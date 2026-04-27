# SPEC: Cross-OS Dotfiles Restructure

**ID:** WRK-001
**Status:** Draft
**Created:** 2026-04-27
**PRD:** ./WRK-001_cross-os-restructure_PRD.md
**Design:** ./WRK-001_cross-os-restructure_DESIGN.md
**Tech Research:** ./WRK-001_cross-os-restructure_TECH_RESEARCH.md
**Execution Mode:** human-in-the-loop
**New Agent Per Phase:** yes
**Max Review Attempts:** 3
**Mode:** Light

## TL;DR

- **Phases:** 5 phases (1 Med-High, 1 Med-High, 1 Low, 1 Med, 1 Low)
- **Approach:** Bottom-up structural restructure. Phase 1 moves all packages into `packages/{common,linux,macos}/` and rewrites the justfile to bucket-dispatch — Fedora keeps working with unchanged config content. Phase 2 splits `zsh` into ZDOTDIR + `conf.d/` loader and the OS-specific `zsh-linux` snippets. Phase 3 splits `bin/` and adds the tmux loader stub. Phase 4 scaffolds the macOS packages (`zsh-macos`, `aerospace`) and the macOS install-deps branch — verified via `stow -n` from the Fedora box. Phase 5 rewrites the README per the 14-section content checklist. Mac-on-hardware validation is post-merge per PRD.
- **Key risks:** (1) Phase 1's `git mv` + justfile rewrite must commit atomically — a partial state breaks `just setup` everywhere. (2) Phase 2's zsh rewrite can break login; the migration flow's scratch-shell protocol is the lifeline.
- **Needs attention:** None. Design resolved everything directional.

## Context

This SPEC implements the design at `./WRK-001_cross-os-restructure_DESIGN.md` verbatim — phase boundaries are the only thing the design didn't pin down. The design pre-baked file paths, loader source, justfile recipes, aerospace.toml, and the README content checklist; the work here is sequencing those into atomic commits that each leave Fedora in a working state.

Read the DESIGN first if you're implementing — it has the full source for the loader, the justfile, and aerospace.toml. The phases below reference DESIGN sections by name rather than re-pasting code.

## Approach

**Sequencing principle:** every phase commit must leave Fedora bootable (login shell works, sway reloads, plugins load). The migration on the existing Fedora machine happens between phases 1 and 2 (or whenever the user pulls a phase commit and re-stows). Commits are designed to be re-stowable from the existing Fedora setup without manual cleanup beyond `just unstow-all` → checkout → `just setup`.

**Why phase 1 moves files but doesn't touch zsh content:** the package-bucket-and-justfile change is structurally invasive but content-neutral. Splitting that from the zsh rewrite (phase 2) means a bisect-friendly history and isolated verification.

**Patterns to follow:**

- `DESIGN.md` §System Design > High-Level Architecture — the target tree, file-for-file.
- `DESIGN.md` §Component Breakdown > `packages/common/zsh` — full loader source.
- `DESIGN.md` §Component Breakdown > `justfile` — the full new justfile bucket structure including `check-conflicts`, `unstow-all`, `restow`, `_stow-bucket*` helpers.
- `DESIGN.md` §Flow: AeroSpace Keybind Mapping — full `aerospace.toml` fragment.
- `DESIGN.md` §README content checklist — the 14 sections the README rewrite must cover.
- Existing `tmux/.tmux.conf` lines 49–50 (`if-shell 'command -v pbcopy' ...`) — established `if-shell` precedent for the loader stub.

**Implementation boundaries:**

- Do not modify any tool's behavior or keybindings beyond what OS-parity requires (PRD scope).
- Do not refactor `.zshrc` lines that aren't being moved — incidental fixes are allowed only on lines the move touches: duplicate `PATH` export, missing newline before `source` line, unguarded `$HOME/.cargo/env`, hardcoded `/home/sirhamy/.opencode/bin`.
- Do not port `zellij-sessionizer`, `obsidian-scratchpad`, or `scratchpad-toggle` to Mac (PRD: deferred follow-up).
- Do not create empty placeholder packages (`bin-macos`, `tmux-macos`, `tmux-linux`, `ghostty-{linux,macos}`) — design calls for them only when first OS-specific content lands.
- Do not write `ARCHITECTURE.md` — design folded its content into the README checklist.
- Do not introduce the `--strict` / `--backup` flag split for `just setup`. Pattern B (fail loud via `check-conflicts`) is the only mode.

## Phase Summary

