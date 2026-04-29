# Change: Cross-OS Dotfiles Restructure

**Status:** Proposed
**Created:** 2026-04-24
**Author:** Hamilton Greene

## TL;DR

- **Problem:** Dotfiles are Linux-first with Fedora paths hardcoded in shared configs; author needs daily-driver parity across a personal Linux box and a work Mac, and expects the dual-OS split to persist indefinitely.
- **Solution:** Adopt a three-rule architecture:
  - **Rule 1 — Package split:** Stow packages live under `packages/{common,linux,macos}/<pkg>`. Every package belongs to exactly one bucket.
  - **Rule 2 — `conf.d` loader pattern:** Shared-but-divergent apps (zsh, tmux) have a loader in the common package that sources a lexicographic glob of `conf.d/*` plus `conf.d/os.<osname>/*`, where `<osname>` is `uname -s` lowercased.
  - **Rule 3 — Filesystem-based OS branching:** OS branching lives in filenames and directory paths, not in `case $OSTYPE` / `if [[ Darwin ]]` inside config bodies. The loader's one-line glob is filesystem dispatch, not an in-body conditional.
- **Key criteria:** (1) `just setup` produces a working shell/editor/terminal on both Fedora and macOS from a clean clone. (2) Editing an OS-specific config means editing a file whose path names the OS. (3) Adding a new OS-only snippet requires no edits to shared files.
- **Merge gate:** Split into pre-merge (dry-run + Fedora validated from any machine) and post-merge Mac validation (initial work-Mac rollout, small patches directly to `main`).

## Problem Statement

