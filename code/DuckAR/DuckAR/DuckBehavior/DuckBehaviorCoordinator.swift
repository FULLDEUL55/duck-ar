import Combine
import Foundation

struct DuckBehaviorRequest {
    let target: DuckState
    let reason: String
    let receivedAt: Date

    init(target: DuckState, reason: String, receivedAt: Date = Date()) {
        self.target = target
        self.reason = reason
        self.receivedAt = receivedAt
    }
}

struct DuckTransitionRule {
    let target: DuckState
    // nil = transition allowed from any state. Keeps rule table compact.
    let allowedFrom: Set<DuckState>?
    let priority: Int

    func isAllowed(from state: DuckState) -> Bool {
        guard let allowedFrom else { return true }
        return allowedFrom.contains(state)
    }
}

enum DuckTransitionTable {
    // Data-driven rules: each target state declares which sources may enter
    // and its priority when multiple requests arrive in the same tick.
    static let rules: [DuckState: DuckTransitionRule] = [
        .idle: DuckTransitionRule(
            target: .idle,
            allowedFrom: nil,
            priority: 0
        ),
        .walking: DuckTransitionRule(
            target: .walking,
            allowedFrom: [.idle, .lookingAround],
            priority: 1
        ),
        .lookingAround: DuckTransitionRule(
            target: .lookingAround,
            allowedFrom: [.idle, .walking],
            priority: 2
        ),
        .pecking: DuckTransitionRule(
            target: .pecking,
            allowedFrom: [.idle, .walking],
            priority: 3
        ),
        .sitting: DuckTransitionRule(
            target: .sitting,
            allowedFrom: [.idle, .walking],
            priority: 4
        )
    ]

    static func rule(for state: DuckState) -> DuckTransitionRule? {
        rules[state]
    }
}

final class DuckBehaviorCoordinator {
    static let idleTickInterval: TimeInterval = 0.5

    private let stateSubject = CurrentValueSubject<DuckState, Never>(.idle)
    private let targetPositionSubject = CurrentValueSubject<SIMD3<Float>?, Never>(nil)
    private var pendingRequests: [DuckBehaviorRequest] = []
    private var idleTickTimer: Timer?

    var currentState: DuckState { stateSubject.value }

    var currentStatePublisher: AnyPublisher<DuckState, Never> {
        stateSubject.removeDuplicates().eraseToAnyPublisher()
    }

    var currentTargetPosition: SIMD3<Float>? { targetPositionSubject.value }

    var targetPositionPublisher: AnyPublisher<SIMD3<Float>?, Never> {
        targetPositionSubject.eraseToAnyPublisher()
    }

    func setTarget(_ position: SIMD3<Float>?) {
        targetPositionSubject.send(position)
    }

    func start() {
        guard idleTickTimer == nil else { return }
        idleTickTimer = Timer.scheduledTimer(
            withTimeInterval: Self.idleTickInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleIdleTick()
            }
        }
    }

    func stop() {
        idleTickTimer?.invalidate()
        idleTickTimer = nil
    }

    func request(_ request: DuckBehaviorRequest) {
        pendingRequests.append(request)
        evaluatePending()
    }

    private func evaluatePending() {
        guard !pendingRequests.isEmpty else { return }
        let current = stateSubject.value
        let allowed = pendingRequests.compactMap { req -> (DuckBehaviorRequest, DuckTransitionRule)? in
            guard let rule = DuckTransitionTable.rule(for: req.target),
                  rule.isAllowed(from: current) else { return nil }
            return (req, rule)
        }
        pendingRequests.removeAll()
        guard let winner = allowed.max(by: { $0.1.priority < $1.1.priority }) else { return }
        guard winner.0.target != current else { return }
        stateSubject.send(winner.0.target)
    }

    // Drains queued requests even without new perception events so a request
    // that arrived but was blocked by a transient state can still resolve.
    private func handleIdleTick() {
        evaluatePending()
    }
}
