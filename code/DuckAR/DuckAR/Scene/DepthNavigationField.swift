//
//  DepthNavigationField.swift
//  DuckAR
//
//  Task #4 phase 2: turns arkit-perception's monocular metric depth into a
//  walkability query for the navigator. Plane raycast only reports floor where
//  ARKit found a plane; metric depth lets the duck reason about the gaps
//  between and behind furniture, while refusing to walk *into* a raised
//  surface (collision avoidance, complementing the #3 occlusion proxy).
//
//  Fail-open by design: when no DepthFrame has arrived (depth model not bundled,
//  or a cold frame), every query returns "fully walkable" so navigation falls
//  back to the existing plane-based behavior with no regression.
//

import ARKit
import Combine
import Foundation
import RealityKit
import simd

@MainActor
final class DepthNavigationField {

    struct Config {
        // A reconstructed surface within ±floorTolerance of groundY counts as
        // floor (walkable). Absorbs monocular depth noise around ground level.
        var floorTolerance: Float = 0.10
        // A visible surface this far above the floor, sitting in front of the
        // sampled ground point, is treated as an obstacle to stop short of.
        var obstacleHeight: Float = 0.12
        // Ignore depth outside this metric band (model is unreliable very near
        // and saturates far away).
        var minDepth: Float = 0.2
        var maxDepth: Float = 8.0
        // Path is probed every sampleSpacing meters, capped at maxSamples so a
        // far target can't blow the per-frame budget.
        var sampleSpacing: Float = 0.09
        var maxSamples: Int = 45
        // Stop this far before the first obstacle so the duck halts in front of
        // furniture rather than clipping its bounding surface.
        var stopMargin: Float = 0.10
    }

    var config = Config()
    weak var debugLog: DebugLogStore?

    private weak var arView: ARView?
    private var latest: DepthFrame?
    private var subscription: AnyCancellable?

    var hasDepth: Bool { latest != nil }

    func attach(arView: ARView, depthPublisher: AnyPublisher<DepthFrame, Never>) {
        self.arView = arView
        subscription = depthPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                self?.latest = frame
            }
    }

    func detach() {
        subscription?.cancel()
        subscription = nil
        latest = nil
    }

    /// Distance (meters, horizontal) the duck may advance from `from` toward
    /// `to` before a raised surface blocks the path. Returns the full segment
    /// length when the path is clear, depth is unavailable, or the geometry is
    /// degenerate (fail-open).
    func walkableDistance(from: SIMD3<Float>, to: SIMD3<Float>, groundY: Float) -> Float {
        let origin = SIMD3<Float>(from.x, groundY, from.z)
        let goal = SIMD3<Float>(to.x, groundY, to.z)
        let full = simd_distance(origin, goal)
        guard full > 1e-4 else { return full }
        guard let frame = latest, let arView else { return full }

        let dir = (goal - origin) / full
        let camForward = Self.cameraForward(arView: arView)

        var travelled = config.sampleSpacing
        var sampleCount = 0
        while travelled <= full, sampleCount < config.maxSamples {
            let probe = origin + dir * travelled
            if let clearance = surfaceClearance(
                at: probe,
                frame: frame,
                arView: arView,
                camForward: camForward,
                groundY: groundY
            ), clearance > config.obstacleHeight {
                let stop = max(0, travelled - config.stopMargin)
                debugLog?.log(
                    .nav,
                    String(format: "🦆 depth obstacle @ %.2fm (clr=%.2f) → stop %.2fm",
                           travelled, clearance, stop)
                )
                return stop
            }
            travelled += config.sampleSpacing
            sampleCount += 1
        }
        return full
    }

    /// Height of the nearest camera-visible surface above the floor, along the
    /// view ray that passes through ground point `g`. nil when no usable depth
    /// sample exists there. A surface farther than `g` (depth saw past the floor
    /// point) reports 0 — open floor.
    private func surfaceClearance(
        at g: SIMD3<Float>,
        frame: DepthFrame,
        arView: ARView,
        camForward: SIMD3<Float>,
        groundY: Float
    ) -> Float? {
        guard let screen = arView.project(g) else { return nil }
        let size = arView.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }

        // View coords (origin top-left) -> Vision-normalized (origin lower-left),
        // matching PerceptionCoordinator's depth-lookup convention.
        let vn = CGPoint(x: screen.x / size.width, y: 1.0 - (screen.y / size.height))
        guard (0...1).contains(vn.x), (0...1).contains(vn.y) else { return nil }
        guard let meters = frame.metricDepth(atVisionNormalizedPoint: vn),
              meters > config.minDepth, meters < config.maxDepth,
              let ray = arView.ray(through: screen) else { return nil }

        // Metric depth is perpendicular Z; convert to distance along the ray.
        let rayDir = simd_normalize(ray.direction)
        let cosTheta = simd_dot(rayDir, camForward)
        let t = cosTheta > 0.1 ? meters / cosTheta : meters
        let surface = ray.origin + rayDir * t

        // If the surface is beyond the ground point, the floor at g is open.
        let distToGround = simd_distance(ray.origin, g)
        if t > distToGround + config.floorTolerance { return 0 }

        return surface.y - groundY
    }

    // ARKit camera looks down its local -Z; world-space forward negates column 2.
    private static func cameraForward(arView: ARView) -> SIMD3<Float> {
        let c = arView.cameraTransform.matrix.columns.2
        return simd_normalize(SIMD3<Float>(-c.x, -c.y, -c.z))
    }
}
