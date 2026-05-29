# Duck-Head — Current State

_Last updated: 2026-05-29 / Metric3D depth 파이프라인 통합 완료 (ORT 경로)_

## Active Tasks

- [x] Phase 1 베이스라인 — ARKit world tracking + plane detection + debug 시각화 (iPad 실기 확인됨)
- [x] 오리 USDZ 확보 — `assets/duck.usdz` (Sketchfab wisdom3D, **CC-BY 4.0, 크레딧 필수**)
- [x] Core ML 사물 분류 — YOLOv3 Tiny VNCoreMLRequest (COCO 가구류 keep list)
- [x] 자연스러운 오리 이동/회전 — DuckNavigator alignment-gated smoothstep, turn-first, mallard waddle
- [x] **Metric3D Small depth — ONNX Runtime iOS** (CoreML 변환 차단 우회). DepthFrame(미터) publish
- [x] 사물 거리 정밀도 — bbox 중심 metric depth → worldTransform
- [x] Mesh-level occlusion — depth 역투영 occlusion proxy mesh (오리가 사물 뒤로 가려짐)
- [x] depth 기반 내비 공간 확장 — DepthNavigationField
- [x] **GitHub repo 생성 + push** — `git@github.com:FULLDEUL55/duck-ar.git`, main 전체 히스토리 push 완료 (HEAD ddad0dc, README 포함)
- [ ] iPad 실기 검증 — builds/ 아카이브들을 사용자 검토 시점에 하나씩 설치/확인
- [ ] depth 정확도/스케일 실측 튜닝 (실기 검증 후)

## Recent Decisions

- 2026-05-29: **Metric3D = ONNX Runtime iOS 경로** — CoreML 변환이 ViT multi-head attention rank-7 reshape(CoreML rank<=5)로 차단. ORT framework 1.24.2 arm64 임베드. SPM 모듈명 `OnnxRuntimeBindings`.
- 2026-05-29: **액션 = 이동만** — 앉기/쪼기 없음 (사용자 지시). 오리는 인식 사물 쪽으로 자연 이동.
- 2026-05-29: **iPad 실기 검증 보류 정책** — 빌드는 여러 개 builds/<tag>/ 로 아카이브해두고, 사용자가 검증 가능할 때 하나씩 검토.
- 2026-05-27: 스택/디바이스/Phase 전략 확정 (complete.md 참조).

## Build Archives (iPad 실기 검토 대기)

- `builds/task1-onnx-bundle-20260529/` — onnx 번들 포함 베이스
- `builds/task1-ort-linked-20260529-1125/` — ORT 심볼 링크 검증
- `builds/depth-pipeline-integrated-20260529-1129/` — depth 추론+occlusion+motion 통합 (258M)
- `builds/depth-occlusion-navi-*` — 최종 (occlusion 실 depth 소비 + navi field)

## Blockers

- GitHub `FULLDEUL55/duck-ar` repo 미생성 (gh CLI/PAT 없음 → 사용자 1회 액션 필요). 생성 후 `git push -u origin main`.
- depth 스케일/정확도는 실기 검증 전까지 미실측.

## Team (Active)

- 팀 `duck-ar` (config: `~/.claude/teams/duck-ar/config.json`) — 멤버 5명 (lead Duck-Head + 4 구현 + ar-researcher 온디맨드)
- 완료 task: #1 (xcode-builder) #2 (arkit-perception) #3 (realitykit-scene) #4 (duck-behavior)
- 전원 idle.

## Next Session Should

1. GitHub repo 생성 확인되면 `git push -u origin main`.
2. 사용자 iPad 검증 → builds/ 아카이브 하나씩 설치, depth 동작/오리 자연스러움 피드백 수집.
3. 피드백 기반 DepthFrame 스케일·occlusion 해상도·DuckMotionConfig 튜닝.

## Inbox

- 확인: `ls /Users/fulld/dev/.inbox/Duck-Head/`
