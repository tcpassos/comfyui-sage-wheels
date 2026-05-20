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
#   BASE_IMAGE     Docker image used for the build
#                  (default: pytorch/pytorch:2.12.0-cuda13.0-cudnn9-devel)
#   OUT_DIR        Output directory for the wheels (default: ./dist)
#
# The resulting wheel is renamed to include the PEP 427 build tag with the SM,
# e.g.: sageattention-2.2.0-90-cp312-cp312-linux_x86_64.whl

set -euo pipefail

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

mkdir -p "$OUT_DIR"

echo "==> Building SageAttention"
echo "    SAGE_REF   = $SAGE_REF"
echo "    SM         = $SM (arch=$ARCH)"
echo "    TORCH_VER  = $TORCH_VER"
echo "    CUDA_TAG   = $CUDA_TAG"
echo "    PY_TAG     = $PY_TAG"
echo "    BASE_IMAGE = $BASE_IMAGE"
echo "    OUT_DIR    = $OUT_DIR"

docker run --rm \
    -e PIP_BREAK_SYSTEM_PACKAGES=1 \
    -e PIP_NO_CACHE_DIR=1 \
    -e TORCH_CUDA_ARCH_LIST="$ARCH" \
    -e MAX_JOBS=4 \
    -e SM="$SM" \
    -e SAGE_REF="$SAGE_REF" \
    -v "$OUT_DIR:/out" \
    "$BASE_IMAGE" bash -euo pipefail -c '
        echo "==> apt deps"
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends git ca-certificates

        echo "==> pip deps"
        pip install -q --upgrade pip wheel setuptools

        echo "==> clone thu-ml/SageAttention @ $SAGE_REF"
        git clone --depth=1 -b "$SAGE_REF" https://github.com/thu-ml/SageAttention.git /tmp/sage 2>/dev/null \
            || git clone https://github.com/thu-ml/SageAttention.git /tmp/sage
        cd /tmp/sage
        if [ "$SAGE_REF" != "main" ]; then
            git checkout "$SAGE_REF" || true
        fi
        echo "    commit: $(git rev-parse HEAD)"

        echo "==> torch sanity"
        python -c "import torch; print(\"torch=\"+torch.__version__, \"cuda=\"+(torch.version.cuda or \"none\"))"

        echo "==> pip wheel (TORCH_CUDA_ARCH_LIST=$TORCH_CUDA_ARCH_LIST)"
        mkdir -p /tmp/wheel
        pip wheel . --no-build-isolation --no-deps -w /tmp/wheel

        WHL=$(ls /tmp/wheel/sageattention-*.whl | head -n1)
        if [ -z "$WHL" ]; then
            echo "ERROR: no wheel produced"
            exit 1
        fi
        BASE=$(basename "$WHL")
        echo "    produced: $BASE"

        # Rename injecting PEP 427 build tag = $SM before the python tag.
        # Pattern: sageattention-<ver>-<pytag>-<abitag>-<plat>.whl
        #     ->   sageattention-<ver>-<SM>-<pytag>-<abitag>-<plat>.whl
        NEW=$(echo "$BASE" | sed -E "s/^(sageattention-[^-]+)-(cp[0-9]+)/\1-${SM}-\2/")
        if [ "$NEW" = "$BASE" ]; then
            echo "ERROR: rename did not match expected pattern on $BASE"
            exit 1
        fi
        cp "$WHL" "/out/$NEW"
        chown $(stat -c %u:%g /out) "/out/$NEW" || true
        echo "==> done: $NEW"
    '

echo "==> Wheel available at $OUT_DIR/"
ls -lh "$OUT_DIR"/sageattention-*-"${SM}"-*.whl 2>/dev/null || true
