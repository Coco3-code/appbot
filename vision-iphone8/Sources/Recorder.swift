import CoreImage
import ImageIO
import UIKit

/// Enregistre des images 128x128 dans Documents/session-AAAAMMJJ-HHMMSS/
/// Le nom du fichier contient la commande que tu donnais : 00012_F.jpg (F avant, L gauche, R droite).
final class Recorder {
    private let context = CIContext()
    private var folder: URL?
    private(set) var count = 0

    var isRecording: Bool { folder != nil }

    func start() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let url = docs.appendingPathComponent("session-" + f.string(from: Date()))
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folder = url
        count = 0
    }

    func stop() { folder = nil }

    func save(_ px: CVPixelBuffer, command: Character) {
        guard let folder, ["F", "L", "R"].contains(command) else { return }
        var img = CIImage(cvPixelBuffer: px).oriented(.right)      // portrait
        let e = img.extent
        // Image ecrasee en carre 128x128, comme le fait Vision (.scaleFill) a l'inference
        img = img.transformed(by: CGAffineTransform(scaleX: 128 / e.width, y: 128 / e.height)
            .translatedBy(x: -e.minX, y: -e.minY))
        guard let data = context.jpegRepresentation(
            of: img, colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8]) else { return }
        let name = String(format: "%05d_%@.jpg", count, String(command))
        try? data.write(to: folder.appendingPathComponent(name))
        count += 1
    }
}
