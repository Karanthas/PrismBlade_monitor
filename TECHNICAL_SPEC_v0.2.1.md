# PrismBlade v0.2.1 技术文档

代号：PrismBlade  
版本：v0.2.1  
日期：2026-05-13  
目标平台：iOS / iPhone 12 Pro  
运行目标：Xcode Simulator 优先，保留真机验证空间  
目标相机：Nikon Z6III  
当前阶段：Metal-first 真实像素监看管线 MVP，不实现正式 Nikon USB/PTP 相机通信

## 1. 版本定位

PrismBlade v0.2.1 是从 v0.1.3 交互原型进入真实图像处理原型的版本。v0.1.x 已经完成横屏优先监看界面、LUT 导入、Mock 相机控制、曝光模式限制、短提示、底部控制条和 scope 避让等交互闭环；v0.2.1 的重点不再是继续堆 UI，而是把当前“看起来像监看”的占位效果升级为基于 Metal shader 的真实像素监看链路。

v0.2.1 的技术路线已经固定为 Metal-first：

- 渲染主路线：纯 Metal shader 管线。
- 帧数据类型：`CVPixelBuffer` 是媒体输入/输出帧；`MTLTexture` 是 GPU 工作帧。
- 视频文件帧源：`AVAssetReader`。
- LUT 实现：Metal 3D texture + fragment shader。
- 伪色与斑马纹：Metal shader。
- Scope 分析：Metal compute 直接生成 waveform / parade bins。
- 颜色空间策略：完整支持 Rec.709 / N-Log / HLG 转换。
- SwiftUI 集成方式：`UIViewRepresentable` 包一层 `MTKView`。

v0.2.1 的核心目标：

- 增加真实 Metal 渲染/处理管线边界：`MetalFrameProcessor`。
- 让预览输入从纯 SwiftUI 合成画面升级为可承载真实像素数据的帧模型。
- 将 `.cube` LUT 从“已解析但只显示 tint”升级为真正应用到显示链路。
- 将伪色和斑马纹从占位 overlay 升级为基于 luma/阈值的像素级处理。
- 将 Luma waveform 和 RGB Parade 从程序波形升级为 Metal compute 生成的 bins。
- 增加 `VideoFileFrameSource`，用 `AVAssetReader` 读取本地测试视频或用户选择视频，作为真实相机 live view 前的验证输入。
- 增加 Rec.709 / N-Log / HLG 到显示工作空间的颜色转换 pass。
- 补齐关键单元测试，保护 LUT parser、曝光模式规则、Mock transport 和状态切换。

本版本仍然不把真实 Nikon Z6III USB/PTP 通信作为交付范围。真实相机通信可做预研和 adapter 命名空间准备，但不进入主功能路径。

## 2. 当前基础

v0.1.3 已经具备以下可复用基础：

- `FrameSource` 抽象和 `SimulatedFrameSource`。
- `MonitorSession` 作为主状态容器。
- `MonitorState`、`CameraState`、`LUTState`、`OrientationState`。
- `CameraTransport`、`CameraCommandService`、`MockCameraTransport`。
- `.cube` parser、LUT descriptor 和导入持久化。
- 伪色、斑马纹、Luma waveform、RGB Parade 的 UI 开关和占位展示。
- 底部常驻相机控制条。
- 曝光模式限制规则和三层校验。
- 设置页中的竖屏监看开关、斑马阈值、scope opacity 和 Mock 调试入口。

当前主要缺口：

- `SyntheticPreviewView` 仍是 SwiftUI gradient、色块和 overlay，不是真实 pixel buffer 渲染。
- LUT 只使用 `previewTintHex` 作为视觉提示，没有应用 `.cube` 数据。
- 伪色不读取亮度，只显示整屏色带。
- 斑马纹不读取像素阈值，只按屏幕宽度比例 mask。
- Scope 不分析真实帧，只根据 `frame.phase` 画程序曲线。
- `VideoFrame` 还没有承载真实 `CVPixelBuffer`。
- 还没有 `CVPixelBuffer -> MTLTexture` 的桥接边界。
- 还没有 Metal 工作纹理、pass 编排、3D LUT texture 和 compute scope bins。
- 项目尚未建立 XCTest 测试目标。

## 3. v0.2.1 范围

### 必须实现

- 新增 `MetalFrameProcessor`，统一编排显示链路中的色彩转换、LUT、伪色、斑马纹和 scope compute。
- 扩展 `VideoFrame` 为媒体帧模型，使用 `CVPixelBuffer` 作为输入/输出载体。
- 新增 `MetalTextureBridge`，使用 `CVMetalTextureCache` 将 `CVPixelBuffer` 转换为 `MTLTexture`。
- 新增 `MetalPreviewSurface`，通过 `UIViewRepresentable` 包装 `MTKView`，替代或包裹当前 `SyntheticPreviewView`。
- 将当前 SwiftUI 合成测试图迁移成可生成真实像素帧的测试输入，或保留为 fallback。
- 使用纯 Metal shader 管线实现预览显示。
- 将 `.cube` 解析结果转换为 Metal 3D texture。
- 使用 fragment shader 完成 3D LUT 采样和 LUT 强度混合。
- LUT 只影响监看显示链路，不改变原始帧。
- 使用 Metal shader 基于 luma / IRE 实现伪色映射。
- 使用 Metal shader 基于阈值实现 High Zebra。
- 保留现有斑马阈值设置。
- 使用 Metal compute 直接生成 Luma waveform bins。
- 使用 Metal compute 直接生成 RGB Parade bins。
- Scope 分析增加 compute 分辨率、执行频率和 readback 节流，避免模拟器和 iPhone 12 Pro 负载过高。
- 新增 `VideoFileFrameSource`，通过 `AVAssetReader` 播放本地测试视频或用户选择视频。
- `SimulatedFrameSource` 继续作为默认 fallback。
- 完整实现 Rec.709 / N-Log / HLG 到统一显示工作空间的转换。
- 建立 XCTest 测试目标。
- 增加 `.cube` parser 正常和异常路径测试。
- 增加曝光模式参数锁定规则测试。
- 增加 `CameraCommandService` 和 `MockCameraTransport` 非法写入拒绝测试。
- 增加基础 monitor state toggle 测试。

