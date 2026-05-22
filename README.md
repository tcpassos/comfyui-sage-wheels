# sage-wheels-linux

Pre-built Linux wheels of [SageAttention 2.x](https://github.com/thu-ml/SageAttention),
distributed via GitHub Releases for use with the
[`tcpassos/comfyui-cloud`](https://hub.docker.com/r/tcpassos/comfyui-cloud) image.

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
Where `<SM>` is the compute capability without the dot: `75` (Turing), `80` (Ampere), `86` (Ampere), `89` (Ada), `90`
(Hopper), `120` (Blackwell), etc.

Examples:
- `sageattention-2.2.0-89-cp312-cp312-linux_x86_64.whl`  → RTX 4090, L40
- `sageattention-2.2.0-90-cp312-cp312-linux_x86_64.whl`  → H100, H200
- `sageattention-2.2.0-120-cp312-cp312-linux_x86_64.whl` → B200, RTX 5090

Each release also includes a `SHA256SUMS` file for verification.

## Supported matrix

| SAGE_VER | TORCH_VER | CUDA_TAG | PY_VER | SM archs                | Paired Docker tag                  |
|----------|-----------|----------|--------|-------------------------|------------------------------------|
| 2.2.0    | 2.12.0    | cu130    | 3.12   | 75, 80, 86, 89, 90, 120 | `tcpassos/comfyui-cloud:latest`    |
| 2.2.0    | 2.11.0    | cu128    | 3.12   | 75, 80, 86, 89, 90, 120 | `tcpassos/comfyui-cloud:cu128`     |

The paired Docker tag is the [`tcpassos/comfyui-cloud`](https://hub.docker.com/r/tcpassos/comfyui-cloud) image whose torch / CUDA / Python combo matches the release tag — the image's entrypoint queries this repo at boot and pulls the wheel matching the GPU's SM.

More combinations can be added on demand.

## Building a new release

See [BUILD.md](./BUILD.md) for the full step-by-step in a cloud pod.

Quick version:
```bash
# On any Linux box with Docker (no GPU required):
./build-all.sh

# Or, directly inside a CUDA cloud pod (no Docker needed):
BUILD_BACKEND=native ./build-all.sh

# wheels land in ./dist/
# then publish via `gh release create`
```

## License

The wheels published here are repackaged binaries of
[`thu-ml/SageAttention`](https://github.com/thu-ml/SageAttention), which is
licensed under Apache-2.0. The scripts in this repo are also Apache-2.0.
