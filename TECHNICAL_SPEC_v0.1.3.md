# PrismBlade v0.1.3 技术文档

代号：PrismBlade  
版本：v0.1.3  
日期：2026-05-13  
目标平台：iOS / iPhone 12 Pro  
首版运行目标：Xcode Simulator  
目标相机：Nikon Z6III  
当前阶段：监看功能原型，不实现真实 USB/PTP 相机通信

## 1. 版本定位

PrismBlade v0.1.3 是基于 `TECHNICAL_SPEC_v0.1.2.md` 的交互修复版本。本版本不改变 v0.1.2 的相机状态模型、曝光模式规则、Mock transport 边界或 LUT 功能范围，只修复代码审查中发现的几个未完全闭环的 UI 行为。

v0.1.3 的核心目标：

- 让禁用相机参数的点击提示在调整浮层关闭时仍然可见。
- 支持点击监看画面空白处关闭参数调整浮层。
- 避免 Scope 面板与参数调整浮层发生视觉重叠。

本版本暂不纳入自动化测试补齐。自动化测试仍作为后续工程质量任务保留，不阻塞 v0.1.3 的交互修复。

## 2. 与 v0.1.2 的主要变化

### UI 变化

- 新增全局短提示区域，用于展示禁用参数原因、相机动作结果和提交错误。
- 短提示不再依赖 `CameraParameterAdjuster` 是否打开。
- 参数调整浮层的打开状态上移到 `MonitorScreen` 管理。
- 点击预览画面空白处时关闭当前参数调整浮层。
- Scope overlay 根据参数调整浮层状态动态调整底部避让距离。

### 状态流变化

- `selectedParameter` 从 `CameraControlPanel` 的私有状态上移为 `MonitorScreen` 层级状态。
- `CameraControlPanel` 通过 `Binding<CameraParameter?>` 读写当前选中参数。
- `MonitorScreen` 根据 `selectedParameter != nil` 判断当前是否存在参数调整浮层。
- `lastUserMessage` 继续保留在 `MonitorSession`，但展示位置移动到主监看 overlay 层。

### 范围不变

- 不修改 `CameraTransport` 协议。
- 不修改 `CameraCommandService` 的曝光模式校验逻辑。
- 不修改 `MockCameraTransport` 的曝光模式二次校验逻辑。
- 不改变 v0.1.2 的曝光模式限制规则。
- 不实现真实 Nikon Z6III 连接。

## 3. v0.1.3 范围

### 必须实现

- 禁用参数点击时显示清晰可见的短提示。
- 短提示在没有参数调整浮层时也能显示。
- 点击禁用参数时不打开调整浮层。
- 点击预览画面空白处时关闭已打开的参数调整浮层。
- 再次点击同一参数时继续关闭调整浮层。
- Scope 面板在参数调整浮层打开时向上避让。
- Scope 面板在参数调整浮层关闭时恢复 v0.1.2 的紧凑位置。
- Scope 宽度继续保持当前主界面可用宽度的 `40%`。
- 底部常驻相机控制条继续保持默认可见。

### 继续保留

- 横屏优先监看体验。
- 设置页中的“允许竖屏拍摄/监看”开关。
- 模拟视频帧源。
- 伪色。
- 斑马纹。
- Luma waveform。
- RGB Parade。
- `.cube` LUT 导入、解析、校验、选择、开关和强度调节。
- 曝光模式显示：`M / A / S / P / Auto`。
- 根据曝光模式限制光圈、快门、ISO、白平衡和对焦的可用性。
- `CameraCommandService` 与 `MockCameraTransport` 的双层校验。

### 明确不做

- 不补齐自动化测试。
- 不连接真实 Nikon Z6III。
- 不实现 USB/PTP 数据传输。
- 不移植 `libgphoto2`。
- 不保存真实录制文件。
- 不做对焦峰值。
- 不做 histogram。
- 不做真实逐像素 3D LUT 渲染优化。

## 4. 问题与修复策略

### 4.1 禁用参数提示不可见

#### 当前问题

v0.1.2 中，点击禁用参数时会调用 `showDisabledParameterReason(for:)` 写入 `MonitorSession.lastUserMessage`，但提示文本只显示在参数调整浮层内部。

