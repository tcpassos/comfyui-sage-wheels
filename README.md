# comfyui-sage-wheels

Pre-built Linux wheels of [SageAttention 2.x](https://github.com/thu-ml/SageAttention),
distributed via GitHub Releases for use with the
[`tcpassos/comfyui-cloud`](https://hub.docker.com/r/tcpassos/comfyui-cloud) image.

## Motivation

Upstream `thu-ml/SageAttention` does not publish wheels. The community fork
`woct0rdho/SageAttention` publishes wheels but **for Windows only**. On Linux
containers the only option is to compile from source, which takes ~5 minutes
per GPU architecture on the first boot.

This repo solves that by publishing pre-compiled Linux wheels per
`(sage_version, torch_version, cuda_version, py_version, sm_arch)` tuple.
The image's entrypoint downloads the right wheel in ~30s instead of
compiling.

## Naming scheme

Each release contains wheels for multiple GPU architectures.

**Release tag**:
```
sage-<SAGE_VER>-torch-<TORCH_VER>-<CUDA_TAG>-py<PY_VER>
```
Example: `sage-2.2.0-torch-2.12.0-cu130-py312`

**Asset filename** (uses PEP 427 *build tag* to distinguish arch):
```
sageattention-<SAGE_VER>-<SM>-cp<PYMM>-cp<PYMM>-linux_x86_64.whl
```
Where `<SM>` is the compute capability without the dot: `89` (Ada), `90`
(Hopper), `120` (Blackwell), etc.

Examples:
- `sageattention-2.2.0-89-cp312-cp312-linux_x86_64.whl`  → RTX 4090, L40
- `sageattention-2.2.0-90-cp312-cp312-linux_x86_64.whl`  → H100, H200
- `sageattention-2.2.0-120-cp312-cp312-linux_x86_64.whl` → B200, RTX 5090

Each release also includes a `SHA256SUMS` file for verification.

## Supported matrix

| SAGE_VER | TORCH_VER | CUDA_TAG | PY_VER | SM archs        |
|----------|-----------|----------|--------|-----------------|
| 2.2.0    | 2.12.0    | cu130    | 3.12   | 89, 90, 120     |

More combinations can be added on demand.

## Building a new release

See [BUILD.md](./BUILD.md) for the full step-by-step in a cloud pod.

Quick version:
```bash
# On any Linux box with Docker (no GPU required):
./build-all.sh
# wheels land in ./dist/
# then publish via `gh release create`
```

## Consuming (from the comfyui-cloud entrypoint)

```bash
SM=$(detect_gpu_sm)  # e.g. 90
URL="https://github.com/tcpassos/comfyui-sage-wheels/releases/download/\
sage-2.2.0-torch-2.12.0-cu130-py312/\
sageattention-2.2.0-${SM}-cp312-cp312-linux_x86_64.whl"

if curl -fsSL --retry 2 -o /tmp/sage.whl "$URL"; then
    pip install --no-deps /tmp/sage.whl
else
    # fallback: compile from source (~5 min)
    pip install --no-build-isolation git+https://github.com/thu-ml/SageAttention.git
fi
```

## License

The wheels published here are repackaged binaries of
[`thu-ml/SageAttention`](https://github.com/thu-ml/SageAttention), which is
licensed under Apache-2.0. The scripts in this repo are also Apache-2.0.
