# PrismBlade v0.3 有线相机通信技术文档

代号：PrismBlade  
版本：v0.3 draft  
日期：2026-05-21  
目标平台：iOS / iPhone 12 Pro  
运行目标：Xcode Simulator + iPhone 真机  
目标相机：Nikon Z6III  
当前阶段：USB to Lightning 有线相机通信开发，包含 PTP 控制通道和 USB 视频流验证

## 1. 版本定位

PrismBlade v0.3 从 v0.2 的真实像素监看原型，转入真实有线相机通信开发。v0.2 已经完成 `CVPixelBuffer -> MTLTexture -> MTKView` 的图像链路、LUT、伪色、斑马纹和 scope；v0.3 的重点是让底部相机控制条从 Mock 通道升级为可连接 Nikon Z6III 的真实 PTP 控制通道，并在同一条 USB to Lightning 物理连接上验证视频流输入。

本阶段采用“完整开发后真机验证”的策略：在真实相机和手机连接测试之前，先把发现、连接、状态、参数、动作、事件、日志和回放测试能力全部开发到可运行状态。由于硬件行为尚未验证，所有外部依赖必须被隔离在 adapter 和协议层中，不能让 SwiftUI、Metal 或 `MonitorSession` 直接依赖 Nikon、USB、PTP 或 ImageCaptureCore 类型。

v0.3 的核心目标：

- 支持相机发现和连接状态管理。
- 支持 `ImageCaptureCore` 作为首选 iOS 直连适配器。
- 建立独立的 PTP 命令封装、响应解析、事务 ID、超时和错误分类。
- 建立 USB 视频流输入边界，优先验证 Nikon USB live view / PTP 数据通道；如果 iOS 暴露 UVC 设备，再接入 AVFoundation 外接视频输入。
- 建立 Nikon Z6III 参数映射层，把真实能力表转换为现有 `CameraState`。
- 支持 ISO、快门、光圈、白平衡、曝光模式、对焦模式的读写流程。
- 支持拍照、半按、对焦、开始/停止录制等动作命令的统一入口。
- 支持相机事件流：断开、参数变化、电量变化、存储变化、录制状态变化和错误。
- 支持诊断日志、命令 trace、能力表导出和测试回放。
- 保持 Mock transport 可用，保证模拟器和自动化测试不依赖真实硬件。

v0.3 不处理：

- HDMI 采集链路。
- Nikon N-Log 曲线最终校准。
- Wi-Fi、USB-LAN 或任何网络桥接路线。
- App Store 上架合规结论。
- `libgphoto2` 的 iOS 移植。

## 2. 当前基础

现有代码中已经有以下边界：

- `CameraTransport`：相机命令边界，当前由 `MockCameraTransport` 实现。
- `CameraCommandService`：UI 之外的命令校验边界，负责曝光模式锁定规则。
- `CameraState` / `CameraValue`：UI 可消费的相机状态和离散 options 表达。
- `MonitorSession`：主状态容器，协调帧源、相机命令、设置、LUT 和曝光辅助。
- `AppEnvironment`：依赖注入入口，后续可以替换 transport 和 frame source。
- `FrameSource`：画面输入边界，已经和相机控制通道分离。

这些基础保持不废弃。v0.3 的主要工作是扩展控制通道能力，而不是重写监看 UI。

## 3. 设计原则

1. 控制通道和画面通道继续分离。
2. SwiftUI 不直接依赖 `ImageCaptureCore`、USB、PTP、Nikon 私有命令或 `libgphoto2`。
3. `CameraTransport` 的输入输出继续使用 PrismBlade 自有 domain model。
4. 真实相机状态必须以相机读取结果为准，不允许使用本地持久化值覆盖机身实际状态。
5. 参数 options 必须来自能力表或 mapper，UI 不生成相机未声明支持的任意值。
6. 所有命令必须串行化，避免 PTP transaction、机身状态和 UI loading 状态互相踩踏。
7. 所有硬件不确定点必须能通过诊断日志定位。
8. Mock、replay 和真实 transport 必须共享同一套 command service 和 UI。
9. 任何真实相机错误都要能映射为可展示、可测试、可诊断的错误类型。
10. 未验证的相机功能默认可见但受能力表禁用，不能假装成功。
11. 视频流必须走 USB to Lightning 有线连接，不引入网络桥、Wi-Fi 或 USB-LAN 备选路线。
12. 控制通道和视频通道在软件架构上继续分离，即使它们共享同一条 USB 物理连接。

