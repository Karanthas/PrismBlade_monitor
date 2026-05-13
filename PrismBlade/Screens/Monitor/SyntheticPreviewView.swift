import SwiftUI

struct SyntheticPreviewView: View {
    var frame: VideoFrame
    var monitor: MonitorState
    var lut: LUTState
    var isPortraitLayout: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                baseRamp
                movingColorBlocks(phase: frame.phase)

                if lut.isEnabled, let descriptor = lut.selectedLUT {
                    descriptor.tintColor
                        .opacity(0.28 * lut.intensity)
                        .blendMode(.softLight)
                }

                if monitor.falseColorEnabled {
                    falseColorOverlay
                        .blendMode(.screen)
                }

                if monitor.zebraEnabled {
                    zebraOverlay(threshold: monitor.zebraThreshold)
                }

                aspectGuides
            }
            .scaleEffect(scale(for: monitor.zoomMode))
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var baseRamp: some View {
        LinearGradient(
            colors: [.black, .blue.opacity(0.7), .gray, .orange.opacity(0.85), .white],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func movingColorBlocks(phase: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let blockSize = max(min(width, height) * 0.18, 86)
            let offset = CGFloat(phase) * (width + blockSize) - blockSize

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.red.opacity(0.72))
                    .frame(width: blockSize, height: blockSize)
                    .offset(x: offset, y: height * 0.22)

                RoundedRectangle(cornerRadius: 6)
                    .fill(.green.opacity(0.7))
                    .frame(width: blockSize * 0.72, height: blockSize * 0.72)
                    .offset(x: width - offset - blockSize, y: height * 0.48)

                let verticalWave = CGFloat(0.24 + 0.18 * sin(phase * Double.pi * 2))

                RoundedRectangle(cornerRadius: 6)
                    .fill(.cyan.opacity(0.66))
                    .frame(width: blockSize * 1.2, height: blockSize * 0.45)
                    .offset(x: width * 0.42, y: height * verticalWave)
            }
        }
    }

    private var falseColorOverlay: some View {
        HStack(spacing: 0) {
            Color.purple.opacity(0.84)
            Color.blue.opacity(0.76)
            Color.gray.opacity(0.34)
            Color.green.opacity(0.54)
            Color.yellow.opacity(0.58)
            Color.orange.opacity(0.7)
            Color.red.opacity(0.82)
        }
        .overlay(alignment: .bottom) {
            // 下方窄条作为 IRE 区间提示，避免伪色开启时用户完全失去亮度参照。
            HStack(spacing: 0) {
                ForEach([0, 18, 40, 60, 90, 100], id: \.self) { value in
                    Text("\(value)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    private func zebraOverlay(threshold: Double) -> some View {
        GeometryReader { proxy in
            let startRatio = min(max(threshold / 100, 0.5), 1)
            let maskWidth = proxy.size.width * CGFloat(1 - startRatio)

            ZebraPattern()
                .stroke(.white.opacity(0.76), lineWidth: 2)
                .background(.black.opacity(0.12))
                .mask(alignment: .trailing) {
                    Rectangle()
                        .frame(width: max(maskWidth, 12))
                }
        }
    }

    private var aspectGuides: some View {
        Rectangle()
            .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            .padding(isPortraitLayout ? 34 : 48)
    }

    private func scale(for mode: ZoomMode) -> CGFloat {
        switch mode {
        case .fit: return 1
        case .fill: return 1.08
        case .oneX: return 1
        case .twoX: return 2
        }
    }
}

struct ZebraPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 13

        for start in stride(from: -rect.height, through: rect.width, by: spacing) {
            path.move(to: CGPoint(x: start, y: rect.maxY))
            path.addLine(to: CGPoint(x: start + rect.height, y: rect.minY))
        }

        return path
    }
}
