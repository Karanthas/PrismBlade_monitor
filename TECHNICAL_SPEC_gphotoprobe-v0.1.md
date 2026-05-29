# PrismBlade GPhotoProbe v0.1 技术文档

代号：GPhotoProbe  
版本：v0.1 draft  
日期：2026-05-21  
目标平台：iPhone 12 Pro 真机优先，Simulator 仅用于 UI/日志开发  
目标相机：Nikon Z6III  
物理连接：USB to Lightning  
实验目标：验证 iPhone App 是否能在 USB to Lightning 有线连接上实现 libgphoto2/gphoto2 风格的相机访问、配置、拍摄、事件、文件和预览能力  
归属关系：PrismBlade 通信可行性实验，不属于 v0.3 功能版本

## 1. 代号说明

本实验代号为 `GPhotoProbe`。

命名含义：

- `GPhoto`：强调以 `gphoto2` / `libgphoto2` 的功能面作为目标参照，而不是只测试几条 PTP 命令。
- `Probe`：强调探针和诊断，不预设方案一定成立。

`GPhotoProbe` 是一个独立实验包。它的目标不是做完整监看 App，也不是把 `libgphoto2` C 库直接塞进 PrismBlade 主 App，而是用最小但严谨的真机实验判断：我们能否在 iOS 公开 API 和 USB to Lightning 约束下，复刻 `gphoto2` 常用命令和 `libgphoto2` 后端能力。

本实验的目标功能参照包括：

```text
gphoto2 --auto-detect
gphoto2 --summary
gphoto2 --abilities
gphoto2 --list-config
gphoto2 --get-config name
gphoto2 --set-config name=value
gphoto2 --capture-image
gphoto2 --capture-image-and-download
gphoto2 --capture-preview
gphoto2 --capture-movie
gphoto2 --wait-event
gphoto2 --list-files
gphoto2 --get-file
```

需要判断的问题：

1. iPhone 12 Pro + USB to Lightning 是否能发现 Nikon Z6III。
2. ImageCaptureCore 是否能暴露 `ICCameraDevice`。
3. ImageCaptureCore 是否允许发送 PTP command。
4. 是否能建立 `libgphoto2` 风格的 abilities 和 config tree。
5. 是否能完成 list/get/set config。
6. 是否能触发拍照、拍照并下载、事件等待和文件访问。
7. 是否能获得 preview/movie/live view 数据，作为 PrismBlade 后续监看输入。
8. PTP 控制和 USB 视频/preview 能否在同一物理连接、同一相机 USB 模式下共存。
9. 如果失败，失败发生在物理层、iOS API 层、相机 USB 模式层、PTP 协议层、gphoto 能力映射层、文件访问层、视频输入层，还是并发共存层。

## 2. libgphoto2 功能解释

`libgphoto2` 是相机访问和控制后端库，不是 GUI 应用。它支持 USB PTP/MTP 相机，未知 PTP 相机通常可以作为 generic PTP camera 工作。`gphoto2` 是它的命令行前端，提供自动发现、配置读写、拍摄、下载、事件等待、preview/movie 等能力。

GPhotoProbe 不把“直接移植完整 libgphoto2”作为第一步。第一步目标是做 **功能等价性探针**：

```text
gphoto2 command surface
  -> GPhotoProbe command model
  -> ImageCaptureCore / PTP / AVFoundation probes
  -> Nikon Z6III result matrix
```

如果探针证明 iOS 公开 API 足够覆盖核心能力，后续可以实现 Swift 原生 `GPhotoKit`。如果探针证明 ImageCaptureCore 无法覆盖关键 PTP/USB 能力，再评估是否需要研究 `libgphoto2` 源码中的 ptp2/camlib 行为，但仍不在本实验中直接移植 C 库。

## 3. 实验边界

### 3.1 包含

GPhotoProbe 包含：

- 独立 iOS App target。
- ImageCaptureCore 设备发现探针。
- PTP 最小命令探针。
- `gphoto2` 命令面映射表。
- `libgphoto2` 风格 camera abilities 探针。
- `libgphoto2` 风格 config tree 探针。
- list/get/set config 探针。
- capture-image 探针。
- capture-image-and-download 探针。
- wait-event 探针。
- list-files / get-file 只读文件访问探针。
- capture-preview / capture-movie 探针。
- AVFoundation 外接视频设备探针。
- Nikon live view / PTP 数据通道实验探针。
- 控制与视频共存实验。
- 桌面 `gphoto2` baseline 日志导入和对比。
- JSONL 诊断日志。
- App 内日志查看。
- 一键导出诊断日志。
- 可重复执行的测试步骤 UI。

### 3.2 不包含

GPhotoProbe 不包含：

