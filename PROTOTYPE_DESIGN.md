# iOS 相机监看 App 原型设计方案

状态：讨论稿  
目标设备：iPhone 12 Pro  
目标相机：Nikon Z6III  
当前阶段：只做模拟器可运行的监看原型，不实现 USB/PTP 相机通信

## 1. 原型目标

先做一个“可用的监看 App 骨架”，重点验证监看体验和图像辅助工具，而不是相机连接。

本阶段原型应支持：

- 视频画面显示：使用模拟帧源、内置测试片段或示例图片序列。
- 曝光辅助：伪色、斑马纹。
- 信号分析：亮度波形图、RGB Parade、直方图优先级可后置。
- 色彩工作流：导入真实 `.cube` LUT、选择 LUT、调节 LUT 强度、显示 LUT 前后效果。
- 监看控制：缩放、画面适配、全屏、工具开关、基础状态栏。
- 相机控制占位：ISO、快门、光圈、白平衡、录制、拍照、对焦都进入首版 UI 和 Mock 状态模型。
- 通信预留：为后续 libgphoto2/PTP/Nikon USB 接入提供抽象接口和模拟实现。

不做：

- 不连接真实 Nikon 相机。
- 不移植 libgphoto2。
- 不处理 iOS 真机 USB 权限、MFi、线缆兼容性、PTP 实机命令。
- 不承诺模拟器性能等于 iPhone 12 Pro 真机性能。

## 2. 关键约束与风险

### iOS 模拟器

Xcode Simulator 适合快速验证 UI、状态流和部分渲染逻辑，但 Apple 文档明确提醒，模拟器不能完全复现真实硬件能力。当前原型应把“视频输入”设计成可替换的 `FrameSource`，而不是依赖真实摄像头或 USB 设备。

建议模拟帧源：

- 本地视频文件：用于验证连续画面、LUT、斑马纹、示波器刷新。
- 静态测试图：灰阶、肤色卡、过曝/欠曝图、Log 曲线样张。
- 程序生成图：亮度坡度、RGB ramp、checkerboard、移动色块，用于回归测试。

### Nikon Z6III + iPhone USB

Nikon 官方手册显示 Z6III 的 USB 菜单包含 `MTP/PTP`、`iPhone`、`USB-LAN` 等模式；连接 iPhone 使用 NX MobileAir 时需要选择 `iPhone` 模式。后续自研 App 是否能直接复用相同有线通道，需要实机验证。

Apple 的 `ImageCaptureCore` 文档显示 iOS/iPadOS 侧可以发现相机、浏览媒体、执行 tethered capture 等能力；`ExternalAccessory` 则面向 MFi accessory 通信。后续通信路线不能过早锁死在单一路径，需要同时预留：

- `ImageCaptureCore` 路线：优先验证是否能满足 Nikon 连接、媒体访问、拍摄触发。
- 自研 PTP/libgphoto2 路线：用于更深的属性控制和事件处理，但 iOS USB 访问边界需单独验证。
- 网络备选路线：如果有线 USB 在 iOS 上受限，保留 Wi-Fi/USB-LAN/中继服务的扩展空间。

### libgphoto2

libgphoto2 以 PTP/MTP 等相机协议为核心，适合参考相机模型、能力枚举、属性读写、事件处理和 capture 流程。但它是偏 Unix-like 的 C 库，后续在 iOS 上直接移植会遇到构建、USB backend、权限和 App Store 合规等问题。

本阶段只把它当作后续通信层的“能力参考”，不要让 UI 或图像处理层依赖 libgphoto2 类型。

## 3. 产品原型

### 主界面布局

第一屏就是监看画面，不做登录页或介绍页。

默认横屏：

- 视频画面全屏优先，横屏是主工作流和默认启动方向。
- 顶部轻量状态条：连接状态、输入格式、帧率、LUT、曝光工具状态、电量/存储占位。
- 左右两侧浮动工具按钮：伪色、斑马纹、波形、LUT、缩放、截图/录制占位。
- 示波器默认作为底部半透明面板覆盖显示，可收起或调整高度。
- 相机控制面板从右侧滑出：ISO、快门、光圈、WB、对焦、录制。
- 所有核心监看控件必须优先适配横屏下单手触达和不遮挡画面主体。

竖屏可选模式：

- 默认不开启；在设置中提供“允许竖屏拍摄/监看”开关。
- 开启后 App 才允许进入竖屏布局，适合竖构图拍摄。
- 中央：9:16 或相机实际比例的视频预览，支持 fit/fill。
- 顶部状态条保留核心信息，减少横向内容拥挤。
- 底部工具条承载常用监看工具，右侧可展开相机控制面板。
- 竖屏模式状态应持久化，但不改变横屏作为默认监看体验的原则。

### 工具交互

