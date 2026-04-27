# Design: Cross-OS Dotfiles Restructure

**ID:** WRK-001
**Status:** Complete
**Created:** 2026-04-24
**PRD:** ./WRK-001_cross-os-restructure_PRD.md
**Tech Research:** ./WRK-001_cross-os-restructure_TECH_RESEARCH.md
**Mode:** Light

## TL;DR

- **Approach:** Three-rule architecture as specified in the PRD — `packages/{common,linux,macos}/<pkg>` buckets; `conf.d/` loader pattern for shared-but-divergent apps (zsh today; tmux scaffolded in the common loader only); filesystem-based OS dispatch via `uname -s`-keyed directory globs. No new invention beyond what the PRD already locked in; this design formalizes layout, flows, and the handful of specifics the PRD left implementation-phase: directory tree, loader source lines, tmux quiet-source incantation, Homebrew prefix resolution, pre-existing-dotfile handling, brew shellenv bootstrap for non-login Mac shells, `.stowrc` fix, the AeroSpace→sway keybind mapping, and the reversibility recipes (`unstow-all`, `restow`).
- **Key decisions:**
  1. **Three-bucket layout** with per-bucket `stow -d` invocations in the justfile; shared directories (`conf.d/`, `.local/bin/`) have a `.gitkeep` placeholder in the common package to prevent stow tree-folding. Loader contract is documented explicitly.
  2. **Loader corrections from research** — tmux uses `source-file -q` (not PRD's `-b`) for missing-file tolerance; macOS zsh uses `${HOMEBREW_PREFIX:=$(brew --prefix)}` (not bare `$(brew --prefix)`); loader dispatch uses `case $OSTYPE` (no fork) instead of `uname -s` (two forks per shell start).
  3. **Pattern B for pre-existing dotfiles** — a `check-conflicts` pre-flight walks the package tree directly (no stow-output parsing) and fails loudly with a remediation message naming each conflicting file. Simpler, format-independent, and aligned with the PRD's "either (a) back up or (b) exit non-zero" clause. Backup is left to the user via the printed `mv ...pre-stow.bak` commands.
  4. **Mac shell bootstrap** — `packages/macos/zsh-macos` ships a `$ZDOTDIR/.zshenv` that evals `brew shellenv` with Intel-path fallback. This fixes non-login interactive shells (new tmux/zellij panes) where `/etc/zprofile` isn't re-read.
- **Tradeoffs:** (a) Accepting a tiny startup cost from the `conf.d` glob+source loop (~1 ms range on typical snippet counts, Mac included) in exchange for branch-free configs. (b) Accepting a larger package count (one app can have up to three packages: `zsh`, `zsh-linux`, `zsh-macos`) in exchange for filesystem-based OS dispatch. (c) `source-file -q` (tmux) is silent on missing files, which also means silent on typo — acknowledged and mitigated by the loader-contract rule.
- **Needs attention:** None blocking. Two items deliberately deferred to day-1 Mac experience: AeroSpace `alt-return`/launcher bindings (held until you know whether you want Spotlight/Raycast/direct binding) and the Mac port of `zellij-sessionizer` (sway-coupled; revisit after AeroSpace floating-window behavior is settled in use). ARCHITECTURE.md is skipped; README absorbs everything that would have lived there.

## Overview

The dotfiles repo moves from a flat `<pkg>/`-at-root layout with `packages_common` / `packages_linux` lists in the justfile, to a `packages/{common,linux,macos}/<pkg>/` tree. Shared-but-divergent apps (today: `zsh`; scaffolded for `tmux`) adopt a `conf.d/` loader: a single, OS-agnostic loader stub sources a lexicographic glob of common snippets, then a glob of `conf.d/os.<osname>/*` snippets where `<osname>` is a normalized OS key. Every OS branch lives in a filename or directory path, never in a `case $OSTYPE` block inside a config body. The one `case $OSTYPE` in the repo is in the loader's bootstrap (one line, picks the directory to glob) — filesystem dispatch, not in-body conditionals.

The justfile keeps its OS-branching — a necessary evil for "which package manager to call" — but reduces it to three package lists and per-bucket `stow` invocations. Config files themselves become portable by construction: grep for `darwin` across the repo and you'll find files, not conditionals.

Migration from the existing Fedora layout is a one-shot `git mv` pass (to preserve blame), a re-stow, and a recompile of the existing `.zshrc` into `conf.d/` snippets — splitting lines that are Fedora-specific (plugin sources under `/usr/share/zsh-*`, `vim=vimx` alias, hardcoded opencode path) into `zsh-linux` while the rest becomes common. Incidental `.zshrc` bugs touched by the move (duplicate `PATH` export, missing newline before a `source` line, unguarded `$HOME/.cargo/env` source, hardcoded `/home/sirhamy/.opencode/bin`) get fixed as part of the split, per PRD scope.

---

## System Design

### High-Level Architecture

```
dotfiles/
├── justfile                 # OS dispatch (install-deps + which buckets to stow)
├── README.md
├── ARCHITECTURE.md          # (nice-to-have per PRD) three-rule pattern explainer
│
├── packages/
│   ├── common/              # Stowed on every OS
│   │   ├── zsh/
│   │   │   ├── .zshenv                            # tiny: exports ZDOTDIR
│   │   │   └── .config/zsh/
│   │   │       ├── .zshrc                         # loader
│   │   │       └── conf.d/
│   │   │           ├── .gitkeep                   # dir-guard (prevents stow fold — DO NOT DELETE)
│   │   │           ├── 10-shell.zsh               # history, completion, options, keybinds
│   │   │           ├── 20-prompt.zsh              # PROMPT, RPROMPT
│   │   │           ├── 30-path.zsh                # portable PATH + zoxide init
│   │   │           ├── 40-functions.zsh           # zp()
│   │   │           └── 50-aliases.zsh             # portable aliases only
│   │   ├── tmux/            # loader-only (conf.d scaffolding; no OS packages yet)
│   │   ├── ghostty/         # plain config (no preemptive scaffold — added at first real divergence)
│   │   ├── zellij/
│   │   ├── nvim/
│   │   ├── yazi/
│   │   ├── git/
│   │   ├── bash/
│   │   └── bin/
│   │       └── .local/bin/
│   │           └── .gitkeep                       # dir-guard; common bin is empty for this change
│   │
│   ├── linux/               # Stowed on Linux (Fedora) only
│   │   ├── zsh-linux/
│   │   │   └── .config/zsh/conf.d/os.linux/
│   │   │       ├── 10-plugins.zsh                 # Fedora /usr/share/zsh-* sources
│   │   │       ├── 20-aliases.zsh                 # vim=vimx
│   │   │       └── 30-paths.zsh                   # opencode, cargo env
│   │   ├── bin-linux/
│   │   │   └── .local/bin/
│   │   │       ├── sway-launch
│   │   │       ├── obsidian-scratchpad
│   │   │       ├── scratchpad-toggle
│   │   │       └── zellij-sessionizer             # sway-coupled; Mac port deferred
│   │   ├── sway/
│   │   ├── swaylock/
│   │   ├── waybar/
│   │   ├── mako/
│   │   ├── wofi/
│   │   ├── fontconfig/
│   │   └── environment.d/
│   │
│   └── macos/               # Stowed on Mac only
│       ├── zsh-macos/
│       │   └── .config/zsh/
│       │       ├── .zshenv                        # brew shellenv bootstrap (runs every zsh, incl. non-login)
│       │       └── conf.d/os.darwin/
│       │           ├── 10-brew.zsh                # plugin sources via $HOMEBREW_PREFIX
│       │           └── 20-aliases.zsh             # mac-specific (e.g. ls -G)
│       └── aerospace/
│           └── .config/aerospace/aerospace.toml
│
└── changes/                 # This change-tracking directory, unchanged by the restructure
```

**Key property:** every file's path names its OS context. `packages/macos/zsh-macos/.config/zsh/conf.d/os.darwin/10-brew.zsh` tells you at a glance what platform it affects.

> **Note on placeholder packages:** `bin-macos` is intentionally omitted for this change. The PRD requires all three buckets *exist*, not that every placeholder package exists. The first Mac-specific script creates `packages/macos/bin-macos/` at that time — a one-file add, same as adding any package. This mirrors the design's treatment of `tmux-{linux,macos}` and `ghostty-{linux,macos}`.

### Loader Contract

Before components, make the contract explicit. This is the load-bearing invariant that keeps the architecture coherent:

**Rule 1 — Directory-guard ownership.** Each shared target directory (`~/.config/zsh/conf.d/`, `~/.local/bin/`) is owned by a `.gitkeep` inside the common package. OS-specific packages MUST NOT also place a `.gitkeep` in the same dir. This prevents stow from tree-folding the directory into a single symlink and enables multi-package contribution.

**Rule 2 — OS-specific contents live under `conf.d/os.<key>/`.** An OS-specific zsh package MUST only add files under `conf.d/os.<key>/`. Never add files directly to `conf.d/`. Never add an `os.darwin/` dir from a Linux package or vice versa. If you need to override a common snippet, add an OS-specific snippet with the same numeric prefix — the loader sources OS-specific *after* common, so last-write wins.

**Rule 3 — Key-to-bucket match.** `linux` bucket uses `os.linux/`; `macos` bucket uses `os.darwin/`. The bucket names (per the PRD, matching directory names) and the loader keys (matching `uname -s` normalized) are different by design — bucket is what you *install*, key is what `$OSTYPE` matches at runtime.

**Rule 4 — No `exit` / `return N` at snippet top level.** Snippets are `source`d by the loader. An `exit 1` kills the login shell. Use guarded conditionals (`[ -r "$f" ] && source "$f"`) for anything that might not exist.

**Rule 5 — Fail-safe loader.** A missing `conf.d/os.<key>/` directory is tolerated (not an error). A syntax error in a snippet prints to stderr (via zsh's normal source-error handling) and the loader moves on. A broken snippet must never abort zsh startup.

The `check-conflicts` recipe (see justfile below) enforces Rule 1 by dry-run-walking the package tree. Rules 2–4 are author discipline, documented here and in README.

### Component Breakdown

#### `packages/common/zsh` — The Loader Package

**Purpose:** Owns the `ZDOTDIR` bootstrap, the loader, and all OS-agnostic snippets. Also owns the `conf.d/` directory on disk (via `.gitkeep`) so OS-specific packages can drop sibling subdirs without stow tree-folding collisions.

**Contents:**
- `.zshenv` (stows to `~/.zshenv`) — respects pre-existing `ZDOTDIR`:
  ```sh
  : "${ZDOTDIR:=$HOME/.config/zsh}"
  export ZDOTDIR
  ```
- `.config/zsh/.zshrc` — the loader (below)
- `.config/zsh/conf.d/.gitkeep` — dir-guard (comment inside: "kept un-folded by stow; DO NOT DELETE")
- `.config/zsh/conf.d/*.zsh` — ordered common snippets (numeric prefix)

**Loader (`.config/zsh/.zshrc`):**

```sh
# ~/.config/zsh/.zshrc  (stowed from packages/common/zsh)
# Filesystem-based OS dispatch. No case $OSTYPE inside snippets.
# conf.d/ is kept un-folded by a .gitkeep in packages/common/zsh — do not delete.

# Fast OS-key dispatch (no fork in common cases). Fallback handles WSL and
# anything unusual.
case "$OSTYPE" in
  darwin*) os_key=darwin ;;
  linux*)  os_key=linux ;;
  *)       os_key="$(uname -s | tr '[:upper:]' '[:lower:]')" ;;
esac

ZDOTCONFD="${ZDOTDIR:-$HOME/.config/zsh}/conf.d"

# null_glob: a no-match glob expands to nothing (missing dir = tolerated).
# Errors from source (syntax errors, unreadable files) print to stderr and
# the for loop continues — we deliberately do NOT `|| print` here, because
# it would also fire on snippets whose last command legitimately returns
# non-zero (e.g. a guarded `[ -d X ] && ...`).
setopt null_glob
for f in "$ZDOTCONFD"/*.zsh "$ZDOTCONFD/os.$os_key"/*.zsh; do
  [ -r "$f" ] || continue
  source "$f"
done
unsetopt null_glob
unset ZDOTCONFD os_key
```

Rules enforced by the loader:
- **Common before OS-specific.** Lexicographic within each tier: `10-shell.zsh` (common) loads before `10-plugins.zsh` (os.darwin/). OS-specific files with the same numeric prefix as a common file are intentional overrides.
- **Missing `os.<key>/` dir is tolerated** via `null_glob`.
- **A broken snippet does not abort login.** zsh prints the error from `source`, the loop moves on.
- **No fork in common cases.** `case $OSTYPE` (a parameter match) beats `$(uname -s)` + pipe (two forks, ~1–2 ms on a slow Mac).
- **Numeric prefix ordering.** Snippets use `NN-name.zsh` so load order is explicit.

**Interfaces:**
- **Input:** `ZDOTDIR` (from `.zshenv`), `$OSTYPE` (from zsh).
- **Output:** a fully-initialized interactive zsh session.

**Dependencies:** zsh 5.x. No external commands in the common dispatch; `uname` only as fallback for unknown `$OSTYPE`.

**Common snippet content (from current `.zshrc`, consolidated into 5 files):**

- `10-shell.zsh`: history options, completion init + zstyle, `setopt` flags (AUTO_CD, CORRECT, GLOB_DOTS), history-search keybinds.
- `20-prompt.zsh`: `PROMPT`, `RPROMPT`.
- `30-path.zsh`: `export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"` (deduped) + `eval "$(zoxide init zsh)"`.
- `40-functions.zsh`: `zp()` function as-is.
- `50-aliases.zsh`: `clauded`, `zls`, `za`. (No `vim=vimx` — that's Fedora-only, moves to `zsh-linux`.)

#### `packages/{linux,macos}/zsh-<os>` — OS-Specific Snippet Bundles

**Linux contents:**
- `.config/zsh/conf.d/os.linux/10-plugins.zsh`:
  ```sh
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  ```
- `.config/zsh/conf.d/os.linux/20-aliases.zsh`:
  ```sh
  alias vim='vimx'   # Fedora's X11-clipboard vim binary
  ```
- `.config/zsh/conf.d/os.linux/30-paths.zsh`:
  ```sh
  [ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
  [ -d "$HOME/.opencode/bin" ] && PATH="$HOME/.opencode/bin:$PATH"
  ```

**Mac contents:**
- `.config/zsh/.zshenv` — **brew shellenv bootstrap** (stowed to `~/.config/zsh/.zshenv`, which zsh reads *after* `~/.zshenv` on every invocation — including non-login shells like new tmux panes):
  ```sh
  # Bootstrap Homebrew's env for every zsh, not just login shells.
  # /etc/zprofile usually does this but (a) non-login shells skip it, (b) a
  # managed Mac may not have it. Idempotent: no-op if already set.
  if [ -z "${HOMEBREW_PREFIX-}" ]; then
    if   [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ];    then eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi
  ```
- `.config/zsh/conf.d/os.darwin/10-brew.zsh` — plugin sources using the now-guaranteed `$HOMEBREW_PREFIX`:
  ```sh
  [ -r "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ] && \
      source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  [ -r "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ] && \
      source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
  ```
- `.config/zsh/conf.d/os.darwin/20-aliases.zsh` — e.g. `alias ls='ls -G'`.

**Why the `$ZDOTDIR/.zshenv` bootstrap:** non-login shells (new terminal tabs in some multiplexers, subshells, zsh spawned by editors) do NOT source `.zprofile`. `brew shellenv` is typically installed in `/etc/zprofile` — which also isn't read by non-login shells — or in the user's own `.zprofile`. Shipping the bootstrap in `$ZDOTDIR/.zshenv` makes `HOMEBREW_PREFIX` and brew-installed binaries on `PATH` available to every zsh, which is what people actually expect.

#### `packages/common/tmux` — tmux Loader + Common Config

**Purpose:** Scaffold `conf.d`-style OS dispatch in tmux so future OS divergence is a one-file add. No OS-specific content exists today; we ship the loader stub only. Mirroring the zsh rule: OS-specific files are sourced *after* common, so the conditional includes go at the end of `tmux.conf`.

**Loader (appended to `packages/common/tmux/.config/tmux/tmux.conf`):**

```tmux
# OS-specific overrides — filesystem-based dispatch via if-shell probe.
# source-file -q: silent-on-missing (the corrected incantation, per
# TECH_RESEARCH Q3). The tradeoff: silent-on-missing is ALSO silent-on-typo,
# so watch out when authoring these paths. Placed at the end of the file
# so OS-specific config lands after common for consistent override semantics.

if-shell '[ "$(uname -s | tr A-Z a-z)" = "linux" ]' \
  'source-file -q ~/.config/tmux/os.linux.conf'
if-shell '[ "$(uname -s | tr A-Z a-z)" = "darwin" ]' \
  'source-file -q ~/.config/tmux/os.darwin.conf'
```

No `tmux-linux` / `tmux-macos` packages are created in this change. The first OS-specific tmux divergence creates the bucket package at that time (a one-line add to `packages_<os>` in the justfile).

#### `packages/common/ghostty`

Ships the current ghostty config as-is. **No preemptive `conf.d` scaffold.** Ghostty's `config-file` include syntax (including whether a `?`/optional prefix is supported) wasn't verified in research; deferring the scaffold to "first real divergence" eliminates an unverified moving piece and still leaves a trivial one-file add path when needed.

#### `packages/common/bin`, `packages/linux/bin-linux`

**Split rule:** a script goes in `bin/` only if it runs correctly on both OSes as-is. Anything that wraps sway/aerospace/platform-specific tools goes in the OS bucket.

- `packages/common/bin/.local/bin/.gitkeep` — dir-guard (the package has no scripts today; the `.gitkeep` ensures `~/.local/bin/` stays un-folded and that `bin-linux` can add files without collision).
- `packages/linux/bin-linux/.local/bin/` — `sway-launch`, `obsidian-scratchpad`, `scratchpad-toggle`, `zellij-sessionizer`.

`packages/macos/bin-macos` is not created in this change; the first Mac script creates it.

#### `packages/macos/aerospace`

**Purpose:** Mac window manager config mirroring sway's keybinding shape. See [Flow: AeroSpace Keybind Mapping](#flow-aerospace-keybind-mapping) for the table.

#### `justfile` — OS Dispatch Controller

**New structure:**

```just
os := `uname -s`

packages_common := "zsh tmux ghostty zellij nvim yazi git bash bin"
packages_linux  := "zsh-linux bin-linux sway swaylock waybar mako wofi fontconfig environment.d"
packages_macos  := "zsh-macos aerospace"

# Link everything for the current OS. Pre-flights conflicts (fails loud on any
# pre-existing non-symlink at a target path), then stows per bucket.
all:
    @just check-conflicts
    @just _stow-bucket common {{packages_common}}
    @if [ "{{os}}" = "Linux" ]; then just _stow-bucket linux {{packages_linux}}; fi
    @if [ "{{os}}" = "Darwin" ]; then just _stow-bucket macos {{packages_macos}}; fi
    @echo "Done. Run 'just reload' on Linux to reload sway/waybar."

# Unlink everything (reversibility — PRD NFR). Three-bucket form.
unstow-all:
    @if [ "{{os}}" = "Linux" ]; then just _unstow-bucket linux {{packages_linux}}; fi
    @if [ "{{os}}" = "Darwin" ]; then just _unstow-bucket macos {{packages_macos}}; fi
    @just _unstow-bucket common {{packages_common}}
    @echo "Done. Packages unlinked. Per-OS system state (Caps->Esc etc.) not reverted."

# Restow — useful after deleting a snippet file to clean up dangling symlinks.
restow:
    @just _stow-bucket-flag -R common {{packages_common}}
    @if [ "{{os}}" = "Linux" ]; then just _stow-bucket-flag -R linux {{packages_linux}}; fi
    @if [ "{{os}}" = "Darwin" ]; then just _stow-bucket-flag -R macos {{packages_macos}}; fi

[private]
_stow-bucket bucket *pkgs:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{pkgs}}; do
      echo "Stowing $pkg from packages/{{bucket}}..."
      stow -d packages/{{bucket}} -t ~ "$pkg"
    done

[private]
_unstow-bucket bucket *pkgs:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{pkgs}}; do
      echo "Unstowing $pkg from packages/{{bucket}}..."
      stow -D -d packages/{{bucket}} -t ~ "$pkg" || true
    done

[private]
_stow-bucket-flag flag bucket *pkgs:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{pkgs}}; do
      stow {{flag}} -d packages/{{bucket}} -t ~ "$pkg"
    done

# Pre-flight: walk the package tree directly (no stow-output parsing). For every
# file a package would link to $HOME, if the target exists as a non-symlink or
# as a symlink pointing outside this repo, fail loudly listing all conflicts and
# a suggested remediation. This satisfies PRD Must-Have "Pre-existing dotfile
# handling — exit non-zero with a clear remediation message."
[private]
check-conflicts:
    #!/usr/bin/env bash
    set -euo pipefail
    repo_root="$(git rev-parse --show-toplevel)"
    case "{{os}}" in
      Linux)  buckets=(common linux) ;;
      Darwin) buckets=(common macos) ;;
      *)      echo "Unsupported OS: {{os}}" >&2; exit 2 ;;
    esac
    conflicts=()
    for b in "${buckets[@]}"; do
      for pkg in "$repo_root/packages/$b"/*/; do
        [ -d "$pkg" ] || continue
        # Walk every regular file and symlink under the package.
        while IFS= read -r -d '' src; do
          rel="${src#"$pkg"}"       # path relative to the package root
          abs="$HOME/$rel"          # where stow would link it
          if [ -L "$abs" ]; then
            # Existing symlink — OK iff it points into our repo.
            lnk="$(readlink "$abs")"
            case "$lnk" in
              "$repo_root"/*|./*|../*) : ;;   # ours (or relative to stow)
              /*) conflicts+=("$abs -> $lnk (foreign symlink)") ;;
              *)  : ;;
            esac
          elif [ -e "$abs" ]; then
            conflicts+=("$abs (non-symlink; would collide)")
          fi
        done < <(find "$pkg" -mindepth 1 \( -type f -o -type l \) -print0)
      done
    done
    if [ "${#conflicts[@]}" -gt 0 ]; then
      echo "check-conflicts: pre-existing paths would collide with stow:" >&2
      printf '  %s\n' "${conflicts[@]}" >&2
      cat >&2 <<'EOF'

To resolve: back up each conflicting file and rerun. For example:
  mv ~/.zshrc ~/.zshrc.pre-stow.bak
Then: just setup
EOF
      exit 1
    fi

# Dry-run plan for the current OS.
plan:
    @just _plan-bucket common {{packages_common}}
    @if [ "{{os}}" = "Linux" ]; then just _plan-bucket linux {{packages_linux}}; fi
    @if [ "{{os}}" = "Darwin" ]; then just _plan-bucket macos {{packages_macos}}; fi

[private]
_plan-bucket bucket *pkgs:
    #!/usr/bin/env bash
    for pkg in {{pkgs}}; do
      echo "=== $pkg ==="
      stow -n -v -d packages/{{bucket}} -t ~ "$pkg" 2>&1
    done
```

**Key behaviors:**
- **`just setup` is idempotent** at the stow layer: `check-conflicts` catches first-time collisions before touching anything; re-running is safe. Brew/dnf are idempotent for repeat installs on their own (stow's re-link is a no-op).
- **`check-conflicts` walks the filesystem directly**, not stow's verbose output. This is format-independent across stow versions, catches all conflict types, and makes failures auditable (the full conflict list is printed to stderr with remediation instructions).
- **`unstow-all` unwinds in reverse order** (os bucket first, then common) so any OS-specific directory guards get cleaned up before the common owner.
- **`restow` runs `stow -R`** which removes dangling symlinks for files deleted from packages and re-establishes correct links.
- **No `plan-os <other-os>` recipe.** The PRD's pre-merge gate ("`stow -n` dry-run clean on macOS layout") is satisfied by running `stow -n` against the macOS package set from a scratch target dir *once* before merge — this is a README-documented one-liner rather than a permanent recipe that would rot from disuse.

#### `.stowrc`

**Decision:** delete `.stowrc`. Every `stow` call in the justfile passes `-t ~` explicitly. Single source of truth (the justfile), no coupling to stow-version-specific `.stowrc` parsing.

### Data Flow

#### Shell startup (Mac, any invocation — login or not)

1. Zsh reads `/etc/zshenv` (system-wide).
2. Zsh reads `$HOME/.zshenv` (our minimal file: respects pre-existing `ZDOTDIR`, otherwise sets to `~/.config/zsh`).
3. Zsh reads `$ZDOTDIR/.zshenv` — on Mac this exists (stowed from `zsh-macos`) and evals `brew shellenv` if `HOMEBREW_PREFIX` isn't already set. `PATH` now includes brew's bin dir; `HOMEBREW_PREFIX` is populated.
4. (Login only) `/etc/zprofile` then `$ZDOTDIR/.zprofile` — we don't ship the latter.
5. (Interactive only) `/etc/zshrc` then `$ZDOTDIR/.zshrc` — our loader.
6. Loader: `os_key=darwin` via `case $OSTYPE`, globs `conf.d/*.zsh` (common), then `conf.d/os.darwin/*.zsh` (brew plugin sources, mac aliases).
7. Each snippet is sourced; a syntax error in one prints via zsh's native error-reporting and the loop continues.
8. Interactive prompt.

#### Shell startup (Linux, any invocation)

Same as Mac but step 3 is a no-op (no `$ZDOTDIR/.zshenv` on Linux — only common's `$HOME/.zshenv` runs). Step 6: `os_key=linux`; `conf.d/os.linux/*.zsh` sources Fedora plugin paths.

#### `just setup` on a fresh Fedora box

1. `just setup` → `install-deps` (dnf) → `all`.
2. `all` → `check-conflicts` → per-bucket `_stow-bucket` for `common` and `linux`.
3. `check-conflicts` walks the package tree under `packages/common/` and `packages/linux/`; fails with a conflict list if any target is a non-symlink or a foreign symlink.
4. Each bucket invokes `stow -d packages/<bucket> -t ~ <pkg>` per package.
5. `all` runs `just reload` on Linux (sway reload, waybar restart, etc.).

#### `just setup` on a fresh Mac

Same as Fedora but `install-deps` runs `brew install ...` + `brew install --cask ghostty aerospace` (each cask install is guarded — see Integration Points), and `_stow-bucket` runs for `common` and `macos`.

### Key Flows

#### Flow: Add an OS-specific zsh snippet

> Scenario: you want an `fnm` path export on Mac only.

1. Create `packages/macos/zsh-macos/.config/zsh/conf.d/os.darwin/40-fnm.zsh` with the single `export PATH=...` line.
2. `git add && git commit && git push` (from any machine).
3. On the Mac, `git pull`. Two sub-cases:
   - **File added to an existing, already-stowed `os.darwin/` dir:** the stowed `os.darwin/` symlink already points to the package tree, so the new file is already visible under `~/.config/zsh/conf.d/os.darwin/40-fnm.zsh` the moment the pull completes. No stow needed.
   - **First file in a newly-created `os.darwin/` subdirectory:** the directory didn't exist before the pull, so stow never linked it. Run `just stow zsh-macos` (or `just restow`) once to re-link the package and pick up the new subdir.
4. Open a new shell. The new snippet is sourced.

Rule of thumb: if in doubt, `just restow` — it's idempotent and cheap.

#### Flow: Add a new top-level stow package

> Scenario: you want to add `starship` as a common package.

1. `mkdir -p packages/common/starship/.config/starship && ...` — create the package tree mirroring target paths under `~`.
2. Add `starship` to the `packages_common` list in the justfile.
3. `just plan` to verify no conflicts.
4. `git commit && just stow starship` (or `just setup` for the full pass).

For a new OS-specific package (e.g., `tmux-macos` on first tmux divergence): add the package directory under `packages/macos/`, register in `packages_macos`, and if it's the first package contributing to a shared dir, also drop a `.gitkeep` in the common owner (see Loader Contract rule 1).

#### Flow: Fresh-clone → working setup (Fedora)

| Check | Source |
|-------|--------|
| zsh prompt renders | `conf.d/20-prompt.zsh` |
| zsh-autosuggestions + syntax-highlighting active | `conf.d/os.linux/10-plugins.zsh` |
| zoxide `z` works | `conf.d/30-path.zsh` |
| fzf Ctrl-R / Ctrl-T bound | fzf's own keybind files + `conf.d/10-shell.zsh` |
| zellij launches via Super+P | `bin-linux/zellij-sessionizer` (unchanged on Linux) |
| tmux launches with config | `tmux/.config/tmux/tmux.conf` loader |
| nvim opens with LazyVim | `nvim/` package |
| yazi opens | `yazi/` package |
| sway reloads without error | `sway/.config/sway/config` |

#### Flow: Fresh-clone → working setup (Mac, day 1 of new job)

1. Install Homebrew manually (`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`) — prerequisite. Xcode Command Line Tools are installed as a side effect.
2. `brew install just stow` (manual prereq; `just` isn't in our deps list).
3. `git clone git@github.com:SIRHAMY/dotfiles.git ~/Code/dotfiles && cd ~/Code/dotfiles`.
4. `just setup` — installs brew formulae/casks from the macOS dep list, runs `check-conflicts`, stows `common` + `macos` buckets.
5. Manual (one-time, per README's "macOS setup" section):
   - Enable Caps→Esc in System Settings → Keyboard → Modifier Keys.
   - Launch AeroSpace (`open -a AeroSpace`). Grant Accessibility permission when prompted. `aerospace reload-config`.
6. Open a new Ghostty window. Zsh loader runs; brew shellenv bootstrapped from `$ZDOTDIR/.zshenv`; plugins load.

#### Flow: Migrate the existing Fedora machine

> This is the one-time painful path. PRD Risk: "Stow conflicts during migration."

1. **Open a scratch shell now** — a second Ghostty window running `bash -l`, kept open for the whole migration. If the zsh rewrite breaks mid-flight, this is your lifeline. Do NOT close it until you've verified a fresh zsh from a *third* Ghostty window works.
2. Verify clean working tree: `git status` — must be clean before checkout.
3. `cd ~/Code/dotfiles && just unstow-all` (runs the *current* branch's unstow, which operates on the flat `<pkg>/` roots).
4. Verify no orphan symlinks: `find ~ -maxdepth 3 -type l -lname "*/Code/dotfiles/*" 2>/dev/null` — should be empty after unstow. If not, `rm` them manually.
5. `git checkout <restructure-branch>`.
6. `just plan` — verify zero stow conflicts. If any, fix before proceeding.
7. `just setup` — `check-conflicts` catches any leftover real files (e.g., if the old `.zshrc` wasn't managed by stow and thus wasn't unstowed), re-stows from the new layout, reloads sway.
8. Open a *third* terminal window (new zsh). Confirm prompt, plugins, zoxide, fzf bindings, etc. all work.
9. Close the scratch shell.

Recovery if zsh breaks: from the scratch `bash` shell, `mv ~/.zshenv ~/.zshenv.broken && mv ~/.zshrc ~/.zshrc.broken 2>/dev/null` → new zsh will start with defaults, no `ZDOTDIR`, no loader. Debug from there.

#### Flow: Post-merge Mac bugfix from Fedora

> PRD "Post-Merge Mac Validation Workflow" — this must be trivially easy.

1. Discover on Mac: `brew install --cask ghostty-something` failed (wrong cask name), or an aerospace bind is wrong.
2. From the Fedora box: `cd ~/Code/dotfiles && $EDITOR justfile` (or the relevant file).
3. `git commit && git push`.
4. On Mac: `git pull`. Config-only changes (zsh/tmux/aerospace) are picked up at next shell reload (zsh) / config reload (tmux: `tmux source ~/.config/tmux/tmux.conf`; aerospace: `aerospace reload-config`). For justfile/install-deps changes: `just setup` (idempotent).

No branches. No migration dance. This is the architectural payoff.

#### Flow: AeroSpace Keybind Mapping

> Mirror the sway subset the PRD names. Mac `Alt` replaces sway's `Super`. Directional keys: h/j/k/l. Multi-output move-container keybinds omitted for now (Mac workflow TBD).

| Action | Sway bind | AeroSpace bind |
|--------|-----------|----------------|
| Focus left/down/up/right | `Super+h/j/k/l` | `alt-h/j/k/l` |
| Move container left/down/up/right | `Super+Ctrl+h/j/k/l` | `alt-shift-h/j/k/l` |
| Switch to workspace 1–9 | `Super+1–9` | `alt-1 … alt-9` |
| Move container to workspace 1–9 | `Super+Ctrl+1–9` | `alt-shift-1 … alt-shift-9` |
| Kill window | `Super+Shift+q` | `alt-shift-q` |
| Reload config | `Super+Shift+c` | `alt-shift-c` |
| Fullscreen | `Super+f` | `alt-f` |
| Launcher | `Super+d` (wofi) | *(out of scope — use Spotlight/Raycast)* |
| Terminal | `Super+Return` (ghostty) | *(out of scope — Dock / Spotlight; revisit post day-1)* |

Concrete `aerospace.toml` fragment:

```toml
# ~/.config/aerospace/aerospace.toml
after-login-command = []
after-startup-command = []
start-at-login = true

enable-normalization-flatten-containers = true
enable-normalization-opaque-containers = true

accordion-padding = 30
default-root-container-layout = 'tiles'
default-root-container-orientation = 'auto'

automatically-unhide-macos-hidden-apps = false

[mode.main.binding]
# Directional focus
alt-h = 'focus left'
alt-j = 'focus down'
alt-k = 'focus up'
alt-l = 'focus right'

# Move container
alt-shift-h = 'move left'
alt-shift-j = 'move down'
alt-shift-k = 'move up'
alt-shift-l = 'move right'

# Workspaces 1-9
alt-1 = 'workspace 1'
alt-2 = 'workspace 2'
alt-3 = 'workspace 3'
alt-4 = 'workspace 4'
alt-5 = 'workspace 5'
alt-6 = 'workspace 6'
alt-7 = 'workspace 7'
alt-8 = 'workspace 8'
alt-9 = 'workspace 9'

# Move container to workspace 1-9
alt-shift-1 = 'move-node-to-workspace 1'
alt-shift-2 = 'move-node-to-workspace 2'
alt-shift-3 = 'move-node-to-workspace 3'
alt-shift-4 = 'move-node-to-workspace 4'
alt-shift-5 = 'move-node-to-workspace 5'
alt-shift-6 = 'move-node-to-workspace 6'
alt-shift-7 = 'move-node-to-workspace 7'
alt-shift-8 = 'move-node-to-workspace 8'
alt-shift-9 = 'move-node-to-workspace 9'

alt-shift-q = 'close'
alt-shift-c = 'reload-config'
alt-f       = 'fullscreen'
```

---

## Technical Decisions

### Decision: `.gitkeep` in `common/<pkg>` owns each shared directory

**Context:** Stow tree-folding will collapse a single-package directory into one symlink, breaking the ability for other packages to contribute sibling files/dirs. Applies to `conf.d/` and `.local/bin/`.

**Decision:** Every shared-directory package puts a `.gitkeep` at the top of any directory that will later be shared across OS packages. Today that's `packages/common/zsh/.config/zsh/conf.d/.gitkeep` and `packages/common/bin/.local/bin/.gitkeep`. The `.gitkeep` has a single-line comment: *"kept un-folded by stow; DO NOT DELETE."* The Loader Contract documents this as Rule 1.

**Rationale:** Research Q1 verified this is the correct and widely-used trick. Alternative (passing `--no-folding` to stow) is global and applies to *everything* stowed.

**Consequences:** A couple of sentinel files in the repo. Because the common `conf.d/` also contains real `.zsh` snippets, the `.gitkeep` is belt-and-suspenders there; for `.local/bin/` (where common has no scripts today) it's the sole guard. A README note in ARCHITECTURE.md (nice-to-have) explains why.

### Decision: Delete `.stowrc`; pass `-t ~` in the justfile

**Context:** Current `.stowrc` has `--target=/home/sirhamy` which is non-portable.

**Decision:** Remove `.stowrc`. Every `stow` invocation in the justfile passes `-t ~` explicitly.

**Rationale:** Single source of truth (the justfile). Every supported stow invocation already threads through a just recipe. Hand-invocations are rare and documented in README. The alternative (`.stowrc` with `--target=$HOME`) is also valid — this is a judgment call in favor of fewer moving pieces.

**Consequences:** A user running `stow zsh` directly without `-t ~ -d packages/common` will get wrong behavior; README covers this.

### Decision: tmux loader uses `source-file -q`, not `if-shell -b`

**Context:** PRD Should-Have specified `if-shell '...' '... -b'` for quiet-on-missing.

**Decision:** Use `source-file -q` inside the `if-shell` body. `-b` is the wrong flag — it backgrounds the shell probe but does not suppress `source-file` errors.

**Rationale:** TECH_RESEARCH Q3 verified `source-file -q` is the documented quiet flag. This is a PRD-claim correction, not a re-decision; the product-level requirement ("no error on missing file") is preserved with the corrected implementation detail.

**Hidden tradeoff (accepted):** `-q` is silent on missing files, which also makes it silent on typos. Mitigation: Loader Contract (Rule 2) + naming convention (`os.<key>.conf` is short and unambiguous). The `just plan` recipe also exercises stow-layer filename correctness even if it can't check tmux semantics.

### Decision: Homebrew prefix resolved once via `$ZDOTDIR/.zshenv` shellenv bootstrap

**Context:** Mac zsh snippets need `$HOMEBREW_PREFIX` and `brew` on PATH. Non-login shells (new tmux/zellij panes, editor-spawned shells, subshells) don't read `.zprofile`, so a `/etc/zprofile`-based `brew shellenv` is unreliable.

**Decision:** `packages/macos/zsh-macos/.config/zsh/.zshenv` evals `brew shellenv` on every zsh invocation (login or not), guarded by `[ -z "${HOMEBREW_PREFIX-}" ]` for idempotency, with Apple-Silicon-first / Intel-fallback brew path probe. OS-specific snippets (`os.darwin/10-brew.zsh`) then use `$HOMEBREW_PREFIX` directly.

**Rationale:** TECH_RESEARCH Q4 showed `brew shellenv` is the canonical bootstrap; doing it in `$ZDOTDIR/.zshenv` rather than `.zprofile` fixes the non-login-shell case, which is the common case inside multiplexers. The `[ -z ...]` guard is cheap enough to run in every `.zshenv`.

**Consequences:** Mac zsh snippets are fast and readable. One forked process per shell start for `brew shellenv` — acceptable (it's a single `eval`, not a loop).

### Decision: Pattern B for pre-existing dotfiles — fail loudly with a list

**Context:** PRD requires `just setup` to handle pre-existing dotfiles deterministically: either "(a) backs them up to `*.pre-stow.bak` or (b) exits non-zero with a clear remediation message." Current justfile's `@for` loop swallows per-package failures silently.

**Decision:** Implement Pattern B via `check-conflicts`: walk the package tree directly with `find`, compare each file's would-be target path in `$HOME` against the existing filesystem, fail loudly with a full conflict list and a printed `mv ... .pre-stow.bak` remediation. No stow-output parsing.

**Rationale:** The earlier design drafted Pattern A (auto-backup via `awk`-parsing `stow -n -v`) but six of seven critique agents independently flagged it as either wrong (awk pattern doesn't match conflict lines) or over-engineered (~30 lines of bash for a situation that happens ~twice in this repo's lifetime). Walking the package tree directly is format-independent across stow versions, catches all conflict types (non-symlink files AND foreign symlinks), and is ~15 lines. The user doing one `mv` per conflict during day-1 Mac setup is not a material cost.

**Consequences:** `just setup` on a fresh Mac with default or MDM-pushed dotfiles exits 1 with a clear list; user runs the printed `mv` commands, reruns `just setup`. Deterministic, auditable, no silent failures.

### Decision: No `tmux-{linux,macos}`, `ghostty-{linux,macos}`, or `bin-macos` packages today

**Context:** PRD "Should Have" asks for tmux `conf.d` scaffolding; "Nice to Have" doesn't say anything about ghostty beyond the restructure itself.

**Decision:** The tmux loader stub (two `if-shell ... source-file -q` lines) scaffolds the pattern in `packages/common/tmux` without creating the `tmux-<os>` packages. `source-file -q` tolerates missing includes. Ghostty gets no preemptive scaffold (include syntax wasn't verified in research; deferring eliminates an unverified moving piece). `bin-macos` is omitted until a Mac-only script exists.

**Rationale:** Empty packages add directory noise for zero current value. The architectural invariant (filesystem-based dispatch) is fully preserved by the loader. When the first OS-specific divergence lands, it's a one-file add + one justfile registration — no scaffolding regret.

**Consequences:** If someone adds a `tmux-macos` later, they must also register it in `packages_macos`. The Loader Contract makes this obligation discoverable.

### Decision: `zellij-sessionizer` stays in `bin-linux` for this change; no Mac port

**Context:** PRD explicitly defers the Mac port of `zellij-sessionizer` (its floating-terminal launch wraps `sway-launch`).

**Decision:** Leave `zellij-sessionizer` in `packages/linux/bin-linux`. On Linux, `Super+P` works unchanged. On Mac, the sessionizer is absent from day 1; any future Mac port is a separate follow-up change.

**Rationale:** PRD "Nice to Have" explicitly deferred; sway-coupled; not worth blocking the restructure on a window-manager-dependent script.

**Consequences:** Mac users don't get `Super+P` on day 1 — this is expected and documented. No shared config references the script by path (verified during design).

### Tradeoffs Accepted

| Tradeoff | We're Accepting | In Exchange For | Why This Makes Sense |
|----------|-----------------|-----------------|---------------------|
| Loader startup cost | ~1 ms per shell start for `conf.d` glob+source loop + (on Mac) one `brew shellenv` eval in `.zshenv` | Zero in-body OS conditionals; every OS branch lives in a filename | Dual-OS split is permanent; conditionals would scale poorly. 1 ms is imperceptible. |
| Package count inflation | One app can become three packages (`zsh` + `zsh-linux` + `zsh-macos`) | Filesystem dispatch; stow-native OS gating | Stow packages are cheap to declare. Naming (`<app>-<os>`) keeps inspection obvious. |
| tmux `source-file -q` silent-on-missing ⇒ silent-on-typo | A path typo in a conditional include will silently do nothing | Graceful handling of not-yet-created OS-specific files | Loader Contract rules + short filenames keep typos unlikely. |
| Pattern B fails instead of auto-backing-up | User runs one `mv` command per conflict once during migration or fresh Mac setup | Deterministic, auditable, no stow-output parsing | Happens ~twice in repo's lifetime; auto-backup added complexity without saving real work. |
| Delete `.stowrc` | No default target; every stow call must thread through justfile or pass `-t ~` | Avoids `.stowrc` / justfile divergence; single source of truth | Justfile is the supported path. Hand-invocations are rare and documented. |
| justfile retains OS conditionals | `if [ "{{os}}" = "Linux" ]` in a handful of recipes | Shell-language constraint: `just` needs to know *which* package manager to call | PRD accepts this explicitly as "necessary evil." Limited to `justfile`; config files stay branch-free. |

---

## Alternatives Considered

### Alternative: In-body OS conditionals (the "obvious" path)

**Summary:** Keep the flat `<pkg>/` layout, add `case $OSTYPE in` / `if [[ $(uname -s) == Darwin ]]` blocks to existing `.zshrc`, `tmux.conf`, etc.

**Pros:**
- Zero restructure; minimal file moves.
- Familiar to any shell scripter.

**Cons:**
- PRD #4 explicit rejection ("doesn't scale"). With dual-OS maintenance over years, every config file grows its own partial branching. Hard to grep, hard to reason about, hard to test.
- OS-specific logic gets re-examined every time you edit any config for any reason.
- No natural place for Mac-only files that don't yet have a Linux counterpart.
- Doesn't solve the `.stowrc` target problem or the sway-coupled-script problem either.

**Why not chosen:** Explicitly the anti-goal per PRD. The whole point of this change is to prevent this outcome.

### Alternative: Pattern A pre-existing-file handling (auto-backup via awk-parsing stow output)

**Summary:** The earlier design drafted a `backup-conflicts` recipe that parsed `stow -n -v` output with `awk` and auto-renamed conflicts to `.pre-stow.bak`.

**Pros:**
- Fully automated; user never runs `mv` by hand.

**Cons:**
- Parses stow's verbose output, which is an implementation detail (format differs across versions and between LINK/MKDIR/conflict lines).
- Conflict lines from stow do NOT match `^LINK: ` — they're `* existing target is neither a link nor a directory:` on stderr. The original awk pattern was wrong and would have silently backed up nothing, then letting stow fail anyway.
- ~30 lines of bash for a migration that happens ~twice in the repo's lifetime.

**Why not chosen:** Replaced with Pattern B (fail loudly, walk the package tree directly). Converges on the same PRD-acceptance outcome with a fraction of the risk.

---

## Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Stow conflicts during Fedora migration | Broken shell/editor state mid-flight | Medium | Scratch shell protocol (now step 1 of migration flow); `just plan` dry-run; `just unstow-all` before branch checkout. |
| Mac work policy / MDM blocks brew or cask | Partial setup; aerospace or ghostty missing | Medium | `install-deps` guards cask installs with `brew list --cask <name> || brew install --cask <name>` to fail on reject, not on already-installed. README documents the `packages/common`-only fallback. |
| `.gitkeep` forgotten when adding a new shared-directory package | Stow folds the directory; OS-specific package later fails with a stow error | Low-Medium | Loader Contract (Rule 1) documents the obligation. The failure surfaces at `just stow` time with a clear stow error, not silently. |
| `brew shellenv` bootstrap fails (no brew on either canonical path) | Mac zsh plugins don't load; `$HOMEBREW_PREFIX` empty | Low | `.zshenv` probes both Apple Silicon and Intel brew paths; `[ -x ... ]` guard means fails silently with no functional change. Plugins silently absent, but shell still works. |
| tmux `source-file -q` silent-on-typo | A typo'd path silently does nothing | Low | Short filenames + Loader Contract. |
| `$OSTYPE` on WSL returns `linux-gnu*` → loads Fedora paths | Fedora plugin paths `[ -r ]`-guarded ⇒ silent no-op on WSL | Low (WSL is out of scope) | Loader's `[ -r "$f" ] || continue` tolerates this. WSL support is deferred per PRD; this is graceful degradation, not correctness. |
| Migration orphan symlinks after `just unstow-all` on old branch | `check-conflicts` flags them as foreign symlinks on the new branch | Low | Migration flow step 4 explicitly checks for orphan symlinks post-unstow. |
| AeroSpace default mod conflicts with macOS system shortcuts | Alt bindings fire system actions instead | Low-Medium | AeroSpace's `[mode.main.binding]` captures first. Day-1 experience will surface any specifics. |

---

## Integration Points

### Existing Code Touchpoints

Files that move or change, with expected treatment:

- `zsh/.zshrc` → split:
  - Common content → `packages/common/zsh/.config/zsh/conf.d/{10,20,30,40,50}-*.zsh`
  - `source /usr/share/zsh-*` lines → `packages/linux/zsh-linux/.config/zsh/conf.d/os.linux/10-plugins.zsh`
  - `alias vim='vimx'` → `packages/linux/zsh-linux/.../os.linux/20-aliases.zsh`
  - `. "$HOME/.cargo/env"` + opencode path → `packages/linux/zsh-linux/.../os.linux/30-paths.zsh`
  - **Bugs fixed incidentally (per PRD scope):** duplicate `PATH` export collapsed, missing newline before `source` line added, `. "$HOME/.cargo/env"` guarded with `[ -r … ] &&`, `/home/sirhamy/.opencode/bin` replaced with `$HOME/.opencode/bin`.
- `zsh/` (top-level) → deleted after content moves.
- `.stowrc` → deleted.
- `justfile` → heavy rewrite (new bucket structure, `check-conflicts`, `unstow-all`, `restow`, `_stow-bucket` / `_unstow-bucket` / `_stow-bucket-flag` helpers).
- `bin/.local/bin/` → split; `git mv` to preserve blame. `packages/common/bin/.local/bin/.gitkeep` added.
- `tmux/`, `ghostty/`, `zellij/`, `nvim/`, `yazi/`, `git/`, `bash/` → `git mv` to `packages/common/<pkg>/`. Only `tmux` gets loader-stub modifications; others move as-is.
- `sway/`, `swaylock/`, `waybar/`, `mako/`, `wofi/`, `fontconfig/`, `environment.d/` → `git mv` to `packages/linux/<pkg>/` as-is.
- `README.md` → rewrite. See [README content checklist](#readme-content-checklist) below for the exact section list. ARCHITECTURE.md is intentionally skipped for this change; README absorbs the loader-contract content that would have lived there.
- `changes/` → untouched.

### New Files

- `packages/common/zsh/.zshenv` (respects pre-existing `ZDOTDIR`).
- `packages/common/zsh/.config/zsh/.zshrc` (loader).
- `packages/common/zsh/.config/zsh/conf.d/.gitkeep`.
- `packages/common/zsh/.config/zsh/conf.d/{10,20,30,40,50}-*.zsh` (consolidated common snippets).
- `packages/common/bin/.local/bin/.gitkeep`.
- `packages/linux/zsh-linux/.config/zsh/conf.d/os.linux/{10,20,30}-*.zsh`.
- `packages/macos/zsh-macos/.config/zsh/.zshenv` (brew shellenv bootstrap).
- `packages/macos/zsh-macos/.config/zsh/conf.d/os.darwin/{10,20}-*.zsh`.
- `packages/common/tmux/.config/tmux/tmux.conf` — loader stub appended.
- `packages/macos/aerospace/.config/aerospace/aerospace.toml`.

### External Dependencies

- GNU stow 2.3+ on both OSes. Fedora dnf ships 2.4.x; brew ships 2.4.x. Fine.
- zsh 5.x. Both OSes default or easily installable.
- tmux 3.x+. Same.
- `git` available during `check-conflicts` (uses `git rev-parse --show-toplevel`).
- Homebrew on Mac (manual prereq).

### README content checklist

The README rewrite must cover these sections. Items marked **(PRD)** are direct PRD Must-Have requirements; items marked **(absorbed)** would have lived in ARCHITECTURE.md but are folded into the README since that doc is skipped.

1. **What this repo is** — one-paragraph intro: stow-managed dotfiles, Linux + Mac, public configs only. (Existing.)
2. **The three-rule taxonomy** **(PRD)** — `packages/{common,linux,macos}/`; `conf.d/` loader for shared-but-divergent apps; filesystem-based OS dispatch. One short paragraph per rule.
3. **Loader Contract (5 rules)** **(absorbed)** — copy from DESIGN.md §Loader Contract. Future-self needs this; it's the load-bearing invariant.
4. **Concrete `conf.d` example** **(PRD)** — show the `~/.config/zsh/conf.d/` tree with one common snippet and one `os.darwin/` snippet. Show the loader source-line. ~10 lines.
5. **How to add an OS-specific snippet** **(PRD)** — the [Add an OS-specific zsh snippet](#flow-add-an-os-specific-zsh-snippet) flow, including the "first file in a new `os.<key>/` subdir requires `just stow`" caveat.
6. **How to add a new top-level package** **(absorbed)** — short version of the [Add a new top-level stow package](#flow-add-a-new-top-level-stow-package) flow. Include the `.gitkeep`-for-shared-dirs reminder.
7. **Per-OS install instructions** **(PRD)** — Fedora and macOS prereqs (`just`, `stow`, Homebrew on Mac with the curl-install command). Then `git clone && cd && just setup`.
8. **macOS setup section** **(PRD)** — Caps→Esc via System Settings → Keyboard → Modifier Keys; launch AeroSpace and grant Accessibility permission; MDM fallback (manual `stow -d packages/common -t ~ <pkg>` workaround if brew/cask is blocked); note that `$ZDOTDIR/.zshenv` handles brew shellenv automatically.
9. **Post-merge Mac validation workflow** **(PRD)** — the [Post-merge Mac bugfix from Fedora](#flow-post-merge-mac-bugfix-from-fedora) flow; emphasize the no-branches, idempotent-`just setup` payoff.
10. **Migration path for the existing Fedora machine** **(PRD)** — the [Migrate the existing Fedora machine](#flow-migrate-the-existing-fedora-machine) flow including the scratch-shell protocol and the recovery escape (`mv ~/.zshenv ~/.zshenv.broken` from the scratch `bash -l`).
11. **Reversibility** **(absorbed)** — short section: `just unstow-all` removes symlinks but does not undo system settings (Caps→Esc) or installed packages. `just restow` rebuilds links after deleting snippet files.
12. **Loader debugging** **(absorbed)** — what to do if a new snippet errors. Errors print to stderr at shell start; for stuck cases, `zsh -f` skips `.zshrc`, then move the offending snippet to `*.zsh.disabled`.
13. **Hand-invocation note** **(absorbed)** — `just` is the supported entry point. If you must run `stow` directly, you need both `-d packages/<bucket>` and `-t ~`. `.stowrc` was deliberately removed.
14. **Cheatsheet** — keep the existing sway/zellij/nvim tables; add a small AeroSpace table mirroring [the keybind mapping](#flow-aerospace-keybind-mapping).

If any of these grow past ~half a page, that's the signal to spin them out into ARCHITECTURE.md after all — but the working assumption is README is sufficient.

### install-deps guards (Mac)

Cask installs wrapped to be idempotent across re-runs (brew `--cask install` errors on already-installed in some versions):

```bash
for cask in ghostty aerospace; do
  brew list --cask "$cask" &>/dev/null || brew install --cask "$cask"
done
```

Formulae use `brew install ...` directly (already idempotent).

---

## Open Questions

Remaining items for SPEC or build phase:

- [ ] **AeroSpace Return/launcher bindings** — deferred to day-1 Mac experience. Use Spotlight (Cmd+Space) for the first few days; bind `alt-return = 'exec-and-forget open -na Ghostty'` once you know whether you want it or prefer a different launcher (Raycast etc.). Not a merge blocker; ship the restructure with no Return/launcher binding in `aerospace.toml`.
- [ ] **Zellij sessionizer Mac port** — out of scope per PRD; logged here for visibility. Follow-up change after AeroSpace floating-window behavior is settled in use.

**Decided (was directional, now resolved):**
- ~~ARCHITECTURE.md inclusion~~ — **skipped.** README absorbs the Loader Contract and the worked-example content that would have lived there. See [README content checklist](#readme-content-checklist).
- ~~Day-1 Mac timing / minimum-viable cut~~ — **not needed.** Implement the full Must-Have list in one pass. Author has the first few days at the new role to get the setup right.

---

## Design Review Checklist

- [x] Design addresses all PRD Must-Have requirements — verified against PRD Success Criteria.
- [x] Key flows are documented — 7 flows: shell startup (Mac + Linux), `just setup` on fresh Fedora + fresh Mac, add-a-snippet, add-a-package, migration, post-merge bugfix, AeroSpace mapping.
- [x] Tradeoffs are explicitly documented — 6 tradeoffs in the table.
- [x] Integration points with existing code are identified — file-by-file mapping.
- [x] Loader contract is explicit — 5 rules with rationale.
- [x] No major open questions remain — 3 minor items flagged, none block merge.

---

## Design Log

| Date | Activity | Outcome |
|------|----------|---------|
| 2026-04-24 | Initial design draft | Full design written in one pass; PRD was specific enough that design is mostly formalizing layout + correcting two research-flagged issues (tmux `-q`, brew prefix). Light mode, 1 alternative (in-body conditionals) noted, 5 tradeoffs explicit. |
| 2026-04-24 | Self-critique (7 parallel agents) + triage | Applied 15 auto-fixes. Biggest: replaced `backup-conflicts` awk-parser (wrong + over-engineered, flagged by 6/7 agents) with Pattern B `check-conflicts` walking the package tree directly; added `$ZDOTDIR/.zshenv` brew shellenv bootstrap under `zsh-macos` to fix non-login-shell chicken-and-egg; made Loader Contract explicit; removed contradictory tmux-linux/tmux-macos tree entries; added `unstow-all` + `restow` recipes; dropped unverified ghostty preemptive scaffold; consolidated zsh common snippets from 9 files to 5. Status → In Review. |
| 2026-04-27 | Walked Needs Attention + open questions with author; resolved all directional items | Pattern B confirmed; brew shellenv bootstrap confirmed; full Must-Have implementation in one pass (no time-cut phasing); AeroSpace launcher binding deferred to day-1 experience; ARCHITECTURE.md skipped — README absorbs the Loader Contract and worked examples via an explicit 14-section content checklist added to the design. Status → Complete. |
