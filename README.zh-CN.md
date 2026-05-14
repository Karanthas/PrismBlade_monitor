# PrismBlade 中文说明

**PrismBlade** 是一个面向 Nikon Z6III 工作流的 iOS 相机监看 App 原型。当前分支正在按 `v0.2.1` Metal-first 计划推进。阶段 2 已完成：项目现在有真实 `CVPixelBuffer` 媒体帧模型、BGRA 模拟帧源、`AVAssetReader` 视频文件帧源，以及覆盖帧模型和视频读取路径的 XCTest。

> 英文主版本：[README.md](README.md)

## 当前状态

当前仓库包含一个可在 iOS Simulator 构建的 SwiftUI 原型工程，并完成了 `v0.2.1` 阶段 2 的媒体帧输入基础。它目前**不会连接真实 Nikon 相机**，**不会实现 USB/PTP 通信**，也**不会移植 `libgphoto2`**。

这个阶段的代码重点是建立可替换边界：

- `FrameSource` 负责提供真实 `CVPixelBuffer` 媒体帧，后续可以替换成真实 live view 源。
- `SimulatedFrameSource` 现在生成 BGRA pixel buffer，不再只输出动画相位。
- `VideoFileFrameSource` 使用 `AVAssetReader` 读取本地视频，并输出同一套 `VideoFrame`。
- `CameraTransport` 负责相机通信，后续可以替换成 ImageCaptureCore、PTP 或网络桥接实现。
- `CameraCommandService` 在命令进入 transport 前做参数校验。
- LUT 解析和仓库逻辑与监看 UI 分离。
- SwiftUI 负责布局和状态展示；当前画面仍是过渡性的合成预览，不是最终 Metal 渲染管线。
- `PrismBladeTests` 负责可重复 fixtures 和 CPU reference，后续 Metal pass 可以拿它们做确定性的结果对比。

## 已实现功能

- 横屏优先的监看主界面。
- 模拟帧源：生成真实 BGRA `CVPixelBuffer`，内容包含移动色块和亮度 ramp。
- 媒体帧模型：`VideoFrame` 携带 `sequence`、`CMTime` timestamp、`FrameFormat`、`CVPixelBuffer` 和相机 metadata。
- 视频文件帧源：`VideoFileFrameSource` 使用 `AVAssetReader` 读取本地 `.mov` / 视频资源并输出 `CVPixelBuffer`。
- 初步色彩编码识别：支持通过 hint、`REC709` / `NLOG` / `HLG` 文件名约定和视频 metadata 标记识别 `Rec.709`、`N-Log`、`HLG`。
- 顶部状态栏：连接状态、输入格式、帧率、LUT 状态、曝光工具、电量和存储占位。
- 左右两侧浮动工具按钮。
- 伪色开关。
- 斑马纹开关和阈值设置。
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
- LUT 管理：内置描述项和 `.cube` 文件导入。
- `.cube` 解析器：支持 `TITLE`、`LUT_3D_SIZE`、`DOMAIN_MIN`、`DOMAIN_MAX`、注释和 RGB 数据行校验。
- LUT metadata 通过 JSON index 持久化到 App documents 目录。
- 设置页：竖屏监看开关、斑马纹阈值、scope 透明度、scope 模式和 Mock 调试入口。
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
- `v0.2.1` 阶段 1-2 XCTest target：
  - 小尺寸 BGRA `CVPixelBuffer` 测试图生成。
  - 合法和非法 `.cube` LUT fixture 生成。
  - luma、LUT 采样、斑马纹 mask、waveform bins 的 CPU reference helper。
  - `LUTParser`、`CameraExposureRules`、`CameraCommandService`、`MockCameraTransport` 单元测试。
  - `VideoFrame` 媒体帧模型测试。
  - `SimulatedFrameSource` 真实 pixel buffer 输出测试。
  - 使用临时生成 `.mov` 的 `VideoFileFrameSource` 读取、时间戳和色彩编码测试。

## 尚未实现

- 真实 Nikon Z6III 连接。
- USB/PTP 通信。
- ImageCaptureCore 接入。
- `libgphoto2` 接入。
- 用户可见的真实视频文件播放入口。
- Metal 预览渲染器。
- Core Image / Metal 3D LUT 采样。
- 基于真实像素的伪色和斑马纹处理。
- 基于真实 pixel buffer 的示波器分析。
- 真实相机曝光模式读取。
- 真实 Nikon 能力表解析。
- Metal 离屏渲染测试。
- 基于真实像素的 scope compute 测试。
- Histogram。
- 对焦峰值。
- 真实录制或拍照文件保存。

## 环境要求

- 安装 Xcode 的 macOS。
- 支持 iOS 17+ 项目的 Xcode 版本。
- iOS Simulator runtime。

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
  Imaging/
    LUTParser.swift
    LUTRepository.swift
  Screens/
    Monitor/
      MonitorScreen.swift
      SyntheticPreviewView.swift
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

Imaging
  -> LUTParser
  -> LUTRepository
  -> Synthetic preview overlays

