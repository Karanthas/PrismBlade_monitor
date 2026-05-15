import simd

enum ColorTransformPass {
    static func encodingCode(for encoding: SourceColorEncoding) -> Float {
        switch encoding {
        case .rec709:
            return 0
        case .nLog:
            return 1
        case .hlg:
            return 2
        }
    }

    static func transform(_ color: SIMD3<Float>, encoding: SourceColorEncoding) -> SIMD3<Float> {
        switch encoding {
        case .rec709:
            return clamp(color)
        case .nLog:
            return SIMD3<Float>(
                decodeNLog(color.x),
                decodeNLog(color.y),
                decodeNLog(color.z)
            )
        case .hlg:
            return SIMD3<Float>(
                decodeHLG(color.x),
                decodeHLG(color.y),
                decodeHLG(color.z)
            )
        }
    }

    static func decodeNLog(_ value: Float) -> Float {
        let x = min(max(value, 0), 1)
        let cut: Float = 452.0 / 1023.0
        let a: Float = 650.0 / 1023.0
        let b: Float = 0.0075
        let c: Float = 150.0 / 1023.0
        let d: Float = 619.0 / 1023.0

        if x < cut {
            return min(max(pow(max(x / a, 0), 3) - b, 0), 1)
        }

        return min(max(exp((x - d) / c), 0), 1)
    }

    static func decodeHLG(_ value: Float) -> Float {
        let x = min(max(value, 0), 1)
        let a: Float = 0.17883277
        let b: Float = 0.28466892
        let c: Float = 0.55991073

        if x <= 0.5 {
            return min(max((x * x) / 3, 0), 1)
        }

        return min(max((exp((x - c) / a) + b) / 12, 0), 1)
    }

    private static func clamp(_ color: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            min(max(color.x, 0), 1),
            min(max(color.y, 0), 1),
            min(max(color.z, 0), 1)
        )
    }
}