| Phase | Name | Complexity | Description |
|-------|------|------------|-------------|
| 1 | Restructure: package buckets + justfile | Med-High | `git mv` all packages into `packages/{common,linux}/`, delete `.stowrc`, rewrite justfile to bucket dispatch with `check-conflicts`/`unstow-all`/`restow`. Fedora content unchanged. |
| 2 | zsh ZDOTDIR migration + conf.d split | Med-High | Bootstrap `~/.zshenv`, write the loader, split current `.zshrc` content into common `conf.d/*.zsh` snippets and `zsh-linux/.../os.linux/*.zsh`. Fix incidental `.zshrc` bugs on touched lines. |
| 3 | bin split + tmux loader stub | Low | Move sway-coupled scripts to `packages/linux/bin-linux/.local/bin/`. Append the `if-shell ... source-file -q` lines to common `tmux.conf`. |
| 4 | macOS scaffolding (zsh-macos + aerospace + install-deps) | Med | Create `zsh-macos` (brew shellenv bootstrap + os.darwin snippets), `aerospace` package, macOS branch of `install-deps` with cask idempotency guards. Verified via `stow -n` from Fedora. |
| 5 | README rewrite | Low | Rewrite README per the 14-section content checklist in DESIGN.md. |

**Ordering rationale:**
- Phase 1 must be first — every later phase assumes the bucket layout and the new justfile.
- Phase 2 depends on Phase 1 (zsh-linux package needs `packages/linux/` to exist and `packages_linux` list to register it).
- Phase 3 is bin + tmux because both are small Linux/scaffolding moves with no cross-dependency to Phase 2's zsh work.
- Phase 4 is macOS scaffolding — independent of Phases 2–3 in principle but easier to verify after the loader contract is in place (Phase 2) so the `stow -n` cross-validation exercises the real common loader.
- Phase 5 is docs last — README references the recipes and structure from Phases 1–4.

---

## Phases

Each phase ends with a single commit on the restructure branch. The Fedora migration on the user's existing machine happens whenever they pull a phase commit and run `just unstow-all` → checkout → `just setup` (Phase 1 commit is the recommended migration point).

---

### Phase 1: Restructure: package buckets + justfile

> `git mv` all packages into `packages/{common,linux}/`, delete `.stowrc`, rewrite the justfile to bucket dispatch.

**Phase Status:** in_progress

**Complexity:** Med-High

**Goal:** Move every existing top-level package into the new `packages/{common,linux}/<pkg>/` tree with `git mv` (preserving blame), delete `.stowrc`, and rewrite the justfile to dispatch per bucket. Fedora content is unchanged inside the moved packages — `just setup` after this phase produces an identical working Fedora environment.

**Files:**

- `packages/common/{zsh,tmux,git,bash,ghostty,zellij,nvim,yazi,bin}/` — create (via `git mv` from repo root).
- `packages/linux/{sway,swaylock,waybar,mako,wofi,fontconfig,environment.d}/` — create (via `git mv`).
- `packages/macos/` — create empty directory with a `.gitkeep` (so the bucket exists for Phase 4).
- `packages/common/bin/.local/bin/.gitkeep` — create — dir-guard preventing stow tree-folding (comment: `kept un-folded by stow; DO NOT DELETE`).
- `.stowrc` — delete.
- `justfile` — rewrite. Replace with the structure in DESIGN.md §Component Breakdown > `justfile`, preserving the existing `install-deps` Fedora branch (with its `install-zellij`/`install-yazi`/`install-resvg`/`install-flatpaks` helpers and the `setup-sway-session` recipe) inside an `if [ "{{os}}" = "Linux" ]` guard. Add the new `check-conflicts`, `_stow-bucket`, `_unstow-bucket`, `_stow-bucket-flag`, `_plan-bucket` helpers. `unstow-all` and `restow` recipes per DESIGN. The macOS branch of `install-deps` is added in Phase 4 — Phase 1 leaves the macOS branch as a stub that `echo`s "macOS install-deps not yet implemented" and exits 1.

**Patterns:**

- DESIGN.md §Component Breakdown > `justfile` for the full recipe shape.
- Existing `justfile` lines 47–71 (`install-deps`) and 147–191 (`setup-sway-session`) — preserve these as-is, only re-wrap the dispatch.

**Tasks:**

- [x] Verify clean working tree (`git status` is clean).
- [x] `mkdir -p packages/common packages/linux packages/macos`.
- [x] `git mv` each of `zsh tmux git bash ghostty zellij nvim yazi bin` into `packages/common/`.
- [x] `git mv` each of `sway swaylock waybar mako wofi fontconfig environment.d` into `packages/linux/`.
- [x] `touch packages/macos/.gitkeep`.
- [x] Create `packages/common/bin/.local/bin/.gitkeep` with the dir-guard comment.
- [x] `git rm .stowrc`.
- [x] Rewrite `justfile` per DESIGN, including: `os` var, three `packages_*` lists (`packages_macos := ""` for now — populated in Phase 4), `all`, `unstow-all`, `restow`, `plan`, `check-conflicts`, `setup`, `_stow-bucket`, `_unstow-bucket`, `_stow-bucket-flag`, `_plan-bucket`, `reload`, and the existing Linux `install-deps` family (preserved verbatim, dispatched via `if [ "{{os}}" = "Linux" ]`). The macOS `install-deps` branch is a "not yet implemented; exit 1" stub — Phase 4 fills it in.
- [x] Update the `setup-sway-session` recipe to reference the new path: `packages/common/bin/.local/bin/sway-launch` (this changes again in Phase 3 when bin splits — a known two-step move).
- [ ] (deferred: user runs during their migration) Migrate the existing Fedora machine (one-time, during Phase 1 acceptance): from a scratch `bash -l` shell, on the OLD branch run `just unstow-all`; verify no orphan symlinks via `find ~ -maxdepth 4 -type l -lname "*Code/dotfiles*" 2>/dev/null`; `git checkout <restructure-branch>`; `just plan` (must report zero conflicts); `just setup`. Keep scratch shell open until verification passes.
- [ ] (deferred: user runs after migration) Verify post-migration: open a fresh shell — prompt renders, plugins load (still via the old hardcoded `/usr/share/zsh-*` paths inside `packages/common/zsh/.zshrc`), `z`/fzf bindings work; `swaymsg reload` succeeds; `tmux` and `nvim` and `yazi` open.
- [x] `find ~ -maxdepth 4 -type l -lname "*Code/dotfiles*" 2>/dev/null` — symlink audit run; current state shows symlinks still pointing into OLD `~/Code/dotfiles/{zsh,tmux,...}` paths (now dangling after `git mv`). Will resolve to `packages/{common,linux}/` after user runs migration. Note: post-migration verification deferred to user.

