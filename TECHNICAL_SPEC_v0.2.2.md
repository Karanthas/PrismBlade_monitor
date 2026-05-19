# PrismBlade v0.2.2 技术文档

代号：PrismBlade
版本：v0.2.2
日期：2026-05-18
目标平台：iOS / iPhone 12 Pro
运行目标：Xcode Simulator 优先，保留真机验证空间
目标相机：Nikon Z6III
当前阶段：修正 N-Log / LUT / 曝光分析链路，不改变真实相机通信范围

## 1. 版本定位

PrismBlade v0.2.2 是 v0.2.1 Metal-first 图像处理原型的曝光链路校正版。v0.2.1 已经实现 `CVPixelBuffer -> MTLTexture -> MTKView` 的真实像素预览、3D LUT 采样、N-Log / HLG / Rec.709 输入解释、伪色、斑马纹和 Metal compute scope。但在真实 Nikon Z6III N-Log 素材上，N-Log 套 Nikon N-Log -> Rec.709 LUT 后出现明显曝光异常。

v0.2.2 只处理这个曝光链路问题：

- 修正 N-Log LUT 预览的输入空间。
- 明确 LUT 关闭时的 N-Log 显示和分析行为。
- 明确 LUT 开启时的预览信号和曝光分析信号。
- 重新定义 shader 内的 raw input、preview output、analysis signal 边界。
- 补充测试，防止再次出现“先 N-Log decode 再采样 N-Log LUT”的错误。

v0.2.2 不处理 scope 清晰度、UI 尺寸、波形密度增强、真实 USB/PTP 通信、真实 live view 或录制文件保存。这些留在后续版本。

## 2. 当前问题

v0.2.1 的固定链路为：

```text
sourceColor
  -> transformToWorkingSpace(colorEncoding)
  -> applyDisplayLUT(workingColor)
  -> false color / zebra
  -> display

scope:
sourceColor
  -> transformToWorkingSpace(colorEncoding)
  -> applyDisplayLUT(workingColor)
  -> bins
```

这个设计把所有输入都先转换到统一显示工作空间，再进入 LUT 和曝光辅助。这个规则对“显示工作空间 LUT”可能成立，但对 Nikon N-Log -> Rec.709 技术 LUT 不成立。

本地开发 LUT：

```text
PrismBlade/Resources/LUTs/N-Log_BT2020_to_REC709_BT1886_size_33.cube
```

从文件名和用途看，该 LUT 的输入空间应是原始 N-Log / BT.2020 编码信号，输出空间应是 Rec.709 / BT.1886 显示信号。当前代码却先将 N-Log 编码值执行 `nlogDecode()`，再用解码后的值采样该 LUT，导致 LUT 采样坐标错误。

### 典型后果

- 中间调可能偏暗或对比异常，因为 LUT 收到的输入码值比预期低。
- 高光可能提前失去层次，因为错误的 `nlogDecode()` 结果会在 LUT 前被 clamp 到 `0...1`。
- 相机机内监看不过曝，但 App 内 LUT 预览过曝或发白，是合理的错误表现。
- false color、zebra 和 scope 会跟随错误的工作空间结果，进一步误导曝光判断。

## 3. 设计原则

v0.2.2 固定以下原则：

1. 原始输入信号不得被隐式改写。
2. N-Log LUT 预览开启时，N-Log -> Rec.709 LUT 必须直接采样原始 N-Log 编码值。
3. N-Log LUT 预览关闭时，预览应直接显示原始 N-Log 画面，不做自定义 Rec.709 化。
4. 曝光分析信号必须和预览信号解耦，不能再隐式使用单一 `workingColor`。
5. scope、zebra、false color 的分析源必须是显式状态：raw signal 或 display signal。
6. 默认曝光分析优先保护拍摄信号，而不是保护 LUT 后观感。
7. LUT 只影响监看显示，不改变原始 `CVPixelBuffer`，也不改变相机状态。

## 4. 核心信号模型

shader 和 processor 内部必须区分三类信号：

```text
rawInputColor
  原始输入像素码值。
  对 N-Log 来说就是 N-Log 编码值。
  对 Rec.709 来说就是解码器输出的 Rec.709 显示码值。
  对 HLG 来说就是 HLG 编码值。

previewColor
  当前监看画面实际显示的颜色。
  LUT off 时通常等于 rawInputColor。
  LUT on 时等于 LUT 输出或 LUT 强度混合结果。

analysisColor
  曝光工具使用的信号。
  由 MonitorState 中的 analysis source 决定。
  可为 rawInputColor 或 previewColor。
```