- PrismBlade 主监看 UI。
- LUT、伪色、斑马纹、scope。
- 完整产品化 Nikon 参数控制 UI。
- 完整产品化 live view 解码链路。
- 删除相机文件。
- 格式化存储卡。
- 修改相机日期、版权信息、owner name 等持久元数据。
- Wi-Fi。
- USB-LAN。
- 网络桥接。
- 直接移植完整 `libgphoto2` C 库。
- App Store 上架工作。

## 4. 项目隔离方式

建议在现有 Xcode project 中新增独立 target：

```text
Target: GPhotoProbe
Product: iOS App
Bundle ID: com.chronus.PrismBlade.GPhotoProbe
Scheme: GPhotoProbe
```

目录建议：

```text
PrismBladeLabs/
  GPhotoProbe/
    GPhotoProbeApp.swift
    GPhotoProbeScreen.swift
    GPhotoProbeViewModel.swift
    ProbeRunState.swift
    ProbeResultModels.swift
    GPhotoCommandModels.swift
    GPhotoCapabilityMatrix.swift
    GPhotoBaselineImporter.swift
    ImageCaptureDeviceProbe.swift
    PTPCommandProbe.swift
    GPhotoAbilitiesProbe.swift
    GPhotoConfigTreeProbe.swift
    GPhotoCaptureProbe.swift
    GPhotoFileAccessProbe.swift
    GPhotoEventProbe.swift
    USBVideoDeviceProbe.swift
    NikonLiveViewProbe.swift
    CoexistenceProbe.swift
    ProbeLogger.swift
    ProbeLogExporter.swift
    ProbePermissions.swift
```

隔离原则：

1. GPhotoProbe 不引用 `MonitorSession`。
2. GPhotoProbe 不修改 PrismBlade 主 App 生命周期。
3. GPhotoProbe 可以复用纯 domain 类型，但首版建议自带最小 model，避免污染主工程。
4. 所有实验 API 使用 adapter 包装，便于后续把确认可行的部分迁回 PrismBlade。
5. 实验失败不得影响主 App 构建。
6. 所有可能改变相机状态的操作默认禁用，必须在 UI 中显式启用。

## 5. 实验 App 功能

### 5.1 主屏结构

GPhotoProbe 主屏分为六块：

```text
Setup
  USB mode note
  cable / adapter note
  desktop gphoto2 baseline import

Discovery
  Run auto-detect equivalent
  Run abilities equivalent
  Run PTP basic probe

Config
  Run list-config equivalent
  Run get-config batch
  Run safe set-config experiment

Capture
  Run capture-image
  Run capture-image-and-download
  Run wait-event
  Run file list/get

Preview / Movie
  Run capture-preview
  Run capture-movie
  Run AVFoundation external video probe
  Run coexistence probe

Diagnostics
  Recent events
  Export JSONL
  Clear logs
```

UI 目标：

- 每个探针都可单独运行。
- 每个探针有明确状态：idle / running / passed / failed / inconclusive。
- 每个失败都有用户可读原因和日志事件 ID。
- 每个探针都映射到一个或多个 gphoto2 命令。
- 结果不做过度解释，最终判断依赖导出日志。

### 5.2 实验运行状态

```swift
enum ProbeStatus: String, Codable, Equatable {
    case idle
    case running
    case passed
    case failed
    case inconclusive
}

struct ProbeRunState: Codable, Equatable {
    var id: UUID
    var startedAt: Date
    var finishedAt: Date?
    var status: ProbeStatus
    var summary: String
    var failureReason: String?
}
```

### 5.3 gphoto2 命令映射

```swift
enum GPhotoCommand: String, Codable, CaseIterable {
    case autoDetect
    case summary
    case abilities
    case listConfig
    case getConfig
    case setConfig
    case captureImage
    case captureImageAndDownload
    case capturePreview
    case captureMovie
    case waitEvent
    case listFiles
    case getFile
}

struct GPhotoCommandResult: Codable, Equatable {
    var command: GPhotoCommand
    var status: ProbeStatus
    var supportedByIOSAPI: Bool
    var supportedByCamera: Bool?
    var requiresExperimentalVendorCommand: Bool
    var summary: String
    var evidenceEventIDs: [String]
}
```

## 6. 探针设计

### 6.1 Physical Setup Probe

目的：记录本次测试环境，避免日志不可复现。

输入由用户在 UI 中选择或填写：

```text
iPhone model
iOS version
Nikon model
Nikon firmware
Camera USB mode: MTP/PTP / iPhone / USB streaming / unknown
Cable or adapter: USB-C to Lightning / Lightning to USB Camera Adapter / other
Power state
Card state
Lens state
```

输出：

```json
{
  "event": "setup.snapshot",
  "cameraUSBMode": "MTP/PTP",
  "cable": "USB-C to Lightning",
  "iphoneModel": "iPhone 12 Pro",
  "iosVersion": "..."
}
```

