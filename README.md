# dotfiles

Public configuration files for my development environment, managed with [GNU Stow](https://www.gnu.org/software/stow/).

**This repo is for public configs only.** No secrets, API keys, or private tooling.

## Packages

| Package | What it configures |
|---------|-------------------|
| `zsh` | Shell config, aliases, prompt |
| `tmux` | Terminal multiplexer keybindings and settings |
| `git` | Git user config |
| `bash` | Bash shell config |
| `ghostty` | Ghostty terminal theme and settings |

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
