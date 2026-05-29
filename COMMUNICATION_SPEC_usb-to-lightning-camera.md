# PrismBlade USB to Lightning 相机通信规格

版本：draft  
日期：2026-05-21  
适用阶段：v0.3 camera-communication 分支  
目标相机：Nikon Z6III  
目标平台：iOS / iPhone 12 Pro  
主路线：USB to Lightning 有线连接 + PTP command  
视频路线：同一条 USB to Lightning 连接上的 Nikon live view / PTP 数据通道，或系统暴露时的 AVFoundation 外接视频输入  

## 1. 规格目标

本文档定义 PrismBlade 有线相机通信的边界、消息模型、命令生命周期、视频流探针、错误模型、诊断格式和真机验证矩阵。它服务于 v0.3 的完整 USB to Lightning 通信开发。

本规格覆盖：

- 设备发现。
- 连接和断开。
- 当前状态读取。
- 参数能力表读取。
- 参数写入。
- 动作触发。
- 相机事件同步。
- USB 视频流探针。
- USB 视频帧输入。
- 诊断日志。
- replay 测试。

本规格不覆盖：

- HDMI。
- Wi-Fi、USB-LAN 或网络桥接。
- 文件下载。
- 云同步。
- 厂商 LUT 授权。

## 2. 通信分层

```text
UI layer
  MonitorSession / CameraControlPanel

Domain command layer
  CameraCommandService
  CameraState / CameraValue / CameraParameter / CameraAction

Transport layer
  CameraTransport
  CameraEventStream
  CameraDeviceDiscovery
  USBCameraFrameSource

Adapter layer
  ImageCaptureCameraTransport
  ReplayCameraTransport
  MockCameraTransport
  USBVideoStreamProbe
  NikonLiveViewStreamClient
  ExternalVideoCaptureClient

Protocol layer
  PTPClient
  PTPCommand
  PTPResponse
  NikonZ6IIICapabilityMapper

System / device layer
  ImageCaptureCore
  AVFoundation external capture, if exposed
  Nikon Z6III USB mode
```

分层规则：

1. UI 只调用 domain command layer。
2. domain command layer 不知道 ImageCaptureCore。
3. adapter layer 负责系统 API 生命周期。
4. protocol layer 负责 bytes、codes、transaction 和 mapper。
5. Nikon 私有 code 只出现在 Nikon mapper、Nikon live view stream client 或 Nikon protocol namespace。
6. 不引入 Network Bridge、Wi-Fi 或 USB-LAN 备选路线。

## 3. Transport 模式

### 3.1 Mock

用途：

- 模拟器默认模式。
- UI 开发。
- 回归测试。

特征：

- 不依赖系统外接相机能力。
- 使用固定 `CameraState.mockInitial`。
- 模拟延迟和错误。
- 支持完整控制条交互。

### 3.2 Replay

用途：

- 使用真机诊断日志回放。
- 复现硬件问题。
- 在无相机环境中测试 mapper 和 UI。

特征：

- 从 JSONL fixture 加载 device discovery、state、event、response。
- 不发送真实 PTP。
- 支持 scripted failure。

### 3.3 ImageCaptureCore / USB to Lightning

用途：

- iPhone 通过 USB to Lightning 直连 Nikon Z6III 的首选真实路线。

特征：

- 使用 ImageCaptureCore 发现 `ICCameraDevice`。
- 通过 `ICCameraDevice.requestSendPTPCommand` 发送 PTP command。
- 使用 ImageCaptureCore capability 判断是否支持 PTP command、take picture、battery 等能力。
- 所有系统类型只停留在 adapter 内部。

### 3.4 USB Video

用途：

- 在同一条 USB to Lightning 连接上获得 Nikon Z6III 的实时画面。

特征：

- 先探测 AVFoundation 是否暴露外接视频设备。
- 再探测 Nikon live view / PTP 数据通道是否可用。
- 输出仍使用现有 `VideoFrame`，交给 Metal 预览管线消费。
- 视频流失败不影响 PTP 控制通道继续工作。

v0.3 不使用 Network Bridge。

## 4. 设备发现

### 4.1 输入

发现层不需要用户输入。真实模式启动后自动扫描。

可选配置：

