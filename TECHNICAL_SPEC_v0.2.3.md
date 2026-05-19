# PrismBlade v0.2.3 技术文档

代号：PrismBlade
版本：v0.2.3
日期：2026-05-18
目标平台：iOS / iPhone 12 Pro
运行目标：Xcode Simulator 优先，保留真机验证空间
目标相机：Nikon Z6III
当前阶段：Scope 可读性校正，重点改善亮度波形图显示

## 1. 版本定位

PrismBlade v0.2.3 是 v0.2.2 曝光链路修正之后的 scope 可读性版本。v0.2.2 负责重新定义 raw input、preview output 和 analysis signal，修正 N-Log / LUT 的曝光问题；v0.2.3 不重新改变该曝光链路，只改善 scope 生成和绘制方式，让亮度波形图在真实素材上更清楚、更像监视器工具，而不是淡、糊、过小或难以判断。

v0.2.3 的核心目标：

- 亮度波形图改用白色显示。
- 提高 waveform / RGB Parade 的 bins 分辨率。
- 改善 bins 归一化，避免弱信号被最亮密集区域压没。
- 改善 `ScopePanel` 绘制策略，让低密度波形也可见。
- 重新设计 scope 面板位置和紧凑尺寸，在不抢占监看画面的前提下改善可读性。
- 在 scope 标题中明确显示分析源，例如 Raw 或 LUT。
- 支持 scope 面板拖动，并在拖动结束后吸附到安全停靠位。
- 保持 scope 只作为监看辅助，不改变预览画面、源帧或 LUT 输出。

v0.2.3 不处理：

- N-Log / LUT 曝光链路修正。
- Nikon N-Log 曲线最终校准。
- HLG HDR/SDR 映射。
- 真实相机 live view。
- USB/PTP 通信。
- waveform 专业标尺的最终校准。

## 2. 当前问题

v0.2.1/v0.2.2 的 scope 已经由 Metal compute 生成真实 bins，但真实素材上仍存在可读性问题：

- `ScopeComputePass.Configuration.default` 使用 `96 x 64` bins，横向和纵向分辨率偏低。
- compute sample 默认上限为 `320 x 180`，对 4K/1080p 素材下采样过重。
- `normalizedBins` 使用线性最大值归一化，少量高密度区域会压低其他波形点。
- `ScopePanel` 以矩形 cell 填充，低强度点不够亮，波形层次不明显。
- 亮度 waveform 当前为绿色，容易和 RGB Parade 的 green channel 视觉含义混淆。
- 主屏 scope 宽度固定为画面宽度 40%，在部分真实素材上横向分布略挤，但大幅放大会遮挡监看主体。
- scope 标题只显示模式，没有明确当前分析的是 raw signal 还是 LUT/display signal。

## 3. 设计原则

v0.2.3 固定以下原则：

1. 亮度 waveform 使用白色显示。
2. RGB Parade 保持 red / green / blue 三色显示。
3. scope 绘制应优先可读性，而不是绝对显示每个 bin 的线性计数。
4. scope 计算应保持 GPU compute 路径，CPU 只读取 compact bins。
5. scope readback 不得阻塞 `MTKView` drawable present。
6. scope 面板应保持紧凑，位置和尺寸都不能遮挡主要监看主体。
7. scope 标题必须能看出分析源，避免 Raw waveform 和 LUT waveform 被误读。

## 4. 视觉规范

### Luma Waveform

亮度波形图使用白色：

```text
primary color: white
low density opacity: 0.18 - 0.28
mid density opacity: 0.45 - 0.70
high density opacity: 0.90 - 1.00
```

背景保持黑色半透明。网格线保持低对比度白色：

```text
grid color: white, opacity 0.14 - 0.20
major grid line width: 1px
```

亮度 waveform 不再使用绿色。绿色只用于 RGB Parade 的 G 通道。

### RGB Parade

RGB Parade 继续使用：

```text
red channel: red
green channel: green
blue channel: blue
```

每个 channel 在自己的横向区域内绘制。v0.2.3 不要求叠加 RGB，也不要求改成白底彩色线。

### 标题

标题应包含模式和分析源：

```text
Waveform · Raw
Waveform · LUT
RGB Parade · Raw
RGB Parade · LUT
```

如果后续分析源命名为 `Preview Display`，标题可显示为：

```text
Waveform · Display
RGB Parade · Display
```

