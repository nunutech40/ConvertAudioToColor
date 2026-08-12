import Foundation

enum AudioMath {
    static func clamp(_ value: Float, _ lower: Float = 0, _ upper: Float = 1) -> Float {
        min(max(value, lower), upper)
    }

    static func normalized(_ value: Float, min: Float, max: Float) -> Float {
        guard max > min else { return 0 }
        return clamp((value - min) / (max - min))
    }

    static func smooth(previous: Float, current: Float, factor: Float = 0.18) -> Float {
        previous + (current - previous) * clamp(factor)
    }
}
