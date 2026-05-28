# 오리 USDZ 무료 소스 비교

_작성: ar-researcher / 2026-05-27 / Phase 1 — Semantic Demo 용_

## 요약 (3줄)

- **Phase 1 (의자→앉기 prototype) 1순위는 Sketchfab `Lowpoly Duck (animated)` by wisdom3D** — 652 tri, 워크사이클 임베드, CC-BY 4.0. GLB → Reality Converter → USDZ 변환 후 RealityKit `Entity.load(named:)` 로 즉시 사용 가능.
- 차선은 **Poly Pizza `Mallard duck` by Poly by Google** (CC-BY 3.0, OBJ/glTF, 애니메이션 없음) — 룩이 "rubber duck" 보다 자연스럽지만 idle/walk 를 RealityKit / Reality Composer Pro 에서 직접 author 해야 함.
- Apple AR Quick Look Gallery 에는 **duck 모델이 없음** (animated `Hummingbird` 만 있음). Quaternius `Ultimate Animated Animal Pack` (CC0) 도 12 종 목록에 duck 미포함. → Sketchfab / Poly Pizza 외 신뢰 가능한 CC0 무료 duck 라인업 부재.

## 비교 표

| # | 모델 | 출처 | 라이선스 | Triangles | Vertices | Formats (네이티브) | 애니메이션 | 파일 크기 | 비고 |
|---|------|------|---------|-----------|----------|-------------------|-----------|----------|------|
| 1 | **Lowpoly Duck (animated)** | Sketchfab — wisdom3D | **CC-BY 4.0** | **652** | 384 | (미확인 — Sketchfab 상세 미노출, 통상 GLB/FBX/OBJ) | **walk cycle 포함, rigged** | (미확인) | Phase 1 1순위. 2,659 DL / 11.5k view |
| 2 | **Mallard duck** | Poly Pizza — Poly by Google | **CC-BY 3.0** | (미확인) | (미확인) | OBJ, glTF | 없음 (정보 없음) | (미확인) | 룩이 가장 mallard 다움. idle/walk 자체 author 필요 |
| 3 | **Duck free 3d model** | Sketchfab — Empire (@empire2ofearth) | **CC-BY 4.0** | 17,500 | 8,800 | (미확인) | 없음 | (미확인) | 폴리곤 과다 — Phase 1 모바일에는 부담. detail 필요 시점에 재고 |
| 4 | **Rubber duck** | Sketchfab — Ikki_3d | **CC-BY 4.0** | 3,500 | 1,900 | (미확인) | 없음 | (미확인) | 룩이 "toy rubber duck" — semantic 매핑 (의자→앉기) 에 톤 부적합 |
| 5 | **Duck (× 여러)** / **Rubber Duck** | Poly Pizza — Poly by Google 외 | CC-BY 3.0 (Poly by Google 기준) | (미확인) | (미확인) | OBJ, glTF | 없음 | (미확인) | 동급 대안. mallard 보다 단순 |
| 6 | **Hummingbird** (참고) | Apple AR Quick Look Gallery | Apple Sample (재배포 제한) | (미확인) | (미확인) | **USDZ 네이티브** | **animated** | (미확인) | duck 아님. animated bird 레퍼런스로만 |
| 7 | **Ultimate Animated Animal Pack** (참고) | Quaternius / Poly Pizza | **CC0** | (미확인) | (미확인) | FBX, OBJ, glTF, Blend | 동물별 12+ 애니메이션 | 종합 팩 | **duck 미포함** (Cow / Donkey / Deer / Alpaca / Bull / Fox / Shiba Inu / Stag / Husky / Wolf / White Horse / Horse) |
| 8 | **LowPoly Animated Animals** (참고) | Quaternius (itch.io) | CC0 | (미확인) | (미확인) | FBX, OBJ, Blend | Death / Idle / Jump / Run / Walk | 6.6 MB | **duck 미포함** (cow / horse / llama / pig / pug / +1) |

> Apple AR Quick Look Gallery 페이지 푸터: "no part of this site and no content provided may be copied, reproduced, republished, uploaded, posted, publicly displayed, encoded, translated, transmitted or distributed in any way...without Apple's express prior written consent." → **재배포·게시 제약**, 학습/프로토타입 한정.

## 추천

### 1순위 — Sketchfab `Lowpoly Duck (animated)` by wisdom3D
- **이유**: 4 후보 중 유일하게 임베드 애니메이션 (walk cycle) + rig 보유. 652 tri 로 M1 iPad 부담 zero. Phase 1 의 의자→앉기 시연 영상에 walk 사이클이 있으면 즉시 "살아있는 캐릭터" 인상 가능.
- **라이선스 액션**: CC-BY 4.0 → 앱 within / 크레딧 화면 / README 에 `wisdom3D — CC-BY 4.0 — <URL>` 표기 필수.
- **변환 파이프라인**: 다운로드 → Reality Converter (`File → Export → .usdz`) → `code/DuckAR/RealityAssets/duck.usdz` 배치. 머티리얼 깨짐 시 Reality Composer Pro 에서 보정.