禁用参数点击流程是：

1. 用户点击禁用参数。
2. `CameraControlPanel` 将 `selectedParameter` 设为 `nil`。
3. `MonitorSession` 写入 `lastUserMessage`。
4. 参数调整浮层关闭。
5. 提示文本因为依附于浮层而不可见。

这不满足“禁用参数点击时给出简短提示”的交互要求。

#### 修复方案

在 `MonitorScreen` 增加独立的 `UserMessageBanner` overlay。

建议位置：

- 横屏：底部控制条上方、水平居中或靠左。
- 竖屏：底部控制条上方、避开安全区。
- 当 Scope 打开时，提示应优先显示在 Scope 与控制条之间或控制条上方，不遮挡参数值。

展示规则：

- 只要 `session.lastUserMessage != nil`，就显示短提示。
- 短提示不依赖 `selectedParameter`。
- 短提示使用轻量黑色半透明背景和黄色或白色文本。
- 文案单行优先，超长时允许 `lineLimit(2)`。
- 不弹全屏 alert，不阻断监看。

生命周期：

- 每次写入新消息时立即显示。
- 建议在 `MonitorSession` 中提供 `showUserMessage(_:)` 方法统一设置消息。
- 建议在 UI 层或 session 层增加自动清除逻辑，例如 2.5 秒后清空。
- 新消息到来时应重置自动清除计时。

推荐模型：

```swift
@Published private(set) var lastUserMessage: UserMessage?

struct UserMessage: Equatable, Identifiable {
    let id: UUID
    let text: String
    let kind: UserMessageKind
}

enum UserMessageKind {
    case info
    case warning
    case error
}
```

如果暂时不想引入新类型，也可以继续使用 `String?`，但需要保证展示位置脱离参数调整浮层。

### 4.2 点击画面空白处无法关闭调整浮层

#### 当前问题

v0.1.2 已实现“再次点击同一参数关闭浮层”，但没有实现“点击画面空白处关闭浮层”。原因是 `selectedParameter` 是 `CameraControlPanel` 的私有状态，`MonitorScreen` 和预览层无法访问或清空该状态。

#### 修复方案

将参数选择状态上移到 `MonitorScreen`：

```swift
struct MonitorScreen: View {
    @ObservedObject var session: MonitorSession
    @State private var activeSheet: MonitorSheet?
    @State private var selectedCameraParameter: CameraParameter?
}
```

`CameraControlPanel` 改为接收 binding：

```swift
struct CameraControlPanel: View {
    @ObservedObject var session: MonitorSession
    @Binding var selectedParameter: CameraParameter?
}
```

预览层增加空白点击关闭逻辑：

```swift
SyntheticPreviewView(...)
    .contentShape(Rectangle())
    .onTapGesture {
        selectedCameraParameter = nil
    }
```

交互要求：

- 点击预览画面关闭浮层。
- 点击左侧工具栏、右侧工具栏、底部控制条不应误触发预览关闭逻辑。
- 点击同一参数仍关闭浮层。
- 点击另一个可用参数时切换到对应调整浮层。
- 点击禁用参数时关闭浮层并显示短提示。

实现注意：

- 建议只把 tap gesture 加在 `SyntheticPreviewView` 上，而不是整个 `ZStack` 上，避免吞掉工具按钮和底部控制条交互。
- 如果 SwiftUI 事件传递导致 overlay 按钮被影响，应使用 `.allowsHitTesting` 或调整 gesture 位置解决。
- `CameraControlPanel` 不再持有 `@State private var selectedParameter`，避免父子状态不一致。

### 4.3 Scope 与调整浮层可能重叠

#### 当前问题

v0.1.2 中 Scope 面板只根据底部常驻控制条高度预留底部 padding。当参数调整浮层打开时，浮层会出现在控制条上方，Scope 面板可能与浮层重叠。

#### 修复方案

在 `MonitorScreen` 中根据 `selectedCameraParameter` 动态计算 Scope 底部避让距离。

建议增加布局常量：

```swift
private enum MonitorLayoutMetrics {
    static let controlBarBottomPadding: CGFloat = 8
    static let controlBarHeight: CGFloat = 60
    static let controlPanelSpacing: CGFloat = 8
    static let parameterAdjusterHeight: CGFloat = 118
    static let scopeToControlsGap: CGFloat = 10
}
```