```text
preferredManufacturer: Nikon
preferredModel: Z6III
discoveryTimeout: 10s
allowMultipleDevices: false
```

### 4.2 输出

```swift
struct CameraDeviceDescriptor: Equatable, Identifiable, Codable {
    var id: String
    var name: String
    var manufacturer: String?
    var model: String?
    var serialNumber: String?
    var connectionKind: CameraConnectionKind
    var capabilities: Set<CameraConnectionCapability>
}

enum CameraConnectionKind: String, Codable {
    case mock
    case replay
    case imageCaptureCore
    case unknown
}

enum CameraConnectionCapability: String, Codable {
    case canAcceptPTPCommands
    case canTakePicture
    case canReportBattery
    case canReportStorage
    case canEmitPTPEvents
    case canProbeUSBVideo
    case canExposeExternalVideoDevice
    case canExposeNikonLiveViewData
}
```

### 4.3 发现事件

```swift
enum CameraDiscoveryEvent: Equatable {
    case searching
    case devicesChanged([CameraDeviceDescriptor])
    case selected(CameraDeviceDescriptor)
    case unavailable(reason: String)
    case failed(String)
}
```

### 4.4 选择规则

如果发现多个设备：

1. 优先 manufacturer/model 匹配 Nikon Z6III。
2. 再优先支持 PTP command 的设备。
3. 如果仍有多个，进入 debug 选择，不自动连接。

如果没有设备：

- UI 显示搜索中或未发现设备。
- Mock 模式不受影响。
- 诊断日志记录 discovery timeout。

## 5. 连接状态

### 5.1 Domain 状态

现有 `ConnectionState` 可继续使用，但文案需要泛化。

```swift
enum ConnectionState: Equatable {
    case disconnected
    case searching
    case connecting
    case connected
    case interrupted(String)
    case failed(String)
}
```

### 5.2 状态迁移

```text
disconnected
  -> searching
  -> connecting
  -> connected

connected
  -> interrupted(reason)
  -> connecting
  -> connected

searching / connecting
  -> failed(reason)
  -> disconnected
```

### 5.3 连接流程

```text
start discovery
  -> receive CameraDeviceDescriptor
  -> select device
  -> open adapter connection
  -> verify capabilities
  -> send GetDeviceInfo or equivalent probe
  -> read current state
  -> publish connected
```

连接成功标准：

- 设备 descriptor 有稳定 id。
- adapter 可发送至少一个 probe 或可确认系统 capability。
- `currentState()` 可以返回 domain `CameraState`，即使部分字段不可写。

## 6. PTP 抽象

### 6.1 内部命令模型

PrismBlade 内部不直接在业务层处理 byte array。PTP 层使用结构化命令：

```swift
struct PTPCommand: Equatable, Codable {
    var operationCode: UInt16
    var parameters: [UInt32]
    var transactionID: UInt32
    var dataPhase: PTPDataPhase
}

enum PTPDataPhase: Equatable, Codable {
    case none
    case send(Data)
    case receive
}
```

### 6.2 响应模型

```swift
struct PTPResponse: Equatable, Codable {
    var responseCode: UInt16
    var transactionID: UInt32
    var parameters: [UInt32]
    var data: Data?
    var durationMS: Int
}
```

### 6.3 Trace 模型

```swift
struct PTPTraceEntry: Codable {
    var timestamp: Date
    var direction: PTPTraceDirection
    var operationCode: UInt16?
    var responseCode: UInt16?
    var transactionID: UInt32
    var parameters: [UInt32]
    var payloadLength: Int
    var durationMS: Int?
    var summary: String
}

enum PTPTraceDirection: String, Codable {
    case request
    case response
    case event
    case error
}
```

Trace 默认不记录完整 payload。需要深度调试时可以在 debug setting 中开启 payload hex，避免日志过大。

### 6.4 Byte order

PTP values 按协议使用 little-endian 解析和编码。所有 PTP byte 操作必须集中在 `PTPCodec`，不得在 mapper 中手写 byte offset。

### 6.5 Transaction

规则：

- 每个 command 分配一个递增 transaction id。
- transaction id 从 1 开始。
- 断线重连后 transaction id 可重置。
- response transaction id 必须匹配 request。
- mismatch 记录 `protocolError`。

### 6.6 标准 probe

首选 probe：

