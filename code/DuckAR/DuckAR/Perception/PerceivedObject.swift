//
//  PerceivedObject.swift
//  DuckAR
//
//  Perception domain model. Pure value type — no ARKit/Vision/RealityKit.
//  The ARSession/Vision infrastructure (PerceptionCoordinator) produces these;
//  duck-behavior consumes them through PerceivedObjectSource without ever
//  touching a framework type. This is the inbound boundary of the domain.
//

import CoreGraphics
import Foundation
import simd

struct PerceivedObject: Sendable, Equatable {
    let type: String
    let worldTransform: simd_float4x4
    let confidence: Float
    let timestamp: TimeInterval
    // Vision-native: normalized [0,1]², origin lower-left, portrait-upright
    // (matches the orientation we feed VNImageRequestHandler).
    let normalizedBoundingBox: CGRect

    // Convert the Vision bbox into UIKit view coordinates (origin upper-left).
    // Phase 1 sanity mapping: linear scale, no camera-image aspect-crop correction.
    func screenRect(in viewSize: CGSize) -> CGRect {
        CGRect(
            x: normalizedBoundingBox.minX * viewSize.width,
            y: (1.0 - normalizedBoundingBox.maxY) * viewSize.height,
            width: normalizedBoundingBox.width * viewSize.width,
            height: normalizedBoundingBox.height * viewSize.height
        )
    }
}