判定：

- 该探针不判定通过/失败，只作为每次 run 的环境 header。

### 6.2 Desktop gphoto2 Baseline Probe

目的：在桌面环境中建立同一台 Nikon Z6III 的 `gphoto2` 参考行为，作为 iPhone 侧 GPhotoProbe 的对照。

前置条件：

- 使用 Mac 或 Linux 通过 USB-C 连接 Nikon Z6III。
- 安装当前稳定版 `gphoto2` / `libgphoto2`。
- 相机 USB 模式与 iPhone 测试一致，至少覆盖 `MTP/PTP`。

建议桌面命令：

```text
gphoto2 --debug --debug-logfile=gphoto-autodetect.log --auto-detect
gphoto2 --debug --debug-logfile=gphoto-summary.log --summary
gphoto2 --debug --debug-logfile=gphoto-abilities.log --abilities
gphoto2 --debug --debug-logfile=gphoto-list-config.log --list-config
gphoto2 --debug --debug-logfile=gphoto-get-config-all.log --get-config capturetarget
gphoto2 --debug --debug-logfile=gphoto-capture-preview.log --capture-preview
gphoto2 --debug --debug-logfile=gphoto-wait-event.log --wait-event=5s
gphoto2 --debug --debug-logfile=gphoto-list-files.log --list-files
```

通过：

- 能生成桌面 baseline 日志。
- 能提取相机 model、driver、port、abilities、config keys、preview/capture 支持情况。

失败：

- 桌面 gphoto2 也无法发现或控制 Z6III。

意义：

- 如果桌面 gphoto2 可用但 iPhone 不可用，问题更可能在 iOS USB/API 边界。
- 如果桌面 gphoto2 也不可用，问题更可能在相机模式、线材、相机固件或 libgphoto2 支持状态。

需要记录：

```json
{
  "event": "gphoto.baseline",
  "source": "desktop",
  "command": "gphoto2 --list-config",
  "logImported": true,
  "detectedModel": "Nikon Z6III",
  "configKeyCount": 42,
  "supportsCapturePreview": true
}
```

### 6.3 ImageCapture Device Probe

目的：判断 iOS 是否通过 ImageCaptureCore 发现 Nikon Z6III。

步骤：

1. 启动 `ICDeviceBrowser`。
2. 设置 camera device browser delegate。
3. 等待 discovery timeout，默认 10 秒。
4. 记录所有发现的 camera device。
5. 记录 device name、manufacturer、model、serial、capabilities。

通过：

- 发现至少一个 `ICCameraDevice`。
- 设备名称或 manufacturer/model 指向 Nikon/Z6III，或用户可手动选择目标设备。

失败：

- timeout 后无任何 camera device。

不确定：

- 发现设备但 manufacturer/model 缺失。
- 发现多个设备且无法自动确认目标。

需要记录：

```json
{
  "event": "imageCapture.discovery",
  "devices": [
    {
      "name": "...",
      "manufacturer": "...",
      "model": "...",
      "serialNumber": "...",
      "capabilities": ["..."]
    }
  ],
  "durationMS": 10000
}
```

### 6.4 PTP Capability Probe

目的：判断 ImageCaptureCore 是否允许向相机发送 PTP command。

前置条件：

- ImageCapture Device Probe 至少发现一个 camera device。

步骤：

1. 读取 `ICCameraDevice.capabilities`。
2. 检查是否包含 `cameraDeviceCanAcceptPTPCommands`。
3. 如果 capability 存在，尝试发送最小 PTP command。
4. 记录 completion error、response data、duration。

首选命令：

```text
GetDeviceInfo
```

通过：

- capability 存在。
- `GetDeviceInfo` 返回成功 response。

失败：

- capability 不存在。
- request API 返回 error。
- response code 表示 rejected / busy / unsupported。
- timeout。

不确定：

- capability 存在，但 command 返回无法解析 response。

需要记录：

```json
{
  "event": "ptp.command",
  "operation": "GetDeviceInfo",
  "operationCode": "0x1001",
  "transactionID": 1,
  "parameters": [],
  "responseCode": "0x2001",
  "payloadLength": 128,
  "durationMS": 42,
  "error": null
}
```

### 6.5 GPhoto Abilities Probe

目的：实现 `gphoto2 --abilities` 的 iPhone 侧等价探针，判断当前连接能暴露哪些后端能力。

输入：

- ImageCaptureCore discovery result。
- PTP `GetDeviceInfo` result。
- AVFoundation external video discovery result。
- 可选桌面 gphoto2 baseline。

输出能力矩阵：

```text
autoDetect
summary
abilities
listConfig
getConfig
setConfig
captureImage
captureImageAndDownload
capturePreview
captureMovie
waitEvent
listFiles
getFile
```

通过：

- 能给每个目标命令输出 supported / unsupported / unknown。
- 每个结论都有证据 event ID。

