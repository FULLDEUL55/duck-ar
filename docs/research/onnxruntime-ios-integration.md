# ONNX Runtime iOS — Metric3D ViT-Small 통합 가이드

_작성: ar-researcher / 2026-05-29 / Task #19 (옵션 C: ORT iOS 우회)_

## 요약 (3줄)

- Metric3D ViT-Small 의 Core ML 변환이 rank 7 reshape 제약에 막혀 **ONNX Runtime iOS (ORT) 우회 경로** 채택. 모델은 `code/DuckAR/DuckAR/Models/metric3d_vit_small.onnx` (fp16, **75.8 MB**, BSD-2-Clause + CC0-1.0) 로 번들.
- **SwiftPM 의존 1 개**: `microsoft/onnxruntime-swift-package-manager` 1.20.0 (또는 그 이후 안정판). XCFramework 약 60-100 MB 추가. App Store 제출 시 framework Info.plist 의 `MinimumOSVersion` 누락 이슈 (ORT #27396) 인지 필요.
- **scale 보정 = canonical focal 1000 → ARKit `ARCamera.intrinsics.fx`** 비례. ONNX 가 모델 내부에 ImageNet mean/std × 255 정규화 노드 (`Sub` + `Div`) 를 이미 포함 → Swift 측 정규화 코드 **불필요**. 입력은 raw [0, 255] float RGB.

## 1. 모델 사양 (재확인)

ONNX 그래프 검사 결과:

```
op 0 : Sub(pixel_values, rgb_mean=[123.6875, 116.25, 103.5])
op 1 : Div(., rgb_std=[58.40625, 57.125, 57.375])
op 2+: DINOv2 patch embed (Conv) → ViT-S → RAFT decoder
```

- `rgb_mean ≈ ImageNet mean (0.485, 0.456, 0.406) × 255`
- `rgb_std  ≈ ImageNet std  (0.229, 0.224, 0.225) × 255`

→ **Swift 측에서 정규화 / 0-1 스케일링 금지**. raw [0, 255] BGR/ARGB CVPixelBuffer → RGB float [0, 255] 채널 분리만 수행.

| I/O | 이름 | 형상 | dtype | 의미 |
|-----|------|------|-------|------|
| input  | `pixel_values`      | `[1, 3, H, W]`              | fp16 | raw RGB in [0, 255] |
| output | `predicted_depth`   | `[1, H', W']`               | fp16 | canonical metric depth (meters) |
| output | `predicted_normal`  | `[1, 3, H', W']`            | fp16 | surface normal (xyz, unit vec) |
| output | `normal_confidence` | `[1, H', W']`               | fp16 | normal confidence in [0, 1] |

- H/W 는 14 의 배수 (DINOv2 patch). **권장 518×518** (= 14·37).
- `H' = 4 · floor(3.5 · floor(H/14))`, W' 동일. 518 입력 시 H' = 4·floor(3.5·37) = 4·129 = **516**.

## 2. SwiftPM 의존 추가 (xcode-builder Task #24 영역)

### 패키지 등록

`File → Add Package Dependencies` 에서:

- URL: `https://github.com/microsoft/onnxruntime-swift-package-manager`
- Dependency Rule: **Up to Next Major Version**, `1.20.0` 이상 (현 최신 안정).
- Product: `onnxruntime` 또는 `onnxruntime_extensions` — 본 모델은 표준 op 만 사용하므로 **`onnxruntime` 만 추가**.

`Package.swift` 가 외부 XCFramework 를 binary dependency 로 가져온다. iOS 최소 deployment target 은 패키지 자체가 iOS 13+ 지원. duck-ar 프로젝트는 iPadOS 26.5 SDK 이므로 호환.

### App Store 제출 주의 (ORT GitHub Issue #27396)

[microsoft/onnxruntime#27396](https://github.com/microsoft/onnxruntime/issues/27396) — SwiftPM 로 받은 `onnxruntime.xcframework` 내부 framework Info.plist 의 `MinimumOSVersion` 누락 → App Store / TestFlight validator 가 거부. **회피책**:
1. SPM 로 받은 후 Xcode build phase 에 post-build script 추가: `defaults write` 또는 `plutil -insert MinimumOSVersion -string "17.0"` 로 framework Info.plist 수정.
2. 또는 ORT GitHub release 의 직접 빌드 XCFramework 사용 (수동 추가).
- Phase 1 (사내 검증) 은 영향 없음. App Store 제출 시점에 해결.

### XCFramework 만 직접 사용 (대안)

ORT 공식 [`onnxruntime-objc` / `onnxruntime-c` Release XCFramework](https://github.com/microsoft/onnxruntime/releases) 를 `Frameworks` 폴더 drag-in → Embed & Sign. 통합 자유도 ↑, SPM 의존 정리 부담 ↓. 단 수동 업데이트.

## 3. Swift bridge 스켈레톤 — `Metric3DEstimator`

`code/DuckAR/DuckAR/Perception/Metric3DEstimator.swift` (제안 위치 — 실제 구현은 arkit-perception Task #20):

```swift
import Foundation
import CoreGraphics
import CoreVideo
import Vision
import simd
import onnxruntime_objc       // SPM product

/// Metric3D ViT-Small monocular metric depth.
/// Loads `metric3d_vit_small.onnx` from the main bundle and runs serial inference
/// on a private queue. Thread-safe to call `estimate(...)` from any thread.
public final class Metric3DEstimator {

    public struct DepthFrame {
        public let depth: [Float]         // row-major, length = height * width, in METERS (post-scaling)
        public let width: Int
        public let height: Int
        public let normal: [Float]?       // optional; length = 3 * height * width if requested
        public let normalConfidence: [Float]?
    }

    public enum EstimatorError: Error {
        case modelMissing
        case sessionFailed(String)
        case inputShapeInvalid
        case outputShapeUnexpected
    }

    private let env: ORTEnv
    private let session: ORTSession
    private let queue = DispatchQueue(label: "duckar.metric3d", qos: .userInitiated)

    // Canonical input geometry: 518 x 518 (14 * 37). Squared shape keeps the
    // attention layout deterministic and matches Metric3D's training canonical.
    private static let inputW: Int = 518
    private static let inputH: Int = 518

    /// canonical focal_length the model was trained against.
    private static let canonicalFocal: Float = 1000.0

    public init() throws {
        guard let url = Bundle.main.url(forResource: "metric3d_vit_small", withExtension: "onnx") else {
            throw EstimatorError.modelMissing
        }
        self.env = try ORTEnv(loggingLevel: .warning)
        let opts = try ORTSessionOptions()
        // Single thread per inference to keep the AR main loop responsive.
        try opts.setIntraOpNumThreads(2)
        try opts.setInterOpNumThreads(1)
        // CoreML EP would be ideal but rank-7 op forces CPU fallback anyway -> stay on default CPU.
        self.session = try ORTSession(env: env, modelPath: url.path, sessionOptions: opts)
    }

    /// Run depth on a frame, scaled to real meters using the actual camera focal length.
    /// - parameters:
    ///   - pixelBuffer: BGRA or 32ARGB CVPixelBuffer from `ARFrame.capturedImage`
    ///   - intrinsicsFx: ARKit `ARCamera.intrinsics[0,0]` in pixels for the FULL captured image
    ///   - imageSize: pixel dimensions of `pixelBuffer` (CVPixelBufferGet*)
    public func estimate(pixelBuffer: CVPixelBuffer,
                         intrinsicsFx: Float,
                         imageSize: CGSize) throws -> DepthFrame {
        // 1) Letterbox / resize to (inputW, inputH) preserving aspect ratio.
        //    Letterbox black borders are fine — Metric3D handles padded regions
        //    gracefully; tracked-bbox lookups will fall inside the active crop.
        let rgb = try preprocess(pixelBuffer: pixelBuffer,
                                 targetWidth: Self.inputW,
                                 targetHeight: Self.inputH)
        // rgb is a flat [3 * H * W] Float32 (or Float16) buffer in CHW order,
        // raw values in [0, 255] — the ONNX graph normalizes internally.

        // 2) ORTValue tensor (NCHW, fp16). We pack as Float16 to match the model's input dtype.
        let shape: [NSNumber] = [1, 3, NSNumber(value: Self.inputH), NSNumber(value: Self.inputW)]
        let tensor = try ORTValue.tensor(
            from: rgb,                  // already serialized as Data
            shape: shape,
            elementType: .float16
        )

        // 3) Run.
        let outputs = try session.run(
            withInputs: ["pixel_values": tensor],
            outputNames: ["predicted_depth"],     // only depth on the hot path
            runOptions: nil
        )
        guard let depthValue = outputs["predicted_depth"] else { throw EstimatorError.outputShapeUnexpected }
        let (depthFloats, depthShape) = try depthValue.toFloat32Array()    // helper: fp16 -> Float, returns shape too
        guard depthShape.count == 3, depthShape[0] == 1 else { throw EstimatorError.outputShapeUnexpected }
        let outH = depthShape[1], outW = depthShape[2]

        // 4) Scale canonical (focal=1000) -> actual.
        //    fx_for_resized_image = intrinsicsFx * (inputW / originalImageW)
        let fxResized = intrinsicsFx * Float(Self.inputW) / Float(imageSize.width)
        let scale = fxResized / Self.canonicalFocal
        var metricDepth = depthFloats
        for i in 0..<metricDepth.count { metricDepth[i] *= scale }

        return DepthFrame(depth: metricDepth,
                          width: outW,
                          height: outH,
                          normal: nil,
                          normalConfidence: nil)
    }
}
```

### 전처리 (요약)

CVPixelBuffer (BGRA, ARFrame 표준) → resize 518×518 → CHW Float16 [0, 255]:

```swift
private func preprocess(pixelBuffer: CVPixelBuffer,
                        targetWidth: Int,
                        targetHeight: Int) throws -> Data {
    // Recommended path: vImage_Buffer for zero-copy BGRA convert + scale.
    // 1) Lock pixel buffer
    // 2) vImageScale_ARGB8888 to (targetWidth, targetHeight)  — letterbox if aspect mismatch
    // 3) vImageConvert_BGRA8888toRGB888 (or manual swizzle B<->R)
    // 4) De-interleave to planar R, G, B
    // 5) Cast UInt8 -> Float16, keep in [0, 255]
    // 6) Concatenate planar R || G || B into a single contiguous fp16 Data of
    //    length 3 * H * W * 2 bytes (fp16 = 2 bytes).
}
```

핵심: **나누기 255 금지**, **ImageNet mean/std 빼기 금지** — 모델 내부에서 처리됨.

### Threading

- `ORTSession` 자체는 thread-safe. 그러나 inference 는 무거운 작업 (M1 iPad 추정 25-100 ms) → AR 메인 루프와 분리 권장.
- 권장: 전용 `DispatchQueue(label: "duckar.metric3d", qos: .userInitiated)`. inflight ≥ 1 이면 새 frame skip (back-pressure).
- ARFrame timestamp 와 함께 결과 publish → `PerceptionCoordinator` (Task #20) 가 detection bbox 와 같은 frame 매칭.

### 에러 처리

| 케이스 | 처리 |
|--------|------|
| 모델 파일 누락 | `modelMissing` throw, UI 에 "depth disabled" 표시 (Task #20) |
| OOM (예: 큰 입력 해상도) | Catch `NSException` from `session.run` → fallback raycast-only 모드 |
| Shape mismatch (입력 14 배수 위반) | `inputShapeInvalid` throw → preprocess 가 항상 518 보장하므로 발생 안 됨 |
| 출력 텐서 미발견 | `outputShapeUnexpected` throw |

## 4. Bbox center → metric depth → world coordinate 공식

### 입력
- Detection: `VNRecognizedObjectObservation.boundingBox` (normalized, Vision Y-flip)
- ARKit `ARCamera.intrinsics` (3×3 simd float)
- ARKit `ARCamera.transform` (4×4 simd float)
- Depth map `D` (H' × W', meters after scale 보정)
- Pixel buffer size `(imgW, imgH)`

### 단계

1. **bbox 중심 → 픽셀 좌표** (capturedImage 픽셀계)
   - `(u_px, v_px) = (bbox.midX * imgW, (1 - bbox.midY) * imgH)`  // Vision Y-flip 해제

2. **픽셀 → depth map 인덱스**
   - 모델 입력은 letterboxed 518×518, 출력 depth 는 H'×W' (예: 516×516). 캡쳐 → 입력 매핑의 역변환 필요.
   - 권장: capturedImage 가 16:9 (예: 1920×1080) → 518 박스 안의 active crop 은 `(518, 518 · 9/16) = (518, ~291)`. nearby 좌표 매핑.
   - 가장 가까운 정수 인덱스 `(i, j)` 에서 depth 추출 (또는 3×3 평균):
     `d_pred = D[j, i]`

3. **canonical → metric 보정** (Estimator 가 이미 적용했다면 skip)
   - `d_metric = d_pred · (fx_resized / 1000)` — Swift bridge 가 처리한 경우 그대로 사용.
   - `fx_resized = intrinsicsFx · 518 / imgW` 로 capturedImage 의 fx 를 resize 비율 보정.

4. **픽셀 + depth → 카메라 로컬 3D**
   - pinhole 역투영. cx, cy 는 capturedImage 의 principal point (intrinsics[2,0], intrinsics[2,1]):
   - ```swift
     let X_cam = (u_px - cx) * d_metric / fx
     let Y_cam = (v_px - cy) * d_metric / fy
     let Z_cam = d_metric
     ```
   - **단위**: `d_metric` 이 meters → X, Y, Z 모두 meters.

5. **카메라 로컬 → world**
   - ARKit `ARCamera.transform` (4×4) 가 camera→world 변환. **단, ARKit/RealityKit 의 카메라 forward 는 `-Z`** (오른손 좌표계, 카메라가 -Z 방향 바라봄).
   - ```swift
     let p_cam = SIMD4<Float>(X_cam, -Y_cam, -Z_cam, 1)   // image Y down → world Y up; image forward Z+ → camera -Z
     let p_world4 = camera.transform * p_cam
     let p_world = SIMD3<Float>(p_world4.x, p_world4.y, p_world4.z) / p_world4.w
     ```
   - `p_world` 가 `PerceivedObject.worldPos` 로 publish.

6. **검증**: raycast hit (`ARView.raycast(.estimatedPlane, .horizontal)`) 결과와 cross-check. 두 좌표가 0.3 m 이내면 신뢰. 차이 크면 detection 신뢰도 낮은 frame 일 가능성 — 폴백.

## 5. M1 iPad 성능 예상

- ORT CPU EP (Core ML EP 도 rank 7 op 만나면 CPU fallback) — 추정 추론 시간:
  - 518×518 fp16 ViT-S 24M params → CPU 만으로 60-150 ms / frame (M1 다중 코어 활용 시)
  - 5 fps depth pipeline 가능. detection (YOLOv3 Tiny, ~30-50 ms) 와 별도 queue 분리 권장.
- 메모리: 모델 weight 75.8 MB + activation (518×518 입력 시 50-100 MB) → ~200 MB 전체. 8 GB RAM 안정.
- 발열: 5 fps 지속 시 (총 추론 budget ~30%) 수분 내 thermal throttle 가능. 시연 후 idle pause 권장.

## 6. 라이선스 / NOTICE

- `code/DuckAR/DuckAR/Models/metric3d_vit_small.LICENSE` — yvanyin/metric3d 본문 (BSD-2-Clause).
- `code/DuckAR/DuckAR/Models/metric3d_vit_small.NOTICE` — 출처/attribution 안내.
- 앱 내 "About / Credits" 화면 권장 표기:
  ```
  Depth estimation: Metric3D ViT-Small
  © 2024 Wei Yin, Mu Hu — BSD-2-Clause
  ONNX export: onnx-community (CC0-1.0)
  ONNX Runtime — Copyright (c) Microsoft Corporation, MIT License
  ```

## 7. 다음 액션 (서브 에이전트 위임 지점)

| Task | 담당 | 내용 |
|------|------|------|
| **#24** | **xcode-builder** | SwiftPM `microsoft/onnxruntime-swift-package-manager` 1.20.0+ 추가 + `metric3d_vit_small.onnx` 를 Copy Bundle Resources 에 등록 + Release 빌드에서 LICENSE/NOTICE 도 함께 번들 |
| **#20 stage 2** | **arkit-perception** | `Metric3DEstimator` 구현 (본 가이드 § 3) + `PerceptionCoordinator` 의 depth slot 에 연결 + scale 앵커링 PoC (canonical → 실제 fx 보정) |
| **#21** | **realitykit-scene** | depth map 활용한 mesh occlusion (오리가 의자 다리 뒤로 가려짐) — depth-aware shader 또는 generated mesh |
| **#22** | **arkit-perception + duck-behavior** | depth 기반 free-space 마스크 → 오리 navigation 영역 확장 |

## 미해결

- **ORT CoreML Execution Provider** 가 일부 노드만 GPU/NE 가속할 수 있음 — 그러나 rank 7 reshape 이 unsupported → CPU fallback 으로 partition. 실측 시 CoreML EP 로 부분 가속 시도 가치 있음 (수 분 작업).
- **fp16 ONNX 입력 dtype** — ORT iOS 의 ORTValue.tensor(.float16) 이 Swift Float16 (iOS 14+) 또는 Data 만 받는지 SDK 1.20 문서 재확인 필요.
- **App Store 제출 시 framework Info.plist `MinimumOSVersion`** — issue #27396 회피 스크립트 정형화 필요. arkit-perception 통합 이후 xcode-builder 가 처리.
- **letterbox vs stretch** — 본 가이드는 letterbox (aspect 보존) 권장. stretch 시 depth aspect 왜곡 → 객체 거리 추정 편향. 실측 후 결정.
- **ORT thread-safety + ARSession callback** — `session.run` 을 ARSession callback 스레드에서 직접 호출하면 메인 루프 lock 가능. 가이드 § 3 의 전용 queue 사용 필수.
- **모델 warm-up** — 첫 호출 100-200 ms 더 느림. 앱 시작 시 dummy `[1,3,518,518]` 으로 1회 호출 권장.

## 근거 (출처 + 접근 일자 2026-05-29)

- [microsoft/onnxruntime-swift-package-manager (1.20.0)](https://github.com/microsoft/onnxruntime-swift-package-manager) — 공식 SPM
- [Releases · onnxruntime-swift-package-manager](https://github.com/microsoft/onnxruntime-swift-package-manager/releases)
- [Package.swift — binary dependency](https://github.com/microsoft/onnxruntime-swift-package-manager/blob/main/Package.swift)
- [ONNX Runtime — Build for iOS](https://onnxruntime.ai/docs/build/ios.html)
- [microsoft/onnxruntime issue #27396 — MinimumOSVersion missing](https://github.com/microsoft/onnxruntime/issues/27396)
- [yvanyin/metric3d (BSD-2-Clause)](https://github.com/yvanyin/metric3d), [LICENSE](https://raw.githubusercontent.com/YvanYin/Metric3D/main/LICENSE)
- [onnx-community/metric3d-vit-small (CC0-1.0)](https://huggingface.co/onnx-community/metric3d-vit-small) — ONNX 재공개
- [Metric3Dv2 project page](https://jugghm.github.io/Metric3Dv2/)
- ONNX graph 검사 결과 (본 보고서 § 1): 모델 내장 `Sub(rgb_mean)` + `Div(rgb_std)` 노드, fp16 ONNX 75.8 MB.
- 이전 보고서: [`metric-3d-slam.md`](./metric-3d-slam.md), [`metric3d-small-conversion.md`](./metric3d-small-conversion.md) — 변환 시도 단계 및 rank 7 블로커 상세.