标题只做状态识别，不在 scope 面板内写大段说明。

## 5. 位置与尺寸

v0.1.3 为减少遮挡，将 scope 宽度限制为 40%。真实 waveform 验证后，单纯放大到 56% 会提高可读性，但会明显抢占监看画面。v0.2.3 采用更克制的紧凑浮层：略大于 v0.1.3，但不做半屏 scope。

默认尺寸：

```text
landscape width: 42% of viewport width
landscape height: 132pt
portrait width: 54% of viewport width
portrait height: 118pt
```

可接受范围：

```text
landscape width: 40% - 48%
landscape height: 124pt - 144pt
portrait width: 50% - 60%
portrait height: 112pt - 132pt
```

### 位置规则

scope 默认使用左下角锚点：

```text
horizontal anchor: leading
vertical anchor: bottom
landscape leading inset: 72pt
portrait leading inset: 12pt
bottom inset: controlStackAvoidance + 10pt
```

左下角的理由：

- 避开右侧工具栏。
- 避开顶部状态栏。
- 保持与当前底部控制条避让逻辑一致。
- 多数横屏构图中，左下角短时遮挡比中央和右侧遮挡更容易接受。

### 避让规则

- 参数调整浮层关闭时，scope 位于底部控制条上方。
- 参数调整浮层打开时，scope 跟随 `controlStackAvoidance` 上移。
- 如果上移后 scope 顶部距离状态栏不足 12pt，优先降低高度到可接受范围下限。
- 如果仍然不足，scope 可临时隐藏标题行，只保留绘图区和一个小型模式标记。
- scope 不进入画面中央，也不覆盖底部相机控制条。

### 拖动与停靠

v0.2.3 支持用户拖动 scope 面板。拖动行为采用“自由拖动预览 + 结束后吸附”的方式：

```text
dragging:
  panel follows finger within safe bounds

on drag ended:
  snap to nearest allowed dock
```

允许停靠位：

```text
Bottom Left
Bottom Right
Top Left
Top Right
```

默认停靠位：

```text
Bottom Left
```

停靠安全边距：

```text
horizontal safe inset: 12pt minimum
top safe inset: statusBarHeight + 10pt
bottom safe inset: controlStackAvoidance + 10pt
side rail avoidance: 56pt where a tool rail is present
```

拖动设计约束：

- 面板拖动时不改变 scope mode、analysis source 或 LUT 状态。
- 面板不能被拖出可见区域。
- 面板不能覆盖底部相机控制条。
- 面板靠近工具栏一侧时，需要自动增加 side rail avoidance。
- 参数调整浮层打开时，底部停靠位自动上移。
- 如果当前停靠位因方向变化或浮层打开而不安全，应自动移动到最近安全位置。
- 拖动结束后的停靠位需要持久化，下次启动恢复。

### 设置入口

Settings 可以提供停靠位置选择，作为拖动之外的辅助入口：

```text
Scope Position:
  Bottom Left
  Bottom Right
  Top Left
  Top Right
```

默认仍为 `Bottom Left`。如果首版不想增加设置项，也必须至少支持拖动后持久化停靠位。

### 非目标

v0.2.3 不做：

- 半屏 scope。
- 任意像素级位置持久化。
- 面板缩放手势。
- full-screen scope。
- 双 scope 同屏。

## 6. Compute 分辨率

v0.2.3 调整默认 `ScopeComputePass.Configuration`：

```swift
static let `default` = Configuration(
    binWidth: 192,
    binHeight: 96,
    frameInterval: 3,
    maxSampleWidth: 640,
    maxSampleHeight: 360
)
```

如果 iPhone 12 Pro 或模拟器性能允许，可提高到：

```text
binWidth: 256
binHeight: 128
maxSampleWidth: 640
maxSampleHeight: 360
```

v0.2.3 首选 `192 x 96` 作为保守默认。`256 x 128` 可作为后续设置项或性能档位。

### 执行频率

默认继续使用：

```text
frameInterval: 3
```

目标：

```text
preview: 30fps
scope analysis: about 10fps
```

如果 scope 清晰度改善后性能仍稳定，可以尝试 `frameInterval = 2`。但 v0.2.3 不把 15fps scope 作为硬性验收标准。

## 7. Bins 归一化

当前线性归一化：

```swift
normalized = Float(count) / Float(maximum)
```

