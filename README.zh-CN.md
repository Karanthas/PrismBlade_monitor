# PrismBlade 中文说明

**PrismBlade** 是一个面向 Nikon Z6III 工作流的 iOS 相机监看 App 原型。当前分支正在按 `v0.2.1` Metal-first 计划推进。阶段 3-6 已经形成一个可运行的纵向切片：项目现在有真实 `CVPixelBuffer` 媒体帧模型、BGRA 模拟帧源、`AVAssetReader` 视频文件帧源、`CVPixelBuffer -> MTLTexture -> MTKView drawable` 的 Metal 预览闭环、显示链路 3D LUT 采样、集中式 Rec.709 / N-Log / HLG 显示空间转换、shader 级伪色 / 斑马纹曝光辅助，以及用于 Luma waveform / RGB Parade 的 Metal compute scope bins。

> 英文主版本：[README.md](README.md)

## 当前状态

当前仓库包含一个可在 iOS Simulator 构建的 SwiftUI 原型工程，并完成了 `v0.2.1` 阶段 3 的 Metal 预览闭环、阶段 4 的 LUT 渲染路径、阶段 5 的颜色转换 / 曝光辅助切片，以及阶段 6 的 Metal compute scope 路径。它目前**不会连接真实 Nikon 相机**，**不会实现 USB/PTP 通信**，也**不会移植 `libgphoto2`**。

这个阶段的代码重点是建立可替换边界：

- `FrameSource` 负责提供真实 `CVPixelBuffer` 媒体帧，后续可以替换成真实 live view 源。
- `SimulatedFrameSource` 现在生成 BGRA pixel buffer，不再只输出动画相位。
- `VideoFileFrameSource` 使用 `AVAssetReader` 读取本地视频，并输出同一套 `VideoFrame`。
- `MetalTextureBridge` 使用 `CVMetalTextureCache` 将 BGRA `CVPixelBuffer` 桥接为 `MTLTexture`。
- `MetalPreviewRenderer` 通过 `MTKViewDelegate` 把最新媒体帧绘制到 `MTKView` drawable。
- `MetalPreviewSurface` 用 `UIViewRepresentable` 把 `MTKView` 接回 SwiftUI 监看界面。
- `LUTStore` 和 `LUTRepository` 负责加载导入 LUT 与可选本地 `.cube` 资源，不要求仓库内再分发厂商 LUT。
- `LUTPass` 将解析后的 `.cube` 数据上传为 3D Metal texture，并按 LUT descriptor 缓存 texture resource。
- `ColorTransformPass`、`FalseColorPass`、`ZebraPass` 负责阶段 5 shader uniforms 的 Swift 侧状态映射。
- `MetalFrameProcessor` 和 `ScopeComputePass` 负责节流后的 Metal compute 分析，并把紧凑的 `ScopeData` bins 回传给 SwiftUI scope 面板。
- `CameraTransport` 负责相机通信，后续可以替换成 ImageCaptureCore、PTP 或网络桥接实现。
- `CameraCommandService` 在命令进入 transport 前做参数校验。
- LUT 解析和仓库逻辑与监看 UI 分离。
- SwiftUI 负责布局和状态展示；实时预览画面现在由 Metal 绘制，工具栏、sheet 和底部控制条仍由 SwiftUI 管理。
- `PrismBladeTests` 负责可重复 fixtures 和 CPU reference，后续 Metal pass 可以拿它们做确定性的结果对比。

## 已实现功能