失败：

- 无法建立基础 device info 或 capability matrix。

需要记录：

```json
{
  "event": "gphoto.abilities",
  "autoDetect": "supported",
  "listConfig": "supported",
  "capturePreview": "unknown",
  "captureMovie": "unsupported",
  "evidenceEventIDs": ["..."]
}
```

### 6.6 GPhoto Config Tree Probe

目的：实现 `--list-config`、`--get-config`、`--set-config` 的等价探针。

步骤：

1. 读取 PTP supported device properties。
2. 对每个 property 执行 descriptor 读取。
3. 生成 gphoto 风格 config key。
4. 对只读参数执行 get。
5. 对明确 writable 且低风险的参数提供 set 实验。

首批 config 映射候选：

```text
/main/capturesettings/iso
/main/capturesettings/shutterspeed
/main/capturesettings/aperture
/main/imgsettings/whitebalance
/main/capturesettings/exposuremode
/main/actions/autofocusdrive
/main/actions/movie
/main/settings/capturetarget
/main/settings/liveviewsize
```

低风险 set-config 白名单：

```text
iso
whitebalance
capturetarget, readback only until confirmed
liveviewsize, readback only until confirmed
```

默认禁止：

```text
date/time
ownername
copyright
format
delete
reset
firmware
```

通过：

- 能列出 config keys。
- 每个 key 能返回 type、current、choices、readonly/writable。
- 白名单 set-config 能写后 readback。

失败：

- 无法读取 property descriptor。
- config key 与桌面 baseline 完全无法对应。
- 写入后 readback 不一致。

### 6.7 GPhoto Capture Probe

目的：实现 `--capture-image` 和 `--capture-image-and-download` 的等价探针。

步骤：

1. 判断相机是否支持 capture。
2. 判断 capture target：card / memory / sdram 是否可用。
3. 执行低风险 capture-image。
4. 等待 event。
5. 如果有新增文件，执行只读下载。
6. 记录文件名、大小、MIME/type、耗时。

通过：

- capture command 被接受。
- wait-event 收到 capture complete 或 object added。
- 可在相机文件系统中找到新增文件。
- `capture-image-and-download` 能下载到 app sandbox。

失败：

- capture unsupported。
- device busy。
- no card / card full。
- capture 成功但事件不可见且无法定位新增文件。

安全规则：

- 不删除相机文件。
- 下载文件保存在 app sandbox，并记录路径和大小。
- capture-image-and-download 只在用户显式确认后运行。

### 6.8 GPhoto File Access Probe

目的：实现 `--list-files` 和 `--get-file` 的等价探针。

步骤：

1. 枚举 storage。
2. 枚举 folder。
3. 列出文件。
4. 读取一个用户选择的小文件或最近 capture 产生的文件。
5. 校验下载 size 和 checksum。

通过：

- 能列出至少一个 storage 或 folder。
- 能读取文件 metadata。
- 能下载文件到 app sandbox。

失败：

- ImageCaptureCore 只允许系统照片导入，无法按 PTP 文件树访问。
- PTP object handles 不可用。
- 下载中断或 size mismatch。

### 6.9 GPhoto Preview / Movie Probe

目的：实现 `--capture-preview` 和 `--capture-movie` 的等价探针，判断能否获得 PrismBlade 需要的监看输入。

路径 A：gphoto 风格 preview/movie。

```text
PTP vendor/liveview command
  -> preview JPEG / MJPEG / frame payload
  -> decode to CVPixelBuffer
```

路径 B：系统 UVC 外接视频。

```text
AVFoundation external video
  -> CMSampleBuffer
  -> CVPixelBuffer
```

通过：

- preview 单帧可获得。
- 或 movie/continuous preview 可以持续 10 秒。
- 可以估算 frame rate、resolution、decode cost。

失败：

- 没有 live view command。
- 有 payload 但格式未知。
- UVC external device 不可见。

### 6.10 PTP Event Probe

目的：判断 ImageCaptureCore 是否能收到 PTP event 或设备状态变化。

步骤：

1. 在 camera device 上设置 event handler。
2. 引导用户在相机端执行低风险动作，例如半按、切换拨盘、打开/关闭菜单。
3. 等待 15 秒。
4. 记录收到的 event 数量和摘要。

通过：

- 收到至少一个可识别事件。

失败：

- 没有事件。

不确定：

- 收到事件但无法解析类型。

意义：

- 如果 event 可用，后续 PrismBlade 可以做实时状态同步。
- 如果 event 不可用，后续需要 polling。

### 6.11 AVFoundation External Video Probe

目的：判断 iOS 是否把 Nikon Z6III 暴露为外接视频 capture device。

步骤：