问题是高密度区域会把其他细节压得很暗。v0.2.3 改为非线性密度映射。

推荐实现：

```swift
let normalized = log1p(Float(count)) / log1p(Float(maximum))
```

或：

```swift
let normalized = sqrt(Float(count) / Float(maximum))
```

首选 `log1p`，因为 waveform bins 往往有少数高峰和大量低密度点。`log1p` 能更好保留低密度结构。

空 bins 仍返回 0：

```swift
count == 0 -> 0
```

非空 bins 应至少给一个可见下限，由 UI 绘制层决定，不在 compute 数据层强行抬高：

```swift
displayOpacity = minOpacity + normalized * opacityRange
```

## 8. ScopePanel 绘制

### Luma waveform 绘制

`drawWaveform` 应使用白色：

```swift
drawBins(
    data.lumaBins,
    ...,
    color: .white,
    ...
)
```

亮度 waveform 的透明度建议：

```swift
let opacity = 0.16 + pow(intensity, 0.85) * 0.84
```

或如果数据层已经使用 `log1p`：

```swift
let opacity = 0.18 + intensity * 0.82
```

cell 最小尺寸继续保持至少 1px，但绘制时需要避免过大的 block 感：

- 当 `cellWidth >= 2` 且 `cellHeight >= 2` 时，可缩小绘制 rect 留出半像素间隔。
- 当 cell 很小时，保持满格填充，避免断裂。

### RGB Parade 绘制

RGB Parade 的每个 channel 使用相同的归一化和 opacity 曲线，但颜色分别为 red/green/blue。

为了避免彩色 channel 在深背景上显得过暗，可以略提高最小透明度：

```text
min opacity: 0.20
max opacity: 1.00
```

### 网格

网格保持低调：

```text
horizontal grid: 0%, 25%, 50%, 75%, 100%
vertical grid: every 10%
```

后续如果加入 N-Log 参考线，应与普通网格区分，例如更亮或虚线。v0.2.3 暂不要求参考线。

## 9. Scope 状态与数据模型

`MonitorState` 需要新增停靠位置状态：

```swift
enum ScopeDockPosition: String, CaseIterable, Identifiable, Equatable {
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight
}

struct MonitorState: Equatable {
    var scopeDockPosition: ScopeDockPosition
}
```

默认值：

```swift
scopeDockPosition = .bottomLeft
```

`MonitorSession` 需要提供：

```swift
func setScopeDockPosition(_ position: ScopeDockPosition)
```

该值需要通过 `UserDefaults` 持久化。拖动手势和 Settings 选择都应调用同一个状态更新入口。

现有 `ScopeData` 可以继续使用：

```swift
struct ScopeData: Equatable {
    var lumaBins: [Float]
    var redBins: [Float]
    var greenBins: [Float]
    var blueBins: [Float]
    var binWidth: Int
    var binHeight: Int
    var sourceSequence: Int
}
```

v0.2.3 不强制修改该模型。

如果需要在 UI 中显示分析源，优先从 `MonitorState.exposureAnalysisSource` 读取，而不是把 analysis source 写入 `ScopeData`。`ScopeData` 只表示数值结果，分析源属于 monitor 状态。

## 10. 与 v0.2.2 的关系

v0.2.3 必须复用 v0.2.2 的分析源规则：

```text
Raw Signal:
  scope bins from rawInputColor

Preview Display:
  scope bins from previewColor
```

v0.2.3 只改善 bins 分辨率、归一化和绘制，不改变 raw / preview 的选择逻辑。

如果 v0.2.2 尚未实现，v0.2.3 的实现顺序应为：

1. 先完成 v0.2.2 的 raw / preview / analysis signal 拆分。
2. 再调整 v0.2.3 的 scope compute 和绘制。

否则 waveform 变清楚后，仍可能清楚地显示一个错误的分析信号。

## 11. 设置项

v0.2.3 保留现有：

```text
Scope mode
Scope opacity
```

新增或预留：

```text
Scope Size: Compact / Standard
Scope Position: Bottom Left / Bottom Right / Top Left / Top Right
```

默认：

```text
Scope Size: Compact
Scope Position: Bottom Left
```

Scope Position 可以通过拖动面板更新，也可以通过 Settings 选择更新。两者必须写入同一个 `MonitorState.scopeDockPosition` 或等价状态，避免 UI 和手势状态分裂。