- 横屏优先的监看主界面。
- 模拟帧源：生成真实 BGRA `CVPixelBuffer`，内容包含移动色块和亮度 ramp。
- 媒体帧模型：`VideoFrame` 携带 `sequence`、`CMTime` timestamp、`FrameFormat`、`CVPixelBuffer` 和相机 metadata。
- 视频文件帧源：`VideoFileFrameSource` 使用 `AVAssetReader` 读取本地 `.mov` / 视频资源并输出 `CVPixelBuffer`。
- 初步色彩编码识别：支持通过 hint、`REC709` / `NLOG` / `HLG` 文件名约定和视频 metadata 标记识别 `Rec.709`、`N-Log`、`HLG`。
- Metal texture 桥接：`MetalTextureBridge` 将 BGRA `CVPixelBuffer` 转换为 `.bgra8Unorm` `MTLTexture`。
- Metal 主预览：`MetalPreviewRenderer` 使用 `MTLDevice`、`MTLCommandQueue`、基础 render pipeline 和 `PreviewShaders.metal` 原样显示输入帧。
- Metal preview shader 中的 Rec.709、N-Log、HLG 输入到显示工作空间的转换。
- Rec.709 输入默认直接输出到监看显示链路；N-Log 输入可通过监看界面的 N-Log LUT 预览按钮启用选中 `.cube` LUT。
- Metal preview shader 中的显示链路 3D LUT 应用，并通过 LUT intensity 混合工作空间画面和 LUT 后画面。
- 基于转换后显示亮度的 shader 伪色。
- 基于转换后显示亮度和设置阈值的 High Zebra / Range Zebra mask。
- Metal compute 生成的 Luma waveform 和 RGB Parade scope bins，由 `ScopePanel` 绘制，不再使用程序占位曲线；默认分析颜色转换和 N-Log LUT 预览后的画面，不包含伪色/斑马纹 overlay。
- `MetalFrameProcessor` 统一解析 LUT 预览状态、生成 shader uniforms，并编排 scope compute 所需的同一份显示状态。
- `LUTPass` 将解析后的 `.cube` entries 转换为 `.rgba32Float` 3D `MTLTexture` resource。
- identity fallback LUT resource：未启用 LUT 或无法解析当前 LUT 时，renderer 仍可继续绘制。
- SwiftUI / Metal 集成：`MetalPreviewSurface` 通过 `UIViewRepresentable` 包装 `MTKView`，替代主预览中的 SwiftUI gradient 占位层。
- Metal viewport 缩放：fit、fill、1x、2x 通过 renderer viewport 实现最小闭环。
- 顶部状态栏：连接状态、输入格式、帧率、LUT 状态、曝光工具、电量和存储占位。
- 左右两侧浮动工具按钮。
- 已接入 Metal preview shader 的伪色开关。
- 已接入 Metal preview shader 的斑马纹开关和阈值设置。
- 宽度为监看区域 40% 的紧凑 Luma waveform 覆盖面板。
- 宽度为监看区域 40% 的紧凑 RGB Parade 覆盖面板。
- 缩放模式切换：fit、fill、1x、2x。
- 底部常驻相机控制条。
- 点击参数后使用离散滑块调整曝光模式、光圈、快门、ISO、白平衡和对焦模式。
- 曝光模式显示和 Mock 切换：`M / A / S / P / Auto`。
- 根据曝光模式限制参数可用性：
  - `M`：光圈、快门、ISO 可调。
  - `A`：光圈可调，快门锁定。
  - `S`：快门可调，光圈锁定。
  - `P`：光圈和快门锁定。
  - `Auto`：光圈、快门、ISO、白平衡锁定。
- 点击被锁定参数、相机动作完成或命令失败时显示全局短提示。
- 点击预览画面空白区域可以关闭当前相机参数调整浮层。
- 相机参数调整浮层打开时，Scope overlay 会自动避让，避免与底部控制区域重叠。
- LUT 管理：可选本地内置 `.cube` 扫描和 `.cube` 文件导入。
- `.cube` 解析器：支持 `TITLE`、`LUT_3D_SIZE`、`DOMAIN_MIN`、`DOMAIN_MAX`、注释和 RGB 数据行校验。
- 可选本地 LUT 目录：`PrismBlade/Resources/LUTs` 下被忽略的厂商 LUT 文件，只有实际存在且解析成功时才会显示。
- LUT metadata 通过 JSON index 持久化到 App documents 目录。
- 设置页：竖屏监看开关、伪色/斑马纹默认开启偏好、斑马纹阈值、scope 透明度、scope 模式和 Mock 调试入口。
- Mock Nikon Z6III 相机控制：
  - 曝光模式
  - 光圈
  - 快门
  - ISO
  - 白平衡
  - 对焦模式
  - 录制开关
  - 拍照动作
  - 对焦动作