推荐计算：

```swift
let hasAdjuster = selectedCameraParameter != nil
let controlStackHeight =
    MonitorLayoutMetrics.controlBarBottomPadding +
    MonitorLayoutMetrics.controlBarHeight +
    MonitorLayoutMetrics.scopeToControlsGap +
    (hasAdjuster
        ? MonitorLayoutMetrics.controlPanelSpacing + MonitorLayoutMetrics.parameterAdjusterHeight
        : 0)
```

Scope 使用动态 padding：

```swift
.padding(.bottom, controlStackHeight)
```

布局要求：

- 未打开调整浮层时，Scope 保持 v0.1.2 的底部紧凑位置。
- 打开调整浮层时，Scope 向上移动，避免遮挡和重叠。
- Scope 宽度仍为 `proxy.size.width * 0.4`。
- 横屏 Scope 高度建议继续保持 `120-150pt`。
- 竖屏 Scope 高度可继续略小，例如 `118pt`。

实现注意：

- 如果调整浮层高度随内容变化，应优先将浮层高度约束在稳定范围内。
- 可以给 `CameraControlPanel` 的调整浮层设置固定或最小高度，降低动态布局抖动。
- 如果后续加入更多相机参数，应重新评估底部控制区可用空间。

## 5. 更新后的 Monitor UI 结构

v0.1.3 的主监看结构建议如下：

```text
┌──────────────────────────────────────────────┐
│ Status Bar                                   │
├──────────────────────────────────────────────┤
│ Tool Rail     Preview Area        Tool Rail  │
│                                              │
│ Scope 40%                                    │
│                                              │
│              Short Message                   │
│        Parameter Adjuster, if opened         │
├──────────────────────────────────────────────┤
│ Mode | Aperture | Shutter | ISO | WB | Focus │
└──────────────────────────────────────────────┘
```

层级建议：

```text
MonitorScreen
  ├─ SyntheticPreviewView
  │   └─ tap empty preview -> selectedCameraParameter = nil
  ├─ StatusBar
  ├─ ScopePanel
  │   └─ bottom padding depends on selectedCameraParameter
  ├─ ToolRails
  ├─ UserMessageBanner
  │   └─ reads session.lastUserMessage
  └─ CameraControlPanel
      ├─ receives Binding<CameraParameter?>
      ├─ CameraParameterAdjuster
      └─ Bottom CameraControlBar
```

## 6. 数据与状态职责

### MonitorScreen

负责持有纯 UI 交互状态：

- 当前 sheet：`activeSheet`
- 当前相机参数调整目标：`selectedCameraParameter`

负责主布局计算：

- 是否竖屏布局。
- Scope 宽度。
- Scope 底部避让距离。
- 短提示位置。

### CameraControlPanel

负责底部相机控制：

- 展示曝光模式、光圈、快门、ISO、白平衡、对焦。
- 根据 `session.availability(for:)` 置灰不可用项。
- 点击可用参数时写入 `selectedParameter` binding。
- 点击禁用参数时清空 `selectedParameter` 并调用 `session.showDisabledParameterReason(for:)`。
- 调整浮层通过离散 slider 或等价控件提交参数。

### MonitorSession

负责业务状态和短提示状态：

- 维护 `MonitorSessionState`。
- 读取相机参数值。
- 计算参数可用性。
- 拒绝不可用参数提交。
- 记录短提示消息。

建议将所有用户可见提示统一经过一个方法：

```swift
func showUserMessage(_ text: String, kind: UserMessageKind = .info)
```

这样可以避免不同代码路径直接写 `lastUserMessage`，也方便后续加入自动清除、消息级别和可访问性支持。

## 7. 错误处理与提示规则

### 禁用参数点击

当用户点击当前曝光模式下不可用的参数：

- 不打开调整浮层。
- 如果已有调整浮层，应关闭。
- 不向 transport 提交命令。
- 显示短提示。

示例提示：

- `当前 A 模式下快门由相机控制`
- `当前 S 模式下光圈由相机控制`
- `Auto 模式下曝光参数由相机控制`
- `Auto 模式下白平衡由相机控制`

### 命令提交失败

当命令层返回错误：

