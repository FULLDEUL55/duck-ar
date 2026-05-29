//
//  DepthOcclusionCoordinator.swift
//  DuckAR
//
//  Phase 2 (Task #3): subscribes to PerceptionCoordinator.depthFramePublisher
//  and maintains a camera-anchored OcclusionMaterial proxy mesh so the duck is
//  hidden behind real furniture. The proxy is regenerated at a throttled
//  cadence to protect the iPad Air 5 (M1, no LiDAR) frame budget.
//
//  Why camera-anchored: the unprojected vertices are in camera-local space, so
//  parenting under AnchorEntity(.camera) needs no per-frame world transform and
//  the proxy naturally tracks the view. OcclusionMaterial writes depth but not
//  colour — world-space duck fragments behind it are culled.
//
//  STATUS: skeleton. The depth pipeline in PerceptionCoordinator is still a
//  no-op (Stage 2), so this stays idle until DepthFrames actually publish. The
//  format/orientation/scale knobs in DepthOcclusionConfig are placeholders
//  pending arkit-perception confirmation.
//

import ARKit
import Combine
import Foundation
import QuartzCore
import RealityKit
import UIKit
import simd

@MainActor
final class DepthOcclusionCoordinator {

    var config = DepthOcclusionConfig()

    // Debug: render the proxy as a translucent surface instead of an invisible
    // occluder, to eyeball depth alignment while tuning the layout knobs.
    var debugVisualize = false

    weak var debugLog: DebugLogStore?

    private weak var cameraAnchor: AnchorEntity?
    private var proxyEntity: ModelEntity?
    private var subscription: AnyCancellable?

    private var isEnabled = true
    private var lastBuildTime: TimeInterval = 0
    // Cap proxy rebuilds at ~10 Hz regardless of depth publish rate.
    private let minBuildInterval: TimeInterval = 0.1

    func attach(to arView: ARView, depthPublisher: AnyPublisher<DepthFrame, Never>) {
        let anchor = AnchorEntity(.camera)
        arView.scene.addAnchor(anchor)
        cameraAnchor = anchor

        let proxy = ModelEntity()
        anchor.addChild(proxy)
        proxyEntity = proxy

        subscription = depthPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                self?.ingest(frame)
            }

        debugLog?.log(.system, "🧱 occlusion proxy attached (idle until depth frames)")
    }

    func detach() {
        subscription?.cancel()
        subscription = nil
        proxyEntity?.removeFromParent()
        proxyEntity = nil
        cameraAnchor?.removeFromParent()
        cameraAnchor = nil
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { proxyEntity?.model = nil }
    }

    // Ground-plane scale calibration. Once a stable raycast hit gives a known
    // metric distance d_world for a pixel whose raw depth is d_raw, set:
    //   rawScale = d_world / d_raw,  rawBias = 0  (invertDepth handled first).
    // TODO(Task #20 PoC): drive this from arkit-perception's raycast + depth
    // sample pairing rather than a manual call.
    func calibrate(rawScale: Float, rawBias: Float = 0) {
        config.rawScale = rawScale
        config.rawBias = rawBias
        debugLog?.log(
            .system,
            String(format: "🧱 occlusion calibrated scale=%.4f bias=%.4f", rawScale, rawBias)
        )
    }

    private func ingest(_ frame: DepthFrame) {
        guard isEnabled, let proxy = proxyEntity else { return }

        let now = CACurrentMediaTime()
        guard now - lastBuildTime >= minBuildInterval else { return }
        lastBuildTime = now

        // TODO(perf): unprojection + MeshResource.generate currently run on the
        // main actor at ≤10 Hz on a coarse grid. If profiling on device shows a
        // hitch, move vertex compute to a background queue and hop back to main
        // only to assign the ModelComponent.
        guard let mesh = DepthOcclusionMeshBuilder.makeMesh(from: frame, config: config) else {
            return
        }

        let material: RealityKit.Material
        if debugVisualize {
            var unlit = UnlitMaterial(color: UIColor(red: 0, green: 1, blue: 1, alpha: 0.25))
            unlit.blending = .transparent(opacity: 0.25)
            material = unlit
        } else {
            material = OcclusionMaterial()
        }

        proxy.model = ModelComponent(mesh: mesh, materials: [material])
    }
}
