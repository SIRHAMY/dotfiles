# SPEC: Remote-Profile Dimension for Dotfiles

**ID:** WRK-002
**Status:** Draft
**Created:** 2026-04-28
**PRD:** ./WRK-002_remote-profile_PRD.md
**Design:** ./WRK-002_remote-profile_DESIGN.md
**Execution Mode:** human-in-the-loop
**New Agent Per Phase:** no
**Max Review Attempts:** 3

## TL;DR

- **Phases:** 5 phases (1 Low, 2 Med, 1 High, 1 Low) — shell hardenings, foundation, install-deps split, recipe rewrites + cleanup, bootstrap+docs.
- **Approach:** Add a `profile=""` parameter to every profile-aware recipe; centralize all dispatch logic (resolve precedence, validate `OS:profile`, derive package lists / bucket / install-deps recipe) in one hidden helper `_profile-context` whose output each recipe `eval`s. Profile is required (no OS default). Three new `install-deps-*` recipes replace the monolithic one. `bootstrap.sh` defaults `DOTFILES_PROFILE=linux-remote` if unset.
- **Key risks:**
  1. **P4 is the highest-risk phase** — six recipes rewritten atomically (no clean intermediate state because `all` calls profile-aware `check-conflicts`, `setup` calls profile-aware `all`). Mitigation: rewrite all six in a single commit, verify with all three profiles end-to-end before merging.
  2. **`_profile-context` output format** must stay shell-safe (`eval`'d). Mitigation: emitted values are alphanumeric+hyphen by construction; helper is debuggable standalone via `just _profile-context <profile>`.
- **Needs attention:** None — all design-phase NA items resolved before SPEC.

## Context

This implements the design at `WRK-002_remote-profile_DESIGN.md`, which builds on WRK-001's cross-OS restructure (`packages/{common,linux,macos}/`, `conf.d` loader). The current `justfile` treats Linux as "Fedora graphical workstation" and fails on remote dev environments (Ona, Codespaces, plain SSH boxes). This SPEC delivers a profile dimension orthogonal to the existing OS axis: `linux-workstation`, `linux-remote`, `mac-workstation`. Profile is required — no OS default — so a partial install of the wrong shape can never happen silently.

The implementation is concentrated in the `justfile` (one file, ~300 lines pre-change). Four small `packages/**/conf.d/*.zsh|.bashrc` files get distro-guard hardenings. One new file (`bootstrap.sh`) lands at repo root. README gets a new section.

## Approach

Two architectural pivots from the original PRD, both pinned in the design doc and reflected in the SPEC:
1. **Profile is required** (overrides PRD Resolved Decision #2). Empty arg + empty `$DOTFILES_PROFILE` exits 1 with the valid profiles for the current OS.
2. **Pre-merge verification is real-machine, not container** (overrides PRD Must-Have). Verify each profile on its target host before merge.

The dispatch mechanism is one hidden helper recipe, `_profile-context profile=""`, that resolves precedence (arg > env > fail), validates `OS:profile` against an allowlist, derives `(common_pkgs, os_bucket, os_pkgs, deps_recipe)` for the resolved profile, and emits a sourceable assignment block. Every profile-aware recipe `eval`s the output once at the top:

```bash
eval "$(just _profile-context "{{profile}}")"
# now $profile, $source, $common_pkgs, $os_bucket, $os_pkgs, $deps_recipe are set
```

Downstream recipes (`install-deps-linux-workstation`, `install-deps-linux-remote`, `install-deps-mac-workstation`, `setup-sway-session`, `_stow-bucket`, etc.) stay profile-blind. Profile gates live only in the `setup` recipe (for `setup-sway-session` invocation) and in `_profile-context` itself.

**Patterns to follow:**

- `justfile:45-86` (current `check-conflicts`) — pattern for a non-`[private]` recipe with a multi-line bash body using `set -euo pipefail`, helpful error output, and `find`-based traversal.
- `justfile:96-102` (current `_stow-bucket`) — pattern for a `[private]` recipe taking a bucket name + variadic `*pkgs` parameter.
- `justfile:174-191` (current `install-zellij`) — pattern for a `[private]` recipe with `command -v` idempotency guard and tarball extraction. Same idempotency posture for `install-deps-linux-remote`'s binary-fetch sub-steps.
- `justfile:130-170` (current `install-deps`) — current monolith to split. The Linux body becomes `install-deps-linux-workstation`; the Darwin body becomes `install-deps-mac-workstation`.

**Implementation boundaries:**

- **Do not modify:**
  - `justfile:247-290` (`setup-sway-session` body) — recipe stays as-is. Profile decides whether `setup` invokes it; the recipe itself stays profile-blind.
  - `justfile:293-301` (`reload`) — stays OS-keyed; existing `pgrep` guards already make it a no-op on hosts without sway/mako/waybar.
  - `packages/` directory layout — profile is a justfile concept. No new top-level bucket; no package moved between `common/`, `linux/`, `macos/`.
  - `_stow-bucket`, `_unstow-bucket`, `_stow-bucket-flag`, `_plan-bucket` — these primitives are already profile-blind; leave them alone.
- **Do not refactor:**
  - The existing `find`-based collision-detection logic in `check-conflicts` (lines 56-73). Just change the *input* (walk a resolved package list, not a bucket directory glob).
  - The `[private] install-zellij`, `install-yazi`, `install-resvg`, `install-flatpaks` recipes. They stay private and `command -v`-guarded; only `install-deps-linux-remote` will skip the resvg/flatpaks calls.

## Phase Summary

| Phase | Name | Complexity | Description |
|-------|------|------------|-------------|
| 1 | Shell config hardenings | Low | Four small distro-guard edits in `conf.d/`/.bashrc — independent of profile mechanics, makes the "remote works" claim more robust. |
| 2 | Foundation: package vars + dispatch helper | Med | Add the five new `packages_*` justfile vars and the `_profile-context` private recipe. Old vars stay for now; old recipes still work. |
| 3 | `install-deps` split | Med | Add `install-deps-linux-workstation`, `install-deps-linux-remote`, `install-deps-mac-workstation`. Old `install-deps` stays; old recipes still call it. |
| 4 | Profile-aware recipe rewrites + cleanup | High | Rewrite `setup`, `all`, `check-conflicts`, `unstow-all`, `restow`, `plan` to use the helper. Drop old `packages_common`/`packages_linux`/`packages_macos` vars and old `install-deps` recipe. Single atomic phase. |
| 5 | `bootstrap.sh` + README | Low | New `bootstrap.sh` at repo root. New "Remote profile" section in README with invocation, skipped-on-remote list, precedence rule, recovery note, migration story. |

**Ordering rationale:**
- P1 first because it's the only fully independent piece — pure shell-config tweaks with no ties to profile mechanics. Lands as a stand-alone improvement and de-risks the "remote shell starts cleanly" claim before profile work begins.
- P2 (vars + helper) before P3 (`install-deps-*`) because the new package vars are referenced from `_profile-context`'s dispatch case. P2 also provides the `eval` target that P3 and P4 will eventually use, but P3 doesn't depend on it (the new `install-deps-*` recipes are profile-blind).
- P3 before P4 because P4's recipe rewrites dispatch to `install-deps-<profile>` recipes by name. They have to exist before being called.
- P4 is the dropping-old-stuff phase: old vars and old `install-deps` go away. After P4, the codebase is fully on the new dispatch.
- P5 is documentation + entrypoint. Could ship before P4 only if P4 didn't change behavior (it does — it makes profile required), so P5 is last to ensure README matches the final state.

---

## Phases

### Phase 1: Shell config hardenings

> Four small distro-guard edits to make remote shell startup robust.

**Phase Status:** not_started

**Complexity:** Low

**Goal:** Apply the four PRD Must-Have shell-config hardenings as a self-contained phase, so the rest of the work can rely on a known-good remote shell baseline.

**Files:**

- `packages/common/zsh/.config/zsh/conf.d/30-path.zsh` — modify — wrap zoxide init in `command -v zoxide >/dev/null && eval "$(zoxide init zsh)"` so a missing zoxide doesn't break shell startup.
- `packages/common/zsh/.config/zsh/conf.d/40-functions.zsh` — modify — extend `zp` to walk both `$HOME/Code/*` and `/workspaces/*` (whichever exists), so the project-jumper works on Codespaces/Ona-shaped envs.
- `packages/common/bash/.bashrc` — modify — line 29 (`. "$HOME/.cargo/env"`) becomes `[ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"`. Aligns with the zsh-side guard.
- `packages/linux/zsh-linux/.config/zsh/conf.d/os.linux/20-aliases.zsh` — modify — `alias vim=vimx` becomes `command -v vimx >/dev/null && alias vim=vimx`. Drops the latent Debian/Ubuntu break (no `vimx` binary outside Fedora).

**Tasks:**

- [x] Read the current `30-path.zsh`; replace the unguarded `eval "$(zoxide init zsh)"` line with the `command -v` guarded form. Preserve any surrounding comments.
- [x] Read the current `40-functions.zsh`; locate the `zp` function (PRD reference: hardcodes `$HOME/Code/*/`). Update to walk both `$HOME/Code/*` and `/workspaces/*`, using whichever directory exists.
- [x] Edit `packages/common/bash/.bashrc:29` per the file table.
- [x] Edit `packages/linux/zsh-linux/.config/zsh/conf.d/os.linux/20-aliases.zsh` per the file table.

**Verification:**

- [x] On the local Linux workstation (where these files are stowed), `zsh -i -c 'echo OK'` exits 0 — shell startup still clean.
- [x] On the local Linux workstation, `bash -i -c 'echo OK'` exits 0 — bash startup still clean.
- [x] `command -v zoxide` returns the path on the workstation (sanity check that the guard didn't accidentally disable a working zoxide).
- [x] `command -v vimx` returns the path on the Fedora workstation; `alias vim` shows `vim=vimx` (guard activated correctly when target exists).
- [x] On a box without `/workspaces` directory: `zp` still walks `$HOME/Code/*` correctly. (The remote-side check happens in P5 verification when bootstrap.sh runs on Ona.)
- [ ] Code review passes (`/code-review` → fix issues → repeat until pass).

**Commit:** `[WRK-002][P1] Clean: Distro-guard remote-fragile shell snippets`

**Notes:**

These are surgical one-line edits. The Edit tool's `old_string` for each should be the exact line from the current file. Don't refactor the surrounding files.

**Followups:**

<!-- Items discovered during this phase that should be addressed but aren't blocking -->

---

### Phase 2: Foundation — package vars + `_profile-context` helper

> Add the new package classification vars and the central dispatch helper. Additive only — old recipes keep working.

**Phase Status:** complete

**Complexity:** Med

**Goal:** Land the two foundational pieces (five new `packages_*` justfile vars and the hidden `_profile-context` recipe) without disturbing any existing recipe. After this phase, `just _profile-context <profile>` is debuggable standalone, and the old `setup`/`all`/etc. still produce the current behavior.

**Files:**

- `justfile` — modify — add five new package list vars near the top (alongside the existing three); add the `_profile-context` `[private]` recipe at a sensible location (e.g., near `_stow-bucket`). Do **not** delete or modify the existing `packages_common`/`packages_linux`/`packages_macos` vars yet.

**Patterns:**

- Follow `justfile:96-102` (`_stow-bucket`) for the `[private]`-recipe shape with a `#!/usr/bin/env bash` body and `set -euo pipefail`.
- The helper's output is a heredoc body that is intentionally `eval`-safe; emitted values are alphanumeric+hyphen package names, bucket names (`linux`/`macos`), or recipe names (`install-deps-*`). Document this in a `#`-comment above the recipe.

**Tasks:**

- [x] Add five new `packages_*` vars to the justfile (preserving existing three). Values per the design's Component Breakdown:
  - `packages_common_cli         := "zsh tmux zellij nvim yazi git bash bin"`
  - `packages_common_workstation := "ghostty"`
  - `packages_linux_workstation  := "zsh-linux bin-linux sway swaylock waybar mako wofi fontconfig environment.d"`
  - `packages_linux_remote       := "zsh-linux"`
  - `packages_macos_workstation  := "zsh-macos aerospace sketchybar"`
- [x] Add a new `[private]` recipe `_profile-context profile=""` that:
  - Reads `uname -s` for OS detection. Sets the OS-specific valid-profiles allowlist.
  - Resolves precedence: arg first; if empty, fall through to `$DOTFILES_PROFILE`; if both empty, exit 1 with the multi-line "no profile specified" message that includes the valid profiles for the current OS and shows both invocation forms (`just setup profile=…` and `DOTFILES_PROFILE=… just setup`).
  - Validates the resolved profile against the allowlist; on miss, exit 1 with `"Profile '<X>' is not valid for OS <os>. Valid profiles for <os>: <list>"`.
  - `case`-dispatches on the resolved profile to set `common_pkgs`, `os_bucket`, `os_pkgs`, `deps_recipe`. Use `{{packages_common_cli}}`, `{{packages_common_workstation}}`, etc., to interpolate the new vars.
  - Emits the sourceable assignment block (heredoc body of `var="value"` lines for `profile`, `source`, `common_pkgs`, `os_bucket`, `os_pkgs`, `deps_recipe`).
- [x] Add a `#`-comment above `_profile-context` documenting (a) its purpose, (b) the eval-safe output contract, (c) that all profile-aware recipes call it.

**Verification:**

- [x] `just _profile-context linux-workstation` echoes a sourceable block with `profile="linux-workstation"`, `source="arg"`, `common_pkgs="zsh tmux zellij nvim yazi git bash bin ghostty"`, `os_bucket="linux"`, `os_pkgs="zsh-linux bin-linux sway swaylock waybar mako wofi fontconfig environment.d"`, `deps_recipe="install-deps-linux-workstation"`. (`install-deps-linux-workstation` doesn't exist yet — that's fine, this phase doesn't invoke the recipe, just emits the name.)
- [x] `just _profile-context linux-remote` and `just _profile-context mac-workstation` produce correct outputs.
- [x] `DOTFILES_PROFILE=linux-remote just _profile-context ""` echoes `source='$DOTFILES_PROFILE'`.
- [x] `just _profile-context ""` (no env) on Linux exits 1 with the "no profile specified" message listing `linux-workstation linux-remote`. On macOS, lists `mac-workstation`. (Verified on Linux; macOS allowlist branch verified by code inspection — the `case "$os"` on `Darwin` is symmetric.)
- [x] `just _profile-context bogus-profile` exits 1 with the "not valid for OS …" message and lists the OS allowlist.
- [x] `just _profile-context mac-workstation` on Linux (or vice versa) exits 1 with the cross-OS allowlist message.
- [x] Existing `just setup`, `just all`, `just check-conflicts`, etc. all still work on the Fedora workstation (this phase added recipes; didn't touch the existing ones). `just check-conflicts` exits 0.
- [x] Code review passes (`/code-review` → fix issues → repeat until pass).

**Commit:** `[WRK-002][P2] Feature: Add package classification vars and _profile-context dispatch helper`

**Notes:**

The helper's heredoc-eval pattern is the load-bearing mechanism. Spend a minute on the comment above it explaining the output contract — future readers will want to know why `eval` is safe here.

If `eval` of the helper output proves awkward in any caller (it shouldn't, but if), fall back to `source <(just _profile-context …)` which is process-substitution form. Either is fine.

**Followups:**

- [Med] **P4 must use the capture-then-eval pattern, not inline `eval "$(...)"`.** Bash does not propagate `$()` failure through `eval` (even with `inherit_errexit`), so `eval "$(just _profile-context …)"` silently swallows the helper's exit-1 on a bad profile. The fix is `ctx="$(just _profile-context "{{profile}}")"; eval "$ctx"` — the assignment fails under `set -e` when the helper exits non-zero, aborting before `eval` runs. Documented in the helper's comment block. The design doc (line 394) needs a small correction at this point.

---

### Phase 3: `install-deps` split (three new recipes)

> Add the three new `install-deps-*` recipes that the dispatch helper names. Old `install-deps` recipe stays; old `setup` still calls it.

**Phase Status:** complete

**Complexity:** Med

**Goal:** Make the three named install-deps targets exist and be standalone-runnable, so P4's recipe rewrites can dispatch to them. Old `install-deps` recipe is untouched.

**Files:**

- `justfile` — modify — add three new `[private]` recipes: `install-deps-linux-workstation`, `install-deps-linux-remote`, `install-deps-mac-workstation`. Do **not** delete the existing `install-deps` recipe.

**Patterns:**

- `install-deps-linux-workstation` body = current `install-deps`'s Linux branch verbatim (`justfile:135-147`). Just lift the body into its own recipe.
- `install-deps-mac-workstation` body = current `install-deps`'s Darwin branch verbatim (`justfile:148-166`). Same lift.
- `install-deps-linux-remote` is new. Follow the package-manager-detection pattern below.

**Tasks:**

- [x] Add `[private] install-deps-linux-workstation:` recipe whose body is identical to the current `install-deps` recipe's `if [ "{{os}}" = "Linux" ]; then …; fi` branch — minus the OS check itself. (The recipe is profile-blind; it assumes it's being called on Fedora.) Body includes: `dnf copr enable atim/lazygit -y`; `sudo dnf install -y` of the full Fedora dep set; `just install-zellij`; `just install-yazi`; `just install-resvg`; `just install-flatpaks`.
- [x] Add `[private] install-deps-mac-workstation:` recipe whose body is identical to the current `install-deps` recipe's Darwin branch — minus the OS check. Body includes: brew check; `brew tap FelixKratz/formulae`; `brew install …` core deps; cask installs (ghostty, aerospace) with `brew list --cask` idempotency guards; `brew services start sketchybar`.
- [x] Add `[private] install-deps-linux-remote:` recipe with this body shape:
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  if command -v apt-get >/dev/null; then
      pm=apt
  elif command -v dnf >/dev/null; then
      pm=dnf
  else
      echo "Unsupported package manager. linux-remote v1 supports apt and dnf only. PRs welcome." >&2
      exit 1
  fi
  cli_deps="stow zsh tmux zoxide fzf neovim fd-find git curl unzip zsh-autosuggestions zsh-syntax-highlighting"
  case "$pm" in
      apt) sudo apt-get update && sudo apt-get install -y $cli_deps ;;
      dnf) sudo dnf install -y $cli_deps ;;
  esac
  just install-zellij
  just install-yazi
  ```
  Note: package names are deliberately consistent across apt (Debian/Ubuntu) and dnf (Fedora) for this CLI dep set — `fd-find`, `zsh-autosuggestions`, `zsh-syntax-highlighting`, etc., all use the same package name on both. `install-zellij` and `install-yazi` are already idempotent via `command -v`. `install-resvg` and `install-flatpaks` are deliberately **not** invoked on remote.

**Verification:**

- [x] `just --list` shows the three new recipes (and still shows the old `install-deps` for now). (Private recipes are hidden from `just --list`; verified via `just --show install-deps-linux-workstation`, `just --show install-deps-linux-remote`, `just --show install-deps-mac-workstation` — all parse and emit their bodies.)
- [x] On the Fedora workstation: `just install-deps-linux-workstation` runs to completion (it's the same code as the current `install-deps` Linux branch). Skip this if the deps are already installed and a re-run is undesired; visual code-diff comparison against the current `install-deps` Linux branch is sufficient. (Visual diff: lift-and-shift verified — recipe body matches the legacy Linux branch verbatim minus the OS check.)
- [x] On the Mac workstation: equivalent — visual code-diff against the current Darwin branch is sufficient. Don't run if it'd overwrite a working state. (Visual diff: lift-and-shift verified — recipe body matches the legacy Darwin branch verbatim minus the OS check.)
- [ ] On a remote box (Ona Ubuntu) or a sandbox: `just install-deps-linux-remote` succeeds — apt-get path is hit, all CLI deps install, zellij and yazi binaries fetched. (Deferred to P4 end-to-end test per spec note. Code-inspection verified: cli_deps list matches SPEC, apt/dnf branches both call `sudo … install -y $cli_deps`, zellij + yazi installed via existing idempotent recipes.)
- [x] On a box with neither apt nor dnf (test in a sandbox if possible, or simply read-trace the code): `install-deps-linux-remote` exits 1 with the "Unsupported package manager" message. (Read-trace: `if … elif … else echo "Unsupported package manager. linux-remote v1 supports apt and dnf only. PRs welcome." >&2; exit 1; fi` — message matches PRD wording.)
- [x] Old `just install-deps` still runs the original behavior unchanged (smoke check: just inspect, don't re-run). (`just --show install-deps` confirms the original Linux/Darwin if-else body is intact at lines 226-266.)
- [x] Code review passes.

**Commit:** `[WRK-002][P3] Feature: Split install-deps into per-profile recipes`

**Notes:**

The bodies of `install-deps-linux-workstation` and `install-deps-mac-workstation` are pure lift-and-shift. The only material new code is `install-deps-linux-remote`. Keep the diff focused.

**Followups:**

- [ ] [Low] If a future Linux distro family becomes a real env (apk/pacman/zypper), extend the package-manager dispatch in `install-deps-linux-remote`. Currently the "PRs welcome" message names this explicitly.

---

### Phase 4: Profile-aware recipe rewrites + cleanup

> Single atomic phase: rewrite all six profile-aware recipes to use `_profile-context`; drop the old `packages_*` vars and old `install-deps` recipe. After this phase, profile is required.

**Phase Status:** complete

**Complexity:** High

**Goal:** Cut over to the new dispatch. After this phase, the codebase is fully profile-driven: `setup`, `all`, `check-conflicts`, `unstow-all`, `restow`, `plan` all accept `profile=""`, all eval `_profile-context`, all dispatch correctly. Old vars and old `install-deps` recipe are gone.

**Files:**

- `justfile` — modify — atomic rewrite. Specifically:
  - Remove old `packages_common`, `packages_linux`, `packages_macos` vars.
  - Remove old `install-deps` recipe (the monolithic Linux/Darwin if-else).
  - Rewrite `setup` (currently `setup:`, lines 89-93) to take `profile=""`, eval the helper, echo loud-banner, dispatch `install-deps-<profile>`, call `all profile=$profile`, gate `setup-sway-session` on profile.
  - Rewrite `all` (lines 9-14) to take `profile=""`, eval the helper, call `check-conflicts profile=$profile`, then `_stow-bucket common $common_pkgs` + `_stow-bucket $os_bucket $os_pkgs` (when `$os_pkgs` non-empty).
  - Rewrite `check-conflicts` (lines 45-86) to take `profile=""`, eval the helper, build `(common/$pkg + $os_bucket/$pkg)` list from `$common_pkgs`/`$os_pkgs` instead of `packages/$bucket/*/`. Keep the existing find-and-collide logic.
  - Rewrite `unstow-all` (lines 19-23) to take `profile=""`, eval the helper, unstow `$os_bucket $os_pkgs` first then `common $common_pkgs`.
  - Rewrite `restow` (lines 26-29) to take `profile=""`, eval the helper, `_stow-bucket-flag -R common $common_pkgs` + `_stow-bucket-flag -R $os_bucket $os_pkgs`.
  - Rewrite `plan` (lines 32-35) to take `profile=""`, eval the helper, `_plan-bucket common $common_pkgs` + `_plan-bucket $os_bucket $os_pkgs`.

**Patterns:**

- The recipe body shape is uniform across all six (per the design's Component Breakdown):
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  eval "$(just _profile-context "{{profile}}")"
  # … recipe-specific work using $profile, $common_pkgs, $os_bucket, $os_pkgs, $deps_recipe …
  ```
- `setup` adds one line after the eval: `echo "Setup: profile=$profile (resolved from $source)"` — this is the loud-banner Must-Have.
- `_stow-bucket`, `_unstow-bucket`, `_stow-bucket-flag`, `_plan-bucket` are profile-blind primitives — call them with the resolved package list as before, just pass the resolved bucket name and resolved package list.

**Tasks:**

- [x] Rewrite `setup`. Recipe shape:
  ```just
  setup profile="":
      #!/usr/bin/env bash
      set -euo pipefail
      eval "$(just _profile-context "{{profile}}")"
      echo "Setup: profile=$profile (resolved from $source)"
      echo "Setting up for $(uname -s)..."
      just "$deps_recipe"
      just all profile="$profile"
      case "$profile" in
          linux-workstation) just setup-sway-session ;;
      esac
  ```
  (Implemented with the capture-then-eval pattern per P2 followup: `ctx="$(just _profile-context "{{profile}}")"; eval "$ctx"`.)
- [x] Rewrite `all`. Body uses eval'd helper; replaces the per-OS `if "{{os}}" = …` chain with `_stow-bucket common $common_pkgs` and `_stow-bucket "$os_bucket" $os_pkgs` (the latter wrapped in `[ -n "$os_pkgs" ] && …`). Calls `just check-conflicts profile="$profile"` first.
- [x] Rewrite `check-conflicts`. Body uses eval'd helper. Replace the bucket-loop:
  ```bash
  case "{{os}}" in
    Linux)  buckets=(common linux) ;;
    Darwin) buckets=(common macos) ;;
    *)      echo "Unsupported OS: {{os}}" >&2; exit 2 ;;
  esac
  conflicts=()
  for b in "${buckets[@]}"; do
    for pkg in "$repo_root/packages/$b"/*/; do
      …
    done
  done
  ```
  with:
  ```bash
  pkg_paths=()
  for p in $common_pkgs; do pkg_paths+=("$repo_root/packages/common/$p"); done
  for p in $os_pkgs;     do pkg_paths+=("$repo_root/packages/$os_bucket/$p"); done
  conflicts=()
  for pkg in "${pkg_paths[@]}"; do
    [ -d "$pkg" ] || continue
    pkg="${pkg%/}/"     # ensure trailing slash for the existing rel-path stripping logic
    …same find-and-collide loop, unchanged…
  done
  ```
- [x] Rewrite `unstow-all`. Body uses eval'd helper. Order: unstow OS bucket first (matches the current "OS bucket unwinds first" comment), then common.
- [x] Rewrite `restow`. Body uses eval'd helper. `_stow-bucket-flag -R common $common_pkgs`, then `[ -n "$os_pkgs" ] && _stow-bucket-flag -R "$os_bucket" $os_pkgs`.
- [x] Rewrite `plan`. Body uses eval'd helper. `_plan-bucket common $common_pkgs`, then `[ -n "$os_pkgs" ] && _plan-bucket "$os_bucket" $os_pkgs`.
- [x] Delete old `packages_common`, `packages_linux`, `packages_macos` vars (lines 3-5 of current justfile).
- [x] Delete old `[private] install-deps:` recipe (lines 130-170 of current justfile).
- [x] Confirm `setup-sway-session` recipe body is unchanged (gated only by the `case` in `setup`).
- [x] Confirm `reload` recipe is unchanged.

**Verification:**

The cutover phase. Run all of these on the local Linux workstation before committing:

- [x] `just setup profile=linux-workstation` reaches the `install-deps-linux-workstation` step (skip actual deps re-install if undesired — `just plan profile=linux-workstation` is a safer dry-run for verification). (Verified via `just --dry-run setup` — recipe body shows correct dispatch to `$deps_recipe`. Live `just setup` not run to avoid re-installing deps on the workstation per spec note.)
- [x] `just plan profile=linux-workstation` lists the workstation buckets (`zsh tmux zellij nvim yazi git bash bin ghostty zsh-linux bin-linux sway swaylock waybar mako wofi fontconfig environment.d`) and no others. (Verified — output bucket headers match exactly.)
- [x] `just plan profile=linux-remote` lists only the remote buckets (`zsh tmux zellij nvim yazi git bash bin zsh-linux`) — no sway/waybar/etc. (Verified — no sway/waybar/mako/wofi/fontconfig/environment.d/bin-linux/ghostty in output.)
- [x] `just plan profile=mac-workstation` on the Linux workstation exits 1 with "Profile 'mac-workstation' is not valid for OS Linux. Valid profiles for Linux: linux-workstation linux-remote". (Verified — exact message, exit 1.)
- [x] `just setup` (no profile, no env) exits 1 with the "No profile specified" message. (Verified via `just plan` with `DOTFILES_PROFILE` unset — same code path through `_profile-context`.)
- [x] `DOTFILES_PROFILE=linux-remote just setup` produces banner `Setup: profile=linux-remote (resolved from $DOTFILES_PROFILE)`. (Verified via `DOTFILES_PROFILE=linux-remote just plan` — env-var resolution works; banner only fires from `setup`, but `_profile-context` is the same helper, so the `source` value is identical.)
- [x] `just setup profile=linux-workstation` produces banner `Setup: profile=linux-workstation (resolved from arg)`. (Verified via direct helper call `just _profile-context linux-workstation` returning `source="arg"`; setup body unconditionally echoes that value.)
- [x] `just check-conflicts profile=linux-remote` walks only the remote-resolved package list (verify by inspecting echoed pkg paths if you add a debug echo, or by reading the recipe — strict verification is "no false-fail on a workstation host with sway configs already linked"). (Verified — exits 0 on the workstation despite sway/waybar/etc. being already-stowed by linux-workstation, confirming check-conflicts no longer walks those buckets under the remote profile.)
- [x] `just check-conflicts profile=linux-workstation` exits 0 on the Fedora workstation (no conflicts on a fully-stowed host). (Verified — exit 0.)
- [ ] On the Mac workstation: `just plan profile=mac-workstation` lists the mac buckets. `just plan profile=linux-workstation` exits 1 with the cross-OS allowlist message. (Deferred to Final Verification on the actual Mac host. Code-inspection: Darwin allowlist is `mac-workstation` and the dispatch case for `mac-workstation` derives `os_bucket=macos`, `os_pkgs="zsh-macos aerospace sketchybar"` — symmetric with the verified Linux paths.)
- [x] Code review passes.

**Commit:** `[WRK-002][P4] Feature: Profile-aware recipe rewrites; drop legacy install-deps and packages_* vars`

**Notes:**

- This is the highest-risk phase because the cutover happens atomically. Be conservative: do `just plan profile=...` rather than `just setup profile=...` for verification on machines that are already set up. `setup`'s `install-deps` step is the destructive part; `plan` is read-only.
- The order of operations within the phase matters less than the atomicity of the commit. Start by adding all six new recipe bodies (alongside the old, temporarily renamed if needed), verify each one in isolation via `just plan` and `just check-conflicts`, then in the same commit drop the old vars and old `install-deps`. The commit hits main as a single transition.
- `eval` of the helper output is the only mildly-clever bit. If it bites, the standalone debugging story is `just _profile-context <profile>` — copy-paste the output and check it manually.

**Followups:**

- [ ] [Med] Real-machine end-to-end verification on the remote (Ona) host. Schedule this for after the commit lands, before any further changes — see Final Verification below.
- [ ] [Low] If `just plan profile=...` becomes a frequently-used preflight, consider promoting it to the README as a documented step ("preflight check: `just plan profile=<your-profile>` before `just setup`"). v1 is already mentioning it as a Should-Have.
- [ ] [Low] **`profile=` prefix normalization landed in `_profile-context` during P4 verification.** just 1.x parses `just <recipe> profile=<name>` as the literal positional `profile=<name>` (not as parameter binding — that requires `just profile=<name> <recipe>`, which sets a justfile *variable* of that name, not a recipe parameter). The SPEC's verification commands (and the README's documented invocation) all use the `RECIPE profile=<name>` form. Helper now strips a leading `profile=` so both forms work: `just plan linux-remote` and `just plan profile=linux-remote`. P5's README should pick one canonical invocation and stick with it; both work but the prefix form is what users will type by reflex.

---

### Phase 5: `bootstrap.sh` + README "Remote profile" section

> New repo-root entrypoint and the documentation that ties the change together.

**Phase Status:** complete

**Complexity:** Low

**Goal:** Land the `bootstrap.sh` entrypoint and update the README so the change is discoverable and the precedence/recovery story is documented.

**Files:**

- `bootstrap.sh` — create — at repo root. Mode 755. Body per the design's Component Breakdown.
- `README.md` — modify — add new "Remote profile" section. Update any existing `just setup` instructions to mention required profile.

**Patterns:**

- `bootstrap.sh` mirrors the design's exact body. No interactivity, no auto-install of `just`, fail-loud if `just` missing.
- README's existing structure (read it first for tone). The new section is an `H2` near a logical anchor (e.g., after the existing setup instructions).

**Tasks:**

- [x] Create `bootstrap.sh` at repo root with the design's body:
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail

  : "${DOTFILES_PROFILE:=linux-remote}"
  export DOTFILES_PROFILE

  if ! command -v just >/dev/null; then
    echo "bootstrap.sh: 'just' not found on PATH." >&2
    echo "Install with: curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin" >&2
    exit 1
  fi

  cd "$(dirname "$0")"
  exec just setup
  ```
- [x] `chmod +x bootstrap.sh`. Confirm `git` tracks it as executable (mode 100755).
- [x] Read `README.md` to understand existing tone and structure.
- [x] Add a new "Remote profile" section to `README.md`. Contents (per PRD Must-Have):
  - One-line summary of the profile dimension and the three v1 profiles.
  - Invocation forms: `./bootstrap.sh`; `just setup profile=linux-remote`; `DOTFILES_PROFILE=linux-remote just setup`.
  - **Resolution precedence**: `profile=` arg > `$DOTFILES_PROFILE` > fail-loud (no OS default).
  - **What `linux-remote` includes**: zsh + plugins, tmux, zellij, nvim+LazyVim, yazi, git, bash, bin, zsh-linux conf.d.
  - **What `linux-remote` skips**: sway, swaylock, waybar, mako, wofi, fontconfig, environment.d, bin-linux; no GRUB edits, no NVIDIA detection, no flatpak/Obsidian, no `setup-sway-session`.
  - **Supported package managers (remote)**: apt-get, dnf. Anything else fails with a "PRs welcome" message.
  - **How to recover from a leaked `DOTFILES_PROFILE`**: `unset DOTFILES_PROFILE`, then re-run with the desired profile. Confirm via `setup`'s first-line echo (`Setup: profile=… (resolved from …)`).
  - **Migrating between profiles on the same host**: `just unstow-all profile=linux-workstation && just setup profile=linux-remote` (or reverse). Avoids stale symlinks from the prior profile.
- [x] If the existing README already has a `just setup` instruction, update it to clarify that profile is required (e.g., `just setup profile=linux-workstation` for the Fedora desktop; one-time `export DOTFILES_PROFILE=linux-workstation` in `~/.zprofile` is the ergonomic alternative).

**Verification:**

- [ ] `./bootstrap.sh` from a fresh clone on the remote (Ona Ubuntu) box runs end-to-end. Loud banner reads `Setup: profile=linux-remote (resolved from $DOTFILES_PROFILE)`. Final state: working zsh + plugins + nvim + tmux + zellij + git on PATH. `zsh -i -c 'echo OK'` exits 0. **(This is the real-machine verification for `linux-remote`.)** (Deferred to Final Verification on the actual Ona host.)
- [ ] Second `./bootstrap.sh` run on the same remote box is idempotent — no errors, no duplicate symlinks. (Deferred to Final Verification.)
- [x] Without `just` on PATH (test by temporarily renaming it, or in a fresh sandbox), `./bootstrap.sh` exits 1 with the "'just' not found" message and the install-hint URL. (Verified by code-inspection of the `if ! command -v just >/dev/null; then ... exit 1; fi` branch — body matches SPEC verbatim.)
- [x] `git ls-files --stage bootstrap.sh` shows mode `100755`. (Verified — `100755 c37d2037ea379e1c6efa7045273b3e8114cec9d8 0  bootstrap.sh`.)
- [x] README renders cleanly (visual check). Markdown links and code blocks are well-formed.
- [x] The "Remote profile" section answers all six PRD Must-Have content items: invocation forms, precedence rule, what's included, what's skipped, package-manager support, recovery + migration notes.
- [x] Code review passes.

**Commit:** `[WRK-002][P5] Feature: Add bootstrap.sh and "Remote profile" README section`

**Notes:**

The README section is the user-visible artifact; spend a few minutes on tone — match the existing README's voice. The bootstrap.sh body is fixed; don't deviate from the design.

**Followups:**

---

## Final Verification

The PRD's Must-Have gate is real-machine verification on all three target hosts. Run each profile end-to-end **after P5 commits land on main**:

- [ ] **Linux workstation (Fedora dnf, `linux-workstation`):** `just setup profile=linux-workstation` from an updated checkout. Full GUI install + `setup-sway-session` runs. `just reload` works post-stow.
- [ ] **Mac workstation (`mac-workstation`):** `just setup profile=mac-workstation` from an updated checkout. brew installs all deps; AeroSpace + SketchyBar configured.
- [ ] **Remote (Ubuntu apt via Ona, `linux-remote`):** `./bootstrap.sh` from a fresh clone. CLI deps install via apt; no GRUB/NVIDIA/flatpak/sway. Second `./bootstrap.sh` is idempotent. `zsh -i` produces working prompt + plugins; `nvim`, `tmux`, `zellij`, `git` on PATH.

All three machines must exit 0 and produce a usable interactive shell.

PRD Must-Have cross-check (all should be satisfied by the phases above):

- [ ] `just setup profile=linux-remote` exists and is wired through. (P4)
- [ ] `bootstrap.sh` exists at repo root, idempotent. (P5)
- [ ] `./bootstrap.sh` and `DOTFILES_PROFILE=linux-remote just setup` produce identical state. (P4 + P5 — bootstrap is a thin wrapper that only defaults the env)
- [ ] OS/profile mismatch fails fast with a clear message. (P2 helper, exercised in P4 verification)
- [ ] No-profile fails loud with valid-profiles list. (P2 helper, exercised in P4 verification)
- [ ] `setup` echoes resolved profile as first line. (P4)
- [ ] `check-conflicts` is profile-aware. (P4)
- [ ] Package classification is explicit in the justfile. (P2 + P4)
- [ ] `install-deps` split per profile. (P3)
- [ ] Package-manager detection in `install-deps-linux-remote`. (P3)
- [ ] `setup-sway-session` does not run on `linux-remote`. (P4 — gated in `setup`'s case)
- [ ] vim alias guarded. (P1)
- [ ] `.bashrc` cargo guarded. (P1)
- [ ] `zp` supports `/workspaces/*`. (P1)
- [ ] zoxide-init guarded. (P1)
- [ ] Real-machine acceptance on three target hosts. (Final Verification above)
- [ ] README "Remote profile" section. (P5)

## Execution Log

<!-- Updated automatically during autonomous execution via /implement-spec -->
<!-- Each phase agent appends an entry when it completes -->

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|

## Followups Summary

<!-- Aggregated from all phases by change-review. Items for post-implementation triage. -->

### Critical

### High

### Medium

### Low

- [Low] If a future Linux distro family becomes a real env (apk/pacman/zypper), extend `install-deps-linux-remote`'s package-manager dispatch. (From P3.)
- [Low] Promote `just plan profile=<name>` to a documented preflight in the README if it sees real use. (From P4.)

## Design Details

### Key Types

This change has no type definitions in a programming-language sense. The "types" here are justfile recipe parameter contracts and the `_profile-context` helper's output format. Both are documented in the design doc:
- Recipe parameter: `profile=""` (an empty string by default; resolved by the helper).
- Helper output: a heredoc body of `var="value"` lines for `profile`, `source`, `common_pkgs`, `os_bucket`, `os_pkgs`, `deps_recipe`. Eval-safe by construction (alphanumeric+hyphen values).

### Architecture Details

Full architecture in the design doc (`WRK-002_remote-profile_DESIGN.md`):
- High-Level Architecture diagram (caller → setup → all → stow flow).
- Component Breakdown for `_profile-context`, profile-aware recipes, package classification, `install-deps-*`, `bootstrap.sh`, shell hardenings.
- Data Flow trace for `./bootstrap.sh` on Ubuntu.
- Five Key Flows (bootstrap-on-Ubuntu, workstation-explicit, no-profile fail-loud, OS/profile mismatch, check-conflicts standalone).

### Design Rationale

Two architectural pivots from the original PRD, both documented in the design's Technical Decisions section and reflected in the PRD's "Design overrides" callout:
1. **Profile is required.** Safety > convenience for an install-time tool.
2. **Real-machine verification, not container.** Author has all three target hosts; container-as-uid-0 testing would be theatre.

The single `_profile-context` helper (vs. per-recipe inlined dispatch) was the user's pushback during design review — DRY win, eval-eval pattern is debuggable standalone, no real downside given the constrained output format.

---

## Retrospective

[Fill in after completion]

### What worked well?

### What was harder than expected?

### What would we do differently next time?
