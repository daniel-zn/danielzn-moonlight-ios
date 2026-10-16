//
//  BoxArtCache.swift
//  Artemis
//
//  Decoded box art from AppAssetManager's files, decoded off the main thread
//  (lazy decoding made scrolling janky upstream).
//

import UIKit

final class BoxArtCache: @unchecked Sendable {
    static let shared = BoxArtCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(atPath path: String, reload: Bool = false) -> UIImage? {
        let key = path as NSString
        if !reload, let cached = cache.object(forKey: key) {
            return cached
        }
        // No box art on disk yet
        guard let image = UIImage(contentsOfFile: path)?.preparingForDisplay() else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
