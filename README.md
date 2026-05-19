# PrismBlade

**PrismBlade** is an iOS camera monitoring prototype for a Nikon Z6III workflow. The current branch has moved from the `v0.2.2` N-Log / LUT exposure-chain correction into the `v0.2.3` scope readability pass. The project now has a real `CVPixelBuffer` media frame model, a BGRA simulated frame source, an `AVAssetReader` video-file frame source, a `CVPixelBuffer -> MTLTexture -> MTKView drawable` Metal preview loop, display-only 3D LUT sampling, explicit raw / preview / analysis signal separation, shader-based false color / zebra exposure assists, and higher-resolution Metal compute scope bins for Luma waveform / RGB Parade.

> Chinese version: [README.zh-CN.md](README.zh-CN.md)

## Status

This repository currently contains a simulator-ready SwiftUI prototype plus the `v0.2.1` Stage 3 Metal preview loop, Stage 4 LUT rendering path, Stage 5 exposure-assist slice, Stage 6 Metal compute scope path, the `v0.2.2` N-Log LUT input / exposure-analysis-source correction, and the `v0.2.3` scope readability update. It does **not** connect to a real Nikon camera, does **not** implement USB/PTP transport, and does **not** port `libgphoto2`.

The app is intentionally built around replaceable boundaries:

- `FrameSource` provides real `CVPixelBuffer` media frames and can later be replaced by a real live-view source.
- `SimulatedFrameSource` now generates BGRA pixel buffers instead of only emitting animation phase state.
- `VideoFileFrameSource` uses `AVAssetReader` to read local videos and emits the same `VideoFrame` type.
- `MetalTextureBridge` uses `CVMetalTextureCache` to bridge BGRA `CVPixelBuffer` frames into `MTLTexture`.
- `MetalPreviewRenderer` renders the latest media frame into an `MTKView` drawable through `MTKViewDelegate`.
- `MetalPreviewSurface` wraps `MTKView` with `UIViewRepresentable` and reconnects the Metal surface to the SwiftUI monitor screen.
- `LUTStore` and `LUTRepository` load imported LUTs and optional local `.cube` resources without requiring redistributable vendor LUTs in the repository.
- `LUTPass` uploads parsed `.cube` data into a 3D Metal texture and caches texture resources per LUT descriptor.
- `ColorTransformPass`, `FalseColorPass`, `ZebraPass`, and `ExposureAnalysisSource` provide the Swift-side state mapping for shader uniforms.
- `MetalFrameProcessor` and `ScopeComputePass` keep raw input, preview display, and exposure-analysis signals explicit, then read back compact `ScopeData` bins for the SwiftUI scope panel.
- `CameraTransport` owns camera communication and can later be replaced by ImageCaptureCore, PTP, or a network bridge.
- `CameraCommandService` validates camera writes before they reach the transport layer.
- LUT parsing and repository logic are separate from the monitor UI.
- SwiftUI owns layout and state presentation; the live preview image is now drawn by Metal while toolbars, sheets, and bottom controls remain SwiftUI-owned.
- `PrismBladeTests` owns repeatable fixtures and CPU references so later Metal passes can be compared against deterministic expected values.

## Current Features

