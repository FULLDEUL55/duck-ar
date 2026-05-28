# LLM Behavior — 정적 dict → LLM 의사결정 업그레이드 후보 비교

> **⚠️ Deferred (2026-05-28)** — Duck-Head 가 Phase 1 액션을 "이동만" 으로 단순화하면서 LLM 의사결정 필요성 보류. 정적 dict 매핑으로 충분. 본 보고서는 향후 행동 다양화 (sitting / pecking / lookingAround 등) 시점에 재참조용으로 보존. 액션 단순화 결정 자체는 [`object-detection-depth.md`](./object-detection-depth.md) 통합 설계 스케치 참조.

_작성: ar-researcher / 2026-05-28 / Phase 1+ 캐릭터 행동 결정 LLM 화_

## 요약 (3줄)

- **1순위는 Apple Foundation Models (iOS 26)** — ~3B on-device, M1 iPad 지원, `@Generable` / `@Guide` 매크로로 Swift struct constrained output (JSON schema 강제), 라이선스 zero / 호출 비용 zero. iPhone 15 Pro 기준 0.6 ms TTFT + 30 tok/s 보고 — M1 iPad 도 20-40 tok/s 추정으로 단발 의사결정 (10-50 tokens) 100-200 ms 안에 완료 가능.
- **현실적 제약**: Foundation Models 는 **이미지 입력 미지원 (iOS 26.3 기준)** — vision 결과 (label + conf) 를 text prompt 로 직렬화해 LLM 에 주입하는 설계가 필요. 매 프레임 호출 불가 → `PerceivedObject` dwell ≥ 1.5 s 또는 신규 객체 진입 시점 트리거만.
- **차선은 Gemma 3 270M (INT4 양자화 ~125 MB) on MLX** — Foundation Models 가 우리 iPad 에서 사용 불가하거나 latency 가 과한 경우. 단, 추론 품질 / 라이선스 (Gemma terms) 검증 추가 필요.

## 비교 표

| # | 후보 | 라이선스 | 크기 (디스크) | RAM 사용 (추정) | iPad M1 latency / throughput | iOS 통합 난이도 | Structured output | 추천 사용 빈도 | 비고 |
|---|------|---------|--------------|----------------|------------------------------|-----------------|-------------------|----------------|------|
| 1 | **Apple Foundation Models** (iOS 26) | Apple SDK / Apple Intelligence | 0 MB (시스템) | OS 관리 (~수 GB) | iPhone 15 Pro 0.6 ms TTFT + **30 tok/s**; M1 iPad **20-40 tok/s 추정** (general LLM bench) | **단순** — `LanguageModelSession.respond(to:generating:)` Swift API | **@Generable / @Guide** (JSON schema 강제, Swift struct 직접 디코드) | 새 `PerceivedObject` 진입 시 1회, 또는 dwell 1.5 s 후 | **이미지 입력 미지원** (iOS 26.3) — vision 결과 text 직렬화 필요. M1+ iPad / Apple Intelligence 활성 필요 |
| 2 | **Gemma 3 270M (INT4)** | Gemma Terms of Use (상용 OK, 일부 제약) | **~125 MB** (INT4) | < 500 MB 추정 | Pixel 9 Pro: 25 대화 = 0.75% 배터리. iOS 직접 측정 자료 없음 | **MLX-Swift** 또는 llama.cpp 통합 — 의존성 추가 필요 | function-calling fine-tune (`FunctionGemma`) 존재, JSON 가능 | 같음 | 가장 작은 진지한 후보. iOS 공식 지원 미명시 (커뮤니티 변환) |
| 3 | **Phi-4 mini (3.8B)** | MIT (Microsoft) | ~2-4 GB (INT4 quant 기준) | 수 GB | iPhone 14/15 (6 GB RAM, Metal) **15-25 tok/s** | llama.cpp Metal 백엔드 / MLX | 일반 JSON prompt 지원 (constrained 아님) | 같음 | 품질 ↑ 하지만 RAM/디스크 부담. iPad Air 5 (8 GB RAM) 빠듯 |
| 4 | **TinyLlama 1.1B** | Apache 2.0 | ~700 MB (INT4) | ~1 GB | iPhone (Metal) 30-50 tok/s 추정 | llama.cpp | 일반 prompt | 같음 | 추론 품질 낮음 — 단순 enum 선택 정도만 신뢰 |
| 5 | **DistilGPT2 / GPT-2 small** | MIT | ~50 MB | < 200 MB | 매우 빠름 | Core ML 변환 가능 | constrained 없음, prompt 만 | 같음 | 추론 품질 매우 낮음 — 캐릭터 행동 결정 신뢰 불가 |
| 6 | (참고) **Claude Haiku 4.5** | Anthropic API | 클라우드 | — | 100-500 ms + 네트워크 | URLSession + API key | JSON mode + tools | 같음 | 비용 발생 + offline 데모 불가. 사내 영상용 PoC 가능 |
| 7 | (참고) **Gemini Flash** | Google API | 클라우드 | — | 100-300 ms + 네트워크 | URLSession + API key | function calling | 같음 | 동상 |
| 8 | (참고) **GPT-4o mini** | OpenAI API | 클라우드 | — | 100-400 ms + 네트워크 | URLSession + API key | JSON mode + tools | 같음 | 동상 |

