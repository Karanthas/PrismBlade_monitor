# PrismBlade v0.2.1 测试文档

版本：v0.2.1  
日期：2026-05-13  
关联文档：`TECHNICAL_SPEC_v0.2.1.md`  
测试目标：验证 Metal-first 真实像素监看管线、视频帧源、LUT、曝光辅助、scope、颜色空间转换和 v0.1.3 交互不回退。

## 1. 测试范围

v0.2.1 的测试重点从“UI 能不能点”升级为“图像处理结果是否可信”。测试必须覆盖：

- `CVPixelBuffer` 媒体帧输入。
- `CVPixelBuffer -> MTLTexture` 桥接。
- `AVAssetReader` 视频文件帧源。
- Metal 渲染主路径。
- Metal 3D LUT texture 和 fragment shader 采样。
- LUT 强度混合。
- Metal shader 伪色。
- Metal shader 斑马纹。
- Rec.709 / N-Log / HLG 转换。
- Metal compute 生成 Luma waveform / RGB Parade bins。
- `UIViewRepresentable + MTKView` 集成。
- v0.1.3 已有监看交互不回退。

不在 v0.2.1 自动化测试范围内：

- 真实 Nikon Z6III USB/PTP 连接。
- 真实相机 live view。
- 真实录制文件保存。
- 实机 USB 权限和线缆兼容性。

## 2. 测试资产分类

### 我可以模拟或生成的资产

这些可以在仓库测试代码中直接生成，不需要你额外提供：

- 小尺寸 `CVPixelBuffer`：
  - 纯黑、纯白、18% gray。
  - 水平灰阶 ramp。
  - RGB ramp。
  - 棋盘格。
  - 单通道红/绿/蓝测试图。
  - 高光 clipping 区域测试图。
- `.cube` LUT 文本：
  - identity LUT。
  - 单通道 ramp LUT。
  - 暖色偏移 LUT。
  - 非法尺寸 LUT。
  - 数据行数量不匹配 LUT。
  - 非法浮点数据 LUT。
  - 非 0...1 domain LUT。
- Metal 离屏测试输入：
  - 小尺寸 texture。
  - 小尺寸 3D LUT texture。
  - 小尺寸 scope bins buffer。
- Mock 相机状态：
  - M / A / S / P / Auto 曝光模式。
  - 支持/不支持的 parameter options。
  - Mock disconnect / reconnect。

### 需要你提供的素材

这些需要真实素材才能验证主观效果、颜色解释和视频解码路径：

- Rec.709 测试视频。
- Nikon Z6III N-Log 测试视频。
- HLG 测试视频。
- Nikon Z6III 实拍素材：
  - 正常曝光。
  - 欠曝。
  - 过曝高光。
  - 肤色场景。
  - 高饱和色块或色卡。
  - 暗部噪声场景。
- 真实 `.cube` LUT：
  - Nikon 官方或常用 N-Log -> Rec.709 LUT。
  - 创意 LUT。
  - 大尺寸 LUT，例如 33^3 或 65^3。
- 参考图片或截图：
  - 同一素材在 DaVinci Resolve / Final Cut / Nikon 官方查看器中应用 LUT 后的参考画面。
  - Waveform / RGB Parade 参考截图。
- 真机测试条件：
  - iPhone 12 Pro 或目标真机。
  - Nikon Z6III。
  - 对应 USB-C / Lightning 转接线或采集链路。

## 3. 自动化测试

### 3.1 数据模型与帧输入

目标：确认媒体边界使用 `CVPixelBuffer`，GPU 工作边界使用 `MTLTexture`。

可模拟：

- 创建 2x2、16x16、256x144 `CVPixelBuffer`。
- 验证 `VideoFrame` 能携带 sequence、timestamp、format、pixelBuffer、metadata。
- 验证 `SimulatedFrameSource` 输出真实 pixel buffer，而不是只输出 `phase`。
- 验证 frame format 正确记录分辨率、帧率和 color encoding。

需要你提供：

- 无。

通过标准：

- 自动化测试可稳定构造和读取测试 pixel buffer。
- `VideoFrame` 不再依赖 SwiftUI 合成状态表达画面。