Camera
  -> CameraCommandService
  -> CameraTransport
  -> MockCameraTransport

Tests
  -> PixelBufferFixtureFactory
  -> CubeFixtureFactory
  -> CPUReference
  -> 帧源、LUT 和相机领域规则的 XCTest
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

### 运行阶段 2 测试

阶段 2 的可见变化很小，重点是媒体帧模型和帧源边界已经切到真实 `CVPixelBuffer`。你要验证的效果是：测试 target 能构建，fixtures 能生成，模拟帧源和视频文件帧源自动化测试能全部通过。

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

当前阶段 2 测试共有 31 个。成功时终端会逐个打印测试用例，并以 `TEST EXECUTE SUCCEEDED` 结束。

### 本地真实素材

真实 Nikon / HLG / N-Log 视频样本统一放在仓库根目录的 `material/` 下。该目录已经加入 `.gitignore`，只用于本地开发和手动验证，不随代码提交。

当前约定文件名：

- `material/REC709.MOV`
- `material/NLOG.MOV`
- `material/HLG.MOV`

自动化测试不依赖这些真实素材；阶段 2 测试会临时生成小型 `.mov` fixture 来验证 `AVAssetReader`。后续阶段 5/7 的颜色转换和真实素材手动验证会优先使用 `material/` 中的文件。

### 监看界面

主界面通过左右浮动工具按钮操作：

- 滤镜图标：伪色。
- 斜线图标：斑马纹。
- 波形图标：切换 scope 模式。
- 滑杆图标：打开 LUT 管理。
- 放大镜图标：切换缩放模式。
- 齿轮图标：打开设置。

`v0.1.3` 中 scope 面板保持约 40% 屏幕宽度，避免 waveform / RGB Parade 大面积遮挡监看画面。当相机参数调整浮层打开时，scope 面板会向上避让，避免与底部控制区域重叠。

### LUT 导入

1. 点击 LUT 工具按钮。
2. 点击 `Import .cube`。
3. 选择 `.cube` 文件。
4. Parser 会校验文件，并把副本保存到 App documents 目录。
5. 在列表中选择导入的 LUT。
6. 启用 LUT 并调节强度。

当前 LUT 显示仍是轻量占位：导入的 LUT 会被真实解析和校验，但预览层暂时使用 descriptor tint 作为视觉提示。下一步应在渲染管线中实现真正的 3D LUT 采样。

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
- 为什么 UI 提交中状态不进入 transport 层。
- 为什么曝光模式放在 `CameraState`，而不是纯 UI 状态。
- 为什么参数可用性同时包含 `isWritable` 和曝光模式规则。
- 为什么禁用参数会在 UI、command service 和 mock transport 三层校验。
- 为什么短提示从参数调整浮层中独立出来。
- 为什么相机参数选择状态由 `MonitorScreen` 持有。
- 为什么 Mock transport 也要校验能力表。
- 为什么原型阶段对超出 0-1 的 LUT 数据先 clamp。
- 为什么 LUT preview tint 只是临时 UI 占位。
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
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild build-for-testing ...
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test-without-building ...
```

iPhone 17 Simulator 上测试构建和测试执行均已成功。在受限 shell 里，Xcode 可能会打印 CoreSimulator 日志权限警告；如果沙盒无法访问 CoreSimulator 或 `testmanagerd`，请直接从 Terminal 或 Xcode 运行测试。

## 下一步计划

推荐按以下顺序继续开发：

1. 进入 `v0.2.1` 阶段 3：Metal 预览最小闭环。
   - 引入 `FrameProcessor`。
   - 将 `VideoFrame.pixelBuffer` 通过 `CVMetalTextureCache` 桥接到 Metal texture。
   - 增加 `MTKView` 承载的 Metal 预览渲染。

2. 将 LUT 应用到真实像素。
   - 把解析后的 `.cube` 数据转换为 3D texture 或 Core Image color cube。
   - 使用原始画面与 LUT 后画面混合实现强度控制。
   - LUT 只影响监看显示，不改变原始帧。

3. 替换当前占位曝光 overlay。
   - 根据 luma 实现伪色。
   - 根据阈值或范围 mask 实现斑马纹。
   - 保持显示 overlay/pass 的设计。

4. 实现真实 scope 分析。
   - 对帧做降采样。
   - 根据像素值生成 Luma waveform。
   - 根据 RGB 通道值生成 RGB Parade。
   - 增加隔帧分析，保护模拟器和 iPhone 12 Pro 性能。

5. 随每个渲染切片继续扩展测试。
   - 增加 Metal 离屏测试。
   - 用 `CPUReference` 对比 Metal 输出。
   - 增加视频帧源和 scope compute 测试。

6. 准备真实相机通信适配层。
   - 保持 `CameraTransport` 稳定。
   - 增加 ImageCaptureCore、PTP、Network Bridge 的空 adapter 命名空间。
   - 不让 SwiftUI 暴露 Nikon、USB、PTP 或 `libgphoto2` 类型。

7. 后续再做硬件验证。
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
