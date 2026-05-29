//
//  DepthOcclusionMesh.swift
//  DuckAR
//
//  Phase 2 (Task #3): turns a monocular depth map into a low-res occlusion
//  proxy mesh so the duck can be hidden behind real furniture. Pure value
//  logic here (config + sampling + unprojection); the entity/lifecycle side
//  lives in DepthOcclusionCoordinator.
//
//  The depth source is Depth Anything V2 Small (see
//  docs/research/metric3d-small-conversion.md): affine-invariant *relative*
//  depth, not metric. Absolute scale must be recovered (rawScale/rawBias)
//  before the proxy lines up with the world-space duck. Several layout knobs
//  (flips / axis swap) stay UNCONFIRMED until arkit-perception pins the
//  published DepthFrame orientation — they're exposed so we can match without
//  touching the unprojection math.
//

import CoreML
import Foundation
import RealityKit
import simd

// Tunables for the low-res occlusion proxy. Defaults bias toward iPad Air 5
// (M1, no LiDAR) headroom: a coarse grid regenerated at depth cadence.
struct DepthOcclusionConfig {
    // Proxy grid resolution (columns × rows) the depth map is downsampled to.
    // 32×24 ≈ 768 verts / ~1.4k tris — cheap to regenerate each depth frame.
    var gridColumns: Int = 32
    var gridRows: Int = 24

    // Depth Anything V2 is affine-invariant *relative* depth. Convert a raw
    // sample → metres via  metres = rawScale * sample + rawBias.
    // Identity until ground-plane calibration lands (see coordinator.calibrate).
    var rawScale: Float = 1.0
    var rawBias: Float = 0.0

    // Some depth models emit inverse depth (near = large value). Flip if so.
    var invertDepth: Bool = false

    // Clamp to a sane working volume so one bad sample can't spawn a vertex
    // kilometres away and wreck the proxy / renderer.
    var minDepthMeters: Float = 0.15
    var maxDepthMeters: Float = 6.0

    // Pixel-layout reconciliation between the depth map and the intrinsics'
    // coordinate frame. UNCONFIRMED until arkit-perception pins orientation
    // (the detector runs Vision with .right for portrait, while intrinsics are
    // currently published sensor-native landscape) — knobs, not hardcodes.
    var flipU: Bool = false
    var flipV: Bool = false
    var swapUV: Bool = false
}

struct DepthMapDimensions {
    let rows: Int   // height
    let cols: Int   // width
}

// Reads a depth MLMultiArray defensively: dimensions come from the trailing
// two axes (tolerating leading batch/channel dims) and samples use the array's
// own strides. NOTE: if perception ends up publishing the Depth Anything V2
// ImageType output as a CVPixelBuffer instead of an MLMultiArray, DepthFrame
// and this reader need a CVPixelBuffer variant — flagged to arkit-perception.
enum DepthMapReader {

    static func dimensions(of map: MLMultiArray) -> DepthMapDimensions? {
        let shape = map.shape.map { $0.intValue }
        guard shape.count >= 2 else { return nil }
        let rows = shape[shape.count - 2]
        let cols = shape[shape.count - 1]
        guard rows > 0, cols > 0 else { return nil }
        return DepthMapDimensions(rows: rows, cols: cols)
    }

    // Single sample via flat index built from strides. Boxed NSNumber reads are
    // fine at proxy resolution (≤ ~1k samples/frame); switch to dataPointer if
    // the grid is ever pushed high.
    static func sample(_ map: MLMultiArray, row: Int, col: Int) -> Float {
        let shape = map.shape.map { $0.intValue }
        let strides = map.strides.map { $0.intValue }
        let rowStride = strides[shape.count - 2]
        let colStride = strides[shape.count - 1]
        let index = row * rowStride + col * colStride
        return map[index].floatValue
    }
}

enum DepthOcclusionMeshBuilder {

    // Builds a proxy mesh in ARKit camera-local space (+x right, +y up,
    // -z forward) by unprojecting a downsampled depth grid through the camera
    // intrinsics. Meant to live under AnchorEntity(.camera) wearing an
    // OcclusionMaterial.
    static func makeMesh(
        from frame: DepthFrame,
        config: DepthOcclusionConfig
    ) -> MeshResource? {
        guard let dims = DepthMapReader.dimensions(of: frame.map) else { return nil }

        let cols = max(2, config.gridColumns)
        let rows = max(2, config.gridRows)

        // Intrinsics are expressed in `imageResolution` pixels.
        let fx = frame.cameraIntrinsics.columns.0.x
        let fy = frame.cameraIntrinsics.columns.1.y
        let cx = frame.cameraIntrinsics.columns.2.x
        let cy = frame.cameraIntrinsics.columns.2.y
        guard fx != 0, fy != 0 else { return nil }

        let imageW = Float(frame.imageResolution.width)
        let imageH = Float(frame.imageResolution.height)
        guard imageW > 0, imageH > 0 else { return nil }

        var positions = [SIMD3<Float>]()
        positions.reserveCapacity(cols * rows)

        for gy in 0..<rows {
            for gx in 0..<cols {
                // Normalized grid coordinate in [0,1].
                let s = Float(gx) / Float(cols - 1)
                let t = Float(gy) / Float(rows - 1)

                let depth = sampleMetricDepth(
                    frame: frame, dims: dims, s: s, t: t, config: config
                )

                // Image-pixel coordinate the intrinsics expect.
                let u = s * imageW
                let v = t * imageH

                // Pinhole unprojection. Image y is down → negate for camera y up.
                let x = (u - cx) * depth / fx
                let y = -(v - cy) * depth / fy
                let z = -depth   // ARKit camera looks down local -z
                positions.append(SIMD3<Float>(x, y, z))
            }
        }

        var indices = [UInt32]()
        indices.reserveCapacity((cols - 1) * (rows - 1) * 6)
        for gy in 0..<(rows - 1) {
            for gx in 0..<(cols - 1) {
                let a = UInt32(gy * cols + gx)
                let b = UInt32(gy * cols + gx + 1)
                let c = UInt32((gy + 1) * cols + gx)
                let d = UInt32((gy + 1) * cols + gx + 1)
                indices.append(contentsOf: [a, b, c, b, d, c])
            }
        }

        var descriptor = MeshDescriptor(name: "DepthOcclusionProxy")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)

        return try? MeshResource.generate(from: [descriptor])
    }

    // Samples the raw depth grid (with layout knobs) and maps to metres.
    private static func sampleMetricDepth(
        frame: DepthFrame,
        dims: DepthMapDimensions,
        s: Float,
        t: Float,
        config: DepthOcclusionConfig
    ) -> Float {
        var su = s
        var sv = t
        if config.flipU { su = 1 - su }
        if config.flipV { sv = 1 - sv }

        let colT = config.swapUV ? sv : su
        let rowT = config.swapUV ? su : sv

        let col = Int((colT * Float(dims.cols - 1)).rounded())
        let row = Int((rowT * Float(dims.rows - 1)).rounded())
        let clampedCol = min(max(col, 0), dims.cols - 1)
        let clampedRow = min(max(row, 0), dims.rows - 1)

        var raw = DepthMapReader.sample(frame.map, row: clampedRow, col: clampedCol)
        if config.invertDepth, raw != 0 { raw = 1 / raw }

        let metric = config.rawScale * raw + config.rawBias
        return min(max(metric, config.minDepthMeters), config.maxDepthMeters)
    }
}
