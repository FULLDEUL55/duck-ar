# Core ML 사물 분류 / 검출 모델 비교 (Phase 1 semantic)

_작성: ar-researcher / 2026-05-27 / Phase 1 — semantic→캐릭터 행동 매핑용_

## 요약 (3줄)

- **Phase 1 PoC 1순위는 Apple `VNClassifyImageRequest`** — iOS 내장, 1000+ classes (실내 furniture 다수 포함), 코드 한 줄, Apple SDK 사용 약관만 적용. 의자/책상/바닥 같은 dominant scene label 매핑에 충분.
- 정확도/박스 좌표 (캐릭터를 의자 위에 정확히 앉히기 등) 필요 시점에 **Apple 공식 Core ML `YOLOv3 Tiny`** (Apple Sample Code License, 35.4 MB, COCO 80 클래스에 chair/couch/dining table/bed 포함) 로 업그레이드.
- **Ultralytics YOLOv8n / YOLO11n / YOLO26 은 AGPL-3.0** — 12.7 MB / iPhone 14 Pro 38 fps 로 가장 매력적이지만, 앱 배포 시 Ultralytics Enterprise License 결제 또는 본 프로젝트 전체 AGPL 공개 의무가 따라옴. Phase 1 (사내 PoC) 한정 사용은 허용, 추후 배포 시점에 라이선스 재결정.

## 비교 표

