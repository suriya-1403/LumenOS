#!/usr/bin/env bash
set -euo pipefail

echo "==> [Stage 03] Configuring Read-Only RootFS with OverlayFS (Power-Cut Resilience)..."

# 1. Install overlayroot from Debian repositories
chroot "${TARGET}" /bin/bash -c "
    apt-get update
    apt-get install -y --no-install-recommends overlayroot
"

# 2. Configure /etc/overlayroot.conf
# By default, we keep it configured with tmpfs.
cat > "${TARGET}/etc/overlayroot.conf" <<EOF
# Lumen OS OverlayFS Configuration
# When enabled, rootfs is mounted Read-Only, and all writes go to RAM (tmpfs).
# Sudden power removal will never corrupt the storage medium.
overlayroot="tmpfs"
EOF

# 3. Install the lumen-mode management CLI tool
cat > "${TARGET}/usr/local/bin/lumen-mode" <<'EOF'
#!/usr/bin/env bash
# Lumen OS Mode Controller (Read-Only vs Read-Write Maintenance)
set -euo pipefail

CONF="/etc/overlayroot.conf"

show_status() {
    if grep -q 'overlayroot="tmpfs"' "${CONF}" 2>/dev/null; then
        echo "[LUMEN OS] Status: PROTECTED (Read-Only Root with OverlayFS)"
        echo "Storage is safe from power cuts. Writes will not persist across reboots."
    else
        echo "[LUMEN OS] Status: MAINTENANCE (Read-Write Mode)"
        echo "WARNING: Changes are saved to disk. Perform a clean shutdown before removing power."
    fi
}

case "${1:-status}" in
    status)
        show_status
        ;;
    ro|protect)
        echo "[LUMEN OS] Enabling Read-Only protection..."
        sed -i 's/overlayroot=.*/overlayroot="tmpfs"/' "${CONF}"
        echo "Protection enabled. Reboot to activate: sudo reboot"
        ;;
    rw|maintenance)
        echo "[LUMEN OS] Enabling Read-Write maintenance mode..."
        sed -i 's/overlayroot=.*/overlayroot="disabled"/' "${CONF}"
        echo "Maintenance mode enabled. Reboot to apply: sudo reboot"
        ;;
    *)
        echo "Usage: lumen-mode [status | ro | rw]"
        echo "  status       Display current filesystem protection state"
        echo "  ro           Enable read-only overlay protection (safe for power cuts)"
        echo "  rw           Enable read-write mode (for installing updates and models)"
        exit 1
        ;;
esac
EOF

chmod +x "${TARGET}/usr/local/bin/lumen-mode"

echo "==> [Stage 03] OverlayFS configuration complete."
