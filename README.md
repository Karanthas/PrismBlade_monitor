# PrismBlade

**PrismBlade** is an iOS camera monitoring prototype for a Nikon Z6III workflow. The current branch is moving through the `v0.2.1` Metal-first plan. Stage 1 is complete: the project now has an XCTest target, generated image/LUT fixtures, CPU reference helpers, and automated protection for the existing LUT parser and mock camera domain rules.

> Chinese version: [README.zh-CN.md](README.zh-CN.md)

## Status

This repository currently contains a simulator-ready SwiftUI prototype plus the first `v0.2.1` testing foundation. It does **not** connect to a real Nikon camera, does **not** implement USB/PTP transport, and does **not** port `libgphoto2`.

The app is intentionally built around replaceable boundaries:

- `FrameSource` provides video frames and can later be replaced by a real live-view source.
- `CameraTransport` owns camera communication and can later be replaced by ImageCaptureCore, PTP, or a network bridge.
- `CameraCommandService` validates camera writes before they reach the transport layer.
- LUT parsing and repository logic are separate from the monitor UI.
- SwiftUI owns layout and state presentation; the current rendered image is still a synthetic preview, not the final Metal pipeline.
- `PrismBladeTests` owns repeatable fixtures and CPU references so later Metal passes can be compared against deterministic expected values.

## Current Features

- Landscape-first monitoring screen.
- Synthetic simulated frame source with moving color blocks and a luminance ramp.
- Top status bar for connection state, input format, frame rate, LUT state, exposure tools, battery, and storage placeholders.
- Left and right floating tool rails.
- False color toggle.
- Zebra toggle with threshold settings.
- Compact Luma waveform overlay at 40% of the monitor width.
- Compact RGB Parade overlay at 40% of the monitor width.
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
- LUT manager with built-in descriptors and `.cube` file import.
- `.cube` parser with validation for `TITLE`, `LUT_3D_SIZE`, `DOMAIN_MIN`, `DOMAIN_MAX`, comments, and RGB data rows.
- LUT metadata persistence through a JSON index in the app documents directory.
- Settings screen with portrait-monitoring permission, zebra threshold, scope opacity, scope mode, and mock debug actions.
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
- XCTest target for `v0.2.1` Stage 1:
  - Pixel buffer fixture generation for small BGRA test images.
  - `.cube` fixture generation for valid and invalid LUT cases.
  - CPU reference helpers for luma, LUT sampling, zebra masks, and waveform bins.
  - Unit tests for `LUTParser`, `CameraExposureRules`, `CameraCommandService`, and `MockCameraTransport`.

## What Is Not Implemented Yet

- Real Nikon Z6III connection.
- USB/PTP communication.
- ImageCaptureCore integration.
- `libgphoto2` integration.
- Real video-file playback.
- Metal preview renderer.
- Core Image / Metal 3D LUT sampling.
- Real per-pixel false color and zebra processing.
- Scope analysis from actual pixel buffers.
- Real camera exposure-mode reading.
- Real Nikon capability table parsing.
- Metal offscreen render tests.
- Real pixel-driven scope compute tests.
- Histogram.
- Focus peaking.
- Real recording or photo capture.

## Requirements

- macOS with Xcode installed.
- Xcode version that supports iOS 17+ projects.
- iOS Simulator runtime.

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
  -> XCTest coverage for LUT and camera domain rules
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

### Run Stage 1 Tests

Stage 1 does not add a visible app feature. The effect you should verify is that the new test target builds and the automated tests pass.

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

The current Stage 1 suite contains 27 tests. A successful run prints each test case and ends with `TEST EXECUTE SUCCEEDED`.

### Monitor Screen

Use the floating tool buttons to toggle monitor assists:

- Camera filter icon: false color.
- Diagonal line icon: zebra overlay.
- Waveform icon: cycles scope mode.
- Slider icon: opens LUT manager.
- Magnifier icon: cycles zoom mode.
- Gear icon: opens settings.

The scope panel is intentionally compact in `v0.1.3`: waveform and RGB Parade use about 40% of the screen width so they do not dominate the monitored image. When the camera parameter adjustment panel is open, the scope panel moves upward to avoid overlapping the bottom controls.

### LUT Import

