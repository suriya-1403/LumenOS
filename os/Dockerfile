FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install host build dependencies for cross-building ARM64 disk images
RUN apt-get update && apt-get install -y --no-install-recommends \
    debootstrap \
    qemu-user-static \
    binfmt-support \
    parted \
    dosfstools \
    e2fsprogs \
    kpartx \
    udev \
    xz-utils \
    curl \
    ca-certificates \
    gnupg \
    sudo \
    git \
    rsync \
    procps \
    coreutils \
    util-linux \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

ENTRYPOINT ["/bin/bash", "/workspace/os/builder-internal.sh"]
