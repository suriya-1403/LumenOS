#!/usr/bin/env bash
set -euo pipefail

echo "==> [Stage 04] Setting up Lumen interactive desktop (Sway) and default HUD..."

OPT_LUMEN="${TARGET}/opt/lumen"
mkdir -p "${OPT_LUMEN}/bin" "${OPT_LUMEN}/ui"

# 1. Create the default minimalist Smart Mirror HUD (Python/Tk or HTML)
cat > "${OPT_LUMEN}/bin/lumen-welcome.py" <<'EOF'
#!/usr/bin/env python3
"""
Lumen OS Default Smart Mirror HUD
Designed for two-way mirror glass: pure #000000 black background with white glowing elements.
"""
import sys
import time
import socket
import tkinter as tk

def get_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "Connecting..."

class LumenHUD:
    def __init__(self, root):
        self.root = root
        self.root.title("Lumen OS")
        self.root.configure(bg="#000000")
        self.root.attributes("-fullscreen", True)
        self.root.config(cursor="none")

        # Top Section: Digital Clock & Date
        self.top_frame = tk.Frame(root, bg="#000000")
        self.top_frame.pack(side="top", fill="x", pady=60, padx=60)

        self.time_label = tk.Label(
            self.top_frame,
            font=("Helvetica", 64, "bold"),
            fg="#FFFFFF",
            bg="#000000"
        )
        self.time_label.pack(anchor="nw")

        self.date_label = tk.Label(
            self.top_frame,
            font=("Helvetica", 24),
            fg="#A0A0A0",
            bg="#000000"
        )
        self.date_label.pack(anchor="nw", pady=(10, 0))

        # Center Section: Futuristic AI Greeting & Status
        self.center_frame = tk.Frame(root, bg="#000000")
        self.center_frame.pack(expand=True)

        self.logo_label = tk.Label(
            self.center_frame,
            text="◈  L U M E N  O S  ◈",
            font=("Helvetica", 22, "bold"),
            fg="#FFFFFF",
            bg="#000000"
        )
        self.logo_label.pack(pady=10)

        self.status_label = tk.Label(
            self.center_frame,
            text="OS CORE INITIALIZED\nAwaiting AI Assistant & Mirror Shell...",
            font=("Helvetica", 14),
            fg="#707070",
            bg="#000000",
            justify="center"
        )
        self.status_label.pack(pady=15)

        # Bottom Section: System Info & Network
        self.bottom_frame = tk.Frame(root, bg="#000000")
        self.bottom_frame.pack(side="bottom", fill="x", pady=40, padx=60)

        self.ip_label = tk.Label(
            self.bottom_frame,
            font=("Helvetica", 14),
            fg="#505050",
            bg="#000000"
        )
        self.ip_label.pack(anchor="sw")

        self.update_clock()

    def update_clock(self):
        current_time = time.strftime("%H:%M")
        current_date = time.strftime("%A, %B %d, %Y")
        ip = get_ip()

        self.time_label.config(text=current_time)
        self.date_label.config(text=current_date)
        self.ip_label.config(text=f"IP: {ip}  |  lumen.local")

        # Refresh every 1000ms
        self.root.after(1000, self.update_clock)

if __name__ == "__main__":
    # Install python3-tk dependency if needed
    root = tk.Tk()
    app = LumenHUD(root)
    root.mainloop()
EOF
chmod +x "${OPT_LUMEN}/bin/lumen-welcome.py"

# Ensure python3-tk is installed for the lightweight native HUD
chroot "${TARGET}" /bin/bash -c "
    apt-get update
    apt-get install -y --no-install-recommends python3-tk
"

# 2. Generate the Sway compositor configuration (fully user-customizable)
SWAY_CONFIG_DIR="${TARGET}/home/${DEFAULT_USER}/.config/sway"
WAYBAR_CONFIG_DIR="${TARGET}/home/${DEFAULT_USER}/.config/waybar"
mkdir -p "${SWAY_CONFIG_DIR}" "${WAYBAR_CONFIG_DIR}"

# Map DISPLAY_ROTATION (0-3) to a Sway output transform. Compositor-level
# rotation is the reliable mechanism under Wayland/KMS.
case "${DISPLAY_ROTATION}" in
    1) SWAY_TRANSFORM="90" ;;
    2) SWAY_TRANSFORM="180" ;;
    3) SWAY_TRANSFORM="270" ;;
    *) SWAY_TRANSFORM="normal" ;;
esac

cat > "${SWAY_CONFIG_DIR}/config" <<'EOF'
# Lumen OS Sway Configuration
# This file is yours - edit it freely to customize keybindings, theming, and
# what launches on boot. Reload changes with: swaymsg reload

xwayland enable

# Two-way mirror glass optimization: pure black background
output * bg #000000 solid_color
output * transform __SWAY_TRANSFORM__

set $mod Mod4
set $term foot
set $menu wofi --show drun