- Landscape-first monitoring screen.
- Synthetic simulated frame source that generates real BGRA `CVPixelBuffer` frames with moving color blocks and a luminance ramp.
- Media frame model where `VideoFrame` carries `sequence`, `CMTime` timestamp, `FrameFormat`, `CVPixelBuffer`, and camera metadata.
- Video-file frame source using `AVAssetReader` to read local `.mov` / video assets and output `CVPixelBuffer` frames.
- Initial color-encoding detection through explicit hints, `REC709` / `NLOG` / `HLG` filename conventions, and video metadata markers.
- Metal texture bridging from BGRA `CVPixelBuffer` to `.bgra8Unorm` `MTLTexture`.
- Metal main preview rendering with `MTLDevice`, `MTLCommandQueue`, a minimal render pipeline, and `PreviewShaders.metal`.
- Raw-signal-first preview shader for Rec.709, N-Log, and HLG inputs. N-Log is no longer automatically decoded into a display working space before LUT sampling.
- Rec.709 input displays directly by default; N-Log input exposes a monitor-side LUT Preview button that applies the selected `.cube` LUT only when enabled.
- Display-only 3D LUT application in the Metal preview shader, with raw input / LUT output mixed by LUT intensity. Nikon N-Log -> Rec.709 LUTs are sampled with the original N-Log code values.
- Explicit exposure analysis source: `Raw Signal` or `Preview Display`, defaulting to `Raw Signal`.
- Shader-based false color using the selected analysis signal.
- Shader-based high zebra and range zebra masks using the selected analysis signal and the settings threshold.
- Metal compute Luma waveform and RGB Parade scope bins, displayed by `ScopePanel` instead of generated placeholder curves; scope analysis follows the selected raw or preview analysis source and excludes false-color / zebra overlays.
- `v0.2.3` scope readability updates: default scope bins are `192 x 96`, sample limits are `640 x 360`, and bin readback uses `log1p` density normalization so low-density waveform detail remains visible.
- White Luma waveform drawing with low-contrast white grid lines; RGB Parade remains red / green / blue.
- Scope title includes both mode and analysis source, for example `Waveform · Raw` or `RGB Parade · LUT`.
- Scope compute dispatch uses explicit threadgroup-grid sizing instead of `dispatchThreads`, improving compatibility across iOS Simulator and different Metal GPU families while preserving the same sampled pixels.
- `MetalFrameProcessor` centralizes LUT preview resolution, shader uniform generation, and the raw / preview / analysis state used by scope compute.
- `LUTPass` conversion from parsed `.cube` entries to `.rgba32Float` 3D `MTLTexture` resources.
- Identity fallback LUT resource so the renderer can keep drawing when no LUT is enabled or a selected LUT cannot be resolved.
- SwiftUI / Metal integration through an `MTKView` wrapped in `UIViewRepresentable`, replacing the SwiftUI gradient placeholder as the main preview.
- Minimal Metal viewport scaling for fit, fill, 1x, and 2x.
- Top status bar for connection state, input format, frame rate, N-Log raw/LUT state, exposure-analysis source, exposure tools, battery, and storage placeholders.
- Left and right floating tool rails.
- False color toggle wired to the Metal preview shader.
- Zebra toggle with threshold settings wired to the Metal preview shader.
- Compact Luma waveform overlay using about 42% of landscape width or 54% of portrait width.
- Compact RGB Parade overlay using the same dockable scope panel.
- Scope overlay drag-and-snap docking to Bottom Left, Bottom Right, Top Left, and Top Right, with the selected dock persisted through `UserDefaults`.
- Zoom mode cycling: fit, fill, 1x, 2x.
- Bottom camera control bar for monitoring-first operation.
- Click-to-adjust discrete sliders for exposure mode, aperture, shutter, ISO, white balance, and focus mode.
- Exposure mode display and mock switching for `M / A / S / P / Auto`.
- Exposure-mode-aware parameter locking:
  - `M`: aperture, shutter, and ISO enabled.
  - `A`: aperture enabled; shutter locked.
  - `S`: shutter enabled; aperture locked.
  - `P`: aperture and shutter locked.
  - `Auto`: aperture, shutter, ISO, and white balance locked.