## 4. 架构目标

目标架构：

```text
SwiftUI
  -> MonitorSession
  -> CameraCommandService
  -> CameraTransport
       ├─ MockCameraTransport
       ├─ ReplayCameraTransport
       └─ ImageCaptureCameraTransport
             -> CameraDeviceDiscovery
             -> ImageCaptureCoreCameraClient
             -> PTPClient
             -> NikonZ6IIICapabilityMapper
             -> CameraDiagnosticsRecorder

FrameSource
  ├─ SimulatedFrameSource
  ├─ VideoFileFrameSource
  └─ USBCameraFrameSource
        -> USBVideoStreamProbe
        -> NikonLiveViewStreamClient
        -> ExternalVideoCaptureClient
        -> CameraDiagnosticsRecorder
```

辅助边界：

```text
CameraEventStream
  -> MonitorSession state reconciliation

CameraDiagnosticsStore
  -> Settings / Debug diagnostics export

PTPTraceLog
  -> JSONL replay fixtures
```

### 4.1 `CameraTransport`

现有 `CameraTransport` 需要从“命令接口”升级为“连接 + 命令 + 事件”接口。

建议形态：

```swift
protocol CameraTransport {
    var events: AsyncStream<CameraEvent> { get }

    func connect() async throws
    func disconnect() async
    func currentState() async throws -> CameraState
    func setValue(_ value: String, for parameter: CameraParameter) async throws -> CameraState
    func trigger(_ action: CameraAction) async throws -> CameraState
}
```

如果事件流在第一批实现中会影响现有 Mock 测试，可以先通过 adapter 包装加入，而不是立刻破坏所有调用点。

### 4.2 `CameraDeviceDiscovery`

发现不应塞进 `connect()`。真实 iOS 外接相机会出现以下状态：

- 没有设备。
- 发现多个设备。
- 设备存在但未授权。
- 设备存在但不支持 PTP command。
- 设备存在但能力表不完整。
- 设备断开后重新出现。

建议新增发现层：

```swift
protocol CameraDeviceDiscovery {
    var devices: AsyncStream<[CameraDeviceDescriptor]> { get }

    func start() async
    func stop() async
}
```

`CameraDeviceDescriptor` 只保留 PrismBlade 自有字段：

```swift
struct CameraDeviceDescriptor: Equatable, Identifiable {
    var id: String
    var name: String
    var manufacturer: String?
    var model: String?
    var serialNumber: String?
    var connectionKind: CameraConnectionKind
    var capabilities: Set<CameraConnectionCapability>
}
```

### 4.3 `ImageCaptureCameraTransport`

`ImageCaptureCameraTransport` 是 v0.3 的首选真实 transport。它负责：

- 使用 ImageCaptureCore 发现 `ICCameraDevice`。
- 判断设备 capability 是否支持 PTP command。
- 管理连接生命周期。
- 把 ImageCaptureCore 回调转换为 async/await。
- 把 PTP response 转换为 domain state。
- 把系统错误映射为 `CameraTransportError`。
- 向诊断 recorder 写入 device、command、response 和 error trace。

ImageCaptureCore 类型不得出现在 SwiftUI、`MonitorSession` 或 `CameraCommandService` 中。

### 4.4 `PTPClient`

PTP 层独立于 Nikon mapper 和 ImageCaptureCore adapter。它负责：

- transaction id 分配。
- command packet 构造。
- response packet 解析。
- data phase 输入输出。
- timeout。
- request/response trace。
- PTP response code 到错误类型的映射。

`PTPClient` 不理解 UI 参数，例如 “ISO 400” 或 “f/2.8”。这些值由 Nikon mapper 负责转换。

### 4.5 `USBCameraFrameSource`

`USBCameraFrameSource` 是 v0.3 新增的视频流边界。它只负责把 USB 有线视频流转换为现有 `VideoFrame`，不负责相机参数控制。

候选输入路径：

