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

# --- Detect GPU vendor (nvidia / amd / unknown) ---
_detect_gpu_vendor() {
    # Primary: /sys/class/drm vendor IDs (NVIDIA=0x10de, AMD=0x1002)
    local v
    for v in /sys/class/drm/card*/device/vendor; do
        [[ -f "$v" ]] || continue
        local id; id=$(< "$v")
        case "$id" in
            0x10de) echo "nvidia"; return ;;
            0x1002) echo "amd";    return ;;
        esac
    done
    # Secondary: lspci string matching
    if command -v lspci &>/dev/null; then
        local pci_out
        pci_out=$(lspci 2>/dev/null | grep -Ei 'VGA compatible controller|3D controller|Display controller' || true)
        if echo "$pci_out" | grep -qi 'nvidia'; then
            echo "nvidia"; return
        elif echo "$pci_out" | grep -Eqi 'amd|radeon|advanced micro devices'; then
            echo "amd"; return
        fi
    fi
    # Ultimate fallback: vendor unknown -- only basic/shared flags will be applied
    echo "unknown"
}

# --- Bootstrap default config on first run ---
if [[ ! -f "$DEFAULTS_CONF" ]]; then
    mkdir -p "$CONFIG_DIR/games"
    cat > "$DEFAULTS_CONF" <<'EOF'
# Steam Launch Options — global defaults
# Set any value to 0 to disable that feature for all games.
# Per-game overrides go in ~/.config/steam-launch/games/<APPID>.conf

# GPU vendor override: auto (detect), nvidia, or amd
GPU_VENDOR_OVERRIDE=auto

# ── NVIDIA-specific options ─────────────────────────────────────────────────

# NVIDIA OpenGL shader disk cache
NVIDIA_SHADER_CACHE_ENABLED=1
# Size of the NVIDIA shader cache in bytes (default: 12 GiB)
NVIDIA_SHADER_CACHE_SIZE=12884901888

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

# ── AMD-specific options ─────────────────────────────────────────────────────

# RADV (Mesa Vulkan) performance-test features
# Common flags: gpl (pipeline libraries), ngg (next-gen geometry),
#               nggc (NGG culling), rt (ray tracing)
RADV_PERFTEST_ENABLED=1
RADV_PERFTEST_FLAGS=gpl,ngg

# AMD Vulkan ICD to use: RADV (Mesa, recommended) or AMDVLK (AMD proprietary)
AMD_VULKAN_ICD=RADV

# Wine/Proton FSR (FidelityFX Super Resolution) upscaling
WINE_FSR_ENABLED=1
# FSR sharpness: 0 = Ultra Quality, 1 = Quality, 2 = Balanced,
#                3 = Performance, 4 = Ultra Performance, 5 = max sharpening
WINE_FSR_STRENGTH=2

# ── Shared options ───────────────────────────────────────────────────────────

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
EOF
fi

# --- Load config (defaults, then per-game overrides) ---

# Built-in fallback values (used when config file is absent or a key is missing)
GPU_VENDOR_OVERRIDE=auto
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
RADV_PERFTEST_ENABLED=1
RADV_PERFTEST_FLAGS=gpl,ngg
AMD_VULKAN_ICD=RADV
WINE_FSR_ENABLED=1
WINE_FSR_STRENGTH=2

# Variables that must never be overridden from config files.
# Includes shell internals and script-critical vars.
readonly _CONF_DENYLIST=(
    # Shell / POSIX internals
    IFS PATH HOME USER UID EUID PPID SHLVL PWD OLDPWD
    BASH BASH_VERSION BASHOPTS SHELLOPTS BASH_ENV
    PS1 PS2 PS3 PS4
    # Script-internal variables
    APPID BASE CONFIG_DIR DEFAULTS_CONF GAME_CONF CACHE_DIR LOG_FILE GPU_VENDOR
    # Security-sensitive loader variables
    LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT
)

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
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            # Reject denied keys
            local denied=0
            local d
            for d in "${_CONF_DENYLIST[@]}"; do
                if [[ "$key" == "$d" ]]; then
                    denied=1
                    break
                fi
            done
            if (( denied )); then
                echo "[steam-launch] WARNING: config '$file' tried to set denied variable '$key' — ignored." >&2
            else
                declare -g "${key}=${val}"
            fi
        fi
    done < "$file"
}

[[ -f "$DEFAULTS_CONF" ]] && _load_conf "$DEFAULTS_CONF"
[[ -f "$GAME_CONF"     ]] && _load_conf "$GAME_CONF"

# --- Resolve GPU vendor ---
if [[ "$GPU_VENDOR_OVERRIDE" == "auto" ]]; then
    GPU_VENDOR=$(_detect_gpu_vendor)
else
    GPU_VENDOR="${GPU_VENDOR_OVERRIDE,,}"   # normalise to lowercase
fi

# --- Set up cache directories ---
CACHE_DIR="$BASE/$APPID"
LOG_FILE="$BASE/$APPID.log"
mkdir -p "$CACHE_DIR/dxvk" "$CACHE_DIR/vkd3d" "$CACHE_DIR/mesa" "$CACHE_DIR/nvidia" "$CACHE_DIR/amd"

# --- Apply options ---

