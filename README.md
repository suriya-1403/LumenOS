# ◈ LUMEN OS ◈

> **Lumen OS** is an ambient, AI-first embedded operating system built from scratch for smart mirrors, powered by **Debian 13 (Trixie) ARM64** for Raspberry Pi 4 and 5.

---

## ✦ Key Features

- **⚡ Fast & Silent Boot**: Stripped of desktop bloat, rainbow splashes, boot logs, and blinking cursors. Boots straight into your smart mirror HUD in seconds.
- **🛡️ Power-Cut Resilient (Read-Only Root with OverlayFS)**: Designed for wall-mounted appliances where users pull the plug. All writes go to RAM (`tmpfs`). Storage will **never corrupt**.
- **🪞 Optical Physics Optimization**: Built for two-way mirror glass—pure `#000000` true black allows seamless mirror reflection, while glowing elements appear holographically on the surface.
- **🖥️ Interactive Wayland Desktop (Sway)**: Uses the `sway` tiling Wayland compositor with direct DRM/KMS hardware acceleration (Mesa V3D/VC4) — real multi-app window management and workspaces, entirely config-file driven, instead of a locked single-app kiosk or a bulky desktop environment.
- **🎙️ AI Voice & Audio Graph (PipeWire)**: Low-latency audio pipeline pre-configured for USB microphone arrays and audio output.
- **📶 Zero-Touch Headless Wi-Fi Setup**: Drop a `wifi.txt` into the boot drive on your Mac/PC, and the mirror connects automatically on first boot.

---

## ✦ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 LUMEN SHELL (Visual Interface)              │
│    Sway Tiling Compositor  |  Waybar + Wofi + Foot           │
│    Custom UI Autostart Hook  |  Fallback: Ambient HUD        │
├─────────────────────────────────────────────────────────────┤
│                 LUMEN BRAIN (AI Companion Core)             │
│   PipeWire Mic Routing  |  Wake Word  |  STT  |  TTS  | LLM │
├─────────────────────────────────────────────────────────────┤
│                 LUMEN BASE (Debian 13 Trixie)               │
│       OverlayFS Read-Only Root  |  Silent Kernel (6.6+)     │
│       Raspberry Pi 4 / 5 Hardware Acceleration (Mesa V3D)   │
└─────────────────────────────────────────────────────────────┘
```

---

## ✦ Quick Start: Building the OS

The build system is containerized with Docker and QEMU, meaning you can build the complete bootable ARM64 image on **macOS** or **Linux** with one command.

### 1. Prerequisites
- [Docker Desktop](https://www.docker.com/) running on your system.

### 2. Build the Disk Image
Run the host builder script:

```bash
chmod +x os/build.sh
./os/build.sh
```

The script will:
1. Spin up the build container.
2. Partition the virtual disk (FAT32 boot + EXT4 root).
3. Debootstrap a clean Debian 13 (Trixie) ARM64 system.
4. Apply the silent boot, Wayland desktop (Sway), PipeWire, and OverlayFS stages.
5. Compress the final image into `output/lumen-os-trixie-arm64-<timestamp>.img.xz`.

---

## ✦ Flashing to SD Card or NVMe SSD

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) or [BalenaEtcher](https://etcher.balena.io/):

1. Select **Use Custom** in Raspberry Pi Imager.
2. Choose `output/lumen-os-trixie-arm64-*.img.xz`.
3. Select your SD Card / NVMe drive and click **Write**.

---

## ✦ Headless Wi-Fi Setup

After flashing, keep the SD card plugged into your computer:
1. Open the visible `bootfs` partition.
2. Create a file named `wifi.txt`:
   ```bash
   SSID="YourHomeWiFiNetwork"
   PASSWORD="YourSecretPassword"
   ```
3. Eject the SD card and insert it into your Raspberry Pi. Lumen OS will automatically import the Wi-Fi credentials on first boot.

---

## ✦ Default System Credentials

| Property | Value |
| :--- | :--- |
| **Hostname** | `lumen` (`lumen.local`) |
| **Default User** | `lumen` |
| **Default Password** | `lumenpassword` |
| **SSH** | Enabled on port `22` |
| **Sudo** | Passwordless sudo enabled for `lumen` |

---

## ✦ Managing Filesystem Protection (`lumen-mode`)

Lumen OS protects storage by mounting the root partition as read-only with an in-memory overlay:

```bash
# Check current filesystem protection status
lumen-mode status

# Switch to Read-Write maintenance mode (e.g. to install packages or AI models)
lumen-mode rw
sudo reboot

# Re-enable Read-Only protection after updates
lumen-mode ro
sudo reboot
```

---

## ✦ Display Orientation (Portrait Mode)

Smart mirrors are usually mounted in portrait orientation (vertical). Rotation
is controlled by the `DISPLAY_ROTATION` setting in `os/config` (0/1/2/3 =
normal/90/180/270), which is applied at build time as a Sway `output *
transform` line in `/home/lumen/.config/sway/config`.

To change it after flashing, without rebuilding the image:
1. Edit `~/.config/sway/config` on the device (or over SSH).
2. Change the `output * transform` line, e.g.:
   ```
   output * transform 90
   ```
3. Apply immediately with `swaymsg reload`, or `sudo reboot`.

---

## ✦ Interactive Desktop & Customization

Lumen boots into a real interactive Sway session, not a locked single-app
kiosk — you get workspaces, window switching, a terminal, and a launcher.
Default keybindings (fully yours to change in `~/.config/sway/config`):

| Keys | Action |
| :--- | :--- |
| `Super + Return` | Open a terminal (`foot`) |
| `Super + D` | Open the app launcher (`wofi`) |
| `Super + Q` | Close the focused window |
| `Super + F` | Toggle fullscreen |
| `Super + 1-4` | Switch workspace |
| `Super + Shift + 1-4` | Move window to workspace |
| `Super + Shift + E` | Exit the Sway session |

**Loading your own UI**: drop an executable script at `/opt/lumen/ui/start.sh`
and it will autostart on boot instead of the default HUD — it still runs
inside the live desktop, so you can switch away from it, open a terminal over
it, or run it alongside other apps. Sway (`~/.config/sway/config`) and Waybar
(`~/.config/waybar/`) are ordinary user config files — edit them freely.

---

## ✦ Project Structure

```
Lumen/
├── os/                         # OS Image Builder & Customization Stages
│   ├── config                  # Distribution, user, and sizing settings
│   ├── Dockerfile              # Cross-compilation container definition
│   ├── build.sh                # Host-level build launcher
│   ├── builder-internal.sh     # Partitioning & debootstrap orchestrator
│   └── stages/                 # Modular system customization stages
│       ├── 00-base-system.sh   # Debian Trixie + RPi kernel & firmware
│       ├── 01-silent-boot.sh   # Silent bootloader & cmdline configuration
│       ├── 02-graphics-audio.sh# Wayland (Sway), Mesa 3D, PipeWire audio
│       ├── 03-overlayfs.sh     # Read-only root protection & lumen-mode CLI
│       ├── 04-desktop-shell.sh # Sway desktop service & default mirror HUD
│       └── 05-firstboot-network.sh # Headless Wi-Fi import
├── output/                     # Generated .img.xz artifacts (gitignored)
├── run-vm.sh                   # QEMU VM launcher for testing images locally
├── brain/                      # (Next) AI assistant service & voice pipeline
└── ui/                         # (Next) Web / Native smart mirror interface
```
