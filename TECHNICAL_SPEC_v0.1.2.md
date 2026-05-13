# PrismBlade v0.1.2 技术文档

代号：PrismBlade  
版本：v0.1.2  
日期：2026-05-13  
目标平台：iOS / iPhone 12 Pro  
首版运行目标：Xcode Simulator  
目标相机：Nikon Z6III  
当前阶段：监看功能原型，不实现真实 USB/PTP 相机通信

## 1. 版本定位

PrismBlade v0.1.2 是基于 v0.1.1 的监看交互修订版本。本版本不改变“先做模拟器可运行原型，不接真实相机”的技术边界，重点调整监看主界面的信息密度和相机参数控制方式。

v0.1.2 的核心目标：

- 降低 Scope 面板对监看画面的遮挡。
- 将相机控制从右侧滑出面板改为底部常驻控制条。
- 支持点击参数值后用离散滑块调整光圈、快门、ISO、白平衡和对焦。
- 增加曝光模式显示：`M / A / S / P / Auto`。
- 根据曝光模式限制光圈、快门、ISO 等参数的可调性。
- 保持 `CameraTransport` 边界稳定，为后续真实相机读取曝光模式和能力表预留空间。

v0.1.2 仍然不实现 Nikon Z6III 实机连接、USB/PTP 传输、ImageCaptureCore 适配或 `libgphoto2` 移植。

## 2. 与 v0.1.1 的主要变化

### UI 变化

- Scope 面板宽度从大面积底部覆盖改为当前可用宽度的 `40%`。
- Scope 面板仍支持 Luma waveform 和 RGB Parade，但默认不再横向铺满。
- 右侧相机控制面板取消作为主交互入口。
- 底部新增常驻相机控制条，直接显示：
  - 曝光模式
  - 光圈
  - 快门
  - ISO
  - 白平衡
  - 对焦
- 点击某个参数值后，底部弹出对应的离散滑块调整面板。

### 状态模型变化

- `CameraState` 增加曝光模式字段。
- `CameraParameter` 增加曝光模式参数。
- 参数可写状态拆分为：
  - 相机基础能力：该参数是否由相机支持写入。
  - 当前曝光模式可用性：该参数在当前模式下是否允许用户调整。
- `CameraCommandService` 和 `MockCameraTransport` 都需要校验曝光模式限制，不能只依赖 UI 置灰。

### Mock 变化

- `MockCameraTransport` 支持切换曝光模式。
- Mock 能力表增加 `ExposureMode`。
- Mock 在当前曝光模式不允许调整某个参数时，拒绝对应写入并返回明确错误。

## 3. v0.1.2 范围

### 必须实现

- Scope 面板宽度调整为主界面可用宽度的 `40%`。
- 底部常驻相机控制条。
- 曝光模式显示：`M / A / S / P / Auto`。
- Mock 曝光模式切换。
- 光圈、快门、ISO、白平衡、对焦的点击调整入口。
- 光圈、快门、ISO 使用离散滑块或 step slider。
- 白平衡使用离散滑块、segmented control 或菜单。
- 对焦使用模式选择和单次 AF 操作，不做连续滑块。
- 根据曝光模式限制参数可用性。
- 禁用参数点击时给出简短提示。
- Mock transport 对曝光模式限制进行二次校验。

### 继续保留

- 横屏优先监看体验。
- 设置页中的“允许竖屏拍摄/监看”开关。
- 模拟视频帧源。
- 伪色。
- 斑马纹。
- Luma waveform。
- RGB Parade。
- `.cube` LUT 导入、解析、校验、选择、开关和强度调节。
- `FrameSource` 抽象。
- `CameraTransport` 抽象。

### 明确不做

- 不连接真实 Nikon Z6III。
- 不实现 USB/PTP 数据传输。
- 不移植 `libgphoto2`。
- 不保存真实录制文件。
- 不做对焦峰值。
- 不做 histogram。
- 不做真实逐像素 3D LUT 渲染优化。
- 不实现真实相机曝光模式读取，只在 Mock 层模拟。

## 4. 总体架构

v0.1.2 延续 v0.1.1 架构，主要改变 UI 层和 Camera domain 的状态表达。

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

- UI 不直接判断 Nikon USB/PTP 细节。
- UI 可以根据 domain 状态置灰控件，但命令层仍必须再次校验。
- 曝光模式和参数能力属于相机状态/能力，不属于纯 UI 状态。
- Scope 尺寸属于 `MonitorScreen` 布局，不影响 `ScopeAnalyzer` 后续实现。