| # | 모델 | 출처 | 라이선스 | Task | Classes | 실내 furniture (chair / dining table / couch / bed) | 모델 크기 (Core ML) | 보고된 fps (디바이스) | 비고 |
|---|------|------|---------|------|---------|--------------------------------|--------------------|---------------------|------|
| 1 | **VNClassifyImageRequest** | iOS Vision (built-in) | Apple SDK | classification (multi-label) | ~1,000+ (Apple Neural Scene Analyzer) | 포함 (1000-class scene/object 풀에 furniture 다수 — 정확 클래스명은 SDK 런타임 조회) | 0 MB (앱에 모델 번들 불필요) | 측정자료 없음 — Vision request 1 회 / frame 으로 실시간 가능 (Apple 사례) | iOS 11+. 라이선스 zero. **Phase 1 PoC 1순위** |
| 2 | **Apple YOLOv3 Tiny** (Core ML 공식) | [developer.apple.com/machine-learning/models](https://developer.apple.com/machine-learning/models/) | Apple Sample Code License (재배포 OK, 앱 통합 OK) | object detection | COCO 80 | **chair / dining table / couch / bed 포함** (COCO 표준) | 35.4 MB | 측정자료 없음 (M1 iPad) — YOLOv8n 의 1/3 수준 추정 | 다운로드 즉시 Xcode drag-in. **차선 1순위** |
| 3 | **Apple YOLOv3** (full) | 동일 | Apple Sample Code License | object detection | COCO 80 | 포함 | 248.4 MB / FP16 124.2 / Int8 62.2 | 측정자료 없음 | 모바일에 과대 — Tiny 권장 |
| 4 | **MobileNetV2+SSDLite** | [hollance coreml-survival-guide](https://github.com/hollance/coreml-survival-guide/blob/master/MobileNetV2+SSDLite/ssdlite.py) / [machinethink blog](https://machinethink.net/blog/mobilenet-ssdlite-coreml/) | TensorFlow Object Detection API (Apache 2.0) + 변환 스크립트 (코드 라이선스 별도) | object detection | COCO 90 (chair/table/couch/bed 포함) | 포함 | 9.3 MB ([tucan9389 repo](https://github.com/tucan9389/ObjectDetection-CoreML)) | iPhone XS 까지는 Metal/GPU 빠름. **Neural Engine 에서 underperform** (depthwise separable conv 한계 — machinethink 분석) | 가장 작음. NE 가속 효율 낮음 |
| 5 | **Ultralytics YOLOv8n** (Core ML export) | [docs.ultralytics.com/integrations/coreml](https://docs.ultralytics.com/integrations/coreml) | **AGPL-3.0** (상용 시 Enterprise License) | object detection | COCO 80 | 포함 | 12.7 MB ([tucan9389 repo](https://github.com/tucan9389/ObjectDetection-CoreML)) | **iPhone 14 Pro 38 fps** (tucan9389) | 라이선스 부담 — Phase 1 내부 PoC 만 |
| 6 | **Ultralytics YOLO11n** | 동일 | AGPL-3.0 | object detection | COCO 80 | 포함 | YOLOv8m 대비 -22% 파라미터 | iPhone Neural Engine **60+ fps** (Roboflow), CoreML 변환 후 21→85 fps 사례 | YOLOv8n 후속. 동일 라이선스 |
| 7 | **Ultralytics YOLO26** | 동일 | AGPL-3.0 | object detection | COCO 80 | 포함 | (미확인) | 모바일 30+ fps (Ultralytics 자체 자료) | 최신 (2025) |
| 8 | **Apple MobileNetV2** (Core ML 공식) | [developer.apple.com/machine-learning/models](https://developer.apple.com/machine-learning/models/) | **Apache 2.0** | classification (단일 라벨) | ImageNet 1000 | 일부 (ImageNet 의 furniture 분류 가능, 단 detection 박스 없음) | 24.7 MB / FP16 12.4 / Int8 6.3 | Core ML 일반: MobileNetV1/V2 240+ fps ([machinethink](https://machinethink.net/faster-neural-networks/)) — SSDLite 아닌 순수 classifier 기준 | classification only. 가장 가벼움 |
| 9 | **Apple FastViT** (Core ML 공식) | 동일 | (GitHub source) | classification | ImageNet 1000 | 일부 | T8 8.2 MB / MA36 88.3 MB | **iPhone 16 Pro T8 ~0.5 ms** (Apple 공시) | 최신 분류기. iPad M1 fps 미공시 |
| 10 | **Apple ResNet-50** (Core ML 공식) | 동일 | (GitHub source) | classification | ImageNet 1000 | 일부 | 102.6 MB / FP16 51.3 / Int8 25.8 | 측정자료 없음 | 분류기 정확도 보강용 |
| 11 | **Apple DETR ResNet50** | 동일 | Facebook Research (GitHub source) | object detection / panoptic | COCO 80 | 포함 | F16 85.5 MB / F16P8 43.1 | 측정자료 없음 | YOLO 대비 무거움 |

> **iPad Air 5 (M1, A15급) 직접 측정 자료 부재.** 현존 자료는 iPhone 14 Pro (A16) / iPhone 16 Pro (A18 Pro) 기준이 대부분. M1 iPad 의 Neural Engine 은 A15 (16-core, 15.8 TOPS) 와 동급으로, iPhone 13 / 13 Pro 와 비슷한 수치가 나올 것으로 추정 — 단 추정치이며 PoC 후 실측 필요.

## 추천

### Phase 1 PoC — `VNClassifyImageRequest` (1순위)
- **이유**:
  1. 모델 번들 zero, 의존성 zero, 라이선스 zero — Phase 1 의 의자→앉기 1 액션 매핑 PoC 에는 최단 경로
  2. iOS 11+ 지원, iPadOS 26.5 (현 환경) 에서 안정
  3. `chair`, `table` 등 dominant scene label 만으로도 캐릭터 행동 트리거 충분
- **구현 윤곽**: `ARSession` frame → `CVPixelBuffer` → `VNImageRequestHandler.perform([VNClassifyImageRequest])` → 신뢰도 ≥ 0.5 label 을 `arkit-perception` 의 `PerceivedObject` 스트림으로 publish

### Phase 1 보강 / Phase 2 진입 시 — Apple `YOLOv3 Tiny` Core ML (차선)
- **이유**:
  1. **Apple Sample Code License** — 앱 통합/배포 안전 (Ultralytics 와 달리 GPL 전파 없음)
  2. 35.4 MB, COCO 80 → chair / dining table / couch / bed / bottle / cup / book 등 일상 사물 박스 좌표 제공
  3. Apple 공식 페이지에서 즉시 다운로드, Xcode drag-and-drop
- **언제 전환**: classification 만으로 캐릭터 위치 결정 부정확 (예: 의자 위 어디 앉을지) → detection 박스 필요한 시점

### Ultralytics YOLOv8n / YOLO11n — **상용 배포 시점 까지 보류**
- 라이선스 (AGPL-3.0) 가 본 프로젝트의 비공개 + App Store 배포 의도와 충돌. **사내 PoC / 비공개 데모 한정 허용**, App Store / TestFlight 일반 배포 시점에 (a) Enterprise License 결제, (b) 본 프로젝트 전체 AGPL 공개, (c) YOLOv3 Tiny / RF-DETR 등 비-AGPL 대체 — 중 택일 필요.

## 근거 (출처 + 접근 일자 2026-05-27)

- [Apple — Core ML Pre-trained Models 카탈로그](https://developer.apple.com/machine-learning/models/) — YOLOv3 / YOLOv3 Tiny / MobileNetV2 / ResNet-50 / FastViT / DETR / Depth Anything V2 정식 배포
- [Apple — VNClassifyImageRequest 문서](https://developer.apple.com/documentation/vision/vnclassifyimagerequest) — Apple Neural Scene Analyzer, 1000+ classes (실측 SDK 런타임 조회 필요)
- [Apple — Classifying Images with Vision and Core ML 가이드](https://developer.apple.com/documentation/vision/classifying_images_with_vision_and_core_ml)
- [tucan9389/ObjectDetection-CoreML (MIT)](https://github.com/tucan9389/ObjectDetection-CoreML) — YOLOv8n / YOLOv5 / YOLOv3 / MobileNetV2+SSDLite iPhone fps 표 (iPhone 14 Pro: YOLOv8n 38 fps, YOLOv5x 7 fps), 모델 크기 (YOLOv8n 12.7 MB, MobileNetV2_SSDLite 9.3 MB)
- [Roboflow — Best iOS Object Detection Models 2025](https://blog.roboflow.com/best-ios-object-detection-models/) — RF-DETR 54.7% mAP / YOLO11 53.4% mAP / YOLO11 Core ML iPhone NE 60+ fps / "21→85 fps" 변환 사례
- [Ultralytics — Core ML Export Docs](https://docs.ultralytics.com/integrations/coreml) — `model.export(format="coreml")` 워크플로
- [Ultralytics — License 페이지](https://www.ultralytics.com/license) — AGPL-3.0 기본, 상용 Enterprise License 별도
- [machinethink — Faster Neural Nets for iOS](https://machinethink.net/faster-neural-networks/) — MobileNetV1/V2 240+ fps 가능 (classifier 만)
- [machinethink — MobileNetV2+SSDLite with Core ML](https://machinethink.net/blog/mobilenet-ssdlite-coreml/) — Neural Engine 에서 SSDLite underperform 분석, COCO 90 classes 학습
- [Photoroom — Core ML iPhone 15 Performance Benchmark 2023](https://www.photoroom.com/inside-photoroom/core-ml-performance-benchmark-2023-edition) — 디바이스별 Core ML 추론 일반 벤치마크 (참고용)
- [hollance/coreml-survival-guide — MobileNetV2+SSDLite 변환 스크립트](https://github.com/hollance/coreml-survival-guide/blob/master/MobileNetV2+SSDLite/ssdlite.py)

## 다음 액션

1. **arkit-perception** 에 위임: `VNClassifyImageRequest` 를 `PerceptionCoordinator` 의 frame pipeline 에 연결 → 신뢰도 threshold (권장 시작값 0.5) 통과 label 을 `PerceivedObject` 로 publish.
2. **duck-behavior**: `chair`, `dining table`, `floor`, `bed`, `sofa/couch` label → 캐릭터 상태머신 전이 매핑 (Task #3 의 `DuckState` enum 과 연결).
3. **Duck-Head** 결정 사항:
   - (a) Phase 1 은 `VNClassifyImageRequest` 만으로 끝낼지, (b) 처음부터 Apple `YOLOv3 Tiny` 도 함께 통합할지
   - 추천: (a) 부터 시작 → 의자 매핑 정확도 부족 확인되면 (b) 추가. 두 모델 동시 통합은 over-engineering.
4. **iPad Air 5 실측 벤치마크 (Phase 1 종료 후)**: `XCTestCase + measure` 또는 단순 `CFAbsoluteTimeGetCurrent` 로 frame-당 추론 시간 측정 → 이 보고서 표에 채워넣기.
5. **라이선스 결정 (Phase 1 종료 시점)**: Ultralytics 채택 시 Enterprise License 견적 요청 + 대안 (Apple YOLOv3 Tiny / RF-DETR / 자체 학습 MobileNetV2+SSDLite) 비교.

## 미해결 (확인 필요)

- iPad Air 5 (M1, A15 NE) 에서 위 모델들의 실제 fps — 자료 부재. PoC 진입 후 실측만 정답.
- `VNClassifyImageRequest` 가 실제로 반환하는 furniture 라벨의 정확한 명세 — SDK 런타임에서 `VNClassifyImageRequest.knownClassifications(forRevision:)` 호출로 확인 가능 (이 호출은 코드 작업이므로 `arkit-perception` 위임).
- Apple `YOLOv3 Tiny` Core ML 의 Apple Sample Code License 본문 — 모델 zip 동봉 라이선스 파일 (`LICENSE.txt`) 확인 필요. 일반적으로 "for development purposes only" 제약 가능성.
- COCO 90 vs 80 차이 — MobileNetV2+SSDLite (COCO 90) 와 YOLO (COCO 80) 의 클래스 ID 매핑 차이.
