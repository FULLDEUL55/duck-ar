//
//  DepthFrame.swift
//  DuckAR
//
//  Perception domain model: one monocular metric-depth result. Pure value
//  logic (sampling + coordinate math); no ARKit/Vision/RealityKit. The depth
//  backend (Metric3DDepthEstimator + PerceptionCoordinator) fills this in;
//  Scene consumers (DepthNavigationField, DepthOcclusionMeshBuilder) read it
//  through metricDepth(atVisionNormalizedPoint:) without knowing the producer.
//

import CoreGraphics
import CoreML
import Foundation
import simd

// `map` is a 2-D MLMultiArray [H', W'] of Float32 depth in METERS, in the
// portrait-upright frame (same orientation Vision detection uses). `contentRect`
// marks the non-padded image region inside the map (normalized, origin top-left)
// because the input is letterboxed into a square — padded borders carry no depth.
// @unchecked Sendable: MLMultiArray is reference-typed and not Sendable —
// the value is published once and treated as read-only by subscribers.
struct DepthFrame: @unchecked Sendable {
    let map: MLMultiArray
    let cameraIntrinsics: simd_float3x3
    let imageResolution: CGSize
    let timestamp: TimeInterval
    let contentRect: CGRect

    var width: Int { map.shape.count == 2 ? map.shape[1].intValue : 0 }
    var height: Int { map.shape.count == 2 ? map.shape[0].intValue : 0 }

    /// Metric depth (meters) at a Vision-normalized point (origin lower-left,
    /// portrait-upright). Returns nil if the point falls in the letterbox
    /// padding or the map is empty. Samples nearest pixel.
    func metricDepth(atVisionNormalizedPoint p: CGPoint) -> Float? {
        let w = width, h = height
        guard w > 0, h > 0 else { return nil }
        // Vision lower-left -> depth-map top-left.
        let nx = p.x
        let ny = 1.0 - p.y
        guard contentRect.width > 0, contentRect.height > 0 else { return nil }
        let cx = (nx - contentRect.minX) / contentRect.width
        let cy = (ny - contentRect.minY) / contentRect.height
        guard (0...1).contains(cx), (0...1).contains(cy) else { return nil }
        let col = min(w - 1, max(0, Int((cx * CGFloat(w - 1)).rounded())))
        let row = min(h - 1, max(0, Int((cy * CGFloat(h - 1)).rounded())))
        let value = map[[NSNumber(value: row), NSNumber(value: col)]].floatValue
        return value.isFinite && value > 0 ? value : nil
    }
}