- Global short feedback banner when a locked parameter is tapped, a camera action completes, or a command fails.
- Tap the empty preview area to close the current camera parameter adjustment panel.
- Scope overlay avoidance when the camera parameter adjustment panel is open.
- LUT manager with optional local built-in `.cube` discovery and `.cube` file import.
- `.cube` parser with validation for `TITLE`, `LUT_3D_SIZE`, `DOMAIN_MIN`, `DOMAIN_MAX`, comments, and RGB data rows.
- Optional local LUT directory support through `PrismBlade/Resources/LUTs`; ignored vendor LUT files are shown only when present and parseable.
- LUT metadata persistence through a JSON index in the app documents directory.
- Settings screen with portrait-monitoring permission, false-color / zebra default-on preferences, zebra threshold, scope opacity, scope mode, scope dock position, exposure analysis source, and mock debug actions.
- Mock Nikon Z6III camera controls:
  - Exposure mode
  - Aperture
  - Shutter
  - ISO
  - White balance
  - Focus mode
  - Record toggle
  - Capture action
  - Focus action
- XCTest target for `v0.2.1` Stages 1-6, `v0.2.2` exposure-chain regression coverage, and `v0.2.3` scope readability coverage:
  - Pixel buffer fixture generation for small BGRA test images.
  - `.cube` fixture generation for valid and invalid LUT cases.
  - CPU reference helpers for luma, LUT sampling, zebra masks, and waveform bins.
  - Unit tests for `LUTParser`, `CameraExposureRules`, `CameraCommandService`, and `MockCameraTransport`.
  - `VideoFrame` media-frame model tests.
  - `SimulatedFrameSource` real pixel-buffer output tests.
  - `VideoFileFrameSource` tests using temporary generated `.mov` fixtures for reading, timestamps, and color encoding.
  - `MetalTextureBridge` test coverage for BGRA pixel-buffer to Metal texture bridging.
  - `LUTRepository` tests for optional local LUT discovery and imported LUT reload.
  - `LUTPass` tests for 3D texture upload order, domain preservation, and texture format.
  - `ColorTransformPass` reference tests for generated Rec.709 / N-Log / HLG inputs.
  - `MetalLUTShaderTests` offscreen-render coverage for LUT intensity blending, N-Log raw output when LUT is disabled, raw N-Log LUT sampling, raw/LUT-output mixing, generated gray-ramp false color, and raw/preview zebra and false-color analysis behavior.
  - `ScopeComputePassTests` coverage for waveform / RGB Parade bins, readback throttling, raw N-Log scope analysis, preview-display scope analysis, new default bin/sample configuration, and non-linear density normalization.

## What Is Not Implemented Yet

- Real Nikon Z6III connection.
- USB/PTP communication.
- ImageCaptureCore integration.
- `libgphoto2` integration.
- User-visible real video-file playback entry point.
- Color-space-aware automatic LUT suggestions.
- Real camera exposure-mode reading.
- Real Nikon capability table parsing.
- Deep color calibration against real Nikon gray-card, color-chart, skin-tone, and waveform reference materials.
- Histogram.
- Focus peaking.
- Real recording or photo capture.

## Requirements

- macOS with Xcode installed.
- Xcode version that supports iOS 17+ projects.
- iOS Simulator runtime.
- Metal Toolchain component. If `.metal` compilation reports a missing toolchain, run:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -downloadComponent MetalToolchain
```

The project has been verified with:

- Xcode `26.4.1`
- iPhone 17 Simulator, iOS `26.4.1`
- Swift `5`
- iOS deployment target `17.0`

## Project Structure

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
    ScopeComputePass.swift
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

## Architecture Overview

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
  -> ScopeComputePass
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
  -> XCTest coverage for frame sources, Metal bridge, LUT parsing/storage/rendering, and camera domain rules
```

`MonitorSession` is the main state container. It coordinates frame input, mock camera commands, settings persistence, LUT import state, exposure-mode availability, and UI-facing monitor state.

## Usage

### Open in Xcode

1. Open `PrismBlade.xcodeproj`.
2. Select the `PrismBlade` scheme.
3. Choose an iPhone Simulator.
4. Run the app.

The first screen is the monitor screen. There is no onboarding, login page, or marketing page.

### Build from Terminal

If your active developer directory is not Xcode, use `DEVELOPER_DIR` explicitly:

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

Expected result:

```text
** BUILD SUCCEEDED **
```

### Run Stage 3-6 and v0.2.3 Tests

Stage 3 moves the main preview from SwiftUI synthetic drawing to an `MTKView`. Stage 4 adds real LUT texture upload and fragment-shader LUT sampling. Stage 5 adds shader-based false color and zebra. Stage 6 adds Metal compute bins for Luma waveform and RGB Parade. The `v0.2.2` correction keeps N-Log LUT sampling on the raw input signal and lets exposure tools analyze either Raw Signal or Preview Display. The `v0.2.3` update improves scope readability with larger bins, `log1p` density normalization, a white Luma waveform, explicit analysis-source titles, and draggable dock positions. The effect you should verify is that the test target builds and the simulated frame source, video-file frame source, Metal texture bridge, LUT repository, LUT pass, Metal shader, exposure analysis, and scope compute tests pass.

#### Option A: Xcode

1. Open `PrismBlade.xcodeproj`.
2. Select the `PrismBlade` scheme.
3. Select an iPhone Simulator.
4. Press `Command-U`, or choose `Product > Test`.
5. Open the Test navigator and confirm the `PrismBladeTests` suites are green.

You should see these suites:

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

#### Option B: Terminal

If `xcode-select -p` points to `/Library/Developer/CommandLineTools`, use the full Xcode binary path or set `DEVELOPER_DIR`. First list available simulator destinations:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -showdestinations \
  -project PrismBlade.xcodeproj \
  -scheme PrismBlade \
  -derivedDataPath /private/tmp/PrismBladeDerivedData
```

Pick an iPhone Simulator id from the output, then build the test products:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  build-for-testing \
  -project PrismBlade.xcodeproj \
  -scheme PrismBlade \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/PrismBladeDerivedData
```

Expected result:

```text
** TEST BUILD SUCCEEDED **
```

Run the tests, replacing `<SIMULATOR_ID>` with the id from `-showdestinations`:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  test-without-building \
  -project PrismBlade.xcodeproj \
  -scheme PrismBlade \
  -destination 'id=<SIMULATOR_ID>' \
  -derivedDataPath /private/tmp/PrismBladeDerivedData
