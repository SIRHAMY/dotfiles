# Design: Remote-Profile Dimension for Dotfiles

**ID:** WRK-002
**Status:** In Review
**Created:** 2026-04-28
**PRD:** ./WRK-002_remote-profile_PRD.md
**Tech Research:** (none — PRD already locks the technical decisions; remaining questions are mechanical and resolved here in design)
**Mode:** Medium

## TL;DR

- **Approach:** Add a `profile` parameter to every profile-aware `just` recipe (`setup`, `all`, `check-conflicts`, `unstow-all`, `restow`, `plan`). A single hidden helper recipe `_profile-context` does *all* the shared work — resolves the precedence chain (`profile=` arg > `$DOTFILES_PROFILE`), validates `OS:profile` against an allowlist, derives the package lists / OS bucket / install-deps recipe — and emits a sourceable assignment block. Each profile-aware recipe collapses to ~3 lines (`eval "$(just _profile-context "{{profile}}")"` + the recipe's own work). Downstream recipes (`install-deps-linux-remote`, `setup-sway-session`, etc.) stay profile-blind. `bootstrap.sh` is a 12-line shell entrypoint that defaults `DOTFILES_PROFILE=linux-remote` if unset and exec's `just setup`.
- **Key decisions:**
  1. **Profile is a justfile concept, gated at call sites** (PRD Resolved Decision #1, #13). No `packages/remote/` bucket; no profile guards inside snippet bodies; downstream recipes are clean.
  2. **One `_profile-context` helper does resolve + validate + derive in one place.** Each profile-aware recipe `eval`s its output. No duplicated dispatch blocks across 6 recipes; single location to update for `mac-remote` or any future profile.
  3. **Profile is required.** `just setup` with no `profile=` arg AND no `$DOTFILES_PROFILE` fails loud with the OS allowlist. No silent OS default. (Overrides PRD Resolved Decision #2 — see Decisions for rationale.)
  4. **`check-conflicts` becomes package-list-aware, not bucket-aware.** Today it walks `packages/$bucket/*/`. Profile-awareness requires walking only the resolved profile's package list — otherwise remote installs falsely-fail on workstation-only conflicts (e.g., a stale `~/.config/sway/config` symlink left over from a prior workstation install).
- **Tradeoffs:** Each profile-aware recipe makes one `just` subprocess call (the context helper) plus an `eval`. Sub-millisecond cost. In exchange we get one place to look for all profile dispatch logic.
- **Needs attention:** None — NA-1, NA-2, NA-3 resolved (see Design Log).

## Overview

The dotfiles already split cleanly along an OS axis (WRK-001: `packages/{common, linux, macos}/` plus `conf.d` loader). This change adds a second, orthogonal axis — *profile* — that determines **which existing buckets get stowed and which install-deps recipe runs**. Profile lives entirely in the `justfile` and `bootstrap.sh`; it does not touch the `packages/` taxonomy or the `conf.d` snippet conventions.

Three v1 profiles are pinned by the PRD: `linux-workstation`, `linux-remote`, `mac-workstation`. Each profile maps to a package list (drawn from a few smaller `packages_*` justfile variables) and an `install-deps-<profile>` recipe. A single helper recipe (`_profile-context`) resolves the two-source precedence chain (`profile=` arg > `$DOTFILES_PROFILE`), validates the `OS:profile` combination, derives the dispatch context (common packages, OS bucket, OS packages, install-deps recipe name), and emits the result as a sourceable assignment block. Every profile-aware recipe — `setup`, `all`, `check-conflicts`, `unstow-all`, `restow`, `plan` — calls `_profile-context` once at the top and `eval`s its output. Downstream recipes (`install-deps-linux-workstation`, `install-deps-linux-remote`, `install-deps-mac-workstation`, `setup-sway-session`) stay clean and runnable on their own.

**Profile is required.** With no `profile=` arg and no `$DOTFILES_PROFILE`, `just setup` (and every other profile-aware recipe) fails loud with the valid profiles for the current OS. No OS-default fallback. This overrides PRD Resolved Decision #2 in service of safety: a partial dotfiles install (the wrong shape — full GUI deps on a headless box, or vice versa) is hard to undo cleanly. Forcing an explicit choice eliminates that failure mode.

`bootstrap.sh` is a thin entrypoint: it sets `DOTFILES_PROFILE=linux-remote` if unset, then `exec just setup`. So `./bootstrap.sh` continues to work without arguments — the env var defaulting *is* the explicit choice. Workstation users now run `just setup profile=linux-workstation` (or set `DOTFILES_PROFILE=linux-workstation` once in their shell rc). Both produce identical state.

---

## System Design

### High-Level Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│ Caller                                                               │
│   ./bootstrap.sh             OR   just setup [profile=...]           │
│   (sets DOTFILES_PROFILE=         (reads profile= arg, then          │
│    linux-remote if unset,          $DOTFILES_PROFILE; if both empty, │
│    then exec's just)               fails loud)                       │
└─────────────────────────────────────┬────────────────────────────────┘
                                      │
                                      ▼
┌──────────────────────────────────────────────────────────────────────┐
│ justfile: setup recipe                                               │
│   eval "$(just _profile-context "{{profile}}")"                      │
│   #  → sets $profile $source $common_pkgs $os_bucket $os_pkgs        │
│   #         $deps_recipe                                             │
│   echo "Setup: profile=$profile (resolved from $source)"             │
│   just "$deps_recipe"                                                │
│   just all profile="$profile"                                        │
│   case "$profile" in linux-workstation) just setup-sway-session ;;   │
│   esac                                                               │
└──────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌──────────────────────────────────────────────────────────────────────┐
│ justfile: all recipe                                                 │
│   eval "$(just _profile-context "{{profile}}")"                      │
│   just check-conflicts profile="$profile"                            │
│   just _stow-bucket common $common_pkgs                              │
│   [ -n "$os_pkgs" ] && just _stow-bucket "$os_bucket" $os_pkgs       │
└──────────────────────────────────────────────────────────────────────┘
```

`_profile-context` is the only new abstraction. Every profile-aware recipe calls it; nothing else does the dispatch logic.

### Component Breakdown

#### Dispatch helper (`_profile-context`)

**Purpose:** Single source of truth for profile resolution, validation, and dispatch context derivation.

**Responsibilities:**
- Read the recipe arg, then `$DOTFILES_PROFILE`; first non-empty wins. If both empty, fail loud with valid-profiles-for-current-OS message.
- Validate the resolved profile against the `OS:profile` allowlist. If invalid, fail loud with the same allowlist message.
- Derive `common_pkgs`, `os_bucket`, `os_pkgs`, `deps_recipe` from the resolved profile.
- Emit a sourceable assignment block (heredoc body of `var="value"` lines).

**Shape:**

```bash
_profile-context profile="":
    #!/usr/bin/env bash
    set -euo pipefail

    os="$(uname -s)"
    case "$os" in Linux|Darwin) ;; *) echo "Unsupported OS: $os" >&2; exit 2 ;; esac

    # Valid profiles per OS (single source of truth)
    case "$os" in
      Linux)  valid="linux-workstation linux-remote" ;;
      Darwin) valid="mac-workstation" ;;
    esac

    # Resolve precedence: arg > env > (none → fail)
    profile="{{profile}}"
    source=""
    if [ -n "$profile" ]; then
      source="arg"
    elif [ -n "${DOTFILES_PROFILE:-}" ]; then
      profile="$DOTFILES_PROFILE"
      source='$DOTFILES_PROFILE'
    else
      cat >&2 <<EOF
    No profile specified. Pass profile=<name> as an argument or export DOTFILES_PROFILE.

      just setup profile=$(echo "$valid" | awk '{print $1}')
      DOTFILES_PROFILE=$(echo "$valid" | awk '{print $1}') just setup

    Valid profiles for $os: $valid