## 5. 目录建议

v0.1.2 建议把相机控制组件从“面板”语义改成“底部控制条 + 调整浮层”。

```text
PrismBlade/
  Screens/
    Monitor/
      MonitorScreen.swift
      MonitorOverlayView.swift
      MonitorToolbar.swift
      ScopePanel.swift
      CameraControlBar.swift
      CameraParameterAdjuster.swift
  Domain/
    MonitorSession.swift
    MonitorModels.swift
    CameraModels.swift
    LUTModels.swift
  Camera/
    CameraTransport.swift
    CameraCommandService.swift
    MockCameraTransport.swift
```

如果当前工程仍使用 `CameraControlPanel.swift` 文件名，可以先在原文件内重构为 `CameraControlBar` 和调整浮层；等实现稳定后再拆文件。

## 6. 核心数据模型

### MonitorSessionState

```swift
struct MonitorSessionState {
    var connection: ConnectionState
    var camera: CameraState
    var monitor: MonitorState
    var orientation: OrientationState
    var lut: LUTState
}
```

### CameraState

v0.1.2 增加 `exposureMode`。

```swift
struct CameraState {
    var exposureMode: CameraValue<ExposureMode>
    var iso: CameraValue<String>
    var shutter: CameraValue<String>
    var aperture: CameraValue<String>
    var whiteBalance: CameraValue<String>
    var focusMode: CameraValue<String>
    var isRecording: Bool
    var batteryLevel: Int?
    var storageRemaining: StorageInfo?
}
```

### ExposureMode

```swift
enum ExposureMode: String, CaseIterable, Identifiable {
    case manual = "M"
    case aperturePriority = "A"
    case shutterPriority = "S"
    case program = "P"
    case auto = "Auto"
}
```

含义：

- `M`：手动曝光。
- `A`：光圈优先。
- `S`：快门优先。
- `P`：程序自动。
- `Auto`：全自动。

后续真实相机版本必须从相机状态读取曝光模式，而不是由 App 自行推断。

### CameraValue

`CameraValue` 需要继续表达当前值、可选项、基础可写性和提交状态。

```swift
struct CameraValue<Value: Equatable> {
    var current: Value
    var options: [Value]
    var isWritable: Bool
    var isSubmitting: Bool
}
```

注意：`isWritable` 只代表相机能力层面的可写，不代表当前曝光模式下可用。

### CameraParameterAvailability

建议增加一个派生模型或方法，用来表达当前曝光模式下是否可调。

```swift
struct CameraParameterAvailability {
    var isEnabled: Bool
    var reason: String?
}
```

示例方法：

```swift
func availability(
    for parameter: CameraParameter,
    camera: CameraState
) -> CameraParameterAvailability
```

该方法可放在 `MonitorSession`、`CameraState` extension 或单独的 domain helper 中。

## 7. 曝光模式限制规则

v0.1.2 先采用以下规则。后续接入真实相机时，可根据 Nikon Z6III 真实能力和 Auto ISO 状态细化。

```text
M:
  Aperture: enabled
  Shutter: enabled
  ISO: enabled
  White Balance: enabled
  Focus: enabled

A:
  Aperture: enabled
  Shutter: disabled, camera-controlled
  ISO: enabled in v0.1.2 mock
  White Balance: enabled
  Focus: enabled

S:
  Aperture: disabled, camera-controlled
  Shutter: enabled
  ISO: enabled in v0.1.2 mock
  White Balance: enabled
  Focus: enabled

P:
  Aperture: disabled, camera-controlled
  Shutter: disabled, camera-controlled
  ISO: enabled in v0.1.2 mock
  White Balance: enabled
  Focus: enabled

Auto:
  Aperture: disabled
  Shutter: disabled
  ISO: disabled
  White Balance: disabled in v0.1.2 mock
  Focus: enabled
```

交互要求：

- 禁用项在底部控制条中应明显置灰。
- 点击禁用项时不打开调整浮层。
- 点击禁用项时显示简短提示，例如：
  - `当前 A 模式下快门由相机控制`
  - `当前 S 模式下光圈由相机控制`
  - `Auto 模式下曝光参数由相机控制`
- `CameraCommandService` 提交命令前应检查当前状态。
- `MockCameraTransport` 应作为最后防线再次拒绝非法写入。

## 8. Monitor UI 结构

### MonitorScreen

默认横屏布局：