不得再使用一个含义混杂的 `workingColor` 同时承担 LUT 输入、预览显示和曝光分析。

## 5. 默认行为

### N-Log 输入，LUT 关闭

```text
rawInputColor = sourceColor.rgb
previewColor = rawInputColor
analysisColor = rawInputColor
```

用户应看到平的 N-Log 画面。waveform / parade / zebra / false color 默认分析原始 N-Log 码值。

这个行为的目的：

- 让 LUT 关闭时的画面不伪装成 Rec.709。
- 让曝光工具直接反映记录信号。
- 避免 App 自己的简化 N-Log decode 造成错误高光、错误中灰或错误观感。

### N-Log 输入，LUT 开启

```text
rawInputColor = sourceColor.rgb
lutInputColor = rawInputColor
lutOutputColor = sampleNLogLUT(lutInputColor)
previewColor = mix(rawInputColor, lutOutputColor, lutIntensity)
analysisColor = rawInputColor by default
```

默认情况下，画面显示 LUT 预览结果，但曝光分析仍使用原始 N-Log 信号。

这个默认值更适合拍摄监看：

- LUT 后画面用于视觉判断构图、对比、肤色和氛围。
- raw signal 用于曝光判断，避免 LUT 的 contrast、rolloff、creative look 或输出 gamma 影响记录信号分析。
- 用户不会因为一个 LUT 后画面看起来很亮，就误以为原始 N-Log 记录已经剪白。

### Rec.709 输入

```text
rawInputColor = sourceColor.rgb
previewColor = rawInputColor unless a compatible display LUT is enabled
analysisColor = rawInputColor by default
```

Rec.709 输入不需要 N-Log decode。v0.2.2 不改变 Rec.709 的默认显示行为。

### HLG 输入

v0.2.2 不重新校准 HLG。为避免引入新的错误，HLG 在本版本应优先采用与 N-Log 一致的保守策略：

```text
LUT off:
  previewColor = rawInputColor
  analysisColor = rawInputColor

LUT on, if a compatible HLG LUT exists:
  previewColor = LUT result
  analysisColor = rawInputColor by default
```

HLG 的专用显示转换和 HDR/SDR 映射留给后续校准版本。

## 6. 曝光分析源

新增显式分析源：

```swift
enum ExposureAnalysisSource: String, CaseIterable, Identifiable, Equatable {
    case rawSignal
    case previewDisplay
}
```

建议 UI 文案：

```text
Raw Signal
Preview Display
```

默认值：

```text
MonitorState.exposureAnalysisSource = .rawSignal
```

### Raw Signal

`analysisColor = rawInputColor`

用于严肃曝光判断。scope、zebra、false color 都读取原始输入码值。

对 N-Log：

- waveform 显示 N-Log 码值分布。
- zebra 阈值解释为 N-Log signal level，而不是 Rec.709 IRE。
- false color 阈值也应按 N-Log signal level 定义，不能沿用 Rec.709 IRE 文案。

### Preview Display

`analysisColor = previewColor`

用于判断当前监看画面本身。LUT 开启时，scope、zebra、false color 会分析 LUT 后显示结果。

这个模式适合：

- 判断 LUT 后 Rec.709 画面是否剪白。
- 判断交付观感里的肤色亮度。
- 对比外部监视器中“LUT 后 waveform”的使用习惯。

但它不应作为 N-Log 记录曝光的默认模式。

## 7. UI 与状态展示

v0.2.2 至少需要让用户知道当前分析源。建议在 scope 标题或状态栏中显示：

```text
Waveform · Raw
Waveform · LUT
RGB Parade · Raw
RGB Parade · LUT
```

如果 N-Log 输入且 LUT 关闭，状态栏应显示：

```text
N-Log Raw
```

如果 N-Log 输入且 LUT 开启，状态栏应显示：

```text
N-Log LUT
Analysis Raw
```

或更紧凑：

```text
N-Log LUT · Raw Scope
```

设置页应增加一个曝光分析源选项。首版可以只放在 Settings，不需要占用监看主屏按钮。

## 8. Shader 处理顺序

### Fragment preview shader

目标结构：