- `v0.2.1` 阶段 1-6 XCTest target：
  - 小尺寸 BGRA `CVPixelBuffer` 测试图生成。
  - 合法和非法 `.cube` LUT fixture 生成。
  - luma、LUT 采样、斑马纹 mask、waveform bins 的 CPU reference helper。
  - `LUTParser`、`CameraExposureRules`、`CameraCommandService`、`MockCameraTransport` 单元测试。
  - `VideoFrame` 媒体帧模型测试。
  - `SimulatedFrameSource` 真实 pixel buffer 输出测试。
  - 使用临时生成 `.mov` 的 `VideoFileFrameSource` 读取、时间戳和色彩编码测试。
  - `MetalTextureBridge` 的 BGRA pixel buffer 到 Metal texture 桥接测试。
  - `LUTRepository` 可选本地 LUT 发现和导入 LUT 重载测试。
  - `LUTPass` 3D texture 上传顺序、domain 保留和 texture format 测试。
  - `ColorTransformPass` 使用生成的 Rec.709 / N-Log / HLG 输入做参考测试。
  - `MetalLUTShaderTests` 使用离屏渲染验证 LUT intensity 混合、N-Log 显示转换、生成灰阶伪色和斑马纹阈值行为。
  - `ScopeComputePassTests` 验证 waveform / RGB Parade bins、readback 节流，以及启用 N-Log LUT 预览时 scope 分析 LUT 后结果。

## 尚未实现

- 真实 Nikon Z6III 连接。
- USB/PTP 通信。
- ImageCaptureCore 接入。
- `libgphoto2` 接入。
- 用户可见的真实视频文件播放入口。
- 基于色彩空间的自动 LUT 建议。
- 真实相机曝光模式读取。
- 真实 Nikon 能力表解析。
- 基于真实 Nikon 灰卡、色卡、肤色和 waveform 参考素材的深度颜色校准。
- Histogram。
- 对焦峰值。
- 真实录制或拍照文件保存。

## 环境要求

- 安装 Xcode 的 macOS。
- 支持 iOS 17+ 项目的 Xcode 版本。
- iOS Simulator runtime。
- Metal Toolchain 组件。若 `.metal` 编译报缺失，可运行：

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -downloadComponent MetalToolchain
```

当前已验证环境：

- Xcode `26.4.1`
- iPhone 17 Simulator，iOS `26.4.1`
- Swift `5`
- iOS deployment target `17.0`

## 项目结构

```text
PrismBlade/
  PrismBladeApp.swift
  App/
    AppEnvironment.swift
  Domain/
    MonitorModels.swift
    MonitorSession.swift
    LUTModels.swift
  Camera/
    CameraModels.swift
    CameraTransport.swift
  Video/
    FrameSource.swift
    SimulatedPixelBufferFactory.swift
    VideoFileFrameSource.swift
  Metal/
    MetalTextureBridge.swift
    MetalPreviewRenderer.swift
    MetalPreviewSurface.swift
    ColorTransformPass.swift
    FalseColorPass.swift
    ZebraPass.swift
    PreviewShaders.metal
  Imaging/
    LUTParser.swift
    LUTRepository.swift
    LUTStore.swift
    LUTPass.swift
  Screens/
    Monitor/
      MonitorScreen.swift
      ScopePanel.swift
      CameraControlPanel.swift
    Settings/
      SettingsScreen.swift
    LUT/
      LUTManagerScreen.swift
  Resources/
    LUTs/
PrismBladeTests/
  Fixtures/
    CubeFixtureFactory.swift
    PixelBufferFixtureFactory.swift
  References/
    CPUReference.swift
  FrameSourceStage2Tests.swift
  MetalTextureBridgeTests.swift
  LUTRepositoryTests.swift
  LUTPassTests.swift
  MetalLUTShaderTests.swift
  *Tests.swift
