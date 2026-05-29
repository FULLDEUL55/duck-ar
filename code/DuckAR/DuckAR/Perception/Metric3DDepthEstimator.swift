//
//  Metric3DDepthEstimator.swift
//  DuckAR
//
//  Monocular metric depth via Metric3D ViT-Small, run through ONNX Runtime.
//
//  WHY ONNX Runtime instead of Core ML: Metric3D's ViT attention emits a
//  rank-7 reshape that Core ML's ML Program rejects (rank <= 5 limit), so the
//  model can't be converted to a .mlpackage. ORT runs the ONNX graph directly.
//
//  WHY the *_f32io.onnx variant: the onnxruntime-objc wrapper's
//  ORTTensorElementDataType enum has no Float16 case, so we cannot build an
//  fp16 input/output ORTValue. We wrap the fp16 model with Cast nodes at the
//  input/output (internals stay fp16, weights unchanged) so the bridge can use
//  plain Float32 tensors. See docs/research/onnxruntime-ios-integration.md.
//

import Accelerate
import CoreImage
import CoreML
import CoreVideo
import Foundation
import simd
import OnnxRuntimeBindings

/// Runs Metric3D ViT-Small on `ARFrame.capturedImage` and returns a metric
/// depth map (meters). All inference is serialized by the caller; the session
/// itself is thread-safe.
final class Metric3DDepthEstimator {

    enum EstimatorError: Error {
        case modelMissing
        case sessionFailed(String)
        case preprocessFailed
        case outputUnexpected
    }

    /// Result of one inference. Depth is row-major, `height * width` Float32 in
    /// meters. `contentRect` marks the non-padded image region inside the map
    /// (normalized, origin top-left) so callers can map a detection bbox center
    /// back into the letterboxed depth grid.
    struct Output {
        let depth: [Float]
        let width: Int
        let height: Int
        let contentRect: CGRect
    }

    // Canonical square input (14 * 37). Keeps the DINOv2 patch/attention layout
    // deterministic and matches Metric3D's training canonical.
    private static let inputDim: Int = 518
    // Focal length the model predicts against (canonical pinhole).
    private static let canonicalFocal: Float = 1000.0

    private static let inputName = "pixel_values_f32"
    private static let outputName = "predicted_depth_f32"

    private let env: ORTEnv
    private let session: ORTSession
    private let ciContext: CIContext

    // Reused 518x518 BGRA scratch buffer for preprocessing (single in-flight).
    private var scratchBuffer: CVPixelBuffer?

    init() throws {
        guard let url = Bundle.main.url(
            forResource: "metric3d_vit_small_f32io",
            withExtension: "onnx"
        ) else {
            throw EstimatorError.modelMissing
        }
        do {
            env = try ORTEnv(loggingLevel: .warning)
            let opts = try ORTSessionOptions()
            // Keep the AR main loop responsive: bounded intra-op parallelism,
            // no inter-op parallelism (single graph, sequential).
            try opts.setIntraOpNumThreads(2)
            try opts.setGraphOptimizationLevel(.all)
            session = try ORTSession(env: env, modelPath: url.path, sessionOptions: opts)
        } catch {
            throw EstimatorError.sessionFailed(String(describing: error))
        }
        ciContext = CIContext(options: [.cacheIntermediates: false])
    }

    /// Warm up the graph once (first run is 100-200 ms slower). Call off the
    /// AR loop. Ignores failures — warm-up is best-effort.
    func warmUp() {
        let count = 3 * Self.inputDim * Self.inputDim
        let zeros = [Float](repeating: 0, count: count)
        _ = try? run(rgbCHW: zeros)
    }

    /// Estimate metric depth for one captured frame.
    /// - parameters:
    ///   - pixelBuffer: `ARFrame.capturedImage` (YUV420, sensor-native landscape).
    ///   - intrinsicsFx: `ARCamera.intrinsics[0][0]` (focal length in pixels) of
    ///     the full captured image. Square-pixel / fx≈fy assumed for canonical scaling.
    func estimate(pixelBuffer: CVPixelBuffer, intrinsicsFx: Float) throws -> Output {
        let (rgb, contentRect, scale) = try preprocess(pixelBuffer: pixelBuffer)
        let (depthCanonical, h, w) = try run(rgbCHW: rgb)

        // Canonical(focal=1000) -> actual meters. The model input is the
        // letterboxed 518px image; focal in that frame = fx * uniformScale.
        let fxModel = intrinsicsFx * scale
        let metricScale = fxModel / Self.canonicalFocal
        var depth = depthCanonical
        if metricScale.isFinite, metricScale > 0 {
            var s = metricScale
            vDSP_vsmul(depth, 1, &s, &depth, 1, vDSP_Length(depth.count))
        }
        return Output(depth: depth, width: w, height: h, contentRect: contentRect)
    }

