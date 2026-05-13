# PrismBlade 中文说明

**PrismBlade** 是一个面向 Nikon Z6III 工作流的 iOS 相机监看 App 原型。当前版本为 `v0.1.3`，核心目标是在 Xcode Simulator 中跑通监看体验、图像辅助工具、LUT 导入流程、底部相机控制、曝光模式限制规则、Mock 相机通信边界，以及 v0.1.3 技术文档中定义的监看交互修复。

> 英文主版本：[README.md](README.md)

## 当前状态

当前仓库包含一个可在 iOS Simulator 构建的 SwiftUI 原型工程。它目前**不会连接真实 Nikon 相机**，**不会实现 USB/PTP 通信**，也**不会移植 `libgphoto2`**。

这个阶段的代码重点是建立可替换边界：

- `FrameSource` 负责提供画面帧，后续可以替换成真实 live view 源。
- `CameraTransport` 负责相机通信，后续可以替换成 ImageCaptureCore、PTP 或网络桥接实现。
- `CameraCommandService` 在命令进入 transport 前做参数校验。
- LUT 解析和仓库逻辑与监看 UI 分离。
- SwiftUI 负责布局和状态展示；当前画面仍是合成预览，不是最终 Metal/Core Image 渲染管线。

## 已实现功能

- 横屏优先的监看主界面。
- 模拟帧源：包含移动色块和亮度 ramp。
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

## 尚未实现

- 真实 Nikon Z6III 连接。
- USB/PTP 通信。
- ImageCaptureCore 接入。
- `libgphoto2` 接入。
- 真实视频文件播放。
- Metal 预览渲染器。
- Core Image / Metal 3D LUT 采样。
- 基于真实像素的伪色和斑马纹处理。
- 基于真实 pixel buffer 的示波器分析。
- 真实相机曝光模式读取。
- 真实 Nikon 能力表解析。
- Histogram。
- 对焦峰值。
- 真实录制或拍照文件保存。

## 环境要求

- 安装 Xcode 的 macOS。
- 支持 iOS 17+ 项目的 Xcode 版本。
- iOS Simulator runtime。

当前已验证环境：

- Xcode `26.4.1`
- iOS Simulator generic build destination
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

Imaging
  -> LUTParser
  -> LUTRepository
  -> Synthetic preview overlays

Camera
  -> CameraCommandService
  -> CameraTransport
  -> MockCameraTransport
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

并使用以下方式完成 Xcode 构建：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ...
```

iOS Simulator 构建已成功。当前沙盒中 Xcode 可能会打印 CoreSimulator 日志权限警告，但这些警告没有阻止编译、链接和 app bundle 生成。

## 下一步计划

推荐按以下顺序继续开发：

1. 增加真实渲染管线。
   - 引入 `FrameProcessor`。
   - 将合成画面逻辑放到 renderer-facing abstraction 后面。
   - 增加 Core Image 或 Metal 预览渲染。

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

5. 增加 `VideoFileFrameSource`。
   - 使用 AVFoundation 读取内置或用户选择的视频。
   - 保留 `SimulatedFrameSource` 作为默认 fallback。

6. 增加测试。
   - `.cube` parser 单元测试。
   - Mock transport 参数校验测试。
   - 曝光模式参数锁定规则测试。
   - Monitor state toggle 测试。
   - 监看页、设置页、LUT 导入错误状态和底部相机控制条的 UI smoke test。

7. 准备真实相机通信适配层。
   - 保持 `CameraTransport` 稳定。
   - 增加 ImageCaptureCore、PTP、Network Bridge 的空 adapter 命名空间。
   - 不让 SwiftUI 暴露 Nikon、USB、PTP 或 `libgphoto2` 类型。

8. 后续再做硬件验证。
   - 使用 iPhone 12 Pro 验证 Nikon Z6III USB 模式。
   - 对比 ImageCaptureCore 的能力覆盖。
   - 决定生产路线使用 USB/PTP、Nikon iPhone 模式、Wi-Fi、USB-LAN 或中继服务。

## 参考文档

- [原型设计](PROTOTYPE_DESIGN.md)
- [技术文档 v0.1.3](TECHNICAL_SPEC_v0.1.3.md)
- [技术文档 v0.1.2](TECHNICAL_SPEC_v0.1.2.md)
- [技术文档 v0.1.1](TECHNICAL_SPEC_v0.1.1.md)
