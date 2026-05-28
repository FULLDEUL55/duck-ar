# Vision AI 업그레이드 후보 비교 (VNClassifyImageRequest 보완)

> **⚠️ Superseded (2026-05-28)** — Duck-Head 가 Phase 1 액션을 "이동만" 으로 단순화하면서 본 보고서의 초점 (classification 보강) 이 우선순위에서 밀림. detection (bbox) + world 위치 추정 새 초점은 [`object-detection-depth.md`](./object-detection-depth.md) 로 이관. 본 파일은 classification 옵션 재검토 시점 참고용으로 보존.

_작성: ar-researcher / 2026-05-28 / Phase 1 데모 퀄리티 향상_

## 요약 (3줄)

- **1순위는 `Create ML 로 SUN397 / OpenImages indoor furniture custom classifier fine-tune` + 기존 `Apple 공식 YOLOv3 Tiny Core ML` 병행** — 라이선스 zero, M1 iPad 친화, "의자/책상/소파/바닥" 4-6 클래스만 좁혀 fine-tune 하면 VNClassifyImageRequest 의 1000-class scene analyzer 보다 confidence 가 훨씬 명확해짐.
- **Apple Visual Intelligence (iOS 26) 는 후보에서 제외** — 일반 vision API 가 아니라 App Intents 로 *앱 콘텐츠를 시스템 검색에 노출* 하는 용도. ARFrame 을 분류해 캐릭터 행동 트리거하는 우리 use case 와 불일치.
- **차선은 YOLO-World s** (open-vocabulary, "chair"/"table"/"couch" 텍스트 프롬프트 → detection). 단, **GPL-v3 + Tencent 상용 라이선스 필요** → 데모용/내부 PoC 한정.

## 비교 표

| # | 후보 | 라이선스 | Task | Open-vocab? | iPad Air 5 (M1) 가용성 | 모델 크기 | 정확도 (실내 furniture) | Core ML 변환 난이도 | 비고 |
|---|------|---------|------|-------------|----------------------|----------|------------------------|---------------------|------|
| 1 | **Apple Visual Intelligence (iOS 26)** | Apple SDK | (시스템 검색 통합, vision API 아님) | N/A | iPadOS 26 + Apple Intelligence 기기 한정 (**M1+ iPad OK**) | 0 MB (시스템) | N/A — 일반 인식 API 미제공 | N/A | **부적합** — App Intents 로 *앱 콘텐츠를 시스템 검색에 등록*. ARFrame 분류 불가 |
| 2 | **Apple Foundation Models Vision capabilities (iOS 26)** | Apple SDK | LLM (이미지 입력 지원 검증 필요) | △ | iPadOS 26 + Apple Intelligence (**M1+ iPad OK**) | 시스템 (~3B 모델) | (미확인 — vision-input 지원 범위 불확실) | N/A | Task #11 영역. 본 표 참고용 |
| 3 | **Apple 공식 YOLOv3 Tiny Core ML** | Apple Sample Code License | object detection | ❌ (COCO 80 fixed) | iPadOS 11+ — Phase 1 안전 | 35.4 MB | COCO 80 — chair / dining table / couch / bed / bottle / cup / book / laptop / tvmonitor 포함 | drag-and-drop | 라이선스 안전. 박스 좌표 제공 |
| 4 | **Create ML 로 custom indoor classifier fine-tune** | Apple SDK | classification (4-6 클래스 좁힘) | ❌ (정의 시 고정) | iPadOS 11+ | 통상 < 20 MB (transfer learning 기반) | **dataset 품질 결정** — 4 클래스 좁혀 학습 시 Top-1 > 90% 통상 (학술 사례 다수) | Create ML 앱 → drag .mlmodel | **1순위**. 라이선스 zero, 가장 가볍고 명확 |
| 5 | **YOLO-World s (Tencent / Ultralytics)** | **GPL-v3** (Tencent 상용 라이선스 별도) | open-vocab detection | ✅ ("chair" 텍스트 프롬프트) | 미검증 — Core ML 공식 변환 가이드 없음 | (미확인) — TFLite/ONNX 만 공식 지원 | YOLOv8s-world 37.4 mAP / YOLOv8x-worldv2 47.1 mAP (zero-shot COCO) | **변환 자체가 R&D** | Tencent 커머셜 라이선스 필요 |
| 6 | **Grounding DINO (HuggingFace)** | Apache 2.0 | open-vocab detection | ✅ | 미검증 — Core ML 변환 사례 없음. transformer 기반으로 M1 실시간 어려움 | (미확인 — 기본 변형 100+ MB 추정) | open-vocab SOTA 급, 단 GPU 환경 | **R&D 수준** | Dynamic-DINO 2025-07 fine-tune 으로 경량화 진전 있음 |
| 7 | **OWLv2 / OWL-ViT (Google)** | Apache 2.0 | open-vocab text-conditioned detection | ✅ | 미검증 — Core ML 변환 사례 없음 | base-patch16 ~600+ MB (FP32) | OWLv2 zero-shot detection SOTA 급 | **R&D 수준** | CLIP 백본 transformer — 모바일 부담 |
| 8 | **DINOv2 small + classifier head 자체 학습** | Apache 2.0 (Meta) | feature extraction → 별도 분류기 학습 | ❌ (분류기 정의 시 고정) | 커뮤니티 Core ML 변환 사례 있음 | small: 85 MB / base: 331 MB | feature 품질 매우 우수 — fine-tune head 와 dataset 에 의존 | small 변환 가능, 단 fine-tune 파이프라인 구축 비용 | 4번보다 강하지만 무게/복잡도 ↑ |
| 9 | **Apple Depth Pro** | Apple-amlr | monocular depth (semantic 보강) | N/A | Core ML 공식 변형 부재. 2.25 MP @ GPU 0.3 s → **M1 NE 실시간 불가** | (미확인) | depth quality SOTA | reference impl PyTorch | Phase 2 depth 검토 시 재고. Phase 1 semantic 보강에는 부적합 |
| 10 | **VNClassifyImageRequest** (현행, 비교 기준) | Apple SDK | classification (multi-label) | ❌ | 모든 iOS 11+ | 0 MB | Apple Neural Scene Analyzer — 1000+ classes, scene 광범위. **furniture 좁은 신뢰도 낮음** (현 데모 약점) | N/A | 기준선 |