- 不弹全屏 alert。
- 保持监看画面可用。
- 在 `UserMessageBanner` 中显示短错误。
- 对应参数的 `isSubmitting` 应恢复为 `false`。

### 相机动作反馈

录制、拍照、AF 动作完成后：

- 可以复用 `UserMessageBanner` 显示短反馈。
- 录制状态仍应以底部控制条 `REC / 停止` 状态为主。
- AF 成功提示不应阻断后续参数操作。

## 8. 手动验证计划

v0.1.3 不新增自动化测试，但必须完成以下手动验证：

1. 启动 App，确认构建通过并进入监看界面。
2. 确认底部控制条默认可见。
3. 确认 Scope 宽度仍约为屏幕宽度 `40%`。
4. 切换到 `A` 模式，点击快门，确认不打开调整浮层并显示短提示。
5. 切换到 `S` 模式，点击光圈，确认不打开调整浮层并显示短提示。
6. 切换到 `P` 模式，点击光圈或快门，确认不打开调整浮层并显示短提示。
7. 切换到 `Auto` 模式，点击 ISO 或白平衡，确认不打开调整浮层并显示短提示。
8. 在 `M` 模式点击光圈，确认调整浮层打开。
9. 在调整浮层打开时点击预览画面空白区域，确认浮层关闭。
10. 在调整浮层打开时再次点击同一参数，确认浮层关闭。
11. 在调整浮层打开时点击另一个可用参数，确认浮层切换。
12. 打开 Scope 后再打开参数调整浮层，确认 Scope 不与浮层重叠。
13. 关闭参数调整浮层，确认 Scope 回到紧凑位置。
14. 确认左侧工具栏、右侧工具栏和底部控制条点击不会被预览 tap gesture 误拦截。
15. 确认 LUT、伪色、斑马纹和 scope 切换仍可使用。

## 9. v0.1.3 完成标准

v0.1.3 完成时，应满足：

- 在 Xcode Simulator 构建通过。
- 禁用参数点击提示在无调整浮层时仍可见。
- 禁用参数点击不会打开调整浮层。
- 可用参数点击后仍可打开并使用离散调整浮层。
- 点击监看画面空白区域可以关闭参数调整浮层。
- 再次点击同一参数可以关闭参数调整浮层。
- Scope 面板不会遮挡底部控制条。
- Scope 面板不会与参数调整浮层重叠。
- Scope 面板宽度仍为当前可用宽度的 `40%` 左右。
- v0.1.2 已完成的曝光模式规则和 Mock transport 校验不回退。
- v0.1.1 的 LUT、伪色、斑马纹、Luma waveform、RGB Parade 基础功能不回退。

## 10. 后续工作

v0.1.3 之后建议优先推进：

1. 自动化测试补齐。
   - `ExposureMode` 参数可用性规则。
   - `CameraCommandService` 曝光模式校验。
   - `MockCameraTransport` 非法写入拒绝。
   - `.cube` parser 正常与异常路径。

2. 真实渲染管线。
   - 增加 `FrameProcessor`。
   - 引入 Core Image 或 Metal preview renderer。
   - 将当前 synthetic preview 迁移为 `FrameSource` 测试输入。

3. 真正的 LUT 应用。
   - 将 `.cube` 转为 3D texture 或 Core Image color cube。
   - 实现 LUT 强度混合。
   - 保持 LUT 只影响监看显示链路。

4. 真实 Scope 分析。
   - 从 pixel buffer 降采样。
   - 生成真实 luma waveform 和 RGB Parade。
   - 增加隔帧分析和性能保护。

5. 真实相机通信预研。
   - 验证 Nikon Z6III + iPhone 12 Pro USB 模式。
   - 验证 ImageCaptureCore 能力覆盖。
   - 评估 PTP、USB-LAN、Wi-Fi 或中继服务路线。

## 11. 与 v0.1.2 和原型设计的关系

本文档是 `TECHNICAL_SPEC_v0.1.2.md` 的交互修复版本，继承 `PROTOTYPE_DESIGN.md` 中的产品方向。v0.1.3 不改变“模拟器原型优先、真实相机通信后置”的原则，也不改变 v0.1.2 建立的底部相机控制条和曝光模式限制模型。
