import MetalKit
import SwiftUI

struct MetalPreviewSurface: UIViewRepresentable {
    var frame: VideoFrame
    var monitor: MonitorState

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: nil)
        view.backgroundColor = .black
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 30
        view.contentMode = .scaleAspectFit

        guard let device = MTLCreateSystemDefaultDevice() else {
            view.isPaused = true
            return view
        }

        view.device = device

        do {
            let renderer = try MetalPreviewRenderer(device: device, colorPixelFormat: view.colorPixelFormat)
            renderer.update(frame: frame, monitor: monitor)
            context.coordinator.renderer = renderer
            view.delegate = renderer
        } catch {
            view.isPaused = true
            assertionFailure(error.localizedDescription)
        }

        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.update(frame: frame, monitor: monitor)
    }

    final class Coordinator {
        var renderer: MetalPreviewRenderer?
    }
}