```text
Nikon USB live view / PTP data channel
  -> NikonLiveViewStreamClient
  -> CVPixelBuffer
  -> VideoFrame

AVFoundation external device, if exposed by iOS on the test device
  -> ExternalVideoCaptureClient
  -> CMSampleBuffer
  -> CVPixelBuffer
  -> VideoFrame
```

本阶段不假设 iPhone 12 Pro + Lightning 一定会暴露 UVC 外接视频设备。Apple 文档当前明确把 AVFoundation external UVC 设备描述为 iPad 外接设备能力；因此 v0.3 必须实现探针和诊断，真机验证后再决定视频流走 Nikon live view 数据通道还是 AVFoundation 外接视频输入。

### 4.6 `NikonZ6IIICapabilityMapper`

Nikon mapper 负责把相机能力表转换为现有 `CameraState`：

```text
Nikon property descriptors
  -> CameraValue(current/options/isWritable)
  -> CameraState
```

它也负责反向映射：

```text
CameraParameter + display value
  -> Nikon property code + encoded value
```

mapper 必须做到：

- 未识别参数不崩溃，标记为不可写或 unsupported。
- 原始 code/value 可进入诊断日志。
- UI 展示值稳定，例如 `1/50`、`f/2.8`、`5600K`。
- 真实 options 顺序贴近相机拨盘或能力表顺序。

### 4.7 `CameraDiagnosticsRecorder`

诊断能力是 v0.3 的核心交付物，不是附属功能。真机测试后期才开始时，日志是定位问题的主要工具。

必须记录：

- app version / build / device model / iOS version。
- transport 类型。
- 发现到的设备 descriptor。
- 连接状态变化。
- 每次 PTP request 的 operation code、parameters、transaction id、payload length。
- 每次 PTP response 的 response code、payload length、耗时。
- 视频流探针结果：是否发现外接视频设备、是否收到 live view 数据、帧率、分辨率、像素格式、掉帧和错误。
- ImageCaptureCore capability。
- Nikon property descriptor 原始摘要。
- domain mapper 输出的 `CameraState` 摘要。
- 错误类型、底层错误、用户可见文案。

日志格式建议使用 JSON Lines，方便复制、比较和生成 replay fixture。

## 5. 用户体验范围

### 5.1 Monitor 主界面

主界面继续显示现有底部相机控制条。真实 transport 接入后，UI 行为应保持：

- 未连接时参数和动作按钮禁用。
- 连接中显示 loading 状态。
- 参数不可写时保留当前值，并展示不可写原因。
- 参数提交中只标记对应 cell。
- 提交失败后恢复提交状态，并展示错误。
- 相机端状态变化时自动刷新当前值。

连接状态文案需要从 `Mock 已连接` 泛化为真实连接：

```text
未连接
搜索中
连接中
已连接
连接中断
连接错误
```

如果保留 Mock，应显示 `Mock 已连接` 或在 debug 区显示 transport 类型，避免误判。

### 5.2 Settings / Debug

Settings 中应新增控制通道调试区：

- Transport 模式：Mock / Real Camera / Replay。
- 设备发现状态。
- 当前设备名称和连接能力。
- 重新扫描。
- 连接 / 断开 / 重连。
- 导出诊断日志。
- 清空诊断日志。
- 复制最近一次错误。
- 复制当前能力表摘要。

这些入口可以先作为开发调试 UI，不作为最终产品体验。

## 6. 状态流

### 6.1 启动

```text
App start
  -> AppEnvironment selects transport mode
  -> MonitorSession starts frame source
  -> CameraDeviceDiscovery starts if real transport is enabled
  -> state.connection = searching
  -> first matching device found
  -> connect
  -> read currentState
  -> state.connection = connected
  -> USBCameraFrameSource probes wired video stream
  -> if video stream is available, replace simulated/video-file frames with real USB frames
```

默认模拟器仍使用 Mock。真机可以通过 launch argument、build flag 或 Settings debug switch 切换真实 transport。

### 6.2 参数写入

```text
User selects value
  -> MonitorSession availability check
  -> mark parameter isSubmitting
  -> CameraCommandService reads latest state
  -> exposure rule check
  -> CameraTransport.setValue
  -> mapper encodes value
  -> PTP set property command
  -> read back affected state
  -> update CameraState
```