- 伪色：一键开关，支持预设映射，例如 IRE false color、曝光区间提示。
- 斑马纹：一键开关，支持阈值滑杆，例如 70%、90%、100%。
- 示波器：首版支持亮度 waveform 和 RGB Parade；可调大小和透明度。
- LUT：支持 Off、内置 LUT、用户导入真实 `.cube` LUT，并支持强度调节。
- 缩放：1x、2x、fit、fill；后续可扩展 pinch-to-zoom 和局部放大。
- 对焦辅助：本阶段可作为二期，边缘峰值需要额外 GPU pass。

## 4. 技术架构

建议采用 Swift + SwiftUI 外壳，核心视频渲染使用 Metal / Core Image。SwiftUI 负责状态和面板，Metal/Core Image 负责实时图像处理。

```text
App Shell (SwiftUI)
  ├─ MonitorView
  ├─ ToolPanels
  ├─ CameraControlPanel
  └─ Settings / LUT Manager

State & Domain
  ├─ MonitorSession
  ├─ CameraState
  ├─ ExposureToolState
  ├─ LUTState
  └─ RecordingState placeholder

Video Pipeline
  ├─ FrameSource protocol
  │   ├─ SimulatedFrameSource
  │   ├─ VideoFileFrameSource
  │   └─ FutureCameraFrameSource
  ├─ FrameProcessor
  │   ├─ LUTPass
  │   ├─ FalseColorPass
  │   ├─ ZebraPass
  │   └─ ScopeAnalyzer
  └─ Renderer
      ├─ MetalPreviewRenderer
      └─ ScopeOverlayRenderer

Camera Communication
  ├─ CameraTransport protocol
  │   ├─ MockCameraTransport
  │   ├─ FutureImageCaptureTransport
  │   ├─ FuturePTPTransport
  │   └─ FutureNetworkBridgeTransport
  └─ CameraCommandService
```

## 5. 核心抽象

### FrameSource

负责提供画面帧，不关心帧来自视频文件、模拟器、真实相机或网络。

职责：

- 输出帧图像、时间戳、色彩空间、分辨率、帧率。
- 暴露启动、暂停、停止。
- 报告输入状态和错误。

预留字段：

- `cameraMetadata`：ISO、快门、光圈、WB、picture profile、Log/HLG 状态。
- `transportLatency`：后续监控 USB/网络延迟。
- `sourceColorEncoding`：Rec.709、N-Log、HLG、RAW preview 等。

### FrameProcessor

负责所有监看工具的处理顺序。

推荐处理顺序：

1. 输入帧标准化：纹理格式、方向、色彩空间。
2. LUT：可选择在监看显示链路中应用，不改变原始帧。
3. 曝光辅助：伪色或斑马纹作为 overlay/pass。
4. Scope 分析：从处理前或处理后帧采样，默认以显示链路为准，可配置。
5. 输出给预览层和示波器层。

### CameraTransport

为后续相机通信保留的最重要边界。UI 只认识“相机能力”和“相机命令”，不认识 USB、PTP、libgphoto2。

职责：

- 发现相机、连接/断开。
- 枚举能力：可控参数、取值范围、只读状态。
- 读写参数：ISO、快门、光圈、WB、Picture Control、对焦模式。
- 触发动作：半按、拍照、开始/停止录制、开始/停止 live view。
- 事件流：属性变化、相机断开、电量变化、存储卡状态、错误。

当前实现：

- `MockCameraTransport`：用固定能力表和延迟模拟真实通信。
- 所有控制 UI 都打到 mock transport，便于后续替换真实实现。

## 6. 图像功能方案

### 伪色

输入：亮度值或经过显示变换后的 luma。  
输出：按曝光区间映射的颜色 overlay。

第一版建议用 Rec.709 显示亮度做判断，方便用户直观看到效果。后续如果接 N-Log，需要增加“Log 输入解释”和“IRE 映射模式”。

建议预设：

- 0-5 IRE：紫/蓝，提示接近死黑。
- 18 IRE 附近：中灰提示。
- 40-60 IRE：肤色/主体安全区。
- 90-100 IRE：高光警告。
- 100+：红色过曝。

### 斑马纹

第一版实现两个模式：

- High Zebra：高于阈值显示斜线，例如 90%。
- Range Zebra：落在某个区间显示斜线，例如 65-75% 肤色参考。

斑马纹应该作为 overlay，不改变底图。

### 示波器

第一版优先做亮度 waveform 和 RGB Parade：

- 横轴对应画面 x 坐标。
- 纵轴对应亮度。
- Luma waveform 显示整体亮度分布。
- RGB Parade 分别显示 R/G/B 通道分布，帮助判断偏色和通道裁切。
- 每帧或隔帧采样，避免模拟器卡顿。
- 在 iPhone 12 Pro 目标上以 30fps 监看为第一性能目标。

第二版：

- Histogram。
- 可切换分析源：LUT 前 / LUT 后。

### LUT

