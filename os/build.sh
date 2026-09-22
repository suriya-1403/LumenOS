#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/output"

echo "===================================================="
echo "           LUMEN OS IMAGE BUILDER                   "
echo "   Target: Debian 13 Trixie (ARM64) for RPi 4/5     "
echo "===================================================="

mkdir -p "${OUTPUT_DIR}"

# Check Docker requirement
if ! command -v docker >/dev/null 2>&1; then
    echo "[ERROR] Docker is required to cross-build the ARM64 disk image."
    echo "Please install and start Docker Desktop (https://www.docker.com/)."
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "[ERROR] Docker daemon is not running."
    echo "Please start Docker Desktop and re-run this script."
    exit 1
fi

echo "[1/2] Building cross-compilation container image..."
docker build -t lumen-builder -f "${SCRIPT_DIR}/Dockerfile" "${SCRIPT_DIR}"

echo "[2/2] Running build container (Privileged for loop mounts)..."
docker run --rm --privileged \
    -v "${REPO_ROOT}:/workspace" \
    -v /dev:/dev \
    -e TERM=xterm-256color \
    lumen-builder

echo ""
echo "===================================================="
echo "          LUMEN OS BUILD COMPLETE!                  "
echo "===================================================="
echo "Your compressed disk image is in: ${OUTPUT_DIR}"
echo "Flash it using Raspberry Pi Imager or BalenaEtcher:"
echo "  rpi-imager --cli ${OUTPUT_DIR}/lumen-os-*.img.xz /dev/sdX"
echo "===================================================="
