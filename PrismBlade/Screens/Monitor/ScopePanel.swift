import SwiftUI

struct ScopePanel: View {
    var mode: ScopeMode
    var opacity: Double
    var data: ScopeData?

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
                    drawWaveform(context: context, size: size, data: data)
                case .rgbParade:
                    drawRGBParade(context: context, size: size, data: data)
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

    private func drawWaveform(context: GraphicsContext, size: CGSize, data: ScopeData?) {
        guard let data, data.isValid else { return }
        drawBins(
            data.lumaBins,
            binWidth: data.binWidth,
            binHeight: data.binHeight,
            rect: CGRect(origin: .zero, size: size),
            color: .green,
            context: context
        )
    }

    private func drawRGBParade(context: GraphicsContext, size: CGSize, data: ScopeData?) {
        guard let data, data.isValid else { return }
        let channelWidth = size.width / 3
        let channels: [(bins: [Float], color: Color)] = [
            (data.redBins, .red),
            (data.greenBins, .green),
            (data.blueBins, .blue)
        ]

        for channel in 0..<channels.count {
            drawBins(
                channels[channel].bins,
                binWidth: data.binWidth,
                binHeight: data.binHeight,
                rect: CGRect(
                    x: CGFloat(channel) * channelWidth,
                    y: 0,
                    width: channelWidth,
                    height: size.height
                ),
                color: channels[channel].color,
                context: context
            )
        }
    }

    private func drawBins(
        _ bins: [Float],
        binWidth: Int,
        binHeight: Int,
        rect: CGRect,
        color: Color,
        context: GraphicsContext
    ) {
        guard binWidth > 0, binHeight > 0, bins.count == binWidth * binHeight else {
            return
        }

        let cellWidth = rect.width / CGFloat(binWidth)
        let cellHeight = rect.height / CGFloat(binHeight)

        for column in 0..<binWidth {
            for row in 0..<binHeight {
                let intensity = min(max(Double(bins[column * binHeight + row]), 0), 1)
                guard intensity > 0 else { continue }

                let x = rect.minX + CGFloat(column) * cellWidth
                let y = rect.maxY - CGFloat(row + 1) * cellHeight
                let opacity = 0.18 + intensity * 0.78
                context.fill(
                    Path(CGRect(
                        x: x,
                        y: y,
                        width: max(cellWidth, 1),
                        height: max(cellHeight, 1)
                    )),
                    with: .color(color.opacity(opacity))
                )
            }
        }
    }
}
