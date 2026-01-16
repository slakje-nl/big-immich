import ImmichAPI
import SwiftUI

final class CustomStringKey<T: CustomString>: NSObject {
    let value: T

    init(_ value: T) {
        self.value = value
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? CustomStringKey<T> else { return false }
        return value == other.value
    }

    override var hash: Int {
        value.hashValue
    }
}

final class ImageWrapper {
    let image: Image
    init(_ image: Image) {
        self.image = image
    }
}

final class ImageCache<T: CustomString> {
    private let cache = NSCache<CustomStringKey<T>, ImageWrapper>()

    init(countLimit: Int? = nil, megaBytesLimit: Int? = nil) {
        if let countLimit {
            cache.countLimit = countLimit
        }
        if let megaBytesLimit {
            cache.totalCostLimit = megaBytesLimit * 1024 * 1024
        }
    }

    func get(_ key: T) -> Image? {
        cache.object(forKey: CustomStringKey(key))?.image
    }

    func set(_ key: T, image: Image) {
        cache.setObject(ImageWrapper(image), forKey: CustomStringKey(key))
    }

    func clear() {
        cache.removeAllObjects()
    }
}
