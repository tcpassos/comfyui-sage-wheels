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
export BASE_IMAGE="${BASE_IMAGE:-pytorch/pytorch:2.12.0-cuda13.0-cudnn9-devel}"
export BUILD_BACKEND="${BUILD_BACKEND:-auto}"
export OUT_DIR="${OUT_DIR:-$(pwd)/dist}"

# TORCH_VER / CUDA_TAG / PY_TAG: only export if the user set them. Otherwise
# build.sh auto-detects (from the running python in native mode, or by parsing
# $BASE_IMAGE in docker mode).
[ -n "${TORCH_VER:-}" ] && export TORCH_VER
[ -n "${CUDA_TAG:-}" ]  && export CUDA_TAG
[ -n "${PY_TAG:-}" ]    && export PY_TAG

SM_LIST="${SM_LIST:-75 80 86 89 90 120}"

mkdir -p "$OUT_DIR"

echo "==================================="
echo "Building SageAttention wheels"
echo "  SAGE_REF   = $SAGE_REF"
echo "  TORCH_VER  = ${TORCH_VER:-auto}"
echo "  CUDA_TAG   = ${CUDA_TAG:-auto}"
echo "  PY_TAG     = ${PY_TAG:-auto}"
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

# If values weren't provided up front, detect them now so the suggested tag
# matches the wheels we just produced.
if [ -z "${TORCH_VER:-}" ] || [ -z "${CUDA_TAG:-}" ] || [ -z "${PY_TAG:-}" ]; then
    _detected="$(python - <<'PY' 2>/dev/null || true
import sys
try:
    import torch
    tv = torch.__version__.split("+")[0]
    cu = (torch.version.cuda or "").replace(".", "")
except Exception:
    tv, cu = "", ""
py = f"cp{sys.version_info.major}{sys.version_info.minor}"
print(f"{tv}|{cu}|{py}")
PY
)"
    _tv="${_detected%%|*}"; _rest="${_detected#*|}"
    _cu="${_rest%%|*}"; _py="${_rest#*|}"
    TORCH_VER="${TORCH_VER:-${_tv:-unknown}}"
    CUDA_TAG="${CUDA_TAG:-cu${_cu:-unknown}}"
    PY_TAG="${PY_TAG:-${_py:-cp312}}"
fi

echo
echo "==> Suggested tag:"
PY_DIGITS="${PY_TAG#cp}"
echo "    sage-<SAGE_VER>-torch-${TORCH_VER}-${CUDA_TAG}-py${PY_DIGITS}"
echo
echo "    (replace <SAGE_VER> with the exact version baked into the wheel filenames)"
echo
echo "==> Next: see BUILD.md → 'Publish release'"