## 추천

### 1순위 — Create ML custom indoor furniture classifier + Apple 공식 YOLOv3 Tiny 병행
- **이유**:
  1. **라이선스 zero** — Create ML 은 Apple SDK, YOLOv3 Tiny 는 Apple Sample Code License. App Store 배포 안전.
  2. **데모 quality 직격** — 현 문제 ("cord/monitor 잘못 잡힘, 의자/책상 안 잡힘") 의 원인은 1000-class 모델이 너무 광범위. 4-6 클래스 (chair / dining_table / couch / bed / floor / wall) 좁힘이 가장 직접적 해결.
  3. **M1 iPad 최적화 보장** — Apple 도구로 변환된 모델은 Neural Engine 가속 안정.
- **Phase 1 데이터셋**: SUN397 (397 scene classes — indoor 다수) 또는 OpenImages V7 (의자 / 책상 / 소파 bounding box 있음) 의 furniture subset → 클래스 4-6 개 추려 ~200-500 장씩 정리. Create ML 의 transfer learning 으로 < 30 분 학습.
- **결합 방식**:
  - YOLOv3 Tiny → 박스 좌표 (캐릭터를 의자 위 어디에 앉힐지)
  - Custom Create ML 분류기 → dominant scene label (확신도 높은 single label)
  - 두 출처가 동일 클래스 (chair) 동의 시에만 행동 트리거 → false positive 차단

### 차선 — YOLO-World s (내부 PoC / 데모 영상 한정)
- **이유**: open-vocabulary 가 매력적 — "rubber duck", "potted plant", "laptop" 등 새 라벨 즉시 추가 가능. 데모 영상 임팩트 강함.
- **제약**: **GPL-v3** + Tencent commercial license 필요 → App Store / 외부 배포 시 결제 또는 본 프로젝트 GPL 공개. Core ML 변환 자체가 R&D (TFLite/ONNX 만 공식). **시연 영상 촬영 후 폐기 권장 흐름**.

### 부정 추천 — Apple Visual Intelligence (iOS 26)
- 이름은 매력적이나 **개발자용 일반 vision API 가 아님**. 시스템 Visual Intelligence 가 표시하는 검색 결과에 우리 앱 콘텐츠를 진입시키는 App Intents 통합용. ARFrame 을 받아 분류해주는 함수 미제공.

## 통합 설계 스케치

```
ARFrame (every Nth frame, 예: 5 fps)
   │
   ├─► YOLOv3 Tiny Core ML  ──► [(label, bbox, conf)] (COCO 80)
   │
   └─► Custom Create ML cls ──► (dominant label, conf)  ──┐
                                                          │
   두 출처가 동일 furniture label & conf ≥ 0.7  ──────────┤
                                                          ▼
                                              PerceivedObject(label, bbox)
                                                          │
                                                          ▼
                                              DuckState 전이 (Task #3 의 상태머신)
```

- 캐릭터 행동 결정은 `PerceivedObject` dwell ≥ 1.5 s 후에만 트리거 → 분류기 jitter 흡수
- VNClassifyImageRequest 는 **제거 권장** (역할 중복) — custom 분류기로 대체

## 근거 (출처 + 접근 일자 2026-05-28)

