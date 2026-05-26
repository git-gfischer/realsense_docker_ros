#!/bin/bash
# =============================================================================
# 00_patch_host_kernel.sh
#
# PURPOSE: Patch the Jetson host kernel to support RealSense cameras via the
#          native V4L backend. This MUST be run on the Jetson board itself,
#          NOT inside Docker (containers share the host kernel).
#
# TESTED ON: Jetson AGX Orin + JetPack 6.0 (L4T 36.3.0)
#
# USAGE:
#   chmod +x 00_patch_host_kernel.sh
#   ./00_patch_host_kernel.sh
#
# REQUIREMENTS:
#   - ~2.5 GB free disk space (kernel source will be downloaded)
#   - Internet connection
#   - Jetson in Max power mode (nvpmodel -m 0)
#   - No USB/UVC cameras attached during patching
#   - Run as a user with sudo privileges
# =============================================================================

set -euo pipefail

LIBREALSENSE_VERSION="v2.55.1"
WORK_DIR="/tmp/librealsense_kernel_patch"

# ── Preflight checks ──────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  RealSense L4T Kernel Patch — Jetson AGX Orin / JetPack 6.0 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Verify we are on a Jetson
if ! grep -q "NVIDIA Tegra" /proc/device-tree/model 2>/dev/null; then
  echo "⚠️  WARNING: This does not appear to be a Jetson board."
  echo "   Proceeding anyway — press Ctrl+C within 5s to abort."
  sleep 5
fi

# Check free disk space (need ~2.5 GB)
FREE_KB=$(df /usr/src --output=avail | tail -1)
if [ "${FREE_KB}" -lt 2621440 ]; then
  echo "❌ ERROR: Not enough free space. Need ~2.5 GB, have $((FREE_KB / 1024)) MB."
  exit 1
fi
echo "✔ Disk space OK ($((FREE_KB / 1024)) MB available)"

# Warn about USB cameras
echo ""
echo "⚠️  Make sure all USB/UVC cameras are UNPLUGGED before continuing."
read -rp "   Are all cameras disconnected? [y/N] " ans
[[ "${ans,,}" == "y" ]] || { echo "Aborting. Disconnect cameras and re-run."; exit 1; }

# ── Set max power mode ────────────────────────────────────────────────────────
echo ""
echo "→ Setting Jetson to Max power mode (nvpmodel -m 0)..."
sudo nvpmodel -m 0 || echo "  (nvpmodel not found — skip if not on Jetson)"

# ── Clone librealsense ────────────────────────────────────────────────────────
echo ""
echo "→ Cloning librealsense ${LIBREALSENSE_VERSION} into ${WORK_DIR}..."
rm -rf "${WORK_DIR}"
git clone \
  --depth 1 \
  --branch "${LIBREALSENSE_VERSION}" \
  https://github.com/IntelRealSense/librealsense.git \
  "${WORK_DIR}"
cd "${WORK_DIR}"

# ── Run the L4T patch script ──────────────────────────────────────────────────
echo ""
echo "→ Running patch-realsense-ubuntu-L4T.sh  (this takes ~30 min)..."
echo "  The script will fetch the kernel source, apply patches, and"
echo "  insert the modified modules. Do NOT interrupt."
echo ""
./scripts/patch-realsense-ubuntu-L4T.sh

# ── Verify modules loaded ─────────────────────────────────────────────────────
echo ""
echo "→ Verifying patched kernel modules..."
for mod in uvcvideo videodev; do
  if lsmod | grep -q "^${mod}"; then
    echo "  ✔ ${mod} loaded"
  else
    echo "  ✘ ${mod} NOT loaded — check patch output above"
  fi
done

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║  Kernel patching complete!                                ║"
echo "║  You can now run:  docker compose up --build              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "NOTE: A reboot is NOT required — modules were inserted live."
echo "      However, they will persist across reboots thanks to the"
echo "      patch script overwriting the stock modules."