### 可以实现，但不阻塞

- Histogram。
- LUT 前 / LUT 后 scope 分析源切换。
- LUT 缩略图。
- LUT 分组和收藏。
- 视频帧源选择 UI。
- 简单性能指标展示，例如帧号、分析间隔、处理耗时。
- ImageCaptureCore、PTP、Network Bridge adapter 的空命名空间。

### 明确不做

- 不实现正式 Nikon Z6III USB/PTP 连接。
- 不移植 `libgphoto2`。
- 不承诺 iOS USB 有线通信路径已经可用。
- 不实现真实相机 live view。
- 不实现真实录制文件保存。
- 不实现真实拍照文件导入或保存。
- 不实现完整 CameraCapabilities 解析。
- 不改变 v0.1.3 的底部相机控制交互模型。
- 不把 LUT 烘焙进原始素材或相机输出。
- 不使用 Core Image 作为实时监看主路径。
- 不使用 SwiftUI `Image` / `Canvas` 做逐帧视频渲染。
- 不用 CPU 逐像素实现 LUT、伪色、斑马纹或 scope 主逻辑。

## 4. 架构目标

v0.2.1 后的目标结构：

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

Imaging Pipeline
  -> MetalFrameProcessor
  -> ColorTransformPass
  -> LUTPass
  -> FalseColorPass
  -> ZebraPass
  -> ScopeComputePass

Rendering
  -> MetalPreviewRenderer
  -> MetalPreviewSurface (UIViewRepresentable + MTKView)
  -> ScopePanel

Camera
  -> CameraTransport
  -> CameraCommandService
  -> MockCameraTransport
  -> FutureImageCaptureTransport placeholder
  -> FuturePTPTransport placeholder
  -> FutureNetworkBridgeTransport placeholder
```

设计原则：

- SwiftUI 只负责布局、交互和状态展示。
- 图像处理逻辑必须从 `SyntheticPreviewView` 中移出。
- `MetalFrameProcessor` 不依赖 Nikon、USB、PTP 或 Mock transport。
- `CameraTransport` 不依赖图像处理类型。
- LUT、伪色、斑马纹和 scope 使用同一帧数据来源，避免画面和分析结果不一致。
- 媒体边界使用 `CVPixelBuffer`；GPU 工作边界使用 `MTLTexture`。
- `CVPixelBuffer -> MTLTexture` 只能发生在 renderer / processor ingress 边界，不能散落在 UI 或帧源里。
- 实时监看主路径不使用 Core Image。
- 真实相机通信只通过未来 `FrameSource` 和 `CameraTransport` 替换，不穿透 UI 层。

## 5. 数据模型调整

### MediaFrame / VideoFrame

v0.1.3 的 `VideoFrame` 主要用于模拟动画：

```swift
struct VideoFrame {
    var sequence: Int
    var timestamp: Date
    var format: FrameFormat
    var phase: Double
    var metadata: FrameCameraMetadata
}
```

v0.2.1 固定采用媒体帧和 GPU 工作帧分层：

- `CVPixelBuffer` 是媒体输入/输出帧，属于 `FrameSource`、视频文件、未来 live view、测试输入和持久化边界。
- `MTLTexture` 是 GPU 工作帧，属于 renderer、processor、shader pass 和 `MTKView` 显示边界。
- `MonitorSession` 可以持有最新媒体帧和元数据，但不直接持有 `MTLTexture`。
- SwiftUI UI 层不直接创建、缓存或解释 GPU texture。

命名可以继续使用 `VideoFrame`，但语义必须是媒体帧：

```swift
struct VideoFrame: Sendable {
    var sequence: Int
    var timestamp: CMTime
    var format: FrameFormat
    var pixelBuffer: CVPixelBuffer
    var metadata: FrameCameraMetadata
}
```

如果 `CVPixelBuffer` 的 Sendable 标注带来并发问题，应通过 dedicated frame actor、主 actor 边界或 wrapper 隔离，不应退回 `phase` 或 SwiftUI 合成状态。

### TextureFrame

`TextureFrame` 只在 Metal renderer / processor 内部出现。它由 `VideoFrame.pixelBuffer` 经 `CVMetalTextureCache` 桥接得到：

```swift
struct TextureFrame {
    var sequence: Int
    var timestamp: CMTime
    var format: FrameFormat
    var sourceTexture: MTLTexture
    var metadata: FrameCameraMetadata
}
```

新增桥接对象：

```swift
final class MetalTextureBridge {
    func makeTexture(from pixelBuffer: CVPixelBuffer) throws -> MTLTexture
}
```

实现要求：

- 内部使用 `CVMetalTextureCacheCreateTextureFromImage`。
- 明确处理 pixel format，例如 `kCVPixelFormatType_32BGRA` 或视频解码输出的 YCbCr 格式。
- texture usage 必须满足 shader read / render target / compute read 的实际需求。
- 桥接失败应返回可展示的短错误，不让 renderer 静默黑屏。

### ScopeData

Scope panel 不应再自己生成波形，而是显示 analyzer 产出的数据：

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

`ScopeComputePass` 直接在 GPU 上生成 bins。CPU 只读取最终的小型 bins buffer 并交给 `ScopePanel` 绘制；CPU 不应逐像素读取原始帧。

## 6. MetalFrameProcessor

### 职责

`MetalFrameProcessor` 负责将输入媒体帧和当前监看状态转换为 GPU 显示输出：

1. 将 `CVPixelBuffer` 桥接为输入 `MTLTexture`。
2. 执行 Rec.709 / N-Log / HLG 到统一显示工作空间的色彩转换。
3. 应用 Metal 3D LUT texture。
4. 在 shader 中完成 LUT 强度混合。
5. 应用伪色或斑马纹 shader pass。
6. 使用 Metal compute 生成 scope bins。
7. 将最终 display texture 合成到 `MTKView` drawable。

### 固定处理顺序

```text
VideoFrame(CVPixelBuffer)
  -> CVMetalTextureCache
  -> TextureFrame(MTLTexture)
  -> ColorTransformPass
      -> Rec.709 / N-Log / HLG to display working space
  -> LUTPass, if enabled
      -> sample Metal 3D LUT texture
      -> mix original and LUT result by intensity
  -> ExposureAssistPass
      -> FalseColorPass, if enabled
      -> ZebraPass, if enabled
  -> ScopeComputePass, if scope enabled
      -> waveform / parade bins buffer
  -> CompositePass
      -> render into MTKView drawable.texture