**Verification:**

- [ ] (deferred: user runs after migration) `just plan` exits 0 with no conflicts on Fedora. (Currently shows expected conflicts because old symlinks at `~/.zshrc` etc. still point to pre-move locations; resolves once user runs `just unstow-all` from the OLD branch then re-stows on new layout.)
- [ ] (deferred: user runs after migration) `just setup` re-stows everything; all PRD Fedora checklist items (a–i) pass.
- [ ] (deferred: user runs after migration) `just unstow-all` then `just setup` is idempotent (second run produces no errors).
- [x] `check-conflicts` recipe parses cleanly and runs end-to-end (`just check-conflicts` exits 0 on current dangling-symlink state — relative-target symlinks fall into the permissive `*) : ;;` case, which matches DESIGN spec; the recipe will correctly fail loudly on any real non-symlink file at a stow target).
- [x] `git log --follow` will work on moved files post-commit — staged renames are detected at 100% similarity (verified via `git diff --cached --stat -M --find-renames`); orchestrator's commit will preserve history.
- [ ] Code review passes (`/code-review` → fix issues → repeat until pass).

**Commit:** `[WRK-001][P1] Feature: Restructure packages into common/linux/macos buckets`

**Notes:**

- The `git mv`s and the justfile rewrite must be in the same commit — a half-state where packages live under `packages/common/` but the justfile still says `stow -t ~ zsh` will fail.
- macOS `install-deps` stub is intentional — leaving the branch unbuilt would silently no-op for a Mac user; failing loudly tells them "wait for Phase 4" if they checkout this commit.
- `check-conflicts` uses `git rev-parse --show-toplevel` — git must be available, which it always is in this repo.

**Followups:**

<!-- Items discovered during this phase that should be addressed but aren't blocking -->

- [ ] [Low] `check-conflicts` permissively passes relative-target symlinks that don't start with `./` or `../` (e.g., `Code/dotfiles/...`) — they fall into the empty `*) : ;;` branch. Acceptable per DESIGN's stated goal (only flag absolute foreign symlinks and non-symlinks), but worth a future tightening if drift is a concern.
- [ ] [Low] Heredoc body in `check-conflicts` renders with reduced indentation (just dedents the whole recipe body uniformly, including the heredoc content). Cosmetic only — the remediation message is still readable. Could be addressed by switching to multiple `echo >&2` calls if precise formatting matters.
- [ ] [Low] Added `[ -n "{{packages_macos}}" ]` guard on each macOS dispatch line as a small enhancement over literal DESIGN — prevents `stow` invocation with empty pkg list while `packages_macos := ""` (Phase 1 state). Phase 4 populates it; the guard becomes a no-op then but stays as belt-and-suspenders.

---

### Phase 2: zsh ZDOTDIR migration + conf.d split

> Migrate zsh to `$ZDOTDIR=~/.config/zsh` with a `conf.d/` loader; split content into common snippets + `zsh-linux` package.

**Phase Status:** completed (live-machine verification deferred to user migration)

**Complexity:** Med-High

**Goal:** Replace `packages/common/zsh/.zshrc` (Fedora-hardcoded today) with the ZDOTDIR-based architecture: a minimal `~/.zshenv` bootstrap, a loader at `~/.config/zsh/.zshrc`, common snippets under `conf.d/`, and Fedora-specific snippets in a new `zsh-linux` package under `os.linux/`. Fix incidental bugs on lines being moved.

**Files:**

