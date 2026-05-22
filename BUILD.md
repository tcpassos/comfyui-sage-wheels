# Build guide

Step-by-step to generate a new release of wheels.

## Requirements

- **No GPU required.** SageAttention only needs the CUDA toolkit (NVCC) at
  build time, which ships with the `pytorch/pytorch:*-devel` base image.
- ~6 GB of free RAM per architecture being built (the `_fused.so` link step
  is memory-hungry). On small runners (4–8 GB) build one arch at a time.
- Docker **or** a host that already has PyTorch + NVCC (native backend).
- `gh` CLI (optional, for automatic upload via `gh release create`).

## Default build matrix

`build-all.sh` builds these compute capabilities by default
(`SM_LIST="75 80 86 89 90 120"`):

| SM  | Arch       | Example GPUs                |
|-----|------------|-----------------------------|
| 75  | Turing     | RTX 20xx, T4                |
| 80  | Ampere     | A100                        |
| 86  | Ampere     | RTX 30xx, A10, A40          |
| 89  | Ada        | RTX 40xx, L40, L40S         |
| 90  | Hopper     | H100, H200                  |
| 120 | Blackwell  | B200, RTX 50xx              |

Override with `SM_LIST="86 89"` (or any subset) to build fewer archs.

## Version auto-detection

`TORCH_VER`, `CUDA_TAG` and `PY_TAG` (used only for the **release tag**, not
for the wheel filename) are detected automatically:

- **Native backend**: read from the running Python interpreter (`torch.__version__`,
  `torch.version.cuda`, `sys.version_info`).
- **Docker backend**: parsed from `BASE_IMAGE` (e.g. `pytorch/pytorch:2.12.0-cuda13.0-...`
  → `TORCH_VER=2.12.0`, `CUDA_TAG=cu130`).

Export any of them explicitly to override. This means a pod sharing the same
base image as `comfyui-docker` will produce a correctly-tagged release without
extra configuration.

## Tuning environment variables

A few knobs that often matter when running on different hosts:

- **`MAX_JOBS`** (default: `4`) — number of parallel compile jobs passed to
  the SageAttention build. The `_fused.so` link step is memory-hungry
  (~6 GB per parallel job), so on small runners reduce it:
  - 4–8 GB RAM: `MAX_JOBS=1`
  - 8–16 GB RAM: `MAX_JOBS=2`
  - ≥ 16 GB RAM: leave the default (`4`)
  Higher values shorten the build but risk OOM kills during link.
- **`PIP_BREAK_SYSTEM_PACKAGES=1`** — required on Debian 12+ / Ubuntu 24.04
  images that ship Python with [PEP 668][pep668] enabled, where `pip install`
  refuses to touch the system interpreter. Most `pytorch/pytorch:*-devel`
  images are already configured to allow it, but if you see
  `error: externally-managed-environment`, export this before running the
  build:

  ```bash
  export PIP_BREAK_SYSTEM_PACKAGES=1
  ./build-all.sh
  ```

  The `docker` backend already injects this variable into the container, so
  this only applies to `BUILD_BACKEND=native`.
- **`SKIP_APT=1`** / **`SKIP_PIP_DEPS=1`** — skip the `apt-get install` and
  `pip install --upgrade pip wheel setuptools` steps when the environment is
  already provisioned (saves time and avoids needing root).

[pep668]: https://peps.python.org/pep-0668/

## Option A — Cloud pod (RunPod / Vast.ai / Lambda)

Works on any pod, with or without GPU. The cheapest CPU-only tier
(~$0.05/h) is enough for the build itself. If the pod is already a
`pytorch/pytorch:*-devel` container, prefer `BUILD_BACKEND=native` — it skips
the extra Docker-in-Docker layer.

### 1. Provision

RunPod or Vast.ai with:
- ≥ 4 vCPU
- ≥ 16 GB RAM (to build all archs in one go) or 8 GB (sequential).
- ≥ 30 GB of ephemeral disk
- Base image: any Ubuntu 22.04 / 24.04 with Docker pre-installed, **or** a
  `pytorch/pytorch:2.12.0-cuda13.0-cudnn9-devel` container for native builds.

### 2. Clone and build

