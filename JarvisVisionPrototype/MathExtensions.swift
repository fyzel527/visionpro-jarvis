import Foundation
import simd

func clamped<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}

extension simd_float4x4 {
    var translation: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}

extension SIMD3 where Scalar == Float {
    static func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        let amount = Swift.min(Swift.max(t, 0), 1)
        return a + (b - a) * amount
    }

    var safeNormalized: SIMD3<Float> {
        let length = simd_length(self)
        guard length > 0.0001 else { return SIMD3<Float>(0, 1, 0) }
        return self / length
    }
}
