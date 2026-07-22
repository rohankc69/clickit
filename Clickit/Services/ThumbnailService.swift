import AppKit
import ImageIO

/// Produces a small thumbnail from an image file without ever decoding the
/// full-resolution bitmap.
///
/// A screenshot is a few hundred kilobytes on disk but tens of megabytes once
/// decoded to a raw bitmap — width × height × 4. Drawing that into a 32pt tile
/// throws almost all of it away. ImageIO decodes straight to the requested size,
/// so only the thumbnail's bytes are ever allocated. This is the whole reason
/// image history can be browsed without the heap tracking the pixels on disk.
enum ImageDownsampler {
    /// Returns a thumbnail whose longest edge is at most `maxPixelSize`, or `nil`
    /// if the file is missing or not a decodable image.
    ///
    /// Safe to call from any thread: `CGImageSource` is thread-safe and this
    /// holds no shared state.
    static func thumbnail(fileURL: URL, maxPixelSize: Int) -> CGImage? {
        // The source itself is only a handle; we never want it to cache the full
        // decoded image, only to hand us the thumbnail below.
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Honour EXIF orientation so a thumbnail is never sideways.
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decode here, on the calling (background) thread, rather than
            // lazily on the first draw where it would hitch the main thread.
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}

/// Bounded in-memory cache of history thumbnails.
///
/// Keyed by item id, which maps to fixed content: an item's bytes never change
/// once captured, so a cached thumbnail can never go stale, and an id that is
/// deleted is never requested again. The cost limit keeps the cache from
/// becoming the memory problem it exists to solve.
@MainActor
final class ThumbnailCache {
    private let cache = NSCache<NSUUID, NSImage>()

    /// Roughly two hundred 96px thumbnails. Ample for a popover that shows a
    /// dozen rows at a time, and far below the full-image footprint it replaces.
    init(totalCostLimit: Int = 8 * 1_024 * 1_024) {
        cache.totalCostLimit = totalCostLimit
    }

    /// The thumbnail for an image item, decoded off the main thread on a cache
    /// miss so scrolling never blocks on file I/O or a decode.
    func thumbnail(id: UUID, fileURL: URL, maxPixelSize: Int) async -> NSImage? {
        let key = id as NSUUID
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let made = await Task.detached(priority: .utility) { () -> SendableThumbnail? in
            guard let cgImage = ImageDownsampler.thumbnail(fileURL: fileURL, maxPixelSize: maxPixelSize) else {
                return nil
            }
            let size = NSSize(width: cgImage.width, height: cgImage.height)
            return SendableThumbnail(
                image: NSImage(cgImage: cgImage, size: size),
                cost: cgImage.width * cgImage.height * 4
            )
        }.value
        guard let made else { return nil }
        cache.setObject(made.image, forKey: key, cost: made.cost)
        return made.image
    }
}

/// `NSImage` is not `Sendable`, but a freshly decoded thumbnail is immutable and
/// only ever read after this point, so handing it back to the main actor is
/// safe. Constructing it in the background task keeps the main thread free.
private struct SendableThumbnail: @unchecked Sendable {
    let image: NSImage
    let cost: Int
}
