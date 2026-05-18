import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

enum QRCode {
    /// Render `text` as a square QR code at the requested point size.
    /// Returns nil if CoreImage refuses the input (extremely long strings).
    static func image(from text: String, size: CGFloat = 240) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        // "H" = highest error correction so a printed/scanned QR survives ~30% damage.
        filter.correctionLevel = "H"

        guard let outputImage = filter.outputImage else { return nil }

        // Nearest-neighbor upscale → crisp blocks, no blur.
        let scale = size / outputImage.extent.width
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