```text
GetDeviceInfo
```

如果 ImageCaptureCore 已经抽象了 session 管理，adapter 不应自行假设必须发送 raw `OpenSession`。是否需要显式 session command 由实际真机 trace 验证后决定。

## 7. USB 视频流规格

### 7.1 目标

视频流必须通过 USB to Lightning 有线连接获得，不使用 Wi-Fi、USB-LAN、网络桥或中继服务。

目标输出仍是现有 `VideoFrame`：

```text
USB camera video source
  -> CVPixelBuffer
  -> VideoFrame
  -> Metal preview pipeline
```

### 7.2 探针顺序

视频探针按以下顺序执行：

```text
connected wired camera
  -> query AVFoundation external capture devices
  -> query supported formats if an external device exists
  -> send Nikon live view / PTP probe if no external video device is available
  -> record result in diagnostics
```

探针结果：

```swift
enum USBVideoProbeResult: Equatable, Codable {
    case externalVideoDeviceFound(name: String, formats: [USBVideoFormat])
    case nikonLiveViewDataFound(formatHint: String?)
    case unavailable(reason: String)
    case failed(String)
}
```

### 7.3 输入路径

路径 A：AVFoundation external capture。

```text
AVCaptureDevice external
  -> AVCaptureSession
  -> CMSampleBuffer
  -> CVPixelBuffer
  -> VideoFrame
```

使用条件：

- iOS 在当前硬件上暴露 external capture device。
- 格式可转换为 PrismBlade 支持的 `CVPixelBuffer`。
- 帧率和延迟可接受。

路径 B：Nikon live view / PTP data channel。

```text
PTP live view command/event
  -> payload chunks
  -> frame decoder
  -> CVPixelBuffer
  -> VideoFrame
```

使用条件：

- Nikon Z6III 在当前 USB 模式下允许 live view 数据。
- ImageCaptureCore 允许发送必要 PTP command。
- payload 格式可以被识别和解码。

### 7.4 FrameSource

```swift
final class USBCameraFrameSource: FrameSource {
    var status: FrameSourceStatus { get }
    var format: FrameFormat? { get }

    func start() async throws
    func stop() async
    func frames() -> AsyncStream<VideoFrame>
}
```

`USBCameraFrameSource` 不写相机参数，不触发动作命令。它只消费已经建立的有线设备连接或视频 capture device。

### 7.5 视频状态

```swift
enum USBVideoStreamStatus: Equatable {
    case stopped
    case probing
    case starting
    case running(format: FrameFormat)
    case failed(String)
}
```

控制连接和视频流状态分开：

```text
PTP control connected + video running
PTP control connected + video failed
PTP control failed + video stopped
```

### 7.6 视频错误

```swift
enum USBVideoStreamError: Error, LocalizedError, Equatable {
    case noExternalVideoDevice
    case liveViewUnsupported
    case streamTimeout
    case unsupportedPixelFormat(String)
    case frameDecodeFailed(String)
    case disconnected
    case underlying(String)
}
```

视频流失败不应让 `CameraTransport` 断开。只有物理线缆断开时，两条通道才同时进入 interrupted。

### 7.7 诊断

视频诊断必须记录：

- 是否发现 AVFoundation external device。
- device name。
- supported formats。
- Nikon live view probe command/response 摘要。
- first frame duration。
- frame size。
- pixel format。
- measured frame rate。
- dropped frame count。
- failure reason。

## 8. Nikon 参数映射

### 8.1 Domain 参数

v0.3 首批支持：

```text
exposureMode
iso
shutter
aperture
whiteBalance
focusMode
```

动作：

```text
toggleRecord
capture
halfPress
focus
```

### 8.2 映射职责

Nikon mapper 负责：

- 从 PTP device info 和 property descriptors 中读取支持列表。
- 将 raw property code 映射到 `CameraParameter`。
- 将 raw value 映射到 UI display string。
- 将 UI display string 映射回 raw value。
- 为不可写参数提供 reason。
- 为未知 raw value 生成稳定 fallback display。

### 8.3 Capability 输出

```swift
struct CameraParameterCapability: Equatable, Codable {
    var parameter: CameraParameter
    var current: String
    var options: [String]
    var isWritable: Bool
    var unavailableReason: String?
    var rawPropertyCode: UInt16?
}
```

