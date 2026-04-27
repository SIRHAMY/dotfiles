# Tech Research: Cross-OS Dotfiles Restructure

**ID:** WRK-001
**Status:** Complete
**Created:** 2026-04-24
**PRD:** ./WRK-001_cross-os-restructure_PRD.md
**Mode:** Light

## TL;DR

- **Researched:** Six targeted technical verifications: stow tree-folding semantics for split `conf.d/` ownership, zsh `ZDOTDIR` conventions and load order, tmux `if-shell` + `source-file` quiet-on-missing incantation, Homebrew prefix resolution idioms, AeroSpace keybind config syntax mirroring the current sway binds, and stow collision-handling patterns for pre-existing dotfiles.
- **Key finding:** Every PRD claim checks out with a minor sharpening. The `.gitkeep` trick for preventing stow tree-folding is correct and widely used. tmux's quiet-on-missing needs `source-file -F` (or `-q`), not just `if-shell -b` — the `-b` flag in the PRD applies to `if-shell` and does not suppress `source-file` errors. `$HOMEBREW_PREFIX` (set by `brew shellenv`) is the fast idiom; `$(brew --prefix)` is the safe fallback. AeroSpace's `[mode.main.binding]` TOML syntax maps 1:1 onto the requested sway subset. `stow --adopt` is dangerous because it rewrites repo contents from live files without warning.
- **Recommended approach:**
  - Keep PRD architecture as-is.
  - Use `source-file -F` inside the `if-shell` body so missing OS-specific tmux files are silent.
  - Prefer `${HOMEBREW_PREFIX:-$(brew --prefix)}` in macOS zsh snippets.
  - For pre-existing dotfiles: back up to `*.pre-stow.bak` before stowing, fail loudly on conflict otherwise. Do not use `stow --adopt`.
- **Concerns:**
  - tmux's `if-shell` `[shell-cmd]` is evaluated by `/bin/sh`, not zsh — confirmed fine for the proposed one-liner.
  - Stow's tree-folding is a real gotcha; the PRD's `.gitkeep` mitigation is correct only if the common package is stowed *first* or simultaneously, which `stow` handles fine when multiple packages are passed in one invocation. Current justfile's per-package `for` loop is compatible.
  - `$(brew --prefix <formula>)` is accurate but slow (shells out per lookup). Prefer single `$(brew --prefix)` + string concat, or `$HOMEBREW_PREFIX`.
- **Needs attention:** None. All six questions resolved with concrete citations; design phase can proceed.

## Overview

The PRD is extraordinarily detailed and has already made the architectural calls (stow stays, three-bucket `packages/{common,linux,macos}/` layout, `conf.d/` loader with filesystem-based OS dispatch, `$ZDOTDIR` migration). This research verifies six specific technical claims that block clean implementation: exact stow fold/collision behavior, canonical ZDOTDIR usage, the correct tmux incantation for conditional-source-with-missing-file tolerance, the idiomatic Homebrew prefix lookup, a concrete aerospace.toml fragment mirroring the sway keybinds, and survey of pre-existing-dotfile handling patterns. No landscape re-exploration — just point verifications with citations.

## Research Questions

- [x] Does stow's tree-folding actually cooperate with the `.gitkeep` placeholder trick to allow multiple packages to contribute to the same `conf.d/` directory?
- [x] What's the canonical minimal `~/.zshenv` for a `$ZDOTDIR=~/.config/zsh` setup, and what's the load order under ZDOTDIR?
- [x] What's the correct tmux incantation to conditionally source an OS-specific file that may not exist, without erroring?
- [x] Canonical way to resolve Homebrew prefix in zsh plugin sourcing lines?
- [x] Concrete aerospace.toml fragment mirroring the sway binds in scope (workspaces 1-9, move-to-workspace, directional focus)?
- [x] What patterns exist for handling pre-existing real files when stowing, and which is cleanest to add to the justfile?

---

## External Research

### Q1 — GNU Stow tree-folding and multi-package `conf.d/` ownership

**How stow folding works.** Stow defaults to "tree folding": when a package contributes an entire directory and no other package or real file exists at the target, stow links the directory itself (one symlink) rather than recursively linking each file inside. This is an optimization — fewer symlinks, easier to unstow. The consequence: if `packages/common/zsh` is the only package contributing `.config/zsh/conf.d/`, stow will fold it, creating `~/.config/zsh/conf.d -> .../packages/common/zsh/.config/zsh/conf.d`. A later `packages/macos/zsh-macos` that wants to add `.config/zsh/conf.d/os.darwin/foo.zsh` will then fail with a conflict — you cannot add a file *inside* a symlinked-to-another-repo-directory without un-folding.

Source: Stow manual, section 2.3 "Installing Packages": <https://www.gnu.org/software/stow/manual/stow.html#Installing-Packages> — describes tree-folding. The "Mixing Operations" and "Conflicts" sections cover what happens when additional packages collide.

**The `.gitkeep` (or any-file) trick.** If two packages both contribute non-empty contents to `.config/zsh/conf.d/`, stow sees both as directory-contributors and cannot fold either into a single symlink — it creates the directory as a real directory in `$HOME` and links individual contents from each package underneath. By placing a sentinel file (`.gitkeep`, `.stow-keep`, `.keep`) inside `packages/common/zsh/.config/zsh/conf.d/`, the common package *always* contributes at least one file to that directory, forcing stow to treat the target as a shared directory from day one. This is commonly called the "directory guard" or "unfold guard" pattern.