The dotfiles repo at `~/Code/dotfiles` is structured as a stow-managed collection split between `packages_common` and `packages_linux` lists in the `justfile`. It works cleanly on Fedora (the author's personal machine) but has several issues when taken to a Mac:

1. **Shared configs are not actually shared.** `zsh/.zshrc` hardcodes Fedora paths (`/usr/share/zsh-autosuggestions/...`, `/usr/share/zsh-syntax-highlighting/...`) and a Fedora-only alias (`vim=vimx`). On Mac these either no-op silently or fail outright.
2. **No macOS package list.** Mac-only tools (e.g. aerospace for window management, brew-path plugin sourcing) have nowhere to live in the current taxonomy.
3. **`bin/` conflates portable scripts with Linux-specific ones.** `zellij-sessionizer` is cross-platform in spirit but wraps a sway-specific floating-terminal launch. `obsidian-scratchpad`, `scratchpad-toggle`, `sway-launch` are sway-only but sit alongside the shared scripts.
4. **The fix everyone reaches for — `case $OSTYPE`/`if [[ Darwin ]]` inside config files — doesn't scale.** With a dual-OS split expected to continue for years across personal Linux and work Mac setups, an ad-hoc branching approach will produce sprawling conditionals across many config files, each with its own partial pattern.
5. **`.stowrc` hardcodes `--target=/home/sirhamy`.** This absolute, user-specific path works on the current Fedora box and nowhere else — it breaks on macOS (`/Users/...`) and on any other machine/user.

The author is bringing these dotfiles to a work Mac and wants a durable architecture, not a one-off port.

## User Stories / Personas

- **Hamilton (self)** — Writes these dotfiles, uses them daily. Runs Fedora + sway at home as the primary dev setup and uses a work Mac alongside it. Expects this pattern (personal Linux, work Mac) to repeat across future work machines. Wants muscle memory from home to carry over to work with minimal friction, and vice versa.

## Desired Outcome

After this change, a fresh clone of `dotfiles` on either Fedora or macOS can run `just setup` and arrive at a working terminal (Ghostty), shell (zsh with prompt, history, plugins, zoxide, fzf), editor (nvim + LazyVim), multiplexer (zellij + tmux), and file manager (yazi). The resulting setup uses identical keybindings and aliases for cross-OS tools (zsh, nvim, zellij, tmux, yazi), and diverges only where the OS requires it — window manager, notification daemon, and system-extension-level tooling are the only documented exceptions.

Editing an OS-specific config looks like opening a file under `packages/macos/zsh-macos/.config/zsh/conf.d/os.darwin/` — the path itself tells you what context it applies to. No grepping for `Darwin` across the repo. Adding a new OS-only snippet is a one-file add with no edits to shared files.

zsh config migrates to `$ZDOTDIR=~/.config/zsh`. This means:
- `~/.zshenv` is a tiny file (stowed from `packages/common/zsh`) that just exports `ZDOTDIR`. It stays at `$HOME` because zsh reads it before it knows where the rest of config lives. Keep it minimal — it runs for every zsh invocation.
- `~/.config/zsh/.zshrc` is the real loader (also stowed from `packages/common/zsh`).
- All `conf.d/` snippets live under `~/.config/zsh/conf.d/`.

The loader contract for `conf.d`:

```sh
# in packages/common/zsh/.config/zsh/.zshrc (simplified)
ZDOTCONFD="${ZDOTDIR}/conf.d"
os_key="$(uname -s | tr '[:upper:]' '[:lower:]')"   # linux | darwin
setopt null_glob
for f in "$ZDOTCONFD"/*.zsh "$ZDOTCONFD/os.$os_key"/*.zsh; do
  [ -r "$f" ] && source "$f"
done
unsetopt null_glob
```

Rules: common snippets load before OS-specific. Missing directories are tolerated (no error, no warning). A broken snippet prints its error but must not abort shell startup.

The `justfile` retains a small, contained set of OS branches (dependency install commands, which package lists to stow, which reload commands exist) but the config files themselves are branch-free.

## Success Criteria

Define how we know this change succeeded. These should be testable before implementation begins.

### Must Have (Pre-Merge Gate)

All of these must be true before the restructure can merge to `main`. They are verifiable from any machine — the Mac-on-hardware checks move to the post-merge gate below.

- [ ] **`.stowrc` is portable.** Either `--target=$HOME` or `.stowrc` removed and `-t ~` passed in the `justfile`. No hardcoded absolute user path remains.
- [ ] **Pre-existing dotfile handling.** `just setup` detects pre-existing non-symlink dotfiles at stow targets and either (a) backs them up to `*.pre-stow.bak` or (b) exits non-zero with a clear remediation message. The current justfile's silent-per-package-failure behavior is fixed.
- [ ] **On Fedora**, `just setup` from a clean clone (and from the migration path on the current machine) produces no regressions against this checklist: (a) zsh prompt renders, (b) zsh-autosuggestions + zsh-syntax-highlighting active, (c) zoxide `z` works, (d) fzf Ctrl-R / Ctrl-T bound, (e) zellij launches via existing shortcut, (f) tmux launches with config, (g) nvim opens with LazyVim, (h) yazi opens, (i) sway reloads without error.
- [ ] **`stow -n` dry-run clean on macOS layout** — invoked from a Linux box against the full `packages/common/*` + `packages/macos/*` set (using `-t <some-dir>`) reports zero conflicts. This validates the three-package zsh tree-folding story without needing Mac hardware.
- [ ] **zsh migrated to `$ZDOTDIR`.** `packages/common/zsh` stows (a) a minimal `~/.zshenv` that exports `ZDOTDIR="$HOME/.config/zsh"` and nothing else, and (b) the real loader at `~/.config/zsh/.zshrc`. All `conf.d/` snippets live under `~/.config/zsh/conf.d/`.
- [ ] **No in-body OS conditionals in config files.** No `case $OSTYPE` / `if [[ Darwin ]]` inside any `.zshrc`, `.tmux.conf`, or similar. The loader pattern (filesystem dispatch via `uname -s`-keyed directory glob) is the only allowed OS-branching mechanism in config files. Loader stubs themselves are single-line, shared, and not OS-specific.
- [ ] `packages/` directory contains three subdirectories: `common/`, `linux/`, `macos/`. Every stow package lives under exactly one. Package layout is `packages/{common,linux,macos}/<pkg>` (flat inside each bucket, not grouped by app).
- [ ] `zsh` package is split: `packages/common/zsh` holds `~/.zshenv`, `~/.config/zsh/.zshrc`, common `conf.d/*.zsh` snippets, and owns the `~/.config/zsh/conf.d/` directory (via a `.gitkeep` placeholder); `packages/linux/zsh-linux` adds only `conf.d/os.linux/*.zsh`; `packages/macos/zsh-macos` adds only `conf.d/os.darwin/*.zsh`. `stow -n` on all three packages together reports zero conflicts.
- [ ] `bin/` is split into `packages/common/bin` (portable scripts only) and `packages/linux/bin-linux` (sway-specific: `sway-launch`, `obsidian-scratchpad`, `scratchpad-toggle`). `packages/macos/bin-macos` is created as an empty stow package (with `.gitkeep`) — no Mac-specific scripts are in scope for this change.
- [ ] `aerospace` exists as a `packages/macos/aerospace` stow package with a config that mirrors the sway keybinding shape (workspaces 1–9 via Alt+N, move-window via Alt+Shift+N, directional focus via Alt+h/j/k/l). Sway binds to mirror are those defined in the current `sway/.config/sway/config`.
- [ ] `install-deps` is defined for macOS: brew formulae for `stow, zsh, zoxide, fzf, zellij, tmux, neovim, fd, lazygit, yazi, zsh-autosuggestions, zsh-syntax-highlighting`; brew casks for `ghostty, aerospace`. Missing packages fail loudly.
- [ ] `os.darwin` zsh snippets use `$(brew --prefix)` to resolve Homebrew paths (no hardcoded `/opt/homebrew` or `/usr/local`).
- [ ] README is updated with: (a) the three-rule taxonomy, (b) a concrete `conf.d` example, (c) how to add a new OS-specific snippet, (d) a "macOS setup" section covering Caps→Esc, AeroSpace Accessibility grant, and MDM fallback, (e) per-OS install instructions, (f) the **post-merge Mac validation workflow** (see below), (g) the migration path for the existing Fedora machine.

### Must Have (Post-Merge Mac Validation)

These are verified on the work Mac during initial setup. Failures here are expected to be small, localized patches (wrong cask name, aerospace config tweak) rather than architectural changes.

- [ ] **Full `just setup` on clean Mac** produces a working environment verified by: (a)–(h) of the Fedora checklist above (aerospace launch/reload substituting for sway), plus (i) Ghostty launches, (j) zsh plugins load via resolved brew paths, (k) Caps Lock → Escape applied per README's manual-step instructions, (l) AeroSpace Accessibility permission granted and window-management works.
- [ ] **MDM posture documented.** Any brew/cask/permission blocks encountered are captured in the README's "macOS setup" section so future managed Macs hit the same doc.

### Post-Merge Mac Validation Workflow

The workflow must be trivially easy from any computer — this is the whole point of splitting the gate.

1. **Discover a Mac-specific issue** on the work Mac (e.g., `brew install --cask ghostty-something` fails, an aerospace binding is wrong).
2. **Edit from any computer** — open the repo in your editor on the Fedora box, the Mac itself, or anywhere. The change is almost always a one-file edit: a cask name in `justfile`, a path in `packages/macos/zsh-macos/conf.d/os.darwin/*.zsh`, a keybind in `packages/macos/aerospace/.../aerospace.toml`.
3. **Commit and push** to `main` (or a short-lived branch if you want review). No long-lived branches; the restructure is already merged.
4. **Pull on the Mac** and re-run `just setup` (idempotent — re-stows, re-runs `install-deps`). Or for config-only changes, the stow symlinks already point at the repo, so `git pull` alone may suffice (zsh/tmux/aerospace will pick up changes on next reload/restart).
5. **No migration dance.** Unlike the one-time restructure migration, post-merge fixes are just normal commits on `main`.

Acceptance for this workflow: the README must state the above steps explicitly, and the `justfile` must support re-running `just setup` idempotently on a partially-configured Mac.

### Should Have

- [ ] `tmux` package follows the same `conf.d` pattern as `zsh`, adapted for tmux's config language: the loader uses `if-shell '[ "$(uname -s | tr A-Z a-z)" = "darwin" ]' 'source-file ~/.config/tmux/os.darwin.conf'` (and linux equivalent), with `-b` (background) so missing files don't error. Even if no OS-specific tmux config exists today, the scaffolding is in place for future divergence.
- [ ] The `justfile` OS dispatch is reduced to three clearly-named lists (`packages_common`, `packages_linux`, `packages_macos`) with a single selector that invokes `stow -d packages/<bucket> -t ~` per bucket.
- [ ] `ghostty` config adopts `conf.d`-style scaffolding preemptively (even with no current OS divergence) so future brew-vs-Linux-build differences land in one-file adds, not retrofits.

### Nice to Have

- [ ] A short `ARCHITECTURE.md` at the repo root (root chosen over `docs/` for discoverability) explaining the three-rule pattern in more depth than the README overview.
- [ ] A `just plan-os linux` / `just plan-os macos` that shows what would be stowed on the *other* OS (useful for sanity-checking a commit made on one machine before it lands on the other).
- [ ] Port `zellij-sessionizer`'s floating-terminal launch to an OS-specific wrapper. **Deferred**: ship the restructure with sessionizer remaining in `packages/linux/bin-linux` (it's sway-coupled today); Mac port is a follow-up change once the aerospace floating-window mechanism is settled.

