#!/usr/bin/env bash
# build.sh — Build a Linux SageAttention wheel for ONE CUDA architecture.
#
# Usage:
#   ./build.sh <SM>
#
# Where <SM> is the compute capability without the dot: 89, 90, 100, 120, ...
#
# Overridable environment variables:
#   SAGE_REF       Tag/branch/commit of thu-ml/SageAttention (default: main)
#   TORCH_VER      Target torch version (default: 2.12.0)
#   CUDA_TAG       CUDA tag (default: cu130)
#   PY_TAG         Python tag (default: cp312)
#   BUILD_BACKEND  Build backend selector: docker|native|auto (default: auto)
#   BASE_IMAGE     Docker image used for the build
#                  (default: pytorch/pytorch:2.12.0-cuda13.0-cudnn9-devel)
#   OUT_DIR        Output directory for the wheels (default: ./dist)
#
# The resulting wheel is renamed to include the PEP 427 build tag with the SM,
# e.g.: sageattention-2.2.0-90-cp312-cp312-linux_x86_64.whl

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SM="${1:?usage: $0 <SM>   e.g. $0 90}"

case "$SM" in
    75)  ARCH="7.5" ;;
    80)  ARCH="8.0" ;;
    86)  ARCH="8.6" ;;
    89)  ARCH="8.9" ;;
    90)  ARCH="9.0" ;;
    100) ARCH="10.0" ;;
    120) ARCH="12.0" ;;
    *) echo "ERROR: SM '$SM' not supported. Add it to the case in build.sh." >&2; exit 1 ;;
esac

SAGE_REF="${SAGE_REF:-main}"
TORCH_VER="${TORCH_VER:-2.12.0}"
CUDA_TAG="${CUDA_TAG:-cu130}"
PY_TAG="${PY_TAG:-cp312}"
BASE_IMAGE="${BASE_IMAGE:-pytorch/pytorch:2.12.0-cuda13.0-cudnn9-devel}"
OUT_DIR="${OUT_DIR:-$(pwd)/dist}"
MAX_JOBS="${MAX_JOBS:-4}"
BUILD_BACKEND="${BUILD_BACKEND:-auto}"

case "$BUILD_BACKEND" in
    docker|native|auto) ;;
    *) echo "ERROR: BUILD_BACKEND must be one of: docker, native, auto" >&2; exit 1 ;;
esac

RESOLVED_BUILD_BACKEND="$BUILD_BACKEND"
if [ "$BUILD_BACKEND" = "auto" ]; then
    if ! command -v docker >/dev/null 2>&1; then
        RESOLVED_BUILD_BACKEND="native"
    elif [ -f /.dockerenv ] || grep -qaE '(docker|kubepods|containerd|lxc)' /proc/1/cgroup 2>/dev/null; then
        RESOLVED_BUILD_BACKEND="native"
    else
        RESOLVED_BUILD_BACKEND="docker"
    fi
fi

mkdir -p "$OUT_DIR"

echo "==> Building SageAttention"
echo "    SAGE_REF   = $SAGE_REF"
echo "    SM         = $SM (arch=$ARCH)"
echo "    TORCH_VER  = $TORCH_VER"
echo "    CUDA_TAG   = $CUDA_TAG"
echo "    PY_TAG     = $PY_TAG"
echo "    BUILD_BACKEND = $RESOLVED_BUILD_BACKEND"
echo "    BASE_IMAGE = $BASE_IMAGE"
echo "    OUT_DIR    = $OUT_DIR"

if [ "$RESOLVED_BUILD_BACKEND" = "docker" ]; then
    docker run --rm \
        -e PIP_BREAK_SYSTEM_PACKAGES=1 \
        -e PIP_NO_CACHE_DIR=1 \
        -e OUT_DIR=/out \
        -e TORCH_CUDA_ARCH_LIST="$ARCH" \
        -e MAX_JOBS="$MAX_JOBS" \
        -e SM="$SM" \
        -e SAGE_REF="$SAGE_REF" \
        -v "$OUT_DIR:/out" \
        -v "$SCRIPT_DIR/build-wheel.sh:/build-wheel.sh:ro" \
        "$BASE_IMAGE" bash /build-wheel.sh
else
    export TORCH_CUDA_ARCH_LIST="$ARCH"
    export SM
    export SAGE_REF
    export OUT_DIR
    export MAX_JOBS
    bash "$SCRIPT_DIR/build-wheel.sh"
fi

echo "==> Wheel available at $OUT_DIR/"
ls -lh "$OUT_DIR"/sageattention-*-"${SM}"-*.whl 2>/dev/null || true