1. 请求 camera permission。
2. 枚举 `AVCaptureDevice.DiscoverySession`。
3. 查询 `.external`、`.externalUnknown` 或当前 SDK 可用的外接设备类型。
4. 记录所有 capture device。
5. 对外接设备读取 formats。
6. 尝试创建 `AVCaptureSession`。
7. 等待首个 `CMSampleBuffer`，默认 timeout 5 秒。

通过：

- 发现外接视频设备。
- 能启动 capture session。
- 能收到至少一个 sample buffer。
- 能取到 `CVPixelBuffer`。

失败：

- 没有外接视频设备。
- 有设备但无法启动 session。
- 首帧 timeout。
- sample buffer 没有 pixel buffer。

不确定：

- 有设备和格式，但启动 session 后收到系统中断。

需要记录：

```json
{
  "event": "avfoundation.externalVideo",
  "devices": [
    {
      "localizedName": "...",
      "uniqueID": "...",
      "formats": [
        {
          "width": 1920,
          "height": 1080,
          "maxFrameRate": 60,
          "pixelFormat": "..."
        }
      ]
    }
  ],
  "firstFrameMS": 832,
  "result": "passed"
}
```

### 6.12 Nikon Live View / PTP Data Probe

目的：判断是否能通过 PTP 或 ImageCaptureCore 暴露的数据通道获得 Nikon live view 数据。

前置条件：

- PTP Capability Probe 成功。

约束：

- 不默认发送未知 vendor-specific 写命令。
- 只发送明确低风险的读命令或 debug-gated 实验命令。
- 所有实验 command 必须在 UI 中显式标注 experimental。

步骤：

1. 读取 device info。
2. 读取 supported operation codes。
3. 读取 supported event codes。
4. 读取 supported device properties。
5. 查找可能与 live view、movie、preview、vendor extension 相关的 capability。
6. 如果需要发送 vendor-specific live view command，必须通过 debug 开关启用。
7. 记录 response code、payload length 和 payload 摘要。

通过：

- 能获得持续 payload 或明确 live view frame 数据。

失败：

- 没有相关 operation/property。
- command unsupported。
- command rejected。
- timeout。

不确定：

- 有 payload 但格式未知。

需要记录：

```json
{
  "event": "nikon.liveViewProbe",
  "operationCode": "0x....",
  "responseCode": "0x....",
  "payloadLength": 4096,
  "payloadSignature": "...",
  "experimental": true,
  "result": "inconclusive"
}
```

### 6.13 Coexistence Probe

目的：判断同一 USB to Lightning 连接下，PTP 控制和 USB 视频流能否共存。

测试组合：

```text
A. PTP idle -> start video
B. video running -> send PTP GetDeviceInfo
C. video running -> read one low-risk property
D. video running -> low-risk write, disabled by default
E. PTP command loop -> start video
```

通过：

- 视频运行时 PTP 读命令仍成功。
- PTP 命令执行时视频不明显断流。

失败：

- 启动视频后 ImageCaptureCore 设备消失。
- 启动视频后 PTP capability 消失。
- PTP 命令 timeout。
- 视频 session 被中断。

不确定：

- 命令偶发成功，但延迟和掉帧明显。

需要记录：

```json
{
  "event": "coexistence.probe",
  "case": "videoRunningThenPTPGetDeviceInfo",
  "videoStatusBefore": "running",
  "ptpResult": "passed",
  "videoStatusAfter": "running",
  "droppedFramesDuringCommand": 2,
  "ptpDurationMS": 76,
  "result": "passed"
}
```

## 7. 问题定位方法

### 7.1 完全发现不到相机

可能原因：

- USB to Lightning 线材或转接器不支持数据。
- 相机 USB 模式不对。
- iOS 不枚举该设备。
- 相机未开机或休眠。
- Lightning 供电或握手失败。

定位方法：

1. 切换 Z6III USB 模式：`MTP/PTP`、`iPhone`、`USB streaming`。
2. 更换线材或转接器。
3. 记录 ImageCaptureCore discovery 是否为空。
4. 记录 AVFoundation capture device list 是否变化。
5. 在 iOS 照片导入或系统层面观察相机是否被识别。

判定：

- ImageCaptureCore 和 AVFoundation 都完全无设备，优先判断为物理层、线材、模式或 iOS 枚举问题。

### 7.2 ImageCaptureCore 发现相机，但 PTP 不可用

可能原因：

- capability 不包含 PTP command。
- 当前 USB 模式不允许 PTP。
- ImageCaptureCore 权限或 API 限制。
- 相机忙。

定位方法：

1. 记录 `ICCameraDevice.capabilities`。
2. 检查是否有 `cameraDeviceCanAcceptPTPCommands`。
3. 发送 `GetDeviceInfo`。
4. 记录 response code 和 completion error。
5. 切换相机 USB 模式后重复。

判定：

