# PrismBlade v0.1.1 技术文档

代号：PrismBlade  
版本：v0.1.1  
日期：2026-05-12  
目标平台：iOS / iPhone 12 Pro  
首版运行目标：Xcode Simulator  
目标相机：Nikon Z6III  
当前阶段：监看功能原型，不实现真实 USB/PTP 相机通信

## 1. 版本定位

PrismBlade v0.1.1 是一个横屏优先的 iOS 相机监看 App 原型版本。它的核心目标是先跑通监看体验、图像辅助工具、LUT 工作流和 Mock 相机控制状态，为后续接入 Nikon Z6III 的 USB/PTP 通信保留清晰边界。

v0.1.1 不追求真实相机连接，也不移植 libgphoto2。所有相机控制都先经过 Mock 通信层，确保 UI、状态流和命令模型提前成型。

## 2. 首版范围

### 必须实现

- 默认横屏监看界面。
- 设置页中的“允许竖屏拍摄/监看”开关。
- 模拟视频帧源。
- 视频预览。
- 伪色。
- 斑马纹。
- Luma waveform。
- RGB Parade。
- 真实 `.cube` LUT 导入、解析、校验、选择、开关和强度调节。
- Mock 相机控制面板：ISO、快门、光圈、WB、录制、拍照、对焦。
- 通信抽象层：`CameraTransport` + `MockCameraTransport`。
- 图像输入抽象层：`FrameSource` + 模拟实现。

### 明确不做

- 不连接真实 Nikon Z6III。
- 不实现 USB/PTP 数据传输。
- 不移植 libgphoto2。
- 不保存真实录制文件。
- 不做对焦峰值。
- 不做 histogram。
- 不做 LUT 分组、收藏、缩略图。
- 不做 3D LUT 性能深度优化，只保证接口可演进。

## 3. 技术选型

### App 层

- SwiftUI：负责界面、状态绑定、设置页和工具面板。
- Combine 或 Swift Concurrency：负责状态流、帧源事件和 Mock 通信事件。
- Observation：如果最低系统版本选择 iOS 17+，优先使用 Swift Observation；否则使用 `ObservableObject`。

### 图像层

- Metal：负责最终预览渲染、overlay 合成和后续性能优化。
- Core Image：可用于 v0.1.1 的 LUT、伪色、斑马纹快速实现；性能瓶颈出现后再下沉到 Metal shader。
- AVFoundation：用于本地视频文件模拟帧源。

### 文件导入

- SwiftUI `fileImporter`：导入 `.cube` 文件。
- App sandbox documents/cache：保存用户导入后的 LUT 副本和索引。
- 自研 `.cube` parser：首版支持常见 3D LUT 格式。

## 4. 总体架构

```text
PrismBladeApp
  ├─ AppShell
  │   ├─ MonitorScreen
  │   ├─ SettingsScreen
  │   └─ LUTManagerScreen
  │
  ├─ Domain
  │   ├─ MonitorSession
  │   ├─ MonitorState
  │   ├─ CameraState
  │   ├─ ConnectionState
  │   ├─ OrientationState
  │   └─ LUTState
  │
  ├─ Video
  │   ├─ FrameSource
  │   ├─ SimulatedFrameSource
  │   ├─ VideoFileFrameSource
  │   ├─ FrameProcessor
  │   ├─ PreviewRenderer
  │   └─ ScopeAnalyzer
  │
  ├─ Imaging
  │   ├─ LUTParser
  │   ├─ LUTRepository
  │   ├─ FalseColorProcessor
  │   ├─ ZebraProcessor
  │   ├─ WaveformAnalyzer
  │   └─ RGBParadeAnalyzer
  │
  └─ Camera
      ├─ CameraTransport
      ├─ CameraCommandService
      ├─ MockCameraTransport
      └─ FutureAdapters
          ├─ ImageCaptureTransport
          ├─ PTPTransport
          └─ NetworkBridgeTransport
```

架构原则：

- UI 不直接读取视频文件、LUT 文件或相机连接。
- 图像处理层不依赖 Nikon、USB、PTP 或 libgphoto2。
- 相机控制 UI 只依赖 `CameraCommandService`，不依赖具体 transport。
- 所有后续真实通信能力都通过 `CameraTransport` 接入。

## 5. 目录建议

