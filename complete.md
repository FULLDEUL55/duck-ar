# duck-ar — 작업 이력

2026-05-26: 프로젝트 부트스트랩 (L3 헤드 Duck-Head 정의, .claude 디렉토리, 폴더 골격).
2026-05-27: 스택 확정 (Swift + ARKit + RealityKit + Apple Vision + Core ML 네이티브). 디바이스 = iPad Air 5 (M1, LiDAR 없음). Phase 1 semantic 우선, Phase 2 monocular ML depth + mesh occlusion. 도메인 서브 에이전트 4명 정의 (xcode-builder / arkit-perception / realitykit-scene / duck-behavior). code/, docs/, assets/ 디렉토리 골격 생성.
2026-05-27: Xcode 26.5 / iOS SDK 26.5 환경 확인. Free Apple ID 로그인 (Developer Program 가입 보류). 5번째 서브 에이전트 `ar-researcher` 추가 (리서치 전담, 도구 셋 = Read/Write/Grep/Glob/Bash/WebFetch/WebSearch). `docs/research/` 디렉토리 생성.
2026-05-27: **Phase 1 베이스라인 빌드 완료** — `code/DuckAR.xcodeproj` 부트스트랩 (SwiftUI App, Bundle `com.fulldeul.DuckAR`, Personal Team `4BB378R83H`, iOS 26.5 target). `ContentView.swift` 에 ARView + `ARWorldTrackingConfiguration` + plane detection (horizontal/vertical) + debug 시각화 (anchor origins/geometry, world origin) 구현. `INFOPLIST_KEY_NSCameraUsageDescription` 추가. iPad Air 5 (iPad13,16) 실기 빌드 + 설치 성공 (`xcodebuild` + `devicectl`). 첫 실행은 사용자 신뢰 단계 (설정 > VPN 및 기기 관리) 대기 중.