- discovery 成功但 capability 缺失，说明 iOS 能看到相机但不能发 PTP。
- capability 存在但 `GetDeviceInfo` 失败，进入协议或相机状态问题。

### 7.3 PTP 基础命令成功，但 gphoto config 失败

可能原因：

- Nikon vendor-specific property 未映射。
- 参数在当前曝光模式、照片/视频模式或菜单状态下不可写。
- 写入值编码错误。
- 写后需要 readback 或等待事件。

定位方法：

1. 先读取 supported properties。
2. 对每个 property 读取 descriptor。
3. 只对明确 writable 的 property 做写入。
4. 写入后 readback。
5. 记录 raw value 和 display value 映射。

判定：

- descriptor 表示 readonly，则 UI 后续必须禁用。
- set 成功但 readback 不一致，则以相机状态为准。

### 7.4 gphoto capture / file 访问失败

可能原因：

- 相机当前模式不支持 tethered capture。
- capture target 不可写。
- 存储卡无卡或满卡。
- ImageCaptureCore 不暴露 PTP object handle 或文件树。
- capture 成功但事件不可见。

定位方法：

1. 对照桌面 `gphoto2 --capture-image --wait-event=5s --list-files`。
2. 在 iPhone 侧记录 capture response、wait-event、object list。
3. 先只做 capture-image，不下载。
4. 再用只读 list-files 检查新增文件。
5. 最后做 get-file 到 app sandbox。

判定：

- 桌面可 capture/download、iPhone 不可，优先判断为 iOS API 或 PTP object access 限制。
- capture 可用但 download 不可，后续 PrismBlade 可只做控制，不承诺机内文件下载。

### 7.5 AVFoundation 找不到外接视频

可能原因：

- iPhone 12 Pro + Lightning 不暴露 UVC external device。
- Z6III 当前不是 USB streaming 模式。
- 相机输出模式不是 iOS 支持的 UVC/MJPEG 格式。
- 权限未授权。

定位方法：

1. 在 `USB streaming` 模式下枚举 capture devices。
2. 记录所有 device type，而不仅仅是 expected external type。
3. 请求并记录 camera permission。
4. 如果可能，用 iPad 或 USB-C iPhone 对照测试。

判定：

- Z6III USB streaming 下仍无 external device，初步判断 iPhone/Lightning 或 iOS API 不暴露该视频输入。

### 7.6 能看到视频，但 PTP 消失或失败

可能原因：

- Z6III USB streaming 模式切换了 USB personality。
- UVC streaming 占用了 USB 通信。
- iOS 将视频设备和 ImageCapture camera device 作为互斥路径。

定位方法：

1. 视频启动前记录 ImageCaptureCore device 和 PTP capability。
2. 视频启动后重新记录 ImageCaptureCore device 和 PTP capability。
3. 视频运行中发送 `GetDeviceInfo`。
4. 停止视频后再次发送 `GetDeviceInfo`。

判定：

- 视频启动后 PTP capability 消失，说明控制和视频在公开 API 下不可共存。
- 停止视频后 PTP 恢复，说明存在模式或 session 互斥。

### 7.7 PTP / gphoto config 可用，但没有 preview/movie

可能原因：

- `MTP/PTP` 模式只提供控制和文件访问，不输出 UVC。
- Nikon live view 数据通道不公开或需要私有命令。
- AVFoundation 不支持当前设备。

定位方法：

1. `MTP/PTP` 模式下跑 AVFoundation probe。
2. `USB streaming` 模式下跑 AVFoundation probe。
3. `MTP/PTP` 模式下跑 Nikon live view probe。
4. 比较三个结果。

判定：

- `MTP/PTP` 下 PTP 成功、视频失败；`USB streaming` 下视频成功、PTP 失败，则单线完整方案风险极高。

### 7.8 视频首帧成功但不稳定

可能原因：

- MJPEG 解码压力。
- Lightning 带宽或供电不稳定。
- 相机休眠或过热。
- capture session 格式选择不合适。

定位方法：

1. 记录 first frame latency。
2. 记录 1 分钟、5 分钟、10 分钟持续帧率。
3. 记录 dropped frame count。
4. 降低分辨率和帧率重复测试。
5. 测试不同线材和供电状态。

判定：

- 低分辨率稳定、高分辨率不稳定，则是带宽或解码压力。
- 换线后结果变化明显，则是物理链路问题。

## 8. 测试矩阵

### 8.1 USB 模式矩阵

每种 USB 模式都运行完整探针：

```text
MTP/PTP
iPhone
USB streaming
```

不测试：

```text
USB-LAN
Wi-Fi
Network Bridge
```

### 8.2 线材矩阵

至少测试：

```text
USB-C to Lightning 数据线
Apple Lightning to USB Camera Adapter + USB-C 数据线
备用 USB-C to Lightning 数据线
```

