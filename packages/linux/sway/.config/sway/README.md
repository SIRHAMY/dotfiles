# Sway Configuration

`$mod` = Super/Windows key

## Keybindings

### Basics

| Key | Action |
|-----|--------|
| `$mod+Return` | Open terminal (Ghostty) |
| `$mod+d` | App launcher (Wofi) |
| `$mod+Shift+q` | Kill focused window |
| `$mod+Shift+c` | Reload sway config |
| `$mod+Shift+e` | Exit sway (with confirmation) |
| `$mod+Escape` | Lock screen |

### Navigation

| Key | Action |
|-----|--------|
| `$mod+h/j/k/l` | Focus left/down/up/right |
| `$mod+Arrow Keys` | Focus left/down/up/right |
| `$mod+Shift+h/j/k/l` | Move window left/down/up/right |
| `$mod+Shift+Arrow Keys` | Move window left/down/up/right |
| `$mod+Ctrl+h/l` | Move workspace to output left/right |
| `$mod+Ctrl+Left/Right` | Move workspace to output left/right |

### Workspaces

| Key | Action |
|-----|--------|
| `$mod+1-0` | Switch to workspace 1-10 |
| `$mod+Shift+1-0` | Move container to workspace 1-10 |
| `$mod+n` | Rename workspace |

### Layout

| Key | Action |
|-----|--------|
| `$mod+minus` | Horizontal split |
| `$mod+backslash` | Vertical split |
| `$mod+s` | Stacking layout |
| `$mod+w` | Tabbed layout |
| `$mod+e` | Toggle split direction |
| `$mod+f` | Fullscreen |
| `$mod+Shift+space` | Toggle floating |
| `$mod+space` | Toggle focus between floating/tiled |
| `$mod+a` | Focus parent container |
| `$mod+Shift+s` | Sticky toggle (window follows across workspaces) |

### Scratchpad

| Key | Action |
|-----|--------|
| `$mod+grave` | Show scratchpad |
| `$mod+Shift+grave` | Move window to scratchpad |

### Resize

Two options: resize mode for fine-tuning, or direct bindings for quick adjustments.

**Resize mode** (enter with `$mod+r`, exit with Escape/Return):

| Key | Action |
|-----|--------|
| `h/l` or `Left/Right` | Shrink/grow width (10px) |
| `j/k` or `Down/Up` | Grow/shrink height (10px) |

**Direct resize** (no mode needed):

| Key | Action |
|-----|--------|
| `$mod+Alt+h` | Shrink width (40px) |
| `$mod+Alt+l` | Grow width (40px) |
| `$mod+Alt+k` | Shrink height (40px) |
| `$mod+Alt+j` | Grow height (40px) |

### Media / Hardware

| Key | Action |
|-----|--------|
| `XF86AudioMute` | Toggle mute |
| `XF86AudioLowerVolume` | Volume down 5% |
| `XF86AudioRaiseVolume` | Volume up 5% |
| `XF86AudioMicMute` | Toggle mic mute |
| `XF86MonBrightnessDown` | Brightness down 5% |
| `XF86MonBrightnessUp` | Brightness up 5% |
| `XF86AudioPlay` | Play/pause |
| `XF86AudioNext` | Next track |
| `XF86AudioPrev` | Previous track |

### Screenshots

| Key | Action |
|-----|--------|
| `Print` | Full screen to file (`~/Pictures/`) |
| `$mod+Ctrl+s` | Select area to clipboard |
| `$mod+Shift+Print` | Select area to file (`~/Pictures/`) |

### Launchers

| Key | Action |
|-----|--------|
| `$mod+p` | Zellij sessionizer (floating) |
| `$mod+v` | Clipboard history (requires cliphist) |

## Modifier Key Philosophy

| Modifier | Purpose |
|----------|---------|
| `$mod` | Navigation, focus, common actions |
| `$mod+Shift` | Move things, destructive actions, toggles |
| `$mod+Ctrl` | Workspace-to-output, screenshots |
| `$mod+Alt` | Direct resize |

## Display Setup

- **Laptop** (eDP-1): 2560x1600, scale 1.5x
- **Left monitor** (DP-2): 2560x1440, vertical (rotated 270)
- **Right monitor** (DP-1): 2560x1440, landscape

## Appearance

- 1px pixel borders, 4px inner gaps, 2px outer gaps
- Dark theme (#161616 background) with emerald green (#10b981) accents
- Caps Lock remapped to Escape (Shift+Caps Lock for actual Caps Lock)

## Waybar Modules

Left: workspaces, mode | Center: window title | Right: CPU, memory, disk, network, battery, volume, brightness, clock, tray

All modules use Font Awesome 6 icons. Hover for tooltips with detailed info.

## Autostart

- Waybar (status bar)
- Mako (notifications)
- Dropbox
- cliphist (clipboard history daemon)

## Dependencies

- **ghostty** - terminal
- **wofi** - app launcher
- **grim** + **slurp** - screenshots
- **wl-clipboard** (`wl-copy`) - clipboard
- **cliphist** - clipboard history (needs manual install)
- **swaylock** - lock screen
- **swayidle** - idle management
- **brightnessctl** - brightness control
- **playerctl** - media control
- **pactl** (PulseAudio/PipeWire) - volume control
- **mako** - notifications
- **waybar** - status bar