EOF
      exit 1
    fi

    # Validate against OS allowlist
    case " $valid " in
      *" $profile "*) ;;
      *) echo "Profile '$profile' is not valid for OS $os. Valid profiles for $os: $valid" >&2; exit 1 ;;
    esac

    # Derive dispatch context
    case "$profile" in
      linux-workstation) common_pkgs="{{packages_common_cli}} {{packages_common_workstation}}"
                         os_bucket="linux"
                         os_pkgs="{{packages_linux_workstation}}"
                         deps_recipe="install-deps-linux-workstation" ;;
      linux-remote)      common_pkgs="{{packages_common_cli}}"
                         os_bucket="linux"
                         os_pkgs="{{packages_linux_remote}}"
                         deps_recipe="install-deps-linux-remote" ;;
      mac-workstation)   common_pkgs="{{packages_common_cli}} {{packages_common_workstation}}"
                         os_bucket="macos"
                         os_pkgs="{{packages_macos_workstation}}"
                         deps_recipe="install-deps-mac-workstation" ;;
    esac

    # Emit sourceable assignment block
    cat <<EOF
    profile="$profile"
    source="$source"
    common_pkgs="$common_pkgs"
    os_bucket="$os_bucket"
    os_pkgs="$os_pkgs"
    deps_recipe="$deps_recipe"
