# Metric 3D Depth + SLAM 후보 비교

_작성: ar-researcher / 2026-05-28 / Phase 2 진입 시점 권장 평가_

## 요약 (3줄)

- **Phase 1 (오리 navigation, 이동만) 동안 metric depth / 외부 SLAM 신규 도입은 비권장.** 현재 ARKit world tracking + plane detection + bbox raycast 로 "의자 옆으로 오리가 걸어감" 시연 정확도 (0.05-0.2 m) 가 이미 충분. 추가 모델은 frame budget 만 갉아먹고 시각적 차이 미미.
- **Phase 2 진입 시 1순위 = Apple ARWorldMap** (라이선스 zero, ARKit 내장, NSKeyedArchiver 직렬화 + `initialWorldMap` 재시작). "오리를 의자 위에 두고 앱 재시작 → 같은 자리에서 오리가 기다림" 시연 임팩트 큼.
- **Phase 2 차선 (mesh-level occlusion 필요 시) = Depth Anything V2 Small Core ML** — Apple 공식 Core ML 카탈로그 통합 (2024-06), 25M params, iPhone 12 Pro Max **31.1 ms/frame**. M1 iPad 추정 25-35 ms 가능. **Apple Depth Pro 는 community Core ML 변환 진행 중이나 M1 iPad 실측 부재 → Depth Anything V2 small 이 현재 더 안전.**

## 비교 표 — Monocular Metric Depth (단안 metric)

| # | 모델 | 라이선스 | 모델 / 크기 | metric depth? | iPad M1 / Apple Silicon 자료 | Core ML 변환 상태 | ARKit 통합 난이도 | 비고 |
|---|------|---------|-------------|--------------|-----------------------------|------------------|------------------|------|
| 1 | **Depth Anything V2 small** | code Apache 2.0; weights: **Apache 2.0** (small/base), CC-BY-NC-4.0 (large) | small 25M params | △ (V2 자체는 affine-invariant relative — metric은 fine-tune 변형 / 카메라 intrinsics 결합 필요) | **iPhone 12 Pro Max 31.1 ms** (Apple 공식 Core ML small 변형 측정) | **Apple 공식 Core ML 카탈로그 포함** (2024-06, V1+V2) | 표준 `VNCoreMLRequest` 통합 + per-frame depth map | **현 시점 가장 통합 안전** |
| 2 | **Apple Depth Pro** | **Apple-amlr** (Apple research, 상용 가능성 명시 제한 — LICENSE 직접 확인 필요) | 600+ M params 추정 (paper 기반) | ✅ (true metric, scale 절대) | 표준 GPU 2.25 MP 0.3 s. **M1 iPad 추론 자료 부재**. community PR #45 가 1024×1024 float16 Core ML 시도 중 | **Apple 공식 카탈로그 = Depth Anything V2 만**. Depth Pro 자체 Core ML 변형은 community PR | 동일 (Core ML 변환 후) | true metric 매력적이나 M1 iPad 추론 fps 미검증 — 통합 비용 ↑ |
| 3 | **Metric3D v2** (YvanYin) | **BSD-2-Clause** ✅ | v2-S (DINOv2-Small + RAFT 4iter), v2-L, v2-g | ✅ true metric (zero-shot, KITTI/NYU 1위) | iOS 포트 없음. ONNX export 지원 — coremltools 경로 가능 | **R&D 수일~수주** | ONNX → coremltools 변환 필요 | 라이선스는 가장 깨끗. 변환 비용 부담 |
| 4 | **UniDepth / UniDepthV2** | (LICENSE 직접 확인 — github lpiccinelli-eth/UniDepth) | (미공시) | ✅ true metric | iOS / Apple Silicon 자료 없음 | iOS 포트 없음 | R&D | UniDepthV2 (2025-02 출시), self-promptable camera module |
| 5 | **MiDaS small / DPT** (참고) | MIT | small ~20-50 MB | ❌ (relative depth only) | Core ML 변환 사례 다수 | 검증됨 | 표준 | metric 아님 — 본 task 목적 불일치 |

## 비교 표 — Multi-view 3D Reconstruction (다중 뷰 dense)

