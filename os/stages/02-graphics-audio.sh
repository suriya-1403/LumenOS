#!/usr/bin/env bash
set -euo pipefail

echo "==> [Stage 02] Installing graphics stack (Wayland/Sway) and audio (PipeWire)..."

# 1. Install the Sway interactive desktop, Mesa 3D Drivers, and Seat Management
chroot "${TARGET}" /bin/bash -c "
    apt-get update
    apt-get install -y --no-install-recommends \
        sway \
        foot \
        wofi \
        waybar \
        swaybg \
        dbus-user-session \
        libpam-systemd \
        seatd \
        xwayland \
        mesa-va-drivers \
        libgl1-mesa-dri \
        libegl-mesa0 \
        wlr-randr

    # Enable seatd for unprivileged user DRM/KMS access
    getent group seat >/dev/null 2>&1 || groupadd -r seat
    usermod -aG seat ${DEFAULT_USER}
    systemctl enable seatd
"

# 2. Install Audio Subsystem (PipeWire + WirePlumber)
chroot "${TARGET}" /bin/bash -c "
    apt-get install -y --no-install-recommends \
        pipewire \
        wireplumber \
        pipewire-pulse \
        pipewire-alsa \
        alsa-utils \
        libasound2-dev \
        libportaudio2 \
        portaudio19-dev \
        ffmpeg
"

# 3. Install Python 3 Runtime & AI Tooling Prerequisites
chroot "${TARGET}" /bin/bash -c "
    apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        build-essential \
        git
"

echo "==> [Stage 02] Graphics and audio stack installation complete."