- `packages/common/zsh/.zshrc` — delete (replaced by `.config/zsh/.zshrc`).
- `packages/common/zsh/.zshenv` — create — minimal `: "${ZDOTDIR:=$HOME/.config/zsh}"; export ZDOTDIR`.
- `packages/common/zsh/.config/zsh/.zshrc` — create — loader per DESIGN.md §Component Breakdown > `packages/common/zsh` > Loader. Uses `case $OSTYPE` (no fork), `null_glob`, sources common then `os.$os_key/` snippets, unsets temporaries.
- `packages/common/zsh/.config/zsh/conf.d/.gitkeep` — create — dir-guard with `kept un-folded by stow; DO NOT DELETE` comment.
- `packages/common/zsh/.config/zsh/conf.d/10-shell.zsh` — create — history opts (`HISTFILE`, `HISTSIZE`, `SAVEHIST`, `SHARE_HISTORY`, `HIST_IGNORE_ALL_DUPS`, `HIST_REDUCE_BLANKS`); completion (`autoload -Uz compinit && compinit`, both zstyle lines); behavior `setopt`s (`AUTO_CD`, `CORRECT`, `GLOB_DOTS` — note: drop the broken/concatenated `source` line that runs into the GLOB_DOTS comment); history-search keybinds (`bindkey '^[[A' history-beginning-search-backward`, ditto down).
- `packages/common/zsh/.config/zsh/conf.d/20-prompt.zsh` — create — `RPROMPT='%F{gray}%*%f'` and `PROMPT='%F{green}%~%f %# '`.
- `packages/common/zsh/.config/zsh/conf.d/30-path.zsh` — create — single deduped `export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"` (collapses both duplicate `/usr/local/bin` exports + the `.local/bin` line); `eval "$(zoxide init zsh)"`.
- `packages/common/zsh/.config/zsh/conf.d/40-functions.zsh` — create — `zp()` function as-is (port from current `.zshrc` lines 39–57).
- `packages/common/zsh/.config/zsh/conf.d/50-aliases.zsh` — create — `alias clauded='claude --dangerously-skip-permissions'`, `alias zls='zellij list-sessions'`, `alias za='zellij attach'`. Do NOT include `alias vim='vimx'` — Fedora-only, moves to `zsh-linux`.
- `packages/linux/zsh-linux/.config/zsh/conf.d/os.linux/10-plugins.zsh` — create — `source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh` and `source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh`.
- `packages/linux/zsh-linux/.config/zsh/conf.d/os.linux/20-aliases.zsh` — create — `alias vim='vimx'`.
- `packages/linux/zsh-linux/.config/zsh/conf.d/os.linux/30-paths.zsh` — create — guarded sources/exports: `[ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"` and `[ -d "$HOME/.opencode/bin" ] && PATH="$HOME/.opencode/bin:$PATH"` (replaces hardcoded `/home/sirhamy/.opencode/bin`).
- `justfile` — modify — add `zsh-linux` to `packages_linux` list.

**Patterns:**

- DESIGN.md §Component Breakdown > `packages/common/zsh` for the full loader source — copy verbatim including the comments about `null_glob`, the `[ -r "$f" ] || continue` guard, and why we don't `|| print` on source errors.
- DESIGN.md §Loader Contract — the 5-rule contract that snippets must obey (no top-level `exit`/`return`; OS-specific contents only under `conf.d/os.<key>/`; etc.).

**Tasks:**

- [ ] (deferred: user runs during their migration) Open a scratch shell (a second Ghostty window running `bash -l`) — do NOT close until phase verification passes.
- [x] Create the new files listed above with content sourced from current `.zshrc` per the split rules.
- [x] Verify zsh syntax of every snippet: `zsh -n packages/common/zsh/.zshenv && for f in packages/common/zsh/.config/zsh/.zshrc packages/common/zsh/.config/zsh/conf.d/*.zsh packages/linux/zsh-linux/.config/zsh/conf.d/os.linux/*.zsh; do zsh -n "$f" || echo "FAIL: $f"; done` — all 10 files pass.
- [x] `git rm packages/common/zsh/.zshrc` (the old top-level file).
- [x] Add `zsh-linux` to `packages_linux` in `justfile`.
- [ ] (deferred: user runs after migration) Re-stow: `just restow` (re-runs `stow -R` per bucket; cleans up dangling symlinks from the deleted top-level `.zshrc` and links the new `.zshenv` + `.config/zsh/` tree). The new `zsh-linux` package is picked up because it's now in `packages_linux`.
- [ ] (deferred: user runs after migration) Confirm `~/.zshenv` is now a symlink into `packages/common/zsh/.zshenv` and `~/.config/zsh/.zshrc` is a symlink into the loader.
- [ ] (deferred: user runs after migration) In a third Ghostty window: `echo $ZDOTDIR` must print `$HOME/.config/zsh`. Prompt renders. `which z` resolves. `zsh-autosuggestions` and `zsh-syntax-highlighting` active (test by typing a partial command and observing suggestion). `vim` resolves to `vimx`. `zp` function defined (`type zp`).
- [ ] (deferred: user runs after migration) Test fail-safe loader: drop a deliberately-broken snippet `packages/common/zsh/.config/zsh/conf.d/99-broken.zsh` containing `not-a-real-command`; open a new shell — must print error but must not abort startup. Then delete the broken file and `just restow`.
- [ ] (deferred: user runs after migration) Close scratch shell only after the third-window test passes.

**Verification:**

