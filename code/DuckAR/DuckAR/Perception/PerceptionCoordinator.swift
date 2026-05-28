//
//  PerceptionCoordinator.swift
//  DuckAR
//
//  ARSession owner. Configures world tracking, owns a reusable
//  VNCoreMLRequest for Apple's YOLOv3 Tiny detector, and publishes
//  located objects via Combine.
//

import ARKit
import Combine
import CoreML
import RealityKit
import Vision
import simd

struct PerceivedObject: Sendable, Equatable {
    let type: String
    let worldTransform: simd_float4x4
    let confidence: Float
    let timestamp: TimeInterval
    // Vision-native: normalized [0,1]², origin lower-left, portrait-upright
    // (matches the orientation we feed VNImageRequestHandler).
    let normalizedBoundingBox: CGRect

    // Convert the Vision bbox into UIKit view coordinates (origin upper-left).
    // Phase 1 sanity mapping: linear scale, no camera-image aspect-crop correction.
    func screenRect(in viewSize: CGSize) -> CGRect {
        CGRect(
            x: normalizedBoundingBox.minX * viewSize.width,
            y: (1.0 - normalizedBoundingBox.maxY) * viewSize.height,
            width: normalizedBoundingBox.width * viewSize.width,
            height: normalizedBoundingBox.height * viewSize.height
        )
    }
}

// Output of Metric3D Small (or equivalent monocular depth model).
// `map` shape/scale TBD by ar-researcher's conversion report; consumers
// must interpret in concert with the model's documented output spec.
// @unchecked Sendable: MLMultiArray is reference-typed and not Sendable —
// the value is published once and treated as read-only by subscribers.
struct DepthFrame: @unchecked Sendable {
    let map: MLMultiArray
    let cameraIntrinsics: simd_float3x3
    let imageResolution: CGSize
    let timestamp: TimeInterval
}

final class PerceptionCoordinator: NSObject, ARSessionDelegate {

    static let modelName: String = "YOLOv3-Tiny (Apple, COCO 80)"
    static let depthModelName: String = "Metric3D Small"

    private static let inferenceFrameStride: Int = 3
    private static let depthFrameStride: Int = 5
    private static let confidenceThreshold: Float = 0.3
    private static let placementDistanceMeters: Float = 1.0
    // COCO labels we surface to duck-behavior. Apple's YOLOv3 Tiny emits
    // lowercase identifiers with underscore-joined multi-word labels.
    private static let furnitureKeepList: Set<String> = [
        "chair", "couch", "sofa", "bed",
        "dining table", "diningtable",
        "tv", "tvmonitor",
        "refrigerator", "oven", "sink",
    ]

    nonisolated let perceivedObjects = PassthroughSubject<PerceivedObject, Never>()
    nonisolated let planeAnchorEvents = PassthroughSubject<PlaneAnchorEvent, Never>()
    nonisolated let depthFramePublisher = PassthroughSubject<DepthFrame, Never>()

    enum PlaneAnchorEvent {
        case added(ARPlaneAnchor)
        case updated(ARPlaneAnchor)
        case removed(ARPlaneAnchor)
    }

    nonisolated(unsafe) weak var debugLog: DebugLogStore?

    private weak var arView: ARView?
    private var frameCounter: Int = 0
    private var isInferring: Bool = false
    private var isInferringDepth: Bool = false

    nonisolated private let inferenceQueue = DispatchQueue(
        label: "com.fulldeul.DuckAR.perception.inference",
        qos: .userInitiated
    )
    nonisolated private let depthInferenceQueue = DispatchQueue(
        label: "com.fulldeul.DuckAR.perception.depth",
        qos: .userInitiated
    )
    // Built once on `inferenceQueue`, then only ever read on the same serial queue.
    nonisolated(unsafe) private var detectionRequest: VNCoreMLRequest?
    // Same lifecycle pattern as `detectionRequest`, but bound to `depthInferenceQueue`.
    // Stays nil until Metric3DSmall.mlmodelc lands in the bundle (Stage 2).
    nonisolated(unsafe) private var depthRequest: VNCoreMLRequest?