转换为现有 UI model：

```text
CameraParameterCapability
  -> CameraValue(current/options/isWritable)
```

### 8.4 未支持参数

未支持参数不应导致连接失败。

处理规则：

- `current = "--"` 或保留上次可信值。
- `options = []`。
- `isWritable = false`。
- reason 写明 `相机未报告该参数能力` 或 `当前连接模式不支持该参数`。
- 诊断日志保留 raw descriptor 摘要。

### 8.5 写入确认

参数写入后必须确认：

```text
set property
  -> response OK
  -> read property or read currentState
  -> mapper confirms displayed value
  -> update UI
```

如果 set 成功但 read back 不一致：

- UI 使用 read back 的真实值。
- 显示短提示：`相机已接受命令，但当前值由机身状态决定`。
- 诊断记录 `writeReadbackMismatch`。

## 9. 命令生命周期

### 9.1 通用流程

```text
Domain command
  -> availability check
  -> transport actor queue
  -> mapper encode
  -> PTP request
  -> PTP response
  -> mapper decode
  -> read back state
  -> publish CameraState
  -> diagnostics trace
```

### 9.2 Parameter command

输入：

```swift
parameter: CameraParameter
value: String
```

输出：

```swift
CameraState
```

失败：

- notConnected
- unsupportedValue
- unsupportedOperation
- parameterLockedByExposureMode
- deviceBusy
- commandTimeout
- responseRejected
- mappingFailed
- disconnectedDuringCommand

### 9.3 Action command

输入：

```swift
action: CameraAction
```

输出：

```swift
CameraState
```

动作映射策略：

- `capture` 优先使用系统 tethered capture 能力或标准 PTP capture command。
- `focus` 和 `halfPress` 可能需要 Nikon 私有 command。
- `toggleRecord` 可能需要 Nikon 私有 command 或在某些 USB 模式不可用。

如果动作能力未知：

- UI 可显示按钮但在真实连接后禁用，reason 来自 capability。
- debug 模式可以允许发送 experimental command，但默认关闭。

## 10. 事件通道

### 10.1 Event model

```swift
enum CameraEvent: Equatable {
    case connectionChanged(ConnectionState)
    case stateChanged(CameraState)
    case parameterChanged(CameraParameter, String)
    case recordingChanged(Bool)
    case batteryChanged(Int?)
    case storageChanged(StorageInfo?)
    case videoStreamChanged(USBVideoStreamStatus)
    case deviceBusy(String)
    case warning(String)
    case error(CameraTransportError)
}
```

### 10.2 来源

事件来源优先级：

1. ImageCaptureCore / PTP event handler。
2. explicit read back after command。
3. low-frequency polling。
4. reconnect state refresh。

### 10.3 去重

`MonitorSession` 不应因为同一状态重复刷新造成 UI 抖动。

规则：

- `CameraState` Equatable 相等时不发布。
- polling 更新低于 1Hz 时不显示 loading。
- 只有用户命令触发的写入显示 submitting。

## 11. 错误映射

### 11.1 Transport error

建议错误：

```swift
enum CameraTransportError: Error, LocalizedError, Equatable {
    case notConnected
    case noDeviceFound
    case permissionDenied
    case unsupportedDevice(name: String?)
    case unsupportedCapability(String)
    case unsupportedValue(parameter: CameraParameter, value: String)
    case unsupportedOperation(String)
    case parameterLockedByExposureMode(parameter: CameraParameter, mode: ExposureMode)
    case commandTimeout(operation: String)
    case deviceBusy(operation: String)
    case protocolError(String)
    case responseRejected(code: String)
    case disconnectedDuringCommand
    case mappingFailed(parameter: CameraParameter, rawValue: String)
    case underlying(String)
}
```

### 11.2 UI 文案

UI 文案要求：

- 用户可理解。
- 不出现裸 PTP code。
- 不超过一行短提示。
- 详细信息进入 diagnostics。

示例：

```text
未发现相机
相机未授权
当前连接模式不支持该参数
相机正忙，请稍后重试
命令超时
连接已断开
```

### 11.3 Diagnostics 详情

同一个错误在 diagnostics 中必须包含：