```

默认 scope 以显示链路为准，也就是色彩转换和 LUT 后的结果。伪色/斑马纹是否进入 scope 分析源应由一个明确开关控制，v0.2.1 默认不把伪色/斑马纹 overlay 纳入 scope。

### 状态输入

`MetalFrameProcessor` 至少需要：

- `MonitorState`
- `LUTState`
- 当前选中 LUT 的 `MTLTextureType3D`
- 当前 `VideoFrame`
- 当前 `FrameFormat.colorEncoding`
- 当前 drawable size / viewport / zoom mode

不要让 `MetalFrameProcessor` 读取 `MonitorSession` 整体对象，避免图像层知道相机控制、设置页和 UI sheet 状态。

### Metal 资源管理

v0.2.1 应建立明确的 GPU 资源生命周期：

- `MTLDevice`、`MTLCommandQueue`、pipeline state 和 sampler 由 `MetalPreviewRenderer` 长期持有。
- 每帧 command buffer 在 `MTKViewDelegate.draw(in:)` 中创建并提交。
- 中间工作纹理使用 texture pool 或按尺寸缓存，避免每帧重复大量分配。
- drawable size 变化时重建尺寸相关资源。
- LUT 3D texture 在选择 LUT 或导入 LUT 后创建并缓存，不应每帧重建。

## 7. LUT 实现

### 当前状态

当前 `.cube` parser 已经支持：

- `TITLE`
- `LUT_3D_SIZE`
- `DOMAIN_MIN`
- `DOMAIN_MAX`
- 注释
- RGB 数据行数量校验
- 超出 0-1 数据 clamp 并记录 warning

当前缺口是解析后的 entries 没有进入渲染链路。

### v0.2.1 要求

- `LUTRepository` 或新的 `LUTStore` 能读取已导入 `.cube` 的解析数据。
- 选中 LUT 后，processor 能获得完整 LUT entries。
- 将 LUT 转换为 `MTLTextureType3D`。
- 使用 fragment shader 对 3D LUT texture 进行三线性采样。
- 在 shader 中支持强度混合：

```text
display = mix(originalDisplay, lutDisplay, intensity)
```

- `intensity = 0` 时画面等同未开启 LUT。
- `intensity = 1` 时完整应用 LUT。
- LUT 应只影响监看显示，不写回源帧，不影响相机状态。
- 导入失败仍通过现有 `lastImportError` 展示，不阻塞 App 启动。
- `.cube` entries 到 3D texture 的排列顺序必须有单元测试覆盖，至少包括 identity LUT 和单通道 ramp LUT。
- LUT texture format 使用 `rgba16Float` 或 `rgba32Float`；不得使用会明显压缩精度的 8-bit 格式作为主实现。
- `DOMAIN_MIN` / `DOMAIN_MAX` 必须参与采样归一化；如果暂时只支持 0...1 domain，非默认 domain 应明确提示或转换。

### 内置 LUT

当前内置 LUT 只有 descriptor 和 tint。v0.2.1 必须为内置 LUT 提供真实 `.cube` 资源，或移除这些内置项的可选入口。v0.2.1 不保留 preview-only LUT，以免出现“导入 LUT 真实生效，内置 LUT 仍是假效果”的割裂。

## 8. 伪色

### 当前状态

当前伪色是整屏横向色带，并不读取画面亮度。

### v0.2.1 要求

- 使用 Metal shader 基于显示链路 luma / IRE 计算。
- 伪色输入必须来自 `ColorTransformPass` 后的显示工作空间。
- Rec.709、N-Log、HLG 输入必须先转换到统一亮度解释空间，再进入伪色映射。
- 保留现有一键开关。
- 伪色作为监看 overlay/pass，不改变源帧。

默认映射：

```text
0-5 IRE      -> purple / blue
18 IRE       -> middle gray marker
40-60 IRE    -> green / skin safe range
90-100 IRE   -> yellow / orange
100+ IRE     -> red clipping warning
```

v0.2.1 必须完整支持 Rec.709 / N-Log / HLG 转换。N-Log 和 HLG 的转换曲线应集中在 `ColorTransformPass` 或 `ColorTransformLibrary` 中，不允许散落在伪色、斑马纹、LUT 和 scope shader 里各自实现。

## 9. 斑马纹

### 当前状态

当前斑马纹按阈值换算屏幕右侧宽度，并没有判断像素是否高于阈值。

### v0.2.1 要求

- High Zebra 必须基于 luma threshold。
- 使用设置页现有阈值，范围继续保持 50-100。
- 斑马纹由 Metal shader 生成 overlay，不改变底图。
- 斜线图案只出现在超过阈值的像素区域。
- 阈值计算必须使用 `ColorTransformPass` 后的统一亮度解释。

Range Zebra 可作为可选功能，若实现应复用现有 `ZebraMode.range`，并补充范围设置或使用默认肤色参考区间。

## 10. 颜色空间与输入解释

v0.2.1 必须完整支持 Rec.709 / N-Log / HLG 转换，而不是只把输入都当作 sRGB/Rec.709。

### 要求

- `FrameFormat.colorEncoding` 必须成为 `ColorTransformPass` 的显式输入。
- `ColorTransformPass` 负责将不同输入编码转换到统一显示工作空间。
- LUT、伪色、斑马纹和 scope 都消费转换后的工作空间数据。
- Rec.709 输入按标准显示亮度解释。
- N-Log 输入必须按 Nikon N-Log 曲线转换到显示/线性工作空间，再参与 LUT 和曝光辅助。
- HLG 输入必须按 HLG EOTF/OOTF 策略转换到显示/线性工作空间，再参与 LUT 和曝光辅助。
- UI 状态栏应继续显示当前输入编码，避免用户误判曝光工具的解释方式。

### Pass 边界

```text
InputTexture
  -> Decode / normalize pixel format
  -> ColorTransformPass(colorEncoding)
  -> WorkingTexture
  -> LUT / FalseColor / Zebra / Scope