写入成功后必须 read back 或等待事件确认。不能只因为 command response 成功就修改 UI 值。

### 6.3 相机端变化

```text
Camera event
  -> CameraEventStream
  -> fetch changed property or currentState
  -> mapper updates CameraState
  -> MonitorSession publishes state
```

如果 ImageCaptureCore 没有提供足够事件，第一版可以使用低频 polling：

```text
connected state
  -> poll selected critical properties every 1-2s
  -> suppress duplicate state updates
```

### 6.4 断线和恢复

断线后：

- 取消未完成命令。
- 结束 submitting 状态。
- `state.connection = interrupted(reason)`。
- 保留最后一次相机状态用于 UI 参考，但所有参数禁用。
- 如果设备重新出现，可以手动或自动重连。

自动重连首版建议保守：

```text
first disconnect: show interrupted
manual reconnect button available
optional debug setting: auto reconnect
```

### 6.5 USB 视频流

视频流启动流程：

```text
connected wired camera
  -> probe AVFoundation external devices
  -> probe Nikon live view / PTP stream support
  -> select first verified USB video path
  -> start USBCameraFrameSource
  -> emit VideoFrame
  -> Metal preview consumes existing frame pipeline
```

视频流失败不应导致 PTP 控制通道断开。UI 可以继续显示相机状态和参数控制，并在 preview 区显示视频流错误。

视频流和控制通道共享物理线缆，但软件状态应独立表达：

```text
camera control connection: connected / failed / interrupted
video stream status: stopped / probing / running / failed
```

## 7. 错误模型

现有 `CameraTransportError` 需要扩展。建议分类：

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

用户文案要短，诊断日志要完整。UI 不需要展示 PTP code，但日志必须保留。

视频流错误建议独立：

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

## 8. 并发模型

真实 transport 应使用 actor 串行化命令：

```swift
actor ImageCaptureCameraTransport: CameraTransport {
    private var connection: CameraConnection?
    private var stateCache: CameraState?
    private var transactionID: UInt32
}
```

规则：

- 同一时间只允许一个 PTP command in flight。
- `disconnect()` 可以取消或标记所有等待命令。
- event/polling 读取不能与用户写入交错破坏状态。
- UI 更新仍由 `MonitorSession` 在 MainActor 进行。
- 长耗时动作必须有 timeout。

默认 timeout：

```text
device discovery warmup: 10s
connect: 10s
read current state: 5s
set parameter: 3s
capture: 15s
focus: 5s
record toggle: 5s
video stream probe: 10s
first video frame: 5s
disconnect: best effort
```

这些值进入配置，而不是散落在实现中。

## 9. 开发切片

### Slice 1：文档和协议骨架

- 新增 v0.3 技术文档和通信规格文档。
- 新增 adapter 命名空间。
- 新增 discovery、event、diagnostics、transport mode 和 video stream status 的 domain model。
- 保持 Mock 行为不变。

完成标准：

- 项目仍可构建。
- 现有相机 Mock 测试仍通过。
- 新类型有基础单元测试。

### Slice 2：诊断和 replay

- 新增 JSONL 诊断 recorder。
- Mock transport 写入同样格式的 command trace。
- Replay transport 可以从 fixture 回放发现、连接、状态和错误。

完成标准：

- 无相机时可以跑完整 debug UI。
- 一段 replay fixture 能驱动底部相机控制条显示真实形态状态。

### Slice 3：ImageCaptureCore discovery

- 接入 `ICDeviceBrowser`。
- 发现 `ICCameraDevice`。
- 读取设备名称、manufacturer、model、serial、capabilities。
- 显示在 Settings debug 区。

完成标准：

- 模拟器编译通过。
- 真机无相机时显示搜索或无设备。
- 发现逻辑不影响 Mock 模式。

### Slice 4：USB 视频流探针

- 探测 AVFoundation 是否暴露外接视频设备。
- 探测 Nikon live view / PTP 数据通道是否可用。
- 记录分辨率、帧率、像素格式、首帧耗时和失败原因。
- 不要求首版完成稳定预览，但必须能把失败原因写进诊断日志。

完成标准：

- 真机无视频流时不影响 PTP 控制。
- 如果系统暴露外接视频设备，可以列出设备和格式。
- 如果 Nikon live view 数据通道返回 payload，可以保存 trace 摘要。