EOF
```

**Failure modes:**
- No profile provided (arg empty, env unset/empty): exit 1, prints valid profiles for current OS.
- Unknown profile (e.g., `linux-laptop`): exit 1, same allowlist message.
- Unknown OS: exit 2.

**Output contract:** stdout is a series of `var="value"` lines, safe to `eval` into the caller's shell. Profile names are alphanumeric+hyphen; dispatch values (bucket name, recipe name, package list) contain no special shell metacharacters by construction.

#### Profile-aware recipes (`setup`, `all`, `check-conflicts`, `unstow-all`, `restow`, `plan`)

Each takes `profile=""` as its first parameter. Recipe body shape:

```bash
#!/usr/bin/env bash
set -euo pipefail
eval "$(just _profile-context "{{profile}}")"
# Now $profile, $source, $common_pkgs, $os_bucket, $os_pkgs, $deps_recipe are set.
# … recipe-specific work …
```

`setup` adds one extra line — the loud-banner echo — immediately after the eval:
```bash
echo "Setup: profile=$profile (resolved from $source)"
```

(Other profile-aware recipes can echo a banner too if useful, but the loud-banner Must-Have only requires `setup`.)

The `eval` line is the **only** place profile decisions are made in user-facing recipes. A code reviewer can grep for `_profile-context` to find every profile-aware recipe.

#### Package classification (justfile variables)

PRD Must-Have spec:

```just
packages_common_cli         := "zsh tmux zellij nvim yazi git bash bin"
packages_common_workstation := "ghostty"
packages_linux_workstation  := "zsh-linux bin-linux sway swaylock waybar mako wofi fontconfig environment.d"
packages_linux_remote       := "zsh-linux"
packages_macos_workstation  := "zsh-macos aerospace sketchybar"
```

(Drops the existing `packages_common`, `packages_linux`, `packages_macos` vars.)

The single workstation-only common bucket today is `ghostty`. If a second emerges, it joins `packages_common_workstation`. If a future `linux-remote`-only common bucket emerges, add `packages_common_remote` and update the dispatch case in `_profile-context`.

`zsh-linux` deliberately stows on both Linux profiles. PRD #5 makes the placement rule explicit: headless-and-shared → `common/cli`; needs-a-desktop → `<os>/workstation`; remote-specific → `linux/remote`. Drift between profile package lists is allowed.

#### `install-deps-*` recipes (three new)

Replace today's monolithic `[private] install-deps`:

- **`install-deps-linux-workstation`** — current Linux behavior verbatim: `dnf copr enable atim/lazygit`, full GUI dep set, `install-zellij`, `install-yazi`, `install-resvg`, `install-flatpaks`. Stays dnf-only and Fedora-coupled. Failing on a Debian box is fine — workstation profile is for the author's Fedora desktop.
- **`install-deps-linux-remote`** — new. Detects package manager via `command -v apt-get >/dev/null && PM=apt || command -v dnf >/dev/null && PM=dnf || { echo 'Unsupported PM' >&2; exit 1; }`. Two arms:
  - apt: `sudo apt-get update && sudo apt-get install -y stow zsh tmux zoxide fzf neovim fd-find git curl unzip zsh-autosuggestions zsh-syntax-highlighting`
  - dnf: `sudo dnf install -y stow zsh tmux zoxide fzf neovim fd-find git curl unzip zsh-autosuggestions zsh-syntax-highlighting`
  - Then `just install-zellij` and `just install-yazi` (binary fetches, already idempotent via `command -v`).
  - Skips `install-resvg` and `install-flatpaks`.
  - Fails loud on apk/pacman/zypper/etc. with a "PRs welcome" message (PRD spec).
- **`install-deps-mac-workstation`** — current Darwin behavior verbatim.

`install-deps-*` recipes are profile-blind: each one assumes it's been called for the right OS+profile, and just does its job. Profile gating happens upstream in `setup`.

#### Stow loop (in `all`)

`all` becomes profile-aware — `eval`s `_profile-context` — and replaces today's per-OS `if "{{os}}" = …` guards with profile-derived `os_bucket` and `os_pkgs`:

```bash
just check-conflicts profile="$profile"
just _stow-bucket common $common_pkgs
[ -n "$os_pkgs" ] && just _stow-bucket "$os_bucket" $os_pkgs
echo "Done. Run 'just reload' on Linux to reload sway/waybar."
```

`_stow-bucket` itself stays unchanged — it's the lowest-level primitive that takes a bucket name and a package list. Same for `_unstow-bucket`, `_stow-bucket-flag`, `_plan-bucket`.

#### `check-conflicts` package-list-aware

Today `check-conflicts` walks `packages/$bucket/*/` — every directory in the bucket. That's only correct because today every directory in the bucket is also stowed. Under profiles, that's a false-fail risk: a `linux-remote` install that doesn't stow `sway` would still hit conflicts if `~/.config/sway/` exists from a prior workstation use.

(Note: only false-fail is at risk, not false-pass. Bucket-walk inspects a *superset* of the resolved profile's packages, so it can over-flag but not under-flag. The fix is still correct — over-flagging blocks legitimate remote installs — but the framing here is just "stop checking packages we won't stow.")

Fix: `check-conflicts` accepts `profile=""`, eval's `_profile-context`, and walks **only** the directories named in `(common_pkgs, os_pkgs)` instead of `packages/$bucket/*/`:

```bash
buckets_pkgs=()
for p in $common_pkgs; do buckets_pkgs+=("common/$p"); done
for p in $os_pkgs;     do buckets_pkgs+=("$os_bucket/$p"); done
for bp in "${buckets_pkgs[@]}"; do
  pkg_root="$repo_root/packages/$bp"
  [ -d "$pkg_root" ] || continue
  # …existing find-and-collide logic…