## 추천

### 1순위 — Apple Foundation Models (iOS 26)
- **이유**:
  1. **라이선스 zero / 호출 비용 zero** — Apple Intelligence 시스템 모델 직접 사용 ("no cost per request").
  2. **Swift 통합 가장 자연스러움** — `LanguageModelSession.respond(to:generating:)` + `@Generable` 매크로로 `DuckBehaviorDecision` struct 를 LLM 출력으로 직접 디코드. JSON 파싱 / 토큰 수동 처리 불필요.
  3. **on-device + offline** — 모바일 AR 데모의 핵심 가치 (네트워크 의존 zero) 와 정렬.
  4. **iPad Air 5 (M1) 호환** — Apple Intelligence 가 M1+ iPad 에서 활성 가능 (사용자가 Settings 에서 Apple Intelligence 활성 필요).
  5. **latency 충분히 작음** — 단발 행동 결정 (10-50 tokens output) 200 ms 내 완료 추정. dwell 트리거 빈도 (수 초당 1회) 와 충돌 없음.

#### 통합 설계 스케치

```swift
import FoundationModels

@Generable
struct DuckBehaviorDecision {
    @Guide(description: "Target state for the duck character",
           .anyOf(["idle", "walking", "sitting", "pecking", "lookingAround"]))
    let targetState: String

    @Guide(description: "Short rationale (≤ 60 chars)")
    let reason: String
}

actor DuckBehaviorPlanner {
    private let session = LanguageModelSession()

    func decide(for perceived: [PerceivedObject]) async throws -> DuckBehaviorDecision {
        let scene = perceived
            .map { "\($0.label) (conf=\(String(format: "%.2f", $0.confidence)))" }
            .joined(separator: ", ")
        let prompt = """
        The duck character is in an AR scene. Camera currently detects: \(scene).
        Pick the most natural single next action for the duck.
        """
        return try await session.respond(to: prompt, generating: DuckBehaviorDecision.self).content
    }
}
```

- **호출 시점** (매 프레임 X):
  - 신규 `PerceivedObject` 진입 (예: 새 의자 인식) → 즉시 1회
  - 현 객체 dwell ≥ 1.5 s 후 행동 재평가 1회
  - 캐릭터 현 행동 완료 (Walking → 도착) 직후 1회
- **Fallback 정책**:
  - LLM call 250 ms 초과 → cancel 후 기존 정적 dict 매핑 (`FurnitureClass → DuckState`) 사용
  - `targetState` 가 enum 5 항목 밖이면 (constraint 우회 시) 정적 매핑으로 폴백
  - Apple Intelligence 비활성 디바이스 → `SystemLanguageModel.default.availability` 체크 → 정적 매핑 only 모드