```metal
const float3 rawInputColor = sourceTexture.sample(sourceSampler, uv).rgb;
const bool lutEnabled = lutUniforms[0].x >= 0.5;
const float lutIntensity = clamp(lutUniforms[0].y, 0.0, 1.0);

float3 previewColor = rawInputColor;

if (lutEnabled) {
    const float3 lutInputColor = lutInputColorForEncoding(rawInputColor, colorEncoding, lutKind);
    const float3 lutOutputColor = sampleDisplayLUT(lutInputColor, lutTexture, lutSampler, lutUniforms);
    previewColor = mix(rawInputColor, lutOutputColor, lutIntensity);
}

const float3 analysisColor = analysisColorForSource(
    rawInputColor,
    previewColor,
    exposureAnalysisSource
);

float3 displayColor = previewColor;

if (falseColorEnabled) {
    displayColor = falseColor(analysisColor, colorEncoding, exposureAnalysisSource);
}

if (zebraEnabled && zebraApplies(analysisColor, colorEncoding, exposureAnalysisSource)) {
    displayColor = applyZebra(displayColor, pixelPosition);
}

return float4(clamp(displayColor, 0.0, 1.0), sourceAlpha);
```

### LUT input selection

v0.2.2 可以先只支持一种 LUT input policy：

```text
selected LUT input = raw input signal
```

也就是说：

```metal
lutInputColor = rawInputColor;
```

后续如果需要支持 display-space creative LUT，再给 `LUTDescriptor` 增加 metadata：

```swift
enum LUTInputSpace {
    case sourceEncoding
    case rec709Display
    case linearDisplay
}
```

v0.2.2 不引入这个复杂度，先修正 Nikon N-Log 技术 LUT 的错误。

### Scope compute shader

scope compute 必须使用和 fragment shader 相同的 raw / preview / analysis 选择逻辑：

```text
sourceTexture
  -> rawInputColor
  -> previewColor, if LUT enabled
  -> analysisColor, according to ExposureAnalysisSource
  -> bins
```

不得在 scope compute 里继续调用旧的 `transformToWorkingSpace()` 后再采样 N-Log LUT。

## 9. 阈值解释

v0.2.1 的 false color / zebra 阈值默认以 Rec.709 luma / IRE 理解。v0.2.2 允许先保留 UI 阈值控件，但必须在内部区分解释方式。

### Raw N-Log 分析

当输入为 N-Log 且 `analysisSource == .rawSignal`：

- waveform y 轴为 N-Log signal level。
- zebra threshold 应直接和 N-Log 码值比较。
- 设置页里的百分比暂时可解释为 normalized signal level。
- 不应在内部先转 Rec.709 luma。

如果后续要做更专业的 N-Log 曝光辅助，应提供 Nikon N-Log 参考标记，例如中灰、肤色、高光保护线等。v0.2.2 不强行校准这些参考线。

### Preview Display 分析

当 `analysisSource == .previewDisplay`：

- waveform y 轴为当前显示信号。
- LUT 后 Rec.709 结果可以用 Rec.709 luma / IRE 风格解释。
- zebra 和 false color 反映的是监看画面的输出，不代表原始 Log 记录是否剪切。

UI 应避免把这两种模式都叫作同一种“IRE”，除非已经明确转换到 Rec.709 显示信号。

## 10. 数据模型调整

`MonitorState` 新增：

```swift
struct MonitorState: Equatable {
    var exposureAnalysisSource: ExposureAnalysisSource
}
```

默认值：

```swift
static let initial = MonitorState(
    ...
    exposureAnalysisSource: .rawSignal
)
```

`MetalFrameProcessor.makeMonitorUniforms` 需要增加 analysis source code：

```swift
SIMD4<Float>(
    ColorTransformPass.encodingCode(for: format.colorEncoding),
    FalseColorPass.enabledFlag(for: monitor),
    ZebraPass.enabledFlag(for: monitor),
    ZebraPass.modeCode(for: monitor.zebraMode)
),
SIMD4<Float>(
    ZebraPass.thresholdFraction(for: monitor),
    ExposureAnalysisPass.sourceCode(for: monitor.exposureAnalysisSource),
    0,
    0
)
```

如果 uniform 空位不足，应新增第三个 uniform vector，不要复用含义不清的字段。

## 11. 需要删除或降级的逻辑

v0.2.2 应删除或停止用于 N-Log LUT 链路的以下逻辑：

```text
N-Log source
  -> nlogDecode()
  -> clamp()
  -> N-Log -> Rec.709 LUT
```

`ColorTransformPass.decodeNLog` 可以暂时保留给测试或未来显示转换实验，但不应在默认 preview/LUT/scope 路径中自动执行。

`transformToWorkingSpace()` 不应继续作为所有 pass 的入口。如果保留函数，需要改名或限制用途，避免误读为“LUT 前必经转换”。

建议重命名：

```text
transformToWorkingSpace -> experimentalDisplayTransform
```

