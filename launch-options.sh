#!/bin/bash

set -euo pipefail

# ---------------------------------------------------------------------------
# Steam Launch Options wrapper
# Config dir: ~/.config/steam-launch/
#   defaults.conf        — global defaults for all games
#   games/<APPID>.conf   — per-game overrides (merged on top of defaults)
# ---------------------------------------------------------------------------

APPID="${SteamGameId:-${SteamAppId:-unknown}}"
BASE="$HOME/.cache/game-shaders"
CONFIG_DIR="$HOME/.config/steam-launch"
DEFAULTS_CONF="$CONFIG_DIR/defaults.conf"
GAME_CONF="$CONFIG_DIR/games/$APPID.conf"

# --- Bootstrap default config on first run ---
if [[ ! -f "$DEFAULTS_CONF" ]]; then
    mkdir -p "$CONFIG_DIR/games"
    cat > "$DEFAULTS_CONF" <<'EOF'
# Steam Launch Options — global defaults
# Set any value to 0 to disable that feature for all games.
# Per-game overrides go in ~/.config/steam-launch/games/<APPID>.conf

# NVIDIA OpenGL shader disk cache
NVIDIA_SHADER_CACHE_ENABLED=1
# Size of the NVIDIA shader cache in bytes (default: 12 GiB)
NVIDIA_SHADER_CACHE_SIZE=12884901888

# DXVK state cache (DirectX 9/10/11 → Vulkan)
DXVK_ENABLED=1

# VKD3D shader cache (DirectX 12 → Vulkan)
VKD3D_ENABLED=1

# Mesa shader cache (open-source Vulkan/OpenGL drivers)
MESA_SHADER_CACHE_ENABLED=1
# Size of the Mesa shader cache (default: 12G)
MESA_SHADER_CACHE_MAX_SIZE=12G

# NTSync kernel synchronisation primitives
NTSYNC_ENABLED=1

# Proton NVIDIA library support (NVIDIA-native libs in Proton)
PROTON_NVIDIA_LIBS_ENABLED=1
# Disable the 32-bit NVIDIA libs (set to 0 only if 32-bit games break)
PROTON_NVIDIA_LIBS_NO_32BIT=1

# DLSS, NGX & DXR ray-tracing support
PROTON_DLSS_ENABLED=1
# Show DLSS on-screen indicator
PROTON_DLSS_INDICATOR=1
# Enable DXR (ray tracing) via VKD3D
VKD3D_DXR_ENABLED=1

# NVAPI & NGX updater (required for DLSS / RTX features)
PROTON_NVAPI_ENABLED=1

# NVIDIA Smooth Motion (driver-level frame generation)
NVIDIA_SMOOTH_MOTION_ENABLED=1
EOF
fi

# --- Load config (defaults, then per-game overrides) ---

# Built-in fallback values (used when config file is absent or a key is missing)
NVIDIA_SHADER_CACHE_ENABLED=1
NVIDIA_SHADER_CACHE_SIZE=12884901888
DXVK_ENABLED=1
VKD3D_ENABLED=1
MESA_SHADER_CACHE_ENABLED=1
MESA_SHADER_CACHE_MAX_SIZE=12G
NTSYNC_ENABLED=1
PROTON_NVIDIA_LIBS_ENABLED=1
PROTON_NVIDIA_LIBS_NO_32BIT=1
PROTON_DLSS_ENABLED=1
PROTON_DLSS_INDICATOR=1
VKD3D_DXR_ENABLED=1
PROTON_NVAPI_ENABLED=1
NVIDIA_SMOOTH_MOTION_ENABLED=1