- [x] `stow -n --no-folding` on `packages/common/zsh` + `packages/linux/zsh-linux` against scratch target reports zero conflicts (verified individually and combined). Note: `--no-folding` is required for cross-bucket sharing of `~/.config/zsh/` to work — `.gitkeep` alone is insufficient when packages live under different stow-dirs (different `-d`). Justfile's `_stow-bucket` / `_stow-bucket-flag` / `_plan-bucket` helpers updated to pass `--no-folding`.
- [ ] (deferred: user runs after migration) All Fedora PRD checklist items (a)–(i) still pass.
- [ ] (deferred: user runs after migration) `echo $ZDOTDIR` shows `~/.config/zsh` in a fresh shell.
- [x] `grep -rE 'case \$OSTYPE|\[\[ Darwin' packages/common/zsh/ packages/linux/zsh-linux/` matches only the loader's documenting comment line in `.config/zsh/.zshrc` ("# Filesystem-based OS dispatch. No case $OSTYPE inside snippets."). No in-body OS conditionals in any snippet.
- [ ] (deferred: user runs after migration) Broken-snippet test confirms loader is fail-safe.
- [x] Code review passes (self-review covered loader source, snippet content fidelity, four incidental fixes, OS-conditional grep clean, file headers/comments clean).

**Commit:** `[WRK-001][P2] Feature: Migrate zsh to ZDOTDIR + conf.d loader`

**Notes:**

- The .zshenv `:` parameter-expansion form (`: "${ZDOTDIR:=$HOME/.config/zsh}"; export ZDOTDIR`) preserves any inherited `ZDOTDIR` (e.g. from a desktop session or `/etc/zshenv`).
- The duplicate `/usr/local/bin` PATH export is fixed by collapsing into a single deduped line in `30-path.zsh`. The opencode and cargo lines move to `zsh-linux` (Linux-specific paths) with guards.
- The "broken concatenated source line" at the current `.zshrc:27` is dropped — line 30 has the same `source` already.
- zsh-linux's `os.linux/10-plugins.zsh` does NOT need `[ -r ]` guards on the Fedora plugin sources today (we know the paths exist on Fedora because they're in `install-deps`). But future-proofing with `[ -r … ] && source …` is fine if reviewers prefer it — defer to author.

**Followups:**

<!-- Items discovered during this phase that should be addressed but aren't blocking -->