```

不要在各个 shader pass 中重复写 N-Log 或 HLG 曲线。颜色解释只能有一个入口，否则后续校准会变得不可控。

## 11. Scope 分析

### 当前状态

当前 `ScopePanel` 使用 `frame.phase` 生成程序曲线，无法反映画面真实亮度、RGB 通道或 LUT 效果。

### v0.2.1 要求

- 新增 `ScopeComputePass`。
- 使用 Metal compute 直接从工作纹理生成 Luma waveform bins。
- 使用 Metal compute 直接从工作纹理生成 RGB Parade bins。
- `ScopePanel` 只负责绘制 `ScopeData`。
- 分析频率可低于预览帧率，例如每 2 帧或每 3 帧分析一次。
- 当 scope 关闭时不执行分析。
- 当 App 在模拟器性能不足时，优先降低 compute grid / bin 分辨率，不影响主预览刷新。
- CPU 只读取最终 bins buffer，不读取完整帧像素。

默认参数：

```text
preview target: 30fps
scope analysis: 10-15fps
waveform bins: 256 x 128
rgb parade bins: 3 x 256 x 128
```

### GPU/CPU 同步

Scope bins 从 GPU 回读到 CPU 会引入同步风险，因此必须满足：

- 使用小型 `MTLBuffer` 存放 bins。
- readback 与渲染显示解耦，不阻塞 drawable present。
- 允许 UI 使用上一帧或上几帧的 scope bins。
- 如果 command buffer 尚未完成，`ScopePanel` 保持旧数据，不等待 GPU。

## 12. VideoFileFrameSource

### 目标

增加真实视频输入，解决只靠合成 ramp 无法验证 LUT、伪色、斑马纹和 scope 的问题。

### 要求

- 使用 `AVAssetReader` 读取本地视频。
- 输出 `VideoFrame`。
- 填充分辨率、帧率、时间戳和色彩编码。
- 播放结束后默认循环。
- 读取失败时回退到 `SimulatedFrameSource` 或展示短提示。
- 不移除 `SimulatedFrameSource`。
- 解码输出应优先选择能高效桥接 Metal 的 pixel format。
- 帧推送节奏由 `VideoFileFrameSource` 根据 sample timing 控制，不依赖 `AVPlayer`。

### UI

v0.2.1 可以先不做完整媒体库管理。可选入口：

- 设置页增加“选择测试视频”。
- 或 Debug section 增加“切换到视频文件源”。
- 或先只支持 bundle 内测试视频。

若实现用户选择视频，需要处理 security-scoped resource，并避免长期持有无效 URL。

## 13. SwiftUI 与 MTKView 集成

v0.2.1 固定使用 `UIViewRepresentable` 包装 `MTKView`。SwiftUI 继续负责监看界面的工具栏、状态栏、sheet、底部相机控制条和短提示；实时视频显示只由 `MTKView` 承担。

### 要求

- 新增 `MetalPreviewSurface`。
- `MetalPreviewSurface` 内部创建或接收 `MetalPreviewRenderer`。
- `MetalPreviewRenderer` 实现 `MTKViewDelegate`。
- `draw(in:)` 中获取当前最新 `VideoFrame`，提交 Metal command buffer，并 present drawable。
- SwiftUI 不应每帧生成 `Image`、`CGImage` 或 `Canvas` 内容。
- SwiftUI 状态变化只更新 renderer 的配置快照，例如 `MonitorState`、`LUTState`、viewport 和 zoom mode。
- 预览区域点击关闭参数调整浮层的交互必须保留。
- 工具栏和底部控制条不能拦截或阻塞 `MTKView` 的持续绘制。

### 状态同步

`MonitorSession` 负责接收 `FrameSource` 输出的 `VideoFrame`，renderer 读取最新帧时必须避免主线程长时间锁定。

使用轻量 frame store：

```swift
final class LatestFrameStore {
    func update(_ frame: VideoFrame)
    func snapshot() -> VideoFrame?
}
```

具体实现可以用 actor、lock 或 MainActor 隔离，但必须保证：

- 写入帧不会阻塞 UI 交互。
- renderer 读取不到新帧时继续显示上一帧。
- 停止监看或切换源时能安全释放旧 pixel buffer 引用。

## 14. 测试计划

v0.2.1 应建立 XCTest 目标，并至少覆盖以下内容。

### 单元测试

- `.cube` parser：合法 2x2x2 或 3x3x3 文件。
- `.cube` parser：缺少 `LUT_3D_SIZE`。
- `.cube` parser：数据行数量不匹配。
- `.cube` parser：非法 RGB 行。
- `.cube` parser：超过最大尺寸。
- 曝光模式规则：
  - `M` 允许光圈、快门、ISO。
  - `A` 锁快门。
  - `S` 锁光圈。
  - `P` 锁光圈和快门。
  - `Auto` 锁曝光参数和白平衡。
- `CameraCommandService` 拒绝当前曝光模式锁定的参数。
- `MockCameraTransport` 拒绝非法 option。
- `MonitorSession` toggle：
  - false color
  - zebra
  - scope mode
  - LUT enabled
  - LUT intensity

### Metal 图像处理测试

如果 Metal 输出不方便直接断言完整图像，至少应加入小尺寸 deterministic 输入和离屏 render / compute 测试：

- LUT identity 输入输出不变。
- LUT intensity 0 输出原图。
- LUT intensity 1 输出 LUT 后结果。
- 高亮像素触发 zebra。
- 低亮和高亮像素映射到不同 false color 区间。
- Rec.709 / N-Log / HLG 同一参考灰阶转换后落在预期亮度范围。
- 简单黑白 ramp 生成合理 waveform。
- RGB ramp 生成可区分的 RGB Parade 数据。
- Scope compute bins 与小尺寸 CPU reference 结果一致或在允许误差内。

### 手动验证

1. App 构建通过并进入监看界面。
2. 默认 `SimulatedFrameSource` 可持续刷新。
3. 如果选择视频源，视频能播放、循环或明确停止。
4. 开启 LUT 后，画面真实发生颜色变化。
5. LUT 强度 0%、50%、100% 可明显区分。
6. 开启伪色后，亮度不同区域显示不同颜色。
7. 调整斑马阈值后，高亮斑马区域随阈值变化。
8. Luma waveform 随画面内容变化。
9. RGB Parade 能反映 RGB 通道差异。
10. 关闭 scope 后性能负载下降或不再执行分析。
11. 底部相机控制条、曝光模式规则和短提示不回退。
12. LUT 导入错误仍能正常展示。

## 15. 性能目标

首版性能目标以 iPhone 12 Pro 监看体验为参考：

- 预览目标：30fps。
- Scope 分析：10-15fps 即可。
- LUT、伪色、斑马纹开启后，UI 交互不应明显卡死。
- 主线程不做逐像素循环。
- 实时主路径不做 CPU 全帧 readback。
- 大型 LUT 解析、3D texture 构建和视频解码不应阻塞主 UI。
- 如果处理压力过高，优先降低 scope compute 分辨率或分析频率，而不是降低预览流畅度。
- Drawable present 不应等待 scope bins readback。

## 16. 文件与模块建议

建议新增或调整：

```text
PrismBlade/
  Video/
    FrameSource.swift
    VideoFileFrameSource.swift
    MetalTextureBridge.swift
    MetalFrameProcessor.swift
    MetalPreviewRenderer.swift

  Imaging/
    LUTParser.swift
    LUTRepository.swift
    LUTStore.swift
    ColorTransformPass.swift
    LUTPass.swift
    FalseColorPass.swift
    ZebraPass.swift
    ScopeComputePass.swift

  Screens/
    Monitor/
      MonitorScreen.swift
      MetalPreviewSurface.swift
      ScopePanel.swift
      CameraControlPanel.swift

  PrismBladeTests/
    LUTParserTests.swift
    CameraExposureRulesTests.swift
    CameraCommandServiceTests.swift
    MockCameraTransportTests.swift
    MonitorSessionTests.swift
    MetalFrameProcessorTests.swift
    ScopeComputePassTests.swift
    ColorTransformPassTests.swift
