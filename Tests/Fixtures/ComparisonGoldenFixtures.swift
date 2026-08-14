import DryFireVisionCore
import Foundation

public enum ComparisonGoldenFixtures {
    public static let tolerance = 0.0001

    public static let pairSimilarities: [SyntheticComparisonFixtureID: Double?] = [
        .identicalDuration: 1.0,
        .identicalShapeDifferentSpeed: 1.0,
        .smallDivergence: 1.0 / 1.025,
        .largeDivergence: 1.0 / 1.675,
        .missingJoint: 1.0,
        .insufficientOverlap: nil,
        .irregularTimestamps: 1.0
    ]

    public static let sessionExpectations: [SyntheticSessionComparisonFixtureID: (representativeIndex: Int?, fastestIndex: Int?, outlierIndices: [Int], consistency: Double?)] = [
        .identical10: (0, 0, [], 1.0),
        .oneOutlier: (0, 0, [9], 1.0),
        .fastOutlier: (0, 9, [9], 1.0),
        .speedVariationSameShape: (0, 0, [], 1.0),
        .insufficient: (0, 0, [], nil)
    ]
}