### 차선 — Poly Pizza `Mallard duck` by Poly by Google
- **이유**: 룩이 가장 mallard 다움 (rubber duck 톤 아님). Poly by Google 출처라 라이선스 안정 (구글 종료 후 Poly Pizza 가 미러).
- **단점**: 애니메이션 없음 → walk/idle 을 Reality Composer Pro / `AnimationResource` 절차적으로 author. iPad 1차 시연에서 캐릭터가 정적이면 인상 약함.
- **라이선스 액션**: CC-BY 3.0 → 크레딧 표기.

## 근거 (출처 + 접근 일자 2026-05-27)

- Sketchfab — [Lowpoly Duck (animated) by wisdom3D](https://sketchfab.com/3d-models/lowpoly-duck-animated-0242fe38361c4bdabadcfddb42eb3325) — CC-BY 4.0, 652 tri / 384 vert, walk cycle 포함, Blender 2.92, 2021-05-11
- Sketchfab — [Duck free 3d model by Empire](https://sketchfab.com/3d-models/duck-free-3d-model-af6c2e8d23434554aa0c6342741a3ee6) — CC-BY 4.0, 17.5k tri / 8.8k vert, 애니 없음, 2022-11-05
- Sketchfab — [Rubber duck by Ikki_3d](https://sketchfab.com/3d-models/rubber-duck-f1de4fc390db4266a509b9739350512a) — CC-BY 4.0, 3.5k tri / 1.9k vert, 애니 없음, 2020-06
- Poly Pizza — [Mallard duck (Poly by Google)](https://poly.pizza/m/frSLi6b6Vid) — CC-BY 3.0, OBJ/glTF
- Poly Pizza — [Duck (Poly by Google)](https://poly.pizza/m/6HpauUCfIAb) — CC-BY 3.0, OBJ/glTF
- Poly Pizza — [Rubber Duck (Poly by Google)](https://poly.pizza/m/9pffFcv7LSm) — CC-BY 3.0, OBJ/glTF
- Poly Pizza — [duck 검색 결과 (17 모델)](https://poly.pizza/search/duck)
- Apple — [AR Quick Look Gallery](https://developer.apple.com/augmented-reality/quick-look/) — duck 없음, 애니메이션 bird 는 Hummingbird 만, Apple Sample 라이선스 제약
- Quaternius — [Ultimate Animated Animal Pack](https://quaternius.com/packs/ultimateanimatedanimals.html) / [Poly Pizza 미러](https://poly.pizza/bundle/Animated-Animal-Pack-ILAPXeUYiS) — CC0, FBX/OBJ/glTF/Blend, duck 미포함
- Quaternius — [Farm Animal Pack](https://quaternius.com/packs/farmanimal.html) — CC0, 7 종, duck 정보 미공개
- Quaternius — [LowPoly Animated Animals (itch.io)](https://quaternius.itch.io/lowpoly-animated-animals) — CC0, 6 종, duck 미포함
- 변환 워크플로 참고 — [Kodeco: Reality Converter & PBR Materials](https://www.kodeco.com/books/apple-augmented-reality-by-tutorials/v1.0/chapters/5-reality-converter-pbr-materials), [DC Engineer: Blender→RealityKit](https://dc-engineer.com/blender-to-realitykit/)

## 다음 액션

1. **사용자**: Sketchfab `Lowpoly Duck (animated)` (wisdom3D) 계정 로그인 후 GLB / FBX 다운로드 → 라이선스 명시 (CC-BY 4.0, attribution 필수) 확인.
2. **사용자**: Reality Converter (macOS) 로 GLB → USDZ 변환. 결과를 `code/DuckAR/RealityAssets/duck.usdz` 에 배치.
3. **xcode-builder**: Xcode 프로젝트에 USDZ 번들 리소스 등록.
4. **realitykit-scene** (Task #5 unblock): `Entity.load(named:"duck")` → 첫 감지된 horizontal plane anchor 에 부착 → 임베드 walk cycle 재생 검증.
5. **크레딧**: README + 앱 내 About 화면에 `Duck model: wisdom3D / CC-BY 4.0 / sketchfab.com/3d-models/lowpoly-duck-animated-0242fe38361c4bdabadcfddb42eb3325` 표기.

## 미해결 (확인 필요)

- Sketchfab 모델들의 정확한 다운로드 포맷 목록 (GLB / FBX / OBJ / BLEND) — Sketchfab 페이지가 로그인 후에만 다운로드 옵션 노출. 사용자가 다운로드 시점에 확인.
- Sketchfab 모델 파일 크기 — 다운로드 후 확인.
- Quaternius `Farm Animal Pack` 의 7 종 정확 목록 — 페이지에 미게재. duck 포함 가능성 있어 정밀 확인 필요 시 itch.io 다운로드 후 검증 가능.
