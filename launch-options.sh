#!/bin/bash

set -euo pipefail


APPID="${SteamGameId:-${SteamAppId:-unknown}}"
BASE="$HOME/.cache/game-shaders"

CACHE_DIR="$BASE/$APPID"
LOG_FILE="$BASE/$APPID.log"
mkdir -p "$CACHE_DIR" "$CACHE_DIR/dxvk" "$CACHE_DIR/vkd3d" "$CACHE_DIR/mesa" "$CACHE_DIR/nvidia"

# --- NVIDIA shader cache ---
export __GL_SHADER_DISK_CACHE=1
export __GL_SHADER_DISK_CACHE_PATH="$CACHE_DIR/nvidia"
export __GL_SHADER_DISK_CACHE_SIZE=12884901888

# --- DXVK ---
export DXVK_STATE_CACHE=1
export DXVK_STATE_CACHE_PATH="$CACHE_DIR/dxvk"

# --- VKD3D ---
export VKD3D_SHADER_CACHE_PATH="$CACHE_DIR/vkd3d"
export PROTON_LOCAL_SHADER_CACHE=1
export PROTON_NVIDIA_LIBS=1
export PROTON_NVIDIA_LIBS_NO_32BIT=1
export PROTON_DLSS_UPGRADE=1
export PROTON_DLSS_INDICATOR=1
export VKD3D_CONFIG=dxr11,dxr
export PROTON_ENABLE_NVAPI=1
export PROTON_ENABLE_NGX_UPDATER=1

export MESA_SHADER_CACHE_DIR="$CACHE_DIR/mesa"
export MESA_SHADER_CACHE_MAX_SIZE=12G

export NTSYNC=1

# --- NVIDIA Smooth Motion ---

export NVPRESENT_QUEUE_FAMILY=1
export NVPRESENT_ENABLE_SMOOTH_MOTION=1

# --- Logging ---
{
    echo "===== $(date '+%F %T') ====="
    echo "AppID: $APPID"
    echo "PID: $$"
    echo "User: $USER"
    echo "PWD: $PWD"
    echo "Command: $*"
    echo "Cache DIR: $CACHE_DIR"
    echo "--- Environment (filtered) ---"
    env | grep -E 'Steam|DXVK|VKD3D|__GL|WAYLAND|DISPLAY|NTSYNC'
    echo "============================="
} > "$LOG_FILE"


# Pipe stdout/stderr into log (append)
stdbuf -oL -eL "$@" 2>&1 | awk '!/wrong ELF class|fork without exec/' >>"$LOG_FILE"