- [Apple — Visual Intelligence 문서](https://developer.apple.com/documentation/VisualIntelligence) — App Intents 통한 앱 콘텐츠 통합
- [Apple — WWDC25 iOS What's New](https://developer.apple.com/wwdc25/guides/ios/) — Visual Intelligence + Foundation Models + Call Translation API
- [MacRumors — iOS 26 Visual Intelligence guide](https://www.macrumors.com/guide/ios-26-visual-intelligence/) — 사용자 기능 (스크린샷 분석, ChatGPT 연동), Apple Intelligence 호환 기기 한정
- [Ultralytics — YOLO-World docs](https://docs.ultralytics.com/models/yolo-world) — s/m/l/x 사이즈, COCO mAP 37.4-47.1, `set_classes()` 런타임 vocab 설정
- [AILab-CVC/YOLO-World GitHub](https://github.com/AILab-CVC/YOLO-World) — **GPL-v3 + Tencent commercial license (yixiaoge@tencent.com)**, reparameterized export 지원, TFLite/ONNX 만 공식 (Core ML 미언급)
- [arXiv: YOLO-World 2401.17270](https://arxiv.org/abs/2401.17270) — 35.4 AP / 52 FPS @ V100 (서버 GPU 기준)
- [HuggingFace — Grounding DINO docs](https://huggingface.co/docs/transformers/en/model_doc/grounding-dino), [arXiv 2303.05499](https://arxiv.org/pdf/2303.05499) — Apache 2.0, transformer 기반
- [PyImageSearch — Grounding DINO 2025-12 video tutorial](https://pyimagesearch.com/2025/12/08/grounding-dino-open-vocabulary-object-detection-on-videos/) — 일반 GPU 사용 가정
- [HuggingFace — OWLv2 docs](https://huggingface.co/docs/transformers/en/model_doc/owlv2), [google/owlv2-base-patch16](https://huggingface.co/google/owlv2-base-patch16) — Apache 2.0, zero-shot SOTA
- [Apple — DepthPro on HuggingFace](https://huggingface.co/apple/DepthPro), [GitHub apple/ml-depth-pro](https://github.com/apple/ml-depth-pro), [Apple ML Research](https://machinelearning.apple.com/research/depth-pro), [arXiv 2410.02073](https://arxiv.org/pdf/2410.02073) — Apple-amlr 라이선스, 0.3 s @ standard GPU for 2.25 MP, Core ML 미공시
- [HuggingFace — DINOv2 docs](https://huggingface.co/docs/transformers/model_doc/dinov2), [facebook/dinov2-small](https://huggingface.co/facebook/dinov2-small) — Apache 2.0, small 21 M params / 85 MB
- [Apple — Creating an Image Classifier Model](https://developer.apple.com/documentation/createml/creating-an-image-classifier-model) — Create ML transfer learning, iPadOS 15+ 프레임워크
- [Apple — MLImageClassifier](https://developer.apple.com/documentation/createml/mlimageclassifier) — ResNet-50 transfer learning baseline

## 다음 액션

1. **Duck-Head 결정 (택1)**:
   - (A) **권장**: Create ML custom 분류기 우선 — SUN397 indoor subset 또는 OpenImages furniture subset 로 4-6 클래스 fine-tune. **누가 데이터셋 정리 + 학습 ?** (수작업이 필요 — 사용자가 직접 또는 ar-researcher 가 후보 dataset URL 제공 후 사용자 다운로드)
   - (B) 임팩트 우선: YOLO-World s 변환 R&D 진행. 단 라이선스 제약 / Core ML 변환 비용 (수일~수주) 인지.
2. **ar-researcher 후속** (A 채택 시): SUN397 / OpenImages indoor furniture subset 다운로드 URL + 카테고리 매핑 + Create ML 입력 폴더 구조 문서 작성 (`docs/research/dataset-prep-indoor-furniture.md`).
3. **arkit-perception** 위임 (A 채택 시): Apple YOLOv3 Tiny `.mlmodel` 다운로드 + Xcode 통합 + `PerceptionCoordinator` 에 dual-source 분류 파이프라인 구현.
4. **VNClassifyImageRequest 제거**: custom 분류기 통합 시점에 PR 로 제거 (혼선 방지).

## 미해결

- Create ML 의 indoor 4-6 클래스 모델이 **실제 M1 iPad 에서 frame budget 안에 들어오는지** 실측 데이터 없음. transfer learning 기반 ResNet-50/MobileNetV2 보통 5-15 ms/frame 추정.
- YOLO-World 의 Core ML 변환 가능 여부 — 공식 가이드 부재. ONNX → coremltools 경로 시도해야 함 (R&D 수일~수주).
- Apple Foundation Models 의 **이미지 입력 (multimodal) 지원 범위** — 현 문서상 text-only? vision-grounded prompt 가능? Task #11 에서 더 확인.
- SUN397 / OpenImages 데이터셋 **라이선스 상업 사용 가능 여부** — SUN397 (research use), OpenImages (CC-BY) — 학습 산출물 배포 시 attribution 정책 확인 필요.
