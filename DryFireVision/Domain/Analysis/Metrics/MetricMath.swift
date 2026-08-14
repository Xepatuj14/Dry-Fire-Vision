import Foundation

public enum MetricMath {
    public static func euclideanDistance(x1: Double, y1: Double, x2: Double, y2: Double) -> Double? {
        guard x1.isFinite, y1.isFinite, x2.isFinite, y2.isFinite else {
            return nil
        }
        let value = hypot(x2 - x1, y2 - y1)
        return value.isFinite ? value : nil
    }

    public static func pathLength(_ positions: [NormalizedJointPosition]) -> Double? {
        guard positions.count >= 2 else {
            return nil
        }

        var total = 0.0
        for pair in zip(positions, positions.dropFirst()) {
            guard let distance = euclideanDistance(
                x1: pair.0.x,
                y1: pair.0.y,
                x2: pair.1.x,
                y2: pair.1.y
            ) else {
                return nil
            }
            total += distance
        }

        return total.isFinite ? total : nil
    }
}