第一版：

- 内置几组测试 LUT。
- 支持通过文件导入真实 `.cube` LUT。
- 支持 LUT 开关和强度滑杆。
- 实现 `.cube` 解析、校验、错误提示和导入状态管理。
- LUT pipeline 支持 1D/3D 接口设计，但首版实现优先 3D `.cube`。

第二版：

- LUT 预览缩略图。
- LUT 分组和收藏。

## 7. 状态模型

建议把状态分成四类，避免后续通信接入时互相污染。

- `ConnectionState`：未连接、搜索中、已连接、连接中断、错误。
- `CameraState`：相机当前参数、电量、存储、录制状态、live view 状态。
- `MonitorState`：UI 工具状态、LUT、scope 类型、overlay 开关、缩放状态。
- `OrientationState`：默认横屏、是否允许竖屏、当前界面方向、当前画面适配方式。

Mock 阶段也要完整走状态流，这样后续真实相机只是替换 transport。

## 8. 开发里程碑

### M0：方案确认

- 确认目标功能优先级。
- 确认 SwiftUI + Metal/Core Image 技术路线。
- 确认当前只做模拟器，不做真机 USB。

### M1：可运行监看壳

- Xcode 项目骨架。
- SwiftUI 横屏优先主界面。
- 设置页提供“允许竖屏拍摄/监看”开关。
- 竖屏布局只在开关开启后启用。
- 模拟帧源。
- 视频预览。
- 工具状态管理。

### M2：曝光工具

- 伪色。
- 斑马纹。
- 工具开关和阈值控制。
- 基础性能测试。

### M3：示波器

- Luma waveform。
- RGB Parade。
- Scope overlay 面板。
- 采样频率控制。

### M4：LUT

- 内置 LUT。
- 真实 `.cube` 文件导入。
- `.cube` 解析、校验和错误提示。
- LUT 强度调节。
- LUT 资源管理基础结构。

### M5：相机控制 Mock

- 相机控制面板：ISO、快门、光圈、WB、录制、拍照、对焦全部出现。
- Mock 能力表。
- Mock 参数读写。
- Mock 录制、拍照、对焦动作反馈。
- 连接/断开/错误状态模拟。

### M6：真机通信预研

- 在 iPhone 12 Pro + Nikon Z6III 上验证 USB 连接路径。
- 分别验证 ImageCaptureCore、Nikon iPhone USB 模式、PTP/libgphoto2 思路。
- 根据实机结果决定后续通信实现路线。

## 9. 建议第一版取舍

第一版应优先完成：

- 画面预览。
- 默认横屏监看布局。
- 竖屏拍摄/监看开关和对应布局。
- 伪色。
- 斑马纹。
- 亮度 waveform。
- RGB Parade。
- 真实 `.cube` LUT 导入、开关和强度调节。
- Mock 相机控制面板：ISO、快门、光圈、WB、录制、拍照、对焦。

暂缓：

- 真实相机连接。
- 录制文件。
- 对焦峰值。
- 多 LUT 管理。
- 3D LUT 高性能优化。
- Histogram。

原因是第一版最重要的是证明监看工具链和 UI 状态模型成立；真实相机通信可以等边界稳定后独立接入。

## 10. 已确认决策

1. 目标相机确认是 Nikon Z6III。
2. 竖屏开关放在设置页即可，主监看界面不提供快捷入口。
3. LUT 首版使用真实 `.cube` 文件导入，不只做内置测试 LUT。
4. RGB Parade 进入首版，与亮度 waveform 一起实现。
5. 相机控制 UI 首版包含 ISO、快门、光圈、WB、录制、拍照、对焦。

## 11. 参考资料

- Apple Developer：[`ImageCaptureCore`](https://developer.apple.com/documentation/imagecapturecore) 可发现和控制相机，并支持 tethered capture 相关能力。
- Apple Developer：[`ExternalAccessory`](https://developer.apple.com/documentation/externalaccessory) 面向 Lightning/MFi accessory 通信。
- Apple Developer：[`Running your app in Simulator or on a device`](https://developer.apple.com/documentation/Xcode/running-your-app-in-simulator-or-on-a-device) 说明模拟器适合调试但不能完全复现硬件能力。
- Nikon Z6III 在线手册：[`USB`](https://onlinemanual.nikonimglib.com/z6III/en/nwm_usb_data_connection_368.html) 说明 `MTP/PTP`、`iPhone`、`USB-LAN` 等 USB 模式。
- Nikon Z6III 产品规格：[`Z6III | Nikon Consumer`](https://imaging.nikon.com/imaging/lineup/mirrorless/z6_3/) 标明 USB Type-C SuperSpeed USB、HDMI Type-A 等接口。
- gphoto 项目：[`libgphoto2`](https://github.com/gphoto/libgphoto2) 是相机访问和控制库，支持 PTP/MTP 等相机通信协议。