```text
PrismBlade/
  PrismBladeApp.swift
  App/
    AppRouter.swift
    AppEnvironment.swift
  Screens/
    Monitor/
      MonitorScreen.swift
      MonitorOverlayView.swift
      MonitorToolbar.swift
      ScopePanel.swift
      CameraControlPanel.swift
    Settings/
      SettingsScreen.swift
    LUT/
      LUTManagerScreen.swift
  Domain/
    MonitorSession.swift
    MonitorModels.swift
    CameraModels.swift
    LUTModels.swift
  Video/
    FrameSource.swift
    SimulatedFrameSource.swift
    VideoFileFrameSource.swift
    FrameProcessor.swift
    PreviewRenderer.swift
  Imaging/
    LUTParser.swift
    LUTRepository.swift
    FalseColorProcessor.swift
    ZebraProcessor.swift
    ScopeAnalyzer.swift
  Camera/
    CameraTransport.swift
    CameraCommandService.swift
    MockCameraTransport.swift
  Resources/
    LUTs/
    TestMedia/
```

## 6. 核心数据模型

### MonitorSession

`MonitorSession` 是首版主状态容器，负责连接 UI、帧源、图像处理和相机命令服务。

职责：

- 启动和停止监看。
- 切换监看工具。
- 管理当前帧源。
- 管理当前 LUT。
- 管理 scope 显示模式。
- 持有相机控制状态。

建议字段：

```swift
struct MonitorSessionState {
    var connection: ConnectionState
    var camera: CameraState
    var monitor: MonitorState
    var orientation: OrientationState
    var lut: LUTState
}
```

### MonitorState

```swift
struct MonitorState {
    var falseColorEnabled: Bool
    var zebraEnabled: Bool
    var zebraMode: ZebraMode
    var zebraThreshold: Double
    var scopeMode: ScopeMode
    var scopeOpacity: Double
    var zoomMode: ZoomMode
    var previewFitMode: PreviewFitMode
}
```

### CameraState

```swift
struct CameraState {
    var iso: CameraValue<Int>
    var shutter: CameraValue<ShutterSpeed>
    var aperture: CameraValue<Aperture>
    var whiteBalance: CameraValue<WhiteBalance>
    var isRecording: Bool
    var focusMode: FocusMode
    var batteryLevel: Int?
    var storageRemaining: StorageInfo?
}
```

`CameraValue` 需要同时表达当前值、可选项、是否可写和是否正在提交命令。

### LUTState

```swift
struct LUTState {
    var selectedLUT: LUTDescriptor?
    var importedLUTs: [LUTDescriptor]
    var builtInLUTs: [LUTDescriptor]
    var intensity: Double
    var isEnabled: Bool
    var lastImportError: LUTImportError?
}
```

## 7. 视频输入设计

### FrameSource

```swift
protocol FrameSource {
    var status: FrameSourceStatus { get }
    var format: FrameFormat? { get }
    func start() async throws
    func stop() async
    func frames() -> AsyncStream<VideoFrame>
}
```

`VideoFrame` 建议包含：

- pixel buffer 或 texture。
- 时间戳。
- 分辨率。
- 色彩空间。
- 帧序号。
- 模拟相机 metadata。

### v0.1.1 帧源

- `SimulatedFrameSource`：生成 ramp、色块、灰阶、过曝区域，用于验证工具。
- `VideoFileFrameSource`：播放内置测试视频或用户选择的视频文件。

首版可以先默认使用 `SimulatedFrameSource`，避免资源缺失导致 App 打不开。

## 8. 图像处理管线

### 处理顺序

```text
VideoFrame
  -> Normalize
  -> Apply LUT
  -> False Color / Zebra Overlay
  -> Scope Sampling
  -> Preview Render
```

首版原则：

- LUT、伪色、斑马纹只影响监看显示，不改变原始帧。
- Scope 默认分析“显示链路结果”，也就是 LUT 后画面。
- 未来需保留“LUT 前 / LUT 后”分析源切换。

### 性能目标

- Xcode Simulator：工具链逻辑可用，交互不卡死。
- iPhone 12 Pro 真机目标：1080p 30fps 作为第一性能线。
- Scope 允许降采样和隔帧分析。
- `.cube` 导入解析可在后台执行，不能阻塞监看界面。

## 9. 伪色

### 输入

