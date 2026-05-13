# PrismBlade

**PrismBlade** is an iOS camera monitoring prototype for a Nikon Z6III workflow. The current version, `v0.1.3`, focuses on the simulator monitoring experience, image-assist tools, LUT import flow, bottom camera controls, exposure-mode-aware parameter rules, a mock camera transport boundary, and the monitor interaction fixes from the v0.1.3 technical spec.

> Chinese version: [README.zh-CN.md](README.zh-CN.md)

## Status

This repository currently contains a simulator-ready SwiftUI prototype. It does **not** connect to a real Nikon camera, does **not** implement USB/PTP transport, and does **not** port `libgphoto2`.

The app is intentionally built around replaceable boundaries:

- `FrameSource` provides video frames and can later be replaced by a real live-view source.
- `CameraTransport` owns camera communication and can later be replaced by ImageCaptureCore, PTP, or a network bridge.
- `CameraCommandService` validates camera writes before they reach the transport layer.
- LUT parsing and repository logic are separate from the monitor UI.
- SwiftUI owns layout and state presentation; the current rendered image is still a synthetic preview, not the final Metal/Core Image pipeline.

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
- Histogram.
- Focus peaking.
- Real recording or photo capture.

## Requirements

- macOS with Xcode installed.
- Xcode version that supports iOS 17+ projects.
- iOS Simulator runtime.

The project has been verified with:

- Xcode `26.4.1`
- iOS Simulator generic build destination
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

And built with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ...
```

The simulator build succeeded. In the current sandbox, Xcode may print CoreSimulator logging permission warnings, but those warnings did not prevent compilation, linking, or app bundle generation.

## Next Steps

Recommended next development steps:

1. Add a real rendering pipeline.
   - Introduce a `FrameProcessor`.
   - Move the synthetic image logic behind a renderer-facing abstraction.
   - Add Core Image or Metal-backed preview rendering.

2. Apply LUTs to pixels.
   - Convert parsed `.cube` data into a 3D texture or Core Image color cube.
   - Apply LUT intensity by blending original and LUT-processed output.
   - Keep the LUT operation display-only, not destructive.

3. Replace placeholder exposure overlays.
   - Implement false color from luma values.
   - Implement zebra from threshold/range masks.
   - Keep these as display overlays or passes.

4. Implement real scope analysis.
   - Sample frames at a reduced resolution.
   - Generate Luma waveform from pixel values.
   - Generate RGB Parade from channel values.
   - Add frame skipping to protect simulator and iPhone 12 Pro performance.

5. Add `VideoFileFrameSource`.
   - Use AVFoundation to read bundled or user-selected video.
   - Keep `SimulatedFrameSource` as the default fallback.

6. Add tests.
   - Unit tests for `.cube` parsing.
   - Unit tests for mock transport value validation.
   - Unit tests for exposure-mode parameter locking.
   - Unit tests for monitor state toggles.
   - UI smoke tests for monitor screen, settings, LUT import error state, and bottom camera control bar.

7. Prepare real camera research adapters.
   - Keep `CameraTransport` stable.
   - Add empty adapter namespaces for ImageCaptureCore, PTP, and network bridge work.
   - Do not expose Nikon, USB, PTP, or `libgphoto2` types to SwiftUI.

8. Perform hardware research later.
   - Validate Nikon Z6III USB modes with iPhone 12 Pro.
   - Compare ImageCaptureCore capability coverage.
   - Decide whether USB/PTP, Nikon iPhone mode, Wi-Fi, USB-LAN, or a bridge service is the right production path.

## Reference Documents

- [Prototype Design](PROTOTYPE_DESIGN.md)
- [Technical Spec v0.1.3](TECHNICAL_SPEC_v0.1.3.md)
- [Technical Spec v0.1.2](TECHNICAL_SPEC_v0.1.2.md)
- [Technical Spec v0.1.1](TECHNICAL_SPEC_v0.1.1.md)
