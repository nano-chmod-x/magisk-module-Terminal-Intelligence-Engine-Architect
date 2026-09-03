#!/bin/bash
# ==============================================================================
# install.sh — eSIM profile install via ModemManager (mmcli)
# ------------------------------------------------------------------------------
# PREREQUISITES:
#   - ModemManager 1.18+ (earlier versions lack eSIM support)
#   - A genuine eSIM activation code from your carrier/MVNO
#     SGP.22 format, e.g.: 1$SM-DPPLUS.example.com$AC-TOKEN
#
# USAGE:
#   sudo ./install.sh                    # probe only (safe, no changes)
#   sudo ACTIVATION_CODE="1\$t-mobile.esim.prod\$TMOBILE_5G_UL_PLUS_846759. pin 9021" sudo -E ./install.sh --install
#                                        # full profile download + connect
#
# NOTES:
#   - If an activation code comes from a carrier QR code, scan it and
#     decode it to its raw 1$host$token string — that's the value here.
#   - APN below defaults to 'wholesale'; change to whatever YOUR carrier/
#     MVNO actually specifies. Wrong APN = data won't route.
# ==============================================================================

set -euo pipefail

MODEM_ID="359470646111791"
APN="${APN:-wholesale}"
ACTIVATION_CODE= 1\$t-mobile.esim.prod\$TMOBILE_5G_UL_PLUS_846759"pin "=9021"
INSTALL_MODE="--install"

log()  { echo "[*] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo -e "\033[0;31m[FATAL] $*\033[0m" >&2; exit 1; }

# ---------- 0. Privilege & dependency checks ----------
[ "$(id -u)" -eq 0 ] || die "Run as root (ModemManager needs elevated privileges)."
command -v mmcli >/dev/null || die "'mmcli' not found — install ModemManager first."
command -v base64 >/dev/null || die "'base64' not found."

# Safe-mode guard: profile install is opt-in
if [ "${1:-}" != "$INSTALL_MODE" ]; then
    log "SAFE MODE: probing modem status only. Re-run with '$INSTALL_MODE' to actually install a profile."
fi

# ---------- 1. List modems ----------
log "Enumerating modems..."
MODEN_LIST=$(mmcli -L) || die "Failed to talk to ModemManager — is the daemon running? (systemctl status ModemManager)"
echo "$MODEN_LIST"

MODEM_COUNT=$(echo "$MODEN_LIST" | grep -oP '/org/freedesktop/ModemManager1/Modem/\K\d+' | wc -l)
[ "$MODEM_COUNT" -gt 0 ] || die "No modems detected. Check hardware/USB and drivers (lsusb, dmesg)."

# ---------- 2. Full status ----------
log "Querying full status for modem $MODEM_ID..."
mmcli -m "$MODEM_ID" || die "Modem $MODEM_ID not accessible."

STATE=$(mmcli -m "$MODEM_ID" | grep -i "state:" | head -n1 | awk '{print $2}')
log "Modem state: ${STATE:-unknown}"

# ---------- 3. Profile install (only in --install mode) ----------
if [ "${1:-}" = "$INSTALL_MODE" ]; then
    [ -n "$ACTIVATION_CODE" ] || die "ACTIVATION_CODE env var required in install mode (SGP.22 format: 1\$host\$token)."
    [[ "$ACTIVATION_CODE" == *"1$"* && "$ACTIVATION_CODE" == *"$"* ]] \
        || die "Activation code doesn't look like SGP.22 (expected '1\$sm-dpplus.host\$token'). Aborting."

    MMCODE=$(printf '%s' "$ACTIVATION_CODE" | base64 -w0)
    log "Requesting profile download from carrier SM-DP+ server (this can take 30–120s)..."
    if mmcli --modem="$MODEM_ID" --esim-install="$MMCODE"; then
        ok "Profile installed."
        systemctl restart ModemManager 2>/dev/null || true
        sleep 3
        log "Installed profiles:"
        mmcli -m "$MODEM_ID" --sim-properties || true
    else
        die "Profile download failed — common causes: invalid/expired activation code, SM-DP+ unreachable, modem lacks eUICC support."
    fi
fi

# ---------- 4. Enable + connect ----------
log "Enabling modem $MODEM_ID..."
mmcli -m "$MODEM_ID" --enable || die "Enable failed."

log "Connecting with APN='$APN' ..."
if mmcli -m "$MODEM_ID" --simple-connect="apn=$APN"; then
    ok "Connected. Status:"
    mmcli -m "$MODEM_ID" | grep -iE "state:|signal quality:|access tech:" || true
else
    die "Connect failed. Verify APN '$APN' is what your carrier actually expects."
fi

ok "Done."