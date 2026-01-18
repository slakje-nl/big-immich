//
//  Typing.swift
//  BigImmich
//
//  Created by Maciej Płoński on 16/01/2026.
//

public protocol CustomString: RawRepresentable, Codable, Hashable, Equatable
where RawValue == String {
    init(rawValue: String)
}

extension CustomString {
    public init(rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public var string: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct AlbumID: CustomString {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct AlbumName: CustomString {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct AssetID: CustomString {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