```json
{
  "event": "camera.error",
  "transport": "imageCaptureCore",
  "operation": "setValue.iso",
  "domainError": "commandTimeout",
  "underlyingError": "...",
  "ptpOperationCode": "0x0000",
  "ptpResponseCode": null,
  "transactionID": 42,
  "durationMS": 3000
}
```

如果 PTP code 尚未确认，使用 `null` 或省略字段，不用占位假值。

## 12. 诊断日志

### 12.1 格式

日志使用 JSON Lines：

```text
one JSON object per line
UTF-8
append-only during session
```

### 12.2 Session header

每次 App 启动写入：

```json
{
  "event": "session.start",
  "timestamp": "2026-05-19T12:00:00Z",
  "appVersion": "0.3",
  "build": "debug",
  "deviceModel": "iPhone 12 Pro",
  "systemVersion": "iOS 17.x",
  "transportMode": "imageCaptureCore"
}
```

### 12.3 Discovery

```json
{
  "event": "camera.discovery.devicesChanged",
  "devices": [
    {
      "id": "...",
      "name": "Nikon Z6III",
      "manufacturer": "Nikon",
      "model": "Z6III",
      "connectionKind": "imageCaptureCore",
      "capabilities": ["canAcceptPTPCommands", "canTakePicture"]
    }
  ]
}
```

### 12.4 Command

```json
{
  "event": "ptp.request",
  "operation": "GetDeviceInfo",
  "operationCode": "0x1001",
  "transactionID": 1,
  "parameters": [],
  "payloadLength": 0
}
```

### 12.5 Response

```json
{
  "event": "ptp.response",
  "operation": "GetDeviceInfo",
  "responseCode": "0x2001",
  "transactionID": 1,
  "payloadLength": 128,
  "durationMS": 42
}
```

### 12.6 State summary

```json
{
  "event": "camera.state",
  "exposureMode": "M",
  "iso": "400",
  "shutter": "1/50",
  "aperture": "f/2.8",
  "whiteBalance": "5600K",
  "focusMode": "AF-S",
  "isRecording": false,
  "batteryLevel": 82
}
```

### 12.7 Video stream

```json
{
  "event": "usbVideo.probe",
  "externalVideoDeviceFound": false,
  "nikonLiveViewDataFound": false,
  "status": "failed",
  "reason": "noExternalVideoDevice",
  "durationMS": 10000
}
```

### 12.8 Privacy

默认日志不记录：

- 用户照片文件名。
- 文件路径。
- 完整媒体目录。
- 完整 payload。

可以记录：

- 设备 model。
- capability 摘要。
- command code。
- response code。
- 参数 display value。

## 13. Replay 规格

Replay fixture 使用同样 JSONL 格式。Replay transport 读取事件并按时间或测试脚本驱动。

### 13.1 Replay modes

```text
immediate: 忽略原始时间戳，尽快回放
timed: 按原始 timestamp 间隔回放
scripted: 测试代码手动推进下一条事件
```

### 13.2 Replay 支持事件

- session.start
- camera.discovery.devicesChanged
- camera.connection
- camera.state
- camera.event
- camera.error
- usbVideo.probe
- usbVideo.frameSource
- ptp.request
- ptp.response

### 13.3 Replay 用途

- 无相机开发 UI。
- 复现真机 bug。
- mapper 回归测试。
- 断线场景测试。
- USB 视频流探针测试。
- device busy 和 timeout 测试。

## 14. 真机测试矩阵

### 14.1 USB 模式

需要分别测试：

```text
Z6III USB = MTP/PTP
Z6III USB = iPhone
```

不测试 `USB-LAN`、Wi-Fi 或网络桥。

### 14.2 连接矩阵

```text
冷启动后连接相机
App 运行中插入相机
连接后拔线
拔线后重新插入
相机休眠后唤醒
切换 USB 模式后重新连接
换线后连接
PTP 控制连接成功但视频流失败
视频流运行中发送 PTP 参数命令
视频流运行中拔线
```

### 14.3 视频矩阵

每种 USB 模式记录：

```text
是否发现 AVFoundation external device
是否发现 Nikon live view / PTP 数据
是否能启动 USBCameraFrameSource
首帧耗时
分辨率
帧率
像素格式
掉帧
视频失败时 PTP 控制是否仍可用
```

### 14.4 参数矩阵

