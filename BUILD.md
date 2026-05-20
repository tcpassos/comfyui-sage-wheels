# Build guide

Step-by-step to generate a new release of wheels.

## Requirements

- **No GPU required.** SageAttention only needs the CUDA toolkit (NVCC) at
  build time, which ships with the `pytorch/pytorch:*-devel` base image.
- ~6 GB of free RAM per architecture being built (the `_fused.so` link step
  is memory-hungry). On small runners (4–8 GB) build one arch at a time.
- Docker.
- `gh` CLI (optional, for automatic upload via `gh release create`).

## Option A — Cloud pod (RunPod / Vast.ai / Lambda)

Works on any pod with Docker. No GPU needed on the pod, so the cheapest tier
(~$0.05/h CPU-only) is enough.

### 1. Provision

RunPod or Vast.ai with:
- ≥ 4 vCPU
- ≥ 16 GB RAM (to build all archs in one go) or 8 GB (sequential).
- ≥ 30 GB of ephemeral disk
- Base image: any Ubuntu 22.04 / 24.04 with Docker pre-installed

### 2. Clone and build

```bash
git clone https://github.com/tcpassos/comfyui-sage-wheels.git
cd comfyui-sage-wheels

# Build every arch declared in build-all.sh
./build-all.sh

# Or single-arch builds:
./build.sh 89    # Ada    (RTX 4090, L40)
./build.sh 90    # Hopper (H100, H200)
./build.sh 120   # Blackwell (B200, RTX 5090)
```

Wheels land in `./dist/`. Expected time per arch: 5–8 min.

### 3. Verify

```bash
ls -lh dist/
cat dist/SHA256SUMS
```

### 4. Publish release

Set the variables used in the tag:

```bash
SAGE_VER=2.2.0
TORCH_VER=2.12.0
CUDA_TAG=cu130
PY_VER=312
TAG="sage-${SAGE_VER}-torch-${TORCH_VER}-${CUDA_TAG}-py${PY_VER}"
```

With `gh` CLI authenticated:

```bash
gh release create "$TAG" \
    --repo tcpassos/comfyui-sage-wheels \
    --title "$TAG" \
    --notes "Sage ${SAGE_VER} compiled against PyTorch ${TORCH_VER} + CUDA ${CUDA_TAG}, Python 3.${PY_VER:1}. Built on $(date -u +%F)." \
    dist/sageattention-*.whl dist/SHA256SUMS
```

Or upload manually via the GitHub UI: Releases → Draft new release → Choose
tag → drag the `.whl` files + `SHA256SUMS`.

### 5. Tear down the pod

Don't forget to destroy the cloud pod to stop billing.

## Option B — Local (Linux PC / WSL2)

Same steps as Option A, skip item 1. Works on any Linux box with Docker and
≥ 16 GB of RAM. WSL2 on Windows works as long as it has enough RAM allocated.

## Optional verification on a GPU pod

Before publishing, it's wise to smoke-test at least one of the wheels on a
pod with the matching GPU arch:

```bash
docker run --rm --gpus all -v $PWD/dist:/wheels \
    pytorch/pytorch:2.12.0-cuda13.0-cudnn9-devel bash -c '
        PIP_BREAK_SYSTEM_PACKAGES=1 pip install --no-deps /wheels/sageattention-2.2.0-90-*.whl &&
        python -c "import sageattention; print(sageattention.__version__)" &&
        python -c "import torch; from sageattention import sageattn; print(\"sageattn OK\")"
    '
```

## Updating to a new Sage version

1. Edit `build.sh`: set `SAGE_REF` to the desired tag/commit of
   `thu-ml/SageAttention`.
2. If torch or CUDA also changed, update `BASE_IMAGE` in `build.sh` and the
   `TORCH_VER` / `CUDA_TAG` defaults in `build-all.sh`.
3. Rebuild + new release with a new tag. The old release stays valid for
   older image versions.