- 中央全屏预览。
- 顶部轻量状态条。
- 左侧工具按钮组。
- 右侧工具按钮组保留设置、LUT、缩放等工具入口。
- Scope overlay 改为较小面板，宽度约为可用宽度 `40%`。
- 底部常驻相机控制条。
- 参数调整浮层从底部控制条上方弹出。

建议布局：

```text
┌──────────────────────────────────────────────┐
│ Status Bar                                   │
├──────────────────────────────────────────────┤
│ Tool Rail     Preview Area        Tool Rail  │
│                                              │
│ Scope 40%                                    │
│                                              │
├──────────────────────────────────────────────┤
│ Mode | Aperture | Shutter | ISO | WB | Focus │
└──────────────────────────────────────────────┘
```

### ScopePanel

v0.1.2 Scope 布局要求：

- 宽度为当前主界面可用宽度的 `40%`。
- 高度保持紧凑，建议横屏 `120-150pt`。
- 位置建议底部左侧或底部居中偏左。
- 不能遮挡底部相机控制条。
- 仍支持 `off / lumaWaveform / rgbParade`。
- 不要求 waveform 和 RGB Parade 同屏。

### CameraControlBar

底部控制条要求：

- 常驻显示，不需要用户展开。
- 高度建议 `56-68pt`。
- 每个参数使用紧凑单元格显示 label 和 value。
- 当前曝光模式显示在最左侧或最靠近曝光参数的位置。
- 录制/拍照动作可以保留在控制条右侧，或作为二级入口；v0.1.2 优先保证曝光参数操作。

建议字段：

```text
M | f/2.8 | 1/50 | ISO 400 | 5600K | AF-S
```

### CameraParameterAdjuster

点击参数后出现调整浮层。

要求：

- 使用离散选项，不使用连续任意数值。
- 横向滑块或 step slider 均可。
- 当前值应高亮。
- 滑动到新值后提交到 `CameraCommandService`。
- 提交中状态应在当前参数单元格或浮层中可见。
- 点击画面空白处或再次点击同一参数可关闭浮层。

各参数建议：

- 曝光模式：离散 segmented control 或横向 picker。
- 光圈：离散滑块，参考镜头光圈档位。
- 快门：离散滑块，参考相机快门档位。
- ISO：离散滑块，参考相机 ISO 档位。
- 白平衡：离散滑块、segmented control 或菜单。
- 对焦：模式选择 + AF action 按钮。

## 9. CameraTransport 与 Mock 行为

### CameraTransport

接口仍保持抽象，不暴露 Nikon、USB、PTP 或 `libgphoto2` 类型。

```swift
protocol CameraTransport {
    func connect() async throws
    func disconnect() async
    func currentState() async throws -> CameraState
    func setValue(_ value: String, for parameter: CameraParameter) async throws -> CameraState
    func trigger(_ action: CameraAction) async throws -> CameraState
}
```

如果实现泛型 `setValue<T>`，也必须保证参数和值类型在 transport 边界内可校验。

### Mock 能力表

```text
Exposure Mode: M, A, S, P, Auto
ISO: 100, 200, 400, 800, 1600, 3200, 6400
Shutter: 1/25, 1/50, 1/60, 1/100, 1/125, 1/250
Aperture: f/1.8, f/2.0, f/2.8, f/4.0, f/5.6, f/8.0
WB: Auto, 3200K, 4300K, 5600K, 6500K
Focus: AF-S, AF-C, MF, Touch Focus placeholder
Actions: Record, Capture, Half Press, Focus
```

### Mock 错误

新增错误类型或错误 case：

```swift
case parameterLockedByExposureMode(parameter: CameraParameter, mode: ExposureMode)
```

错误展示：

- UI 不弹全屏 alert。
- 底部控制条或状态提示区域显示短消息。
- 提示应说明是哪一个曝光模式导致参数不可调。

## 10. 持久化

v0.1.2 继续持久化 v0.1.1 的设置：

- 竖屏开关。
- 最近选择的 LUT。
- LUT 强度。
- zebra threshold。
- scope mode。
- scope opacity。

v0.1.2 新增建议持久化：

- 最近一次 Mock 曝光模式。
- 最近一次打开的底部调整参数不需要持久化。

说明：

- 真实相机接入后，曝光模式应以相机状态为准。
- 如果持久化 Mock 曝光模式，只能用于模拟器体验，不应覆盖真实相机读取值。

## 11. 错误处理

