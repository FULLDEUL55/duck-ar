# Object Detection + World 위치 추정 후보 비교

_작성: ar-researcher / 2026-05-28 / Phase 1 — 오리가 "사물 쪽으로 이동" 시연_

> **재초점**: Duck-Head 가 액션을 일단 "이동만" 으로 단순화 (sitting/pecking 제거). 따라서 본 보고서는 (a) **bounding box 출력 가능한 detection 모델** 과 (b) **bbox 의 world 위치 추정 (이동 목표 좌표)** 두 축에 집중. 이전 `vision-ai-upgrade.md` (classification 보강 위주) 와 `llm-behavior.md` (액션 의사결정 LLM 화) 는 본 보고서가 supersede.

## 요약 (3줄)

- **즉시 통합 가능 1순위**: **Apple 공식 YOLOv3 Tiny Core ML** (35.4 MB, Apple Sample Code License, COCO 80 — chair / dining table / couch / bed 포함) + **`ARView.raycastQuery(from: bboxCenter, allowing: .estimatedPlane, alignment: .horizontal)`** 로 bbox 중심 → world 좌표. 추가 의존성 / 라이선스 부담 zero, Phase 1 시연 (의자 쪽으로 오리가 걸어가기) 에 충분.
- **차선 detection**: **MobileNetV2 + SSDLite** (9.3 MB, COCO 90) — Neural Engine underperform 알려져 있으나 GPU 경로로도 모바일 실시간 가능. 모델 크기 우선 시 채택.
- **Depth 보강은 Phase 2 로 미룸**: Apple Depth Pro Core ML 변환은 [community PR #45](https://github.com/apple/ml-depth-pro/pull/45) 가 1024×1024 float16 패키지 진행 중. M1 iPad 실시간 추론 검증 부재. Phase 1 의 "이동만" 시연에는 raycast 만으로 충분 — depth 는 mesh-level occlusion / 정밀 height 필요한 Phase 2 진입 시점에 재평가.

## 비교 표 — Detection 후보

| # | 모델 | 라이선스 | 모델 크기 | 클래스 | Open-vocab? | 실내 가구 (chair / table / couch / bed) | iPad M1 fps 자료 | Core ML 변환 난이도 | 비고 |
|---|------|---------|----------|--------|-------------|------------------------------------|-----------------|---------------------|------|
| **1** | **Apple 공식 YOLOv3 Tiny** | Apple Sample Code License | 35.4 MB | COCO 80 | ❌ | **포함** | M1 iPad 직접 자료 없음. iPhone 14 Pro YOLOv8n 38 fps 자료 참조 시 충분 | drag-and-drop (Apple 배포 .mlmodel) | **즉시 1순위** |
| 2 | **MobileNetV2 + SSDLite** | (변환 코드 별도, base Apache 2.0) | **9.3 MB** | COCO 90 | ❌ | 포함 | 가장 가벼움. Neural Engine 에서 underperform — Metal/GPU 경로 사용 시 iPhone XS 까지 빠름 ([machinethink](https://machinethink.net/blog/mobilenet-ssdlite-coreml/)) | 변환 스크립트 ([hollance](https://github.com/hollance/coreml-survival-guide/blob/master/MobileNetV2+SSDLite/ssdlite.py)) 또는 [tucan9389 prebuilt](https://github.com/tucan9389/ObjectDetection-CoreML) | 모델 크기 ↓ 우선 시 |
| 3 | **Apple 공식 DETR ResNet50** | Facebook Research (GitHub source) | F16 85.5 MB / F16P8 43.1 MB | COCO 80 (+ panoptic) | ❌ | 포함 | 측정자료 없음. transformer 기반으로 YOLOv3 Tiny 대비 무거움 | Apple 사전 변환 .mlpackage 제공 | 정확도 ↑ 시 |
| 4 | **Ultralytics YOLOv8n / YOLO11n** | **AGPL-3.0** (상용 Enterprise license) | 12.7 MB | COCO 80 | ❌ | 포함 | iPhone 14 Pro YOLOv8n **38 fps**, YOLO11 iPhone NE **60+ fps** | `model.export(format='coreml')` | 라이선스 부담 — 데모 외 배포 시 결정 보류 |
| 5 | **YOLO-World s (Tencent)** | **GPL-v3** + Tencent commercial license | (미확인) | open-vocab ("chair" 텍스트 프롬프트) | ✅ | 포함 (vocab 정의) | 미검증 (TFLite/ONNX 만 공식, Core ML 가이드 없음) | **R&D 수일~수주** | open-vocab 매력적이나 라이선스 + 변환 비용 |
| 6 | **Apple FastViT + custom detection head** | Apple SDK (FastViT GitHub source) | T8 8.2 MB (classifier) — detection head 추가 시 추가 | ImageNet 1000 (classifier) | ❌ | 일부 (classifier 만) | iPhone 16 Pro T8 0.5 ms (classifier only) | **detection 헤드 직접 구현 필요** | 분류기에 머무름 — detection 직접 안 됨 |
| 7 | **VNRecognizeAnimalsRequest / VNDetectFaceRectanglesRequest** | Apple SDK | 0 MB | 동물 / 얼굴 한정 | ❌ | ❌ (furniture 미지원) | 시스템 최적화 | 0 | 우리 use case 무관 — 참고 |
| 8 | **VNGenerateForegroundInstanceMaskRequest** (iOS 17+) | Apple SDK | 0 MB | "두드러진 객체 마스크" (클래스 없음, 1 + N instance segmentation) | ❌ | (mask 만 — class label 없음) | 시스템 최적화 (Apple Vision) | 0 | bbox 대신 mask 제공. 단 class 모름 — classifier 와 합쳐야 함. **참고 후보** |

## 비교 표 — World 위치 추정 후보

| # | 방법 | 정확도 (의자~책상 거리) | 의존성 | iPad Air 5 (M1, LiDAR 없음) 가용 | 통합 비용 | 비고 |
|---|------|----------------------|--------|---------------------------------|----------|------|
| **1** | **`ARView.raycastQuery(from: screenPt, allowing: .estimatedPlane, alignment: .horizontal)`** | cm 단위 X, 0.05-0.2 m 수준 — Phase 1 "옆으로 이동" 시연 충분 | ARKit / RealityKit 표준 | ✅ (LiDAR 무관) | **0 (라이브러리 추가 zero)** | **즉시 1순위**. bbox 중심 → screen 점 → ray → horizontal plane 교차 |
| 2 | **`raycastQuery(... .existingPlaneGeometry, .horizontal)`** | 신뢰도 ↑ (실제 감지 plane 만 hit) | ARKit plane detection 완료 후만 | ✅ | 0 | (#1) fallback. plane 감지 전 / plane 밖 영역은 hit 실패 |
| 3 | **`raycastQuery(... .estimatedPlane, .any)`** | vertical plane (벽, 책상 옆면) 도 hit | ARKit | ✅ | 0 | 벽에 붙은 사물 위치 필요 시 |
| 4 | **`session.raycast(query)` (단발) vs `trackedRaycast(query) { ... }` (연속)** | 동일 | ARKit | ✅ | 단발 < 연속 | dwell 기반 갱신은 단발 raycast 로 충분. 연속 추적은 카메라/오리 이동 따라 좌표 안정화 시 |
| 5 | **Apple Depth Pro Core ML** (community PR #45) | dense depth — 좌석 height 등 정밀 추정 가능 | ml-depth-pro 변환 패키지 (1024×1024 float16) | M1 iPad 실시간 추론 검증 부재 | **R&D 수일~수주** | Phase 2 mesh-level occlusion / 정밀 height 시점에만 |
| 6 | **DepthAnything-v2 small Core ML** | dense depth | HuggingFace, Apple Core ML 변환 사례 ([DeepWiki](https://deepwiki.com/kaylorchen/Depth-Anything-V2/8.2-apple-core-ml)) | 미검증 (M1 iPad) | R&D 수일 | Depth Pro 대안 — 더 가벼움 |
| 7 | **Scene Reconstruction (`ARMeshAnchor`)** | mm 단위 mesh | ARKit | ❌ **iPad Air 5 LiDAR 없음 — 불가** | — | 본 디바이스에서 사용 불가. 참고만 |
| 8 | **Hit-test 구 API (`ARFrame.hitTest`)** | raycast 동급 | ARKit (deprecated) | ✅ | 0 | iOS 13+ 권장은 raycast. 신규 코드 사용 비권장 |

## 추천

### 1순위 — Apple 공식 YOLOv3 Tiny + ARView raycast (.estimatedPlane / .horizontal)
- **이유**:
  1. **즉시 통합 가능**. detection 모델 (`.mlmodel` drag-in) + 위치 추정 (ARKit 표준 API). 추가 라이브러리 zero, 라이선스 안전.
  2. **Phase 1 시연 (의자 쪽 이동)** 정확도 요구가 cm 가 아닌 0.1 m 수준이면 raycast 만으로 충분.
  3. M1 iPad 직접 fps 자료는 없으나 동급 (A15 NE) 추정으로 YOLOv8n iPhone 14 Pro 38 fps 자료 참조 시 5-15 fps 충분 가능. Phase 1 시연은 매 프레임 detection 불필요 — 2-5 fps 로도 시연 충분.
  4. classification 보강 필요 시 (#10 이전 보고서) 동일 파이프라인에 Create ML custom classifier 후속 추가 가능 — 본 1순위와 충돌 없음.

### 통합 설계 스케치 (Phase 1)

```
ARFrame (every Nth frame, 예: 5 fps)
   │
   ▼
VNImageRequestHandler.perform([VNCoreMLRequest(model: yolov3Tiny)])
   │
   ▼
[VNRecognizedObjectObservation]  (.boundingBox 는 normalized image space)
   │
   ├─ filter: label ∈ {chair, dining table, couch, bed, ...} AND conf ≥ 0.5
   │
   ▼
For each obj:
  let bboxCenter = CGPoint(x: obj.boundingBox.midX * viewWidth,
                           y: (1 - obj.boundingBox.midY) * viewHeight)   // Vision Y-flip
  let query = arView.makeRaycastQuery(from: bboxCenter,
                                      allowing: .estimatedPlane,
                                      alignment: .horizontal)
  if let result = arView.session.raycast(query).first {
      // result.worldTransform.translation → 이동 목표 좌표
      perceivedObjects.upsert(label: obj.labels[0].identifier,
                              worldPos: result.worldTransform.translation,
                              firstSeenAt: ..., lastSeenAt: ...)
  }
   │
   ▼
DuckBehaviorPlanner (정적 dict 매핑 — LLM 보류 결정에 따름)
   │
   ▼
DuckState.Walking(target: perceivedObject.worldPos)  →  RealityKit Entity 이동
```

- **트리거**: 신규 furniture label 진입 OR 현 target 의 worldPos 이동 ≥ 0.3 m
- **Fallback (raycast 실패)**: bbox 중심 raycast 0 hit → frame 전체 horizontal plane 중 카메라 가장 가까운 plane 중심 사용 → 그것도 없으면 무동작
- **Smoothing**: worldPos 는 최근 N 회 평균 (저역 필터) — detection jitter / raycast 노이즈 흡수

### 차선 — MobileNetV2 + SSDLite (9.3 MB)
- 모델 크기 ↓ 우선 시. detection 부분만 swap, raycast 파이프라인 동일.
- 단 Neural Engine 미활용 → Metal/GPU 경로 명시적 강제 (`MLModelConfiguration.computeUnits = .cpuAndGPU`) 필요.

### Depth 모델은 Phase 1 미도입
- "이동만" 시연에 dense depth 불필요. raycast 만으로 충분.
- Phase 2 진입 시 (mesh occlusion / 의자 좌석 위 정밀 착지 필요) Apple Depth Pro Core ML community PR 진척도 + DepthAnything-v2 small 의 M1 iPad 실측 비교 후 결정.

## 근거 (출처 + 접근 일자 2026-05-28)

### Detection 모델
- [Apple — Machine Learning Models 카탈로그](https://developer.apple.com/machine-learning/models/) — YOLOv3 Tiny 35.4 MB / MobileNetV2 / DETR ResNet50 / FastViT 공식 .mlpackage
- [tucan9389/ObjectDetection-CoreML (MIT)](https://github.com/tucan9389/ObjectDetection-CoreML) — YOLOv8n 12.7 MB / MobileNetV2_SSDLite 9.3 MB, iPhone 14 Pro fps 표
- [Roboflow — Best iOS Object Detection Models 2025](https://blog.roboflow.com/best-ios-object-detection-models/) — YOLO11 iPhone NE 60+ fps
- [machinethink — MobileNetV2+SSDLite with Core ML](https://machinethink.net/blog/mobilenet-ssdlite-coreml/) — NE underperform 분석, COCO 90
- [Ultralytics — Core ML Export](https://docs.ultralytics.com/integrations/coreml) — `model.export(format='coreml')`
- [Ultralytics License](https://www.ultralytics.com/license) — AGPL-3.0
- [AILab-CVC/YOLO-World GitHub](https://github.com/AILab-CVC/YOLO-World) — GPL-v3, Tencent commercial

### Vision + ARKit 통합 패턴
- [Dennis Ippel — Vision Framework Object Detection in ARKit](https://rozengain.medium.com/using-vision-framework-object-detection-in-arkit-c0b5366f465d) — bbox → raycast 전형 패턴
- [Yehor Chernenko — Core ML + ARKit: Annotating Objects in AR](https://heartbeat.comet.ml/core-ml-arkit-annotating-objects-in-augmented-reality-493952a94a5f) — raycastQuery → world position 코드
- [MasDennis/ARKitVisionObjectDetection (GitHub)](https://github.com/MasDennis/ARKitVisionObjectDetection)
- [hanleyweng/CoreML-in-ARKit](https://github.com/hanleyweng/CoreML-in-ARKit) — ARKit + Core ML 템플릿
- [machinethink — How to display Vision bounding boxes](https://machinethink.net/blog/bounding-boxes/) — Vision 좌표계 (Y-flip) 처리

### Raycast / World 좌표
- [Apple — ARRaycastQuery.Target.estimatedPlane](https://developer.apple.com/documentation/arkit/arraycastquery/target-swift.enum/estimatedplane) — 비평면 / 추정 plane
- [Apple — ARRaycastQuery.Target.existingPlaneGeometry](https://developer.apple.com/documentation/arkit/arraycastquery/target-swift.enum/existingplanegeometry) — 확정 plane geometry 만
- [Apple — ARRaycastResult](https://developer.apple.com/documentation/arkit/arraycastresult) — `worldTransform` 결과
- [Medium / Jandi — ARTrackedRaycast in SwiftUI](https://medium.com/@arkit/realitykit-911-how-to-implement-artrackedraycast-in-swiftui-app-0430283a014f) — `trackedRaycast` 연속 추적

### Depth (Phase 2 참고)
- [Apple — Depth Pro 연구 페이지](https://machinelearning.apple.com/research/depth-pro), [arXiv 2410.02073](https://arxiv.org/pdf/2410.02073)
- [GitHub apple/ml-depth-pro](https://github.com/apple/ml-depth-pro), [PR #45 — 1024×1024 float16 Core ML 변환](https://github.com/apple/ml-depth-pro/pull/45), [Issue #3 — iOS 포팅 논의](https://github.com/apple/ml-depth-pro/issues/3)
- [HuggingFace apple/DepthPro-hf](https://huggingface.co/apple/DepthPro-hf) — Apple-amlr 라이선스
- [DeepWiki — kaylorchen/Depth-Anything-V2 Apple Core ML 변환](https://deepwiki.com/kaylorchen/Depth-Anything-V2/8.2-apple-core-ml)

## 다음 액션

1. **사용자 액션**: Apple 공식 [YOLOv3 Tiny Core ML](https://developer.apple.com/machine-learning/models/) `.mlpackage` 다운로드 → `code/DuckAR/Models/YOLOv3Tiny.mlpackage` 배치. 동봉 `LICENSE.txt` (Apple Sample Code License) 본문 확인 — App Store 배포 가능 범위 명시 여부.
2. **arkit-perception 위임** (PerceptionCoordinator Task #4 후속):
   - `VNCoreMLRequest(model: try VNCoreMLModel(for: YOLOv3Tiny().model))` 통합
   - bbox 중심 → `ARView.makeRaycastQuery(from:allowing:.estimatedPlane, alignment:.horizontal)` → world transform
   - `PerceivedObject { label, confidence, worldPos: SIMD3<Float>, firstSeenAt, lastSeenAt }` 표준 struct emit
   - frame 빈도 조절 (`every Nth frame`, 5 fps 시작) — UI 메인 thread 블록 방지
3. **duck-behavior 위임** (DuckState 상태머신 Task #3 후속):
   - `Walking(target: SIMD3<Float>)` 액션만 처리 (LLM/sitting/pecking 보류)
   - 정적 매핑: 어떤 furniture label 이든 가장 가까운 worldPos 로 이동
   - 도착 판정: 거리 < 0.15 m → `Idle` 복귀
4. **계측** (Phase 1 종료 시점): M1 iPad 에서 YOLOv3 Tiny 단일 frame 추론 ms 측정 + raycast hit rate (시도 / 성공) 기록 → 본 보고서 표에 채워넣기.

## 미해결

- **Apple YOLOv3 Tiny Core ML 의 LICENSE.txt 본문** — 다운로드 zip 동봉 텍스트 직접 확인. "for development purposes only" 제약 가능성 (App Store 배포 시 영향). 사용자 / xcode-builder 가 다운로드 시점에 확인.
- **M1 iPad 단일 frame detection latency 실측치** 부재 — PoC 통합 후 첫 측정값 필요.
- **bbox 중심 raycast 의 실제 hit rate** — 의자 좌석 (수평면) 은 잘 잡히지만, 책상 윗면 / 침대 등 큰 면적은 plane 감지가 분리되거나 estimated plane 정확도 낮을 가능성. 사용자 실제 환경 (사무실 / 거실) 에서 측정 필요.
- **Apple Depth Pro Core ML 변환 PR #45** 의 머지 상태 / 결과 모델 크기 / iPad M1 추론 latency — Phase 2 진입 시점에 재조사.
- **VNGenerateForegroundInstanceMaskRequest** (iOS 17+) 를 mask + classifier 조합으로 detection 대체할 수 있는지 — iOS 26.5 SDK 에서 instance mask 품질 측정 미수행. 현 단계에서는 표준 detection 모델 사용.
