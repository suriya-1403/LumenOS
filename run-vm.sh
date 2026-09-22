#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"

echo "===================================================="
echo "          LUMEN OS - QEMU VM LAUNCHER               "
echo "===================================================="

if ! command -v qemu-system-aarch64 >/dev/null 2>&1; then
    echo "[ERROR] qemu-system-aarch64 is not installed."
    echo "Install it with Homebrew: brew install qemu"
    exit 1
fi

# 1. Locate disk image
RAW_IMG=$(ls -1 "${OUTPUT_DIR}"/lumen-os-*.img 2>/dev/null | tail -n1 || true)
XZ_IMG=$(ls -1 "${OUTPUT_DIR}"/lumen-os-*.img.xz 2>/dev/null | tail -n1 || true)

if [[ -z "${RAW_IMG}" ]]; then
    if [[ -n "${XZ_IMG}" ]]; then
        echo "[1/3] Decompressing disk image (one-time setup)..."
        xz -dk -T0 "${XZ_IMG}"
        RAW_IMG=$(ls -1 "${OUTPUT_DIR}"/lumen-os-*.img 2>/dev/null | tail -n1)
    else
        echo "[ERROR] No Lumen OS image found in ${OUTPUT_DIR}."
        echo "Please run ./os/build.sh first to generate an image."
        exit 1
    fi
else
    echo "[1/3] Found disk image: $(basename "${RAW_IMG}")"
fi

# 2. Extract kernel and initrd from the boot partition if needed
KERNEL="${OUTPUT_DIR}/vmlinuz"
INITRD="${OUTPUT_DIR}/initrd.img"

if [[ ! -f "${KERNEL}" || ! -f "${INITRD}" ]]; then
    echo "[2/3] Extracting kernel and initramfs from boot partition..."
    
    # Try native macOS hdiutil first
    if command -v hdiutil >/dev/null 2>&1; then
        set +e
        MOUNT_INFO=$(hdiutil attach "${RAW_IMG}" 2>/dev/null)
        DISK_DEV=$(echo "${MOUNT_INFO}" | grep -i "Windows_FAT_32\|bootfs" | awk '{print $1}')
        MOUNT_POINT=$(echo "${MOUNT_INFO}" | grep -i "Windows_FAT_32\|bootfs" | awk '{print $NF}')
        
        if [[ -n "${MOUNT_POINT}" && -d "${MOUNT_POINT}" ]]; then
            cp -f "${MOUNT_POINT}/vmlinuz" "${KERNEL}" 2>/dev/null || true
            cp -f "${MOUNT_POINT}/initrd.img" "${INITRD}" 2>/dev/null || true
            hdiutil detach "${DISK_DEV}" >/dev/null 2>&1 || true
        fi
        set -e
    fi
    
    # Fallback to Docker if hdiutil did not extract both files
    if [[ ! -f "${KERNEL}" || ! -f "${INITRD}" ]]; then
        echo "Extracting via Docker container..."
        IMG_NAME=$(basename "${RAW_IMG}")
        docker run --rm --privileged \
            -v "${OUTPUT_DIR}:/workspace" \
            debian:trixie-slim bash -c "
                apt-get update -qq && apt-get install -y -qq kpartx dosfstools > /dev/null
                LOOP=\$(losetup -Pf --show /workspace/${IMG_NAME})
                mkdir -p /mnt/boot
                mount \${LOOP}p1 /mnt/boot
                cp -f /mnt/boot/vmlinuz /workspace/vmlinuz
                cp -f /mnt/boot/initrd.img /workspace/initrd.img
                umount /mnt/boot
                losetup -d \${LOOP}
            "
    fi
fi

if [[ ! -f "${KERNEL}" || ! -f "${INITRD}" ]]; then
    echo "[ERROR] Failed to extract vmlinuz and initrd.img from image."
    exit 1
fi

echo "[2/3] Kernel and initrd ready."

# 3. Configure hardware acceleration (HVF on Apple Silicon)
ARCH=$(uname -m)
if [[ "${ARCH}" == "arm64" ]]; then
    echo "Using Apple Silicon Hypervisor Framework (-accel hvf)..."
    ACCEL_ARGS=("-accel" "hvf" "-cpu" "host")
else
    echo "Using TCG CPU emulation..."
    ACCEL_ARGS=("-cpu" "cortex-a72")
fi

echo "[3/3] Booting Lumen OS in QEMU VM..."
echo "----------------------------------------------------"
echo "Display Window: The GUI window will show the mirror HUD."
echo "Terminal:       System and kernel boot logs are mirrored here."
echo "SSH Access:     ssh -p 2222 lumen@localhost (password: lumenpassword)"
echo "Exit VM:        Close the window or press Ctrl+A then X in terminal"
echo "----------------------------------------------------"

exec qemu-system-aarch64 \
    -name "Lumen OS Smart Mirror" \
    -M virt \
    "${ACCEL_ARGS[@]}" \
    -m 2048 \
    -smp 4 \
    -kernel "${KERNEL}" \
    -initrd "${INITRD}" \
    -append "root=/dev/vda2 rw console=tty0 console=ttyAMA0" \
    -drive "file=${RAW_IMG},format=raw,if=virtio" \
    -device virtio-gpu-pci \
    -device usb-ehci \
    -device usb-kbd \
    -device usb-mouse \
    -serial mon:stdio \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0
