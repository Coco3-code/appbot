import SwiftUI
import AVFoundation

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct PreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var detector = Detector()
    var body: some View {
        ZStack(alignment: .bottom) {
            PreviewView(session: detector.session).ignoresSafeArea()
            VStack(spacing: 4) {
                Text(detector.label).font(.title2).bold()
                BLEStatus(ble: detector.ble)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .padding()
        }
        .onAppear { detector.start() }
    }
}

struct BLEStatus: View {
    @ObservedObject var ble: BLEManager
    var body: some View { Text(ble.status).font(.footnote) }
}