```

命名可以根据实际实现微调，但边界应保持清楚：

- `Video` 负责媒体帧输入和 `CVPixelBuffer` 边界。
- `Imaging` 负责 LUT、曝光辅助、颜色转换和 scope 算法。
- `Metal` 相关 renderer / processor 负责 `MTLTexture` 工作帧和 GPU 资源生命周期。
- `Screens` 只负责显示和用户交互。
- `Camera` 继续只负责相机命令边界。

## 17. 真实相机通信预研

v0.2.1 不交付真实相机连接，但可以做不影响主线的预研准备：

- 保持 `CameraTransport` 稳定。
- 保持 `FrameSource` 可以被未来 live view source 替换。
- 可新增空 adapter 命名空间：
  - `ImageCaptureTransport`
  - `PTPTransport`
  - `NetworkBridgeTransport`
- adapter 内暂不实现 USB/PTP 细节。
- SwiftUI 不应出现 Nikon、USB、PTP 或 `libgphoto2` 类型。

后续硬件验证仍应单独进行：

- iPhone 12 Pro + Nikon Z6III USB 模式。
- Nikon `iPhone` USB 模式与普通 `MTP/PTP` 模式差异。
- ImageCaptureCore 能否满足发现、媒体访问、拍摄触发和参数控制。
- PTP/libgphoto2 思路在 iOS 上的权限、构建和合规风险。
- Wi-Fi、USB-LAN 或中继服务作为备选路线。

## 18. 开发计划

v0.2.1 的开发必须按可验证的纵向切片推进，而不是同时大面积改动帧源、renderer、shader、scope 和 UI。原因是 Metal-first 管线的失败点很多：Xcode project 配置、`CVPixelBuffer` 生命周期、`MTLTexture` 桥接、shader 输出、drawable present、GPU/CPU 同步和 SwiftUI 状态刷新都可能独立出错。分阶段开发可以让每一步都有可运行状态和清晰回退点。

### 阶段 0：文档与分支基线

目标：

- 固化 `TECHNICAL_SPEC_v0.2.1.md` 和 `TEST_PLAN_v0.2.1.md`。
- 从 `main` 创建 v0.2.1 集成分支。
- 保持 `main` 作为 v0.1.x 稳定原型。

主要工作：

- 提交 v0.2.1 技术文档和测试文档。
- 建立 `v0.2.1-metal-pipeline` 集成分支。
- 后续所有 v0.2.1 功能分支都从该集成分支切出。

验收标准：

- 文档在集成分支存在。
- `main` 不承担 v0.2.1 开发风险。

为什么先做：

- v0.2.1 会改核心架构，必须先把设计基线和稳定分支边界固定下来。

### 阶段 1：测试目标与 Fixtures

目标：

- 建立 XCTest 目标。
- 先准备可重复的图像、LUT 和 Metal 离屏测试基础。

主要工作：

- 新增 `PrismBladeTests`。
- 增加 pixel buffer test helper。
- 增加 `.cube` fixture generator。
- 增加小尺寸 CPU reference helper，用于 LUT、颜色转换、伪色、斑马纹和 scope bins 对比。
- 增加基础 Mock transport / 曝光模式规则测试。

涉及模块：

- `PrismBladeTests/`
- `LUTParser`
- `CameraExposureRules`
- `CameraCommandService`
- `MockCameraTransport`

验收标准：

- XCTest target 可运行。
- v0.1.3 已有 domain 规则有自动化保护。
- 可以在测试中生成小尺寸 `CVPixelBuffer` 和 `.cube` 文本。

为什么排在这里：

- 后面每个 Metal pass 都需要可重复的输入和 reference，否则只能靠肉眼看颜色，定位错误会非常慢。

### 阶段 2：媒体帧模型与帧源

目标：

- 把 `VideoFrame` 从模拟动画状态升级为 `CVPixelBuffer` 媒体帧。
- 让 `SimulatedFrameSource` 输出真实 pixel buffer。
- 新增 `VideoFileFrameSource`，使用 `AVAssetReader` 读取视频。

主要工作：

- 修改 `VideoFrame`。
- 保留 sequence、timestamp、format、metadata。
- 将 `SimulatedFrameSource` 的 ramp / 色块生成到 `CVPixelBuffer`。
- 新增 `VideoFileFrameSource`。
- 处理视频循环、读取失败、format 识别和 color encoding 初始策略。

涉及模块：

- `FrameSource.swift`
- `VideoFileFrameSource.swift`
- `MonitorSession.swift`
- `AppEnvironment.swift`

验收标准：

- App 可以继续启动。
- 默认 simulated source 仍有画面数据。
- 测试能确认输出帧包含真实 `CVPixelBuffer`。
- bundle 测试视频可以通过 `AVAssetReader` 输出帧。

为什么排在这里：

- Metal renderer 的输入必须先稳定。没有真实 media frame，后续 `CVMetalTextureCache`、LUT 和 scope 都无法可靠开发。

### 阶段 3：Metal 预览最小闭环

目标：

- 打通 `CVPixelBuffer -> MTLTexture -> MTKView drawable`。
- 先不做 LUT、伪色、斑马纹和 scope，只做原样显示。

主要工作：

- 新增 `MetalTextureBridge`。
- 新增 `MetalPreviewRenderer`。
- 新增 `MetalPreviewSurface`，用 `UIViewRepresentable` 包装 `MTKView`。
- 建立 `MTLDevice`、`MTLCommandQueue`、基础 render pipeline。
- 处理 drawable size、viewport、fit/fill/zoom 的最小实现。
- 保留点击预览关闭参数调整浮层。

涉及模块：

- `MetalTextureBridge.swift`
- `MetalPreviewRenderer.swift`
- `MetalPreviewSurface.swift`
- `MonitorScreen.swift`

验收标准：

- `MTKView` 能显示 simulated pixel buffer。
- SwiftUI 工具栏、底部控制条、sheet 和短提示仍可交互。
- 不再用 SwiftUI gradient 作为主预览。

为什么排在这里：

- 这是整条 Metal-first 管线的第一条纵向闭环。先让画面显示出来，后面的 shader pass 才能逐个接入并验证。

### 阶段 4：LUT 管线

目标：

- 实现 `.cube -> Metal 3D texture -> fragment shader sampling -> intensity mix`。

主要工作：

- 新增或扩展 `LUTStore`，能读取导入 LUT 的完整 entries。
- 将 parsed LUT 创建为 `MTLTextureType3D`。
- 增加 LUT fragment shader。
- 实现 LUT intensity 混合。
- 为内置 LUT 提供真实 `.cube` 资源，或移除 preview-only 内置项。

涉及模块：

- `LUTParser.swift`
- `LUTRepository.swift`
- `LUTStore.swift`
- `LUTPass.swift`
- Metal shader 文件
- `MetalFrameProcessor.swift`

验收标准：

- identity LUT 输出不变。
- intensity 0 / 0.5 / 1 结果可测试。
- 导入真实 `.cube` 后画面真实变色。
- LUT 不改变源 `CVPixelBuffer`。

为什么排在这里：

- LUT 是色彩监看的核心能力，并且它依赖基础 Metal 显示但不依赖 scope。先做 LUT 可以尽早验证 3D texture、采样精度和 shader 管线。

### 阶段 5：颜色转换与曝光辅助

目标：

- 实现 Rec.709 / N-Log / HLG 到统一显示工作空间的转换。
- 实现 Metal shader 伪色和斑马纹。

主要工作：

- 新增 `ColorTransformPass`。
- 集中实现 Rec.709 / N-Log / HLG 曲线。
- 让 LUT、伪色、斑马纹和 scope 都消费转换后的 working texture。
- 新增 `FalseColorPass`。
- 新增 `ZebraPass`。
- 保留现有 UI 开关和斑马阈值设置。

涉及模块：

- `ColorTransformPass.swift`
- `FalseColorPass.swift`
- `ZebraPass.swift`
- Metal shader 文件
- `MonitorModels.swift`
- `SettingsScreen.swift`

验收标准：

- Rec.709 / N-Log / HLG 参考灰阶转换测试通过。
- 灰阶 ramp 的伪色映射稳定。
- 斑马纹只出现在超阈值区域。
- 开关关闭时画面回到 LUT 后正常显示链路。

为什么排在 LUT 后：

- 伪色和斑马纹的判断必须基于统一颜色解释。先做 LUT 和 shader 资源管理，再接颜色转换与曝光辅助，可以减少并发变量。

### 阶段 6：Metal Compute Scope

目标：

- 用 Metal compute 直接生成 Luma waveform 和 RGB Parade bins。
- 让 `ScopePanel` 消费真实 `ScopeData`。

主要工作：

- 新增 `ScopeComputePass`。
- 建立 waveform bins buffer 和 RGB parade bins buffer。
- 控制 compute 执行频率。
- 做 GPU/CPU readback 解耦。
- `ScopePanel` 从程序曲线改为绘制 bins。

涉及模块：

- `ScopeComputePass.swift`
- `ScopePanel.swift`
- `MetalFrameProcessor.swift`
- Metal compute shader 文件

验收标准：

- 灰阶 ramp 生成合理 waveform。
- RGB ramp 生成可区分的 RGB Parade。
- scope off 时不执行 compute。
- readback 不阻塞 drawable present。

为什么排在这里：

- Scope 同时依赖真实帧、颜色转换、GPU 工作纹理和 readback 策略。它应该在显示与曝光辅助稳定后再接入。

### 阶段 7：集成、性能与真实素材验证

目标：

- 把 v0.2.1 的所有功能收敛为可运行版本。
- 用真实素材做手动验证。
- 确认 v0.1.3 交互不回退。

主要工作：

- 跑完整 XCTest。
- 模拟器构建验证。
- 使用 Rec.709 / N-Log / HLG 素材验证颜色转换。
- 使用真实 LUT 验证画面结果。
- 长时间运行观察内存、发热、掉帧和黑屏。
- 更新 README 和文档。

涉及模块：

- 全项目。

验收标准：

- v0.2.1 完成标准全部满足。
- 至少一组真实素材完成手动验证。
- `main` 合并前保持可构建、可运行、测试通过。

为什么最后做：

- 真实素材和性能问题只有在完整链路接通后才有意义。这个阶段不应再做大架构改动，只做收敛、修复和验证。

## 19. Git 分支规划

### 分支角色

```text
main
  稳定分支，保留当前 v0.1.x 可运行状态。
  不直接承接 v0.2.1 大规模开发。