### Slice 5：PTPKit

- PTP operation descriptor。
- transaction id。
- command/response parser。
- timeout wrapper。
- response code mapping。
- 单元测试覆盖 byte encoding/decoding。

完成标准：

- 纯单元测试不依赖 ImageCaptureCore。
- 错误响应、短包、未知 code、timeout 都有测试。

### Slice 6：真实连接和基础状态

- `ImageCaptureCameraTransport.connect()`。
- PTP `GetDeviceInfo`。
- 电量、设备信息、基础 storage 摘要。
- `currentState()` 返回部分真实状态，未支持字段标记不可写或 unknown。

完成标准：

- 真机测试时能导出设备信息和原始响应。
- UI 能从 searching/connecting 进入 connected 或明确失败。

### Slice 7：Nikon capability mapper

- 读取 Nikon/Z6III 可用 property descriptor。
- 映射曝光模式、ISO、快门、光圈、白平衡、对焦模式。
- 生成 `CameraValue.options`。
- 不支持项禁用，并记录原因。

完成标准：

- replay fixture 可验证 mapper 输出。
- UI options 来自 mapper，而不是 Mock 固定数组。

### Slice 8：参数写入

- set ISO。
- set shutter。
- set aperture。
- set white balance。
- set exposure mode。
- set focus mode。
- 写后 read back。

完成标准：

- 每个参数都有成功、unsupported、busy、timeout、rejected 测试。
- UI loading 状态和失败恢复正确。

### Slice 9：动作命令

- capture。
- half press。
- focus。
- toggle record。

完成标准：

- 能区分命令 accepted、device busy、unsupported 和 timeout。
- 动作成功后读取最新状态。

### Slice 10：USB 视频帧源

- `USBCameraFrameSource`。
- Nikon live view stream decoder 或 AVFoundation external capture client。
- 输出 `VideoFrame`。
- 接入现有 Metal preview pipeline。
- 统计帧率、掉帧、首帧耗时。

完成标准：

- 如果真机链路支持视频流，预览画面由 USB 相机帧驱动。
- 如果不支持，UI 显示明确错误，控制通道仍可用。
- 失败日志足以区分“未发现外接视频设备”“Nikon live view 不支持”“帧解码失败”。

### Slice 11：事件同步和断线恢复

- PTP event handler 或 polling。
- 电量/存储/录制/参数变化同步。
- 断线取消命令。
- 手动重连。

完成标准：

- replay 可模拟断线、重连、机身拨盘变化。
- UI 不出现永久 submitting。

## 10. 测试策略

### 10.1 单元测试

必须覆盖：

- PTP packet encoding。
- PTP response parsing。
- transaction id 递增。
- timeout。
- response code 到错误映射。
- Nikon raw value 到 UI display value 映射。
- UI display value 到 Nikon raw value 映射。
- capability 缺失时的 fallback。
- event 到 `CameraState` 更新。
- replay fixture。
- USB video stream status。
- first frame timeout。
- unsupported pixel format。

### 10.2 集成测试

无硬件集成测试：

- Mock transport。
- Replay transport。
- Scripted failing transport。
- Diagnostics recorder。

真机手动测试：

- Z6III `MTP/PTP` 模式。
- Z6III `iPhone` 模式。
- USB-C to Lightning 数据线或 Apple Lightning to USB Camera Adapter + USB-C 数据线。
- iPhone 12 Pro 权限弹窗。
- 首次连接。
- 热插拔。
- 相机休眠。
- USB 视频流是否出现。
- 首帧耗时和稳定帧率。
- PTP 控制和视频流同时运行时是否互相影响。
- 低电量。
- 存储卡无卡 / 满卡。
- 录制中修改参数。
- 相机端拨盘修改参数。

### 10.3 回归测试

v0.3 不应破坏：

- Mock 相机控制。
- 视频文件帧源。
- Metal 预览。
- LUT。
- 伪色 / 斑马。
- Scope。
- 设置持久化。

## 11. 真机测试准备

真机测试前需要准备：

