import Foundation
import AppKit

/// Prepares a user-chosen image for Spotify's playlist cover endpoint.
///
/// Spotify's `PUT /playlists/{id}/images` wants a **base64-encoded JPEG**, and the
/// base64 payload must be **≤ 256 KB**. We center-crop to a square, scale to
/// 640×640 (Spotify stores a few sizes; 640 is the largest it serves, so there's
/// no gain shipping more pixels), then JPEG-encode, stepping quality down until the
/// base64 string fits under the cap.
enum PlaylistImage {
    /// Hard ceiling Spotify enforces on the base64 body.
    static let maxBase64Bytes = 256 * 1024
    /// Largest cover size Spotify serves — no reason to encode more pixels.
    static let edge: CGFloat = 640

    enum PrepError: LocalizedError {
        case unreadable
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .unreadable: return "That file couldn't be read as an image."
            case .tooLarge:   return "That image is too detailed to fit Spotify's cover size limit."
            }
        }
    }

    /// Read the file at `url`, produce a square 640×640 JPEG, and return it
    /// base64-encoded and under Spotify's size cap. Throws `PrepError` on failure.
    static func base64JPEG(from url: URL) throws -> String {
        guard let image = NSImage(contentsOf: url) else { throw PrepError.unreadable }
        return try base64JPEG(from: image)
    }

    /// Same, from an already-loaded `NSImage` (used by the cover preview path).
    static func base64JPEG(from image: NSImage) throws -> String {
        let square = squareBitmap(image, edge: edge)

        // Step quality down until the base64 payload fits. 0.5 still looks fine on a
        // 640px cover; below that we'd rather fail loudly than ship a mushy image.
        for quality in stride(from: 0.9, through: 0.5, by: -0.1) {
            guard let jpeg = square.representation(using: .jpeg,
                                                   properties: [.compressionFactor: quality])
            else { continue }
            let base64 = jpeg.base64EncodedString()
            if base64.utf8.count <= maxBase64Bytes { return base64 }
        }
        throw PrepError.tooLarge
    }

    /// Center-crop `image` to a square and redraw it into an `edge`×`edge` bitmap.
    private static func squareBitmap(_ image: NSImage, edge: CGFloat) -> NSBitmapImageRep {
        let px = Int(edge)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = NSSize(width: edge, height: edge)

        // Source crop: the largest centered square of the original.
        let s = image.size
        let side = min(s.width, s.height)
        let srcRect = NSRect(x: (s.width - side) / 2, y: (s.height - side) / 2,
                             width: side, height: side)

        let destRect = NSRect(x: 0, y: 0, width: edge, height: edge)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // JPEG has no alpha channel: a transparent PNG would otherwise flatten to
        // black. Lay down a white matte first, then composite the image over it.
        NSColor.white.setFill()
        destRect.fill()
        image.draw(in: destRect, from: srcRect, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