```

## 架构概览

```text
SwiftUI App Shell
  -> MonitorScreen
  -> SettingsScreen
  -> LUTManagerScreen

Domain State
  -> MonitorSession
  -> MonitorState
  -> CameraState
  -> LUTState
  -> OrientationState

Video Input
  -> FrameSource
  -> SimulatedFrameSource
  -> VideoFileFrameSource

Metal Preview
  -> MetalTextureBridge
  -> MetalPreviewRenderer
  -> MetalPreviewSurface
  -> ColorTransformPass
  -> FalseColorPass
  -> ZebraPass
  -> PreviewShaders.metal

Imaging
  -> LUTParser
  -> LUTRepository
  -> LUTStore
  -> LUTPass

Camera
  -> CameraCommandService
  -> CameraTransport
  -> MockCameraTransport

Tests
  -> PixelBufferFixtureFactory
  -> CubeFixtureFactory
  -> CPUReference
  -> 帧源、Metal bridge、LUT 解析/存储/渲染和相机领域规则的 XCTest
```

`MonitorSession` 是当前主状态容器。它负责协调帧输入、Mock 相机命令、设置持久化、LUT 导入状态、曝光模式可用性和 UI 所需的监看状态。

## 使用说明

### 使用 Xcode 打开

1. 打开 `PrismBlade.xcodeproj`。
2. 选择 `PrismBlade` scheme。
3. 选择一个 iPhone Simulator。
4. 运行 App。

App 启动后第一屏就是监看界面，没有登录页、介绍页或营销页。

### 使用终端构建

如果当前 `xcode-select` 没有指向完整 Xcode，可以显式指定 `DEVELOPER_DIR`：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project PrismBlade.xcodeproj \
  -scheme PrismBlade \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/PrismBladeDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

预期结果：

```text
** BUILD SUCCEEDED **
```

### 运行阶段 3-6 测试

阶段 3 的关键变化是主预览从 SwiftUI 合成画面切到 `MTKView`。阶段 4 新增真实 LUT texture 上传和 fragment shader LUT 采样。阶段 5 新增集中式 Rec.709 / N-Log / HLG 显示转换，以及 shader 级伪色和斑马纹。阶段 6 新增 Luma waveform 和 RGB Parade 的 Metal compute bins。你要验证的效果是：测试 target 能构建，fixtures 能生成，模拟帧源、视频文件帧源、Metal texture bridge、LUT repository、LUT pass、颜色转换、Metal shader 和 scope compute 自动化测试能全部通过。

#### 方式 A：Xcode

1. 打开 `PrismBlade.xcodeproj`。
2. 选择 `PrismBlade` scheme。
3. 选择一个 iPhone Simulator。
4. 按 `Command-U`，或点击 `Product > Test`。
5. 打开 Test navigator，确认 `PrismBladeTests` 下面的测试全部变绿。

你应该能看到这些测试套件：

- `PixelBufferFixtureFactoryTests`
- `LUTParserTests`
- `CameraExposureRulesTests`
- `CameraCommandServiceTests`
- `MockCameraTransportTests`
- `CPUReferenceTests`
- `FrameSourceStage2Tests`
- `MetalTextureBridgeTests`
- `LUTRepositoryTests`
- `LUTPassTests`
- `MetalLUTShaderTests`
- `ScopeComputePassTests`

#### 方式 B：终端

如果 `xcode-select -p` 指向 `/Library/Developer/CommandLineTools`，建议直接使用完整 Xcode 路径，或者显式设置 `DEVELOPER_DIR`。先列出可用模拟器：

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -showdestinations \
  -project PrismBlade.xcodeproj \
  -scheme PrismBlade \
  -derivedDataPath /private/tmp/PrismBladeDerivedData
```

从输出里选一个 iPhone Simulator 的 id，然后先构建测试产物：

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  build-for-testing \
  -project PrismBlade.xcodeproj \
  -scheme PrismBlade \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/PrismBladeDerivedData