## Scope

### In Scope

- Restructuring the repo under `packages/{common,linux,macos}/`. File moves use `git mv` to preserve blame history.
- Introducing the `conf.d` loader pattern in `zsh` (and scaffolding it in `tmux` and `ghostty`).
- Creating `zsh-macos`, `bin-macos` (empty), `aerospace` packages.
- Splitting `bin/` into portable + OS-specific.
- Fixing the hardcoded Fedora paths in `.zshrc` by moving them into `zsh-linux/.../os.linux/`. This includes fixing the surfaced bugs touched by the move: duplicate `PATH` export, missing newline before a `source` line, unguarded `$HOME/.cargo/env` source, hardcoded `/home/sirhamy/.opencode/bin` path. Any `.zshrc` issues *not* on lines being moved are out of scope for this change.
- Fixing the `.stowrc` hardcoded target.
- Updating `justfile` to handle the three-list + three-directory taxonomy, with `stow -d packages/<bucket>` invocations per bucket.
- Updating README and adding ARCHITECTURE doc.
- Testing on both Fedora (existing, via migration) and macOS (on the work Mac) from a clean clone.
- `packages/linux/` for this change means "Fedora-compatible Linux." Other Linux distros (Debian, NixOS, etc.) are not a goal — supporting them is a future change.