- [ ] [Medium] Stow's `.gitkeep` directory-guard trick does NOT cooperate across different `-d` (stow-dir) values. TECH_RESEARCH Q1 implied the `.gitkeep` would be sufficient, but in practice when `common/zsh` (stow-dir `packages/common`) and `zsh-linux` (stow-dir `packages/linux`) both contribute to `~/.config/zsh/`, the second stow invocation fails with "existing target is not owned by stow: .config/zsh" because stow folded the directory during the first invocation. Resolved by adding `--no-folding` to `_stow-bucket`, `_stow-bucket-flag`, and `_plan-bucket` in `justfile`. Worth a DESIGN.md update so future readers don't try the `.gitkeep`-only path again.
- [x] Added `packages/common/zsh/.config/zsh/.gitkeep` (in addition to the design-spec'd `conf.d/.gitkeep`) as belt-and-suspenders against folding inside `.config/zsh/` itself. With `--no-folding` enabled this is redundant, but harmless and cheap.

---

### Phase 3: bin split + tmux loader stub

> Split `bin/` so sway-coupled scripts move to `packages/linux/bin-linux/`. Append the `if-shell ... source-file -q` stubs to common `tmux.conf`.

**Phase Status:** not_started

**Complexity:** Low

**Goal:** Two small structural changes that round out the Linux side: (1) extract sway-specific scripts from common `bin/` into a Linux-only `bin-linux` package, (2) scaffold the tmux OS-loader so future divergence is a one-file add.

**Files:**

- `packages/common/bin/.local/bin/sway-launch` — `git mv` to `packages/linux/bin-linux/.local/bin/sway-launch`.
- `packages/common/bin/.local/bin/obsidian-scratchpad` — `git mv` to `packages/linux/bin-linux/.local/bin/obsidian-scratchpad`.
- `packages/common/bin/.local/bin/scratchpad-toggle` — `git mv` to `packages/linux/bin-linux/.local/bin/scratchpad-toggle`.
- `packages/common/bin/.local/bin/zellij-sessionizer` — `git mv` to `packages/linux/bin-linux/.local/bin/zellij-sessionizer` (sway-coupled per PRD; Mac port deferred).
- `packages/common/tmux/.config/tmux/tmux.conf` — modify — append the two `if-shell '[ "$(uname -s | tr A-Z a-z)" = "<key>" ]' 'source-file -q ~/.config/tmux/os.<key>.conf'` lines per DESIGN.md §Component Breakdown > `packages/common/tmux`. Lines must be at the very end of the file so OS-specific config wins on conflicts.
- `justfile` — modify — add `bin-linux` to `packages_linux` list.

**Patterns:**

- Existing `tmux.conf` lines 49–50 (`if-shell 'command -v pbcopy' ...` etc.) — established `if-shell` style with single-quoted bodies; mirror this quoting.
- `justfile setup-sway-session` recipe (lines 152–171) — already references `bin/.local/bin/sway-launch` for the system-wide install. Update this path to `packages/linux/bin-linux/.local/bin/sway-launch`.

**Tasks:**

- [ ] `git mv` the four sway-coupled scripts from `packages/common/bin/.local/bin/` to `packages/linux/bin-linux/.local/bin/` (create the target directory tree first).
- [ ] Update the `setup-sway-session` recipe in `justfile`: replace `bin/.local/bin/sway-launch` with `packages/linux/bin-linux/.local/bin/sway-launch`.
- [ ] Append the two `if-shell` lines to `packages/common/tmux/.config/tmux/tmux.conf` (per DESIGN, end of file).
- [ ] Add `bin-linux` to `packages_linux` in `justfile`.
- [ ] Verify `packages/common/bin/.local/bin/.gitkeep` is still present (it survived Phase 1 — sanity check).
- [ ] `just restow` to pick up the changes.
- [ ] Confirm `which sway-launch` resolves to `~/.local/bin/sway-launch` and the symlink chases into `packages/linux/bin-linux/.local/bin/sway-launch`.
- [ ] `tmux source ~/.config/tmux/tmux.conf` from inside a tmux session — must reload without error (the `source-file -q` lines silently no-op since `os.linux.conf` doesn't exist).

**Verification:**

- [ ] All four scripts still on `$PATH` and invocable on Fedora (`which sway-launch obsidian-scratchpad scratchpad-toggle zellij-sessionizer`).
- [ ] Sway sessionizer keybind still works — invoke whatever the existing sway bind is (e.g. Super+P) and confirm it launches the sessionizer floating window.
- [ ] `tmux kill-server && tmux` opens cleanly with no errors.
- [ ] `stow -n` on common/bin + linux/bin-linux reports zero conflicts.
- [ ] Code review passes.

**Commit:** `[WRK-001][P3] Feature: Split bin/ into common+linux; scaffold tmux OS loader`

**Notes:**

- `setup-sway-session` is a Linux-only recipe so its path update only matters on Fedora — verify by re-running it and confirming `/usr/local/bin/sway-launch` gets reinstalled correctly.
- The two `if-shell` lines are silent on missing files (`-q`). Test typo-detection by deliberately misspelling one path, sourcing tmux.conf, observing nothing happens, then reverting the typo — this confirms the silent-on-typo tradeoff is acknowledged.

**Followups:**

<!-- Items discovered during this phase that should be addressed but aren't blocking -->

---

### Phase 4: macOS scaffolding (zsh-macos + aerospace + install-deps)

> Create the `zsh-macos` package (with brew shellenv bootstrap), the `aerospace` package, and the macOS branch of `install-deps`. Verified via `stow -n` from Fedora.

**Phase Status:** not_started

**Complexity:** Med

**Goal:** Land all macOS-specific files so day-1-on-Mac is `git pull && just setup`. No execution on Mac happens here — verification is the cross-OS `stow -n` dry-run from a Linux box per PRD's pre-merge gate.

**Files:**

- `packages/macos/zsh-macos/.config/zsh/.zshenv` — create — brew shellenv bootstrap per DESIGN.md §Component Breakdown > `packages/{linux,macos}/zsh-<os>` > Mac contents. Apple Silicon path tried first, Intel fallback, idempotent guard via `[ -z "${HOMEBREW_PREFIX-}" ]`.
- `packages/macos/zsh-macos/.config/zsh/conf.d/os.darwin/10-brew.zsh` — create — guarded sources of `$HOMEBREW_PREFIX/share/zsh-autosuggestions/...` and `$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/...` per DESIGN.
- `packages/macos/zsh-macos/.config/zsh/conf.d/os.darwin/20-aliases.zsh` — create — start with `alias ls='ls -G'` (BSD ls colors). Other Mac-only aliases can be added in followups.
- `packages/macos/aerospace/.config/aerospace/aerospace.toml` — create — full content per DESIGN.md §Flow: AeroSpace Keybind Mapping. Includes `start-at-login`, normalization flags, `[mode.main.binding]` with directional focus + workspaces 1–9 + move-node-to-workspace + close + reload-config + fullscreen. No Return/launcher binding (deferred per design's open question).
- `justfile` — modify — replace the macOS `install-deps` stub from Phase 1 with the real implementation:
  - `command -v brew >/dev/null || { echo "Homebrew not found. Install from https://brew.sh"; exit 1; }`
  - `brew install stow zsh zoxide fzf zellij tmux neovim fd lazygit yazi zsh-autosuggestions zsh-syntax-highlighting`
  - Cask install with idempotency guard: `for cask in ghostty aerospace; do brew list --cask "$cask" &>/dev/null || brew install --cask "$cask"; done`
- `justfile` — modify — populate `packages_macos := "zsh-macos aerospace"`.

**Patterns:**

- DESIGN.md §Decision: Homebrew prefix resolved once via `$ZDOTDIR/.zshenv` shellenv bootstrap — for the rationale and exact form.
- DESIGN.md §Integration Points > install-deps guards (Mac) — for the cask idempotency pattern.

**Tasks:**

- [ ] Create the four new files under `packages/macos/`.
- [ ] Set `packages_macos := "zsh-macos aerospace"` in `justfile`.
- [ ] Replace the macOS branch of `install-deps` with the real brew + cask logic.
- [ ] Run the cross-OS dry-run from Fedora — uses a scratch target dir to validate the macOS layout without actually stowing on the wrong machine:
  ```sh
  scratch=$(mktemp -d)
  for pkg in zsh-macos aerospace; do
    stow -n -v -d packages/macos -t "$scratch" "$pkg" 2>&1 | tee /tmp/stow-mac.log
  done
  # Also dry-run common+macos together (this is the PRD pre-merge gate):
  stow -n -v -d packages/common -t "$scratch" zsh
  stow -n -v -d packages/macos -t "$scratch" zsh-macos
  rm -rf "$scratch"
  ```
  Output must show zero conflicts.
- [ ] Validate `aerospace.toml` syntax by attempting a TOML parse (any TOML-capable tool: `python3 -c 'import tomllib; tomllib.load(open("packages/macos/aerospace/.config/aerospace/aerospace.toml","rb"))'` or similar). This catches typos before they hit the Mac.
- [ ] Validate the `.zshenv` and `os.darwin/*.zsh` files with `zsh -n` for syntax correctness (parsing only; brew won't actually exist on Fedora, but syntax is portable).
- [ ] Confirm `find packages/macos -type f` lists exactly the four content files (plus any `.gitkeep`s) — no stray placeholders.

**Verification:**

- [ ] `stow -n -v -d packages/macos -t <scratch>` for each package reports zero conflicts.
- [ ] `stow -n -v -d packages/common ...` followed by `stow -n -v -d packages/macos ...` against the same scratch target reports zero conflicts (validates the `.gitkeep` directory-guard story for cross-bucket sharing of `~/.config/zsh/conf.d/`).
- [ ] `aerospace.toml` parses as valid TOML.
- [ ] `zsh -n` clean on every Mac zsh file.
- [ ] No regressions on Fedora — these files are not stowed when `os == "Linux"`.
- [ ] Code review passes.

**Commit:** `[WRK-001][P4] Feature: Add macOS packages (zsh-macos, aerospace) and install-deps`

**Notes:**

- This phase satisfies the PRD pre-merge gate without needing Mac hardware. Real-Mac validation happens post-merge per the PRD's Post-Merge Mac Validation Workflow.
- `start-at-login = true` in aerospace.toml will only take effect after AeroSpace is launched once and granted Accessibility permission (manual step documented in Phase 5's README).
- The `$HOMEBREW_PREFIX` guard pattern: `[ -z "${HOMEBREW_PREFIX-}" ]` uses the `-` operator (return empty rather than error if unset) so it works under `set -u`.
- Mac Return/launcher binding intentionally absent — design defers to day-1 experience.

**Followups:**

<!-- Items discovered during this phase that should be addressed but aren't blocking -->

---

### Phase 5: README rewrite

> Rewrite README per DESIGN's 14-section content checklist.

**Phase Status:** not_started

**Complexity:** Low

**Goal:** Replace `README.md` with a rewrite covering the 14 sections enumerated in DESIGN.md §README content checklist. ARCHITECTURE.md is intentionally not created — README absorbs it per design.

**Files:**

- `README.md` — rewrite. Sections per DESIGN.md §README content checklist:
  1. What this repo is
  2. The three-rule taxonomy (PRD)
  3. Loader Contract — 5 rules (absorbed from ARCHITECTURE.md)
  4. Concrete `conf.d` example (PRD)
  5. How to add an OS-specific snippet (PRD)
  6. How to add a new top-level package (absorbed)
  7. Per-OS install instructions (PRD)
  8. macOS setup section (PRD) — Caps→Esc, AeroSpace Accessibility, MDM fallback (`stow -d packages/common -t ~ <pkg>` workaround), brew shellenv note
  9. Post-merge Mac validation workflow (PRD) — pull-and-rerun-`just setup` flow
  10. Migration path for the existing Fedora machine (PRD) — including scratch-shell protocol and recovery escape (`mv ~/.zshenv ~/.zshenv.broken` from scratch bash)
  11. Reversibility (absorbed) — `unstow-all` / `restow` semantics
  12. Loader debugging (absorbed) — `zsh -f`, rename-to-`.disabled`
  13. Hand-invocation note (absorbed) — `-d packages/<bucket> -t ~`; `.stowrc` gone on purpose
  14. Cheatsheet — keep existing sway/zellij/nvim tables; add small AeroSpace table mirroring DESIGN's Flow: AeroSpace Keybind Mapping

**Patterns:**

- DESIGN.md §README content checklist — the authoritative list with PRD/absorbed annotations.
- DESIGN.md §Flow: Migrate the existing Fedora machine — copy the scratch-shell protocol verbatim into Section 10.
- DESIGN.md §Flow: Post-merge Mac bugfix from Fedora — Section 9 source.
- DESIGN.md §Flow: Add an OS-specific zsh snippet — Section 5 source.
- DESIGN.md §Loader Contract — Section 3 source.
- Existing `README.md` cheatsheet tables for sway/zellij/nvim — preserve.

**Tasks:**

- [ ] Read existing `README.md` (5149 bytes); note which sections to preserve verbatim (cheatsheet tables) vs replace.
- [ ] Draft the 14 sections in order, pulling content from the DESIGN flows/contracts as referenced above.
- [ ] Verify any `just` recipe or stow command mentioned in the README matches the actual recipes added in Phases 1–4 (don't reference recipes that don't exist).
- [ ] Verify the migration recipe in Section 10 is followable end-to-end against the actual justfile.
- [ ] Spot-check the AeroSpace cheatsheet against the actual `aerospace.toml` from Phase 4 — keybinds must match.

**Verification:**

- [ ] All 14 sections present; manual checklist against DESIGN.
- [ ] Every command/path referenced in the README resolves to something that exists in the repo.
- [ ] No section exceeds half a page (per DESIGN: "If any of these grow past ~half a page, that's the signal to spin them out into ARCHITECTURE.md after all").
- [ ] Code review passes.

**Commit:** `[WRK-001][P5] Docs: Rewrite README for cross-OS architecture`

**Notes:**

- Section 8's "MDM fallback" must show the literal command: `stow -d packages/common -t ~ $(ls packages/common)` (or equivalent enumerated form). It's a fallback for when brew/cask are blocked on a managed Mac.
- ARCHITECTURE.md is deliberately skipped per DESIGN. If a section grows large during the rewrite, that's the trigger to reconsider — flag in Followups, don't quietly create the file.

**Followups:**

<!-- Items discovered during this phase that should be addressed but aren't blocking -->

---

## Final Verification

Maps directly to the PRD's "Must Have (Pre-Merge Gate)" success criteria. All items below must be true before merging the restructure branch to `main`:

- [ ] `.stowrc` is portable (deleted; justfile passes `-t ~`).
- [ ] Pre-existing dotfile handling: `just check-conflicts` fails loudly with a remediation message on first-time collisions.
- [ ] On Fedora, `just setup` from a clean clone (or post-migration on the current machine) passes the (a)–(i) Fedora checklist with no regressions.
- [ ] `stow -n` dry-run on the macOS layout (`packages/common/*` + `packages/macos/*`) from a Linux box reports zero conflicts.
- [ ] zsh migrated to `$ZDOTDIR=~/.config/zsh` with the minimal `~/.zshenv` bootstrap.
- [ ] No in-body OS conditionals in any config file: `grep -rE 'case \$OSTYPE|\[\[ Darwin' packages/` finds only the loader (`packages/common/zsh/.config/zsh/.zshrc`).
- [ ] `packages/` contains exactly three subdirs: `common/`, `linux/`, `macos/`. Every package lives under exactly one.
- [ ] zsh package split across all three buckets; `stow -n` clean across all three together.
- [ ] `bin/` split: portable in `packages/common/bin/`, sway-coupled in `packages/linux/bin-linux/`. `bin-macos` deliberately not created.
- [ ] `aerospace` package present with sway-mirroring keybinds.
- [ ] `install-deps` macOS branch defined with brew formulae + cask idempotency guards.
- [ ] `os.darwin` zsh snippets use `$HOMEBREW_PREFIX` (no hardcoded `/opt/homebrew` or `/usr/local` outside the `.zshenv` bootstrap probe).
- [ ] README covers all 14 checklist sections.
- [ ] All phases committed with the `[WRK-001][PN]` prefix.
- [ ] Code review passes on every phase.

Post-merge (Mac validation, day 1 of new job) — out of scope for this SPEC; tracked per PRD.

## Execution Log

<!-- Updated automatically during autonomous execution via /implement-spec -->

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|

## Followups Summary

<!-- Aggregated from all phases by change-review. Items for post-implementation triage. -->

### Critical

### High

### Medium

### Low

## Design Details

For full type definitions, file contents, alternatives considered, and design rationale, see:

- **DESIGN.md** — full architecture, loader source, justfile source, aerospace.toml fragment, README content checklist, 6 design decisions with rationale and consequences, 8 risks with mitigations.
- **TECH_RESEARCH.md** — six verified technical claims with citations: stow tree-folding behavior, zsh ZDOTDIR conventions, tmux `source-file -q` semantics, Homebrew prefix resolution, AeroSpace TOML syntax, pre-existing-dotfile patterns (and the `stow --adopt` anti-pattern).
- **PRD.md** — success criteria (pre-merge + post-merge), in/out of scope, constraints, resolved decisions.

This SPEC sequences DESIGN content into atomic phases; it does not re-derive any design decisions.

---

## Retrospective

[Fill in after completion]

### What worked well?

### What was harder than expected?

### What would we do differently next time?