```

预期结果：

```text
** TEST BUILD SUCCEEDED **
```

再运行测试，把 `<SIMULATOR_ID>` 替换成 `-showdestinations` 里看到的模拟器 id：

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  test-without-building \
  -project PrismBlade.xcodeproj \
  -scheme PrismBlade \
  -destination 'id=<SIMULATOR_ID>' \
  -derivedDataPath /private/tmp/PrismBladeDerivedData
```

预期结果：

```text
** TEST EXECUTE SUCCEEDED **
```

当前阶段 3-6 测试共有 49 个。成功时终端会逐个打印测试用例，并以 `TEST EXECUTE SUCCEEDED` 结束。

### 本地真实素材

真实 Nikon / HLG / N-Log 视频样本统一放在仓库根目录的 `material/` 下。该目录已经加入 `.gitignore`，只用于本地开发和手动验证，不随代码提交。

当前约定文件名：

- `material/REC709.MOV`
- `material/NLOG.MOV`
- `material/HLG.MOV`

自动化测试不依赖这些真实素材；测试会临时生成小型 `.mov` fixture 来验证 `AVAssetReader`，使用模拟 BGRA pixel buffer 验证 Metal bridge，并使用生成的灰阶、clipping 和 float texture 输入验证阶段 5 颜色转换、伪色、斑马纹，以及阶段 6 scope compute。

真实灰卡、色卡、肤色、过曝、欠曝、暗部噪声，以及参考 waveform / RGB Parade 素材仍然是后续阶段 5-7 深度校准所需素材。请继续把这些资源放在 `material/` 下；该目录已被忽略，应只保留在本地。

### 本地 LUT 素材

可选本地 `.cube` LUT 可以放在 `PrismBlade/Resources/LUTs/` 下。App 启动时会扫描该目录，并把可解析的 `.cube` 文件显示为本地内置 LUT。这个机制主要用于开发环境中的厂商 LUT，例如可能不可再分发的 Nikon N-Log 还原 LUT。

仓库会忽略本地 LUT payload：

- `PrismBlade/Resources/LUTs/*.cube`
- `PrismBlade/Resources/LUTs/*.3dl`
- `PrismBlade/Resources/LUTs/*.mga`
- `PrismBlade/Resources/LUTs/*.zip`

除非确认某个 LUT 资源允许再分发，否则只提交 `PrismBlade/Resources/LUTs/README.md`。本地 LUT 文件缺失或解析失败时会被静默隐藏，不会阻塞 App 启动。

### 监看界面

主界面通过左右浮动工具按钮操作：

- 滤镜图标：伪色。
- 斜线图标：斑马纹。
- 波形图标：切换 scope 模式。
- 滑杆图标：打开 LUT 管理。
- 放大镜图标：切换缩放模式。
- 齿轮图标：打开设置。

`v0.1.3` 中 scope 面板保持约 40% 屏幕宽度，避免 waveform / RGB Parade 大面积遮挡监看画面。当相机参数调整浮层打开时，scope 面板会向上避让，避免与底部控制区域重叠。

阶段 3 开始，主预览由 `MTKView` 绘制：`VideoFrame.pixelBuffer` 会通过 `CVMetalTextureCache` 桥接为 `MTLTexture`，再由 `PreviewShaders.metal` 采样到 drawable。阶段 4 会绑定 3D LUT texture，并在 fragment shader 中按 intensity 混合 LUT 输出。阶段 5 会把输入色彩编码和曝光辅助状态传入 shader。阶段 6 新增节流的 compute 旁路，读取同一份 source texture 并生成紧凑的 `ScopeData` bins。当前由 `MetalFrameProcessor` 统一决定显示状态：Rec.709 直接输出，N-Log 在启用 LUT 预览且选中 LUT 时应用 LUT，scope 默认跟随 LUT 后显示结果。