v0.2.1-metal-pipeline
  v0.2.1 集成分支。
  所有 v0.2.1 短功能分支最终合入这里。

codex/v0.2.1-test-target
  阶段 1：测试目标与 fixtures。

codex/v0.2.1-frame-source
  阶段 2：VideoFrame、CVPixelBuffer、SimulatedFrameSource、AVAssetReader。

codex/v0.2.1-metal-renderer
  阶段 3：MTKView、MetalTextureBridge、MetalPreviewRenderer、基础显示。

codex/v0.2.1-lut-pass
  阶段 4：Metal 3D LUT texture、fragment shader、强度混合。

codex/v0.2.1-color-exposure
  阶段 5：Rec.709 / N-Log / HLG、伪色、斑马纹。

codex/v0.2.1-scope-compute
  阶段 6：Metal compute waveform / RGB Parade bins。

codex/v0.2.1-integration
  阶段 7：集成、性能保护、真实素材验证、文档同步。
```

### 分支创建顺序

1. 从 `main` 创建 `v0.2.1-metal-pipeline`。
2. 将 v0.2.1 技术文档和测试文档提交到 `v0.2.1-metal-pipeline`。
3. 从 `v0.2.1-metal-pipeline` 创建每个短功能分支。
4. 短功能分支完成后合回 `v0.2.1-metal-pipeline`。
5. `v0.2.1-metal-pipeline` 完成全部验收后再合回 `main`。

### 合并规则

- 短功能分支只合并到 `v0.2.1-metal-pipeline`，不直接合并到 `main`。
- 每条短功能分支都应尽量保持小范围 ownership，避免多个分支长期改同一批文件。
- 涉及 `project.pbxproj` 的改动优先集中在 `test-target` 和 `metal-renderer` 阶段，减少 Xcode project 冲突。
- 每次合并前至少完成：
  - Xcode build。
  - 当前阶段相关 XCTest。
  - v0.1.3 核心交互 smoke test。
- 如果某个阶段中途无法保持 App 可运行，应在该短分支内解决，不把半断裂状态合入集成分支。

### 为什么这样设计

- `main` 保留稳定原型，避免 v0.2.1 架构迁移期间无法演示。
- `v0.2.1-metal-pipeline` 提供一个持续集成点，避免所有功能等到最后才第一次相遇。
- 短分支按依赖顺序拆分，能减少 Metal 管线开发中的定位成本。
- 测试目标先行，让后续 shader 和颜色转换有自动化 reference。
- Scope compute 放在后面，因为它依赖帧模型、Metal 显示、颜色转换和 GPU/CPU 同步策略。

## 20. v0.2.1 完成标准

v0.2.1 完成时，应满足：

- Xcode Simulator 构建通过。
- 建立 XCTest 测试目标，并且核心单元测试通过。
- 预览显示不再完全依赖 SwiftUI gradient/overlay 占位。
- `VideoFrame` 使用 `CVPixelBuffer` 表达媒体帧。
- `MetalTextureBridge` 能稳定完成 `CVPixelBuffer -> MTLTexture` 桥接。
- `MetalFrameProcessor` 能接收帧和监看状态并输出显示结果。
- `MTKView` 通过 `UIViewRepresentable` 集成到 SwiftUI。
- `.cube` LUT 能真实改变显示像素。
- `.cube` LUT 被转换为 Metal 3D texture，并由 fragment shader 采样。
- LUT 强度滑杆真实有效。
- 伪色由 Metal shader 基于亮度 / IRE 映射。
- 斑马纹由 Metal shader 基于亮度阈值显示。
- Luma waveform 由 Metal compute bins 生成。
- RGB Parade 由 Metal compute bins 生成。
- Rec.709 / N-Log / HLG 输入经过明确颜色转换 pass。
- `VideoFileFrameSource` 使用 `AVAssetReader` 播放测试视频，或至少完成可运行的 bundle 视频源。
- `SimulatedFrameSource` 仍可作为 fallback。
- v0.1.3 的底部相机控制条、曝光模式锁定、短提示、LUT 导入流程、scope 避让和设置页功能不回退。
- 真实 Nikon 通信仍停留在边界或预研层，不进入 UI 主路径。

## 21. 与 v0.1.3 的关系

v0.1.3 解决的是监看交互闭环：底部控制条、曝光模式限制、禁用提示、点击预览关闭调整浮层、scope 避让等。v0.2.1 继承这些交互，不重新设计主界面。

v0.2.1 解决的是图像真实性闭环：同样的按钮和开关继续存在，但它们背后不再只是 SwiftUI 占位效果，而是进入真实帧处理、真实 LUT、真实曝光辅助和真实 scope 分析。

因此，v0.2.1 的开发优先级应是：

1. 建立帧数据和处理管线。
2. 打通真实预览显示。
3. 接入真实 LUT。
4. 接入伪色和斑马纹。
5. 接入 Rec.709 / N-Log / HLG 颜色转换。
6. 接入 Metal compute scope。
7. 增加视频文件输入。
8. 补测试和性能保护。
9. 最后再做通信 adapter 预研。
