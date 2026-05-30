//
//  DuckEntityCoordinator.swift
//  DuckAR
//
//  Phase 1: loads duck.usdz onto the first detected horizontal plane,
//  plays the embedded animation loop, applies a grounding shadow, and
//  hands off to DuckNavigator once anchored. The duck is then reparented
//  from the plane anchor to a free world anchor so its world Y stays
//  locked to the ground regardless of plane updates.
//
//  ARSession ownership lives in PerceptionCoordinator, so we anchor via
//  AnchorEntity(.plane(...)) rather than ARSessionDelegate callbacks.
//

import ARKit
import Combine
import RealityKit
import simd

@MainActor
final class DuckEntityCoordinator {

    private static let usdzName = "duck"
    private static let minimumPlaneBounds = SIMD2<Float>(0.3, 0.3)

    // If no qualifying horizontal plane anchors within this window, place the
    // duck ahead of the camera so it always appears (chairs/sofas/walls alone
    // never yield a floor plane on a LiDAR-less iPad).
    private static let planeWaitTimeout: TimeInterval = 2.5

    private var planeAnchor: AnchorEntity?
    private var worldAnchor: AnchorEntity?
    private var duckEntity: Entity?
    private var updateSubscription: Cancellable?
    private var isPlaced = false
    // Set once the duck is reparented to a world anchor and handed to the
    // navigator — guards the plane-ready path and the fallback from racing.
    private var hasHandedOff = false

    private let navigator = DuckNavigator()
    private let depthField = DepthNavigationField()

    weak var debugLog: DebugLogStore? {
        didSet {
            navigator.debugLog = debugLog
            depthField.debugLog = debugLog
        }
    }

    func attach(
        to arView: ARView,
        behavior: DuckBehaviorCoordinator,
        depthPublisher: AnyPublisher<DepthFrame, Never>
    ) {
        guard !isPlaced, planeAnchor == nil else { return }

        depthField.attach(arView: arView, depthPublisher: depthPublisher)

        let anchor = AnchorEntity(
            .plane(
                .horizontal,
                classification: .any,
                minimumBounds: Self.minimumPlaneBounds
            )
        )
        planeAnchor = anchor
        arView.scene.addAnchor(anchor)

        Task { @MainActor in
            await loadDuck(into: anchor, arView: arView, behavior: behavior)
            scheduleFallbackPlacement(arView: arView, behavior: behavior)
        }
    }