### Out of Scope

- **Karabiner-Elements setup.** Mac handles Caps→Esc natively; no kernel-extension-level keyboard remapping needed.
- **Hyper-key remap for Super-equivalent modifier.** Alt is fine as the mod on Mac.
- **Porting `obsidian-scratchpad` to Mac.** Sway-specific; a Mac equivalent (aerospace scratchpad or dedicated floating window rule) is a separate, future change.
- **Porting `zellij-sessionizer` to Mac.** Sway-coupled; deferred to a follow-up.
- **Windows / WSL support.** Not needed now; the architecture should not *preclude* it but we will not build/test for it. Distro detection for non-Fedora Linux is likewise deferred.
- **Migrating to chezmoi, home-manager, nix, or other dotfile managers.** Stow stays.
- **Changing any tool's behavior or keybindings beyond what OS-parity requires.** This is a structural refactor, not a feature change.
- **A `just doctor` health-check command.** No concrete pain point justifies it yet; revisit only if setup fails silently in practice.
- **Auditing `install-deps` for end-to-end idempotency.** Brew/dnf are idempotent for repeat installs; the restructure's idempotency claim applies to `stow`/symlink operations, not to side-effecting sudo steps (copr enable, grub edit, flatpak install).
- **A per-machine `conf.d/local/` (gitignored) slot for machine-local secrets / VPN / proxy config.** Deferred unless the work Mac actually requires it.

## Non-Functional Requirements

- **Reliability (stow-level):** `just setup` is idempotent at the stow/symlink layer — running it twice on the same machine produces no errors and no duplicate symlinks. Partial-failure recovery (e.g. network drop mid-`install-deps`) is handled by re-running `just setup`; brew/dnf are idempotent on repeat.
- **Fail-safe shell:** A missing `conf.d` directory, unreadable snippet, or syntax error in a single snippet must log an error but not abort zsh startup. The user must never be locked out of their login shell by a malformed OS-specific snippet.
- **Reversibility:** `just unstow-all` must work on both OSes and leave `~` as close to pre-setup as stow can manage. It does not un-install packages or revert System Settings changes (e.g. Caps→Esc).
- **Platform Support:** Fedora (current version on the personal machine) and macOS (current version on a managed work Mac, Apple Silicon assumed). Homebrew prefix is resolved dynamically via `$(brew --prefix)` — no hardcoded `/opt/homebrew` or `/usr/local`. No pinning to specific subversions.
- **Portability:** The restructure should not preclude adding a third OS later (e.g. WSL, FreeBSD) without re-architecting. The OS-key normalization (`uname -s | tr A-Z a-z`) handles this naturally for Unix-family OSes; Windows would need a separate key scheme.

## Constraints

- **Keep using stow.** No switch to a different dotfile manager as part of this change.
- **Managed-Mac security realities.** The Mac may be managed by Mobile Device Management (MDM). The solution must not require disabling System Integrity Protection (SIP) or installing kernel extensions. This rules out yabai and (for now) Karabiner-Elements. Homebrew and AeroSpace installs assume admin rights on the work Mac; if MDM blocks them, see Needs Attention.
- **Solo maintainer.** No external review process. The ARCHITECTURE doc exists to help future-self, not a team.
- **Obsidian Sync compatibility is not a concern here** — this repo is not the Obsidian vault.

## Dependencies

