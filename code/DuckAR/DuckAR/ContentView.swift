//
//  ContentView.swift
//  DuckAR
//
//  Phase 1 sanity check: ARKit world tracking + plane detection.
//  ARSession ownership lives in PerceptionCoordinator; this view only renders.
//

import SwiftUI
import RealityKit
import ARKit
import Combine

struct ContentView: View {
    @StateObject private var debugLog = DebugLogStore()
    @StateObject private var overlayStore = PerceptionOverlayStore()

    @State private var perception = PerceptionCoordinator()
    @State private var behavior = DuckBehaviorCoordinator()
    @State private var duckEntity = DuckEntityCoordinator()
    @State private var planeVisualizer = PlaneVisualizer()
    @State private var depthOcclusion = DepthOcclusionCoordinator()
    @State private var adapter: PerceptionToBehaviorAdapter?
    @State private var stateLog: AnyCancellable?
    @State private var overlayBridge: AnyCancellable?

    var body: some View {
        ZStack {
            ARViewContainer(
                perception: perception,
                duckEntity: duckEntity,
                behavior: behavior,
                planeVisualizer: planeVisualizer,
                depthOcclusion: depthOcclusion
            )
                .ignoresSafeArea()
            DetectionOverlay(store: overlayStore)
                .ignoresSafeArea()
            DebugConsoleOverlay(store: debugLog, modelName: PerceptionCoordinator.modelName)
        }
        .onAppear {
            perception.debugLog = debugLog
            planeVisualizer.debugLog = debugLog
            duckEntity.debugLog = debugLog
            depthOcclusion.debugLog = debugLog

            let newAdapter = PerceptionToBehaviorAdapter(behavior: behavior)
            newAdapter.debugLog = debugLog
            // Wire behavior to perception through the PerceivedObjectSource port.
            newAdapter.attach(to: perception as PerceivedObjectSource)
            behavior.start()

            stateLog = behavior.currentStatePublisher.sink { [debugLog] state in
                debugLog.log(.behavior, "state → \(state.rawValue)")
            }

            overlayBridge = perception.perceivedObjectsPublisher
                .receive(on: DispatchQueue.main)
                .sink { [overlayStore] object in
                    overlayStore.ingest(object)
                }

            adapter = newAdapter
        }
        .onDisappear {
            adapter?.detach()
            adapter = nil
            stateLog?.cancel()
            stateLog = nil
            overlayBridge?.cancel()
            overlayBridge = nil
            behavior.stop()
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    let perception: PerceptionCoordinator
    let duckEntity: DuckEntityCoordinator
    let behavior: DuckBehaviorCoordinator
    let planeVisualizer: PlaneVisualizer
    let depthOcclusion: DepthOcclusionCoordinator

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        perception.attach(to: arView)

        // Built-in .showAnchorGeometry renders opaque and hides the camera feed —
        // PlaneVisualizer draws translucent meshes instead. World origin stays
        // for orientation reference.
        arView.debugOptions = [.showWorldOrigin]
        arView.environment.lighting.intensityExponent = 1.0

        planeVisualizer.attach(to: arView, planeEvents: perception.planeAnchorEvents)
        duckEntity.attach(
            to: arView,
            behavior: behavior,
            depthPublisher: perception.depthFramePublisher.eraseToAnyPublisher()
        )
        depthOcclusion.attach(
            to: arView,
            depthPublisher: perception.depthFramePublisher.eraseToAnyPublisher()
        )

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

#Preview {
    ContentView()
}