#### 미해결 / 검증 필요
- 사용자 iPad Air 5 의 **Apple Intelligence 활성 상태** 확인. (Settings → Apple Intelligence — 약 4 GB 모델 다운로드 필요)
- M1 iPad 실측 latency — Foundation Models 의 공식 M1 iPad 토큰/초 벤치 부재. 사용자 디바이스에서 단발 측정 필요.
- `@Generable` `.anyOf` enum constraint 실제 가용 시그니처 (`@Guide` 시그니처 변경 가능성, Xcode 26 베타에서 확정).

### 차선 — Gemma 3 270M INT4 via MLX-Swift
- **이유**:
  1. Foundation Models 비활성/품질 부족 시 fallback. **125 MB** 로 앱 번들 가능 범위.
  2. MLX-Swift 가 Apple Silicon (M1 iPad 포함) 최적화 — Metal/CPU 활용. 100+ tok/s 가능 예상.
  3. FunctionGemma fine-tune 으로 JSON 출력 학습 가능.
- **제약**:
  1. **라이선스** — Gemma Terms of Use. 상용 사용 가능하나 비차별 약관 / Google 정책 변경 리스크.
  2. iOS 공식 지원 미명시 — 통합 자체가 추가 R&D (수일).
  3. 추론 품질 — 270M params 는 복잡한 추론 부족. 단순 의사결정 (5 enum 중 1) 에는 충분 추정.

### Cloud API (참고) — 사내 데모 영상 한정
- Claude Haiku 4.5 / Gemini Flash / GPT-4o mini 모두 가능. JSON mode + function calling 으로 동일 struct 매핑.
- **데모 영상 촬영 시 일회성** — 1순위는 어디까지나 on-device Foundation Models. 모바일 AR 의 가치 명제 (offline / privacy) 와 충돌.

## 근거 (출처 + 접근 일자 2026-05-28)

