import ImmichAPI
import SwiftUI

/// Boxes a value in a class so `NSCache` (which requires `AnyObject`) can hold it.
///
/// Deliberately **non-generic** (stores `Any`, not a generic `Value`): a generic
/// `final class` that stores a value of its own generic parameter crashes the Swift
/// 6.3 optimizer's performance inliner in `-O` builds — an infinite recursion in
/// `isCallerAndCalleeLayoutConstraintsCompatible` while inlining the class's `deinit`,
/// which surfaces at archive time. Keeping the stored property concrete avoids it.
final class StructWrapper {
    let value: Any
    init(_ value: Any) {
        self.value = value
    }
}

/// An `NSObject` cache key built from a `CustomString`'s underlying string, so the
/// cache stays keyed by the app's typed id wrappers. Non-generic for the same
/// optimizer reason as `StructWrapper` — it stores the `String`, not the generic `T`.
final class CustomStringKey: NSObject {
    let value: String

    init(_ value: some CustomString) {
        self.value = value.rawValue
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? CustomStringKey else { return false }
        return value == other.value
    }

    override var hash: Int {
        value.hashValue
    }
}

/// A `struct` rather than a `class` on purpose: a generic `final class`'s deallocating
/// `deinit` crashes the Swift 6.3 optimizer's inliner in `-O` builds. A struct has no
/// such `deinit`, and since it only holds a reference to the `NSCache`, copies still
/// share one underlying cache — reference semantics are preserved where they matter.
struct MemoryCache<Key: CustomString, Value> {
    private let cache = NSCache<CustomStringKey, StructWrapper>()

    init(countLimit: Int? = nil, megaBytesLimit: Int? = nil) {
        if let countLimit {
            cache.countLimit = countLimit
        }
        if let megaBytesLimit {
            cache.totalCostLimit = megaBytesLimit * 1024 * 1024
        }
    }

    func get(_ key: Key) -> Value? {
        cache.object(forKey: CustomStringKey(key))?.value as? Value
    }

    func set(_ key: Key, value: Value) {
        cache.setObject(StructWrapper(value), forKey: CustomStringKey(key))
    }

    func clear() {
        cache.removeAllObjects()
    }
}