- **Depends On:**
  - Homebrew installed on the Mac (prerequisite for `just install-deps`).
  - GNU stow 2.x available on both OSes (already in `install-deps`).
  - Network access during initial `just setup` to install packages and pull aerospace.
- **Blocks:**
  - Any future macOS-specific config work (aerospace tuning, Mac-specific zellij layouts, etc.) — cleanest to land this restructure first.

## Risks

- [ ] **Stow conflicts during migration.** Moving packages into `packages/{common,linux,macos}/` will require unstowing everything first on the current Fedora machine, then re-stowing from the new layout. If something goes wrong mid-flight, shell/editor could be in a broken state. **Mitigation:** dry-run `just plan` at each step; keep a scratch shell open in case the zsh rewrite breaks login.
- [ ] **Multiple packages writing to the same `conf.d/` tree could collide via stow tree-folding.** E.g. if `common/zsh` and `macos/zsh-macos` both expose directories at `.config/zsh/conf.d/`. **Mitigation:** only the common package owns the top-level `conf.d/` directory (via a `.gitkeep` placeholder to prevent stow folding); OS-specific packages only contribute their `os.linux/` or `os.darwin/` subdirs. Must-Have acceptance requires `stow -n` across the full package set to report zero conflicts on both OSes.
- [ ] **Managed-Mac policy / MDM may block brew or aerospace.** **Mitigation:** check managed-device policy before running `just setup` on the work Mac; manual fallback is to stow `packages/common/*` only. See "Needs Attention" item 3 for whether to bake this into tooling.
- [ ] **Scope creep toward "fix everything on Mac while you're at it."** Tempting to also rework nvim for Mac, add new tools, etc. **Mitigation:** this PRD constrains scope to structural restructure only; anything feature-level goes in a follow-up change.
- [ ] **Pre-existing macOS dotfiles block stow.** A fresh Mac has a default `.zshrc`/`.zprofile`; MDM may have pushed more. Stow refuses to link over real files, and the current justfile's `@for` loop swallows per-package failures silently. **Mitigation:** Must-Have adds backup-or-fail behavior to `just setup`.
- [ ] **Broken zsh snippet could lock user out of login shell.** **Mitigation:** Non-Functional Requirement mandates fail-safe loader semantics.

## Resolved Decisions

Items that were directional during critique, now decided:

1. **zsh migrates to `$ZDOTDIR=~/.config/zsh`.** `packages/common/zsh` stows a minimal `~/.zshenv` (just `export ZDOTDIR="$HOME/.config/zsh"`) plus the real loader at `~/.config/zsh/.zshrc`. All snippets live under `~/.config/zsh/conf.d/`. No meaningful cross-OS downsides; standard zsh feature.
2. **Mac validation is split into pre-merge (dry-run, Fedora clean-clone) and post-merge (real Mac, initial setup).** See "Post-Merge Mac Validation Workflow" in Must-Have. Post-merge fixes are small patches to `main`, not branch work.
3. **MDM fallback is document-only.** README's "macOS setup" section explains the manual `stow -d packages/common -t ~ $(ls packages/common)` workaround if brew/cask is blocked. No `just setup-common-only` recipe until a real blocker is hit.
4. **justfile naming stays `packages_common` / `packages_linux` / `packages_macos`.** Matches directory names; `_only` suffix is cognitive overhead for no clarity gain.

## Open Questions

Implementation-phase items that can be decided during SPEC or build:

- [ ] Exact set of aerospace keybindings to mirror from sway — enumerate during design after reviewing current `sway/.config/sway/config`.
- [ ] Whether to verify stow tree-folding behavior via a scripted `stow -n` test in CI-equivalent form, or via manual dry-run during implementation.

## References

- Current dotfiles: `~/Code/dotfiles`
- Current `justfile`: `packages_common` / `packages_linux` recipe lists; `setup-linux` / `setup-mac` / `install-deps` recipes.
- Current `.zshrc`: the hardcoded Fedora plugin paths (`/usr/share/zsh-autosuggestions/...`, `/usr/share/zsh-syntax-highlighting/...`) and `alias vim='vimx'` — `vimx` is Fedora's clipboard-enabled `vim-X11` binary, so the alias fails on macOS where clipboard support is already compiled into brew's `vim`.
- Current `bin/` contents: `bin/.local/bin/` (mixed portable + sway-specific — `zellij-sessionizer`, `sway-launch`, `obsidian-scratchpad`, `scratchpad-toggle`).
- Current `.stowrc`: contains `--target=/home/sirhamy` hardcoded path.
- AeroSpace (chosen Mac window manager): https://github.com/nikitabobko/AeroSpace