    // No qualifying horizontal plane after the timeout → place the duck in
    // front of the camera so it is always visible and the navigator always runs.
    private func scheduleFallbackPlacement(
        arView: ARView,
        behavior: DuckBehaviorCoordinator
    ) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.planeWaitTimeout * 1_000_000_000))
            guard !hasHandedOff, let entity = duckEntity else { return }
            let pos = fallbackWorldPosition(arView: arView)
            debugLog?.log(.system, String(
                format: "🦆 no plane in %.1fs — fallback placement @ (%.2f, %.2f, %.2f)",
                Self.planeWaitTimeout, pos.x, pos.y, pos.z
            ))
            reparentAndHandoff(arView: arView, planeAnchor: planeAnchor, worldPos: pos, entity: entity, behavior: behavior)
        }
    }

    // Screen-center raycast against an estimated plane (any alignment); falls
    // back to a point ~1.2 m ahead of the camera dropped below eye level.
    private func fallbackWorldPosition(arView: ARView) -> SIMD3<Float> {
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        if let query = arView.makeRaycastQuery(from: center, allowing: .estimatedPlane, alignment: .any),
           let hit = arView.session.raycast(query).first {
            let c = hit.worldTransform.columns.3
            return SIMD3<Float>(c.x, c.y, c.z)
        }
        let cam = arView.cameraTransform.matrix
        let forward = -SIMD3<Float>(cam.columns.2.x, cam.columns.2.y, cam.columns.2.z)
        let camPos = SIMD3<Float>(cam.columns.3.x, cam.columns.3.y, cam.columns.3.z)
        var p = camPos + normalize(forward) * 1.2
        p.y -= 0.4
        return p
    }

    private func loadDuck(
        into anchor: AnchorEntity,
        arView: ARView,
        behavior: DuckBehaviorCoordinator
    ) async {
        do {
            let entity = try await Entity(named: Self.usdzName, in: nil)
            anchor.addChild(entity)
            duckEntity = entity
            applyGroundingShadow(to: entity)
            playEmbeddedLoop(on: entity)
            observeAnchorReady(
                arView: arView,
                planeAnchor: anchor,
                entity: entity,
                behavior: behavior
            )
            isPlaced = true
        } catch {
            debugLog?.log(.system, "🦆 USDZ load failed: \(error)")
        }
    }

    // GroundingShadowComponent only attaches to entities with a ModelComponent;
    // a USDZ root often holds only a transform with child meshes, so walk down.
    private func applyGroundingShadow(to entity: Entity) {
        if entity.components[ModelComponent.self] != nil {
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        }
        for child in entity.children {
            applyGroundingShadow(to: child)
        }
    }

    private func playEmbeddedLoop(on entity: Entity) {
        guard let animation = entity.availableAnimations.first else { return }
        entity.playAnimation(animation.repeat(), transitionDuration: 0.2)
    }

    // AnchorEntity(.plane) anchors asynchronously; on the first frame where
    // the plane anchor is live, snapshot the duck's world transform, reparent
    // it under a free world anchor, drop the plane anchor, and hand off to
    // the navigator. Then cancel the subscription.
    private func observeAnchorReady(
        arView: ARView,
        planeAnchor: AnchorEntity,
        entity: Entity,
        behavior: DuckBehaviorCoordinator
    ) {
        updateSubscription = arView.scene.subscribe(
            to: SceneEvents.Update.self
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self.hasHandedOff, planeAnchor.isAnchored else { return }
                let worldPos = entity.position(relativeTo: nil)
                self.debugLog?.log(.system, String(
                    format: "🦆 placed on plane @ (%.2f, %.2f, %.2f)",
                    worldPos.x, worldPos.y, worldPos.z
                ))
                self.reparentAndHandoff(
                    arView: arView,
                    planeAnchor: planeAnchor,
                    worldPos: worldPos,
                    entity: entity,
                    behavior: behavior
                )
                self.updateSubscription?.cancel()
                self.updateSubscription = nil
            }
        }
    }

    private func reparentAndHandoff(
        arView: ARView,
        planeAnchor: AnchorEntity?,
        worldPos: SIMD3<Float>,
        entity: Entity,
        behavior: DuckBehaviorCoordinator
    ) {
        guard !hasHandedOff else { return }
        hasHandedOff = true
        updateSubscription?.cancel()
        updateSubscription = nil

        // Initial yaw faces the camera so the duck doesn't spawn looking away.
        // Match navigator's mesh-forward correction so the body & nav agree.
        let cameraWorld = arView.cameraTransform.matrix.columns.3
        let dx = cameraWorld.x - worldPos.x
        let dz = cameraWorld.z - worldPos.z
        let yaw = atan2(dx, dz) + navigator.config.forwardAxisOffset

        entity.removeFromParent()
        let worldAnchor = AnchorEntity()
        worldAnchor.position = worldPos
        worldAnchor.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        arView.scene.addAnchor(worldAnchor)
        worldAnchor.addChild(entity)
        // Inside the world anchor the duck sits at local origin.
        entity.position = SIMD3<Float>(0, 0, 0)
        entity.orientation = simd_quatf()

        planeAnchor?.removeFromParent()
        self.planeAnchor = nil
        self.worldAnchor = worldAnchor

        navigator.attach(
            anchor: worldAnchor,
            arView: arView,
            groundY: worldPos.y,
            scene: arView.scene,
            targetPublisher: behavior.targetPositionPublisher,
            depthField: depthField
        )
    }
}