每个参数记录：

```text
是否能读取当前值
是否能读取 options
是否可写
写入支持值是否成功
写入后 read back 是否一致
机身端修改后 App 是否同步
录制中是否可写
Auto/P/A/S/M 下是否可写
```

参数：

```text
exposureMode
iso
shutter
aperture
whiteBalance
focusMode
```

### 14.5 动作矩阵

动作：

```text
capture
halfPress
focus
toggleRecord
```

每个动作记录：

```text
是否支持
是否成功
耗时
失败 code
失败文案
动作后状态是否刷新
```

### 14.6 异常矩阵

```text
无存储卡
存储卡满
电量低
相机菜单打开
相机正在写卡
相机正在录制
镜头切到 MF
相机端拨盘改变参数
App 发送命令时拔线
```

## 15. 兼容策略

### 15.1 参数缺失

如果真实相机不报告某参数：

- UI 禁用对应 cell。
- 显示当前值为 `--` 或最后可信值。
- reason 说明能力缺失。
- 诊断记录 raw capability。

### 15.2 参数只读

如果参数可读不可写：

- UI 显示当前值。
- 禁用调整器。
- reason 使用 `当前连接模式下不可写`。

### 15.3 参数被模式锁定

继续使用 `CameraExposureRules` 作为业务规则层。但真实相机能力优先：

```text
not writable by camera capability
  -> disabled
else locked by exposure mode rule
  -> disabled
else enabled
```

### 15.4 命令实验开关

未确认的 Nikon 私有 command 不应默认在产品 UI 中启用。

Debug 可以加：

```text
Enable experimental Nikon commands
```

打开后才允许发送实验动作，并在日志中标记：

```json
{ "experimental": true }
```

## 16. 与现有代码的关系

### 16.1 保持稳定

应尽量保持：

- `CameraParameter`
- `CameraAction`
- `CameraState`
- `CameraValue`
- `CameraCommandService`
- `MonitorSession.cameraValue(for:)`
- `MonitorSession.availability(for:)`
- Metal preview pipeline 的 `VideoFrame` 输入语义

### 16.2 需要调整

可能需要调整：

- `CameraTransport` 增加 event stream。
- `CameraTransportError` 增加真实通信错误。
- `ConnectionState.title` 去掉固定 Mock 文案。
- `AppEnvironment` 增加 transport mode 选择。
- `AppEnvironment` 增加 USB camera frame source 选择。
- 新增 `USBCameraFrameSource` 和 USB video stream status。
- Settings 增加 debug diagnostics 区。
- Tests 增加 replay、PTP、mapper、diagnostics、USB video probe。

### 16.3 不应调整

v0.3 有线通信不应改动：

- Metal render pipeline。
- LUT parser / repository。
- Scope compute。
- VideoFileFrameSource 行为，除非只是共享 `FrameSource` helper。
- FalseColor / Zebra shader 语义。

## 17. 验收标准

通信规格验收标准：

1. 任意 transport 都实现相同 domain 接口。
2. 真机模式失败时能给出明确 domain error。
3. 每个 command 都有 trace。
4. 每个状态变化都能进入 replay。
5. 参数 options 不由 UI 硬编码生成。
6. 写入后必须 read back 或有事件确认。
7. 断线不会留下永久 submitting 状态。
8. Mock 模式和 replay 模式可在无硬件下覆盖主要 UI。
9. 真机测试矩阵能用日志复盘。
10. USB 视频流通过 `USBCameraFrameSource` 输出 `VideoFrame`。
11. 视频流失败不会导致 PTP 控制通道不可用。
12. 不存在 Network Bridge、Wi-Fi 或 USB-LAN 路线。

## 18. 参考资料

- Apple Developer：ImageCaptureCore  
  https://developer.apple.com/documentation/imagecapturecore
- Apple Developer：`ICCameraDevice.requestSendPTPCommand`  
  https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requestsendptpcommand%28_%3Aoutdata%3Acompletion%3A%29
- Apple Developer：AVFoundation external camera device type  
  https://developer.apple.com/documentation/avfoundation/avcapturedevice/devicetype-swift.struct/external
- Nikon Z6III Reference Guide：USB  
  https://onlinemanual.nikonimglib.com/z6III/en/nwm_usb_data_connection_368.html