| # | 모델 | 라이선스 | 입력 | 출력 | 모바일 가용성 | 비고 |
|---|------|---------|------|------|-------------|------|
| 6 | **DUSt3R** (NaverLabs) | **CC-BY-NC-SA 4.0** ❌ 상용 불가 | pair (2장) images | dense pointmap + camera | 서버 GPU 권장. on-device 미검증 | 상용 시 별도 라이선스 협상 필요 |
| 7 | **MASt3R** (NaverLabs) | **CC-BY-NC-SA 4.0** + 추가 dataset license (mapfree 제약) ❌ 상용 불가 | image pair | metric pointmap + local features | 동상 | DUSt3R + descriptor head + metric. 비상업만 |
| 8 | **MV-DUSt3R+** (CVPR 2025 Oral) | (DUSt3R 기반 — 같은 NC 가능성 — LICENSE 확인 필요) | sparse multi-view | scene in 2s | 서버 GPU | sparse view → single-stage 빠름 |
| 9 | **VGGT** (CVPR 2025 Best Paper, facebookresearch) | 가중치 **non-commercial**. **VGGT-1B-Commercial** 별도 신청 (2025-07, no military) — code 라이선스는 commercial-friendly | 1~100+ images | camera / depth / pointmap / tracks, < 1s | 서버 GPU. bfloat16 (Ampere+). **모바일/Core ML port 없음** | 1B params primary. VGGT-500M / 200M 출시 예정 → 향후 모바일 후보 |
| 10 | **COLMAP** (SfM) | BSD-3 | image set (배치) | sparse + dense | offline 배치 도구. 모바일 부적합 | 클래식 SfM. 본 task 목적 불일치 |

## 비교 표 — SLAM / Spatial Persistence

| # | 후보 | 라이선스 | iPad Air 5 (M1, LiDAR 없음) 가용 | ARKit 통합 | 효익 | 비용 |
|---|------|---------|--------------------------------|-----------|------|------|
| **11** | **Apple ARWorldMap** | Apple SDK ✅ | ✅ (LiDAR 무관 — ARKit world tracking 의 일부) | **즉시** — `getCurrentWorldMap()` → `NSKeyedArchiver` 직렬화 → 재시작 시 `ARWorldTrackingConfiguration.initialWorldMap` | 세션 영속 (앱 재시작 후 같은 위치) / 다중 세션 / 같은 공간 공유 가능성 | 0 — 라이브러리 / 라이선스 zero. relocalization 대기 UX 만 처리 |
| 12 | **Apple RoomPlan** (iOS 16+) | Apple SDK | **❌ iPad Air 5 LiDAR 없음 — 동작 불가** | — | (방 전체 furniture USDZ 자동 생성) | iPad Air 5 에서는 미지원 |
| 13 | **Apple Object Capture** (iOS 17+) | Apple SDK | LiDAR 권장 — 비LiDAR 동작 자료 일부 있으나 품질↓ | 별도 OS 메뉴 / API | 단일 객체 USDZ 자동 생성 | 본 task 목적과 영역 다름 (오리 캐릭터 = 사물 캡처 아닌 가상 캐릭터) |
| 14 | **클래식 SLAM** (ORB-SLAM3 / VINS-Mono) | GPL-3.0 / GPL-3.0 | 모바일 빌드 가능하나 R&D | ARKit 와 별도 트랙. **이중 트랙 의미 없음** (ARKit 가 이미 6-DoF VIO 제공) | 학술적 가치만 | 매우 큼. 비권장 |

## 추천

### Phase 1 (현재) — Metric 3D / 외부 SLAM 도입 비권장
- **이유**:
  1. 현재 시연 ("의자 옆 floor 로 오리 이동") 의 위치 정확도 요구가 0.05-0.2 m 수준. raycast (.estimatedPlane) 만으로 이미 충족.
  2. metric depth 추가 효익 = 거리감 정확도 (오리 walking speed scale). 그러나 ARKit 의 world coordinate (m 단위) 이미 metric — raycast hit transform 의 SIMD3 거리도 metric. **별도 monocular metric depth 모델이 제공하는 추가 정보가 거의 zero**.
  3. 비용 = Depth Anything V2 small 추가 25M params + 31 ms/frame iPhone 12 Pro Max (M1 iPad 추정 25-35 ms) → 5 fps detection 시 frame budget 25% 추가 소비. 효익 < 비용.
