#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="/workspace"
CONFIG_FILE="${WORKSPACE}/os/config"
STAGES_DIR="${WORKSPACE}/os/stages"
OUTPUT_DIR="${WORKSPACE}/output"

# Source configuration
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
else
    echo "[ERROR] Config file not found at ${CONFIG_FILE}"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
IMAGE_NAME="${OS_NAME}-${DEBIAN_RELEASE}-${ARCH}-${TIMESTAMP}"
RAW_IMAGE="${OUTPUT_DIR}/${IMAGE_NAME}.img"
TARGET="/mnt/lumen"
LOOP_DEV=""

cleanup() {
    local exit_code=$?
    echo "[INFO] Cleaning up mount points and loop devices..."
    set +e
    if [[ -d "${TARGET}" ]]; then
        if mountpoint -q "${TARGET}/run"; then umount -l "${TARGET}/run"; fi
        if mountpoint -q "${TARGET}/dev/pts"; then umount -l "${TARGET}/dev/pts"; fi
        if mountpoint -q "${TARGET}/dev"; then umount -l "${TARGET}/dev"; fi
        if mountpoint -q "${TARGET}/proc"; then umount -l "${TARGET}/proc"; fi
        if mountpoint -q "${TARGET}/sys"; then umount -l "${TARGET}/sys"; fi
        if mountpoint -q "${TARGET}/boot/firmware"; then umount "${TARGET}/boot/firmware"; fi
        if mountpoint -q "${TARGET}"; then umount "${TARGET}"; fi
    fi
    if [[ -n "${LOOP_DEV}" ]]; then
        losetup -d "${LOOP_DEV}" 2>/dev/null || true
    fi
    if [[ ${exit_code} -ne 0 ]]; then
        echo "[ERROR] Build failed with status ${exit_code}."
        rm -f "${RAW_IMAGE}"
    fi
    exit ${exit_code}
}
trap cleanup EXIT INT TERM

echo "----------------------------------------------------"
echo "Starting Lumen OS build for ${DEBIAN_RELEASE} (${ARCH})"
echo "Image: ${RAW_IMAGE}"
echo "----------------------------------------------------"

# Step 1: Create sparse image file
echo "[1/8] Creating raw disk image (${IMAGE_SIZE_MB}MB)..."
truncate -s "${IMAGE_SIZE_MB}M" "${RAW_IMAGE}"

# Step 2: Partition the disk image (MBR for Pi bootloader)
echo "[2/8] Partitioning disk image..."
parted --script "${RAW_IMAGE}" \
    mklabel msdos \
    mkpart primary fat32 4MiB "$((BOOT_SIZE_MB + 4))MiB" \
    set 1 boot on \
    mkpart primary ext4 "$((BOOT_SIZE_MB + 4))MiB" 100%

# Step 3: Attach loop device and format partitions
echo "[3/8] Formatting partitions..."
LOOP_DEV=$(losetup -Pf --show "${RAW_IMAGE}")
echo "Attached loop device: ${LOOP_DEV}"

# Wait for kernel partition detection
sleep 2

PART_BOOT="${LOOP_DEV}p1"
PART_ROOT="${LOOP_DEV}p2"

mkfs.vfat -F 32 -n "bootfs" "${PART_BOOT}"
mkfs.ext4 -F -L "rootfs" "${PART_ROOT}"

# Retrieve PARTUUIDs for fstab and cmdline
export PARTUUID_BOOT
export PARTUUID_ROOT
PARTUUID_BOOT=$(blkid -s PARTUUID -o value "${PART_BOOT}")
PARTUUID_ROOT=$(blkid -s PARTUUID -o value "${PART_ROOT}")
echo "Boot PARTUUID: ${PARTUUID_BOOT}"
echo "Root PARTUUID: ${PARTUUID_ROOT}"

# Step 4: Mount target filesystem
echo "[4/8] Mounting filesystems..."
mkdir -p "${TARGET}"
mount "${PART_ROOT}" "${TARGET}"
mkdir -p "${TARGET}/boot/firmware"
mount "${PART_BOOT}" "${TARGET}/boot/firmware"

# Step 5: Debootstrap stage 1 (Foreign ARM64)
echo "[5/8] Running debootstrap stage 1 (${DEBIAN_RELEASE} ${ARCH})..."
debootstrap \
    --arch="${ARCH}" \
    --foreign \
    --components=main,contrib,non-free,non-free-firmware \
    "${DEBIAN_RELEASE}" \
    "${TARGET}" \
    "${DEBIAN_MIRROR}"

