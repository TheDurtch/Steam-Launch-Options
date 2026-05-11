# Steam Launch Options

A dynamic Steam game launcher wrapper for Linux that applies per-game environment variable profiles with a simple config file system. All options are enabled by default and can be toggled globally or on a per-game basis — no script editing required.

---

## Features

- **Shader caches** — NVIDIA OpenGL, DXVK (DX9/10/11), VKD3D (DX12), and Mesa caches are routed to a single organized directory under `~/.cache/game-shaders/<AppID>/`
- **Proton tweaks** — NVIDIA libs, DLSS upgrade, NGX updater, DXR ray tracing, and NVAPI
- **NTSync** — kernel-level synchronisation for lower CPU overhead
- **NVIDIA Smooth Motion** — driver-level frame generation
- **Per-game config** — override any option for a specific game without touching the script
- **Logging** — every launch is logged to `~/.cache/game-shaders/<AppID>.log`
- **Self-bootstrapping** — creates `~/.config/steam-launch/defaults.conf` on first run with all options documented inline

---

## Setup

### 1. Download the script

```bash
curl -Lo ~/.local/bin/launch-options.sh \
  https://raw.githubusercontent.com/TheDurtch/Steam-Launch-Options/main/launch-options.sh
chmod +x ~/.local/bin/launch-options.sh
```

### 2. Set Steam launch options

In Steam → right-click game → Properties → Launch Options, enter:

```
~/.local/bin/launch-options.sh %command%
```

That's it. The script will create your config file on first launch.

---

## Config

All config lives in `~/.config/steam-launch/`.

```
~/.config/steam-launch/
├── defaults.conf          # global defaults (all games)
└── games/
    ├── 570.conf           # per-game override for AppID 570 (Dota 2)
    ├── 1086940.conf       # per-game override for AppID 1086940 (BG3)
    └── ...
```

### `defaults.conf`

Created automatically on first run. Edit to change the global defaults for every game.

```ini
# NVIDIA OpenGL shader disk cache
NVIDIA_SHADER_CACHE_ENABLED=1
NVIDIA_SHADER_CACHE_SIZE=12884901888   # bytes (default 12 GiB)

# DXVK state cache (DirectX 9/10/11 → Vulkan)
DXVK_ENABLED=1

# VKD3D shader cache (DirectX 12 → Vulkan)
VKD3D_ENABLED=1

# Mesa shader cache (open-source Vulkan/OpenGL drivers)
MESA_SHADER_CACHE_ENABLED=1
MESA_SHADER_CACHE_MAX_SIZE=12G

# NTSync kernel synchronisation
NTSYNC_ENABLED=1

# Proton NVIDIA library support
PROTON_NVIDIA_LIBS_ENABLED=1
PROTON_NVIDIA_LIBS_NO_32BIT=1         # set to 0 if 32-bit games break

# DLSS upgrade (also triggers NGX updater when enabled)
PROTON_DLSS_ENABLED=1
PROTON_DLSS_INDICATOR=1               # on-screen DLSS indicator
VKD3D_DXR_ENABLED=1                   # DXR via VKD3D

# NVAPI & NGX updater (required for DLSS / RTX features)
PROTON_NVAPI_ENABLED=1

# NVIDIA Smooth Motion (driver-level frame generation)
NVIDIA_SMOOTH_MOTION_ENABLED=1
```

### Per-game overrides

Create `~/.config/steam-launch/games/<AppID>.conf` with only the keys you want to change. You do **not** need to copy the full defaults file — only the overrides.

**Example:** Disable DLSS and ray tracing for AppID 570 (Dota 2):

```bash
mkdir -p ~/.config/steam-launch/games
cat > ~/.config/steam-launch/games/570.conf <<'EOF'
PROTON_DLSS_ENABLED=0
VKD3D_DXR_ENABLED=0
PROTON_NVAPI_ENABLED=0
EOF
```

**Example:** Disable NTSync for a game that crashes with it:

```bash
cat > ~/.config/steam-launch/games/12345.conf <<'EOF'
NTSYNC_ENABLED=0
EOF
```

---

## Available options

| Option | Default | Description |
|---|---|---|
| `NVIDIA_SHADER_CACHE_ENABLED` | `1` | NVIDIA OpenGL shader disk cache (`__GL_SHADER_DISK_CACHE`) |
| `NVIDIA_SHADER_CACHE_SIZE` | `12884901888` | Cache size in bytes (12 GiB) |
| `DXVK_ENABLED` | `1` | DXVK state cache for DX9/10/11 games |
| `VKD3D_ENABLED` | `1` | VKD3D shader cache for DX12 games |
| `MESA_SHADER_CACHE_ENABLED` | `1` | Mesa shader cache for open-source GPU drivers |
| `MESA_SHADER_CACHE_MAX_SIZE` | `12G` | Mesa cache size limit |
| `NTSYNC_ENABLED` | `1` | NTSync kernel sync primitives |
| `PROTON_NVIDIA_LIBS_ENABLED` | `1` | Use NVIDIA-native libs inside Proton |
| `PROTON_NVIDIA_LIBS_NO_32BIT` | `1` | Disable 32-bit NVIDIA libs (safe for most games) |
| `PROTON_DLSS_ENABLED` | `1` | DLSS upgrade (`PROTON_DLSS_UPGRADE`); also enables NGX updater |
| `PROTON_DLSS_INDICATOR` | `1` | Show DLSS on-screen indicator |
| `VKD3D_DXR_ENABLED` | `1` | DXR (ray tracing) via VKD3D (`VKD3D_CONFIG=dxr11,dxr`) |
| `PROTON_NVAPI_ENABLED` | `1` | NVAPI support (`PROTON_ENABLE_NVAPI`); also enables NGX updater |
| `NVIDIA_SMOOTH_MOTION_ENABLED` | `1` | NVIDIA Smooth Motion frame generation |

---

## Logs

Each game writes a log to `~/.cache/game-shaders/<AppID>.log`. The log contains:

- Launch timestamp, AppID, PID, user, working directory, and command
- Which config files were loaded
- Active/inactive state of every option group
- Filtered environment variables at launch time
- Game stdout/stderr (filtered to remove noisy ELF errors)

```bash
# View the log for AppID 570
cat ~/.cache/game-shaders/570.log
```

---

## Shader cache location

All shader caches are stored under `~/.cache/game-shaders/<AppID>/`:

```
~/.cache/game-shaders/
└── 570/
    ├── dxvk/
    ├── vkd3d/
    ├── mesa/
    └── nvidia/
```

To clear the cache for a single game:

```bash
rm -rf ~/.cache/game-shaders/570
```

---

## Requirements

- Linux with Proton (Steam Play)
- NVIDIA GPU recommended (AMD users can disable `NVIDIA_*` and `PROTON_*` options in `defaults.conf`)
- `stdbuf` (part of GNU coreutils, pre-installed on most distros)

---

## License

[LICENSE](LICENSE)