```

Expected result:

```text
** TEST EXECUTE SUCCEEDED **
```

The current suite contains 60 tests. A successful run prints each test case and ends with `TEST EXECUTE SUCCEEDED`.

### Local Real Materials

Real Nikon / HLG / N-Log video samples live in the repository-root `material/` directory. This directory is listed in `.gitignore`; it is for local development and manual validation only, and should not be committed.

Current filename convention:

- `material/REC709.MOV`
- `material/NLOG.MOV`
- `material/HLG.MOV`

For local manual testing, duplicate an Xcode scheme locally, for example `PrismBlade Local Video`, and pass a test video path through `Run > Arguments > Arguments Passed On Launch`:

```text
-PBLocalVideoPath
/Users/chronus/code/diy/monitor/material/NLOG.MOV
```

When `AppEnvironment` sees `-PBLocalVideoPath`, it temporarily injects `VideoFileFrameSource` so local real materials can be used to validate N-Log raw display, N-Log LUT preview, false color, zebra, and scopes before real camera communication exists. This is a local testing hook only; it should not become a user-visible video-source switch. Once the real camera `FrameSource` is implemented, remove this launch-argument hook or route the default path back to the camera source.

Automated tests do not depend on those real materials. Tests generate small temporary `.mov` fixtures to verify `AVAssetReader`, use simulated BGRA pixel buffers to verify Metal bridging, and use generated gray / clipping / float-texture inputs for false-color, zebra, raw N-Log LUT sampling, and scope compute checks.

Real gray-card, color-chart, skin-tone, overexposure, underexposure, dark-noise, and reference waveform / RGB Parade materials are still needed for deeper calibration. Keep those assets in `material/`; the directory is ignored and should remain local.

### Local LUT Materials

Optional local `.cube` LUTs can live in `PrismBlade/Resources/LUTs/`. The app scans that directory at launch and shows parseable `.cube` files as local built-in LUTs. This is intended for development-only vendor LUTs such as Nikon N-Log conversion LUTs that may not be redistributable.

The repository ignores local LUT payloads:

- `PrismBlade/Resources/LUTs/*.cube`
- `PrismBlade/Resources/LUTs/*.3dl`
- `PrismBlade/Resources/LUTs/*.mga`
- `PrismBlade/Resources/LUTs/*.zip`

Only `PrismBlade/Resources/LUTs/README.md` is meant to be committed unless a LUT asset is confirmed to be redistributable. Missing or invalid local LUT files are hidden silently and do not block app launch.

### Monitor Screen

Use the floating tool buttons to toggle monitor assists:

- Camera filter icon: false color.
- Diagonal line icon: zebra overlay.
- Waveform icon: cycles scope mode.
- Slider icon: opens LUT manager.
- Magnifier icon: cycles zoom mode.
- Gear icon: opens settings.

The scope panel is intentionally compact: waveform and RGB Parade use about 42% of landscape width or 54% of portrait width so they do not dominate the monitored image. The default dock is Bottom Left. You can drag the panel freely within safe bounds; when released, it snaps to the nearest allowed dock: Bottom Left, Bottom Right, Top Left, or Top Right. The selected dock is persisted and is also available in Settings. When the camera parameter adjustment panel is open, bottom dock positions move upward to avoid overlapping the bottom controls.

Starting in Stage 3, the main preview is drawn by `MTKView`: `VideoFrame.pixelBuffer` is bridged through `CVMetalTextureCache` into `MTLTexture`, then sampled by `PreviewShaders.metal` into the drawable. Stage 4 binds a 3D LUT texture and mixes LUT output by intensity in the fragment shader. Stage 5 sends exposure-assist state into the shader. Stage 6 adds a throttled compute side path that reads the same source texture and produces compact `ScopeData` bins. `v0.2.2` removes the old implicit “decode N-Log before LUT” path: Rec.709 displays directly, N-Log LUT Preview samples raw N-Log code values, and exposure tools explicitly analyze either Raw Signal or Preview Display. `v0.2.3` keeps that signal policy intact and only changes scope resolution, normalization, drawing, labeling, and docking.

```text
source texture
  -> rawInputColor
  -> previewColor:
       raw input, or raw input mixed with LUT output when LUT Preview is enabled
  -> analysisColor:
       Raw Signal or Preview Display
  -> false color, if enabled, based on analysisColor
  -> zebra, if enabled, based on analysisColor
  -> MTKView drawable
  -> side path: ScopeComputePass, if scope is enabled, analyzing analysisColor
  -> ScopeData readback
  -> ScopePanel
```

The scope overlay now draws `ScopeData` bins from Metal compute. If readback is delayed, SwiftUI keeps displaying the previous scope data while preview rendering continues. Luma waveform is drawn in white and titled with the selected analysis source, while RGB Parade keeps separate red, green, and blue channel regions.

`ScopeComputePass` dispatches whole threadgroups and lets the shader guard discard edge threads outside the sampled region. This avoids simulator-sensitive `dispatchThreads` behavior and remains compatible with devices that do not support non-uniform threadgroups. The default configuration is now `192 x 96` bins, `frameInterval = 3`, and `640 x 360` max sampling. CPU readback maps counts with `log1p(count) / log1p(maximum)` instead of linear max normalization.

### LUT Import

1. Tap the LUT tool button.
2. Tap `Import .cube`.
3. Pick a `.cube` file.
4. The parser validates the file and saves a copy into the app documents directory.
5. Select the imported LUT from the list.
6. Enable LUT and adjust intensity.

Current LUT imports are parsed, validated, cached through `LUTStore`, uploaded to Metal as 3D textures through `LUTPass`, and sampled by the preview fragment shader when LUT is enabled. The pass is display-only and does not alter the original `CVPixelBuffer`. In `v0.2.2`, selected LUTs are sampled from the raw input signal; this keeps Nikon N-Log -> Rec.709 technical LUTs from receiving already-decoded N-Log values.

### Mock Camera Controls

The bottom control bar talks to `MockCameraTransport` through `CameraCommandService`. This keeps the UI on the same command boundary that a real camera transport will use later.

Available mock controls:

- Exposure mode: `M`, `A`, `S`, `P`, `Auto`
- Aperture
- Shutter
- ISO
- White balance
- Focus mode
- Record
- Capture
- Focus

Tap a parameter value to open a compact adjustment panel. The adjustment panel uses discrete slider steps from the mock capability table, so the UI cannot generate unsupported arbitrary values.

Tap the empty preview area, tap the same parameter again, or use the close button to dismiss the adjustment panel. This state is owned by `MonitorScreen`, so preview gestures and scope layout use the same source of truth.

Exposure mode affects parameter availability:

```text
M:    aperture, shutter, ISO enabled
A:    aperture enabled; shutter locked
S:    shutter enabled; aperture locked
P:    aperture and shutter locked
Auto: aperture, shutter, ISO, and white balance locked
```

Locked parameters are dimmed. Tapping one shows a short reason in the global message banner instead of opening the slider. The same rule is enforced in `MonitorSession`, `CameraCommandService`, and `MockCameraTransport`.

The settings screen also includes mock debug actions for reconnecting and simulating a disconnect.

## Code Notes

Important implementation decisions are documented with inline comments in the Swift files. The comments focus on boundaries that will matter during review:

- Why the app starts directly in monitoring mode.
- Why frame input and camera commands are separated.
- Why `VideoFrame` uses `CVPixelBuffer` as the media boundary.
- Why the simulated frame source generates BGRA pixel buffers instead of keeping only animation phase.
- Why the video-file frame source uses `AVAssetReader` instead of leaking `AVPlayer` into the frame-source or UI layers.
- Why `CVPixelBuffer -> MTLTexture` bridging is centralized at the Metal renderer boundary instead of spread through UI or frame-source code.
- Why the main preview uses `MTKView` while SwiftUI continues to own toolbars, sheets, and bottom controls.
- Why UI submission state does not leak into the transport boundary.
- Why exposure mode lives in `CameraState`, not local UI state.
- Why parameter availability has both `isWritable` and exposure-mode rules.
- Why disabled parameters are checked in UI, command service, and mock transport.
- Why short user messages are shown outside the parameter adjustment panel.
- Why camera parameter selection is owned by `MonitorScreen`.
- Why the mock transport validates values.
- Why out-of-range LUT values are clamped in the prototype parser.
- Why LUT preview tint remains metadata while real LUT rendering uses parsed `.cube` entries.
- Why optional local vendor LUT files are discovered at runtime rather than hard-coded as always-visible built-ins.
- Why `LUTPass` uses a fallback identity resource when LUT rendering is disabled or unavailable.
- Why N-Log LUT preview samples raw input code values rather than an automatically decoded display-space value.
- Why exposure analysis can use Raw Signal or Preview Display, and why Raw Signal is the default.
- Why generated gray / clipping inputs are enough for automated shader checks but do not replace real Nikon calibration materials.
- Why the scope overlay uses a compact `v0.2.3` size instead of a half-screen scope.
- Why the scope overlay supports four persisted dock positions and dynamic bottom avoidance when the parameter adjustment panel is open.
- Why Luma waveform is drawn white and RGB Parade keeps separate RGB colors.
- Why scope bin counts use non-linear density normalization for readability.
- Why scope compute uses explicit `dispatchThreadgroups` sizing for simulator and GPU-family compatibility.

The code intentionally favors reviewable boundaries over early performance optimization. Many comments are inline because this project is still shaping the real camera and rendering contracts.

## Verification

The current code has been checked with:

```sh
plutil -lint PrismBlade.xcodeproj/project.pbxproj PrismBlade/Info.plist
```

And checked with:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild build ...
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild build-for-testing ...
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test ... -only-testing:PrismBladeTests/ScopeComputePassTests
```

The app build, simulator test build, and focused `ScopeComputePassTests` run succeeded on an available iPhone Simulator. Full XCTest execution requires a concrete simulator and working CoreSimulator / `testmanagerd` services. The normal `.metal` compilation path depends on the installed Metal Toolchain. In restricted shells, Xcode may not see the cryptex-mounted Metal Toolchain or may print CoreSimulator logging permission warnings; run from Terminal or Xcode directly if the sandbox cannot access the Metal Toolchain, CoreSimulator, or `testmanagerd`.

## Next Steps

Recommended next development steps:

1. Validate the `v0.2.2` N-Log / LUT exposure-chain correction with real material.
   - Compare `material/NLOG.MOV` with optional local Nikon / N-Log LUTs.
   - Confirm LUT Off shows flat N-Log rather than an app-generated Rec.709 conversion.
   - Confirm LUT On samples raw N-Log code values and keeps highlight detail from being clipped before LUT sampling.
   - Keep local vendor LUT assets out of the repository unless redistribution is confirmed.
   - Calibrate N-Log / HLG, false color, zebra, waveform, and RGB Parade behavior after real gray-card, color-chart, skin-tone, and reference scope materials arrive.

2. Preserve the current analysis policy.
   - Rec.709 input displays directly and does not auto-apply LUTs.
   - N-Log input uses the monitor-side N-Log LUT Preview button for the selected LUT.
   - Raw Signal remains the default exposure analysis source.
   - Preview Display remains available for checking LUT-output waveform / zebra / false-color behavior.

3. Deepen scope validation.
   - Manually validate the `v0.2.3` white waveform, `192 x 96` bins, and four-position drag snapping with `material/REC709.MOV`, `material/NLOG.MOV`, and `material/HLG.MOV`.
   - Add reduced-resolution or high-quality sampling options for heavier real footage.
   - Compare Luma waveform and RGB Parade against reference screenshots.
   - Tune bin dimensions, opacity curves, and analysis interval on iPhone 12 Pro hardware.
   - Add frame skipping to protect simulator and iPhone 12 Pro performance.

4. Continue expanding tests with each rendering slice.
   - Add broader offscreen Metal tests around real LUT fixtures and edge cases.
   - Compare Metal output against `CPUReference`.
   - Add video frame source and scope compute tests.

5. Prepare real camera research adapters.
   - Keep `CameraTransport` stable.
   - Add empty adapter namespaces for ImageCaptureCore, PTP, and network bridge work.
   - Do not expose Nikon, USB, PTP, or `libgphoto2` types to SwiftUI.

6. Perform hardware research later.
   - Validate Nikon Z6III USB modes with iPhone 12 Pro.
   - Compare ImageCaptureCore capability coverage.
   - Decide whether USB/PTP, Nikon iPhone mode, Wi-Fi, USB-LAN, or a bridge service is the right production path.

## Reference Documents

- [Prototype Design](PROTOTYPE_DESIGN.md)
- [Technical Spec v0.2.3](TECHNICAL_SPEC_v0.2.3.md)
- [Technical Spec v0.2.2](TECHNICAL_SPEC_v0.2.2.md)
- [Technical Spec v0.2.1](TECHNICAL_SPEC_v0.2.1.md)
- [Test Plan v0.2.1](TEST_PLAN_v0.2.1.md)
- [Technical Spec v0.1.3](TECHNICAL_SPEC_v0.1.3.md)
- [Technical Spec v0.1.2](TECHNICAL_SPEC_v0.1.2.md)
- [Technical Spec v0.1.1](TECHNICAL_SPEC_v0.1.1.md)