每个线材记录：

```text
是否发现 ImageCaptureCore device
是否发现 AVFoundation external device
是否支持 PTP
是否收到视频首帧
是否出现供电或断连
```

### 8.3 gphoto 功能矩阵

每种 USB 模式都记录：

```text
auto-detect
summary
abilities
list-config
get-config batch
safe set-config
capture-image
capture-image-and-download
capture-preview
capture-movie
wait-event
list-files
get-file
```

每项结果必须是：

```text
supported
unsupported
unsafe
unknown
failed
```

### 8.4 顺序矩阵

```text
先 PTP，后视频
先视频，后 PTP
视频运行中 PTP read
PTP polling 中启动视频
断开重连后重复
相机休眠唤醒后重复
```

### 8.5 相机状态矩阵

```text
照片模式
视频模式
M / A / S / P / Auto
存储卡正常
无存储卡
相机菜单打开
相机休眠
电池低电量
镜头 AF
镜头 MF
```

## 9. 日志规格

日志格式：JSON Lines。

每次启动先写 session header：

```json
{
  "event": "session.start",
  "codename": "GPhotoProbe",
  "version": "0.1",
  "timestamp": "2026-05-21T00:00:00Z",
  "appBuild": "debug",
  "deviceModel": "iPhone 12 Pro",
  "iosVersion": "...",
  "targetCamera": "Nikon Z6III"
}
```

gphoto 命令等价结果必须写：

```json
{
  "event": "gphoto.commandResult",
  "command": "listConfig",
  "status": "passed",
  "supportedByIOSAPI": true,
  "supportedByCamera": true,
  "requiresExperimentalVendorCommand": false,
  "evidenceEventIDs": ["..."]
}
```

每个探针必须写：

```json
{
  "event": "probe.finished",
  "probe": "PTPCapabilityProbe",
  "status": "passed",
  "durationMS": 1032,
  "summary": "GetDeviceInfo succeeded"
}
```

错误事件必须写：

```json
{
  "event": "probe.error",
  "probe": "USBVideoDeviceProbe",
  "domain": "AVFoundation",
  "reason": "noExternalVideoDevice",
  "underlyingError": null,
  "diagnosticHint": "Try Z6III USB streaming mode"
}
```

PTP trace 必须写：

```json
{
  "event": "ptp.trace",
  "direction": "request",
  "operation": "GetDeviceInfo",
  "operationCode": "0x1001",
  "transactionID": 1,
  "parameters": [],
  "payloadLength": 0
}
```

视频 trace 必须写：

```json
{
  "event": "video.frame",
  "source": "AVFoundationExternal",
  "width": 1920,
  "height": 1080,
  "frameRateEstimate": 29.97,
  "pixelFormat": "420f",
  "sequence": 1,
  "firstFrameMS": 840
}
```

## 10. 判定标准

### 10.1 gphoto 核心能力成立

满足以下条件，才认为 iPhone 侧实现 `libgphoto2` 核心功能具备可行性：

1. ImageCaptureCore 能发现 Nikon Z6III。
2. PTP `GetDeviceInfo` 成功。
3. 能生成 abilities matrix。
4. 能生成 config tree。
5. 能完成 `list-config` 和批量 `get-config`。
6. 至少一个低风险 `set-config` 写后 readback 成功。
7. `capture-image` 或 `capture-image-and-download` 至少一个成功。
8. `wait-event` 或 polling 能观察 capture 结果。
9. `list-files` / `get-file` 至少一个只读文件访问路径成功。

### 10.2 gphoto 控制成立，preview/movie 不成立

满足以下条件：

1. ImageCaptureCore discovery 成功。
2. PTP probe 成功。
3. abilities / config / capture 至少部分成立。
4. `capture-preview`、`capture-movie`、AVFoundation external video 均失败或 inconclusive。

结论：

- 可以继续开发 libgphoto2 风格的控制、配置、拍摄和文件访问能力。
- 不能承诺 iPhone 12 Pro + USB to Lightning 实时视频流。

### 10.3 preview/movie 成立，gphoto 控制不成立

满足以下条件：

1. AVFoundation external video 或 Nikon live view 数据成功。
2. ImageCaptureCore discovery 失败，或 PTP capability 缺失，或 config/capture 能力无法建立。

结论：

- 可以验证有线视频输入。
- 不能承诺 `gphoto2` 风格配置和拍摄控制。

### 10.4 二者互斥

满足以下条件：

1. `MTP/PTP` 模式下 PTP 成功但视频失败。
2. `USB streaming` 模式下视频成功但 PTP 失败。
3. 任一模式下启动视频后 PTP capability 消失或命令 timeout。

结论：

- 公开 API 下同线“preview/movie + gphoto 控制”不可作为主方案。
- 后续版本必须重新定义目标，或接受 `gphoto2` 控制能力与实时监看能力分离。