# Step 6: Prepare QEMU and complete debootstrap stage 2
echo "[6/8] Running debootstrap stage 2 in QEMU chroot..."
cp /usr/bin/qemu-aarch64-static "${TARGET}/usr/bin/"

mount_chroot() {
    mkdir -p "${TARGET}/proc" "${TARGET}/sys" "${TARGET}/dev" "${TARGET}/dev/pts" "${TARGET}/run" "${TARGET}/boot/firmware"
    mountpoint -q "${TARGET}/proc" || mount -t proc proc "${TARGET}/proc"
    mountpoint -q "${TARGET}/sys" || mount -t sysfs sysfs "${TARGET}/sys"
    mountpoint -q "${TARGET}/dev" || mount --bind /dev "${TARGET}/dev"
    mountpoint -q "${TARGET}/dev/pts" || mount --bind /dev/pts "${TARGET}/dev/pts"
    mountpoint -q "${TARGET}/run" || mount -t tmpfs tmpfs "${TARGET}/run"
    mountpoint -q "${TARGET}/boot/firmware" || mount "${PART_BOOT}" "${TARGET}/boot/firmware"
}

# Mount before second-stage
mount_chroot

# Complete debootstrap inside chroot
chroot "${TARGET}" /debootstrap/debootstrap --second-stage

# debootstrap unmounts proc/sys on completion, so remount for custom stages
mount_chroot

# Prevent daemons from trying to start inside the cross-build chroot
cat > "${TARGET}/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF
chmod +x "${TARGET}/usr/sbin/policy-rc.d"

# Force dpkg and apt to never prompt on conffile changes or stdin
mkdir -p "${TARGET}/etc/apt/apt.conf.d" "${TARGET}/etc/dpkg/dpkg.cfg.d"
cat > "${TARGET}/etc/apt/apt.conf.d/70debconf" <<'EOF'
Dpkg::Options {
   "--force-confdef";
   "--force-confold";
};
APT::Get::Assume-Yes "true";
EOF

cat > "${TARGET}/etc/dpkg/dpkg.cfg.d/force-conf" <<'EOF'
force-confdef
force-confold
EOF

# Step 7: Execute modular Lumen stages
echo "[7/8] Executing Lumen customization stages..."
export DEBIAN_FRONTEND=noninteractive
export UCF_FORCE_CONFFOLD=1

for stage in "${STAGES_DIR}"/*.sh; do
    if [[ -f "${stage}" ]]; then
        echo ">>> Running stage: $(basename "${stage}")"
        # Ensure mounts are active before each stage
        mount_chroot
        # Source the stage script in the build context
        # shellcheck source=/dev/null
        source "${stage}"
    fi
done

# Step 8: Clean up, unmount, and compress image
echo "[8/8] Finalizing image and compressing..."

# Remove temporary QEMU binary, policy-rc.d, and dpkg prompt overrides
rm -f "${TARGET}/usr/bin/qemu-aarch64-static"
rm -f "${TARGET}/usr/sbin/policy-rc.d"
rm -f "${TARGET}/etc/apt/apt.conf.d/70debconf" "${TARGET}/etc/dpkg/dpkg.cfg.d/force-conf"

# Clean package manager cache
chroot "${TARGET}" apt-get clean || true
rm -rf "${TARGET}/var/lib/apt/lists/*" "${TARGET}/tmp/*" "${TARGET}/var/tmp/*"

# Sync and unmount
sync
if mountpoint -q "${TARGET}/run"; then umount -l "${TARGET}/run"; fi
umount -l "${TARGET}/dev/pts"
umount -l "${TARGET}/dev"
umount -l "${TARGET}/proc"
umount -l "${TARGET}/sys"
umount "${TARGET}/boot/firmware"
umount "${TARGET}"
losetup -d "${LOOP_DEV}"
LOOP_DEV=""

echo "Compressing ${RAW_IMAGE} with xz (multi-threaded)..."
xz -T0 -v -9 "${RAW_IMAGE}"

FINAL_IMAGE="${RAW_IMAGE}.xz"
echo "Generating SHA256 checksum..."
sha256sum "${FINAL_IMAGE}" > "${FINAL_IMAGE}.sha256"

echo "Build complete: ${FINAL_IMAGE}"
