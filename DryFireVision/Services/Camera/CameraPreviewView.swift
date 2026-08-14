import SwiftUI

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(UIKit)
import UIKit

public struct CameraPreviewView: UIViewRepresentable {
    private let previewSession: CameraPreviewSession

    public init(previewSession: CameraPreviewSession) {
        self.previewSession = previewSession
    }

    public func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = previewSession.captureSession
        return view
    }

    public func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.previewLayer.session = previewSession.captureSession
    }
}

public final class PreviewContainerView: UIView {
    public override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // UIKit constructs this view with layerClass, so the layer type is mechanically guaranteed.
        layer as! AVCaptureVideoPreviewLayer
    }
}
#elseif canImport(AppKit)
import AppKit

public struct CameraPreviewView: NSViewRepresentable {
    private let previewSession: CameraPreviewSession

    public init(previewSession: CameraPreviewSession) {
        self.previewSession = previewSession
    }

    public func makeNSView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = previewSession.captureSession
        return view
    }

    public func updateNSView(_ nsView: PreviewContainerView, context: Context) {
        nsView.previewLayer.session = previewSession.captureSession
    }
}

public final class PreviewContainerView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer = previewLayer
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }
}
#endif
