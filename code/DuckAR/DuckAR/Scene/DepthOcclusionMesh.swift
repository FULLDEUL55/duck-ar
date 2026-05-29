//
//  DepthOcclusionMesh.swift
//  DuckAR
//
//  Phase 2 (Task #3): turns the confirmed DepthFrame (Depth Anything V2 Small,
//  see PerceptionCoordinator) into a low-res occlusion proxy mesh so the duck
//  can be hidden behind real furniture. Pure value logic here (config +
//  unprojection); entity/lifecycle lives in DepthOcclusionCoordinator.
//
//  Coordinate reconciliation (the crux):
//  - DepthFrame.map is portrait-upright; lookups go through
//    metricDepth(atVisionNormalizedPoint:) (Vision normalized, origin
//    lower-left).
//  - DepthFrame.cameraIntrinsics is sensor-native landscape (origin top-left,
//    +x right, +y down), the same frame as ARKit's camera transform — hence as
//    AnchorEntity(.camera) local space. So intrinsics-unprojected vertices land
//    directly in camera-local space with no extra rotation.
//  We therefore iterate the grid in the *valid Vision band* (contentRect),
//  fetch metric depth per point, and convert each Vision point back to a
//  landscape pixel for the pinhole unprojection.
//
//  Vision(portrait, lower-left) ↔ landscape(top-left) for the back camera in
//  portrait (.right orientation), derived from a 90° CW sensor→display rotation:
//      lu = 1 - vy ,  lv = 1 - vx        (landscape normalized, origin TL)
//      vx = 1 - lv ,  vy = 1 - lu        (inverse)
//

import CoreML
import Foundation
import RealityKit
import simd

// Tunables for the low-res occlusion proxy. Defaults bias toward iPad Air 5
// (M1, no LiDAR) headroom: a coarse grid regenerated at depth cadence.
struct DepthOcclusionConfig {
    // Proxy grid resolution (columns × rows) sampled across the valid band.
    // 32×24 ≈ 768 verts / ~1.4k tris — cheap to regenerate each depth frame.
    var gridColumns: Int = 32
    var gridRows: Int = 24

    // DepthFrame is documented as metric (meters). Kept as an affine knob in
    // case on-device tuning reveals a residual scale/offset; identity by default.
    // metric = depthScale * sample + depthBias.
    var depthScale: Float = 1.0
    var depthBias: Float = 0.0

    // Clamp to a sane working volume so one bad sample can't spawn a vertex
    // kilometres away and wreck the proxy / renderer.
    var minDepthMeters: Float = 0.15
    var maxDepthMeters: Float = 6.0
}

enum DepthOcclusionMeshBuilder {

    // Builds a proxy mesh in ARKit/RealityKit camera-local space (+x right,
    // +y up, -z forward) by unprojecting a depth grid through the camera
    // intrinsics. Meant to live under AnchorEntity(.camera) wearing an
    // OcclusionMaterial. Returns nil if intrinsics/resolution are degenerate.
    static func makeMesh(
        from frame: DepthFrame,
        config: DepthOcclusionConfig
    ) -> MeshResource? {
        let cols = max(2, config.gridColumns)
        let rows = max(2, config.gridRows)

        // Intrinsics are expressed in `imageResolution` (landscape) pixels.
        let fx = frame.cameraIntrinsics.columns.0.x
        let fy = frame.cameraIntrinsics.columns.1.y
        let cx = frame.cameraIntrinsics.columns.2.x
        let cy = frame.cameraIntrinsics.columns.2.y
        guard fx != 0, fy != 0 else { return nil }

        let imageW = Float(frame.imageResolution.width)
        let imageH = Float(frame.imageResolution.height)
        guard imageW > 0, imageH > 0 else { return nil }

        // Valid Vision band (lower-left) derived from contentRect (upper-left).
        let content = frame.contentRect
        let vxMin = Float(content.minX)
        let vxMax = Float(content.maxX)
        let vyMin = Float(1.0 - (content.minY + content.height))
        let vyMax = Float(1.0 - content.minY)

        var positions = [SIMD3<Float>](repeating: .zero, count: cols * rows)
        var valid = [Bool](repeating: false, count: cols * rows)

        for gy in 0..<rows {
            let t = Float(gy) / Float(rows - 1)
            let vy = vyMin + t * (vyMax - vyMin)
            for gx in 0..<cols {
                let s = Float(gx) / Float(cols - 1)
                let vx = vxMin + s * (vxMax - vxMin)

                guard let raw = frame.metricDepth(
                    atVisionNormalizedPoint: CGPoint(x: CGFloat(vx), y: CGFloat(vy))
                ) else { continue }

                let metric = min(
                    max(config.depthScale * raw + config.depthBias, config.minDepthMeters),
                    config.maxDepthMeters
                )

                // Vision(portrait, lower-left) → landscape pixel (top-left).
                let lu = 1.0 - vy
                let lv = 1.0 - vx
                let u = lu * imageW
                let v = lv * imageH

                // Pinhole unprojection into ARKit camera space (y up, -z forward).
                let x = (u - cx) * metric / fx
                let y = -(v - cy) * metric / fy
                let z = -metric
                let idx = gy * cols + gx
                positions[idx] = SIMD3<Float>(x, y, z)
                valid[idx] = true
            }
        }

        // Emit a triangle only when all four corners of its quad are valid, so
        // letterbox gaps don't stretch geometry across missing depth.
        var indices = [UInt32]()
        indices.reserveCapacity((cols - 1) * (rows - 1) * 6)
        for gy in 0..<(rows - 1) {
            for gx in 0..<(cols - 1) {
                let a = gy * cols + gx
                let b = gy * cols + gx + 1
                let c = (gy + 1) * cols + gx
                let d = (gy + 1) * cols + gx + 1
                guard valid[a], valid[b], valid[c], valid[d] else { continue }
                indices.append(contentsOf: [
                    UInt32(a), UInt32(b), UInt32(c),
                    UInt32(b), UInt32(d), UInt32(c),
                ])
            }
        }
        guard !indices.isEmpty else { return nil }

        var descriptor = MeshDescriptor(name: "DepthOcclusionProxy")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)

        return try? MeshResource.generate(from: [descriptor])
    }
}
