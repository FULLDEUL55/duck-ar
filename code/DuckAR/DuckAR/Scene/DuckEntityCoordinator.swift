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

    private var planeAnchor: AnchorEntity?
    private var worldAnchor: AnchorEntity?
    private var duckEntity: Entity?
    private var updateSubscription: Cancellable?
    private var isPlaced = false

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
        }
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
                guard planeAnchor.isAnchored else { return }
                self.handoffToNavigator(
                    arView: arView,
                    planeAnchor: planeAnchor,
                    entity: entity,
                    behavior: behavior
                )
                self.updateSubscription?.cancel()
                self.updateSubscription = nil
            }
        }
    }

    private func handoffToNavigator(
        arView: ARView,
        planeAnchor: AnchorEntity,
        entity: Entity,
        behavior: DuckBehaviorCoordinator
    ) {
        let worldPos = entity.position(relativeTo: nil)

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

        planeAnchor.removeFromParent()
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
