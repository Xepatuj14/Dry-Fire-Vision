import Foundation

public enum FutureRecordedSegmentationFixtureID: String, CaseIterable, Sendable {
    case frontGood10 = "DF_FRONT_GOOD_10"
    case fortyFiveGood10 = "DF_45_GOOD_10"
    case sideGood10 = "DF_SIDE_GOOD_10"
    case fastSlowMix = "DF_FAST_SLOW_MIX"
    case oneOutlier = "DF_ONE_OUTLIER"
    case lowLight = "DF_LOW_LIGHT"
    case wristOcclusionShort = "DF_WRIST_OCCLUSION_SHORT"
    case wristOcclusionLong = "DF_WRIST_OCCLUSION_LONG"
    case leavesFrame = "DF_LEAVES_FRAME"
    case twoPeople = "DF_TWO_PEOPLE"
    case cameraMoved = "DF_CAMERA_MOVED"
    case pauseMidRep = "DF_PAUSE_MID_REP"
    case falseStart = "DF_FALSE_START"
    case noReps = "DF_NO_REPS"
}
