# dotfiles

Public configuration files for my development environment, managed with [GNU Stow](https://www.gnu.org/software/stow/) and `just`. Targets Fedora (sway-based personal box) and macOS (work Mac, AeroSpace-based) from a single source tree.

**This repo is for public configs only.** No secrets, API keys, or private tooling.

## 1. What this repo is

A stow-managed dotfiles repo split into three buckets — `packages/common/`, `packages/linux/`, `packages/macos/`. `just setup` on either OS produces a working terminal (Ghostty), shell (zsh + plugins + zoxide + fzf), editor (nvim/LazyVim), multiplexers (zellij, tmux), file manager (yazi), and window manager config (sway on Linux, AeroSpace on Mac). Editing OS-specific config means editing a file whose path names the OS — no `case $OSTYPE` inside config bodies.

## 2. The three-rule taxonomy

1. **Package split.** Every stow package lives under exactly one of `packages/{common,linux,macos}/<pkg>/`. Common is linked everywhere; linux/macos buckets are linked only on the matching OS.
2. **`conf.d/` loader pattern.** Shared-but-divergent apps (today: zsh; scaffolded for tmux) ship a loader in the common package that sources a lexicographic glob of `conf.d/*` snippets, then `conf.d/os.<key>/*` snippets where `<key>` is `uname -s` lowercased (`linux` or `darwin`).
3. **Filesystem-based OS branching.** OS branches live in filenames and directory paths, not in `case $OSTYPE` / `if [[ Darwin ]]` inside config bodies. The loader's one-line dispatch is the only OS conditional in any config file.

## 3. Loader Contract — 5 rules

The load-bearing invariant of the architecture:

1. **Directory-guard ownership.** Each shared target directory (`~/.config/zsh/conf.d/`, `~/.local/bin/`) is owned by a `.gitkeep` inside the common package. OS-specific packages must not also place a `.gitkeep` in the same directory.
2. **OS-specific contents live under `conf.d/os.<key>/`.** OS packages must only add files under `conf.d/os.<key>/`. Never add files directly to `conf.d/`. Never add an `os.darwin/` dir from a Linux package or vice versa. To override a common snippet, use the same numeric prefix in an OS-specific snippet — OS-specific is sourced after common, last-write wins.
3. **Key-to-bucket match.** `linux` bucket uses `os.linux/`; `macos` bucket uses `os.darwin/`. Bucket names match directory names; keys match `uname -s` normalized.
4. **No `exit` / `return N` at snippet top level.** Snippets are `source`d. An `exit 1` kills the login shell. Use guarded conditionals (`[ -r "$f" ] && source "$f"`).
5. **Fail-safe loader.** A missing `conf.d/os.<key>/` directory is tolerated. A syntax error in a snippet prints to stderr and the loader moves on. A broken snippet must never abort zsh startup.

`just check-conflicts` enforces Rule 1 by walking the package tree directly. Rules 2–4 are author discipline.

## 4. Concrete `conf.d` example

```
~/.config/zsh/                                         (stowed)
├── .zshrc                                             ← loader (common/zsh)
├── .zshenv                                            ← brew shellenv (Mac only, from zsh-macos)
└── conf.d/
    ├── .gitkeep                                       ← dir-guard, owned by common/zsh
    ├── 10-shell.zsh                                   ← common
    ├── 20-prompt.zsh                                  ← common
    ├── 30-path.zsh                                    ← common
    ├── 40-functions.zsh                               ← common
    ├── 50-aliases.zsh                                 ← common
    ├── os.linux/                                      ← only on Linux
    │   ├── 10-plugins.zsh                             ← /usr/share/zsh-* sources
    │   ├── 20-aliases.zsh                             ← alias vim='vimx'
    │   └── 30-paths.zsh                               ← cargo + opencode
    └── os.darwin/                                     ← only on Mac
        ├── 10-brew.zsh                                ← $HOMEBREW_PREFIX plugin sources
        └── 20-aliases.zsh                             ← alias ls='ls -G'
```

The loader (excerpt from `packages/common/zsh/.config/zsh/.zshrc`):

```sh
case "$OSTYPE" in darwin*) os_key=darwin ;; linux*) os_key=linux ;; *) os_key="$(uname -s | tr '[:upper:]' '[:lower:]')" ;; esac
ZDOTCONFD="${ZDOTDIR:-$HOME/.config/zsh}/conf.d"
setopt null_glob
for f in "$ZDOTCONFD"/*.zsh "$ZDOTCONFD/os.$os_key"/*.zsh; do
  [ -r "$f" ] || continue
  source "$f"
done
unsetopt null_glob
```

## 5. How to add an OS-specific snippet

Scenario: an `fnm` PATH export on Mac only.

1. Create `packages/macos/zsh-macos/.config/zsh/conf.d/os.darwin/40-fnm.zsh` with the `export PATH=...` line.
2. `git add && git commit && git push`.
3. On the Mac, `git pull`. Two cases:
   - **File added to an already-stowed `os.darwin/` dir:** the symlink already points into the package tree, so the new file is visible immediately. No stow needed.
   - **First file in a newly-created `os.<key>/` subdirectory:** run `just restow` once to re-link the package and pick up the new subdir.
4. Open a new shell — the snippet is sourced.

Rule of thumb: if in doubt, `just restow` — it's idempotent and cheap.

## 6. How to add a new top-level package

Scenario: add `starship` as a common package.

1. `mkdir -p packages/common/starship/.config/starship` and create files mirroring the target paths under `~`.
2. Add `starship` to the `packages_common` list in `justfile`.
3. `just plan` to verify no conflicts.
4. `git commit && just restow` (or `just setup` for the full pass).

For an OS-specific package (e.g. `tmux-macos` on first divergence): create under `packages/macos/`, register in `packages_macos`, and if it contributes to a shared directory drop a `.gitkeep` in the common owner per Rule 1.

**Note on `--no-folding`:** every stow invocation in `justfile` passes `--no-folding`. Stow's tree-folding will collapse single-package directories into one symlink, which breaks cross-bucket sharing of directories like `~/.config/zsh/`. `.gitkeep` placeholders alone are insufficient when packages live under different `-d` (stow-dir) values, so the helpers (`_stow-bucket`, `_stow-bucket-flag`, `_plan-bucket`) all force `--no-folding`.

## 7. Per-OS install instructions

**Prerequisites (manual, one-time):**

Fedora:
```sh
sudo dnf install -y just stow git
```

macOS:
```sh
# Install Homebrew first if you don't have it:
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install just stow git
```

**Then on either OS:**

```sh
git clone git@github.com:SIRHAMY/dotfiles.git ~/Code/dotfiles
cd ~/Code/dotfiles
just setup profile=linux-workstation   # Fedora desktop
# or
just setup profile=mac-workstation     # Mac
```

`just setup profile=<name>` runs the matching `install-deps-<profile>` recipe (dnf on Fedora workstation; brew + casks on Mac), including the pinned official OpenCode v1.18.3 installer for every profile, then `check-conflicts`, then `all` (per-bucket stow). On `linux-workstation` it also runs `setup-sway-session`.

**Profile is required** — `just setup` with no profile and no `$DOTFILES_PROFILE` exits with a list of valid profiles for the current OS. For ergonomic muscle memory, export the profile once in your shell rc (e.g. `~/.zprofile`):

```sh
export DOTFILES_PROFILE=linux-workstation
```

Then plain `just setup` works again. See §15 for the remote-profile path and full precedence rules.

## 8. macOS setup

After `just setup` finishes, three manual one-time steps:

1. **Caps Lock → Escape.** System Settings → Keyboard → Keyboard Shortcuts → Modifier Keys → set Caps Lock to Escape. Mac handles this natively; no Karabiner needed.
2. **AeroSpace Accessibility permission.** Launch AeroSpace (`open -a AeroSpace`). When prompted, grant Accessibility permission in System Settings → Privacy & Security → Accessibility. Then `aerospace reload-config`.
3. **Hide the macOS menu bar (so SketchyBar can own the top strip).** System Settings → Control Center → "Automatically hide and show the menu bar" → set to **Always**. Otherwise SketchyBar's bar and the macOS menu bar stack on top of each other. Hiding the menu bar also hides the AeroSpace menu-extra workspace indicator, which is the intended outcome — SketchyBar replaces it.
4. **Shell PATH handled automatically.** `packages/macos/zsh-macos/.config/zsh/.zshenv` evals `brew shellenv` and adds `~/.opencode/bin` on every zsh invocation (login or not), so new tmux/zellij panes get Homebrew and official OpenCode binaries on `PATH` without `.zprofile`-only weirdness.

**MDM fallback (managed work Mac).** If brew or cask installs are blocked by MDM, you can still stow the common configs by hand, skipping `install-deps`:

```sh
stow --no-folding -d packages/common -t ~ $(ls packages/common)
```

You will be missing the brew formulae (zsh plugins, fzf, etc.) and the casks (Ghostty, AeroSpace), but the configs themselves will link. File a ticket with IT for the missing pieces.

If SketchyBar specifically is blocked (tap install denied), skip step 3 above and leave the macOS menu bar visible — AeroSpace's built-in menu-extra workspace indicator is the fallback. The `exec-on-workspace-change` hook in `aerospace.toml` is guarded with `command -v sketchybar`, so AeroSpace itself stays healthy without it.

## 9. Post-merge Mac validation workflow

Once the restructure is merged to `main`, fixing Mac-specific issues from any computer is a normal commit, not a migration:

1. **Discover** a Mac-specific issue (wrong cask name, an AeroSpace bind that fights a system shortcut, etc.).
2. **Edit from any computer** — the Fedora box, the Mac itself, or anywhere. Almost always a one-file edit: a cask name in `justfile`, a path in `packages/macos/zsh-macos/.config/zsh/conf.d/os.darwin/*.zsh`, a keybind in `packages/macos/aerospace/.config/aerospace/aerospace.toml`.
3. **Commit and push** to `main` (or a short-lived branch if you want review).
4. **Pull on the Mac** and re-run `just setup` — idempotent. For config-only changes, `git pull` alone may suffice; the stowed symlinks already point into the repo, so zsh/tmux/aerospace pick up changes on next reload (`tmux source ~/.tmux.conf`, `aerospace reload-config`, or open a new shell).
5. **No migration dance.** Just normal commits on `main`.

## 10. Migration path for the existing Fedora machine

The one-time painful path. PRD risk: "Stow conflicts during migration."

1. **Open a scratch shell now** — a second Ghostty window running `bash -l`, kept open for the whole migration. If the zsh rewrite breaks mid-flight this is your lifeline. Do not close it until a fresh zsh from a *third* Ghostty window works.
2. Verify clean working tree: `git status` — must be clean before checkout.
3. `cd ~/Code/dotfiles && just unstow-all` (run this on the OLD branch — operates on the flat `<pkg>/` roots that existed pre-restructure).
4. Verify no orphan symlinks: `find ~ -maxdepth 4 -type l -lname "*Code/dotfiles*" 2>/dev/null` — should be empty after unstow. If not, `rm` the orphans manually.
5. `git checkout <restructure-branch>` (or `main` if already merged).
6. `just plan` — verify zero stow conflicts. If any, fix before proceeding.
7. `just setup` — `check-conflicts` catches any leftover real files (e.g. a `.zshrc` that wasn't managed by stow), re-stows from the new layout, reloads sway.
8. Open a *third* terminal window (new zsh). Confirm prompt, plugins, zoxide, fzf bindings all work.
9. Close the scratch shell.

**Recovery if zsh breaks:** from the scratch `bash -l` shell:

```sh
mv ~/.zshenv ~/.zshenv.broken
mv ~/.zshrc  ~/.zshrc.broken 2>/dev/null
```

A new zsh will then start with defaults, no `ZDOTDIR`, no loader. Debug from there.

## 11. Reversibility

- `just unstow-all` removes every symlink stow placed in `~`. Three-bucket form: OS bucket unwinds first (so OS-specific dir guards clean up before the common owner), then common.
- `just unstow-all` does NOT uninstall packages and does NOT revert system settings (Caps→Esc, AeroSpace Accessibility grant, NVIDIA grub edits, etc.).
- `just restow` runs `stow -R --no-folding` per bucket. Use after deleting a snippet file to clear dangling symlinks, or after adding a file in a brand-new `os.<key>/` subdirectory.

## 12. Loader debugging

When a snippet errors:

- Errors print to stderr at shell start — read what zsh says.
- For stuck cases, start zsh with no rc files: `zsh -f`. This skips `.zshenv`, `.zshrc`, and the loader entirely.
- Move the offending snippet aside without deleting it: `mv 99-foo.zsh 99-foo.zsh.disabled`. The loader globs `*.zsh`, so `.disabled` is ignored. Then `just restow` to clean up the stale symlink and restart your shell.
- If `~/.zshenv` itself is broken (rare — it's tiny), use the recovery escape from §10.

## 13. Hand-invocation note

`just` is the supported entry point. If you must run `stow` directly, you need both `-d packages/<bucket>` and `-t ~` (and `--no-folding` to match the justfile's behavior):

```sh
stow --no-folding -d packages/common -t ~ zsh
stow -D --no-folding -d packages/linux -t ~ sway     # unlink
```

`.stowrc` was deliberately removed — it used to hardcode `--target=/home/sirhamy`, which was non-portable. The `justfile` is now the single source of truth for stow invocation.

## 14. Cheatsheet

### Sway (Linux)

| Action | Keys |
|--------|------|
| Focus direction | `Super+h/j/k/l` or `Super+Arrows` |
| Move container direction | `Super+Ctrl+h/j/k/l` or `Super+Ctrl+Arrows` |
| Move workspace to output | `Super+Shift+h/j/k/l` or `Super+Shift+Arrows` |
| Switch to workspace 1-10 | `Super+1-0` |
| Switch to workspace 11-20 | `Super+Shift+1-0` |
| Move container to workspace 1-10 | `Super+Ctrl+1-0` |
| Move container to workspace 11-20 | `Super+Ctrl+Shift+1-0` |
| Open project sessionizer | `Super+P` (see `packages/linux/bin-linux/.local/bin/zellij-sessionizer`) |
| Cycle Obsidian scratchpad | `Super+N` |

### AeroSpace (macOS)

Mirrors the sway shape with `Alt` replacing `Super`. From `packages/macos/aerospace/.config/aerospace/aerospace.toml`:

| Action | Keys |
|--------|------|
| Focus left/down/up/right | `Cmd+Alt+h/j/k/l` |
| Move container left/down/up/right | `Alt+Ctrl+h/j/k/l` |
| Move workspace to prev/next monitor | `Alt+Shift+h` / `Alt+Shift+l` |
| Switch to workspace 1-10 | `Alt+1-0` |
| Switch to workspace 11-20 | `Alt+Shift+1-0` |
| Move container to workspace 1-10 | `Alt+Ctrl+1-0` |
| Move container to workspace 11-20 | `Alt+Ctrl+Shift+1-0` |
| Close window | `Alt+Shift+q` |
| Reload config | `Alt+Shift+c` |
| Fullscreen | `Alt+f` |
| Flatten + balance workspace tree | `Alt+Shift+r` |

Launcher and terminal-spawn binds are deliberately unset on Mac — use Spotlight (`Cmd+Space`) or Raycast until day-1 experience tells us what to bind.

### SketchyBar (macOS)

Per-monitor workspace pills, mirroring waybar's `sway/workspaces` with `all-outputs=false`. Each monitor's bar shows only its own non-empty workspaces; the focused workspace gets the green highlight. Config at `packages/macos/sketchybar/.config/sketchybar/`.

| Action | How |
|--------|-----|
| Click a pill | Switches to that workspace (calls `aerospace workspace N`) |
| Reload after editing config | `brew services restart sketchybar` or `sketchybar --reload` |
| Debug (see plugin stderr) | `pkill sketchybar && sketchybar` (foreground) |
| Inspect runtime state | `sketchybar --query bar` / `sketchybar --query space.1.1` |

Pills update on every `aerospace_workspace_change` (wired via `exec-on-workspace-change` in `aerospace.toml`) and on monitor hotplug (`display_change`).

### Zellij

| Action | Keys / Command |
|--------|----------------|
| Open project sessionizer | `Super+P` (Linux only) |
| Start with dev layout manually | `zellij -l dev` |
| Move focus left/down/up/right | `Alt+h/j/k/l` |
| Previous/next tab | `Alt+[` / `Alt+]` |

Pane mode (`Ctrl+p`), then:

| Action | Key |
|--------|-----|
| New pane (auto direction) | `n` |
| Split down (horizontal) | `d` |
| Split right (vertical) | `r` |
| Close pane | `x` |

### Debugging phantom windows

A workspace shows tiling slots for windows you can't see (app quit but the window record lingered, a hidden/minimized window AeroSpace still tracks, etc.). List what the WM thinks is there, then kill by ID.

**AeroSpace (macOS):**

```sh
aerospace list-windows --workspace focused          # current workspace
aerospace list-windows --workspace 3                # specific workspace
aerospace list-windows --all                        # everything, all workspaces
aerospace list-windows --all --format '%{window-id} %{app-name} %{window-title}'

aerospace close --window-id <ID>                    # ask the app to close it
kill <PID>                                          # if close is ignored; PID via `aerospace list-windows --format '%{window-id} %{app-pid} %{app-name}'`
```

If a window has no title and the app-name is unfamiliar, it's almost always the phantom. `aerospace reload-config` does *not* clear them — you have to close or kill.

**Sway (Linux):**

```sh
swaymsg -t get_tree | jq '.. | select(.type? == "con") | {id, name, app_id, pid, visible}'
swaymsg -t get_workspaces                            # workspace summary
swaymsg '[con_id=<ID>] kill'                         # kill the container
```

For a focused-workspace-only view: `swaymsg -t get_tree | jq '.. | select(.type? == "workspace" and .focused == true)'`.

### Neovim

| Action | Keys |
|--------|------|
| Toggle hidden files in explorer | `Shift+H` |
| Open file | `:e path/to/file` |
| Vertical split | `:vs` or `:vs path/to/file` |
| Navigate splits | `Ctrl+w h/j/k/l` |
| Fuzzy find buffers | `<leader>fb` |
| Next/prev buffer | `Tab` / `Shift+Tab` |
| Copy file path | `<leader>cp` |
| Copy file directory | `<leader>cd` |

## 15. Remote profile

A second axis on top of the `{common,linux,macos}` package buckets: **profile**. Three v1 profiles — `linux-workstation` (Fedora desktop with sway/waybar/etc.), `linux-remote` (headless dev essentials only), `mac-workstation` (Mac with AeroSpace/SketchyBar). Profile selects which buckets to stow and which `install-deps-*` recipe to run. The OS axis stays unchanged.

### Invocation

Three equivalent forms:

```sh
./bootstrap.sh                                  # defaults DOTFILES_PROFILE=linux-remote, then exec's just setup
just setup profile=linux-remote                 # explicit arg
DOTFILES_PROFILE=linux-remote just setup        # env var
```

`bootstrap.sh` is the one-line entrypoint for fresh remote envs (Ona, Codespaces, plain SSH boxes). It only sets `DOTFILES_PROFILE` if unset — it does not clobber a pre-existing value — then exec's `just setup`. It does not auto-install `just`; if `just` is missing it fails loud with the canonical install command (`https://just.systems/install.sh`).

Before invoking `just setup`, `bootstrap.sh` runs `check-conflicts` and **auto-backs-up** any pre-existing files that would collide with stow (e.g., the `~/.bashrc` / `~/.zshenv` that base images often ship). Originals move to `*.pre-stow.<timestamp>.bak`; nothing is deleted. This makes the unattended path on remote dev envs work out of the box. If you need to disable this, run `just setup` directly instead of `./bootstrap.sh`.

### Remote shell default

`linux-remote` tries to set the user's login shell to zsh with `sudo usermod --shell "$(command -v zsh)" "$USER"` when the remote container allows passwordless sudo. Remote dev images sometimes keep `/etc/passwd` or login-shell changes outside user control, so the profile also stows a small `~/.bashrc.d/90-exec-zsh` fallback shim. For interactive TTY bash sessions, it exports `SHELL` to the resolved zsh path and `exec`s zsh. It also stows a remote-only `~/.bash_profile` that sources `~/.profile` first, then `~/.bashrc`, so login bash sessions reach the same shim. Noninteractive `bash -c` commands are left alone.

Use this when you need to stay in bash:

```sh
DOTFILES_KEEP_BASH=1 bash
```

Skip the login-shell mutation but still install the fallback shim with:

```sh
DOTFILES_SKIP_LOGIN_SHELL=1 just setup profile=linux-remote
```

### AI dotfiles

`linux-remote` also runs `just setup-ai-dotfiles` after the base CLI setup. It clones or updates the private AI config repo, then runs that repo's `just link` so home-level AI instructions, Claude config, and cross-harness skills are sourced from Git instead of copied by hand.

Defaults:

```sh
AI_DOTFILES_REPO=git@github.com:SIRHAMY/ai-dotfiles.git
AI_DOTFILES_DIR=$HOME/Code/ai-dotfiles
```

Re-running `just setup` (or `just setup-ai-dotfiles`) is the reconcile path on an existing machine: it re-runs ai-dotfiles' `just link`, which is idempotent and picks up any managed paths added there since this host was last linked. A machine linked before a new hook/command/config was added to ai-dotfiles won't have it — and the drift is silent (a wired hook just no-ops) — until setup runs again.

If the checkout exists and is clean, setup runs `git pull --ff-only`. If it has local changes, setup skips the pull and links the current checkout so local work is not overwritten. Useful overrides:

```sh
AI_DOTFILES_SKIP_UPDATE=1      # link current checkout without pulling
DOTFILES_SKIP_AI_DOTFILES=1    # skip AI dotfiles entirely
```

### EFS runtime state

`linux-remote` also runs `just setup-efs-state`. This is optional: if `EFS_MOUNT_POINT` is unset, missing, or not mounted, setup keeps using local runtime state and continues.

There are two supported modes. Pick one via the `EFS_MOUNT_POINT` Ona secret.

#### Mode A — share-everything (recommended)

```sh
EFS_MOUNT_POINT=/home/vscode
```

Ona mounts the EFS volume directly over `$HOME` and auto-syncs the prebuilt home into it on first boot (up to ~30 minutes). Everything in `$HOME` is then shared across all your Ona instances by default — shell history, dotfiles state, agent sessions, gitconfig, anything new tools drop under `$HOME` going forward.

`setup-efs-state` then creates exclude symlinks from `$HOME/<path>` to `/prebuilt-home/<path>` for paths that must NOT live on EFS. The exclude list:

```text
# Build/dependency caches — large, rebuildable, sometimes per-arch.
~/.cache, ~/.npm, ~/.yarn, ~/.pnpm-store, ~/.cargo, ~/.rustup, ~/go,
~/.gradle, ~/.m2, ~/.local/share/uv, ~/.local/share/virtualenvs

# IDE / language-server state — machine-specific, large.
~/.vscode-server, ~/.vscode-server-insiders, ~/.cursor-server

# Local daemon state — tied to the local Docker daemon.
~/.docker

# Long-lived static credentials — kept machine-local per security policy.
~/.aws, ~/.ssh, ~/.kube, ~/.config/gcloud

# Dotfiles checkouts — prebuilt clone wins over any EFS snapshot.
$DOTFILES_DIR (auto-detected), $AI_DOTFILES_DIR
```

Override the list with `DOTFILES_EFS_EXCLUDES=path1,path2,...` (replaces defaults) or extend it with `DOTFILES_EFS_EXTRA_EXCLUDES=path3,path4` (appends). Paths are relative to `$HOME`.

Mode A requires `/prebuilt-home` to exist (Ona provides this). On non-Ona hosts the script logs and exits.

#### Mode B — selective (more conservative)

```sh
EFS_MOUNT_POINT=/home/vscode/.efs
```

EFS is mounted at a subdirectory, not over `$HOME`. Only the paths listed below are symlinked into EFS; nothing else is shared.

Runtime state — sessions, history, agent memory:

```text
~/.claude.json       -> $EFS_MOUNT_POINT/state/claude/.claude.json
~/.claude/projects  -> $EFS_MOUNT_POINT/state/claude/projects
~/.claude/todos     -> $EFS_MOUNT_POINT/state/claude/todos
~/.codex/config.toml -> $EFS_MOUNT_POINT/state/codex/config.toml
~/.codex/history.jsonl -> $EFS_MOUNT_POINT/state/codex/history.jsonl
~/.codex/memories   -> $EFS_MOUNT_POINT/state/codex/memories
~/.codex/rules      -> $EFS_MOUNT_POINT/state/codex/rules
~/.codex/sessions   -> $EFS_MOUNT_POINT/state/codex/sessions
~/.zsh_history      -> $EFS_MOUNT_POINT/state/shell/zsh_history
```

Revocable per-user auth tokens — avoids re-login on every new instance:

```text
~/.claude/.credentials.json -> $EFS_MOUNT_POINT/state/claude/.credentials.json
~/.codex/auth.json          -> $EFS_MOUNT_POINT/state/codex/auth.json
~/.config/gh                -> $EFS_MOUNT_POINT/state/gh
~/.config/acli              -> $EFS_MOUNT_POINT/state/acli
```

Only enable the auth-token block when the EFS volume is dedicated to a single user. Long-lived static credentials (cloud access keys, service-account JSON, SSH private keys, kube configs that reach production) stay machine-local regardless.

Agent config that belongs in Git stays managed by `ai-dotfiles` (`~/.claude/commands`, `~/.claude/skills`, `~/.claude/settings.json`, `~/.claude/statusline.sh`, `~/.agents/skills`). EFS is only for runtime state such as `/vim` mode, old Claude sessions, todos, agent histories, and shell history.

Codex follows the same rule: config, rules, memories, prompt history, and old sessions are shared; caches, logs, plugin caches, and SQLite runtime databases stay local to each machine. Other agents such as OpenCode should be added here only after confirming their state paths and separating source-controlled config from runtime state.

#### EFS guardrails (both modes)

- Do not put source-controlled config in EFS. Skills, commands, settings, and top-level agent instructions come from `ai-dotfiles`. In Mode A, the dotfiles checkouts are auto-excluded for the same reason.
- Keep long-lived static credentials out of EFS — cloud access keys, service-account JSON, SSH private keys, and kube configs that reach production stay machine-local or in Ona secrets. Revocable per-user OAuth tokens for dev tooling may be linked, but only when the EFS volume is dedicated to a single user.
- Do not share dependency caches or runtime databases unless there is a proven need. Keep package caches, plugin caches, logs, `node_modules`, virtualenvs, and SQLite/WAL files local. Mode A auto-excludes the common offenders.
- Add new agents conservatively: identify their config paths, runtime-state paths, auth paths, and cache paths first, then decide whether the state is worth preserving — and in Mode A, whether anything needs an exclude.

#### Useful overrides

```sh
DOTFILES_EFS_STATE_ROOT=/some/efs/path/state         # Mode B: override default state path
DOTFILES_EFS_EXCLUDES=path1,path2                    # Mode A: replace default exclude list
DOTFILES_EFS_EXTRA_EXCLUDES=path3,path4              # Mode A: append to default exclude list
DOTFILES_PREBUILT_HOME=/some/other/prebuilt-home     # Mode A: override exclude target root
DOTFILES_SKIP_EFS_STATE=1                            # skip the script entirely
DOTFILES_EFS_ALLOW_UNMOUNTED=1                       # local testing only
```

#### Rollback

Mode B — undo a selective link by removing the symlink and moving the stored state back from EFS:

```sh
rm ~/.claude/projects
mv "$EFS_MOUNT_POINT/state/claude/projects" ~/.claude/projects
```

Mode A — undo an exclude by removing the symlink to `/prebuilt-home/<path>` and either restoring a backup or letting the path repopulate from prebuilt:

```sh
rm ~/.cache
# either: cp -a /prebuilt-home/.cache ~/.cache
# or: restore the matching ~/.cache.pre-efs.<timestamp>.bak created at first run
```

If setup backed up a conflicting path during a mode switch, restore from the timestamped `.pre-efs.<timestamp>.bak`.

To disable all future EFS linking on a machine, unset `EFS_MOUNT_POINT` or run setup with:

```sh
DOTFILES_SKIP_EFS_STATE=1 just setup profile=linux-remote
```

#### Switching from Mode B to Mode A

Flipping `EFS_MOUNT_POINT` from `/home/vscode/.efs` to `/home/vscode` reuses the same EFS volume but remounts it over `$HOME`. The previously selectively-linked state (Claude projects, codex sessions, zsh history, etc.) will appear under `~/state/...` on the new mount instead of at its natural home-dir location. One-time migration after first boot on the new mount:

```sh
# Move runtime state into natural home-dir locations.
for sub in claude codex shell gh acli; do
  [ -d ~/state/$sub ] && cp -an ~/state/$sub/. ~/  # adjust per layout
done
# Or, more conservatively, move specific paths:
mv ~/state/claude/projects ~/.claude/projects
mv ~/state/shell/zsh_history ~/.zsh_history
# ...etc, then `rm -rf ~/state` once verified.
```

After migration, `setup-efs-state` running in Mode A will detect the natural paths and leave them in place.

### Ona helpers

The zsh config ships two laptop-side helpers for Ona environments:

```sh
ona login                         # one-time, or whenever the CLI token expires
ona-ssh                           # pick a running environment, then SSH in
ona-up <repo-url|project-id>       # create an environment, then run ona-ssh
```

`ona-ssh` lists running environments with `ona environment list --running-only --format json`, shows name/branch/age/activity/id in `fzf`, then connects with `ona environment ssh`. By default it attaches to a remote zellij session named `main`, creating it with the `dev` layout when needed:

```sh
zellij -l dev attach main -c
```

`ona-up` creates uniquely named environments by default, using `<project>-YYYYMMDDTHHMMSS` so multiple environments do not all appear as `main`. The project segment is derived from the repo URL or project ID. Pass `--name` to keep full manual control:

```sh
ona-up https://github.com/owner/dotfiles.git       # dotfiles-20260429T153042
ona-up <project-id> --name investigation
```

For every mode, `ona-ssh` exports remote `SHELL` to zsh when zsh exists before launching the shell or multiplexer, so newly-created panes follow the zsh default even if Ona's login shell is still bash. It also forces remote `TERM=xterm-256color` and `COLORTERM=truecolor`. This avoids Ghostty's local `xterm-ghostty` terminfo leaking into remote boxes that do not know that terminal entry.

Plain Ghostty-over-SSH sessions get the same terminal fallback from the Linux zsh config: if `TERM=xterm-ghostty` reaches a remote without the Ghostty terminfo entry, zsh downgrades `TERM` to `xterm-256color` and keeps `COLORTERM=truecolor`.

Useful overrides:

```sh
ona-ssh --plain                   # SSH only, no remote multiplexer
ona-ssh <environment-id>           # skip the picker
ONA_SSH_SESSION=dotfiles ona-ssh   # use a different remote zellij session
ONA_SSH_LAYOUT=compact ona-ssh     # use a different layout for new sessions
ONA_SSH_TERM=xterm-ghostty ona-ssh # opt back into local TERM if remote terminfo supports it
```

### Resolution precedence

`profile=` arg > `$DOTFILES_PROFILE` > **fail loud** (no OS default).

`just setup` with no arg and no env var exits 1 with the valid profiles for the current OS. Workstation users either pass `profile=linux-workstation` (or `mac-workstation`) explicitly each time, or `export DOTFILES_PROFILE=linux-workstation` once in `~/.zprofile`. `setup`'s first line of output echoes the resolved profile and where it came from:

```
Setup: profile=linux-remote (resolved from $DOTFILES_PROFILE)
Setup: profile=linux-workstation (resolved from arg)
```

So an env-var leak is visible immediately, not silent.

### What `linux-remote` includes

Stowed: `zsh` (+ plugins via OS package manager), `tmux`, `zellij`, `nvim` (+ LazyVim), `yazi`, `git`, `bash`, `bin`, plus the `zsh-linux` conf.d bucket (cargo/opencode PATH guards, plugin source paths — both valid on Debian/Ubuntu and Fedora) and the `bash-remote` shim that hands interactive bash TTY sessions to zsh.

### What `linux-remote` skips

Stow buckets: `ghostty`, `sway`, `swaylock`, `waybar`, `mako`, `wofi`, `fontconfig`, `environment.d`, `bin-linux`. Recipes: no GRUB edits, no NVIDIA detection, no flatpak/Obsidian install, no `setup-sway-session`. The remote `$HOME` never sees those symlinks; `linux-remote` issues exactly one `sudo` invocation — the package-manager install.

### Supported package managers (remote)

`install-deps-linux-remote` detects `apt-get` and `dnf`. Anything else (apk, pacman, zypper, …) fails with:

```
Unsupported package manager. linux-remote v1 supports apt and dnf only. PRs welcome.
```

The package manager handles baseline CLI dependencies. Neovim is installed from the official release tarball into `~/.local/opt` with a `~/.local/bin/nvim` symlink so LazyVim is not pinned to stale distro packages.

### Recovering from a leaked `DOTFILES_PROFILE`

If a synced shell rc exports `DOTFILES_PROFILE=linux-remote` and you're on a workstation, `just setup` will silently default to remote — except that `setup`'s first-line banner makes it visible. To override for one invocation, pass `profile=` (arg wins over env). To clear it for the session:

```sh
unset DOTFILES_PROFILE
just setup profile=linux-workstation
```

Confirm via the banner that the resolved profile and source match what you expect.

### Migrating between profiles on the same host

Switching a host from `linux-workstation` to `linux-remote` (or back) on the same checkout: unstow under the old profile first, then setup under the new one. Avoids stale symlinks from the prior profile (`~/.config/sway/`, `~/.config/waybar/`, etc.) blocking the new install:

```sh
just unstow-all profile=linux-workstation
just setup profile=linux-remote
```

`check-conflicts` walks only the resolved profile's package list, so it won't false-fail on workstation-only paths under a remote install — but stale symlinks left over from the prior profile stay on disk until you unstow them. The migration above is the clean path.

## 16. OpenCode Web service (Linux)

Both Linux profiles stow and provision one `systemd --user` service that runs `opencode serve` on `127.0.0.1:4096`. The `oc` command starts or reuses that service, waits for its authenticated health endpoint, and attaches a TUI to the current working directory. OpenCode Web and `oc` therefore use the same backend and can see the same sessions. `linux-workstation` also publishes that loopback service privately through Tailscale Serve; `linux-remote` stays local-only and neither requires nor invokes Tailscale.

### Prerequisites and security

Install these before using `oc`:

- `just setup` installs and verifies OpenCode v1.18.3 at `~/.opencode/bin/opencode` with its pinned official installer. It does not use Homebrew because that executable path conflicts with the service contract.
- `curl` and a working `systemd --user` manager are required by `oc` and setup on both Linux profiles.
- `linux-workstation` additionally requires a running, connected Tailscale client. `linux-remote` does not require Tailscale or a tailnet.
- `jq` is required only when setup must migrate an existing `~/.config/opencode/config.json`.

The service reads its Basic-auth password from the local-only `~/.config/opencode/server.env`. Setup creates it if absent, requires a regular user-owned file, and sets mode `0600`; it never prints the password. Do not add it to Git, shell history, terminal output, or a shared filesystem.

The public lower-precedence config disables OpenCode sharing and accepts all OpenCode permissions with `{"*": "allow"}`. Loopback binding, Basic auth, Tailscale Serve, and a restricted tailnet policy limit network reachability, but they do not make untrusted agents safe: an automatically permitted agent can run shell commands as this Unix user and can access inherited credentials. Use only trusted agents and providers.

### Install and make persistent

Run setup for the intended Linux profile. It stows the package, reloads the user manager, enables lingering, and enables and starts the newly stowed unit:

```sh
just setup profile=linux-workstation
# or: just setup profile=linux-remote

```

Lingering keeps the user manager and enabled service alive after logout. Re-run `just setup profile=linux-workstation` or `linux-remote` to reconcile the package, reload the user manager, and restart the service on later updates.

If `~/.config/opencode/config.json` already exists as a regular file, setup validates it as JSON and creates a timestamped `.pre-opencode-web.<timestamp>.bak` backup. It moves that config to the higher-precedence `opencode.json` when no such file exists; otherwise it deep-merges the old `config.json` below the existing `opencode.json`, backing up both inputs. It never changes `opencode.jsonc`. Setup warns, without printing values, when either higher-precedence file defines `permission` or `share`, because that policy overrides the stowed defaults. Fix an invalid config or an unexpected higher-precedence policy before continuing.

### Private tailnet access

`just setup profile=linux-workstation` validates Tailscale and creates the persistent Tailscale Serve proxy. It terminates tailnet HTTPS and forwards only to the loopback OpenCode server; do not use Tailscale Funnel. `linux-remote` never creates this route.

Inspect the workstation route with:

```sh
tailscale serve status
```

The first command may prompt to enable HTTPS for the tailnet. The `--bg` configuration persists in Tailscale; `tailscale serve status` prints the private `https://<device>.<tailnet>.ts.net` URL. See [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve) for configuration and reset behavior.

Restrict that HTTPS listener to the intended phone or other device in the tailnet policy. Tailscale policies are allow-only: remove or narrow any broader rule that already grants the host access. The following is an illustrative [policy fragment](https://tailscale.com/docs/reference/syntax/policy-file), not a copy-paste policy: replace both addresses with the server and intended-client Tailscale IPs, merge it with the existing HuJSON policy, and keep only the access the device needs.

```jsonc
"hosts": {
  "opencode-server": "100.x.y.z",
},
"acls": [
  {
    "action": "accept",
    "src": ["100.a.b.c"],
    "proto": "tcp",
    "dst": ["opencode-server:443"],
  },
],
```

The ACL controls tailnet reachability to Serve's HTTPS listener, normally port `443`, rather than the loopback-only backend port `4096`. Verify the intended device can load the Serve URL and that no unwanted device is permitted by another policy rule.

### Normal worktree use

From the worktree where the agent should operate, run:

```sh
cd ~/Code/project
oc
```

`oc` validates the prerequisites and private environment, starts `opencode-web.service` idempotently, then attaches OpenCode with that worktree as its directory. Leaving the TUI detaches the client; it does not stop the shared server. Open the private Serve URL on an allowed tailnet device to monitor or continue the same server sessions in Web. Authenticate locally with the private server credential without displaying or copying it into notes.

### Recovery, archives, and logs

Use these commands before changing configuration:

```sh
systemctl --user status opencode-web.service
journalctl --user -u opencode-web.service -e
journalctl --user -u opencode-web.service -f
systemctl --user restart opencode-web.service
tailscale serve status
```

A service restart does not intentionally discard OpenCode history. Run `oc` from the worktree and select the existing session in the TUI or Web UI. For a portable archive, use OpenCode's session export/import commands outside the public dotfiles checkout; `--sanitize` redacts sensitive transcript and file data, but review the archive before sharing it.

```sh
mkdir -p ~/Documents/opencode-archives
~/.opencode/bin/opencode session list
~/.opencode/bin/opencode export <session-id> --sanitize > ~/Documents/opencode-archives/<session-id>.json
~/.opencode/bin/opencode import ~/Documents/opencode-archives/<session-id>.json
```

### Manual smoke procedure and result

Run this on a Linux host after completing the setup above. It is the acceptance procedure for the remaining WRK-004 e2e checklist; documenting it is not evidence that the real-host smoke has passed.

**2026-07-17 current-host result: partial.** Disposable-home checks verified the then-current `oc` failures for missing OpenCode, `curl`, Tailscale, and an insecure private environment file. They also verified config migration to `opencode.json`, deep-merge precedence, timestamped backups, and unchanged `opencode.jsonc`. Narrow provisioning created the private environment file, stowed the package, enabled linger, and enabled the unit. After removing an existing manual server that held port `4096`, the managed unit started successfully; it remained active after restart and authenticated `GET /global/health` passed. Tailscale Serve now publishes the private browser route, and the user confirmed it loads from a phone. Repeated interactive attach, shared Web/TUI session visibility, post-logout availability, and ACL exclusion remain unverified.

1. **Prerequisites:** Confirm `oc` fails before starting a service when OpenCode, `curl`, the private environment file, or the user manager is unavailable. On `linux-workstation`, also confirm setup fails when Tailscale is unavailable or disconnected; `linux-remote` must not require it. For example, capture the installed helper path, then run it with an empty temporary home to exercise the missing-OpenCode failure and with an empty `PATH` to exercise the missing-`curl` failure:

   ```sh
   oc_path="$HOME/.local/bin/oc"
   temporary_home="$(mktemp -d)"
   HOME="$temporary_home" /bin/bash "$oc_path"
   PATH=/nonexistent /bin/bash "$oc_path"
   ```

   Each invocation must exit nonzero with the named prerequisite error. Exercise workstation-only unavailable or disconnected Tailscale, an insecure or missing `server.env`, and an inaccessible user manager in an isolated test account rather than weakening the working host.
2. **Migration:** On a test account with a valid pre-existing `~/.config/opencode/config.json`, run `just setup profile=linux-remote`. Confirm a timestamped backup exists, the original settings are in `opencode.json` or preserved by the merge, `config.json` is stowed, and any higher-precedence `permission` or `share` warning is reviewed. Repeat with an existing `opencode.json` and verify its values win; verify `opencode.jsonc` remains unchanged.
3. **Attach and shared visibility:** In a worktree, run `oc`, create or resume a recognizable session, exit, and run `oc` again. Confirm the unit remains active and both attachments authenticate to the same server. On `linux-workstation`, load the private Serve URL on the allowed phone or tailnet device and confirm the same session is visible in Web; `linux-remote` remains local-only.
4. **Persistence:** Run `systemctl --user restart opencode-web.service`, then reconnect with `oc` and Web. Confirm the prior session history remains. On `linux-workstation`, log out of the Linux host and confirm the Serve URL remains available from the allowed phone; then log back in and inspect the status and journal commands above.
5. **Access boundary:** Confirm the intended device reaches the HTTPS URL and an excluded tailnet device cannot. Record the result only after the real-host run; do not mark the e2e checklist complete from this document alone.
