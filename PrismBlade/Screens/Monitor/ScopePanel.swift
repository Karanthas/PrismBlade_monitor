import SwiftUI

struct ScopePanel: View {
    var mode: ScopeMode
    var opacity: Double
    var frame: VideoFrame

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(mode.title)
                    .font(.caption.weight(.bold))
                Spacer()
                Text("显示链路采样")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.68))
            }

            Canvas { context, size in
                drawGrid(context: context, size: size)

                switch mode {
                case .off:
                    break
                case .lumaWaveform:
                    drawWaveform(context: context, size: size)
                case .rgbParade:
                    drawRGBParade(context: context, size: size)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(opacity))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        var grid = Path()

        for ratio in stride(from: 0.0, through: 1.0, by: 0.25) {
            let y = size.height * ratio
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }

        for ratio in stride(from: 0.0, through: 1.0, by: 0.1) {
            let x = size.width * ratio
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
        }

        context.stroke(grid, with: .color(.white.opacity(0.18)), lineWidth: 1)
    }

    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        var path = Path()
        let phase = frame.phase * Double.pi * 2

        for x in stride(from: 0.0, through: size.width, by: 2) {
            let normalizedX = Double(x / max(size.width, 1))
            let luma = 0.5 + 0.42 * sin((normalizedX * 8 * Double.pi) + phase)
            let y = size.height * (1 - luma)

            if x == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        context.stroke(path, with: .color(.green.opacity(0.95)), lineWidth: 2)
    }

    private func drawRGBParade(context: GraphicsContext, size: CGSize) {
        let channelWidth = size.width / 3
        let colors: [Color] = [.red, .green, .blue]

        for channel in 0..<3 {
            var path = Path()
            let startX = CGFloat(channel) * channelWidth
            let phaseOffset = frame.phase * Double.pi * 2 + Double(channel)

            for localX in stride(from: 0.0, through: channelWidth, by: 2) {
                let normalizedX = Double(localX / max(channelWidth, 1))
                let value = 0.5 + 0.4 * sin((normalizedX * 6 * Double.pi) + phaseOffset)
                let y = size.height * (1 - value)
                let point = CGPoint(x: startX + localX, y: y)

                if localX == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }

            context.stroke(path, with: .color(colors[channel].opacity(0.92)), lineWidth: 2)
        }
    }
}