### 10.5 全部失败

满足以下条件：

- ImageCaptureCore 发现失败。
- AVFoundation external video 发现失败。
- 所有 USB 模式均无可用设备。

结论：

- 优先排查线材、转接器、相机 USB 设置、iOS 权限。
- 如果对照设备可用，则判定为 iPhone 12 Pro / Lightning 平台限制。

## 11. 开发切片

### Slice 1：Target 和基础 UI

- 新增 `GPhotoProbe` target。
- 新增独立 app entry。
- 新增基础 probe list UI。
- 新增 session setup form。
- 新增 JSONL logger。

完成标准：

- 可在 Simulator 启动。
- 可在 iPhone 真机安装。
- 可导出空日志。

### Slice 2：桌面 baseline 导入

- 导入桌面 `gphoto2 --debug` 日志。
- 解析 model、abilities、config keys。
- 显示 baseline 对照表。

完成标准：

- 可导入至少一份桌面日志。
- 能把 iPhone 探针结果和 baseline 关联。

### Slice 3：ImageCaptureCore discovery

- 接入 `ICDeviceBrowser`。
- 显示发现设备。
- 记录 capabilities。

完成标准：

- 无相机时有明确 timeout。
- 发现设备时写入 JSONL。

### Slice 4：PTP probe

- 封装最小 PTP command。
- 发送 `GetDeviceInfo`。
- 记录 response。

完成标准：

- capability 缺失、timeout、response rejected 都有清晰日志。

### Slice 5：gphoto abilities / config probe

- 生成 abilities matrix。
- 生成 config tree。
- 执行 get-config batch。
- 执行安全 set-config。

完成标准：

- 每个 config key 有 current、choices、readonly/writable。
- 每次 set 都有 readback。

### Slice 6：capture / event / file probe

- capture-image。
- wait-event。
- list-files。
- get-file。
- capture-image-and-download。

完成标准：

- 不删除相机文件。
- 失败时能区分 capture、event 和 file access 问题。

### Slice 7：preview / movie / AVFoundation video probe

- 请求 camera permission。
- 枚举外接 capture device。
- 尝试启动 session。
- 捕获首帧。

完成标准：

- 无外接设备和首帧 timeout 都有清晰日志。

### Slice 8：Coexistence probe

- 实现 PTP then video。
- 实现 video then PTP。
- 实现 video running + PTP read。

完成标准：

- 可以判断 PTP 和视频是否互相导致消失、超时或中断。

### Slice 9：导出和测试包整理

- App 内导出 JSONL。
- 增加测试清单页面。
- 增加版本号和 build 信息。

完成标准：

- 真机测试后能导出完整日志。
- 日志足以复盘每个探针步骤。

## 12. 真机测试执行顺序

建议第一次测试严格按以下顺序：

1. 在桌面通过 `gphoto2 --debug` 采集 baseline：auto-detect、summary、abilities、list-config、capture-preview、wait-event、list-files。
2. 打开 GPhotoProbe，不连接相机，运行 discovery、PTP、config、video probe，确认无设备 baseline。
3. Z6III 设置为 `MTP/PTP`，连接 iPhone，运行 discovery、PTP、abilities、config。
4. 如果 config 成立，再运行 capture、event、file access。
5. 如果 capture/file 成立，再运行 preview/movie 和 coexistence。
6. 导出日志，命名 `GPhotoProbe_MTP_PTP_run1.jsonl`。
7. Z6III 设置为 `iPhone`，重新连接，运行同一组探针。
8. 导出日志，命名 `GPhotoProbe_iPhoneMode_run1.jsonl`。
9. Z6III 设置为 `USB streaming`，重新连接，重点运行 preview/movie、AVFoundation video、coexistence。
10. 导出日志，命名 `GPhotoProbe_USBStreaming_run1.jsonl`。
11. 更换线材或转接器，重复关键探针。
12. 汇总结果，按 gphoto 功能矩阵判断哪些能力可以进入 PrismBlade 后续通信路线。

## 13. 参考资料

- gphoto/libgphoto2 GitHub  
  https://github.com/gphoto/libgphoto2
- gPhoto remote control documentation  
  https://gphoto.sourceforge.io/doc/remote/
- Apple Developer：ImageCaptureCore  
  https://developer.apple.com/documentation/imagecapturecore
- Apple Developer：`ICCameraDevice.requestSendPTPCommand`  
  https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requestsendptpcommand%28_%3Aoutdata%3Acompletion%3A%29
- Apple Developer：AVFoundation external camera device type  
  https://developer.apple.com/documentation/avfoundation/avcapturedevice/devicetype-swift.struct/external
- Nikon Z6III Reference Guide：USB  
  https://onlinemanual.nikonimglib.com/z6III/en/nwm_usb_data_connection_368.html
