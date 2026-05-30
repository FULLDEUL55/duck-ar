//
//  DepthFrame.swift
//  DuckAR
//
//  Perception domain model: one monocular metric-depth result. Pure value
//  type (row-major Float buffer + sampling math); no ARKit/Vision/RealityKit
//  and no CoreML reference types. The depth backend (Metric3DDepthEstimator +
//  PerceptionCoordinator) fills this in; Scene consumers (DepthNavigationField,
//  DepthOcclusionMeshBuilder) read it through metricDepth(atVisionNormalizedPoint:)
//  without knowing the producer.
//

import CoreGraphics
import Foundation
import simd

// `depth` is a row-major [height * width] Float32 buffer of metric depth in
// METERS, in the portrait-upright frame (same orientation Vision detection
// uses). `contentRect` marks the non-padded image region inside the buffer
// (normalized, origin top-left) because the model input is letterboxed into a
// square — padded borders carry no depth.
struct DepthFrame: Sendable {
    let depth: [Float]
    let width: Int
    let height: Int
    let cameraIntrinsics: simd_float3x3
    let imageResolution: CGSize
    let timestamp: TimeInterval
    let contentRect: CGRect

    /// Metric depth (meters) at a Vision-normalized point (origin lower-left,
    /// portrait-upright). Returns nil if the point falls in the letterbox
    /// padding or the buffer is empty. Samples nearest pixel.
    func metricDepth(atVisionNormalizedPoint p: CGPoint) -> Float? {
        let w = width, h = height
        guard w > 0, h > 0, depth.count == w * h else { return nil }
        // Vision lower-left -> depth-buffer top-left.
        let nx = p.x
        let ny = 1.0 - p.y
        guard contentRect.width > 0, contentRect.height > 0 else { return nil }
        let cx = (nx - contentRect.minX) / contentRect.width
        let cy = (ny - contentRect.minY) / contentRect.height
        guard (0...1).contains(cx), (0...1).contains(cy) else { return nil }
        let col = min(w - 1, max(0, Int((cx * CGFloat(w - 1)).rounded())))
        let row = min(h - 1, max(0, Int((cy * CGFloat(h - 1)).rounded())))
        let value = depth[row * w + col]
        return value.isFinite && value > 0 ? value : nil
    }
}