done
```

This also makes `check-conflicts` standalone-runnable per profile (`just check-conflicts profile=linux-remote`) — useful as a sanity check before `setup`.

#### `bootstrap.sh`

Repo-root entrypoint. Minimal:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Default to remote profile if caller did not specify one.
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

Idempotent because `just setup` is idempotent; reruns echo the resolved profile and walk through the same dispatch.

#### Shell config hardenings (4 small file edits)

Already pinned by PRD Must-Haves; mentioned here for design completeness. No structural change — single-line edits to existing files:

| File | Change |
|------|--------|
| `packages/common/zsh/.config/zsh/conf.d/30-path.zsh` | Wrap zoxide init in `command -v zoxide >/dev/null && eval "$(zoxide init zsh)"` |
| `packages/common/zsh/.config/zsh/conf.d/40-functions.zsh` | `zp` walks both `$HOME/Code/*` and `/workspaces/*` (whichever exists) |
| `packages/common/bash/.bashrc` | Cargo source becomes `[ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"` |
| `packages/linux/zsh-linux/.config/zsh/conf.d/os.linux/20-aliases.zsh` | `command -v vimx >/dev/null && alias vim=vimx` (drops the unguarded alias) |

### Data Flow

End-to-end on a clean Ubuntu remote box, caller invokes `./bootstrap.sh`:

1. **`bootstrap.sh`** — checks for `just`, sets `DOTFILES_PROFILE=linux-remote` (it was unset), exec's `just setup`. No args passed.
2. **`just setup`** (no `profile=` arg) — eval's `_profile-context ""`. Helper sees empty arg, falls through to env (`$DOTFILES_PROFILE=linux-remote`), validates `Linux:linux-remote` ✓, derives context, emits assignments. Setup echoes `Setup: profile=linux-remote (resolved from $DOTFILES_PROFILE)`.
3. **install-deps dispatch** — `just "$deps_recipe"` → `just install-deps-linux-remote`. Detects apt-get, runs `apt-get install -y …`, then `install-zellij` and `install-yazi` (both `command -v`-guarded; install on first run, no-op on rerun).
4. **`just all profile=linux-remote`** — eval's `_profile-context "linux-remote"`. Resolves to `linux-remote:arg`, validates, derives, emits. Calls:
   - `just check-conflicts profile=linux-remote` — eval's the helper, walks the resolved package list (`common: zsh tmux zellij nvim yazi git bash bin` + `linux: zsh-linux`), no conflicts on a fresh clone, exits 0.
   - `just _stow-bucket common zsh tmux zellij nvim yazi git bash bin` — stows each.
   - `just _stow-bucket linux zsh-linux` — stows `zsh-linux` (which carries the cargo/opencode PATH conf.d, valid on Debian).
5. **Setup-sway-session gate** — case in `setup` does not match `linux-workstation`; `setup-sway-session` is not invoked. No GRUB edit, no NVIDIA detection, no `/usr/local/bin` write.
6. **Final echo** — "Done. …"

A second `./bootstrap.sh` run repeats steps 1–5 with no errors and no new symlinks (stow is idempotent; apt-get and install-zellij/install-yazi are guarded).

### Key Flows

#### Flow: `./bootstrap.sh` on clean Ubuntu (happy path)

> Default remote bootstrap on a fresh Debian-family host.

1. **Caller** — `./bootstrap.sh` from a freshly cloned repo. `DOTFILES_PROFILE` unset.
2. **Bootstrap defaults env** — sets `DOTFILES_PROFILE=linux-remote`, `exec just setup`.
3. **Profile resolution + validation + context derivation** — helper resolves `linux-remote:env`, validates `Linux:linux-remote` ✓, emits assignments. Setup banner: `Setup: profile=linux-remote (resolved from $DOTFILES_PROFILE)`.
4. **install-deps-linux-remote** — apt detected; CLI deps installed; zellij+yazi binaries fetched.
5. **all → check-conflicts** — package-list-aware walk; no conflicts on fresh clone.
6. **all → stow** — `common` bucket (8 pkgs) and `linux` bucket (`zsh-linux` only) linked into `$HOME`.
7. **Sway-session gate** — skipped (profile ≠ `linux-workstation`).
8. **Done.** Subsequent `zsh -i` produces working prompt + zoxide + fzf + plugins; `nvim`, `tmux`, `zellij`, `git` on PATH.

**Edge cases:**
- *zoxide install failed silently* — the `30-path.zsh` guard means shell startup still succeeds; `z` is just unavailable.
- *Package mirror flake mid-`apt-get install`* — `set -euo pipefail` aborts. Caller reruns `./bootstrap.sh`; idempotent.

#### Flow: `just setup profile=linux-workstation` on Fedora workstation

> Workstation-side install. Caller now passes `profile=` explicitly (or has `DOTFILES_PROFILE=linux-workstation` exported in their shell rc — same result, banner reads `(resolved from $DOTFILES_PROFILE)`).

1. **Caller** — `just setup profile=linux-workstation` on the Fedora desktop.
2. **Profile resolution + validation + context derivation** — helper resolves `linux-workstation:arg`, validates `Linux:linux-workstation` ✓, derives context. Banner: `Setup: profile=linux-workstation (resolved from arg)`.
3. **install-deps-linux-workstation** — `dnf copr enable atim/lazygit`, full GUI dep set, zellij/yazi/resvg/flatpaks.
4. **all → check-conflicts** — walks `common: zsh tmux zellij nvim yazi git bash bin ghostty` + `linux: zsh-linux bin-linux sway swaylock waybar mako wofi fontconfig environment.d`.
5. **all → stow** — full workstation stow.
6. **Sway-session gate** — `linux-workstation` matches; `just setup-sway-session` runs (NVIDIA detect, GRUB edit, session entry).
7. **Done.** `just reload` available to nudge sway/waybar/mako.

**Edge cases:**
- *User has `DOTFILES_PROFILE=linux-remote` leaked into their shell rc and forgets to pass `profile=`* — `profile=` arg wins (precedence), so passing it explicitly always overrides. If they don't pass it, helper resolves to `linux-remote:env`, banner makes it visible immediately. Recovery: `unset DOTFILES_PROFILE && just setup profile=linux-workstation`.

#### Flow: No profile specified → fail-loud

> The change in posture from PRD #2: invoking without an explicit profile is no longer a no-op.

1. **Caller** — `just setup` on a fresh Linux box, no arg, `DOTFILES_PROFILE` unset.
2. **Profile resolution** — helper sees empty arg, empty env, fails:
   ```
   No profile specified. Pass profile=<name> as an argument or export DOTFILES_PROFILE.

     just setup profile=linux-workstation
     DOTFILES_PROFILE=linux-workstation just setup

   Valid profiles for Linux: linux-workstation linux-remote
   ```
   Exit code 1.
3. **No partial state** — no install-deps, no stow.

**Edge cases:**
- *Caller invokes `bootstrap.sh` instead* — no fail-loud, because bootstrap defaults the env var. This is the intended split: explicit-tool callers must be explicit; the script-bootstrap path is opinionated about defaulting to remote.

#### Flow: OS/profile mismatch (fail-fast)

> Invalid combination must abort before any side effect.

1. **Caller** — `just setup profile=mac-workstation` on Linux.
2. **Profile resolution** — helper resolves `mac-workstation:arg`.
3. **OS validation** — `mac-workstation` not in `Linux`'s allowlist (`linux-workstation linux-remote`).
4. **Fail loud** — stderr: `Profile 'mac-workstation' is not valid for OS Linux. Valid profiles for Linux: linux-workstation linux-remote`. Exit code 1.
5. **No partial state** — no install-deps, no stow.

**Edge cases:**
- *Unknown profile* (`profile=linux-laptop`) — same path: not in allowlist, same allowlist message.

#### Flow: `check-conflicts profile=linux-remote` standalone (preflight)

> Profile-aware preflight before committing to a setup.

1. **Caller** — `just check-conflicts profile=linux-remote`.
2. **Helper eval** — same resolution + validation + context derivation as `setup`.
3. **Walk** — iterates only directories `packages/common/{zsh,tmux,zellij,nvim,yazi,git,bash,bin}` and `packages/linux/zsh-linux`. Skips `sway`, `waybar`, etc.
4. **Report** — list of any conflicting paths with remediation hint, or silent success.

**Edge cases:**
- *User has stale workstation symlinks (`~/.config/sway/` pointing into the repo)* — these don't appear in the remote profile's package list, so check-conflicts ignores them. Migration story: `just unstow-all profile=linux-workstation` first. Documented in README.

---

## Technical Decisions

### Decision: Single `_profile-context` helper does resolve + validate + derive in one place

**Context:** Six recipes need profile-aware behavior. The shared work is identical: read the precedence chain, validate `OS:profile`, look up the package lists / bucket / install-deps recipe for the resolved profile. Inlining this in each recipe means ~12 lines of near-identical bash per recipe — drift waiting to happen, painful to maintain when adding a new profile (e.g., `mac-remote`).

**Decision:** A hidden helper recipe `_profile-context profile=""` does everything: resolves precedence, validates, looks up dispatch context, emits a sourceable assignment block (heredoc body of `var="value"` lines). Each profile-aware recipe `eval`s the output once at the top:

```bash
eval "$(just _profile-context "{{profile}}")"
```

**Rationale:**
- Single source of truth. Adding a new profile means editing one `case` statement in `_profile-context`, not six.
- Each profile-aware recipe is now ~3 lines of dispatch overhead (eval + own work), down from ~12.
- Failure modes (no profile, unknown profile, OS mismatch) are surfaced in `_profile-context` itself — its non-zero exit propagates through `eval` and `set -e`, aborting the caller. No duplication of error message construction.
- Standalone-debuggable: `just _profile-context linux-remote` echoes the assignments, easy to inspect.

**Consequences:**
- `eval` of a heredoc string requires confidence that the assigned values are shell-safe. Profile names are alphanumeric+hyphen; package lists are space-separated lowercase identifiers; bucket names are `linux`/`macos`; recipe names are `install-deps-*`. None contain shell metacharacters by construction. If a future addition introduces something exotic, switch to a more structured format (e.g., key=value with explicit shell-quoting).
- Adding a new profile-aware recipe means following the convention (eval at top). Convention is enforced by code review and by the visible pattern across six existing siblings.

### Decision: Profile is required (overrides PRD Resolved Decision #2)

**Context:** PRD originally locked in "linux-workstation is the default on Linux when no profile is given," preserving back-compat. During design review, the author raised: a profile-less invocation could silently install the wrong shape (remote on a workstation host, or workstation on a remote host) if the caller forgets a flag. This is hard to undo cleanly — partial stow + partial deps install across two profiles is messier than just refusing to start.

**Decision:** No OS-default fallback. `just setup` (and every other profile-aware recipe) with no `profile=` arg AND no `$DOTFILES_PROFILE` exits 1 with the valid-profiles-for-current-OS message. Workstation users either pass `profile=linux-workstation` explicitly or set `DOTFILES_PROFILE=linux-workstation` once in their shell rc.

**Rationale:**
- Safety > convenience for an install-time tool. The cost of "wrong install" is high (cleanup is manual); the cost of "type one extra arg" is low (one-time muscle memory cost, or a single `export` line in `~/.zprofile`).
- The loud-banner Must-Have already echoes the resolved profile — combined with required-explicit, the user always sees and confirms which install is happening.
- `bootstrap.sh` is unaffected because it always sets `DOTFILES_PROFILE=linux-remote` if unset before calling `just setup`. The script *is* the explicit choice on the bootstrap path.

**Consequences:**
- Overrides PRD Resolved Decision #2. PRD will need a corresponding update (or this design supersedes for downstream SPEC/build work).
- Workstation users see a one-time error if they forget to pass the profile after upgrading. The error message tells them exactly what to do.
- `just setup` invoked via shell completion or muscle-memory now requires a parameter; users who muscle-memorize `just setup` will hit the loud-fail once and adapt.

### Decision: Profile gates only at call sites, not inside downstream recipes

**Context:** PRD Resolved Decision #13 already pins this. Restated here because it's load-bearing for the design's clarity guarantee.

**Decision:** `install-deps-linux-workstation`, `install-deps-linux-remote`, `install-deps-mac-workstation`, `setup-sway-session`, `install-zellij`, `install-yazi`, `install-resvg`, `install-flatpaks`, `_stow-bucket`, `_unstow-bucket`, etc., have **no** awareness of profiles. They do exactly what their name says, and trust the caller to invoke them in the right context.

**Rationale:**
- A reviewer reading `install-deps-linux-remote` should not need to know about profiles to understand what it does.
- Each downstream recipe stays runnable on its own (`just install-deps-linux-remote` is valid even outside a `setup` invocation), useful for partial troubleshooting.
- Profile decisions live in `_profile-context` + the call-site case in `setup` (for `setup-sway-session` gating). Two places, both small and obvious.

**Consequences:**
- A user manually invoking `just setup-sway-session` on a remote box will run the sway installer regardless of profile. Acceptable: the recipe name is self-explanatory and the user is opting into the action explicitly.

### Decision: `check-conflicts` walks the resolved profile's package list, not the bucket directory

**Context:** Today's `check-conflicts` iterates `packages/$bucket/*/` — every directory inside `packages/linux/` etc. That's only correct because today every directory in the bucket is also stowed. Under profiles, a remote install skips most `linux/` directories.

**Decision:** `check-conflicts` accepts `profile=""`, eval's `_profile-context`, and walks only `(common_pkgs, os_bucket × os_pkgs)`.

**Rationale:**
- Without this change, a remote install on a machine with stale workstation files (`~/.config/sway/`, `~/.config/waybar/`) would falsely abort — bucket-walk would catch the conflict on a path the remote install was never going to touch.
- (Bucket-walk inspects a *superset* of the resolved profile's packages, so it can over-flag but not under-flag. Only the over-flag direction is at risk; framing matters because there's no "false-pass" risk.)
- Keeping `check-conflicts` standalone-runnable (`just check-conflicts profile=linux-remote`) gives a useful preflight without committing to setup.

**Consequences:**
- The find-and-collide loop's outer iteration becomes `for pkg in $resolved_pkgs` instead of `for pkg in packages/$bucket/*/`. Slightly more code; same algorithm.
- Stale workstation symlinks (from a prior workstation→remote migration on the same host) don't surface in remote check-conflicts output. Migration must run `unstow-all profile=linux-workstation` first. Documented in README.

### Decision: `bootstrap.sh` fails loud if `just` is missing (no auto-install)

**Context:** PRD Open Question. Could either (a) require `just` to be on PATH, or (b) auto-install via `https://just.systems/install.sh | bash -s --` on first run.

**Decision:** Fail loud with the exact install command in the error message. No auto-install.

**Rationale:**
- `curl | bash` is a footgun; doing it inside our own `bootstrap.sh` propagates that footgun into our default bootstrap path.
- The error message points at the exact install command, so the user runs it once and reruns `./bootstrap.sh`.
- Keeps `bootstrap.sh` <15 lines and trivially auditable.

**Consequences:**
- A truly fresh container (only `git`, `bash`, `curl`) needs two commands instead of one: `curl | bash` for `just`, then `./bootstrap.sh`. Acceptable.
- If a future remote env consistently lacks `just`, revisit. v1 ships fail-loud.

### Decision: Pre-merge verification is real-machine, not container

**Context:** PRD Must-Have specified a documented two-distro container acceptance test (Ubuntu + Fedora). During design review, the author flagged that v1 will be verified by running the install on the three real target machines: Linux workstation (Fedora dnf, `linux-workstation`), Mac workstation (Darwin, `mac-workstation`), remote (Ona = Ubuntu apt, `linux-remote`).

**Decision:** Drop the container test from the design's scope. Verification happens on real hardware: each profile runs on its target host before merging.

**Rationale:**
- The three-machine matrix exercises every code path: all three profiles, both Linux package managers, and the actual environments the dotfiles will be used in.
- Container-as-uid-0 tests can mask sudo edge cases that only show up on a real user account.
- One author, no CI, no pressure to scale verification beyond what the maintainer actually uses.

**Consequences:**
- Overrides PRD Must-Have for "Two-distro container acceptance test, runnable manually." PRD will need a corresponding update (or this design supersedes for downstream SPEC/build work).
- No copy-pasteable test command in the README. Verification protocol becomes "run `./bootstrap.sh` on your remote, run `just setup profile=linux-workstation` on the Fedora desktop, run `just setup profile=mac-workstation` on the Mac. All three should succeed."
- If the matrix ever grows (a second remote shape, a new Linux distro family), reconsider. Not v1.

### Tradeoffs Accepted

| Tradeoff | We're Accepting | In Exchange For | Why This Makes Sense |
|----------|-----------------|-----------------|----------------------|
| `eval` of helper output | `eval`'d strings must be shell-safe; we trust the helper's output format | Single source of truth for resolve+validate+dispatch; ~3-line recipes instead of ~12 | Output format is constrained: profile names alphanumeric+hyphen, no shell metacharacters in any emitted value by construction |
| Workstation users must specify profile (no OS default) | One-time muscle-memory cost; one-time fail-loud after upgrade | Eliminates "wrong install" failure mode; explicit confirmation of intent every time | Safety > convenience for an install tool; loud-fail message tells users exactly what to type |
| Helper subprocess cost | One `just _profile-context` fork per profile-aware recipe call (sub-millisecond) | Centralized dispatch; no duplicated logic | Cost is unobservable; alternative is 6× duplicated logic that drifts |
| `bootstrap.sh` requires `just` already installed | One extra command for a truly fresh container (`curl \| bash` for just) | No `curl \| bash` inside our own script; trivially auditable bootstrap | Error message points at exact install command |
| Workstation→remote on the same host needs explicit `unstow-all` first | Slight migration friction for the (rare) case of toggling between profiles on one box | `check-conflicts` doesn't need cross-profile awareness; profile lists stay independent | This is not the common path; one-line README note covers it |
| Real-machine verification, no container test | No copy-pasteable smoke test in README | Verification matches actual usage; covers sudo edge cases container-as-root would mask | Author has all three target machines; container test would be theatre |

---

## Alternatives Considered

### Alternative: `packages/remote/` as a fourth bucket

**Summary:** Create a sibling to `packages/{common, linux, macos}/` called `packages/remote/`. Configs that should land on remote envs go there.

**How it would work:**
- New top-level directory `packages/remote/`.
- `packages_remote := "..."` justfile var.
- Stow loop adds a fourth conditional branch: stow `remote` bucket when `profile=linux-remote`.

**Pros:**
- Profiles map 1:1 to filesystem buckets, which is visually clean.
- New remote-only configs have an obvious home.

**Cons:**
- Cross-cutting configs become awkward. `tmux` config is identical on workstation and remote; today it lives in `common/`. With a `remote/` bucket, you either duplicate it (drift inevitable) or keep it in `common/` and add a special "common is always stowed regardless of profile" rule that contradicts the bucket-as-profile mental model.
- `zsh-linux` is the canonical "mostly headless, sometimes used in workstation too" case. Putting it in `remote/` then auto-stowing on workstation breaks the bucket boundary.
- Doubles the placement decision: every new package needs both an OS classification (current axis) and a profile classification (new axis). Today the profile axis is captured implicitly by the package list, where most placement is mechanical.

**Why not chosen:** PRD Resolved Decision #1 and #5 lock in "profile is justfile-only, package buckets stay OS-only." Also: WRK-001 just settled the OS axis; reorganizing `packages/` again now would impose churn for low net gain.

### Alternative: Auto-detect remote env via known marker env vars

**Summary:** No `profile=` parameter, no `DOTFILES_PROFILE` env var. `setup` and `bootstrap.sh` detect remote-ness by sniffing `CODESPACES`, `REMOTE_CONTAINERS`, `GITPOD_WORKSPACE_ID`, Ona's marker (TBD), etc.

**How it would work:**
- `_detect-environment` shell helper runs first.
- Decision tree: if any sniff matches → `linux-remote`; else `linux-workstation` on Linux, `mac-workstation` on Darwin.

**Pros:**
- No flags to remember. `./bootstrap.sh` Just Works™ on every recognized env.

**Cons:**
- The env-var matrix is a moving target — Ona's marker is TBD, JetBrains Space's is unknown, custom devboxes won't set any of them. Detection misses are silent.
- Override-ability is essential for testing. Wanting to test the workstation path on a Codespaces box, or vice versa, becomes "comment out the env var in your shell" — fragile.
- Implicit detection violates the design's required-explicit posture (Decision: Profile is required).

**Why not chosen:** PRD Resolved Decision #3 pins `bootstrap.sh defaults to linux-remote unconditionally`, with explicit override available via `profile=`/`DOTFILES_PROFILE`. Auto-detection captured as Nice-to-Have for future tightening once we have ≥2 confirmed remote envs.

---

## Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| `_profile-context` output format ambiguity | Low — emitted values are shell-safe by construction (alphanumeric+hyphen profile names, alphanumeric package/bucket/recipe names). | Very low | Document the format in the helper's comment. If a future addition introduces shell-special characters, switch to a structured format. |
| Workstation user upgrades and hits no-profile fail-loud the first time | Low — error message tells them exactly what to type or export. | Medium (one-time) | README's "Migrating from previous behavior" note. Loud-fail is a feature here, not a bug. |
| `check-conflicts` package-list-aware change has subtle off-by-one | Medium — could incorrectly skip a package or fail on a phantom path. | Medium during the change; very low after | Real-machine verification on all three target hosts pre-merge. |
| `bootstrap.sh` `set -euo pipefail` masks a partial-success that real users would tolerate | Low — apt/dnf/install-zellij/install-yazi all have meaningful failure modes that should abort. | Low | Strict mode is correct posture. If a specific step proves flaky, add a recipe-level retry rather than relaxing global strict mode. |
| Cloud-shell `/etc/zshrc` interferes with our zsh setup (PRD Risk) | Medium — could double-bind keys or duplicate plugin loads. | Medium on Codespaces specifically | PRD-decided: do nothing in v1. Document. Add `unsetopt GLOBAL_RCS` in `.zshenv` only if observed. |
| Latent shell-config breakage on a third Linux distro (e.g., Debian 12 vs Ubuntu 24.04) | Low — package names rarely diverge for our CLI set. | Low | apt path uses package names common to recent Debian and Ubuntu. If a divergence shows up, add a per-distro guard at that point. |

---

## Integration Points

### Existing Code Touchpoints

- `justfile:1-5` — replace package-list vars (`packages_common`, `packages_linux`, `packages_macos`) with the five-list shape in Component Breakdown.
- `justfile:9-14` (`all` recipe) — add `profile=""` parameter; replace OS-conditional stow loop with `eval`-driven dispatch.
- `justfile:19-23` (`unstow-all` recipe) — same: profile parameter + helper eval.
- `justfile:26-29` (`restow` recipe) — same.
- `justfile:32-35` (`plan` recipe) — same.
- `justfile:45-86` (`check-conflicts` recipe) — add `profile=""` parameter; replace bucket-walk with package-list walk.
- `justfile:89-93` (`setup` recipe) — add `profile=""` parameter; loud-banner echo; dispatch to `install-deps-<profile>`; gate `setup-sway-session` on profile.
- `justfile:130-170` (`install-deps` recipe) — split into three: `install-deps-linux-workstation` (current Linux body), `install-deps-linux-remote` (new), `install-deps-mac-workstation` (current Darwin body).
- `justfile` (new lines) — add `_profile-context` hidden helper recipe.
- `packages/common/zsh/.config/zsh/conf.d/30-path.zsh` — zoxide guard.
- `packages/common/zsh/.config/zsh/conf.d/40-functions.zsh` — `zp` function `/workspaces/*` support.
- `packages/common/bash/.bashrc:29` — cargo source guard.
- `packages/linux/zsh-linux/.config/zsh/conf.d/os.linux/20-aliases.zsh` — vim alias guard.
- `bootstrap.sh` (new file at repo root).
- `README.md` — new "Remote profile" section. Contents (per PRD Must-Have, adjusted for design decisions): what `linux-remote` includes, how to invoke (`just setup profile=linux-remote`, `DOTFILES_PROFILE=...`, `./bootstrap.sh`), what's skipped (sway/waybar/etc., GRUB, NVIDIA, flatpak), the "PR welcome for new package managers" note, the resolution-precedence rule (`profile=` arg > `$DOTFILES_PROFILE`; **no OS default — explicit required**), how to recover from a leaked `DOTFILES_PROFILE` (`unset DOTFILES_PROFILE`), the workstation→remote migration story (`unstow-all profile=linux-workstation` first).

**Explicitly not touched:**
- `justfile:247-290` (`setup-sway-session`) — recipe body unchanged. Profile decides whether `setup` invokes it; the recipe itself stays profile-blind (PRD Should-Have / Resolved Decision #13).
- `justfile:293-301` (`reload`) — unchanged. Stays OS-keyed; existing `pgrep` guards already make it a no-op on hosts without sway/mako/waybar (PRD Resolved Decision #14).
- `packages/` directory layout — unchanged. Profile is a justfile concept (PRD Resolved Decision #1).

**Future extension hook:** Adding `mac-remote` later means (1) a new `packages_macos_remote` justfile var, (2) a `Darwin` allowlist update in `_profile-context`, (3) a `mac-remote` arm in the same helper's dispatch case, (4) a new `install-deps-mac-remote` recipe. No structural change to the dispatch mechanism. Confirms PRD's "architecture should not preclude `mac-remote`" Out-of-Scope note.

### External Dependencies

- **`apt-get` or `dnf`** — required on the Linux target. Failure mode is a clear "Unsupported package manager" error from `install-deps-linux-remote`.
- **`https://just.systems/install.sh`** — referenced from `bootstrap.sh`'s missing-`just` error message. Failure mode is the user follows the URL manually.
- **GitHub release downloads** — `install-zellij` and `install-yazi` already pull from GitHub releases. Already idempotent via `command -v`. Failure mode is `set -e` aborts; user reruns.

---

## Open Questions

Items deferred to SPEC or build phase:

- [ ] **`bootstrap.sh` shebang and POSIX-ness.** Current sketch uses `#!/usr/bin/env bash`. Is `sh` (dash on Debian) sufficient? `set -euo pipefail` and `: "${VAR:=default}"` work in bash and dash; `command -v` is POSIX. **Recommendation:** stick with bash for explicitness — `bash` is on every target env we care about.
- [ ] **`_profile-context` as a recipe vs. inline shell function.** Recipe form (current design) is debuggable standalone via `just _profile-context linux-remote`. Alternative: define a bash function in a `scripts/_lib.sh` and have each recipe `source` it. Recipe form has fewer files; sourced-function form runs faster (no fork). Recommendation: recipe form for v1 (simplicity); revisit if profile-aware recipes become hot paths (they don't).

---

## Design Review Checklist

Before moving to SPEC:

- [x] Design addresses all PRD Must-Have requirements (with explicit overrides documented for required-profile and real-machine verification).
- [x] Key flows are documented (5 flows: bootstrap-on-Ubuntu, workstation explicit, no-profile fail-loud, OS/profile mismatch, check-conflicts standalone).
- [x] Tradeoffs are explicitly documented in the Tradeoffs Accepted table.
- [x] Integration points with existing code identified down to file:line.
- [x] All Needs Attention items resolved (NA-1, NA-2, NA-3 — see Design Log).
- [ ] PRD updated to reflect design overrides (PRD Resolved Decision #2 → required profile; PRD Must-Have container test → real-machine verification). **Author action.**

---

## Design Log

| Date | Activity | Outcome |
|------|----------|---------|
| 2026-04-28 | Initial design draft (medium mode) | 1 chosen approach; 2 alternatives evaluated and rejected; 5 key decisions documented; 4 key flows traced |
| 2026-04-28 | Iteration on author review | Three changes applied: (1) replaced per-recipe boilerplate with single `_profile-context` helper that emits sourceable assignments; (2) made profile required (no OS default), overriding PRD #2; (3) dropped two-distro container acceptance test in favor of real-machine verification on three target hosts, overriding PRD Must-Have. NA-1 / NA-2 / NA-3 resolved. Status: Initial → In Review. |