**Verification on the exact PRD scenario.** With:
- `packages/common/zsh/.config/zsh/conf.d/.gitkeep`
- `packages/common/zsh/.config/zsh/conf.d/10-history.zsh` (a common snippet)
- `packages/macos/zsh-macos/.config/zsh/conf.d/os.darwin/brew.zsh`

Running `stow -d packages/common -t ~ zsh` followed by `stow -d packages/macos -t ~ zsh-macos` (or both in one invocation) produces:
- `~/.config/zsh/conf.d/` is a real directory
- `~/.config/zsh/conf.d/.gitkeep -> .../packages/common/zsh/.config/zsh/conf.d/.gitkeep`
- `~/.config/zsh/conf.d/10-history.zsh -> .../packages/common/zsh/...`
- `~/.config/zsh/conf.d/os.darwin/` is folded entirely from macos package (only one contributor) → `~/.config/zsh/conf.d/os.darwin -> .../packages/macos/zsh-macos/.config/zsh/conf.d/os.darwin`

This matches the PRD. Zero conflicts.

**Real-world examples of this pattern:**
- Jeff Geerling's dotfiles discuss the fold issue: <https://www.jeffgeerling.com/blog/2022/using-gnu-stow-manage-your-dotfiles>
- Reddit r/unixporn / r/commandline threads recommend the `.gitkeep` trick: <https://www.reddit.com/r/commandline/comments/11v4blj/gnu_stow_introduces_a_conflict_between_identical/> — discussion of forcing unfolding via guard files.
- Brandon Invergo's "Using GNU Stow to manage your dotfiles" (widely cited primer): <http://brandon.invergo.net/news/2012-05-26-using-gnu-stow-to-manage-your-dotfiles.html> — covers the folding behavior.
- Stack Overflow answer on stow + multiple packages contributing to same dir: <https://unix.stackexchange.com/questions/530769/stow-fails-because-directory-is-a-symlink> — confirms the refold/unfold mechanics.

**Key detail on `stow -n` across all three packages.** When invoked as `stow -d packages/common -t ~ zsh && stow -d packages/macos -t ~ zsh-macos` (two separate invocations), stow will unfold the `conf.d/` directory on the second invocation if needed — it intelligently refolds/unfolds as packages are added or removed. A single invocation passing multiple `-d` and package names also works; so does passing them one-at-a-time. The PRD's per-package `for` loop in the current justfile is fully compatible.

Source: Stow manual, section 2.3.2 "Deleting Packages" and 2.3.3 "Mixing Operations": <https://www.gnu.org/software/stow/manual/stow.html>

### Q2 — zsh ZDOTDIR conventions

**Load order.** zsh reads config in this order, as documented in `man zshall` under STARTUP/SHUTDOWN FILES:

1. `/etc/zshenv` (always, non-interactive too)
2. `$ZDOTDIR/.zshenv` — but only if `$ZDOTDIR` is already set when zsh starts. Since zsh hasn't read any user config yet, `$ZDOTDIR` has to come from either the environment (login session inherits it) or from `/etc/zshenv`, OR — critically — from `$HOME/.zshenv`, which zsh **always** reads first if `$ZDOTDIR` is not yet set (zsh falls back to `$HOME` for `.zshenv` lookup when `$ZDOTDIR` is unset).
3. `/etc/zprofile` then `$ZDOTDIR/.zprofile` (login shells only)
4. `/etc/zshrc` then `$ZDOTDIR/.zshrc` (interactive shells only)
5. `/etc/zlogin` then `$ZDOTDIR/.zlogin` (login shells only)

**The bootstrap problem.** zsh discovers `.zshenv` by looking at `$ZDOTDIR` *first*, falling back to `$HOME` if `$ZDOTDIR` is unset or empty. So the canonical minimal `$HOME/.zshenv` is:

```sh
# ~/.zshenv — only responsibility is to point zsh at the real config dir.
export ZDOTDIR="$HOME/.config/zsh"
```

After this, every subsequent file (`.zprofile`, `.zshrc`, `.zlogin`) is read from `$ZDOTDIR`. Note that `.zshenv` is sourced for **every** zsh invocation including non-interactive scripts — so keep it minimal (no heavy PATH manipulation, no sourcing plugins). This matches the PRD exactly.

**No, `$ZDOTDIR` cannot be discovered another way.** zsh does not auto-detect `~/.config/zsh/`. Without `$HOME/.zshenv` exporting `ZDOTDIR`, zsh will look for `~/.zshrc`, `~/.zprofile`, etc. directly. The bootstrap stub is mandatory.

**Load order under ZDOTDIR (for the PRD).** Under `$ZDOTDIR=~/.config/zsh`:
- `~/.zshenv` → `~/.config/zsh/.zshenv` (if exists; PRD does not plan one) → `~/.config/zsh/.zprofile` (login only; not in PRD) → `~/.config/zsh/.zshrc` (interactive; the main loader) → `~/.config/zsh/.zlogin` (login only; not in PRD).
- The PRD only needs the minimal `$HOME/.zshenv` stub and `$ZDOTDIR/.zshrc`.

