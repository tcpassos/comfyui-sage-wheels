#!/usr/bin/env bash
# build-all.sh — Build wheels for every arch in SM_LIST and generate SHA256SUMS.
#
# Variables exported to build.sh:
#   SAGE_REF       (default: main)
#   TORCH_VER      (default: 2.12.0)
#   CUDA_TAG       (default: cu130)
#   PY_TAG         (default: cp312)
#   BASE_IMAGE     (default: pytorch/pytorch:2.12.0-cuda13.0-cudnn9-devel)
#   BUILD_BACKEND  (default: auto; values: docker|native|auto)
#   OUT_DIR        (default: ./dist)
#   SM_LIST        Space-separated list (default: "86 89 90 120")
#
# On small runners (< 16 GB RAM), parallel builds of the _fused.so link step
# can OOM. This script runs sequentially to stay safe.

set -euo pipefail

cd "$(dirname "$0")"

export SAGE_REF="${SAGE_REF:-main}"
export TORCH_VER="${TORCH_VER:-2.12.0}"
export CUDA_TAG="${CUDA_TAG:-cu130}"
export PY_TAG="${PY_TAG:-cp312}"
export BASE_IMAGE="${BASE_IMAGE:-pytorch/pytorch:2.12.0-cuda13.0-cudnn9-devel}"
export BUILD_BACKEND="${BUILD_BACKEND:-auto}"
export OUT_DIR="${OUT_DIR:-$(pwd)/dist}"

SM_LIST="${SM_LIST:-86 89 90 120}"

mkdir -p "$OUT_DIR"

echo "==================================="
echo "Building SageAttention wheels"
echo "  SAGE_REF   = $SAGE_REF"
echo "  TORCH_VER  = $TORCH_VER"
echo "  CUDA_TAG   = $CUDA_TAG"
echo "  PY_TAG     = $PY_TAG"
echo "  BASE_IMAGE = $BASE_IMAGE"
echo "  BUILD_BACKEND = $BUILD_BACKEND"
echo "  SM_LIST    = $SM_LIST"
echo "  OUT_DIR    = $OUT_DIR"
echo "==================================="

for sm in $SM_LIST; do
    echo
    echo ">>> sm${sm}"
    ./build.sh "$sm"
done

echo
echo "==> Generating SHA256SUMS"
( cd "$OUT_DIR" && sha256sum sageattention-*.whl > SHA256SUMS )
cat "$OUT_DIR/SHA256SUMS"

echo
echo "==> Suggested tag:"
PY_DIGITS="${PY_TAG#cp}"
echo "    sage-<SAGE_VER>-torch-${TORCH_VER}-${CUDA_TAG}-py${PY_DIGITS}"
echo
echo "    (replace <SAGE_VER> with the exact version baked into the wheel filenames)"
echo
echo "==> Next: see BUILD.md → 'Publish release'"