    func attach(to arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
        arView.session.run(Self.makeConfiguration(), options: [])
        inferenceQueue.async { [weak self] in
            self?.loadDetector()
        }
        depthInferenceQueue.async { [weak self] in
            self?.loadDepthEstimator()
        }
    }

    private static func makeConfiguration() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        // iPad Air 5 has no LiDAR — sceneReconstruction is intentionally omitted.
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        }
        return config
    }

    nonisolated private func loadDetector() {
        guard let url = Bundle.main.url(forResource: "YOLOv3Tiny", withExtension: "mlmodelc") else {
            debugLog?.log(.system, "⚠ YOLOv3Tiny.mlmodelc not bundled")
            return
        }
        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all
            let mlModel = try MLModel(contentsOf: url, configuration: cfg)
            let visionModel = try VNCoreMLModel(for: mlModel)
            let request = VNCoreMLRequest(model: visionModel)
            request.imageCropAndScaleOption = .scaleFill
            detectionRequest = request
            debugLog?.log(.system, "✅ YOLOv3Tiny loaded")
        } catch {
            debugLog?.log(.system, "⚠ Failed to load YOLOv3Tiny: \(error)")
        }
    }

    nonisolated private func loadDepthEstimator() {
        guard let url = Bundle.main.url(forResource: "Metric3DSmall", withExtension: "mlmodelc") else {
            debugLog?.log(.system, "ℹ Metric3DSmall.mlmodelc not bundled — depth pipeline idle")
            return
        }
        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all
            let mlModel = try MLModel(contentsOf: url, configuration: cfg)
            let visionModel = try VNCoreMLModel(for: mlModel)
            let request = VNCoreMLRequest(model: visionModel)
            request.imageCropAndScaleOption = .scaleFill
            depthRequest = request
            debugLog?.log(.system, "✅ Metric3D Small loaded")
        } catch {
            debugLog?.log(.system, "⚠ Failed to load Metric3D Small: \(error)")
        }
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCounter &+= 1
        guard let arView = arView else { return }

        // YOLOv3 Tiny detector — independent stride / in-flight guard.
        if frameCounter % Self.inferenceFrameStride == 0, !isInferring {
            isInferring = true
            let pixelBuffer = frame.capturedImage
            let cameraTransform = frame.camera.transform
            let timestamp = frame.timestamp
            let viewSize = arView.bounds.size

            inferenceQueue.async { [weak self] in
                self?.runDetection(
                    pixelBuffer: pixelBuffer,
                    cameraTransform: cameraTransform,
                    timestamp: timestamp,
                    viewSize: viewSize
                )
            }
        }

        // Metric3D depth estimator — independent stride / in-flight guard.
        // Runs as a no-op until the model lands in the bundle (Stage 2).
        if frameCounter % Self.depthFrameStride == 0, !isInferringDepth {
            isInferringDepth = true
            let depthPixelBuffer = frame.capturedImage
            let intrinsics = frame.camera.intrinsics
            let imageResolution = frame.camera.imageResolution
            let timestamp = frame.timestamp

            depthInferenceQueue.async { [weak self] in
                self?.runDepthEstimation(
                    pixelBuffer: depthPixelBuffer,
                    intrinsics: intrinsics,
                    imageResolution: imageResolution,
                    timestamp: timestamp
                )
            }
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let plane = anchor as? ARPlaneAnchor else { continue }
            planeAnchorEvents.send(.added(plane))
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let plane = anchor as? ARPlaneAnchor else { continue }
            planeAnchorEvents.send(.updated(plane))
        }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let plane = anchor as? ARPlaneAnchor else { continue }
            planeAnchorEvents.send(.removed(plane))
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {}
    func sessionWasInterrupted(_ session: ARSession) {}
    func sessionInterruptionEnded(_ session: ARSession) {
        session.run(Self.makeConfiguration(), options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: - Vision pipeline

    nonisolated private func runDetection(
        pixelBuffer: CVPixelBuffer,
        cameraTransform: simd_float4x4,
        timestamp: TimeInterval,
        viewSize: CGSize
    ) {
        defer {
            DispatchQueue.main.async { [weak self] in
                self?.isInferring = false
            }
        }
        guard let request = detectionRequest else { return }

        // iPad portrait: ARFrame pixel buffer is sensor-native landscape-right.
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .right,
            options: [:]
        )
        do {
            try handler.perform([request])
        } catch {
            return
        }
        guard let observations = request.results as? [VNRecognizedObjectObservation] else { return }

        var detections: [(label: String, confidence: Float, bbox: CGRect)] = []
        for obs in observations {
            guard let top = obs.labels.first else { continue }
            let identifier = top.identifier.lowercased()
            guard Self.furnitureKeepList.contains(identifier) else { continue }
            guard top.confidence >= Self.confidenceThreshold else { continue }
            detections.append((identifier, top.confidence, obs.boundingBox))
        }

        guard !detections.isEmpty else { return }

        let placementFallback = Self.placementTransform(
            camera: cameraTransform,
            distance: Self.placementDistanceMeters
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let arView = self.arView else { return }
            for det in detections {
                // Vision bbox: normalized, origin lower-left, portrait-upright (we passed .right).
                // ARView: UIKit coords, origin upper-left. Skip crop correction for Phase 1.
                let normalized = CGPoint(x: det.bbox.midX, y: 1.0 - det.bbox.midY)
                let screenPoint = CGPoint(
                    x: normalized.x * viewSize.width,
                    y: normalized.y * viewSize.height
                )

                let world: simd_float4x4
                if let hit = arView.raycast(
                    from: screenPoint,
                    allowing: .estimatedPlane,
                    alignment: .any
                ).first {
                    world = hit.worldTransform
                } else {
                    world = placementFallback
                }

                let object = PerceivedObject(
                    type: det.label,
                    worldTransform: world,
                    confidence: det.confidence,
                    timestamp: timestamp,
                    normalizedBoundingBox: det.bbox
                )
                let t = world.columns.3
                self.debugLog?.log(
                    .perception,
                    String(format: "👁 %@ %.2f @ (%.2f, %.2f, %.2f)",
                           det.label, det.confidence, t.x, t.y, t.z)
                )
                self.perceivedObjects.send(object)
            }
        }
    }

    // MARK: - Depth pipeline (Stage 1 scaffolding; Stage 2 fills in inference)

    nonisolated private func runDepthEstimation(
        pixelBuffer: CVPixelBuffer,
        intrinsics: simd_float3x3,
        imageResolution: CGSize,
        timestamp: TimeInterval
    ) {
        defer {
            DispatchQueue.main.async { [weak self] in
                self?.isInferringDepth = false
            }
        }
        guard depthRequest != nil else { return }
        // Stage 2 (ar-researcher .mlpackage 도착 후) 채울 내용:
        //   1. VNImageRequestHandler(cvPixelBuffer: ..., orientation: .right).perform([request])
        //   2. results 에서 depth MLMultiArray 추출 (모델 출력 키는 변환 보고서 따라)
        //   3. DepthFrame(map:, cameraIntrinsics: intrinsics, imageResolution:, timestamp:) publish
        //   4. (옵션) latestDepthFrame 캐시 후 runDetection 측에서 bbox 중심 → metric depth 조회
        _ = (pixelBuffer, intrinsics, imageResolution, timestamp)
    }

    nonisolated private static func placementTransform(
        camera: simd_float4x4,
        distance: Float
    ) -> simd_float4x4 {
        // Camera looks down its local -Z; offset `distance` meters ahead in camera space.
        var forward = matrix_identity_float4x4
        forward.columns.3.z = -distance
        return camera * forward
    }
}
