import CoreGraphics
import Foundation
import Vision

/// Payload formatting shared by the picker and the history window, so the two can't drift.
extension String {
    var payloadIsURL: Bool {
        guard let url = URL(string: self), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    /// Short label: host for URLs, a generic descriptor otherwise.
    var payloadSubtitle: String {
        if payloadIsURL, let host = URL(string: self)?.host { return host }
        return "Plain text"
    }
}

struct QRResult: Identifiable, Hashable {
    let id = UUID()
    let payload: String
    /// Fraction of the screen the code occupies — used to rank the picker list.
    let area: CGFloat

    var isURL: Bool { payload.payloadIsURL }

    var subtitle: String { payload.payloadSubtitle }
}

enum QRScanner {
    /// Decodes every QR code in `image`, largest first, de-duplicated by payload.
    static func scan(_ image: CGImage) -> [QRResult] {
        var results = detect(in: image)

        // Vision occasionally misses codes in very large images. A half-scale retry is
        // cheap and picks up cases the full-resolution pass drops.
        if results.isEmpty, let smaller = downscale(image, by: 0.5) {
            results = detect(in: smaller)
        }

        var seen = Set<String>()
        return results
            .sorted { $0.area > $1.area }
            .filter { seen.insert($0.payload).inserted }
    }

    private static func detect(in image: CGImage) -> [QRResult] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        return (request.results ?? []).compactMap { observation in
            guard let payload = observation.payloadStringValue, !payload.isEmpty else { return nil }
            let box = observation.boundingBox
            return QRResult(payload: payload, area: box.width * box.height)
        }
    }

    private static func downscale(_ image: CGImage, by factor: CGFloat) -> CGImage? {
        let width = Int(CGFloat(image.width) * factor)
        let height = Int(CGFloat(image.height) * factor)
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
              )
        else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