### 参数禁用

当用户点击当前曝光模式下不可用的参数：

- 不打开调整浮层。
- 显示简短状态提示。
- 不向 transport 提交命令。

当命令层收到不可用参数写入：

- `CameraCommandService` 返回错误。
- `MockCameraTransport` 也返回错误。
- UI 显示同类短提示。

### 连接错误

继续沿用 v0.1.1：

- 未连接时提交命令应返回错误。
- Mock 断开应更新状态栏和底部控制条可用性。
- 连接错误不应频繁打断监看界面。

### LUT 和视频错误

继续沿用 v0.1.1 规则。

## 12. 测试计划

### 单元测试

- `ExposureMode` 参数可用性规则。
- `M` 模式下光圈、快门、ISO 可写。
- `A` 模式下快门不可写。
- `S` 模式下光圈不可写。
- `P` 模式下光圈和快门不可写。
- `Auto` 模式下曝光参数不可写。
- Mock transport 拒绝曝光模式锁定参数。
- Mock transport 允许切换曝光模式。
- `.cube` parser 正常文件。
- `.cube` parser 数据数量不匹配。
- `.cube` parser 非法浮点数。

### UI / 交互测试

- Scope 面板宽度约为主界面可用宽度的 `40%`。
- 底部相机控制条默认可见。
- 点击光圈、快门、ISO、WB 后出现调整浮层。
- 点击禁用参数不出现调整浮层。
- 切换曝光模式后控制条置灰状态即时更新。
- Mock 参数提交时显示 loading 或短暂提交状态。
- 设置页仍可修改竖屏开关、zebra threshold、scope opacity。

### 手动验证

- App 启动默认横屏。
- Scope 不再大面积遮挡画面。
- 底部控制条显示曝光模式和核心参数。
- `M` 模式下可调光圈、快门和 ISO。
- `A` 模式下快门不可调，光圈可调。
- `S` 模式下光圈不可调，快门可调。
- `P` 模式下光圈和快门不可调。
- `Auto` 模式下曝光参数不可调。
- 禁用项提示文案清晰。
- LUT、伪色、斑马纹和 scope 切换仍可使用。

## 13. v0.1.2 完成标准

v0.1.2 完成时，应满足：

- 在 Xcode Simulator 可启动并构建通过。
- 默认进入横屏监看体验。
- Scope 面板宽度缩小为当前可用宽度的 `40%` 左右。
- 相机控制从右侧面板改为底部常驻控制条。
- 底部控制条显示曝光模式、光圈、快门、ISO、白平衡和对焦。
- 点击可用参数后可以通过离散滑块或等价控件调整。
- 当前曝光模式下不可用的参数会置灰并阻止提交。
- Mock transport 支持曝光模式切换和模式限制校验。
- v0.1.1 的 LUT、伪色、斑马纹、Luma waveform、RGB Parade 基础功能不回退。
- 真实通信相关代码仍只停留在接口和命名空间，不包含具体 USB/PTP 实现。

## 14. 后续工作

v0.1.2 之后建议优先推进：

1. 真实渲染管线。
   - 增加 `FrameProcessor`。
   - 引入 Core Image 或 Metal preview renderer。
   - 将当前 synthetic preview 迁移为 `FrameSource` 测试输入。

2. 真正的 LUT 应用。
   - 将 `.cube` 转为 3D texture 或 Core Image color cube。
   - 实现 LUT 强度混合。
   - 保持 LUT 只影响监看显示链路。

3. 真实 Scope 分析。
   - 从 pixel buffer 降采样。
   - 生成真实 luma waveform 和 RGB Parade。
   - 增加隔帧分析和性能保护。

4. `VideoFileFrameSource`。
   - 使用 AVFoundation 播放本地测试视频。
   - 保留 `SimulatedFrameSource` 作为 fallback。

5. 真实相机通信预研。
   - 验证 Nikon Z6III + iPhone 12 Pro USB 模式。
   - 验证 ImageCaptureCore 能力覆盖。
   - 评估 PTP、USB-LAN、Wi-Fi 或中继服务路线。

## 15. 与 v0.1.1 和原型设计的关系

本文档是 `TECHNICAL_SPEC_v0.1.1.md` 的交互修订版本，继承 `PROTOTYPE_DESIGN.md` 中的产品方向。v0.1.2 主要调整监看界面的控制布局和相机曝光模式模型，不改变当前阶段“模拟器原型优先、真实相机通信后置”的原则。

