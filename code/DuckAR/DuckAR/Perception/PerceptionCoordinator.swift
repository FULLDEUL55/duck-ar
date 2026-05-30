//
//  PerceptionCoordinator.swift
//  DuckAR
//
//  Perception infrastructure / inbound adapter. Owns the ARSession, runs the
//  YOLOv3 Tiny detector (Vision) and the Metric3D depth estimator, and
//  translates raw ARKit/Vision results into pure domain models
//  (PerceivedObject, DepthFrame — defined in their own files) published via
//  Combine. All ARKit/Vision/RealityKit types stay confined to this layer.
//

import ARKit
import Combine
import CoreML
import RealityKit
import Vision
import simd

final class PerceptionCoordinator: NSObject, ARSessionDelegate, PerceivedObjectSource {

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

    // Domain-model outbound ports (PerceivedObject / DepthFrame carry no
    // framework types). planeAnchorEvents intentionally keeps ARPlaneAnchor:
    // its only consumer (PlaneVisualizer) is itself RealityKit infrastructure,
    // so wrapping it in a domain type would be a value-free passthrough.
    nonisolated let perceivedObjects = PassthroughSubject<PerceivedObject, Never>()
    nonisolated let planeAnchorEvents = PassthroughSubject<PlaneAnchorEvent, Never>()
    nonisolated let depthFramePublisher = PassthroughSubject<DepthFrame, Never>()

    // PerceivedObjectSource port. Behavior depends on this protocol, never the
    // concrete coordinator, so the perception backend stays swappable.
    nonisolated var perceivedObjectsPublisher: AnyPublisher<PerceivedObject, Never> {
        perceivedObjects.eraseToAnyPublisher()
    }

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
    // Built once on `depthInferenceQueue`, then only read on the same serial queue.
    nonisolated(unsafe) private var depthEstimator: Metric3DDepthEstimator?

    // Latest depth result, written on `depthInferenceQueue`, read on main during
    // detection placement. Guarded by `depthLock`.
    nonisolated(unsafe) private var latestDepthFrame: DepthFrame?
    nonisolated private let depthLock = NSLock()

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
        do {
            let estimator = try Metric3DDepthEstimator()
            estimator.warmUp()
            depthEstimator = estimator
            debugLog?.log(.system, "✅ Metric3D ViT-Small (ONNX Runtime) loaded")
        } catch Metric3DDepthEstimator.EstimatorError.modelMissing {
            debugLog?.log(.system, "ℹ metric3d_vit_small_f32io.onnx not bundled — depth pipeline idle")
        } catch {
            debugLog?.log(.system, "⚠ Failed to load Metric3D: \(error)")
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

        let depthFrame = currentDepthFrame()

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

                // Placement priority: metric depth (monocular) > plane raycast > fixed fallback.
                // Depth gives a distance even where ARKit has found no plane (e.g. a chair
                // mid-room); we project it along the view ray for that screen point.
                let world: simd_float4x4
                if let depthFrame = depthFrame,
                   let meters = depthFrame.metricDepth(
                       atVisionNormalizedPoint: CGPoint(x: det.bbox.midX, y: det.bbox.midY)),
                   meters > 0.2, meters < 8.0,
                   let ray = arView.ray(through: screenPoint) {
                    // depth is perpendicular Z; convert to distance along the ray.
                    let dir = simd_normalize(ray.direction)
                    let forward = -simd_normalize(SIMD3<Float>(
                        cameraTransform.columns.2.x,
                        cameraTransform.columns.2.y,
                        cameraTransform.columns.2.z
                    ))
                    let cosTheta = simd_dot(dir, forward)
                    let t = cosTheta > 0.1 ? meters / cosTheta : meters
                    let p = ray.origin + dir * t
                    var m = matrix_identity_float4x4
                    m.columns.3 = SIMD4<Float>(p.x, p.y, p.z, 1)
                    world = m
                } else if let hit = arView.raycast(
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

    // MARK: - Depth pipeline (Metric3D ViT-Small via ONNX Runtime)

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
        guard let estimator = depthEstimator else { return }

        let fx = intrinsics.columns.0.x
        let output: Metric3DDepthEstimator.Output
        do {
            output = try estimator.estimate(pixelBuffer: pixelBuffer, intrinsicsFx: fx)
        } catch {
            debugLog?.log(.system, "⚠ depth inference failed: \(error)")
            return
        }

        guard let map = try? MLMultiArray(
            shape: [NSNumber(value: output.height), NSNumber(value: output.width)],
            dataType: .float32
        ) else { return }
        output.depth.withUnsafeBytes { src in
            memcpy(map.dataPointer, src.baseAddress!, output.depth.count * MemoryLayout<Float>.size)
        }

        let frame = DepthFrame(
            map: map,
            cameraIntrinsics: intrinsics,
            imageResolution: imageResolution,
            timestamp: timestamp,
            contentRect: output.contentRect
        )

        depthLock.lock()
        latestDepthFrame = frame
        depthLock.unlock()

        depthFramePublisher.send(frame)
    }

    nonisolated private func currentDepthFrame() -> DepthFrame? {
        depthLock.lock()
        defer { depthLock.unlock() }
        return latestDepthFrame
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
