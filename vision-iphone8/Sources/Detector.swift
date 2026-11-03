import AVFoundation
import Vision
import CoreML

/// Messages BLE vers l'ESP32 (1er octet = type)
///  1 STOP            : [1]
///  2 POSITION dechet : [2, x, y, w, h]   (0..255, origine en haut a gauche)
///  3 GO (reprise)    : [3]
///  4 OBSTACLES       : [4, masque]       (bit0 gauche, bit1 centre, bit2 droite)
///  Le message 4 est envoye ~10 fois/s : il sert aussi de signal de vie.
private enum Msg: UInt8 { case stop = 1, position = 2, go = 3, obstacles = 4 }

final class Detector: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let ble = BLEManager()
    @Published var label = "-"

    private var request: VNCoreMLRequest?
    private let queue = DispatchQueue(label: "video")
    private var lastSend = Date.distantPast
    private var seenFrames = 0
    private var lostFrames = 0
    private var stopped = false

    func start() {
        guard let url = Bundle.main.url(forResource: "best", withExtension: "mlmodelc"),
              let ml = try? MLModel(contentsOf: url),
              let vn = try? VNCoreMLModel(for: ml) else {
            label = "Modele introuvable"
            return
        }
        let r = VNCoreMLRequest(model: vn)
        r.imageCropAndScaleOption = .scaleFill
        request = r
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { return }
            self.queue.async { self.configure() }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(out) { session.addOutput(out) }
        session.commitConfiguration()
        session.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let px = CMSampleBufferGetImageBuffer(sampleBuffer), let request else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: px, orientation: .right)
        try? handler.perform([request])
        let results = (request.results as? [VNRecognizedObjectObservation]) ?? []

        let dechets = results.filter { $0.confidence > 0.5 && $0.labels.first?.identifier == "dechet" }
        let obstacles = results.filter { $0.confidence > 0.4 && $0.labels.first?.identifier == "obstacle" }

        // --- Obstacles : masque gauche / centre / droite ---
        var mask: UInt8 = 0
        for o in obstacles {
            let b = o.boundingBox
            if b.width * b.height < 0.03 { continue }      // trop petit = trop loin
            if b.minX < 0.33 { mask |= 1 }
            if b.maxX > 0.33 && b.minX < 0.66 { mask |= 2 }
            if b.maxX > 0.66 { mask |= 4 }
        }

        // --- Dechet : STOP immediat, puis position, puis GO quand il a disparu ---
        let best = dechets.max(by: { $0.confidence < $1.confidence })
        if best != nil {
            lostFrames = 0
            seenFrames += 1
            if !stopped && seenFrames >= 3 {          // 3 images de suite = detection fiable
                stopped = true
                ble.sendReliable(Data([Msg.stop.rawValue]))
            }
        } else {
            seenFrames = 0
            if stopped {
                lostFrames += 1
                if lostFrames >= 10 {
                    stopped = false
                    ble.sendReliable(Data([Msg.go.rawValue]))
                }
            }
        }

        // --- Envois periodiques (10/s max) ---
        if Date().timeIntervalSince(lastSend) > 0.1 {
            lastSend = Date()
            ble.send(Data([Msg.obstacles.rawValue, mask]))
            if stopped, let b = best?.boundingBox {
                func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(1, v)) * 255) }
                ble.send(Data([Msg.position.rawValue, byte(b.midX), byte(1 - b.midY),
                               byte(b.width), byte(b.height)]))
            }
        }

        let text = (best.map { "Dechet \(Int($0.confidence * 100))%" } ?? "Pas de dechet")
            + " | obstacles: "
            + (mask & 1 != 0 ? "G " : "") + (mask & 2 != 0 ? "C " : "") + (mask & 4 != 0 ? "D" : "")
        DispatchQueue.main.async { self.label = text }
    }
}