- 默认使用 Rec.709 显示亮度。
- 后续接入 N-Log 时增加 Log 到 IRE 的解释模式。

### 预设映射

```text
0-5 IRE      deep shadow warning
18 IRE       middle gray reference
40-60 IRE    subject / skin safe range
90-100 IRE   highlight warning
100+ IRE     clipping warning
```

### UI

- 工具按钮：开/关。
- 设置入口：选择预设。
- 状态栏显示 false color active。

## 10. 斑马纹

### 模式

- `high`: 高于阈值显示斜线。
- `range`: 落在指定范围内显示斜线。

### 参数

- 默认 high threshold：90%。
- 可调范围：50%-100%。
- range 默认：65%-75%。

### 实现要求

- overlay 方式显示。
- 斜线密度和透明度固定为首版默认值。
- 不改变 LUT 后底图颜色，只叠加提示纹理。

## 11. Scope

### Luma Waveform

- 横轴对应画面 x 坐标。
- 纵轴对应亮度。
- 使用降采样降低计算量。
- 支持半透明底板、网格线、IRE 标尺。

### RGB Parade

- 分为 R/G/B 三个通道区域。
- 每个通道独立显示分布。
- 用于检查偏色、通道裁切和 LUT 后通道变化。

### UI

```swift
enum ScopeMode {
    case off
    case lumaWaveform
    case rgbParade
}
```

首版不做 waveform + parade 同屏。用户在 scope 面板中切换。

## 12. LUT

### `.cube` 支持范围

v0.1.1 支持：

- `TITLE`
- `LUT_3D_SIZE`
- `DOMAIN_MIN`
- `DOMAIN_MAX`
- RGB 浮点数据行
- `#` 注释

v0.1.1 暂不保证：

- 1D LUT 完整支持。
- 非标准扩展标签。
- 超大 LUT 的极致性能。

### 导入流程

1. 用户在 LUT Manager 中点击导入。
2. `fileImporter` 选择 `.cube`。
3. 后台读取文件。
4. `LUTParser` 解析并校验。
5. `LUTRepository` 保存副本和 metadata。
6. UI 显示导入成功或错误。
7. 用户选择 LUT，监看链路即时应用。

### 校验规则

- 必须包含 `LUT_3D_SIZE`。
- 数据行数量必须等于 `size * size * size`。
- RGB 每行必须为 3 个有效浮点数。
- 值域默认按 0-1 处理，超出范围先 clamp 并给 warning。
- 文件读取失败、格式错误、数据数量不匹配需要明确错误提示。

## 13. 相机控制 Mock

### CameraTransport

```swift
protocol CameraTransport {
    var connectionEvents: AsyncStream<CameraConnectionEvent> { get }
    var cameraEvents: AsyncStream<CameraEvent> { get }

    func connect() async throws
    func disconnect() async
    func capabilities() async throws -> CameraCapabilities
    func currentState() async throws -> CameraState
    func setValue<T>(_ value: T, for parameter: CameraParameter) async throws
    func trigger(_ action: CameraAction) async throws
}
```

### MockCameraTransport

首版行为：

- 启动时显示未连接。
- 用户点击连接后进入已连接状态。
- ISO、快门、光圈、WB 从 Mock 能力表读取。
- 参数提交有短暂 loading 状态。
- 录制按钮切换 `isRecording`。
- 拍照按钮显示一次性成功反馈。
- 对焦按钮模拟 half-press / focus success。
- 可通过调试入口模拟断开和错误。

### Mock 能力表

```text
ISO: 100, 200, 400, 800, 1600, 3200, 6400
Shutter: 1/25, 1/50, 1/60, 1/100, 1/125, 1/250
Aperture: f/1.8, f/2.0, f/2.8, f/4.0, f/5.6, f/8.0
WB: Auto, 3200K, 4300K, 5600K, 6500K
Focus: AF-S, AF-C, MF, Touch Focus placeholder
Actions: Record, Capture, Half Press, Focus
```

## 14. 方向策略

默认策略：

- App 首屏横屏。
- 横屏是主工作流。
- 竖屏默认关闭。

设置项：

```swift
struct OrientationState {
    var allowsPortraitMonitoring: Bool
    var currentOrientation: AppOrientation
    var previewFitMode: PreviewFitMode
}
```

行为：

