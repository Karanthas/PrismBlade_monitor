import Foundation

struct RGBDouble: Equatable {
    var red: Double
    var green: Double
    var blue: Double
}

enum CPUReference {
    static func clamp(_ value: RGBDouble) -> RGBDouble {
        RGBDouble(
            red: clamp01(value.red),
            green: clamp01(value.green),
            blue: clamp01(value.blue)
        )
    }

    static func mix(_ first: RGBDouble, _ second: RGBDouble, amount: Double) -> RGBDouble {
        let t = clamp01(amount)
        return RGBDouble(
            red: first.red + (second.red - first.red) * t,
            green: first.green + (second.green - first.green) * t,
            blue: first.blue + (second.blue - first.blue) * t
        )
    }

    static func rec709Luma(_ value: RGBDouble) -> Double {
        value.red * 0.2126 + value.green * 0.7152 + value.blue * 0.0722
    }

    static func zebraMask(
        pixels: [RGBDouble],
        threshold: Double
    ) -> [Bool] {
        pixels.map { rec709Luma($0) >= threshold }
    }

    static func waveformBins(
        pixels: [RGBDouble],
        width: Int,
        height: Int,
        binCount: Int
    ) -> [Int] {
        guard width > 0, height > 0, binCount > 0 else { return [] }
        var bins = Array(repeating: 0, count: width * binCount)

        for y in 0..<height {
            for x in 0..<width {
                let pixel = pixels[y * width + x]
                let luma = clamp01(rec709Luma(pixel))
                let bin = min(Int((luma * Double(binCount - 1)).rounded()), binCount - 1)
                bins[x * binCount + bin] += 1
            }
        }

        return bins
    }

    static func sampleNearest3DLUT(
        input: RGBDouble,
        entries: [RGBDouble],
        size: Int
    ) -> RGBDouble {
        guard size > 1, entries.count == size * size * size else {
            return input
        }

        let clamped = clamp(input)
        let redIndex = nearestIndex(for: clamped.red, size: size)
        let greenIndex = nearestIndex(for: clamped.green, size: size)
        let blueIndex = nearestIndex(for: clamped.blue, size: size)
        return entries[index(red: redIndex, green: greenIndex, blue: blueIndex, size: size)]
    }

    static func sampleTrilinear3DLUT(
        input: RGBDouble,
        entries: [RGBDouble],
        size: Int
    ) -> RGBDouble {
        guard size > 1, entries.count == size * size * size else {
            return input
        }

        let clamped = clamp(input)
        let red = axisPosition(clamped.red, size: size)
        let green = axisPosition(clamped.green, size: size)
        let blue = axisPosition(clamped.blue, size: size)

        let c000 = entries[index(red: red.low, green: green.low, blue: blue.low, size: size)]
        let c100 = entries[index(red: red.high, green: green.low, blue: blue.low, size: size)]
        let c010 = entries[index(red: red.low, green: green.high, blue: blue.low, size: size)]
        let c110 = entries[index(red: red.high, green: green.high, blue: blue.low, size: size)]
        let c001 = entries[index(red: red.low, green: green.low, blue: blue.high, size: size)]
        let c101 = entries[index(red: red.high, green: green.low, blue: blue.high, size: size)]
        let c011 = entries[index(red: red.low, green: green.high, blue: blue.high, size: size)]
        let c111 = entries[index(red: red.high, green: green.high, blue: blue.high, size: size)]

        let c00 = mix(c000, c100, amount: red.fraction)
        let c10 = mix(c010, c110, amount: red.fraction)
        let c01 = mix(c001, c101, amount: red.fraction)
        let c11 = mix(c011, c111, amount: red.fraction)
        let c0 = mix(c00, c10, amount: green.fraction)
        let c1 = mix(c01, c11, amount: green.fraction)
        return mix(c0, c1, amount: blue.fraction)
    }

    private static func index(red: Int, green: Int, blue: Int, size: Int) -> Int {
        blue * size * size + green * size + red
    }

    private static func nearestIndex(for value: Double, size: Int) -> Int {
        min(max(Int((clamp01(value) * Double(size - 1)).rounded()), 0), size - 1)
    }

    private static func axisPosition(_ value: Double, size: Int) -> (low: Int, high: Int, fraction: Double) {
        let position = clamp01(value) * Double(size - 1)
        let low = Int(floor(position))
        let high = min(low + 1, size - 1)
        return (low, high, position - Double(low))
    }

    private static func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