### 3.2 CVPixelBuffer 到 MTLTexture 桥接

目标：确认 `MetalTextureBridge` 能稳定把媒体帧转为 GPU 工作帧。

可模拟：

- 生成 BGRA `CVPixelBuffer`。
- 使用 `CVMetalTextureCache` 转换为 `MTLTexture`。
- 验证 texture 尺寸、pixel format、usage。
- 用离屏 shader 采样 texture，验证颜色与源 pixel buffer 一致。
- 测试无效 pixel buffer 或不支持 pixel format 的错误路径。

需要你提供：

- 可选：真实视频解码出的 YCbCr pixel buffer 样本，用于确认非 BGRA 输入路径。

通过标准：

- BGRA 输入桥接稳定。
- 失败时返回明确错误，不静默黑屏。
- renderer 不在 SwiftUI 层直接处理 texture。

### 3.3 AVAssetReader 视频帧源

目标：确认 `VideoFileFrameSource` 能读取视频并按时间输出 `VideoFrame`。

可模拟：

- 使用测试 bundle 中的小视频。
- 验证能读取 sample buffer / pixel buffer。
- 验证 sequence 递增。
- 验证 timestamp 单调递增。
- 验证播放结束后循环。
- 验证读取失败时回退或报错。

需要你提供：

- Rec.709 测试视频。
- N-Log 测试视频。
- HLG 测试视频。
- 真实 Nikon Z6III 视频样本。

通过标准：

- bundle 视频可稳定读取。
- 用户素材能正确识别格式、分辨率、帧率和 color encoding。
- 不依赖 `AVPlayer` 抽帧。

### 3.4 LUT Parser 与 LUT Store

目标：确认 `.cube` 文件解析、校验、存储和读取可靠。

可模拟：

- identity LUT。
- 数据数量不匹配。
- 缺少 `LUT_3D_SIZE`。
- 非法 RGB 行。
- 超过最大支持尺寸。
- `DOMAIN_MIN` / `DOMAIN_MAX`。
- warning 路径。

需要你提供：

- 常用真实 `.cube` LUT。
- Nikon N-Log 相关 LUT。
- 大尺寸 33^3 / 65^3 LUT。

通过标准：

- 合法 LUT 可解析。
- 非法 LUT 有明确错误。
- 导入成功后 index 可恢复。
- 真实 LUT 不会因 parser 假设过窄而误拒绝。

### 3.5 Metal 3D LUT Texture 与采样

目标：确认 `.cube` entries 到 3D texture 的排列顺序、采样和强度混合正确。

可模拟：

- identity LUT：输出等于输入。
- 单通道 ramp LUT：只改变指定通道。
- 小尺寸 2^3 / 3^3 LUT：逐点验证。
- intensity 0：输出原图。
- intensity 0.5：输出为原图和 LUT 结果中间值。
- intensity 1：输出完整 LUT 结果。

需要你提供：

- 真实 LUT 与参考渲染截图。
- 用同一素材在专业软件中应用 LUT 后的参考结果。

通过标准：

- 小尺寸 deterministic 测试误差在允许范围内。
- identity LUT 不引入明显色偏。
- 强度滑杆结果连续、可预测。

### 3.6 颜色空间转换

目标：确认 Rec.709 / N-Log / HLG 输入进入统一显示工作空间。

可模拟：

- 构造 Rec.709 灰阶 ramp。
- 构造 N-Log 编码灰阶参考值。
- 构造 HLG 编码灰阶参考值。
- 对比 shader 输出与 CPU reference 曲线。
- 验证 luma 计算集中在 `ColorTransformPass` 之后。

需要你提供：

- Nikon Z6III N-Log 实拍素材。
- HLG 实拍素材。
- 对应官方或可信参考转换结果。
- 灰卡、色卡、肤色场景素材。

通过标准：

- Rec.709 / N-Log / HLG 同一参考灰阶转换后落在预期亮度范围。
- shader 与 CPU reference 误差在允许范围内。
- 伪色、斑马纹和 scope 不各自重复实现 Log/HLG 曲线。

