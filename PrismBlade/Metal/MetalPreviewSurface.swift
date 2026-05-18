import Foundation
import MetalKit
import SwiftUI

struct MetalPreviewSurface: UIViewRepresentable {
    var frame: VideoFrame
    var monitor: MonitorState
    var lut: LUTState
    var lutStore: LUTStore
    var onScopeData: (ScopeData) -> Void

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
            let renderer = try MetalPreviewRenderer(
                device: device,
                colorPixelFormat: view.colorPixelFormat,
                lutStore: lutStore
            )
            renderer.update(frame: frame, monitor: monitor, lut: lut)
            renderer.scopeDataHandler = makeScopeDataHandler()
            context.coordinator.renderer = renderer
            view.delegate = renderer
        } catch {
            view.isPaused = true
            assertionFailure(error.localizedDescription)
        }

        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.scopeDataHandler = makeScopeDataHandler()
        context.coordinator.renderer?.update(frame: frame, monitor: monitor, lut: lut)
    }

    private func makeScopeDataHandler() -> (ScopeData) -> Void {
        { scopeData in
            DispatchQueue.main.async {
                onScopeData(scopeData)
            }
        }
    }

    final class Coordinator {
        var renderer: MetalPreviewRenderer?
    }
}
