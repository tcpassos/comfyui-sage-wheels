#!/usr/bin/env bash
# build-wheel.sh — Build a Linux SageAttention wheel in the current environment.
#
# Required environment variables:
#   SM
#   TORCH_CUDA_ARCH_LIST
#   SAGE_REF
#   OUT_DIR
#
# Optional environment variables:
#   MAX_JOBS       (default: 4)
#   SKIP_APT=1     Skip apt-get install of git + ca-certificates
#   SKIP_PIP_DEPS=1 Skip pip install --upgrade pip wheel setuptools
#   SRC_DIR        (default: /tmp/sage)
#   WHEEL_TMP      (default: /tmp/wheel)

set -euo pipefail

: "${SM:?SM is required}"
: "${TORCH_CUDA_ARCH_LIST:?TORCH_CUDA_ARCH_LIST is required}"
: "${SAGE_REF:?SAGE_REF is required}"
: "${OUT_DIR:?OUT_DIR is required}"

MAX_JOBS="${MAX_JOBS:-4}"
SRC_DIR="${SRC_DIR:-/tmp/sage}"
WHEEL_TMP="${WHEEL_TMP:-/tmp/wheel}"

mkdir -p "$OUT_DIR"

if [ -z "${SKIP_APT:-}" ] && command -v apt-get >/dev/null 2>&1; then
    echo "==> apt deps"
    if [ "$(id -u)" -eq 0 ]; then
        apt-get update -qq || true
        apt-get install -y -qq --no-install-recommends git ca-certificates || true
    elif command -v sudo >/dev/null 2>&1; then
        sudo apt-get update -qq || true
        sudo apt-get install -y -qq --no-install-recommends git ca-certificates || true
    else
        echo "    non-root and sudo not available; skipping apt install"
    fi
fi

if [ -z "${SKIP_PIP_DEPS:-}" ]; then
    echo "==> pip deps"
    pip install -q --upgrade pip wheel setuptools
fi

echo "==> clone thu-ml/SageAttention @ $SAGE_REF"
if [ ! -d "$SRC_DIR/.git" ]; then
    rm -rf "$SRC_DIR"
    git clone https://github.com/thu-ml/SageAttention.git "$SRC_DIR"
fi

cd "$SRC_DIR"
git fetch --all --tags -q || true
git checkout "$SAGE_REF"
echo "==> clean stale build artifacts from previous SM builds"
git clean -fdx
git reset --hard HEAD
echo "    commit: $(git rev-parse HEAD)"

echo "==> torch sanity"
python -c "import torch; print(\"torch=\"+torch.__version__, \"cuda=\"+(torch.version.cuda or \"none\"))"

echo "==> pip wheel (TORCH_CUDA_ARCH_LIST=$TORCH_CUDA_ARCH_LIST, MAX_JOBS=$MAX_JOBS)"
mkdir -p "$WHEEL_TMP"
pip wheel . --no-build-isolation --no-deps -w "$WHEEL_TMP"

shopt -s nullglob
wheels=( "$WHEEL_TMP"/sageattention-*.whl )
shopt -u nullglob
WHL="${wheels[0]:-}"
if [ -z "$WHL" ]; then
    echo "ERROR: no wheel produced"
    exit 1
fi
BASE="$(basename "$WHL")"
echo "    produced: $BASE"

# Rename injecting PEP 427 build tag = $SM before the python tag.
# Pattern: sageattention-<ver>-<pytag>-<abitag>-<plat>.whl
#     ->   sageattention-<ver>-<SM>-<pytag>-<abitag>-<plat>.whl
NEW="$(echo "$BASE" | sed -E "s/^(sageattention-[^-]+)-(cp[0-9]+)/\1-${SM}-\2/")"
if [ "$NEW" = "$BASE" ]; then
    echo "ERROR: rename did not match expected pattern on $BASE"
    exit 1
fi

cp "$WHL" "$OUT_DIR/$NEW"
chown "$(stat -c %u:%g "$OUT_DIR")" "$OUT_DIR/$NEW" || true
echo "==> done: $NEW"
