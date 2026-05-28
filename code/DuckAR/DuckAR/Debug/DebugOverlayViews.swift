//
//  DebugOverlayViews.swift
//  DuckAR
//
//  SwiftUI overlays drawn over ARViewContainer:
//   - DebugConsoleOverlay: rolling log + model name (top-left)
//   - DetectionOverlay: per-detection bbox + label (anchored to ARView coords)
//

import QuartzCore
import SwiftUI

struct DebugConsoleOverlay: View {
    @ObservedObject var store: DebugLogStore
    let modelName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Model: \(modelName)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
            ForEach(store.lines.suffix(DebugLogStore.maxLines)) { line in
                Text("[\(line.level.rawValue)] \(line.message)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(line.level.color)
            }
        }
        .padding(8)
        .background(.black.opacity(0.55))
        .cornerRadius(8)
        .padding(.top, 40)
        .padding(.leading, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

struct DetectionOverlay: View {
    @ObservedObject var store: PerceptionOverlayStore

    var body: some View {
        GeometryReader { geo in
            // TimelineView ticks so stale bboxes fall off even without new
            // detections — store's filter uses CACurrentMediaTime, matching
            // PerceivedObject.timestamp's timebase.
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let now = CACurrentMediaTime()
                ZStack(alignment: .topLeading) {
                    ForEach(store.visibleItems(at: now)) { item in
                        boundingBox(for: item.object, in: geo.size)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func boundingBox(for object: PerceivedObject, in size: CGSize) -> some View {
        let rect = object.screenRect(in: size)
        let color = Self.color(for: object.confidence)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(color, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
            Text(String(format: "%@ %.2f", object.type, object.confidence))
                .font(.caption2.bold())
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(color.opacity(0.8))
                .foregroundStyle(.black)
                .offset(y: -16)
        }
        .position(x: rect.midX, y: rect.midY)
    }

    private static func color(for confidence: Float) -> Color {
        switch confidence {
        case ..<0.5: return .gray
        case ..<0.7: return .yellow
        default: return .green
        }
    }
}