```bash
git clone https://github.com/tcpassos/sage-wheels-linux.git
cd sage-wheels-linux

# Build every arch declared in build-all.sh (auto-picks docker or native)
./build-all.sh

# Or single-arch builds:
./build.sh 75    # Turing    (RTX 20xx, T4)
./build.sh 80    # Ampere    (A100)
./build.sh 86    # Ampere    (RTX 30xx, A10)
./build.sh 89    # Ada       (RTX 40xx, L40)
./build.sh 90    # Hopper    (H100, H200)
./build.sh 120   # Blackwell (B200, RTX 50xx)
```

Wheels land in `./dist/`. Expected time per arch: 5–8 min. The SageAttention
source tree is cleaned between builds so each wheel is compiled from a
pristine state.

### 3. Verify

```bash
ls -lh dist/
cat dist/SHA256SUMS
```

### 4. Publish release

#### 4a. Install and authenticate `gh` on the pod (one-time)

PyTorch base images don't ship the GitHub CLI:

```bash
(type -p curl >/dev/null || apt-get update && apt-get install -y curl) \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y gh

gh auth login    # GitHub.com → HTTPS → paste a Personal Access Token
gh auth status   # confirm
```

**Token permissions required** (otherwise `gh release create` returns
`HTTP 403: Resource not accessible by personal access token`):

- **Fine-grained PAT** (recommended): grant access to the target repository
  and set **Repository permissions → Contents: Read and write**.
- **Classic PAT**: the full `repo` scope (public repos work with
  `public_repo`, but `repo` is the safe choice).

Create / edit tokens at <https://github.com/settings/tokens>. Quick sanity
check:

```bash
gh api user --jq .login                                # must match the repo owner
gh api repos/tcpassos/sage-wheels-linux --jq .permissions
# expected to include push:true
```

#### 4b. Derive the tag from the wheels you just built

```bash
SAGE_VER=$(ls dist/sageattention-*.whl | head -1 | sed -nE 's/.*sageattention-([0-9.]+)-.*/\1/p')
TORCH_VER=$(python -c 'import torch; print(torch.__version__.split("+")[0])')
CUDA_TAG="cu$(python -c 'import torch; print((torch.version.cuda or "").replace(".",""))')"
PY_VER="cp$(python -c 'import sys; print(f"{sys.version_info.major}{sys.version_info.minor}")')"
PY_DIGITS="${PY_VER#cp}"
TAG="sage-${SAGE_VER}-torch-${TORCH_VER}-${CUDA_TAG}-py${PY_DIGITS}"
echo "$TAG"
```

#### 4c. Create the release and upload the assets

```bash
gh release create "$TAG" \
    --repo tcpassos/sage-wheels-linux \
    --title "$TAG" \
    --notes "Sage ${SAGE_VER} compiled against PyTorch ${TORCH_VER} + CUDA ${CUDA_TAG}, Python 3.${PY_DIGITS:1}. Built on $(date -u +%F)." \
    dist/sageattention-*.whl dist/SHA256SUMS
```

Alternative without `gh`: download `dist/` from the pod (panel, `scp`,
`rclone`), then on GitHub use **Releases → Draft a new release → Choose a
tag (create new)** and drag the `.whl` + `SHA256SUMS` files in.

### 5. Tear down the pod

Don't forget to destroy the cloud pod to stop billing.

## Option B — Local (Linux PC / WSL2)

Same steps as Option A, skip provisioning. Works on any Linux box with Docker
and ≥ 16 GB of RAM. WSL2 on Windows works as long as it has enough RAM
allocated.

## Option C — Native build inside a CUDA cloud pod (no Docker)

Use this when your pod is already a container based on
`pytorch/pytorch:*-devel` or similar, and you don't want to install/run Docker
inside it. Provision a pod with the right CUDA image and run:

```bash
apt-get update && apt-get install -y git
git clone https://github.com/tcpassos/sage-wheels-linux.git
cd sage-wheels-linux
BUILD_BACKEND=native ./build-all.sh
```

Auto-detection: if you simply run `./build-all.sh` inside a container without
Docker installed, the scripts will pick `native` automatically.

If you are not root and the deps are already there, set:
`SKIP_APT=1 SKIP_PIP_DEPS=1`.

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
