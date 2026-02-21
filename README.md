# dotfiles

Public configuration files for my development environment, managed with [GNU Stow](https://www.gnu.org/software/stow/).

**This repo is for public configs only.** No secrets, API keys, or private tooling.

## How it works

Each top-level directory is a stow "package". Stow symlinks its contents into `~`, so a file at `sway/.config/sway/config` becomes `~/.config/sway/config`. When adding new configs, mirror the target path inside the package directory.

Packages are split into **common** (linked on all platforms) and **Linux-only** (linked only on Linux). The justfile detects the OS automatically.

## Packages

### Common (Linux + macOS)

| Package | What it configures |
|---------|-------------------|
| `zsh` | Shell config, aliases, prompt |
| `tmux` | Terminal multiplexer keybindings and settings |
| `git` | Git user config |
| `bash` | Bash shell config |
| `ghostty` | Ghostty terminal theme and settings |
| `zellij` | Zellij terminal multiplexer config and keybindings |
| `bin` | Custom scripts (`~/.local/bin`) |

### Linux only

| Package | What it configures |
|---------|-------------------|
| `sway` | Sway window manager |
| `swaylock` | Lock screen appearance |
| `waybar` | Waybar status bar |
| `mako` | Mako notification daemon |
| `environment.d` | Systemd environment variables (e.g. Electron Wayland, PATH) |

## Dependencies

### Installed by `just setup`

**Fedora:**
`stow` `zsh` `zoxide` `fzf` `zellij` `tmux` `sway` `swaylock` `swayidle` `waybar` `mako` `wofi` `grim` `slurp` `wl-clipboard` `brightnessctl` `playerctl` `zsh-autosuggestions` `zsh-syntax-highlighting`

**macOS:**
`stow` `zsh` `zoxide` `fzf` `ghostty` `zellij` `tmux`

### Manual install required

| Package | Notes |
|---------|-------|
| `just` | Task runner. Install first: `dnf install just` / `brew install just` |
| `ghostty` (Fedora) | Not in default repos. Install from [ghostty.org](https://ghostty.org) or a COPR |
| `cargo` / Rust toolchain | For tools installed via cargo. Install from [rustup.rs](https://rustup.rs) |

## Usage

### Fresh machine setup

```sh
# Install prerequisites
sudo dnf install -y stow just   # Fedora
brew install stow just           # macOS

# Clone and set up
git clone git@github.com:SIRHAMY/dotfiles.git ~/Code/dotfiles
cd ~/Code/dotfiles
just setup
```

### Link everything

```sh
just all
```

### Link a single package

```sh
just stow zsh
```

### Unlink a single package

```sh
just unstow zsh
```

### Unlink everything

```sh
just unstow-all
```

### Dry run (see what would be linked)

```sh
just plan
```

### Reload running apps (Linux)

```sh
just reload
```
