import Combine
import Foundation
import simd

struct BehaviorMappingConfig {
    var dwellWindow: TimeInterval = 0.5
    var dwellMinObservations: Int = 2
    var dwellConfidenceSum: Float = 0.6
    var dwellConfidenceMax: Float = 0.5
    // Same furniture class will not re-emit a target position within this window.
    var cooldown: TimeInterval = 2.0
}

enum FurnitureClass: String, Hashable {
    case chair
    case sofa
    case bed
    case table
    case tv
    case refrigerator
    case oven
    case sink
}

enum BehaviorMappingTable {
    // COCO 80 identifier (lowercase) → furniture class. arkit-perception emits
    // both space- and underscore-joined variants for multi-word labels; both
    // appear here so the adapter does not care which spelling arrives.
    static let cocoToFurnitureClass: [String: FurnitureClass] = [
        "chair": .chair,
        "couch": .sofa,
        "sofa": .sofa,
        "bed": .bed,
        "dining table": .table,
        "diningtable": .table,
        "tv": .tv,
        "tvmonitor": .tv,
        "refrigerator": .refrigerator,
        "oven": .oven,
        "sink": .sink
    ]
}

private struct ObservationWindow {
    private(set) var samples: [(timestamp: TimeInterval, confidence: Float)] = []

    mutating func add(timestamp: TimeInterval, confidence: Float, window: TimeInterval) {
        samples.append((timestamp, confidence))
        samples.removeAll { timestamp - $0.timestamp > window }
    }

    mutating func clear() { samples.removeAll() }

    var count: Int { samples.count }
    var confidenceSum: Float { samples.reduce(0) { $0 + $1.confidence } }
    var confidenceMax: Float { samples.map(\.confidence).max() ?? 0 }
}

final class PerceptionToBehaviorAdapter {

    weak var debugLog: DebugLogStore?

    private let behavior: DuckBehaviorCoordinator
    private let config: BehaviorMappingConfig
    private var subscription: AnyCancellable?
    private var windows: [FurnitureClass: ObservationWindow] = [:]
    private var lastTriggerTimestamp: [FurnitureClass: TimeInterval] = [:]

    init(behavior: DuckBehaviorCoordinator, config: BehaviorMappingConfig = BehaviorMappingConfig()) {
        self.behavior = behavior
        self.config = config
    }

    func attach<P: Publisher>(to publisher: P) where P.Output == PerceivedObject, P.Failure == Never {
        subscription = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] object in
                Task { @MainActor in
                    self?.handle(object)
                }
            }
    }

    func detach() {
        subscription?.cancel()
        subscription = nil
        windows.removeAll()
        lastTriggerTimestamp.removeAll()
    }

    private func handle(_ object: PerceivedObject) {
        guard let furniture = BehaviorMappingTable.cocoToFurnitureClass[object.type] else { return }

        var window = windows[furniture] ?? ObservationWindow()
        window.add(timestamp: object.timestamp, confidence: object.confidence, window: config.dwellWindow)
        windows[furniture] = window

        guard window.count >= config.dwellMinObservations else { return }
        guard window.confidenceSum >= config.dwellConfidenceSum
            || window.confidenceMax >= config.dwellConfidenceMax else { return }

        if let last = lastTriggerTimestamp[furniture],
           object.timestamp - last < config.cooldown {
            return
        }
        lastTriggerTimestamp[furniture] = object.timestamp
        windows[furniture]?.clear()

        let t = object.worldTransform.columns.3
        let position = SIMD3<Float>(t.x, t.y, t.z)
        let reason = String(
            format: "saw %@ cls=%@ conf=%.2f",
            object.type, furniture.rawValue, window.confidenceMax
        )
        print(String(
            format: "🦆 → walking @ (%.2f, %.2f, %.2f) (%@)",
            position.x, position.y, position.z, reason
        ))
        behavior.setTarget(position)
        behavior.request(DuckBehaviorRequest(target: .walking, reason: reason))
    }
}
