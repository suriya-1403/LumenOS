#!/usr/bin/env bash
set -euo pipefail

echo "==> [Stage 05] Configuring headless first-boot Wi-Fi importer..."

# Create a systemd service that checks for wifi.txt or wpa_supplicant.conf on /boot/firmware
cat > "${TARGET}/usr/local/bin/lumen-firstboot-network" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

BOOT_DIR="/boot/firmware"
WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
WIFI_TXT="${BOOT_DIR}/wifi.txt"
BOOT_WPA="${BOOT_DIR}/wpa_supplicant.conf"

# Case 1: Direct wpa_supplicant.conf placed on boot partition
if [[ -f "${BOOT_WPA}" ]]; then
    echo "[LUMEN-NET] Importing wpa_supplicant.conf from boot partition..."
    mv "${BOOT_WPA}" "${WPA_CONF}"
    chmod 600 "${WPA_CONF}"
    systemctl restart wpa_supplicant.service || true
fi

# Case 2: Simple wifi.txt key-value file
# Format:
# SSID="YourWiFi"
# PASSWORD="YourPassword"
if [[ -f "${WIFI_TXT}" ]]; then
    echo "[LUMEN-NET] Parsing wifi.txt from boot partition..."
    SSID=""
    PASSWORD=""
    # shellcheck source=/dev/null
    source "${WIFI_TXT}"
    if [[ -n "${SSID}" && -n "${PASSWORD}" ]]; then
        wpa_passphrase "${SSID}" "${PASSWORD}" >> "${WPA_CONF}"
        chmod 600 "${WPA_CONF}"
        systemctl restart wpa_supplicant.service || true
        # Remove plaintext wifi.txt for security once imported
        mv "${WIFI_TXT}" "${WIFI_TXT}.imported"
    fi
fi
EOF
chmod +x "${TARGET}/usr/local/bin/lumen-firstboot-network"

cat > "${TARGET}/etc/systemd/system/lumen-firstboot-network.service" <<EOF
[Unit]
Description=Lumen OS First-Boot Wi-Fi Importer
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/lumen-firstboot-network
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

chroot "${TARGET}" /bin/bash -c "
    systemctl enable lumen-firstboot-network.service
"

echo "==> [Stage 05] First-boot network importer configured."
