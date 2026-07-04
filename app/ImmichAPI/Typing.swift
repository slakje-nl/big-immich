//
//  Typing.swift
//  BigImmich
//
//  Created by Maciej Płoński on 16/01/2026.
//

public protocol CustomString: RawRepresentable, Codable, Hashable, Equatable
    where RawValue == String
{
    init(rawValue: String)
}

public extension CustomString {
    init(rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var string: String {
        rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
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
