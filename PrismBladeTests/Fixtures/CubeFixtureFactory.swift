import Foundation

enum CubeFixtureFactory {
    static func identity(size: Int = 2, title: String = "Identity") -> String {
        cube(size: size, title: title) { red, green, blue in
            RGBDouble(red: red, green: green, blue: blue)
        }
    }

    static func warmOffset(size: Int = 2, title: String = "Warm Offset") -> String {
        cube(size: size, title: title) { red, green, blue in
            RGBDouble(
                red: min(red + 0.08, 1),
                green: min(green + 0.03, 1),
                blue: max(blue - 0.05, 0)
            )
        }
    }

    static func redChannelRamp(size: Int = 2, title: String = "Red Ramp") -> String {
        cube(size: size, title: title) { red, _, _ in
            RGBDouble(red: red, green: 0, blue: 0)
        }
    }

    static func invalidSize() -> String {
        """
        TITLE "Invalid Size"
        LUT_3D_SIZE 1
        0.000000 0.000000 0.000000
        """
    }

    static func dataCountMismatch(size: Int = 3, actualRows: Int = 2) -> String {
        let rows = Array(repeating: "0.000000 0.000000 0.000000", count: actualRows)
            .joined(separator: "\n")

        return """
        TITLE "Count Mismatch"
        LUT_3D_SIZE \(size)
        \(rows)
        """
    }

    static func invalidFloat() -> String {
        """
        TITLE "Invalid Float"
        LUT_3D_SIZE 2
        nope 0.000000 0.000000
        """
    }

    static func outOfRangeDomainAndData() -> String {
        """
        TITLE "Out Of Range"
        LUT_3D_SIZE 2
        DOMAIN_MIN -0.100000 0.000000 0.000000
        DOMAIN_MAX 1.100000 1.000000 1.000000
        -0.250000 0.000000 0.000000
        1.250000 0.000000 0.000000
        0.000000 1.500000 0.000000
        0.000000 0.000000 2.000000
        0.000000 0.000000 0.000000
        1.000000 1.000000 1.000000
        0.500000 0.500000 0.500000
        0.250000 0.250000 0.250000
        """
    }

    static func cube(
        size: Int,
        title: String,
        transform: (Double, Double, Double) -> RGBDouble
    ) -> String {
        var lines = [
            "TITLE \"\(title)\"",
            "LUT_3D_SIZE \(size)"
        ]

        for blueIndex in 0..<size {
            for greenIndex in 0..<size {
                for redIndex in 0..<size {
                    let denominator = Double(max(size - 1, 1))
                    let red = Double(redIndex) / denominator
                    let green = Double(greenIndex) / denominator
                    let blue = Double(blueIndex) / denominator
                    let transformed = transform(red, green, blue)
                    lines.append(format(transformed))
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func format(_ value: RGBDouble) -> String {
        String(format: "%.6f %.6f %.6f", value.red, value.green, value.blue)
    }
}
