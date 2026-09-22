#!/usr/bin/env bash
set -euo pipefail

echo "==> [Stage 01] Configuring silent boot, kernel parameters, and hardware flags..."

BOOT_DIR="${TARGET}/boot/firmware"
mkdir -p "${BOOT_DIR}"

# 1. Populate /boot/firmware with Raspberry Pi bootloader binaries, kernel, and DTBs
echo "==> Deploying Raspberry Pi bootloader firmware files..."
if [ -d "${TARGET}/usr/lib/raspi-firmware" ]; then
    cp -r "${TARGET}"/usr/lib/raspi-firmware/* "${BOOT_DIR}/" 2>/dev/null || true
fi

echo "==> Deploying kernel, initramfs, and device tree blobs..."
LATEST_KERNEL=$(ls -1 "${TARGET}"/boot/vmlinuz-* 2>/dev/null | sort -V | tail -n1 || true)
LATEST_INITRD=$(ls -1 "${TARGET}"/boot/initrd.img-* 2>/dev/null | sort -V | tail -n1 || true)

if [[ -n "${LATEST_KERNEL}" && -f "${LATEST_KERNEL}" ]]; then
    KERNEL_NAME=$(basename "${LATEST_KERNEL}")
    cp -f "${LATEST_KERNEL}" "${BOOT_DIR}/${KERNEL_NAME}"
    cp -f "${LATEST_KERNEL}" "${BOOT_DIR}/vmlinuz"
fi

if [[ -n "${LATEST_INITRD}" && -f "${LATEST_INITRD}" ]]; then
    INITRD_NAME=$(basename "${LATEST_INITRD}")
    cp -f "${LATEST_INITRD}" "${BOOT_DIR}/${INITRD_NAME}"
    cp -f "${LATEST_INITRD}" "${BOOT_DIR}/initrd.img"
fi

# Copy Device Tree Blobs (Pi 3, 4, 400, CM4, 5)
for dtb_dir in "${TARGET}"/usr/lib/linux-image-*/broadcom "${TARGET}"/usr/lib/linux-image-*; do
    if [ -d "${dtb_dir}" ]; then
        cp -f "${dtb_dir}"/bcm*.dtb "${BOOT_DIR}/" 2>/dev/null || true
    fi
done

# 2. Configure /boot/firmware/cmdline.txt for pure silent boot
# console=tty3 directs boot spam to virtual terminal 3 (hidden)
# vt.global_cursor_default=0 disables the blinking text cursor
# logo.nologo suppresses the 4-raspberry boot logo
cat > "${BOOT_DIR}/cmdline.txt" <<EOF
console=serial0,115200 console=tty3 root=PARTUUID=${PARTUUID_ROOT} rootfstype=ext4 fsck.repair=yes rootwait quiet splash loglevel=0 vt.global_cursor_default=0 logo.nologo
EOF

# 3. Configure /boot/firmware/config.txt
cat > "${BOOT_DIR}/config.txt" <<EOF
# ====================================================
# Lumen OS - Hardware & Firmware Configuration
# ====================================================

# 64-bit ARM Mode & Upstream Kernel Loading
arm_64bit=1
upstream_kernel=1
kernel=vmlinuz
initramfs initrd.img followkernel

# Silent & Fast Boot
disable_splash=1
boot_delay=0
disable_overscan=1

# Graphics Acceleration (KMS)
dtoverlay=vc4-kms-v3d
max_framebuffers=2

# Audio Hardware
dtparam=audio=on

# Hardware Interfaces for Smart Mirror Sensors
$( [[ "${ENABLE_I2C}" == "true" ]] && echo "dtparam=i2c_arm=on" )
$( [[ "${ENABLE_SPI}" == "true" ]] && echo "dtparam=spi=on" )
$( [[ "${ENABLE_UART}" == "true" ]] && echo "enable_uart=1" )

# Camera Support (Auto-detect Pi Camera v2, v3, HQ)
$( [[ "${ENABLE_CAMERA}" == "true" ]] && echo "camera_auto_detect=1" )

# HDMI & Display Orientation Hook
# Smart mirrors typically mount displays in portrait orientation.
# Rotation is applied at the compositor level (Sway's `output * transform`,
# see os/stages/04-desktop-shell.sh) rather than here, since that is the
# reliable mechanism under Wayland/KMS. This flag is kept only as a fallback
# for legacy non-KMS displays.
# display_hdmi_rotate=${DISPLAY_ROTATION}
EOF

# 3. Disable getty on tty1 to prevent terminal cursor flicker
chroot "${TARGET}" /bin/bash -c "
    systemctl disable getty@tty1.service 2>/dev/null || true
    systemctl mask getty@tty1.service 2>/dev/null || true
"

echo "==> [Stage 01] Silent boot configuration complete."