- [Apple — Foundation Models 문서](https://developer.apple.com/documentation/FoundationModels) — `LanguageModelSession`, `respond()`, `streamResponse()`, `@Generable`, `@Guide`
- [Apple — Guided generation (Generating Swift data structures)](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation?changes=_10_5) — JSON Schema 기반 type-safe Swift struct 디코딩
- [Apple — Foundation Models adapter training](https://developer.apple.com/apple-intelligence/foundation-models-adapter/) — LoRA 어댑터 학습 (도메인 특화)
- [Apple Newsroom 2025-09 — Foundation Models framework](https://www.apple.com/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/) — Swift 3 lines, 3B 모델, 비용 zero
- [Apple ML Research — Introducing Apple Foundation Models](https://machinelearning.apple.com/research/introducing-apple-foundation-models) — iPhone 15 Pro **0.6 ms TTFT + 30 tok/s** (token speculation 적용 전), 3B 모델이 Phi-3-mini / Mistral-7B / Gemma-7B / Llama-3-8B 능가 보고
- [Apple Intelligence Foundation Language Models — arXiv 2507.13575](https://arxiv.org/html/2507.13575v3) — 모델 카드 / 학습 방법론
- [Apple — WWDC25 "Deep dive into Foundation Models framework" (301)](https://developer.apple.com/videos/play/wwdc2025/301/)
- [createwithswift.com — Exploring Foundation Models framework](https://www.createwithswift.com/exploring-the-foundation-models-framework/) — 멀티모달 일부 (text/vision/multimodal) 언급
- [remio.ai — Integrating On-Device AI Guide iOS 26](https://www.remio.ai/post/integrating-on-device-ai-a-guide-to-apple-s-foundation-models-for-ios-26) — **iOS 26.3 기준 이미지 입력 미지원 (text only)** 보고
- [InfoQ 2025-07 — Apple Foundation Models iOS 26 details](https://www.infoq.com/news/2025/07/apple-foundation-models-ios26/)
- [Trail of Bits Blog — Understanding Apple's On-Device Models](https://blog.trailofbits.com/2024/06/14/understanding-apples-on-device-and-server-foundations-model-release/) — low-bit palettization, LoRA mixed 2-bit/4-bit, 3.7 bpw avg
- [ModelPiper — Local LLM benchmarks on Apple Silicon M1-M4](https://modelpiper.com/blog/local-llm-benchmarks-apple-silicon) — M1 8 GB: 0.8B/3B 모델 20-40 tok/s; M1 16 GB: 3-9B 40-80 tok/s
- [LLM Check — Apple Silicon LLM benchmarks](https://llmcheck.net/benchmarks)
- [Google Developers — Introducing Gemma 3 270M](https://developers.googleblog.com/en/introducing-gemma-3-270m/) — 270M params, INT4 양자화 **125 MB**, 0.75% 배터리/25 대화 (Pixel 9 Pro), MLX 지원
- [InfoQ 2026-01 — FunctionGemma 270M function calling edge variant](https://www.infoq.com/news/2026/01/functiongemma-edge-function-call/) — 함수 호출 fine-tune
- [Local AI Master — Phi-4 Mini](https://localaimaster.com/models/phi-4-mini) — iPhone 14/15 Metal **15-25 tok/s**, 3.8B params, 200K vocab, GQA, MIT 라이선스
- [microsoft/Phi-4-mini-instruct HuggingFace](https://huggingface.co/microsoft/Phi-4-mini-instruct)
- [DEV — Run LLMs Locally on iPhone 2026](https://dev.to/alichherawalla/how-to-run-llms-locally-on-your-iphone-in-2026-completely-offline-no-subscription-4b3a)

## 다음 액션

1. **사용자 액션 (Duck-Head 결정 전제)**: iPad Air 5 (M1) 의 **Settings → Apple Intelligence & Siri** 활성 + 모델 다운로드 완료 여부 확인. 비활성 시 Foundation Models 사용 불가 → 차선 (Gemma 3 270M MLX) 검토.
2. **Duck-Head 결정**:
   - (A) **권장**: Foundation Models 1순위 채택. 단발 의사결정 latency 사용자 디바이스에서 실측 (단일 호출 ms 측정 + 50 회 평균).
   - (B) Foundation Models 미가용 시: Gemma 3 270M MLX 통합 R&D (수일).
3. **duck-behavior 위임 (A 채택 시)**:
   - `DuckBehaviorDecision` `@Generable` struct 정의 + `DuckBehaviorPlanner` actor 추가.
   - 기존 정적 dict 매핑 (`Task #3` 의 `DuckState` 전이) 을 **fallback** 으로 보존. LLM call timeout 250 ms 또는 enum 위반 시 폴백.
   - 호출 트리거: 신규 객체 진입 / dwell ≥ 1.5 s / 행동 완료 직후 — 매 프레임 호출 금지.
4. **arkit-perception 인터페이스 합의**: `PerceivedObject` 스트림에 `label / confidence / bbox / firstSeenAt / lastSeenAt` 표준화 → `DuckBehaviorPlanner` 가 dwell 계산 가능.
5. **계측**: 첫 통합 후 LLM call latency / 폴백 발동률 / 응답 enum 위반률 측정 → 본 보고서 표 업데이트.

## 미해결

- **Foundation Models 의 vision multimodal 지원 시점** — iOS 26.3 text only. 향후 minor 업데이트에서 이미지 입력 추가 시 vision 모델과 통합 가능. WWDC26 발표 시 재확인.
- M1 iPad **단발 prompt latency 실측치** — 공식 발표는 iPhone 15 Pro 기준. iPad Air 5 (A15급 NE) 는 약간 낮을 가능성.
- Gemma 3 270M 의 **Gemma Terms of Use 본문** — 사용 제한 (Acceptable Use Policy) 정밀 검토 필요. 캐릭터 행동 결정 use case 가 허용 범위인지 확인.
- `@Generable` 의 enum constraint 실제 동작 — string `.anyOf` 외에 Swift enum 직접 매핑 시그니처 확정 필요 (Xcode 26 베타 변경 가능).
- Apple Intelligence 미활성 디바이스 비율 / 사용자 onboarding 마찰 — 데모 시 사용자에게 활성 요청 plain 가이드 필요.
