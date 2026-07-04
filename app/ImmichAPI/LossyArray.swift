//
//  LossyArray.swift
//  BigImmich
//
//  Created by Maciej Płoński on 08/04/2026.
//

struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var items: [Element] = []

        while !container.isAtEnd {
            if let item = try? container.decode(Element.self) {
                items.append(item)
            } else {
                // Skip invalid item
                _ = try? container.decode(Dummy.self)
            }
        }

        elements = items
    }

    private struct Dummy: Decodable {}
}
