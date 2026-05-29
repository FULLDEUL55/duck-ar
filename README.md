# duck-ar

iPad(Air 5, M1, **LiDAR 없음**)에서 카메라 영상 → 공간 인식(depth + 사물 인식) → 가상 캐릭터(오리)가 실제 사물을 인지하고 그 공간 안에서 자연스럽게 이동하는 모바일 AR 앱.

네이티브 Apple 스택: **Swift 6 · ARKit · RealityKit · Apple Vision · Core ML · ONNX Runtime**.

## 현재 상태 (Phase 1)

- ARKit world tracking + plane detection (horizontal/vertical)
- YOLOv3 Tiny (Core ML / Vision) 사물 인식 — COCO 가구류
- **Metric3D ViT-Small** monocular metric depth (ONNX Runtime iOS) → 사물 거리 정밀도, mesh-level occlusion, depth 기반 내비
- 오리 자연 이동/회전 (alignment-gated smoothstep, turn-first, mallard waddle)

## 빌드

```sh
cd code/DuckAR
xcodebuild build -scheme DuckAR -destination 'generic/platform=iOS' -allowProvisioningUpdates
```

Free Apple ID 서명(7일 provisioning) + Personal Team. iPad 실기 설치는 `xcrun devicectl device install app`.

## 모델 파일 (git 미포함)

`metric3d_vit_small.onnx`(~75MB)는 `.gitignore` 처리됨. 빌드 전 `code/DuckAR/DuckAR/Models/` 에 배치 필요.
원본: [Metric3D](https://github.com/YvanYin/Metric3D) (ViT-Small variant). 라이선스는 `Models/metric3d_vit_small.LICENSE` / `.NOTICE` 참조.

## 크레딧 / 라이선스

- **오리 3D 모델**: *Lowpoly Duck (animated)* by **wisdom3D** — **CC-BY 4.0** — https://sketchfab.com/3d-models/lowpoly-duck-animated-0242fe38361c4bdabadcfddb42eb3325 (배포 시 어트리뷰션 필수)
- **Metric3D**: 원저장소 라이선스 준수 (`Models/metric3d_vit_small.LICENSE`)