# Source helper — strip comments and blank lines, then eval safe KEY=VALUE pairs
_load_conf() {
    local file="$1"
    while IFS= read -r line; do
        # Strip a trailing CR from CRLF files, then strip comments and trim whitespace
        line="${line%$'\r'}"
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"   # ltrim
        line="${line%"${line##*[![:space:]]}"}"   # rtrim
        [[ -z "$line" ]] && continue
        # Only allow KEY=VALUE where KEY is alphanumeric + underscore
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            declare -g "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
        fi
    done < "$file"
}

[[ -f "$DEFAULTS_CONF" ]] && _load_conf "$DEFAULTS_CONF"
[[ -f "$GAME_CONF"     ]] && _load_conf "$GAME_CONF"

# --- Set up cache directories ---
CACHE_DIR="$BASE/$APPID"
LOG_FILE="$BASE/$APPID.log"
mkdir -p "$CACHE_DIR/dxvk" "$CACHE_DIR/vkd3d" "$CACHE_DIR/mesa" "$CACHE_DIR/nvidia"

# --- Apply options ---

if [[ "$NVIDIA_SHADER_CACHE_ENABLED" == "1" ]]; then
    export __GL_SHADER_DISK_CACHE=1
    export __GL_SHADER_DISK_CACHE_PATH="$CACHE_DIR/nvidia"
    export __GL_SHADER_DISK_CACHE_SIZE="$NVIDIA_SHADER_CACHE_SIZE"
fi

if [[ "$DXVK_ENABLED" == "1" ]]; then
    export DXVK_STATE_CACHE=1
    export DXVK_STATE_CACHE_PATH="$CACHE_DIR/dxvk"
fi

if [[ "$VKD3D_ENABLED" == "1" ]]; then
    export VKD3D_SHADER_CACHE_PATH="$CACHE_DIR/vkd3d"
    export PROTON_LOCAL_SHADER_CACHE=1
fi

if [[ "$MESA_SHADER_CACHE_ENABLED" == "1" ]]; then
    export MESA_SHADER_CACHE_DIR="$CACHE_DIR/mesa"
    export MESA_SHADER_CACHE_MAX_SIZE="$MESA_SHADER_CACHE_MAX_SIZE"
fi

if [[ "$NTSYNC_ENABLED" == "1" ]]; then
    export NTSYNC=1
fi

if [[ "$PROTON_NVIDIA_LIBS_ENABLED" == "1" ]]; then
    export PROTON_NVIDIA_LIBS=1
    if [[ "$PROTON_NVIDIA_LIBS_NO_32BIT" == "1" ]]; then
        export PROTON_NVIDIA_LIBS_NO_32BIT=1
    fi
fi

if [[ "$PROTON_DLSS_ENABLED" == "1" ]]; then
    export PROTON_DLSS_UPGRADE=1
    [[ "$PROTON_DLSS_INDICATOR" == "1" ]] && export PROTON_DLSS_INDICATOR=1
fi

if [[ "$VKD3D_DXR_ENABLED" == "1" ]]; then
    export VKD3D_CONFIG=dxr11,dxr
fi

if [[ "$PROTON_NVAPI_ENABLED" == "1" ]] || [[ "$PROTON_DLSS_ENABLED" == "1" ]]; then
    export PROTON_ENABLE_NGX_UPDATER=1
fi

if [[ "$PROTON_NVAPI_ENABLED" == "1" ]]; then
    export PROTON_ENABLE_NVAPI=1
fi

if [[ "$NVIDIA_SMOOTH_MOTION_ENABLED" == "1" ]]; then
    export NVPRESENT_QUEUE_FAMILY=1
    export NVPRESENT_ENABLE_SMOOTH_MOTION=1
fi

# --- Logging ---
{
    echo "===== $(date '+%F %T') ====="
    echo "AppID:      $APPID"
    echo "PID:        $$"
    echo "User:       $USER"
    echo "PWD:        $PWD"
    echo "Command:    $*"
    echo "Cache DIR:  $CACHE_DIR"
    echo "Config:     $DEFAULTS_CONF"
    [[ -f "$GAME_CONF" ]] && echo "Game conf:  $GAME_CONF"
    echo "--- Active options ---"
    echo "NVIDIA shader cache:   $NVIDIA_SHADER_CACHE_ENABLED"
    echo "DXVK:                  $DXVK_ENABLED"
    echo "VKD3D:                 $VKD3D_ENABLED"
    echo "Mesa shader cache:     $MESA_SHADER_CACHE_ENABLED"
    echo "NTSync:                $NTSYNC_ENABLED"
    echo "Proton NVIDIA libs:    $PROTON_NVIDIA_LIBS_ENABLED"
    echo "DLSS/NGX:              $PROTON_DLSS_ENABLED"
    echo "NVAPI:                 $PROTON_NVAPI_ENABLED"
    echo "NVIDIA Smooth Motion:  $NVIDIA_SMOOTH_MOTION_ENABLED"
    echo "--- Environment (filtered) ---"
    env | grep -E 'Steam|DXVK|VKD3D|__GL|WAYLAND|DISPLAY|NTSYNC|PROTON|NVPRESENT|MESA' || true
    echo "============================="
} > "$LOG_FILE"

# Pipe stdout/stderr into log (append)
stdbuf -oL -eL "$@" 2>&1 | awk '!/wrong ELF class|fork without exec/' >>"$LOG_FILE"