如果首版不做 Scope Size 设置，应固定使用本文档的紧凑尺寸。Scope Position 则建议实现，因为它直接解决不同构图下遮挡主体的问题。

## 12. 测试计划

### Unit / GPU tests

1. `ScopeComputePass.Configuration.default` 使用新默认值。

断言：

```text
binWidth == 192
binHeight == 96
maxSampleWidth == 640
maxSampleHeight == 360
frameInterval == 3
```

2. `normalizedBins` 使用非线性映射。

构造 counts：

```text
[0, 1, 4, 16, 256]
```

断言：

- 0 仍为 0。
- 非 0 值单调递增。
- 低计数值高于线性归一化结果，保证弱信号更可见。

3. waveform bins 仍按列和亮度分布正确落点。

沿用 v0.2.1 的灰阶 ramp 测试，但更新默认 bin 尺寸相关断言。

4. RGB Parade 三通道仍分离。

确保 scope 分辨率提升后不破坏 red / green / blue bins 的 channel 归属。

### View tests / manual screenshot

5. Luma Waveform 使用白色绘制。

可以通过 SwiftUI snapshot 或人工截图验证：

- waveform trace 为白色。
- grid 为低透明白色。
- 背景仍为半透明黑色。

6. RGB Parade 仍使用 RGB 三色。

7. Scope 标题包含分析源。

例如：

```text
Waveform · Raw
RGB Parade · LUT
```

8. Scope 拖动后吸附到最近停靠位。

人工或 UI 测试验证：

- 拖到右下附近，释放后停靠为 `Bottom Right`。
- 拖到左上附近，释放后停靠为 `Top Left`。
- 停靠后不覆盖工具栏、状态栏或底部控制条。
- 退出并重新进入后恢复上一次停靠位。

### Manual validation

使用本地素材：

```text
material/NLOG.MOV
material/REC709.MOV
material/HLG.MOV
```

验证步骤：

1. 打开 `REC709.MOV`，确认 waveform 白色可见，横向分布比 v0.2.1 更细。
2. 打开 `NLOG.MOV`，在 Raw analysis 下确认 waveform 是平 Log 信号的码值分布。
3. 开启 N-Log LUT，确认 waveform 标题仍正确显示 Raw 或 LUT 分析源。
4. 切换 RGB Parade，确认 R/G/B 三色通道清晰。
5. 打开参数调整浮层，确认 scope 仍避让底部控制。
6. 在 iPhone 12 Pro Simulator 上观察预览刷新，不应因为 scope 增强明显卡顿。

## 13. 验收标准

v0.2.3 完成时必须满足：

- Luma waveform 为白色，不再是绿色。
- RGB Parade 仍为 red / green / blue。
- 默认 bins 至少为 `192 x 96`。
- sample 上限至少为 `640 x 360`。
- bins 归一化使用 `log1p` 或等效非线性映射。
- 低密度波形点在真实素材中可见。
- scope 面板采用紧凑浮层，横屏默认约 42%，可接受范围为 40% - 48%。
- scope 默认锚定左下角，并随底部控制条和参数调整浮层动态上移。
- scope 支持拖动并吸附到四个安全停靠位。
- scope 停靠位持久化，下次启动恢复。
- scope 标题显示分析源。
- scope 开启时不明显阻塞主预览。
- 现有 waveform / parade compute tests 通过。

## 14. 非目标

v0.2.3 不要求：

- 增加 full-screen scope。
- 增加 histogram。
- 增加 vectorscope。
- 增加 N-Log 官方参考线。
- 复刻某一品牌外部监视器的 waveform 样式。
- 支持 waveform 缩放、冻结、峰值保持。
- 支持 LUT 前 / LUT 后双 waveform 同屏。
- 对 waveform 做最终色彩科学校准。

## 15. 后续版本建议

v0.2.4 可以处理 LUT metadata：

- 区分 technical LUT 和 creative LUT。
- 记录 LUT input space / output space。
- 自动建议 N-Log 输入使用 N-Log technical LUT。

v0.2.5 可以处理专业 scope：

- N-Log waveform 参考线。
- Rec.709 IRE 标尺。
- false color 参考说明。
- full-screen scope 模式。
- waveform freeze / hold。

v0.2.6 可以处理性能档位：

- Compact / Standard / High Quality scope。
- 按设备自动选择 bins 和 sample resolution。
- 对低端设备降低 compute frequency。