### 3.7 Metal 伪色

目标：确认伪色按统一亮度解释映射，而不是整屏占位 overlay。

可模拟：

- 灰阶 ramp 输入。
- 0-5 IRE 区间。
- 18 IRE 中灰点。
- 40-60 IRE 主体区间。
- 90-100 IRE 高光区间。
- 100+ clipping 区间。
- Rec.709 / N-Log / HLG 转换后的同一亮度区间。

需要你提供：

- 真实肤色素材。
- 欠曝、正常、过曝素材。
- 你偏好的 false color 映射参考。

通过标准：

- 同一亮度区间映射到稳定颜色。
- 伪色开启后不改变源帧。
- 关闭伪色后画面恢复正常显示链路。

### 3.8 Metal 斑马纹

目标：确认斑马纹只出现在超过阈值的像素区域。

可模拟：

- 灰阶 ramp。
- 单一高光方块。
- 阈值 70 / 90 / 100。
- 不同分辨率和缩放模式。
- 斜线图案坐标稳定性。

需要你提供：

- 真实过曝场景。
- 肤色高光场景。
- 你想采用的 zebra 参考阈值习惯。

通过标准：

- 阈值升高时 zebra 区域减少。
- 阈值降低时 zebra 区域增加。
- 斜线只覆盖超阈值区域。
- 关闭 zebra 后无残留 overlay。

### 3.9 Metal Compute Scope

目标：确认 Luma waveform 和 RGB Parade bins 由 GPU compute 生成。

可模拟：

- 水平灰阶 ramp。
- 垂直灰阶 ramp。
- RGB ramp。
- 单色红/绿/蓝块。
- 高光 clipping 块。
- 小尺寸 CPU reference bins。
- scope off 时不执行 compute。
- readback 延迟时 UI 使用旧数据。

需要你提供：

- 真实视频素材的 waveform / parade 参考截图。
- 色卡或测试卡视频。
- 你希望 scope 显示的样式参考。

通过标准：

- waveform 反映画面横向亮度分布。
- RGB Parade 能区分 R/G/B 通道差异。
- scope bins 与 CPU reference 在允许误差内。
- scope readback 不阻塞 drawable present。

### 3.10 MTKView 集成

目标：确认 SwiftUI 负责 UI，`MTKView` 负责实时预览。

可模拟：

- 启动 monitor screen。
- renderer 持续绘制。
- SwiftUI 状态切换不打断绘制。
- 点击预览区域仍关闭参数调整浮层。
- 工具栏、sheet、底部控制条正常响应。
- drawable size 改变时重建资源。

需要你提供：

- 真机横屏/竖屏使用反馈。
- 长时间监看体验反馈。

通过标准：

- 不使用 SwiftUI `Image` / `Canvas` 做逐帧视频渲染。
- `MTKView` 不被工具栏遮挡到无法绘制。
- UI 操作不造成明显掉帧或黑屏。

### 3.11 相机 Mock 与 v0.1.3 回归

目标：确保 v0.2.1 图像管线开发不破坏已有交互。

可模拟：

- 曝光模式规则：
  - `M`：光圈、快门、ISO 可调。
  - `A`：快门锁定。
  - `S`：光圈锁定。
  - `P`：光圈和快门锁定。
  - `Auto`：曝光参数和白平衡锁定。
- 禁用参数短提示。
- 点击预览关闭参数调整浮层。
- Scope 避让底部参数浮层。
- LUT 导入错误展示。
- Mock reconnect / disconnect。

需要你提供：

- 无。

通过标准：

- v0.1.3 完成标准全部不回退。

## 4. 手动测试

### 模拟器手动测试

可由我执行：

1. 构建 App。
2. 启动进入监看界面。
3. 切换伪色、斑马纹、scope、LUT、缩放。
4. 切换 Mock 曝光模式并验证锁定提示。
5. 导入合法和非法 LUT。
6. 播放 bundle 测试视频。
7. 验证 scope 打开/关闭时性能和 UI 行为。

需要你提供：