- iPhone 12 Pro，iOS 版本记录。
- Nikon Z6III，固件版本记录。
- USB-C to Lightning 数据线，或 Apple Lightning to USB Camera Adapter + USB-C 数据线。
- 备用数据线。
- 相机电池满电。
- 至少一张可写存储卡。
- Z6III USB 菜单分别测试 `MTP/PTP` 和 `iPhone`。
- 不测试 Wi-Fi、USB-LAN 或网络桥。

测试产物：

- 诊断 JSONL。
- 设备 discovery 摘要。
- capability 摘要。
- USB 视频流探针摘要。
- 视频首帧和帧率记录。
- 每个参数的成功/失败矩阵。
- 错误截图或屏幕录制。
- 手动测试记录。

## 12. 风险和应对

### 12.1 iOS 直连 PTP 能力不足

风险：ImageCaptureCore 可以发现相机，但无法覆盖 Nikon 参数读写或录制控制。

应对：

- 保留 PTP command 能力检测。
- 记录 raw response。
- 不引入网络桥；如果 PTP 控制能力不足，本阶段记录限制并收紧功能范围。

### 12.2 USB to Lightning 视频流不可用

风险：iPhone 12 Pro + Lightning 不暴露 UVC 外接视频设备，且 Nikon live view 不能通过可用 PTP 路径读取。

应对：

- 明确区分控制通道成功和视频流失败。
- 记录 AVFoundation external device discovery 结果。
- 记录 Nikon live view probe 的 request/response。
- 不用网络桥绕过该风险。

### 12.3 Nikon 私有命令不完整

风险：标准 PTP 只能覆盖部分能力，关键参数需要 Nikon 私有 operation/property。

应对：

- mapper 允许 unknown/unsupported。
- 先以读取能力表和日志为目标。
- 用真机 trace 补齐映射。

### 12.4 录制控制不可用

风险：拍照可用，但视频录制 toggle 不支持或需要特殊模式。

应对：

- `CameraAction.toggleRecord` 可返回 `unsupportedOperation`。
- UI 使用能力表禁用 REC，而不是命令失败后才提示。

### 12.5 相机状态异步变化

风险：机身拨盘、菜单、自动曝光和录制状态会改变参数，UI 缓存失真。

应对：

- 事件流优先，polling 兜底。
- 参数写入后 read back。
- command service 每次写入前读取最新状态。

### 12.6 没有硬件时开发盲区

风险：完整开发完成后才上机，可能集中暴露 adapter 级问题。

应对：

- 所有 adapter 响应都可诊断、可回放。
- replay fixture 驱动 UI。
- 未验证 code path 保持小而集中。

## 13. 完成标准

v0.3 控制通道完成标准：

1. Mock 模式完整可用。
2. Replay 模式完整可用。
3. 真机模式可以发现设备或给出明确失败原因。
4. 真实 transport 能进入连接状态或记录完整失败诊断。
5. 能读取并展示基础相机状态。
6. 能基于真实能力表启用/禁用 UI 参数。
7. 支持核心参数读写流程。
8. 支持核心动作命令流程。
9. 支持 USB 视频流探针。
10. 如果真机支持 USB 视频流，能通过 `USBCameraFrameSource` 输出 `VideoFrame`。
11. 如果真机不支持 USB 视频流，能给出明确失败原因且 PTP 控制通道继续可用。
12. 支持断线和重连流程。
13. 每次真机测试都能导出足够定位问题的日志。

## 14. 参考资料

- Apple Developer：ImageCaptureCore  
  https://developer.apple.com/documentation/imagecapturecore
- Apple Developer：`ICCameraDevice.requestSendPTPCommand`  
  https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requestsendptpcommand%28_%3Aoutdata%3Acompletion%3A%29
- Apple Developer：AVFoundation external camera device type  
  https://developer.apple.com/documentation/avfoundation/avcapturedevice/devicetype-swift.struct/external
- Nikon Z6III Reference Guide：USB  
  https://onlinemanual.nikonimglib.com/z6III/en/nwm_usb_data_connection_368.html
- PrismBlade v0.2 总结：`V0.2_SUMMARY.zh-CN.md`
- PrismBlade 原型设计：`PROTOTYPE_DESIGN.md`
- PrismBlade v0.2.3 技术文档：`TECHNICAL_SPEC_v0.2.3.md`
