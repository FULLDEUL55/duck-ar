//
//  DebugLogStore.swift
//  DuckAR
//
//  In-app rolling log surfaced as a SwiftUI overlay. Replaces print() across
//  coordinators so messages are visible during on-device runs without an
//  attached Xcode debugger. `log` is nonisolated so callers on background
//  queues (e.g. Vision inference) don't need to wrap in Task themselves.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class DebugLogStore: ObservableObject {

    static let maxLines: Int = 12

    enum Level: String, Sendable {
        case perception
        case behavior
        case nav
        case system
    }

    struct LogLine: Identifiable, Sendable {
        let id = UUID()
        let timestamp: TimeInterval
        let level: Level
        let message: String
    }

    @Published private(set) var lines: [LogLine] = []

    nonisolated func log(_ level: Level, _ message: String) {
        // Mirror to stderr (NSLog) so on-device runs are inspectable via
        // `devicectl device process launch --console` without an Xcode debugger.
        NSLog("DuckAR[%@] %@", level.rawValue, message)
        let entry = LogLine(
            timestamp: Date().timeIntervalSinceReferenceDate,
            level: level,
            message: message
        )
        Task { @MainActor in
            self.append(entry)
        }
    }

    private func append(_ entry: LogLine) {
        lines.append(entry)
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
    }
}

extension DebugLogStore.Level {
    var color: Color {
        switch self {
        case .perception: return .cyan
        case .behavior: return .yellow
        case .nav: return .green
        case .system: return .white
        }
    }
}