- 如果要验证用户导入视频，需要你提供测试视频文件。
- 如果要验证真实 LUT 主观效果，需要你提供 LUT 和参考图。

### 真机手动测试

需要你执行或提供环境：

1. iPhone 12 Pro 真机运行。
2. 长时间监看 10-30 分钟。
3. 切换 LUT、伪色、斑马纹、scope。
4. 观察发热、掉帧、黑屏、UI 卡顿。
5. 使用真实 Nikon Z6III 素材验证 N-Log / HLG。
6. 对比专业软件中的 LUT 和 scope 参考。

需要你提供：

- 真机测试结果。
- 屏幕录制或截图。
- 出现问题时的素材、操作步骤和日志。

## 5. 素材清单

### 阶段 5 当前策略

阶段 5 首轮开发先使用程序生成素材推进：

- 自动化测试生成灰阶 ramp、18% 中灰、clipping 高光、RGB 色块和小尺寸 float texture。
- Metal 离屏测试验证 Rec.709 / N-Log / HLG 曲线入口、false color 分段和 zebra 阈值。
- 这些生成素材用于证明算法链路正确，不用于最终颜色校准。

真实灰卡、色卡、肤色和参考 waveform 到位后，再补充深度验证用例和人工校准记录。

### 最小素材包

为了让 v0.2.1 开发可闭环，建议你至少提供：

- 一个 Rec.709 测试视频。
- 一个 Nikon Z6III N-Log 视频。
- 一个 HLG 视频。
- 一个真实 `.cube` LUT。
- 一个 N-Log -> Rec.709 LUT。
- 一组参考截图：
  - LUT 前。
  - LUT 后。
  - Waveform。
  - RGB Parade。

### 理想素材包

如果要把色彩和监看工具做得更可靠，建议补充：

- 灰卡视频。
- 色卡视频。
- 肤色视频。
- 欠曝视频。
- 正常曝光视频。
- 过曝高光视频。
- 暗部噪声视频。
- 高饱和红/绿/蓝场景。
- 33^3 LUT。
- 65^3 LUT。
- 同一素材在 DaVinci Resolve 或 Final Cut 中的参考结果。

## 6. 测试分工

### 我可以完成

- 编写 XCTest。
- 生成小尺寸 pixel buffer 测试图。
- 生成测试 `.cube` 文件。
- 做离屏 Metal render / compute 测试。
- 验证 Mock 相机和 UI 状态回归。
- 在模拟器上运行构建和基础手动测试。
- 使用你提供的素材加入测试 bundle 或手动验证流程。

### 需要你完成或提供

- Nikon Z6III N-Log / HLG / Rec.709 实拍素材。
- 真实 LUT 文件。
- 专业软件参考截图。
- iPhone 12 Pro 真机验证。
- 长时间运行体验反馈。
- 如果后续进入真实通信预研，需要提供相机、线缆、连接方式和测试结果。

## 7. 通过标准

v0.2.1 测试通过至少需要满足：

- XCTest 核心测试通过。
- 合成 pixel buffer 可稳定进入 Metal 管线。
- `AVAssetReader` 能读取测试视频并输出 `CVPixelBuffer`。
- `CVPixelBuffer -> MTLTexture` 桥接稳定。
- Metal 3D LUT、伪色、斑马纹、scope compute 有自动化覆盖。
- Rec.709 / N-Log / HLG 转换有 reference 测试。
- `MTKView` 集成后监看 UI 可交互。
- v0.1.3 交互回归通过。
- 至少一组真实素材完成手动验证。

## 8. 风险与补救

- 如果 N-Log / HLG 参考素材不足，颜色转换测试只能先通过合成曲线和 CPU reference 验证，真实观感风险保留。
- 如果没有真实 waveform / parade 参考截图，scope 只能验证算法一致性，无法验证专业工具显示习惯是否完全一致。
- 如果没有 iPhone 12 Pro 真机，性能目标只能在模拟器和通用构建中初步验证。
- 如果真实 `.cube` LUT 格式变体不足，parser 可能遗漏某些实际 LUT 文件写法。
- 如果视频素材都是短片段，无法充分发现长时间运行的内存和发热问题。
