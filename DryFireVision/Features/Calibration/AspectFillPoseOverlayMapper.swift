import CoreGraphics
import Foundation

struct AspectFillPoseOverlayMapper {
    let sourceAspectRatio: Double

    init(sourceAspectRatio: Double = 9.0 / 16.0) {
        self.sourceAspectRatio = sourceAspectRatio
    }

    func displayPoint(for sample: JointSample, in size: CGSize) -> CGPoint {
        let targetAspectRatio = Double(size.width / max(size.height, 1))
        let imageWidth: Double
        let imageHeight: Double
        let offsetX: Double
        let offsetY: Double

        if targetAspectRatio > sourceAspectRatio {
            imageWidth = Double(size.width)
            imageHeight = imageWidth / sourceAspectRatio
            offsetX = 0
            offsetY = (Double(size.height) - imageHeight) / 2
        } else {
            imageHeight = Double(size.height)
            imageWidth = imageHeight * sourceAspectRatio
            offsetX = (Double(size.width) - imageWidth) / 2
            offsetY = 0
        }

        return CGPoint(
            x: offsetX + sample.x * imageWidth,
            y: offsetY + sample.y * imageHeight
        )
    }
}
