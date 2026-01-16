import ImmichAPI
import SwiftUI

final class StructWrapper<Value> {
    let value: Value
    init(_ value: Value) {
        self.value = value
    }
}

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

final class MemoryCache<Key: CustomString, Value> {
    private let cache = NSCache<CustomStringKey<Key>, StructWrapper<Value>>()

    init(countLimit: Int? = nil, megaBytesLimit: Int? = nil) {
        if let countLimit {
            cache.countLimit = countLimit
        }
        if let megaBytesLimit {
            cache.totalCostLimit = megaBytesLimit * 1024 * 1024
        }
    }

    func get(_ key: Key) -> Value? {
        cache.object(forKey: CustomStringKey(key))?.value
    }

    func set(_ key: Key, value: Value) {
        cache.setObject(StructWrapper(value), forKey: CustomStringKey(key))
    }

    func clear() {
        cache.removeAllObjects()
    }
}