- **예외**: 만약 카메라 intrinsics 가 unstable 한 환경 (사용자 디바이스 lens 자동 보정 미흡) 이라면 metric depth 가 보조 신호. 현재까지 사용자 보고 없음 → 보류.

### Phase 2 진입 시 1순위 — Apple ARWorldMap (spatial persistence)
- **트리거**: 시연 임팩트 보강 단계. "오리를 의자에 두고 앱 종료/재시작 → 같은 자리에서 오리가 기다림" 데모.
- **이유**:
  1. 라이선스 / 라이브러리 / 의존성 zero — ARKit 표준 API.
  2. 구현 비용 가장 작음 — `NSKeyedArchiver` 직렬화 + 재시작 시 `initialWorldMap` 설정 + relocalization 대기 UX.
  3. 시연 임팩트 강함 — "같은 공간 재진입" 은 일반 사용자에게도 마법 같음.
  4. LiDAR 무관 — iPad Air 5 가용.
- **구현 윤곽** (xcode-builder + realitykit-scene 합동):
  ```swift
  // Save
  session.getCurrentWorldMap { map, _ in
      guard let map = map else { return }
      let data = try! NSKeyedArchiver.archivedData(
          withRootObject: map, requiringSecureCoding: true)
      try! data.write(to: worldMapURL, options: .atomic)
  }
  // Load
  let data = try Data(contentsOf: worldMapURL)
  let map = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: ARWorldMap.self, from: data)
  let config = ARWorldTrackingConfiguration()
  config.initialWorldMap = map
  session.run(config)
  // Listen to session(_:cameraDidChangeTrackingState:) for .normal after relocalization
  ```

### Phase 2 차선 — Depth Anything V2 Small Core ML (mesh-level occlusion 필요 시점에만)
- **트리거**: "오리가 의자 다리 뒤로 숨음" 같은 mesh occlusion 시연 단계.
- **이유**:
  1. **Apple 공식 Core ML 카탈로그 포함** (2024-06 등재) — 가장 검증된 모바일 monocular depth 옵션.
  2. small 25M params, iPhone 12 Pro Max **31.1 ms/frame** — M1 iPad 동급 또는 약간 빠름 추정.
  3. small/base 가중치 Apache 2.0 (large 만 CC-BY-NC-4.0) — 상용 안전.
- **제약**:
  1. V2 는 본질적으로 affine-invariant relative depth — true metric 변환은 camera intrinsics + scale 보정 필요. ARKit `ARCamera.intrinsics` 활용 가능.
  2. 가린 영역의 depth 만으로 occlusion mesh 자동 생성 안 됨 — depth → mesh 변환 또는 depth-aware shader 추가 구현 필요.

### 부정 추천 — DUSt3R / MASt3R / VGGT
- 모두 **non-commercial / 상용 제한 (또는 별도 신청)** — 본 프로젝트의 잠재 배포 (App Store 등) 와 충돌.
- VGGT 의 commercial 변형 (VGGT-1B-Commercial, 2025-07) 은 신청 필요 + military 금지 약관. 신청 통과해도 1B params → 모바일 부적합. VGGT-500M / 200M 출시 예정 시점 (미공시) 까지 보류.

### 부정 추천 — Apple RoomPlan
- iPad Air 5 LiDAR 없음 → 동작 자체 불가. iPhone Pro / iPad Pro 라인업 확장 시점에 재검토.

## Phase 별 통합 시점 권장