- `allowsPortraitMonitoring == false` 时，竖屏布局不启用。
- 用户在设置页打开开关后，App 允许进入竖屏布局。
- 竖屏设置持久化到本地。
- 主监看界面不提供竖屏快捷入口。

## 15. UI 结构

### MonitorScreen

默认横屏布局：

- 中央全屏预览。
- 顶部轻量状态条。
- 左侧工具按钮组。
- 右侧工具按钮组。
- 底部 scope overlay。
- 右侧滑出相机控制面板。

### CameraControlPanel

控件要求：

- ISO：菜单或横向 picker。
- 快门：菜单或横向 picker。
- 光圈：菜单或横向 picker。
- WB：菜单或横向 picker。
- 录制：明显的圆形按钮和录制状态。
- 拍照：快门按钮。
- 对焦：半按/对焦按钮，首版可做单按钮。

### SettingsScreen

首版包含：

- 允许竖屏拍摄/监看。
- 默认 zebra threshold。
- Scope opacity。
- LUT 管理入口。
- Mock 调试入口。

## 16. 持久化

首版需要持久化：

- 竖屏开关。
- 最近选择的 LUT。
- LUT 强度。
- zebra threshold。
- scope mode。
- scope opacity。

建议：

- 简单设置使用 `UserDefaults`。
- LUT 文件和 metadata 使用 documents 目录。
- LUT metadata 可用 JSON 索引文件。

## 17. 错误处理

### LUT 错误

- 文件无法读取。
- 文件不是 `.cube`。
- 缺少 `LUT_3D_SIZE`。
- 数据行数量不匹配。
- RGB 值非法。
- LUT 尺寸过大。

### 视频错误

- 帧源启动失败。
- 视频文件无法解码。
- 无可用帧。

### Mock 相机错误

- 未连接时提交命令。
- 参数不在能力表内。
- 模拟连接断开。

错误展示原则：

- 监看界面不被错误弹窗频繁打断。
- 导入类错误用明确提示。
- 连接和命令类错误显示在状态条或控制面板内。

## 18. 测试计划

### 单元测试

- `.cube` parser 正常文件。
- `.cube` parser 数据数量不匹配。
- `.cube` parser 非法浮点数。
- Mock transport 参数读写。
- Monitor state toggle。

### 快照/交互测试

- 横屏主界面。
- 设置页竖屏开关。
- 相机控制面板展开。
- LUT 导入错误提示。
- Scope 模式切换。

### 手动验证

- App 启动默认横屏。
- 打开伪色后画面出现曝光映射。
- 打开斑马纹后高亮区域出现斜线。
- Luma waveform 随画面变化。
- RGB Parade 随 RGB ramp 变化。
- 导入 `.cube` 后画面色彩发生变化。
- LUT 强度滑杆有效。
- Mock ISO、快门、光圈、WB 可切换。
- 录制、拍照、对焦有明确反馈。

## 19. 后续通信预留

v0.1.1 的关键预留点：

- `CameraTransport` 不暴露 libgphoto2 类型。
- `CameraCapabilities` 需要能表达 Nikon 真实能力差异。
- `CameraEvent` 需要覆盖属性变化、连接断开、电量变化、存储变化和错误。
- `FrameSource` 能替换为未来 live view 视频源。
- `CameraState` 不假设所有参数都可写。

未来可接入：

- `ImageCaptureTransport`：验证 iOS 侧 ImageCaptureCore 能力。
- `PTPTransport`：验证自研 PTP/libgphoto2 思路。
- `NetworkBridgeTransport`：作为 iOS USB 受限时的中继路线。

## 20. v0.1.1 完成标准

v0.1.1 完成时，应满足：

- 在 Xcode Simulator 可启动。
- 默认进入横屏监看体验。
- 设置页可开启竖屏监看。
- 有可运行模拟帧源。
- 预览画面可见且持续刷新。
- 伪色、斑马纹可开关。
- Luma waveform 和 RGB Parade 可切换显示。
- `.cube` LUT 可导入并应用。
- Mock 相机控制面板完整出现并可交互。
- 真实通信相关代码只停留在接口和命名空间，不包含具体 USB/PTP 实现。

## 21. 与原型设计的关系

本文档是 `PROTOTYPE_DESIGN.md` 的 v0.1.1 工程化版本。原型设计用于确认产品方向；本文档用于指导第一版实现、拆分模块和控制边界。
