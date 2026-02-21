# dotfiles

Public configuration files for my development environment, managed with [GNU Stow](https://www.gnu.org/software/stow/).

**This repo is for public configs only.** No secrets, API keys, or private tooling.

## How it works

Each top-level directory is a stow "package". Stow symlinks its contents into `~`, so a file at `sway/.config/sway/config` becomes `~/.config/sway/config`. When adding new configs, mirror the target path inside the package directory.

## Packages

| Package | What it configures |
|---------|-------------------|
| `zsh` | Shell config, aliases, prompt |
| `tmux` | Terminal multiplexer keybindings and settings |
| `git` | Git user config |
| `bash` | Bash shell config |
| `ghostty` | Ghostty terminal theme and settings |
| `sway` | Sway window manager |
| `waybar` | Waybar status bar |
| `mako` | Mako notification daemon |
| `environment.d` | Systemd environment variables (e.g. Electron Wayland) |
| `zellij` | Zellij terminal multiplexer config and keybindings |

## Usage

### Prerequisites

```sh
# Fedora
sudo dnf install -y stow just

# macOS
brew install stow just
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
