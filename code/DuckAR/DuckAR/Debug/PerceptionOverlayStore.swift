//
//  PerceptionOverlayStore.swift
//  DuckAR
//
//  Keeps the most recent PerceivedObjects in memory so the SwiftUI overlay
//  can draw bounding boxes. Wraps each object in an Identifiable item — the
//  PerceivedObject itself stays Equatable for Combine deduping.
//

import Combine
import Foundation
import QuartzCore

@MainActor
final class PerceptionOverlayStore: ObservableObject {

    static let maxItems: Int = 5
    static let staleAfter: TimeInterval = 0.5

    struct Item: Identifiable {
        let id = UUID()
        let object: PerceivedObject
    }

    @Published private(set) var items: [Item] = []

    func ingest(_ object: PerceivedObject) {
        items.append(Item(object: object))
        // Drop anything older than the staleness window using the same
        // timebase as the new object (ARFrame.timestamp = CACurrentMediaTime).
        items.removeAll { object.timestamp - $0.object.timestamp > Self.staleAfter }
        if items.count > Self.maxItems {
            items.removeFirst(items.count - Self.maxItems)
        }
    }

    func visibleItems(at mediaTime: TimeInterval) -> [Item] {
        items.filter { mediaTime - $0.object.timestamp <= Self.staleAfter }
    }
}