1. Tap the LUT tool button.
2. Tap `Import .cube`.
3. Pick a `.cube` file.
4. The parser validates the file and saves a copy into the app documents directory.
5. Select the imported LUT from the list.
6. Enable LUT and adjust intensity.

Current LUT behavior is intentionally lightweight: imported LUTs are parsed and validated, but the preview uses a descriptor tint as a visual placeholder. Full 3D LUT sampling should be implemented in the rendering pipeline next.

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
- Why UI submission state does not leak into the transport boundary.
- Why exposure mode lives in `CameraState`, not local UI state.
- Why parameter availability has both `isWritable` and exposure-mode rules.
- Why disabled parameters are checked in UI, command service, and mock transport.
- Why short user messages are shown outside the parameter adjustment panel.
- Why camera parameter selection is owned by `MonitorScreen`.
- Why the mock transport validates values.
- Why out-of-range LUT values are clamped in the prototype parser.
- Why LUT preview tint is only a temporary UI placeholder.
- Why the scope overlay is constrained to 40% width.
- Why the scope overlay uses dynamic bottom avoidance when the parameter adjustment panel is open.

The code intentionally favors reviewable boundaries over early performance optimization. Many comments are inline because this project is still shaping the real camera and rendering contracts.

## Verification

The current code has been checked with:

```sh
plutil -lint PrismBlade.xcodeproj/project.pbxproj PrismBlade/Info.plist
```

And built and tested with:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild build-for-testing ...
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test-without-building ...
```

The simulator test build and test execution succeeded on an iPhone 17 Simulator. In restricted shells, Xcode may print CoreSimulator logging permission warnings; run from Terminal or Xcode directly if the sandbox cannot talk to CoreSimulator or `testmanagerd`.

## Next Steps

Recommended next development steps:

1. Add the media frame model and frame source updates from `v0.2.1` Stage 2.
   - Move `VideoFrame` toward real `CVPixelBuffer` payloads.
   - Keep `phase` only as transitional simulator state if needed during the migration.
   - Preserve the generated pixel-buffer fixtures as the test input source.

2. Add a real Metal preview loop from `v0.2.1` Stage 3.
   - Introduce a `FrameProcessor`.
   - Move the synthetic image logic behind a renderer-facing abstraction.
   - Add `MTKView`-backed preview rendering.

3. Apply LUTs to pixels.
   - Convert parsed `.cube` data into a 3D texture or Core Image color cube.
   - Apply LUT intensity by blending original and LUT-processed output.
   - Keep the LUT operation display-only, not destructive.

4. Replace placeholder exposure overlays.
   - Implement false color from luma values.
   - Implement zebra from threshold/range masks.
   - Keep these as display overlays or passes.

5. Implement real scope analysis.
   - Sample frames at a reduced resolution.
   - Generate Luma waveform from pixel values.
   - Generate RGB Parade from channel values.
   - Add frame skipping to protect simulator and iPhone 12 Pro performance.

6. Add `VideoFileFrameSource`.
   - Use AVFoundation to read bundled or user-selected video.
   - Keep `SimulatedFrameSource` as the default fallback.

7. Continue expanding tests with each rendering slice.
   - Add offscreen Metal tests.
   - Compare Metal output against `CPUReference`.
   - Add video frame source and scope compute tests.

8. Prepare real camera research adapters.
   - Keep `CameraTransport` stable.
   - Add empty adapter namespaces for ImageCaptureCore, PTP, and network bridge work.
   - Do not expose Nikon, USB, PTP, or `libgphoto2` types to SwiftUI.

9. Perform hardware research later.
   - Validate Nikon Z6III USB modes with iPhone 12 Pro.
   - Compare ImageCaptureCore capability coverage.
   - Decide whether USB/PTP, Nikon iPhone mode, Wi-Fi, USB-LAN, or a bridge service is the right production path.

## Reference Documents

- [Prototype Design](PROTOTYPE_DESIGN.md)
- [Technical Spec v0.2.1](TECHNICAL_SPEC_v0.2.1.md)
- [Test Plan v0.2.1](TEST_PLAN_v0.2.1.md)
- [Technical Spec v0.1.3](TECHNICAL_SPEC_v0.1.3.md)
- [Technical Spec v0.1.2](TECHNICAL_SPEC_v0.1.2.md)
- [Technical Spec v0.1.1](TECHNICAL_SPEC_v0.1.1.md)