if [[ "$NVIDIA_SHADER_CACHE_ENABLED" == "1" ]] && [[ "$GPU_VENDOR" == "nvidia" ]]; then
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

if [[ "$PROTON_NVIDIA_LIBS_ENABLED" == "1" ]] && [[ "$GPU_VENDOR" == "nvidia" ]]; then
    export PROTON_NVIDIA_LIBS=1
    if [[ "$PROTON_NVIDIA_LIBS_NO_32BIT" == "1" ]]; then
        export PROTON_NVIDIA_LIBS_NO_32BIT=1
    fi
fi

if [[ "$PROTON_DLSS_ENABLED" == "1" ]] && [[ "$GPU_VENDOR" == "nvidia" ]]; then
    export PROTON_DLSS_UPGRADE=1
    [[ "$PROTON_DLSS_INDICATOR" == "1" ]] && export PROTON_DLSS_INDICATOR=1
fi

if [[ "$VKD3D_DXR_ENABLED" == "1" ]] && [[ "$GPU_VENDOR" == "nvidia" ]]; then
    export VKD3D_CONFIG=dxr11,dxr
fi

if { [[ "$PROTON_NVAPI_ENABLED" == "1" ]] || [[ "$PROTON_DLSS_ENABLED" == "1" ]]; } && [[ "$GPU_VENDOR" == "nvidia" ]]; then
    export PROTON_ENABLE_NGX_UPDATER=1
fi

if [[ "$PROTON_NVAPI_ENABLED" == "1" ]] && [[ "$GPU_VENDOR" == "nvidia" ]]; then
    export PROTON_ENABLE_NVAPI=1
fi

if [[ "$NVIDIA_SMOOTH_MOTION_ENABLED" == "1" ]] && [[ "$GPU_VENDOR" == "nvidia" ]]; then
    export NVPRESENT_QUEUE_FAMILY=1
    export NVPRESENT_ENABLE_SMOOTH_MOTION=1
fi

# --- AMD-specific options ---

if [[ "$GPU_VENDOR" == "amd" ]]; then
    if [[ "$RADV_PERFTEST_ENABLED" == "1" ]] && [[ -n "$RADV_PERFTEST_FLAGS" ]]; then
        export RADV_PERFTEST="$RADV_PERFTEST_FLAGS"
    fi

    if [[ -n "$AMD_VULKAN_ICD" ]]; then
        export AMD_VULKAN_ICD
    fi

    if [[ "$WINE_FSR_ENABLED" == "1" ]]; then
        export WINE_FULLSCREEN_FSR=1
        export WINE_FULLSCREEN_FSR_STRENGTH="$WINE_FSR_STRENGTH"
    fi
fi

# --- Logging ---
{
    echo "===== $(date '+%F %T') ====="
    echo "AppID:      $APPID"
    echo "PID:        $$"
    echo "User:       ${USER:-unknown}"
    echo "PWD:        ${PWD:-$(pwd)}"
    echo "Command:    $*"
    echo "Cache DIR:  $CACHE_DIR"
    echo "Config:     $DEFAULTS_CONF"
    [[ -f "$GAME_CONF" ]] && echo "Game conf:  $GAME_CONF"
    echo "GPU vendor: $GPU_VENDOR"
    if [[ "$GPU_VENDOR" == "unknown" ]]; then
        echo "WARNING: GPU vendor could not be detected — only basic/shared flags are active (DXVK, VKD3D, Mesa, NTSync). Vendor-specific options (NVIDIA/AMD) are disabled."
    fi
    echo "--- Active options ---"
    echo "DXVK:                  $DXVK_ENABLED"
    echo "VKD3D:                 $VKD3D_ENABLED"
    echo "Mesa shader cache:     $MESA_SHADER_CACHE_ENABLED"
    echo "NTSync:                $NTSYNC_ENABLED"
    if [[ "$GPU_VENDOR" == "nvidia" ]]; then
        echo "NVIDIA shader cache:   $NVIDIA_SHADER_CACHE_ENABLED"
        echo "Proton NVIDIA libs:    $PROTON_NVIDIA_LIBS_ENABLED"
        echo "DLSS/NGX:              $PROTON_DLSS_ENABLED"
        echo "NVAPI:                 $PROTON_NVAPI_ENABLED"
        echo "NVIDIA Smooth Motion:  $NVIDIA_SMOOTH_MOTION_ENABLED"
    fi
    if [[ "$GPU_VENDOR" == "amd" ]]; then
        echo "RADV perftest:         $RADV_PERFTEST_ENABLED ($RADV_PERFTEST_FLAGS)"
        echo "AMD Vulkan ICD:        $AMD_VULKAN_ICD"
        echo "Wine FSR:              $WINE_FSR_ENABLED (strength=$WINE_FSR_STRENGTH)"
    fi
    echo "--- Environment (filtered) ---"
    env | grep -E 'Steam|DXVK|VKD3D|__GL|WAYLAND|DISPLAY|NTSYNC|PROTON|NVPRESENT|MESA|RADV|AMD_VULKAN|WINE_FULLSCREEN' || true
    echo "============================="
} > "$LOG_FILE"

# Pipe stdout/stderr into log (append)
stdbuf -oL -eL "$@" 2>&1 | awk '!/wrong ELF class|fork without exec/' >>"$LOG_FILE"