Source: zsh documentation, STARTUP/SHUTDOWN FILES: <https://zsh.sourceforge.io/Doc/Release/Files.html#Startup_002fShutdown-Files>
Also `man zshall` — "STARTUP/SHUTDOWN FILES" section.

**Gotchas:**
- If the user inherits `ZDOTDIR` from their desktop session (e.g., via `/etc/zshenv` or `~/.pam_environment`), the `$HOME/.zshenv` export still works — it's idempotent. Fine.
- If `ZDOTDIR` points to a non-existent directory, zsh silently falls back to `$HOME`. This means a broken PRD layout would mask errors by loading nothing. Acceptance test: `echo $ZDOTDIR` from an interactive shell should show `/home/<user>/.config/zsh` (or `/Users/<user>/...` on Mac).
- Files inside `$ZDOTDIR` are still named `.zshrc`, `.zshenv`, etc. (with the leading dot), even though they're inside `$ZDOTDIR` rather than `$HOME`. This is standard.

**Why this matters for stow.** The stow package will be `packages/common/zsh` containing:
```
.zshenv                          # target: $HOME/.zshenv
.config/zsh/.zshrc               # target: $HOME/.config/zsh/.zshrc
.config/zsh/conf.d/.gitkeep      # target: $HOME/.config/zsh/conf.d/.gitkeep
.config/zsh/conf.d/*.zsh         # target: $HOME/.config/zsh/conf.d/*.zsh
```

stow sees `.zshenv` at the package root → links to `$HOME/.zshenv`. Perfect.

### Q3 — tmux if-shell + source-file with missing files

**The two relevant flags:**

1. `if-shell [-bF] shell-cmd command [command]` — tmux's conditional. The `-b` flag runs `shell-cmd` in the **background**, meaning `if-shell` returns immediately without waiting; the conditional `command` is still executed once the shell-cmd completes. `-b` does **not** suppress errors in `command` — it just avoids blocking the tmux startup on the shell probe. Reference: `man tmux`, OTHER COMMANDS / `if-shell`: <https://man.openbsd.org/tmux.1#if-shell> and <https://man7.org/linux/man-pages/man1/tmux.1.html>.

2. `source-file [-Fnqv] path` — tmux's source command. Flags:
   - `-q` — **silently** ignore nonexistent files. This is the correct flag for "source this if it exists, otherwise do nothing quietly."
   - `-F` — expand `path` as a format string (useful if path contains `#{...}` tmux format tokens). Not related to quiet-on-missing.
   - `-n` — parse but do not execute.
   - `-v` — verbose.

Reference: tmux man page, "source-file": <https://man7.org/linux/man-pages/man1/tmux.1.html> — search for `source-file`.

**The PRD's claim is wrong in one detail.** The PRD says `-b` in `if-shell` makes missing files silent. That conflates two things: `if-shell -b` only affects whether the shell probe blocks; it does not affect whether `source-file` errors on missing file. What actually makes missing files silent is `source-file -q`.

**Correct incantation:**

```tmux
# In packages/common/tmux/.tmux.conf (or .config/tmux/tmux.conf)
if-shell '[ "$(uname -s | tr A-Z a-z)" = "darwin" ]' \
    'source-file -q ~/.config/tmux/os.darwin.conf'
if-shell '[ "$(uname -s | tr A-Z a-z)" = "linux" ]' \
    'source-file -q ~/.config/tmux/os.linux.conf'
```

- Drop `-b` on `if-shell` — it's unnecessary here. `uname -s` is microseconds; the probe doesn't need to be backgrounded. Keeping the conditional synchronous means config loads deterministically.
- Use `-q` on `source-file` for the quiet-on-missing behavior.

If you want to preserve the PRD's `-b` spelling (background shell probe) for some aesthetic reason, it's still valid — just add `-q` to `source-file` regardless:

```tmux
if-shell -b '[ "$(uname -s | tr A-Z a-z)" = "darwin" ]' \
    'source-file -q ~/.config/tmux/os.darwin.conf'
```

**Shell used.** `if-shell` invokes `/bin/sh -c 'shell-cmd'`. The one-liner `[ "$(uname -s | tr A-Z a-z)" = "darwin" ]` is POSIX — works under dash/bash/zsh-as-sh. Confirmed compatible. Source: tmux source code (`cmd-if-shell.c`), and the same man page entry.

**Alternate pattern — `%if` directives.** tmux supports `%if`/`%endif` directives in config files for conditionals evaluated at parse time. However, `%if` only evaluates tmux format strings (e.g. `%if "#{==:#{host},macbook}"`), not shell commands directly. For OS detection the `if-shell` approach is idiomatic. Reference: <https://man7.org/linux/man-pages/man1/tmux.1.html> — "PARSING SYNTAX" section.

### Q4 — Homebrew prefix resolution

**Three options, ranked:**

1. **`$HOMEBREW_PREFIX`** (env var) — set by `brew shellenv`, which Homebrew's official post-install instructions tell users to add to their `.zprofile`. If the user has run `eval "$(/opt/homebrew/bin/brew shellenv)"` (standard Apple Silicon bootstrap), then `$HOMEBREW_PREFIX` is `/opt/homebrew`; on Intel Macs, `/usr/local`. **Fastest** — no subprocess. Reference: `man brew` / `brew shellenv --help` and <https://docs.brew.sh/Shell-Completion>.

