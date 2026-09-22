#!/usr/bin/env bash
set -euo pipefail

echo "==> [Stage 00] Configuring base system, kernel, and firmware..."

# 1. Configure Hostname and Hosts
echo "${HOSTNAME}" > "${TARGET}/etc/hostname"
cat > "${TARGET}/etc/hosts" <<EOF
127.0.0.1   localhost
127.0.1.1   ${HOSTNAME}
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

# 2. Configure /etc/fstab with PARTUUIDs
cat > "${TARGET}/etc/fstab" <<EOF
# <file system>             <mount point>   <type>  <options>       <dump>  <pass>
PARTUUID=${PARTUUID_ROOT}   /               ext4    defaults,noatime  0       1
PARTUUID=${PARTUUID_BOOT}   /boot/firmware  vfat    defaults          0       2
EOF

# 3. Configure Debian Trixie APT Sources (main, contrib, non-free, non-free-firmware)
cat > "${TARGET}/etc/apt/sources.list" <<EOF
deb ${DEBIAN_MIRROR} ${DEBIAN_RELEASE} main contrib non-free non-free-firmware
deb ${DEBIAN_MIRROR} ${DEBIAN_RELEASE}-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security ${DEBIAN_RELEASE}-security main contrib non-free non-free-firmware
EOF

# 4. Set up DNS inside chroot for package downloads
cat > "${TARGET}/etc/resolv.conf" <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# 5. Bypass buggy z50-raspi-firmware hooks that fail in cross-build chroot environments
mkdir -p "${TARGET}/etc/kernel/postinst.d" "${TARGET}/etc/initramfs/post-update.d"
chroot "${TARGET}" /bin/bash -c "
    dpkg-divert --add --divert /etc/kernel/postinst.d/z50-raspi-firmware.disabled --rename /etc/kernel/postinst.d/z50-raspi-firmware 2>/dev/null || true
    dpkg-divert --add --divert /etc/initramfs/post-update.d/z50-raspi-firmware.disabled --rename /etc/initramfs/post-update.d/z50-raspi-firmware 2>/dev/null || true
"
cat > "${TARGET}/etc/kernel/postinst.d/z50-raspi-firmware" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "${TARGET}/etc/kernel/postinst.d/z50-raspi-firmware"

cat > "${TARGET}/etc/initramfs/post-update.d/z50-raspi-firmware" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "${TARGET}/etc/initramfs/post-update.d/z50-raspi-firmware"

# 7. Update packages and install core firmware, kernel, and utilities
chroot "${TARGET}" /bin/bash -c "
    apt-get update
    apt-get install -y --no-install-recommends \
        locales \
        tzdata \
        sudo \
        curl \
        ca-certificates \
        chrony \
        wpasupplicant \
        wireless-regdb \
        openssh-server \
        systemd-resolved \
        kmod \
        udev \
        pciutils \
        usbutils \
        zstd \
        dosfstools

    # Install Raspberry Pi Bootloader/Firmware, Linux 6.x ARM64 Kernel, and Wi-Fi/BT firmware
    apt-get install -y --no-install-recommends \
        raspi-firmware \
        linux-image-arm64 \
        firmware-brcm80211
"

# Set ROOTPART in raspi-firmware defaults after package has been unpacked
echo "ROOTPART=\"PARTUUID=${PARTUUID_ROOT}\"" > "${TARGET}/etc/default/raspi-firmware"

# 7. Configure Timezone and Locale
chroot "${TARGET}" /bin/bash -c "
    echo '${LOCALE} UTF-8' >> /etc/locale.gen
    locale-gen
    update-locale LANG=${LOCALE}
    ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
"

# 8. Create Default User (lumen) and Configure Sudo
chroot "${TARGET}" /bin/bash -c "
    if ! id -u ${DEFAULT_USER} >/dev/null 2>&1; then
        useradd -m -s /bin/bash -G sudo,audio,video,input,render ${DEFAULT_USER}
        echo '${DEFAULT_USER}:${DEFAULT_PASSWORD}' | chpasswd
    fi
    # Add passwordless sudo for appliance convenience
    echo '${DEFAULT_USER} ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/010_${DEFAULT_USER}-nopasswd
    chmod 0440 /etc/sudoers.d/010_${DEFAULT_USER}-nopasswd
"

# 9. Enable essential services
chroot "${TARGET}" /bin/bash -c "
    systemctl enable ssh
    systemctl enable chrony
    systemctl enable systemd-resolved
"

echo "==> [Stage 00] Base system configuration complete."