    // MARK: - Inference

    /// Runs the session on a CHW Float32 [0,255] buffer, returns (depth, H', W').
    private func run(rgbCHW: [Float]) throws -> ([Float], Int, Int) {
        let shape: [NSNumber] = [1, 3, NSNumber(value: Self.inputDim), NSNumber(value: Self.inputDim)]
        let data = rgbCHW.withUnsafeBufferPointer { Data(buffer: $0) }
        let mutable = NSMutableData(data: data)
        let input = try ORTValue(
            tensorData: mutable,
            elementType: .float,
            shape: shape
        )
        let outputs = try session.run(
            withInputs: [Self.inputName: input],
            outputNames: [Self.outputName],
            runOptions: nil
        )
        guard let depthValue = outputs[Self.outputName] else {
            throw EstimatorError.outputUnexpected
        }
        let info = try depthValue.tensorTypeAndShapeInfo()
        let dims = info.shape.map { $0.intValue }
        // [1, H', W']
        guard dims.count == 3, dims[0] == 1 else { throw EstimatorError.outputUnexpected }
        let h = dims[1], w = dims[2]
        let raw = try depthValue.tensorData() as Data
        let count = h * w
        guard raw.count >= count * MemoryLayout<Float>.size else {
            throw EstimatorError.outputUnexpected
        }
        var depth = [Float](repeating: 0, count: count)
        _ = depth.withUnsafeMutableBytes { dst in
            raw.copyBytes(to: dst, count: count * MemoryLayout<Float>.size)
        }
        return (depth, h, w)
    }

    // MARK: - Preprocess

    /// Sensor-native YUV420 -> upright RGB, letterboxed into 518x518, CHW Float32 [0,255].
    /// Returns (chw, contentRect, uniformScale) where uniformScale maps the upright
    /// image into the model input (for focal-length scaling).
    private func preprocess(
        pixelBuffer: CVPixelBuffer
    ) throws -> ([Float], CGRect, Float) {
        // Rotate sensor-native landscape to portrait-upright so depth-map indexing
        // matches the detection bbox frame (Vision uses .right orientation too).
        let ci = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let orientedW = ci.extent.width
        let orientedH = ci.extent.height
        guard orientedW > 0, orientedH > 0 else { throw EstimatorError.preprocessFailed }

        let dim = CGFloat(Self.inputDim)
        let scale = dim / max(orientedW, orientedH)
        let contentW = orientedW * scale
        let contentH = orientedH * scale
        let offsetX = (dim - contentW) / 2
        let offsetY = (dim - contentH) / 2

        let scaled = ci
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
        let canvas = CGRect(x: 0, y: 0, width: dim, height: dim)
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: canvas)
        let composited = scaled.composited(over: black)

        let buffer = try scratchPixelBuffer()
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        ciContext.render(composited, to: buffer, bounds: canvas, colorSpace: colorSpace)

        let rgb = try chwFloat(from: buffer)

        // contentRect normalized in the depth map's frame (origin top-left).
        // Vertical: CIContext.render flips to top-left origin; padding here is
        // horizontal (portrait), so y stays full.
        let contentRect = CGRect(
            x: offsetX / dim,
            y: offsetY / dim,
            width: contentW / dim,
            height: contentH / dim
        )
        return (rgb, contentRect, Float(scale))
    }

    private func scratchPixelBuffer() throws -> CVPixelBuffer {
        if let existing = scratchBuffer { return existing }
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Self.inputDim, Self.inputDim,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw EstimatorError.preprocessFailed
        }
        scratchBuffer = buffer
        return buffer
    }

    /// BGRA 518x518 -> planar RGB Float32 CHW in [0,255].
    private func chwFloat(from buffer: CVPixelBuffer) throws -> [Float] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw EstimatorError.preprocessFailed
        }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let src = base.assumingMemoryBound(to: UInt8.self)

        let plane = width * height
        var out = [Float](repeating: 0, count: 3 * plane)
        out.withUnsafeMutableBufferPointer { dst in
            for y in 0..<height {
                let row = y * stride
                for x in 0..<width {
                    let p = row + x * 4         // BGRA
                    let idx = y * width + x
                    dst[idx]             = Float(src[p + 2]) // R
                    dst[plane + idx]     = Float(src[p + 1]) // G
                    dst[2 * plane + idx] = Float(src[p + 0]) // B
                }
            }
        }
        return out
    }
}