```text
source texture
  -> Rec.709 / N-Log / HLG 显示转换
  -> N-Log LUT 预览，若启用且已选择 LUT
  -> 伪色，若启用
  -> 斑马纹，若启用
  -> MTKView drawable
  -> 旁路：ScopeComputePass，若 scope 启用，分析颜色转换和 LUT 后结果
  -> ScopeData readback
  -> ScopePanel
```

Scope overlay 现在绘制 Metal compute 生成的 `ScopeData` bins。若 readback 延迟，SwiftUI 会继续显示上一份 scope 数据，同时预览渲染继续进行。

### LUT 导入

1. 点击 LUT 工具按钮。
2. 点击 `Import .cube`。
3. 选择 `.cube` 文件。
4. Parser 会校验文件，并把副本保存到 App documents 目录。
5. 在列表中选择导入的 LUT。
6. 启用 LUT 并调节强度。

当前 LUT 导入会真实解析和校验，经 `LUTStore` 缓存后由 `LUTPass` 上传为 Metal 3D texture，并在启用 LUT 时由 preview fragment shader 采样。这个 pass 只影响监看显示链路，不会修改原始 `CVPixelBuffer`。

### Mock 相机控制

底部控制条通过 `CameraCommandService` 连接 `MockCameraTransport`。这样 UI 已经走了后续真实 transport 也会使用的命令边界。

当前 Mock 控件包括：

- 曝光模式：`M`、`A`、`S`、`P`、`Auto`
- 光圈
- 快门
- ISO
- 白平衡
- 对焦模式
- 录制
- 拍照
- 对焦

点击参数值会打开紧凑调整浮层。调整浮层使用 Mock 能力表里的离散档位，因此 UI 不会生成相机不支持的任意值。

点击预览画面空白区域、再次点击同一参数，或点击浮层关闭按钮，都可以关闭当前调整浮层。这个状态由 `MonitorScreen` 持有，因此预览点击和 scope 布局避让使用的是同一份状态。

曝光模式会影响参数是否可调：

```text
M:    光圈、快门、ISO 可调
A:    光圈可调，快门锁定
S:    快门可调，光圈锁定
P:    光圈和快门锁定
Auto: 光圈、快门、ISO、白平衡锁定
```

被锁定的参数会置灰。点击时会在全局短提示区域显示原因，不打开滑块。相同规则会在 `MonitorSession`、`CameraCommandService` 和 `MockCameraTransport` 中重复校验。

设置页里还提供重新连接 Mock 相机和模拟断开的调试入口。

## 代码注释说明

Swift 文件里已经对关键实现点加了行内注释，重点说明后续审查时容易关心的边界：

- 为什么 App 启动后直接进入监看。
- 为什么帧输入和相机命令分开。
- 为什么 `VideoFrame` 使用 `CVPixelBuffer` 作为媒体边界。
- 为什么模拟帧源也生成 BGRA pixel buffer，而不是只保存动画相位。
- 为什么视频文件帧源使用 `AVAssetReader`，而不是把 `AVPlayer` 泄漏到帧源或 UI 层。
- 为什么 `CVPixelBuffer -> MTLTexture` 桥接集中在 Metal renderer 边界，而不是散落在 UI 或帧源里。
- 为什么主预览使用 `MTKView`，而 SwiftUI 继续负责工具栏、sheet 和底部控制条。
- 为什么 UI 提交中状态不进入 transport 层。
- 为什么曝光模式放在 `CameraState`，而不是纯 UI 状态。
- 为什么参数可用性同时包含 `isWritable` 和曝光模式规则。
- 为什么禁用参数会在 UI、command service 和 mock transport 三层校验。
- 为什么短提示从参数调整浮层中独立出来。
- 为什么相机参数选择状态由 `MonitorScreen` 持有。
- 为什么 Mock transport 也要校验能力表。
- 为什么原型阶段对超出 0-1 的 LUT 数据先 clamp。
- 为什么 LUT preview tint 仍作为 metadata 保留，而真实 LUT 渲染使用解析后的 `.cube` entries。
- 为什么可选本地厂商 LUT 在运行时发现，而不是硬编码成永远可见的内置项。
- 为什么 LUT 未启用或不可用时，`LUTPass` 使用 identity fallback resource。
- 为什么颜色转换要集中在 LUT、伪色、斑马纹和未来 scope 分析之前。
- 为什么生成的灰阶 / clipping 输入足够支撑阶段 5 自动化测试，但不能替代真实 Nikon 校准素材。
- 为什么 scope overlay 被限制为 40% 宽度。
- 为什么参数调整浮层打开时 scope overlay 要动态避让底部区域。