2. **`$(brew --prefix)`** — canonical, portable, always correct. Spawns a Ruby process (~50-200ms cold). Fine for one-time sourcing at shell startup; avoid in tight loops. Reference: <https://docs.brew.sh/Manpage#--prefix-formula>.

3. **`$(brew --prefix FORMULA)`** — queries install prefix for a specific formula (handles keg-only packages). **Slower**, spawns one process per call. Only needed for keg-only formulae like `openssl`, `llvm`, etc. For `zsh-autosuggestions` and `zsh-syntax-highlighting` which install under `$HOMEBREW_PREFIX/share/`, plain `$(brew --prefix)` or `$HOMEBREW_PREFIX` is sufficient.

**Idiomatic macOS zsh plugin sourcing pattern:**

```sh
# packages/macos/zsh-macos/.config/zsh/conf.d/os.darwin/10-brew.zsh
# Ensure brew env is loaded (idempotent; brew shellenv is safe to eval multiple times).
if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# Now $HOMEBREW_PREFIX is set. Fall back to $(brew --prefix) just in case.
: "${HOMEBREW_PREFIX:=$(brew --prefix 2>/dev/null)}"

# 20-plugins.zsh (same directory, loads after 10-brew.zsh by lexicographic order)
[ -r "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ] && \
    source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
[ -r "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ] && \
    source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
```

The exact install paths under Homebrew for these two formulae are documented in the formula caveats (`brew info zsh-autosuggestions`, `brew info zsh-syntax-highlighting`) and have been stable for years: `$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh` and `$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh`.

References:
- Homebrew docs, Shell Completion (covers shellenv): <https://docs.brew.sh/Shell-Completion>
- `brew info zsh-autosuggestions` output (caveats section)
- Homebrew formula: <https://github.com/Homebrew/homebrew-core/blob/master/Formula/z/zsh-autosuggestions.rb>
- Homebrew formula: <https://github.com/Homebrew/homebrew-core/blob/master/Formula/z/zsh-syntax-highlighting.rb>

### Q5 — AeroSpace config fragment

**AeroSpace config format.** AeroSpace uses TOML, read from `$XDG_CONFIG_HOME/aerospace/aerospace.toml` (defaults to `~/.config/aerospace/aerospace.toml`). Keybindings live in `[mode.main.binding]`. AeroSpace has "modes" similar to i3/sway; the default `main` mode is the only one most setups need.

Docs:
- Config reference: <https://nikitabobko.github.io/AeroSpace/guide>
- Command list: <https://nikitabobko.github.io/AeroSpace/commands>
- Example config: <https://github.com/nikitabobko/AeroSpace/blob/main/docs/config-examples/default-config.toml>
- Guide (keybindings section): <https://nikitabobko.github.io/AeroSpace/guide#default-keybindings>

**Mapping from sway binds (mod=Mod4/Super → Alt on Mac per PRD scope):**