# Core keybindings
bindsym $mod+Return exec $term
bindsym $mod+d exec $menu
bindsym $mod+q kill
bindsym $mod+f fullscreen toggle
bindsym $mod+Shift+space floating toggle
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right
bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right
bindsym $mod+1 workspace number 1
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace number 3
bindsym $mod+4 workspace number 4
bindsym $mod+Shift+1 move container to workspace number 1
bindsym $mod+Shift+2 move container to workspace number 2
bindsym $mod+Shift+3 move container to workspace number 3
bindsym $mod+Shift+4 move container to workspace number 4
bindsym $mod+Shift+e exit

# Status bar (autostarted as its own layer-shell client - do not also use a
# 'bar { swaybar_command waybar }' block, or it will render twice)
exec waybar

# Autostart hook: launches your own custom UI from /opt/lumen/ui/start.sh if
# present and executable, otherwise falls back to the default Lumen HUD.
# Drop your own app in there to make Lumen boot straight into it.
exec sh -c 'if [ -x /opt/lumen/ui/start.sh ]; then exec /opt/lumen/ui/start.sh; else exec /usr/bin/python3 /opt/lumen/bin/lumen-welcome.py; fi'

# Keep the default/custom boot app fullscreen; add your own for_window rule
# here if your start.sh app opens a window with a different title.
for_window [title="Lumen OS"] fullscreen enable
EOF
sed -i "s/__SWAY_TRANSFORM__/${SWAY_TRANSFORM}/" "${SWAY_CONFIG_DIR}/config"

# 3. Generate a minimal Waybar status bar theme (also user-editable)
cat > "${WAYBAR_CONFIG_DIR}/config.jsonc" <<'EOF'
{
    "layer": "top",
    "position": "top",
    "height": 32,
    "modules-left": ["sway/workspaces", "sway/mode"],
    "modules-center": ["clock"],
    "modules-right": ["network", "pulseaudio"],
    "clock": {
        "format": "{:%H:%M   %A, %B %d}"
    },
    "network": {
        "format-wifi": "  {essid}",
        "format-ethernet": "  {ipaddr}",
        "format-disconnected": "Offline"
    },
    "pulseaudio": {
        "format": "{icon}  {volume}%",
        "format-muted": "Muted",
        "format-icons": ["", "", ""]
    }
}
EOF

cat > "${WAYBAR_CONFIG_DIR}/style.css" <<'EOF'
* {
    font-family: "Helvetica", sans-serif;
    font-size: 14px;
}
window#waybar {
    background-color: #000000;
    color: #FFFFFF;
}
#workspaces button {
    color: #707070;
    padding: 0 8px;
}
#workspaces button.focused {
    color: #FFFFFF;
}
#clock, #network, #pulseaudio {
    padding: 0 12px;
    color: #A0A0A0;
}
EOF

# Dotfiles are written as root during the chroot build - hand them back to
# the user, or the "customize completely" desktop is locked from its own owner.
chroot "${TARGET}" /bin/bash -c "
    chown -R ${DEFAULT_USER}:${DEFAULT_USER} /home/${DEFAULT_USER}/.config
"

# 4. Create the Desktop Launch Wrapper
cat > "${TARGET}/usr/local/bin/lumen-desktop" <<'EOF'
#!/usr/bin/env bash
# Lumen OS Sway Desktop Launcher
set -euo pipefail

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export WAYLAND_DISPLAY="wayland-0"
export XDG_CURRENT_DESKTOP=sway
export XDG_SESSION_TYPE=wayland
export WLR_NO_HARDWARE_CURSORS=1
export SEATD_SOCK="/run/seatd.sock"

# If running inside a QEMU VM (virtio-gpu without virgl), use the pixman
# software renderer since hardware GL acceleration isn't available there.
if ls /sys/bus/pci/devices/*virtio* >/dev/null 2>&1 || [[ -d /sys/bus/virtio ]]; then
    export WLR_RENDERER=pixman
fi

mkdir -p "${XDG_RUNTIME_DIR}"
chmod 0700 "${XDG_RUNTIME_DIR}"

echo "[LUMEN] Starting Sway interactive desktop on $(date)..."
exec sway
EOF
chmod +x "${TARGET}/usr/local/bin/lumen-desktop"

# 5. Create Systemd Service for the Lumen Desktop, bound to tty1
cat > "${TARGET}/etc/systemd/system/lumen-desktop.service" <<EOF
[Unit]
Description=Lumen OS Interactive Desktop Service (Sway)
After=network.target seatd.service sound.target systemd-user-sessions.service getty@tty1.service
Wants=seatd.service
Conflicts=getty@tty1.service

[Service]
Type=simple
User=${DEFAULT_USER}
Group=${DEFAULT_USER}
SupplementaryGroups=video render input seat
PAMName=login
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty-fail
StandardOutput=journal
StandardError=journal
Environment=HOME=/home/${DEFAULT_USER}
Environment=USER=${DEFAULT_USER}
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=SEATD_SOCK=/run/seatd.sock
ExecStart=/usr/local/bin/lumen-desktop
Restart=always
RestartSec=3

[Install]
WantedBy=graphical.target
EOF

# 6. Enable the service in the target system
chroot "${TARGET}" /bin/bash -c "
    systemctl enable lumen-desktop.service
"

echo "==> [Stage 04] Sway interactive desktop and default HUD complete."