当前代码倾向于优先保证边界清晰和便于审查，而不是过早做性能优化。很多注释使用行内形式，是为了方便后续逐行检查真实相机和渲染边界。

## 验证情况

当前代码已通过：

```sh
plutil -lint PrismBlade.xcodeproj/project.pbxproj PrismBlade/Info.plist
```

并使用以下方式完成 Xcode 构建和测试：

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild build ...
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild build-for-testing ...
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test-without-building ...
```

iPhone 17 Pro Simulator 上 app 构建、测试构建和测试执行均已成功。正常 `.metal` 编译路径依赖已安装的 Metal Toolchain；在受限 shell 里，Xcode 可能看不到 cryptex 挂载的 Metal Toolchain，或打印 CoreSimulator 日志权限警告。如果沙盒无法访问 Metal Toolchain、CoreSimulator 或 `testmanagerd`，请直接从 Terminal 或 Xcode 运行构建和测试。

## 下一步计划

推荐按以下顺序继续开发：

1. 进入 `v0.2.1` 阶段 7 集成验证。
   - 使用可选本地 Nikon / N-Log LUT 做更多真实素材验证。
   - 除非确认授权允许再分发，否则继续把本地厂商 LUT 资源留在仓库之外。
   - 等真实灰卡、色卡、肤色和参考 scope 素材到位后，校准 N-Log / HLG、伪色、斑马纹、waveform 和 RGB Parade 行为。

2. 继续保持当前显示策略。
   - Rec.709 输入默认直出，不自动套 LUT。
   - N-Log 输入通过监看界面的 N-Log LUT 预览按钮切换选中 LUT。
   - 伪色和斑马纹只影响监看显示，不进入 scope 分析。

3. 深化 scope 验证。
   - 为更重的真实素材增加降采样选项。
   - 将 Luma waveform 和 RGB Parade 与参考截图对比。
   - 在 iPhone 12 Pro 真机上微调 bin 尺寸和分析间隔。
   - 增加隔帧分析，保护模拟器和 iPhone 12 Pro 性能。

4. 随每个渲染切片继续扩展测试。
   - 围绕真实 LUT fixtures 和边界情况增加更多 Metal 离屏测试。
   - 用 `CPUReference` 对比 Metal 输出。
   - 增加视频帧源和 scope compute 测试。

5. 准备真实相机通信适配层。
   - 保持 `CameraTransport` 稳定。
   - 增加 ImageCaptureCore、PTP、Network Bridge 的空 adapter 命名空间。
   - 不让 SwiftUI 暴露 Nikon、USB、PTP 或 `libgphoto2` 类型。

6. 后续再做硬件验证。
   - 使用 iPhone 12 Pro 验证 Nikon Z6III USB 模式。
   - 对比 ImageCaptureCore 的能力覆盖。
   - 决定生产路线使用 USB/PTP、Nikon iPhone 模式、Wi-Fi、USB-LAN 或中继服务。

## 参考文档

- [原型设计](PROTOTYPE_DESIGN.md)
- [技术文档 v0.2.1](TECHNICAL_SPEC_v0.2.1.md)
- [测试文档 v0.2.1](TEST_PLAN_v0.2.1.md)
- [技术文档 v0.1.3](TECHNICAL_SPEC_v0.1.3.md)
- [技术文档 v0.1.2](TECHNICAL_SPEC_v0.1.2.md)
- [技术文档 v0.1.1](TECHNICAL_SPEC_v0.1.1.md)