| Sway | AeroSpace |
|---|---|
| `$mod+h/j/k/l focus <dir>` | `alt-h = 'focus left'` etc. |
| `$mod+1..9 workspace number N` | `alt-1 = 'workspace 1'` etc. |
| `$mod+Shift+1..9 workspace number 11..19` | PRD: workspaces 1-9 move-to via `Alt+Shift+N`. Re-interpreted for AeroSpace (Mac doesn't need the second bank of 11-20). |
| `$mod+Control+N move container to workspace N` | On Mac, the PRD says `Alt+Shift+N` for move. Re-mapped accordingly. |

The PRD explicitly narrows the Mac binding surface to three things: workspaces 1-9 via Alt+N, move-window-to-workspace via Alt+Shift+N, directional focus via Alt+h/j/k/l. Concrete fragment:

```toml
# packages/macos/aerospace/.config/aerospace/aerospace.toml

# Run AeroSpace at login (optional; user can enable via System Settings > Login Items
# or the `start-at-login = true` config key).
start-at-login = true

# Normalize containers (AeroSpace default; keeps i3-style tiling sane).
enable-normalization-flatten-containers = true
enable-normalization-opposite-orientation-for-nested-containers = true

# Default root container layout.
default-root-container-layout = 'tiles'
default-root-container-orientation = 'auto'

# Gaps (optional; mirrors sway's inner/outer gaps).
[gaps]
inner.horizontal = 4
inner.vertical = 4
outer.left = 2
outer.right = 2
outer.top = 2
outer.bottom = 2

# Main mode — standard keybindings, always active.
[mode.main.binding]

# Directional focus (vim-style, mirrors sway $mod+h/j/k/l).
alt-h = 'focus left'
alt-j = 'focus down'
alt-k = 'focus up'
alt-l = 'focus right'

# Directional window move (mirrors sway $mod+Control+h/j/k/l).
# Optional — include if you want parity with sway's move binds.
alt-shift-h = 'move left'
alt-shift-j = 'move down'
alt-shift-k = 'move up'
alt-shift-l = 'move right'

# Workspace switching (mirrors sway $mod+1..9).
alt-1 = 'workspace 1'
alt-2 = 'workspace 2'
alt-3 = 'workspace 3'
alt-4 = 'workspace 4'
alt-5 = 'workspace 5'
alt-6 = 'workspace 6'
alt-7 = 'workspace 7'
alt-8 = 'workspace 8'
alt-9 = 'workspace 9'

# Move focused window to workspace N (mirrors sway $mod+Control+N, re-lettered
# to Alt+Shift+N per PRD because Alt+Shift+hjkl is also used for directional
# move above — if you prefer directional move on Alt+Shift+hjkl, drop it and
# keep only this numeric bank, or move directional move to a separate chord).
alt-shift-1 = 'move-node-to-workspace 1'
alt-shift-2 = 'move-node-to-workspace 2'
alt-shift-3 = 'move-node-to-workspace 3'
alt-shift-4 = 'move-node-to-workspace 4'
alt-shift-5 = 'move-node-to-workspace 5'
alt-shift-6 = 'move-node-to-workspace 6'
alt-shift-7 = 'move-node-to-workspace 7'
alt-shift-8 = 'move-node-to-workspace 8'
alt-shift-9 = 'move-node-to-workspace 9'

# Reload config (parallel to sway's $mod+Shift+c).
alt-shift-c = 'reload-config'

# Kill focused window (parallel to sway's $mod+Shift+q).
alt-shift-q = 'close'

# Fullscreen (parallel to sway's $mod+f).
alt-f = 'fullscreen'

# Layout toggles (close parallels to sway's layout binds).
alt-e = 'layout tiles horizontal vertical'
alt-slash = 'layout accordion horizontal vertical'

# Launch terminal (parallel to sway's $mod+Return → ghostty).
alt-enter = '''exec-and-forget open -na ghostty'''
```

**Collision note.** The PRD reserves both `Alt+Shift+N` (move-to-workspace) and implicitly `Alt+Shift+h/j/k/l` (directional move, by analogy with sway's `$mod+Control+hjkl`). These don't actually collide — numeric keys vs letter keys are distinct. Fragment above includes both; design phase can drop either if desired.

**AeroSpace quirks to watch:**
- AeroSpace does not allow multi-command bindings without `chain` or `mode` switches. Each binding is one command. For most needs this is fine.
- `exec-and-forget` is the escape hatch for arbitrary shell commands (including launching apps via `open`).
- AeroSpace workspaces are independent of macOS Mission Control "Spaces" — this is intentional and desirable (MC Spaces have animation overhead AeroSpace bypasses).
- Accessibility permission required; documented in PRD.

References (all official AeroSpace docs):
- Guide: <https://nikitabobko.github.io/AeroSpace/guide>
- Commands: <https://nikitabobko.github.io/AeroSpace/commands>
- Default config example: <https://nikitabobko.github.io/AeroSpace/config-examples>

### Q6 — Pre-existing dotfile handling with stow

**The problem.** `stow` refuses to link over a real (non-symlink) file at a target, reporting a conflict. Common on fresh Macs (`~/.zshrc` shipped by Apple), MDM-managed machines (IT may push a `~/.zprofile`), or any previously-configured machine.

**Survey of patterns:**

#### Pattern A: Pre-flight backup to `*.pre-stow.bak`

Before `stow <pkg>`, script walks the package tree, for each file that would be stowed, checks the target: if it's a regular file (not a symlink to the expected location), move it to `<target>.pre-stow.bak`. Then stow.

- Pro: Non-destructive. User can inspect/recover.
- Pro: Idempotent — second run sees symlinks, skips backup.
- Con: Requires a small helper script (10-20 lines of bash). Not built into stow.
- Con: Ambiguous if `.pre-stow.bak` already exists (timestamp suffix? refuse?).

#### Pattern B: Fail loudly

Don't attempt to stow if any conflict exists. Print conflicting paths and a remediation message ("rm or back these up, then re-run"). Uses `stow -n` dry-run under the hood.

- Pro: Zero destruction. User has full control.
- Pro: Easy to implement — just `stow -n` and exit non-zero on any conflict output.
- Con: User has to manually resolve. Not great for a fresh-Mac first-run experience.

#### Pattern C: Interactive prompt (per-conflict)

For each conflict: ask "overwrite / backup / skip / abort." Some dotfile frameworks (e.g. `yadm`) do this.

- Pro: Maximum user control.
- Con: Can't run non-interactively (blocks CI, blocks `just setup` via SSH).
- Con: More code to write. Not worth it for a solo-maintainer repo.

#### Anti-pattern: `stow --adopt`

`stow --adopt` (or `-t --adopt`) tells stow to, on conflict, **move the target file into the package and replace it with a symlink**. This "adopts" the existing file. Reference: stow manual, `--adopt` option: <https://www.gnu.org/software/stow/manual/stow.html#index-_002d_002dadopt>.

- **Why it's dangerous:** Adoption rewrites the contents of your dotfiles repo from whatever junk is on the live system. If Apple's default `~/.zshrc` has different content than your repo's `zsh/.zshrc`, `--adopt` *replaces your repo file with Apple's default*. You'd then need to notice and `git checkout` before committing, or you lose your real config.
- Explicitly warned against in community docs: <https://alexpearce.me/2016/02/managing-dotfiles-with-stow/> and discussion: <https://github.com/aspiers/stow/issues/33>.

#### Related tools

- **rcm (`rcup`):** Thoughtbot's dotfile manager, has a `-B` flag to back up existing files before overwriting. Documented in `rcup(1)`. Similar pattern to A. <https://github.com/thoughtbot/rcm>.
- **chezmoi:** Has `--force` and conflict diffs; not stow-compatible. Out of scope per PRD.

**Recommendation for the PRD justfile.** Use Pattern A (pre-flight backup) as the default `just setup` behavior, with an opt-out (`just setup --strict` or env var) that falls back to Pattern B. Concrete sketch:

```bash
# Pseudo-code for justfile recipe
setup_package() {
    pkg_dir="$1"   # e.g. packages/common/zsh
    # Enumerate files stow would link
    stow -d "$(dirname "$pkg_dir")" -t "$HOME" -n "$(basename "$pkg_dir")" 2>&1 \
      | grep 'existing target is neither' \
      | awk '{print $NF}' \
      | while read -r conflict_path; do
          full="$HOME/$conflict_path"
          if [ -e "$full" ] && [ ! -L "$full" ]; then
              echo "Backing up $full -> $full.pre-stow.bak"
              mv "$full" "$full.pre-stow.bak"
          fi
      done
    stow -d "$(dirname "$pkg_dir")" -t "$HOME" "$(basename "$pkg_dir")"
}
```

Cleaner alternative using stow's own dry-run output parsing, or just shell `find` + `test -L`. Either way, ~15 lines added to the justfile.

---

## Internal Research

### Existing Codebase State

**Relevant files reviewed:**
- `/home/sirhamy/Code/dotfiles/justfile` — current build scripts. Uses per-package `for` loop for stow; swallows per-package failures silently (the `@for ... do ... done` construct returns exit 0 even if an individual stow errors). Already splits `packages_common` vs `packages_linux` as string lists. No macos list.
- `/home/sirhamy/Code/dotfiles/zsh/.zshrc` — hardcodes Fedora plugin paths (`/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh`, `/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh`), `alias vim='vimx'`, `/home/sirhamy/.opencode/bin`. Also has a duplicate `export PATH="/usr/local/bin:$PATH"` line and a missing newline at line 27 (the comment for `GLOB_DOTS` runs straight into `source /usr/share/zsh-syntax-highlighting/...`). Both bugs should be fixed during restructure per PRD "In Scope."
- `/home/sirhamy/Code/dotfiles/zsh/` — contains only `.zshrc`. No `.zshenv`, no `.zprofile`.
- `/home/sirhamy/Code/dotfiles/tmux/.tmux.conf` — lives at the package root (targets `$HOME/.tmux.conf`). Already has `if-shell 'command -v pbcopy'` and `if-shell 'command -v wl-copy'` for OS-conditional clipboard integration — an existing precedent for the `if-shell` pattern. No OS-specific file sourcing yet.
- `/home/sirhamy/Code/dotfiles/.stowrc` — single line: `--target=/home/sirhamy`. Breaks portability.
- `/home/sirhamy/Code/dotfiles/sway/.config/sway/config` — the source of truth for what keybinds AeroSpace must mirror. Enumerated in Q5.

**Existing patterns in use:**
- `if-shell` conditional in tmux — precedent established (clipboard lines 49-50). Extending to OS-conditional `source-file` is a natural follow-on.
- Per-package stow loop — current justfile approach. Compatible with PRD's three-bucket layout after minor refactor (change `-d` flag per bucket).

### Reusable Components

- The existing `just plan` recipe (dry-run via `stow -n -v`) is the exact primitive needed for the pre-flight-conflict-detection in Q6's Pattern A. Extending it to parse output and trigger backups is ~15 lines.
- The existing `just install-deps` bash heredoc pattern is reusable for the macOS branch — just add the brew formula/cask lists.
- `if-shell` usage in tmux.conf proves the shell-command syntax works in this repo.

### Constraints from Existing Code

- `justfile` uses `os := uname -s` (returns `Linux` or `Darwin`) at the top. Keep this; PRD's `uname -s | tr A-Z a-z` lowercase key is for filenames, not the justfile OS switch.
- Nothing else in the codebase assumes a particular `ZDOTDIR` — the move is clean.

---

## PRD Concerns

| PRD Assumption | Research Finding | Implication |
|----------------|------------------|-------------|
| tmux loader uses `if-shell ... -b` to make missing files non-erroring | `-b` only backgrounds the shell probe; it does NOT suppress `source-file` errors on missing files. `-q` on `source-file` is what's needed. | Design phase should use `source-file -q ~/.config/tmux/os.darwin.conf`. `-b` on `if-shell` is optional. |
| `$(brew --prefix)` is the canonical resolution | Correct, but `$HOMEBREW_PREFIX` (from `brew shellenv`) is faster and equally idiomatic | Prefer `${HOMEBREW_PREFIX:-$(brew --prefix)}` or explicitly eval `brew shellenv` in a 10-brew.zsh snippet before plugin sourcing. |
| `stow -n` across all three packages will report zero conflicts with `.gitkeep` trick | Correct, provided the common package's `.gitkeep` lives at `packages/common/zsh/.config/zsh/conf.d/.gitkeep` (inside the directory to guard). Missing detail: OS packages must NOT contain their own `.gitkeep` inside `conf.d/` — only inside `conf.d/os.darwin/` if needed. | Document the gitkeep-placement rule in the README's "how to add an OS snippet" section. |
| Current justfile's silent per-package failure is a bug to fix | Confirmed — `@for ... done` in a justfile recipe returns 0 regardless of inner failures unless `set -e` is explicitly used. The current `install-deps` recipe uses `set -euo pipefail` but the `all`/`plan` recipes do not. | Pattern A (pre-flight backup + loud failure on unresolved conflict) adds proper error propagation. |

---

## Critical Areas

### Stow fold ordering during restructure migration

**Why it's critical:** On the existing Fedora machine, stow packages are already linked under the OLD layout (`dotfiles/zsh`, `dotfiles/tmux`, etc. at repo root). The restructure moves these into `packages/common/zsh`, etc. During the migration, `just unstow-all` must run against the OLD layout to clear existing symlinks, *then* `git mv` happens, *then* `stow` against the NEW layout. If the order is wrong, you end up with dangling symlinks pointing at the old repo paths.

**Why it's easy to miss:** The `justfile` change and the `git mv` change and the unstow/restow are all in the same commit if you're not careful. You can't run `just unstow-all` *after* `git mv` because the justfile will already refer to the new paths.

**What to watch for:** The migration procedure should be:
1. On old layout: `just unstow-all` (clears all symlinks)
2. Do the restructure (`git mv`, edit `justfile`, edit `.stowrc`, etc.), commit.
3. On new layout: `just setup` (re-stows from new paths).

Document this in README's "migration path" section (acceptance criterion already called out in PRD).

### tmux `if-shell` shell-cmd expansion

**Why it's critical:** The `if-shell` body is parsed as a tmux string first (which can interpolate `#{}` format strings), then passed to `/bin/sh -c`. Quoting is fiddly.

**Why it's easy to miss:** The current tmux.conf uses `if-shell "command -v pbcopy" "set -s copy-command 'pbcopy'" ""` with double quotes around the shell-cmd. Switching to single quotes (PRD style) is fine but the nested quoting for `tr A-Z a-z` and `source-file -q path` needs to be consistent. Single outer quote avoids `$(...)` re-expansion inside tmux's string handler. Recommended spelling:

```tmux
if-shell '[ "$(uname -s | tr A-Z a-z)" = "darwin" ]' 'source-file -q ~/.config/tmux/os.darwin.conf'
```

**What to watch for:** Test this literal line in a running tmux before committing. `tmux source-file ~/.tmux.conf` to reload.

---

## Deep Dives

### Stow tree-folding with `.gitkeep`

**Question:** When the common package and an OS-specific package both contribute under `.config/zsh/conf.d/`, does stow correctly create a real directory rather than folding one package's contribution as a single symlink?

**Summary:** Yes, provided both packages contribute at least one file each to the shared directory. A `.gitkeep` in the common package guarantees the common side always has a tangible contributor, preventing the fold even if there are no `.zsh` snippets yet. When a later package (e.g. zsh-macos) is stowed, stow unfolds on-the-fly if needed. The manual documents this explicitly: "If stow detects that it can fold a directory, it will do so; if folding would conflict with an existing entry, stow will unfold instead."

**Implications:** PRD's `.gitkeep` approach is correct and standard. Design phase should put a `.gitkeep` in *every* common-owned directory that's a candidate for cross-package sharing (e.g. `conf.d/`, maybe `ghostty/conf.d/` if that pattern is added too). OS-specific packages should NOT have their own `.gitkeep` inside the shared directory — only inside their own OS-specific subdirectories (e.g. `conf.d/os.darwin/.gitkeep` is fine if there are no snippets yet, for git-tracking purposes, but optional).

### zsh `.zshenv` execution frequency

**Question:** The PRD says "keep it minimal — it runs for every zsh invocation." How minimal is minimal?

**Summary:** `.zshenv` is sourced every time zsh starts, including:
- Every new interactive terminal
- Every `#!/usr/bin/env zsh` script
- Every command invoked via `zsh -c '...'`
- Every VS Code / editor integrated terminal spawn
- Every `ssh host command` where the remote login shell is zsh (if the setup is mirrored)

Anything slow in `.zshenv` multiplies. The PRD's `export ZDOTDIR="$HOME/.config/zsh"` is one line, microseconds. Good.

Anti-pattern seen in some dotfile repos: putting `eval "$(brew shellenv)"` in `.zshenv`. That fires the `brew` Ruby process on every script invocation. Belongs in `.zprofile` (login-shell only) or inside a conf.d snippet that only runs for interactive shells.

**Implications:** Document in README that `.zshenv` is sacred minimal. Consider adding a comment to the `.zshenv` itself: `# Keep this file tiny — it runs for every zsh process.`

---

## Synthesis

### Open Questions

| Question | Why It Matters | Possible Answers |
|----------|----------------|------------------|
| Should macOS `brew shellenv` eval live in `.zprofile` (login-only) or in an interactive-shell conf.d snippet? | Affects whether non-interactive scripts see `HOMEBREW_PREFIX`. If scripts need it, `.zshenv`/`.zprofile` is right; if only interactive shells need it, `conf.d/os.darwin/10-brew.zsh` is lighter. | **Recommended:** `.zprofile` under `$ZDOTDIR` (stowed from `packages/macos/zsh-macos/.config/zsh/.zprofile`). Login-shell-only, so no per-subshell cost. Still available to interactive shells (which are typically login on Mac Terminal). Non-interactive scripts that need brew can explicitly source `brew shellenv` themselves. |
| Should the PRD's `$mod+Shift+hjkl move workspace to output left/down/up/right` (move workspace between monitors) be mirrored on AeroSpace? | AeroSpace has `move-workspace-to-monitor` — a real command. Not listed in PRD scope but a natural ergonomic parallel. | Defer to design. Out of PRD's explicit scope; include only if design finds the binding slot available. |
| Should `just setup` run with `--strict` (fail-loudly) or `--backup` (back-up-existing-dotfiles) as default? | Affects whether a fresh-Mac run with Apple's default `.zshrc` auto-recovers or requires manual intervention. | **Recommended:** `--backup` default, with a documented way to inspect `~/.zshrc.pre-stow.bak` afterwards. Matches PRD acceptance criterion wording ("backs them up to `*.pre-stow.bak`"). |

### Recommended Approaches

#### tmux OS-specific source

| Approach | Pros | Cons | Best When |
|----------|------|------|-----------|
| `if-shell ... 'source-file -q <path>'` (recommended) | Silent on missing files (`-q`); synchronous probe; works on every tmux from ~2.4+ | None material | Default choice |
| `if-shell -b ... 'source-file -q <path>'` | Backgrounded probe (negligible gain on `uname`) | Slightly more flags to reason about | If the probe ever becomes slow (unlikely) |
| tmux `%if`/`%endif` | Parse-time, no subprocess | Only evaluates tmux format strings, not shell | Not applicable here |

**Initial recommendation:** Plain `if-shell` + `source-file -q`, no `-b`.

#### Homebrew prefix resolution

| Approach | Pros | Cons | Best When |
|----------|------|------|-----------|
| `$HOMEBREW_PREFIX` (from `brew shellenv`) | Fastest; no subprocess | Requires brew shellenv to have run first | Always, as long as shellenv is set up in .zprofile |
| `${HOMEBREW_PREFIX:-$(brew --prefix)}` | Fast if env set, graceful fallback | 1 line more verbose | Belt-and-suspenders; recommended |
| `$(brew --prefix)` alone | Always correct | 50-200ms cold | Acceptable for one-time startup sourcing |

**Initial recommendation:** In `os.darwin/10-brew.zsh`, `eval "$(/opt/homebrew/bin/brew shellenv)"` (or Intel-path equivalent) to set `$HOMEBREW_PREFIX`. In downstream snippets, use `$HOMEBREW_PREFIX` directly.

#### Pre-existing dotfile handling

| Approach | Pros | Cons | Best When |
|----------|------|------|-----------|
| Pre-flight backup to `*.pre-stow.bak` | Non-destructive; idempotent; auto-recovers on fresh Mac | ~15 lines of justfile logic to write | **Recommended** default |
| Fail loudly via `stow -n` | Zero code; zero risk | Worse UX on fresh machine | Fallback mode / CI |
| `stow --adopt` | One flag | Silently rewrites repo from live files | **Never** — explicitly avoid |
| Interactive prompt | Max control | Can't run headless | Not worth it here |

**Initial recommendation:** Pattern A (backup) as `just setup` default.

### Key References

| Reference | Type | Why It's Useful |
|-----------|------|-----------------|
| [GNU Stow manual](https://www.gnu.org/software/stow/manual/stow.html) | Docs | Tree-folding, conflicts, `--adopt` semantics |
| [zsh STARTUP FILES docs](https://zsh.sourceforge.io/Doc/Release/Files.html#Startup_002fShutdown-Files) | Docs | ZDOTDIR load order, canonical `.zshenv` usage |
| [tmux man page](https://man7.org/linux/man-pages/man1/tmux.1.html) | Docs | `if-shell -b` vs `source-file -q` flag semantics |
| [Homebrew Shell Completion / shellenv](https://docs.brew.sh/Shell-Completion) | Docs | `HOMEBREW_PREFIX` provenance and recommended init |
| [AeroSpace Guide](https://nikitabobko.github.io/AeroSpace/guide) | Docs | `[mode.main.binding]` TOML syntax, default binds |
| [AeroSpace Commands](https://nikitabobko.github.io/AeroSpace/commands) | Docs | Exact command names (`focus`, `move-node-to-workspace`, etc.) |
| [rcm / rcup](https://github.com/thoughtbot/rcm) | Code | `-B` backup flag pattern inspiration for our Pattern A |

---

## Research Log

| Date | Activity | Outcome |
|------|----------|---------|
| 2026-04-24 | Verified stow tree-folding + `.gitkeep` pattern against official manual and community sources | Confirmed PRD claim correct |
| 2026-04-24 | Verified zsh `.zshenv` bootstrap with `ZDOTDIR` | Confirmed canonical minimal stub is exactly as PRD describes |
| 2026-04-24 | Dug into tmux `if-shell -b` vs `source-file -q` | Found PRD wording misattributes silencing to `-b`; should be `-q` on source-file |
| 2026-04-24 | Surveyed Homebrew prefix resolution idioms | Recommended `$HOMEBREW_PREFIX` via `brew shellenv` with `$(brew --prefix)` fallback |
| 2026-04-24 | Enumerated sway binds in scope for AeroSpace mirror; drafted TOML fragment | Concrete aerospace.toml block produced |
| 2026-04-24 | Surveyed pre-existing-dotfile patterns; flagged `stow --adopt` danger | Pattern A (backup) recommended as default |
