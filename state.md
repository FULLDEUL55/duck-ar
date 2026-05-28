# Duck-Head — Current State

_Last updated: 2026-05-27 / Apple Developer Program 보류 → Free Apple ID 로 시작_

## Active Tasks (Phase 1 Semantic Demo)

- [x] Apple Developer Program 가입 — **보류** (Phase 1 동안 불필요, 무료 Apple ID 로 충분)
- [x] **사용자 액션**: Xcode → Settings → Accounts → Apple ID 추가 (Free 계정) — 완료
- [x] Xcode 버전 확인 — **Xcode 26.5 / iOS SDK 26.5** (요구치 15+ 크게 상회)
- [x] **사용자 액션**: iPad Air 5 USB-C 케이블 연결 + 신뢰 — iPad13,16 인식 OK
- [x] `code/DuckAR.xcodeproj` 부트스트랩 (SwiftUI App 템플릿, Bundle: `com.fulldeul.DuckAR`, Team: `4BB378R83H` Personal)
- [x] `INFOPLIST_KEY_NSCameraUsageDescription` 추가 (project.pbxproj)
- [x] `ContentView.swift` — RealityKit `ARView` + `ARWorldTrackingConfiguration` + plane detection + debug 시각화
- [x] iPad Air 5 실기 빌드 성공 (`xcodebuild build ... -allowProvisioningUpdates`)
- [x] iPad Air 5 실기 설치 성공 (`xcrun devicectl device install app`)
- [x] **사용자 액션**: iPad 인증서 신뢰 완료
- [x] **Phase 1 베이스라인 동작 확인** — 카메라 영상 + horizontal/vertical plane 감지 + world origin + environment texturing + person segmentation 모두 정상
- [ ] 오리 USDZ 모델 소스 확보 (무료 / 자체 제작) → 사용자 결정 필요
- [ ] Core ML 사물 분류 모델 후보 평가 (YOLOv8n / MobileNetV3 / Apple 사전훈련) → **`ar-researcher` 리서치 → Duck-Head 결정 → `arkit-perception` 통합**
- [ ] 오리 USDZ 무료 소스 탐색 (Sketchfab CC0 / Apple AR Quick Look / Poly Pizza) → `ar-researcher`
- [ ] semantic 인식 → 캐릭터 행동 1개 프로토타입 (의자→앉기) → `duck-behavior`

## Recent Decisions (last 7 days)

- 2026-05-27: **스택 확정** — Swift + Xcode + ARKit + RealityKit + Apple Vision + Core ML 네이티브
- 2026-05-27: **디바이스 확정** — iPad Air 5 (M1, LiDAR 없음, 후면 광각 1개). Scene Reconstruction 불가.
- 2026-05-27: **Phase 1 = semantic 우선** — 사물 분류 → 캐릭터 행동 매핑. mesh-level occlusion 은 Phase 2.
- 2026-05-27: **Phase 2 depth 전략** — monocular ML depth (Apple Depth Pro / DepthAnything-v2 small) Core ML 변환 후 검토.
- 2026-05-27: **확장 로드맵** — iPad Air 5 (Phase 1) → iPhone (Phase 2) → Android (Phase 3, Unity AR Foundation 재설계 검토)
- 2026-05-27: **도메인 서브 에이전트 4명 정의** — xcode-builder / arkit-perception / realitykit-scene / duck-behavior
- 2026-05-27: **Apple Developer Program 가입 보류** — Phase 1 (semantic 데모) 은 무료 Apple ID 로 충분. 7일 재서명 부담만 감수. TestFlight / App Store 필요 시점에 ₩129,000/년 결제 재검토.
- 2026-05-27: **Xcode 환경 확인** — Xcode 26.5 / iOS SDK 26.5 / Swift 6 설치 완료. Free Apple ID Xcode 로그인 완료.
- 2026-05-27: **Xcode 26 ARKit 템플릿 변경 인지** — "Augmented Reality App" 별도 템플릿 제거됨. 일반 iOS App 템플릿 + ARKit/RealityKit import 방식으로 부트스트랩 예정.
- 2026-05-27: **5번째 서브 에이전트 추가** — `ar-researcher` (리서치 전담). 코드 수정 없이 모델 후보·USDZ 소스·API 동향 탐색 후 `docs/research/*.md` 보고서 생성. 도구 셋에 WebFetch / WebSearch 포함.
- 2026-05-26: 프로젝트 부트스트랩 — Duck-Head 페르소나 정의
- 2026-05-26: 시작 캐릭터 = 오리 (mallard duck). 후일 변경 가능

## Blockers

- Apple Developer 계정 상태 확인 필요 (실기 배포 vs 시뮬레이터만)
- Xcode 설치/버전 미확인
- 오리 USDZ 에셋 소스 미정

## Team (Active)

- 팀 `duck-ar` (config: `~/.claude/teams/duck-ar/config.json`) — 멤버 5명
- 완료 task: #1 #2 (ar-researcher), #3 #7 (duck-behavior), #4 #6 (arkit-perception)
- 대기: #5 (USDZ 결정 + 사용자 배치 후 → realitykit-scene)
- idle: 5명 전원

## ar-researcher 추천 결과 (2026-05-27)

- **USDZ 1순위**: Sketchfab `Lowpoly Duck (animated)` by wisdom3D — CC-BY 4.0, 652 tri, walk cycle 임베디드. GLB → Reality Converter 로 USDZ 변환 필요. **사용자 직접 검토 후 결정 보류 중**. 보고서: `docs/research/duck-usdz-sources.md`
- **Core ML 채택**: Apple 내장 `VNClassifyImageRequest` (라이선스 zero, 1000+ classes). Ultralytics YOLOv8n 은 AGPL-3.0 라 상용 배포 보류. 보고서: `docs/research/coreml-object-detection.md`

## Next Session Should

1. `ar-researcher` 에 위임: 오리 USDZ 무료 소스 비교 (Sketchfab CC0 / Apple AR Quick Look 갤러리 / Poly Pizza) → `docs/research/duck-usdz-sources.md`
2. Duck-Head 후보 선택 → 에셋 다운로드 → `assets/` 에 보관
3. `realitykit-scene` 에 위임: 오리 Entity 로드 + 첫 감지된 horizontal plane 위에 배치 + idle 애니메이션
4. `ar-researcher` 에 위임: Core ML 사물 분류 모델 비교 (YOLOv8n / MobileNetV3 / Apple `MLImageClassifier`) → `docs/research/coreml-object-detection.md`
5. (병렬) `duck-behavior` 에 위임: `DuckState` enum + 기본 상태머신 골격 (Idle / Walking / LookingAround)

## Inbox

- 확인: `ls /Users/fulld/dev/.inbox/Duck-Head/`

## 도메인 서브 에이전트 (참조)

| 이름 | 1차 위임 영역 | 영역 |
|------|---------------|------|
| xcode-builder | `.xcodeproj`, SPM, signing, 빌드, TestFlight | 구현 |
| arkit-perception | ARSession, Vision, Core ML 사물 분류 | 구현 |
| realitykit-scene | USDZ, 머티리얼, 조명, anchor entity | 구현 |
| duck-behavior | 상태머신, semantic→행동, 애니메이션 블렌딩 | 구현 |
| ar-researcher | 모델 비교·USDZ 소스 탐색·API 동향·벤치마크 → `docs/research/*.md` | 리서치 |
