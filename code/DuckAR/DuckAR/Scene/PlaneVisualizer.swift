//
//  PlaneVisualizer.swift
//  DuckAR
//
//  Translucent overlay for detected ARPlaneAnchors. Replaces ARView's
//  built-in `.showAnchorGeometry`, which renders opaque and obscures the
//  camera feed. Subscribes to PerceptionCoordinator.planeAnchorEvents
//  so the ARSession delegate stays single-owner.
//

import ARKit
import Combine
import RealityKit
import UIKit

@MainActor
final class PlaneVisualizer {

    private static let horizontalColor = UIColor.systemBlue.withAlphaComponent(0.2)
    private static let verticalColor = UIColor.systemGreen.withAlphaComponent(0.2)

    weak var debugLog: DebugLogStore?

    private weak var arView: ARView?
    private var anchors: [UUID: AnchorEntity] = [:]
    private var subscription: AnyCancellable?

    func attach<P: Publisher>(to arView: ARView, planeEvents: P)
        where P.Output == PerceptionCoordinator.PlaneAnchorEvent, P.Failure == Never {
        self.arView = arView
        subscription = planeEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    self?.handle(event)
                }
            }
    }

    func detach() {
        subscription?.cancel()
        subscription = nil
        for anchor in anchors.values {
            anchor.removeFromParent()
        }
        anchors.removeAll()
    }

    private func handle(_ event: PerceptionCoordinator.PlaneAnchorEvent) {
        switch event {
        case .added(let plane):
            let axis = (plane.alignment == .horizontal) ? "h" : "v"
            let ext = plane.planeExtent
            debugLog?.log(.perception,
                          String(format: "📐 plane add %@ %@ %.2f×%.2f",
                                 plane.identifier.uuidString.prefix(8) as CVarArg,
                                 axis,
                                 ext.width,
                                 ext.height))
            addOrReplace(plane)
        case .updated(let plane):
            addOrReplace(plane)
        case .removed(let plane):
            anchors[plane.identifier]?.removeFromParent()
            anchors.removeValue(forKey: plane.identifier)
        }
    }

    private func addOrReplace(_ plane: ARPlaneAnchor) {
        guard let arView else { return }
        let entity = anchors[plane.identifier] ?? {
            let new = AnchorEntity(anchor: plane)
            arView.scene.addAnchor(new)
            anchors[plane.identifier] = new
            return new
        }()
        for child in entity.children {
            child.removeFromParent()
        }
        entity.addChild(makeMesh(for: plane))
    }

    private func makeMesh(for plane: ARPlaneAnchor) -> ModelEntity {
        let extent = plane.planeExtent
        let mesh = MeshResource.generatePlane(width: extent.width, depth: extent.height)
        let color: UIColor = (plane.alignment == .horizontal)
            ? Self.horizontalColor
            : Self.verticalColor
        let material = UnlitMaterial(color: color)
        let model = ModelEntity(mesh: mesh, materials: [material])
        // ARPlaneAnchor.center is the plane center offset within its anchor frame.
        model.position = SIMD3<Float>(plane.center.x, 0, plane.center.z)
        return model
    }
}