| 시점 | 추가할 것 | 추가 이유 | 추가 비용 |
|------|----------|----------|----------|
| **Phase 1 (현재)** | (없음) — 기존 ARKit + raycast 유지 | 시연 정확도 충족 | 0 |
| **Phase 1 종료 후, Phase 2 진입 직전** | **ARWorldMap 영속** | 시연 임팩트 보강. "오리가 같은 자리에서 기다림" | 작음 (수 시간 — 직렬화 + relocalization UX) |
| **Phase 2 mesh occlusion 단계** | **Depth Anything V2 Small Core ML** | 오리가 의자 다리/책상 다리 뒤로 가려짐 | 중 (수일 — Core ML 통합 + depth-aware shader 또는 mesh 생성) |
| **Phase 2 정밀 metric scale 단계 (선택)** | Apple Depth Pro Core ML (community PR 머지 후) | true metric 정확도 ↑ — Depth Anything V2 affine 한계 노출 시 | 중-대 (PR 머지 + M1 iPad 실측 + 통합) |
| **Phase 3 multi-device 공유 / Android 확장** | 외부 SLAM (Niantic Lightship / Google Cloud Anchors / VPS) 재평가 | ARKit 단독으로 cross-platform 불가 | 대 — 별도 보고서 필요 |

## 근거 (출처 + 접근 일자 2026-05-28)

