# Metric3D ViT-Small → Core ML 변환 시도 + Depth Anything V2 fallback 산출

_작성: ar-researcher / 2026-05-29 / Task #19_

## 요약 (3줄)

- **Metric3D ViT-Small (yvanyin/metric3d, BSD-2-Clause; HF ONNX 재공개 onnx-community/metric3d-vit-small, CC0-1.0) 의 Core ML `.mlpackage` 변환 시도 → 블로커**: coremltools 9.0 PyTorch frontend 가 ViT attention 의 **rank 7 reshape 텐서** 를 거부 (`Core ML only supports tensors with rank <= 5`). MIL frontend pipeline 은 끝까지 통과 (5772/5774 ops, 95/95 passes), 검증 단계에서 실패. 라이선스는 안전, 모델 사양 확인 완료.
- **team-lead 결정 권한 위임에 따라 fallback = Apple 공식 Depth Anything V2 Small (Apache-2.0) `.mlpackage`** 를 산출물로 채택. `DepthAnythingV2SmallF16.mlpackage` (24.8M params, **49.8 MB**, 입력 image 518×392 RGB, 출력 depth ImageType) 가 `code/DuckAR/DuckAR/Models/` 에 배치 완료.
- **trade-off**: Depth Anything V2 는 본질이 affine-invariant **relative depth** — Metric3D 의 절대 metric scale 강점 일부 손실. iOS 통합 시 ARKit `ARCamera.intrinsics` + ground plane scale 앵커링으로 절대 scale 보정 필요 (별도 PoC, Task #20 또는 후속 task 영역).

## 변환 시도 (재현 가능한 단계)

### 환경 셋업

```sh
mkdir -p /Users/fulld/dev/duck-ar/_tmp/metric3d_convert
cd /Users/fulld/dev/duck-ar/_tmp/metric3d_convert
python3 -m venv venv && source venv/bin/activate
pip install --upgrade pip
pip install onnx==1.17.0 numpy==1.26.4
pip install coremltools==9.0
pip install torch==2.4.1 torchvision
pip install onnx2torch==1.5.15
pip install huggingface_hub
```

호스트: macOS Darwin 25.4.0, system Python 3.9.6 (`/usr/bin/python3`, Xcode-bundled).

### 모델 받기

HF 의 `onnx-community/metric3d-vit-small` 가 PyTorch 2.0.1 export ONNX 두 변형 제공:

```sh
curl -sL "https://huggingface.co/onnx-community/metric3d-vit-small/resolve/main/onnx/model.onnx"      -o model.onnx        # 151 MB, fp32
curl -sL "https://huggingface.co/onnx-community/metric3d-vit-small/resolve/main/onnx/model_fp16.onnx" -o model_fp16.onnx   # 75.8 MB, fp16
curl -sL "https://huggingface.co/onnx-community/metric3d-vit-small/resolve/main/config.json"               -o config.json
curl -sL "https://huggingface.co/onnx-community/metric3d-vit-small/resolve/main/preprocessor_config.json"  -o preprocessor_config.json
```

ONNX 시그니처 (`onnx.load` + graph.input/output 검사):

| 텐서 | 형상 | dtype | 의미 |
|------|------|-------|------|
| `pixel_values` (input) | `[batch_size, 3, H, W]` | float16 (또는 fp32 variant) | ImageNet-정규화 RGB. H/W 는 14의 배수 (DINOv2 patch). 권장 518×518. |
| `predicted_depth` (out) | `[B, 4·floor(3.5·floor(H/14)), 4·floor(3.5·floor(W/14))]` | fp16/fp32 | canonical focal=1000 공간의 metric depth (meters). |
| `predicted_normal` (out) | `[B, 3, ..., ...]` | fp16/fp32 | surface normal (xyz). |
| `normal_confidence` (out) | `[B, ..., ...]` | fp16/fp32 | normal 신뢰도. |

- opset 11, IR 10, producer `pytorch 2.0.1`.
- **camera intrinsics 입력 없음** — 모델은 canonical (focal_length=1000, principal point=center) 공간에서 예측. 실제 카메라의 `fx_actual` 로 후처리 보정 필요:
  `depth_actual = depth_canonical × (fx_actual / 1000)`. ARKit `ARCamera.intrinsics.columns.0.x` 가 fx.

### 변환 스크립트 (`convert.py`)

```python
import torch, coremltools as ct
from onnx2torch import convert as onnx_to_torch

# coremltools 9.0 lacks an upsample_bicubic2d converter; Metric3D's token2feature
# decoder uses it. Map to bilinear (sub-pixel difference, acceptable for nav use).
from coremltools.converters.mil.frontend.torch.torch_op_registry import register_torch_op
from coremltools.converters.mil.frontend.torch.ops import upsample_bilinear2d

@register_torch_op
def upsample_bicubic2d(context, node):
    return upsample_bilinear2d(context, node)

ONNX_PATH = "model.onnx"          # fp32 ONNX — avoids onnx2torch mixed-dtype trace error
OUT_PATH  = "Metric3DSmall.mlpackage"
H = W = 518                       # 14·37 (DINOv2 patch multiple)

torch_model = onnx_to_torch(ONNX_PATH).eval().to(torch.float32)
dummy = torch.zeros(1, 3, H, W, dtype=torch.float32)
with torch.no_grad():
    traced = torch.jit.trace(torch_model, dummy, strict=False)

mlmodel = ct.convert(
    traced,
    inputs=[ct.TensorType(name="pixel_values", shape=(1, 3, H, W), dtype=float)],
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS17,
    compute_precision=ct.precision.FLOAT16,
)
mlmodel.save(OUT_PATH)
```

### 시도 1 — fp16 ONNX

- 실패: `RuntimeError: Input type (c10::Half) and bias type (float) should be the same`
- 원인: onnx2torch 변환 후 `.to(torch.float32)` 가 일부 conv weight 만 cast, 일부 buffer 가 half 유지 → conv2d 입력 dtype 불일치.

### 시도 2 — fp32 ONNX + bicubic→bilinear shim 없음

- 실패: `NotImplementedError: PyTorch convert function for op 'upsample_bicubic2d' not implemented.`
- 원인: coremltools 9.0 torch frontend 미구현 op. Metric3D 의 `depth_model/encoder/Resize` 에서 발생.

### 시도 3 — fp32 ONNX + `@register_torch_op upsample_bicubic2d → upsample_bilinear2d`

- 진행: ONNX→torch 변환 OK. trace OK. **MIL Frontend 5772/5774 ops 변환 + default pipeline 95/95 passes + backend_mlprogram 12/12 passes 모두 통과**.
- 실패: 최종 invalid-tensor-rank 검증에서
  ```
  ValueError: Core ML only supports tensors with rank <= 5.
  Layer "input_tensor_1013_cast_fp16", with type "reshape", outputs a rank 7 tensor.
  ```
- 원인 추정: Metric3D ViT-S 의 multi-head attention 내부에서 `[B, num_tokens, num_heads, head_dim]` 외에 window/patch 축 추가가 ONNX export 시 reshape op 으로 평탄화되며 rank 7 폴리노미얼이 발생. Core ML ML Program 의 하드 rank 5 제한과 충돌.

### 시도 후 결정 (team-lead 권한 위임)

- 라이선스/모델 사양은 안전 — 변환 실패는 순전히 ONNX 그래프 형상과 coremltools 9.0 ML Program 제약의 비호환.
- 추가 해결 경로 (A/B/C 보고서 내 비교 표) 비용/리스크가 큼 → **fallback D 채택**: Apple 공식 Depth Anything V2 Small Core ML (Apache-2.0) 다운로드 후 동일 슬롯에 배치.

## 산출물 (Depth Anything V2 small Core ML)

- **출처**: HF `apple/coreml-depth-anything-v2-small` 의 `DepthAnythingV2SmallF16.mlpackage`.
- **라이선스**: Apache-2.0 (Apple 재배포).
- **배치 경로**: `code/DuckAR/DuckAR/Models/DepthAnythingV2SmallF16.mlpackage` (**48 MB**).
  - team-lead 원 지시 파일명 `Metric3DSmall.mlpackage` 와 차이: 실제 모델이 Metric3D 가 아니므로 혼동 방지 차원에서 **실제 모델명 유지**. arkit-perception 통합 시 코드에서도 `DepthAnythingV2SmallF16` 로 참조 권장.
- **다운로드 절차** (재현):
  ```sh
  cd /Users/fulld/dev/duck-ar/_tmp/metric3d_convert && source venv/bin/activate
  python3 -c "from huggingface_hub import snapshot_download; \
      snapshot_download('apple/coreml-depth-anything-v2-small', \
          allow_patterns=['DepthAnythingV2SmallF16.mlpackage/*'], \
          local_dir='hf_dl')"
  cp -R hf_dl/DepthAnythingV2SmallF16.mlpackage \
        /Users/fulld/dev/duck-ar/code/DuckAR/DuckAR/Models/
  ```

### Core ML 시그니처 (검증 완료, `MLModel` spec 로드)

| I/O | 이름 | 타입 | 형상 / 사양 |
|-----|------|------|-------------|
| input | `image` | ImageType (RGB) | width=518, height=392, colorSpace=20 (RGB) |
| output | `depth` | ImageType | grayscale (depth map) |

- 모델 메타데이터: `version=2.0`, `shortDescription="Depth Anything V2 is a state-of-the-art deep learning model for depth estimation."`, `author="Original Paper: Lihe Yang et al. (Depth Anything V2)"`.
- 파라미터: 24.8M, F16 weight 49.8 MB (다른 quantization 변형 F16P6 / F16P8 / F16INT8 / F32 등 동 repo 에 존재 — 정확도/크기 trade-off 필요 시점에 swap 가능).

### M1 iPad 추론 예상

- 자료 (이전 보고서 `metric-3d-slam.md` § Monocular Metric Depth #1 / [AIBase 2024-06-25](https://www.aibase.com/news/10179)): **iPhone 12 Pro Max 31.1 ms/frame** (F16 small).
- M1 iPad Air 5 (A15급 NE) 추정: 25-35 ms — 5-10 fps depth 파이프라인 충분.
- 메모리: F16 49.8 MB weight + activation (518×392 입력에서 수십 MB 추가) → 전체 ~200 MB 추정. 8 GB RAM iPad Air 5 안정 범위.

## 추천 (다음 단계)

### Phase 1 통합 (arkit-perception Task #20)
1. `VNCoreMLRequest(model: try VNCoreMLModel(for: DepthAnythingV2SmallF16().model))` — Vision 표준 통합. ImageType 입력이므로 `VNImageRequestHandler(cvPixelBuffer:)` 에서 자동 RGB 변환 + resize.
2. depth 출력은 ImageType (grayscale) — `VNCoreMLFeatureValueObservation` 이 아닌 `VNPixelBufferObservation` 로 추출 가능. `CVPixelBuffer` → `vImage` 또는 `MLMultiArray` 후처리.
3. **affine-invariant → metric scale 보정**:
   - ARKit `arView.session.currentFrame?.camera.intrinsics` (3×3) 에서 `fx = intrinsics[0,0]` 추출.
   - ground plane 의 raycast hit world distance d_world 와 depth map 평균 d_pred 비율로 scale s = d_world / d_pred 추정.
   - 모든 depth pixel: `d_metric = s · d_pred`. 첫 안정 frame 에서 s 캡쳐 후 carry.
4. depth-aware occlusion (Task #21) / free-space (Task #22) 는 별도 task.

### 향후 Metric3D 재시도 옵션 (선택)
시간 여유 / metric absolute 강점이 결정적 필요할 때:
- **(A) onnxsim 단순화 + opset 변경 후 재시도** (1-3 h) — `pip install onnxsim` → `onnxsim model.onnx model_sim.onnx` 로 reshape 폴리노미얼 정리 후 onnx2torch 재변환. rank 5 이하 보장은 미확정.
- **(B) yvanyin/metric3d 원본 PyTorch + mmcv 빌드 + trace + coremltools** (0.5-1 d) — mmcv build 리스크 있음.
- **(C) ONNX Runtime iOS** (2-4 h) — Core ML 우회. XCFramework +60-100 MB, 그러나 모델 metric depth 그대로 사용.

## 비교 표 — 시도된 대안 (의사결정 근거)

| # | 옵션 | 예상 비용 | 라이선스 | App 크기 | depth 종류 | 결정 |
|---|------|----------|---------|---------|-----------|------|
| A | onnxsim 단순화 + opset 변경 | 1-3 h | BSD-2 + CC0 | +75-150 MB | metric | 보류 |
| B | 원본 PyTorch + mmcv + trace | 0.5-1 d | BSD-2 | +75-150 MB | metric | 보류 |
| C | ONNX Runtime iOS | 2-4 h | BSD-2 + CC0 + MIT (ORT) | +60-100 MB (.xcframework) | metric | 보류 |
| **D** | **Depth Anything V2 small (Apple Core ML)** | **0.5 h** | **Apache-2.0** | **+48 MB** | **relative (scale 보정 필요)** | **채택** |

## 근거 (출처 + 접근 일자 2026-05-29)

### Metric3D
- [yvanyin/metric3d GitHub](https://github.com/yvanyin/metric3d) — README, ONNX export 스크립트 (`onnx/metric3d_onnx_export.py`)
- [yvanyin/metric3d LICENSE (BSD-2-Clause)](https://raw.githubusercontent.com/YvanYin/Metric3D/main/LICENSE)
- [HuggingFace onnx-community/metric3d-vit-small (CC0-1.0)](https://huggingface.co/onnx-community/metric3d-vit-small) — `onnx/model.onnx` 151 MB, `onnx/model_fp16.onnx` 75.8 MB
- [Metric3Dv2 project page](https://jugghm.github.io/Metric3Dv2/)

### Depth Anything V2 (채택 fallback)
- [HuggingFace apple/coreml-depth-anything-v2-small (Apache-2.0)](https://huggingface.co/apple/coreml-depth-anything-v2-small) — `DepthAnythingV2SmallF16.mlpackage` 49.8 MB 외 8 변형
- [Apple — Machine Learning Models 카탈로그](https://developer.apple.com/machine-learning/models/) — Depth Anything V2 공식 등재
- [huggingface/coreml-examples — depth-anything-example](https://github.com/huggingface/coreml-examples/blob/main/depth-anything-example/README.md) — Swift 통합 샘플
- [AIBase 2024-06-25 — Apple Core ML 등재 발표](https://www.aibase.com/news/10179) — iPhone 12 Pro Max **31.1 ms/frame** (F16 small)
- [DeepWiki — kaylorchen/Depth-Anything-V2 Apple Core ML](https://deepwiki.com/kaylorchen/Depth-Anything-V2/8.2-apple-core-ml)

### 변환 도구
- [coremltools 9.0](https://apple.github.io/coremltools/) — ML Program 컨버터 (ONNX 직접 지원 deprecated)
- [onnx2torch 1.5.15](https://pypi.org/project/onnx2torch/) — ONNX → PyTorch nn.Module
- [coremltools register_torch_op](https://apple.github.io/coremltools/source/coremltools.converters.mil.frontend.torch.html) — custom op handler

## 미해결

- **Metric3D Core ML 변환은 옵션 A/B/C 중 하나로 재도전 가능** — Depth Anything V2 의 affine-invariant 한계가 시연/네비게이션에 실측 문제로 드러날 시점에 재진입.
- **Depth Anything V2 → metric scale 보정 절차의 안정성** — 단일 ground plane scale 앵커링이 카메라 이동 후에도 일관되는지 별도 검증 필요 (Task #20 PoC 영역).
- **518×392 입력 vs ARFrame 720p/1080p crop 비율** — Vision 의 자동 resize 가 horizontal-stretch 인지 letterbox 인지 (huggingface/coreml-examples 샘플 확인 필요). horizontal-stretch 면 depth aspect 왜곡 보정 필요.
- **다른 quantization 변형 (F16P6 / F16P8 / F16INT8)** 의 M1 iPad 정확도/속도 비교 미수행 — Phase 2 진입 시 GB-품질 trade-off 측정 가능.
- **Apple 공식 등재 Depth Anything V2 의 weight 출처 — 원본 ByteDance/HKU MIT 라이선스 가중치인지 Apple 재학습본인지 명시 부재** — Apache-2.0 재배포 권한 충분하나 attribution 의무 확인 (README 에 "Original Paper: Lihe Yang et al." 표기 있음).