或直接拆成更明确的函数：

```metal
float3 rawInputColor(...)
float3 previewColor(...)
float3 analysisColor(...)
```

## 12. 测试计划

v0.2.2 至少增加以下自动化测试。

### Preview shader

1. N-Log + LUT enabled 时，LUT 采样输入必须是原始 N-Log 码值。

测试方法：

- 构造一个 1D 行为明显的 3D LUT。
- 输入 `sourceColor = 0.7`。
- 如果 shader 先 `nlogDecode()`，输出会落到错误位置或被 clamp。
- 断言输出等于直接采样 `0.7` 的结果。

2. N-Log + LUT disabled 时，输出应等于 raw N-Log 输入。

测试方法：

- 输入 `sourceColor = 0.36366777`。
- colorEncoding = `.nLog`。
- LUT disabled。
- 断言输出仍接近 `0.36366777`，而不是 `0.18`。

3. N-Log + LUT intensity 0.5 时，应在 raw input 和 LUT output 之间混合。

```text
preview = mix(rawInputColor, lutOutputColor, 0.5)
```

不是：

```text
preview = mix(decodedNLogColor, lutOutputColor, 0.5)
```

### Scope compute

4. Scope raw analysis mode 分析 raw N-Log。

- 输入 N-Log 灰阶。
- LUT enabled。
- `analysisSource = .rawSignal`。
- bins 应落在 raw 码值对应高度。

5. Scope preview analysis mode 分析 LUT 后结果。

- 输入同一 N-Log 灰阶。
- LUT enabled。
- `analysisSource = .previewDisplay`。
- bins 应落在 LUT 输出对应高度。

### Zebra / false color

6. Raw N-Log 分析模式下，zebra threshold 与 raw signal 比较。

7. Preview Display 分析模式下，zebra threshold 与 preview signal 比较。

## 13. 手动验证

使用本地素材：

```text
material/NLOG.MOV
PrismBlade/Resources/LUTs/N-Log_BT2020_to_REC709_BT1886_size_33.cube
```

验证步骤：

1. 启动 App 并载入 `material/NLOG.MOV`。
2. 确认 LUT 关闭时画面是平的 N-Log，不应被 App 自动转成 Rec.709。
3. 打开 waveform，确认标题显示 Raw 或等价状态。
4. 开启 Nikon N-Log -> Rec.709 LUT。
5. 确认预览画面变为正常对比度 Rec.709 风格，而不是整体发白或异常剪切。
6. 确认 waveform 默认仍显示 Raw 分析源。
7. 在 Settings 中切换到 Preview Display 分析源。
8. 确认 waveform / zebra 跟随 LUT 后画面变化。
9. 对比相机机内监看或外部监视器 LUT 预览，检查高光层次是否明显改善。

验收标准：

- LUT 关闭时，N-Log 不再被自动 decode。
- LUT 开启时，N-Log LUT 不再吃 decode 后的值。
- 高光不会在 LUT 前被 App 的 `nlogDecode + clamp` 提前剪切。
- scope / zebra / false color 的分析源可解释、可切换。
- UI 能让用户知道当前分析的是 Raw 还是 LUT 后显示。

## 14. 非目标

v0.2.2 明确不解决：

- Nikon N-Log 曲线的最终校准。
- HLG 到 SDR/HDR 的最终监看策略。
- scope 面板尺寸、清晰度、动态范围增强。
- professional monitor 行为的完整复刻。
- 每种外部监视器的 LUT 前 / LUT 后工具差异。
- Creative LUT 和 Technical LUT 的完整 metadata 管理。
- 自动识别 LUT input/output color space。
- 真实相机 live view。
- USB/PTP 通信。

## 15. 后续版本建议

v0.2.3 可以处理 scope 可读性：

- 提高 bins 分辨率。
- 改善 bins 归一化和低密度可视化。
- 增加 waveform 标尺和 N-Log 参考线。
- 增加 waveform 面板尺寸策略。

v0.2.4 可以处理 LUT metadata：

- 区分 technical LUT 和 creative LUT。
- 记录 LUT input space / output space。
- 自动建议 N-Log 输入使用 N-Log technical LUT。
- 对 Rec.709 输入禁用 N-Log technical LUT 或提示风险。

v0.2.5 可以处理真实素材校准：

- 使用灰卡、色卡、肤色、高光保护场景。
- 对比相机机内 View Assist、Nikon 官方工具、DaVinci Resolve 和常见外部监视器。
- 为 Raw N-Log waveform 增加可靠参考线。