### Monocular Metric Depth
- [Apple — Machine Learning Models 카탈로그](https://developer.apple.com/machine-learning/models/) — Depth Anything V2 small/base 공식 Core ML
- [AIBase — ByteDance Depth Anything V2 Apple Core ML 등재 (2024-06-25)](https://www.aibase.com/news/10179) — small 25M params, iPhone 12 Pro Max **31.1 ms**
- [DepthAnything/Depth-Anything-V2 GitHub](https://github.com/DepthAnything/Depth-Anything-V2) — NeurIPS 2024
- [DeepWiki — kaylorchen/Depth-Anything-V2 Apple Core ML](https://deepwiki.com/kaylorchen/Depth-Anything-V2/8.2-apple-core-ml)
- [Apple ML Research — Depth Pro](https://machinelearning.apple.com/research/depth-pro), [arXiv 2410.02073](https://arxiv.org/pdf/2410.02073), [HuggingFace apple/DepthPro-hf](https://huggingface.co/apple/DepthPro-hf) (Apple-amlr)
- [GitHub apple/ml-depth-pro](https://github.com/apple/ml-depth-pro), [PR #45 — 1024×1024 float16 Core ML](https://github.com/apple/ml-depth-pro/pull/45), [Issue #3 — iOS 포팅](https://github.com/apple/ml-depth-pro/issues/3)
- [Metric3D / Metric3Dv2 — YvanYin GitHub](https://github.com/yvanyin/metric3d) — BSD-2-Clause, v1-T/L + v2-S/L/g (DINOv2+RAFT), ONNX 지원
- [Metric3Dv2 project page](https://jugghm.github.io/Metric3Dv2/), [HuggingFace zachL1/Metric3D](https://huggingface.co/zachL1/Metric3D)
- [UniDepth GitHub (lpiccinelli-eth)](https://github.com/lpiccinelli-eth/UniDepth), [UniDepthV2 arXiv 2502.20110](https://arxiv.org/abs/2502.20110), [UniDepth CVPR 2024](https://openaccess.thecvf.com/content/CVPR2024/papers/Piccinelli_UniDepth_Universal_Monocular_Metric_Depth_Estimation_CVPR_2024_paper.pdf)
- [Survey: Monocular Metric Depth Estimation — arXiv 2501.11841](https://arxiv.org/html/2501.11841v4)

### Multi-view 3D
- [DUSt3R GitHub (naver)](https://github.com/naver/dust3r) — **CC-BY-NC-SA 4.0**
- [MASt3R GitHub (naver)](https://github.com/naver/mast3r) — CC-BY-NC-SA 4.0 + mapfree dataset 제약
- [MASt3R + MASt3R-SfM Tutorial — learnopencv](https://learnopencv.com/mast3r-sfm-grounding-image-matching-3d/)
- [DUSt3R 논문 — arXiv 2312.14132](https://arxiv.org/pdf/2312.14132), [MASt3R 논문 — arXiv 2406.09756](https://arxiv.org/pdf/2406.09756)
- [MV-DUSt3R+ project (CVPR 2025 Oral)](https://mv-dust3rp.github.io/)
- [VGGT — facebookresearch GitHub](https://github.com/facebookresearch/vggt) — CVPR 2025 Best Paper. VGGT-1B-Commercial 2025-07 신청. VGGT-500M/200M 출시 예정
- [VGGT 논문 — CVPR 2025 openaccess](https://openaccess.thecvf.com/content/CVPR2025/papers/Wang_VGGT_Visual_Geometry_Grounded_Transformer_CVPR_2025_paper.pdf)

### SLAM / Persistence
- [Apple — Saving and loading world data (ARWorldMap 가이드)](https://developer.apple.com/documentation/arkit/creating_a_persistent_ar_experience)
- [Shiru99 — AR Persistence Part-VIII](https://shiru99.medium.com/ar-persistence-with-arkit-realitykit-in-details-ar-with-ios-part-viii-28911d5cac5b), [Part-VII](https://shiru99.medium.com/ar-persistence-with-arkit-realitykit-ar-with-ios-part-vii-2dfd4fda446c)
- [AppCoda — ARKit Persistence Tutorial](https://www.appcoda.com/arkit-persistence/)
- [Apple — RoomPlan 디바이스 요구사항 (LiDAR 필수)](https://developer.apple.com/forums/thread/751207)
- [Volpis — Apple's RoomPlan Overview 2026](https://volpis.com/blog/apple-roomplan-overview/)
- [Apple — Augmented Reality Quick Look LiDAR 디바이스 호환표 (RoomSketcher)](https://help.roomsketcher.com/hc/en-us/articles/29949063142045-Does-My-Phone-or-Tablet-Have-LiDAR)

## 다음 액션

1. **Duck-Head 결정**:
   - (A) **권장 — Phase 1 는 현 raycast 파이프라인 유지. metric depth / 외부 SLAM 미도입.** Task #18 (오리 polish) 와 #16 (detection + raycast 통합) 완료까지 본 분야 추가 작업 없음.
   - (B) Phase 1 추가 임팩트 우선 시 — ARWorldMap 영속을 Phase 1 종료 직전에 끼워넣기 (수 시간 작업).
2. **Phase 2 진입 시점 ar-researcher 후속**:
   - Depth Anything V2 small Core ML 의 **M1 iPad 실측 latency** (Apple 공식 카탈로그 .mlpackage 다운로드 + 단발 측정).
   - Apple Depth Pro Core ML PR #45 머지 / 완성도 / 최종 모델 크기 / M1 iPad 추론 fps 재조사.
   - 그 시점에 본 보고서 `Phase 2 추가 채택 후보` 표 갱신.
3. **realitykit-scene + xcode-builder 합동** (B 채택 또는 Phase 2 진입 시):
   - `ARWorldMap` 직렬화 / 복원 / relocalization UX (로딩 spinner + "방 둘러보세요" 안내).
   - 저장 경로 (앱 Documents) + 다중 슬롯 (`Map_RoomA.arworldmap` 등) 구조.

## 미해결

- **Apple Depth Pro M1 iPad 추론 latency** — community PR #45 의 1024×1024 float16 패키지 머지 후 측정 필요. 현 시점 비교 데이터 부재.
- **Depth Anything V2 V2 의 metric 변환 절차** — 본질이 affine-invariant relative depth → ARKit `ARCamera.intrinsics` + 단일 ground plane scale 앵커링 결합 절차 미정리. Phase 2 진입 시 별도 PoC 필요.
- **Apple Depth Pro 의 Apple-amlr 라이선스 본문** — 상용 사용 가능 범위 (research-only? 일부 commercial OK?). HuggingFace 모델 카드 / LICENSE 직접 확인 필요.
- **Metric3D v2 의 Core ML 변환 결과 검증** — BSD-2-Clause 로 라이선스는 가장 깨끗하나 iOS 포트 사례 없음. coremltools 경로 PoC 가 R&D 수일~수주.
- **VGGT-500M / VGGT-200M 출시 시점** — Phase 3 multi-view 시점에 재후보. 현재 1B 만 출시.
- **ARWorldMap relocalization 실패율** — 시연 환경 (사무실/거실) 의 실제 relocalization 안정성. 조명 변화 / 가구 이동 시 실패 가능. 실측 필요.
