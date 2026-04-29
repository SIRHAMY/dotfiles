# Change: Remote-Profile Dimension for Dotfiles

**Status:** Draft
**Created:** 2026-04-27
**Updated:** 2026-04-28 (design-review iteration — see "Design overrides" note below)
**Author:** Hamilton Greene
**Builds on:** WRK-001 (cross-OS restructure — `packages/{common,linux,macos}/`, conf.d loader, `just setup`)

**Design overrides (2026-04-28):** Two decisions changed during design review and are reflected throughout this document. Both are tracked in the Resolved Decisions section.
1. **Profile is required.** Original PRD #2 said `linux-workstation` was the default on Linux. Flipped to "explicit profile required, no OS default" for safety — eliminates the "wrong install" failure mode. `bootstrap.sh` still defaults `DOTFILES_PROFILE=linux-remote` so `./bootstrap.sh` works without args.
2. **Pre-merge verification is real-machine, not container.** Original PRD Must-Have specified a documented two-distro container acceptance test. Flipped to "verify on the three real target hosts" (Linux workstation = Fedora dnf + `linux-workstation`; Mac workstation = `mac-workstation`; remote = Ubuntu apt + `linux-remote`) — naturally exercises every code path, no container-as-uid-0 sudo edge cases.

## TL;DR

- **Problem:** `just setup` currently treats Linux as "Fedora graphical workstation" — installs sway/waybar/mako/wofi/fontconfig, configures NVIDIA, edits GRUB, installs flatpak/Obsidian, runs `setup-sway-session`. Pointing it at a remote dev environment (Ona, devcontainer, Codespaces, plain SSH box) is a hard fail before the first useful symlink lands.
- **Solution:** Add a **profile dimension** orthogonal to the existing OS dimension. v1 profiles: `linux-workstation` (current Linux behavior), `linux-remote` (headless dev essentials only), `mac-workstation` (current macOS behavior). **Profile is required** — selected via `just setup profile=<name>` or `DOTFILES_PROFILE=<name>`; if both are empty, `just setup` fails loud with the valid profiles for the current OS (no OS default). A new `bootstrap.sh` entrypoint defaults `DOTFILES_PROFILE=linux-remote` if unset and shells out to `just`, so `./bootstrap.sh` works without args.
- **Architectural rule:** Profile is a **justfile-only bucket-selector**, not a fourth `packages/` directory. The existing OS axis stays. `linux-remote` skips workstation-only stow buckets (sway, waybar, mako, wofi, fontconfig, environment.d, bin-linux) and runs a stripped, package-manager-detecting `install-deps-linux-remote` (apt or dnf, no GUI deps, no GRUB/NVIDIA/flatpak).
- **Acceptance gate:** Real-machine verification on all three target hosts before merge. Linux workstation (Fedora dnf, `linux-workstation`), Mac workstation (`mac-workstation`), and a remote box (Ubuntu apt via Ona, `linux-remote`) each run their respective `just setup` (or `./bootstrap.sh` on remote) and arrive at a working interactive shell + nvim + tmux + zellij + git. No GRUB/NVIDIA/flatpak/sway side trips on remote. (Two-distro container test was the original gate; dropped during design review — see "Design overrides" above.)

## Problem Statement

WRK-001 made the dotfiles cross-OS by splitting `packages/{common,linux,macos}/` and introducing the `conf.d` loader pattern. That fixed the OS axis. But it left an implicit assumption baked into the Linux side: every Linux machine is the author's Fedora desktop with sway, NVIDIA, flatpak/Obsidian, and an X session.

Concretely, on a fresh Ubuntu/Debian remote dev environment (e.g., Ona, GitHub Codespaces, a plain VPS), running `just setup` today fails for at least these reasons:

1. **`install-deps` is dnf-only and copr-coupled.** `justfile:136` runs `sudo dnf copr enable atim/lazygit -y` unconditionally on Linux. No apt path. Hard fail on Debian-family.
2. **`install-deps` installs a desktop stack.** `justfile:137-141` installs `sway swaylock swayidle waybar mako wofi grim slurp brightnessctl playerctl gnome-keyring flatpak` and a fontconfig/font set. None of those exist on the remote box's package index, none are wanted, and they bloat install-time even on a forgiving distro.
3. **`setup-sway-session` runs unconditionally on Linux.** `justfile:93,247-290` installs a binary to `/usr/local/bin`, writes a wayland-session `.desktop` file, edits `/etc/default/grub`, and writes `/etc/modprobe.d/nvidia-drm.conf` if it sees an NVIDIA card. None of these are meaningful in a container or on a headless VM, and several will error.
4. **Workstation-only stow packages get linked anyway.** `packages_linux := "zsh-linux bin-linux sway swaylock waybar mako wofi fontconfig environment.d"` is the only Linux bucket. Even if `install-deps` succeeded, stow would still link sway/waybar/mako/wofi configs into a remote `$HOME` where they're dead weight.
5. **A few config-level hazards on non-Fedora Linux.**
   - `packages/linux/zsh-linux/.config/zsh/conf.d/os.linux/20-aliases.zsh` aliases `vim=vimx`, which is a Fedora `vim-X11` binary that doesn't exist on Debian. The alias *file* loads on any Linux, but invoking `vim` then errors. (This is the only os.linux-tagged file that's actually distro-specific rather than OS-specific.)
   - `packages/common/bash/.bashrc:29` sources `~/.cargo/env` unconditionally. Bash silently no-ops if missing; it's a latent bug, not a current break.
   - `packages/common/zsh/conf.d/40-functions.zsh` has a `zp()` project-jumper that hardcodes `$HOME/Code/*/`. Remote dev environments standardize on `/workspaces/*` (Codespaces, Ona, devcontainers). The function returns empty; not broken, but useless on remote.

The author wants this to work for "remote envs I use in future" — Ona is the immediate trigger but the architecture should generalize to any apt- or dnf-based headless box.

## User Stories / Personas

- **Hamilton (self), spinning up an Ona workspace.** Wants to clone the dotfiles and have a working zsh + nvim + tmux in under three minutes, no sudo theater, no GUI packages downloaded, no GRUB edits attempted. Same muscle memory as the Fedora desktop and the work Mac — same prompt, same keybinds, same nvim setup.
- **Hamilton (self), one year from now, on $next_remote_env.** Whatever the next remote dev product is (Codespaces, Devbox, JetBrains Space, a fresh EC2 box), the path is the same: `bootstrap.sh` (or `just setup profile=linux-remote`) and you're in. Adding support for a new shape of remote env should not require reorganizing the repo.

## Desired Outcome

`just setup profile=linux-remote` (or `DOTFILES_PROFILE=linux-remote just setup`, or `./bootstrap.sh` which defaults to `linux-remote`) on a clean Ubuntu/Debian or Fedora box arrives at a working interactive shell (zsh with prompt, zoxide, fzf, plugins), tmux, zellij, nvim with LazyVim, and git — and *only* those things. No sway, waybar, mako, wofi, fontconfig, flatpak, Obsidian, GRUB edits, NVIDIA detection, or sway-session install runs.

**Profile is required — there is no OS default.** `just setup` with no `profile=` arg AND no `$DOTFILES_PROFILE` exits non-zero with the valid profiles for the current OS. Workstation users either pass `profile=linux-workstation` (or `mac-workstation`) explicitly, or set `DOTFILES_PROFILE=...` once in their shell rc. `bootstrap.sh` defaults `DOTFILES_PROFILE=linux-remote` if unset before calling `just setup`, so `./bootstrap.sh` continues to work without args — the script *is* the explicit choice on the bootstrap path. (Original PRD #2 had `linux-workstation` as the implicit Linux default for back-compat. Flipped during design review for safety; see "Design overrides" above and Resolved Decision #2.)

The profile dimension lives entirely in the `justfile` (and in `bootstrap.sh`'s defaulting logic). `packages/` keeps its current `{common, linux, macos}` shape. The rule: **profile selects which buckets to stow and which `install-deps-*` to run; OS narrows further within those buckets.** A workstation install is a strict superset of a remote install of the same OS — anything `linux-remote` stows, `linux-workstation` also stows. This means workstation runs implicitly exercise the remote path, giving free coverage.

`linux-remote` profile rules:
- **Stow buckets:** `packages/common/{cli-safe-pkgs}` only. (See "Package classification" below.)
- **Skipped stow buckets:** `packages/common/ghostty`, `packages/linux/{sway, swaylock, waybar, mako, wofi, fontconfig, environment.d, bin-linux}`. The remote shell never sees these symlinks.
- **install-deps-linux-remote:** detects `apt-get` vs `dnf`, installs a tight CLI-only set (stow zsh tmux zoxide fzf neovim fd-find git curl + zsh-autosuggestions + zsh-syntax-highlighting), runs `install-zellij` (binary, portable), runs `install-yazi` (binary, portable). Skips `install-resvg` and `install-flatpaks`. Fails loud with a clear message on any other package manager.
- **setup-sway-session:** does not run.
- **conf.d snippets** stay OS-keyed (not profile-keyed). Workstation-specific shell config does not need a profile guard because workstation-only configs live in workstation-only stow buckets — they're never linked in a remote setup. (See "Architectural rule" in TL;DR.)

`bootstrap.sh` is a tiny shell entrypoint — non-interactive, defaults `DOTFILES_PROFILE` to `linux-remote`, exec's `just setup`. Its job is to be the one-line URL-pipe-to-bash that a remote env's setup hook (Ona's repo init, a Dockerfile RUN line) can call without arguments.

## Success Criteria

### Must Have (Pre-Merge Gate)

Verifiable before merge by running each profile end-to-end on its target host. Real-machine verification on the three target hosts (Linux workstation, Mac workstation, remote box) is the primary gate — see the "Real-machine pre-merge verification" item below.

- [ ] **`just setup profile=linux-remote` exists and is wired through.** Recipe accepts `profile` as a parameter. `DOTFILES_PROFILE` env var is read as a fallback when `profile=` is not passed. **No OS default** — empty arg + empty `$DOTFILES_PROFILE` exits non-zero with a clear "no profile specified, valid profiles for `<OS>` are …" message, listing only the profiles valid for the current OS.
- [ ] **`bootstrap.sh` exists at repo root.** Non-interactive. Defaults `DOTFILES_PROFILE=linux-remote` if unset. Exec's `just setup`. Idempotent on reruns.
- [ ] **`./bootstrap.sh` and `DOTFILES_PROFILE=linux-remote just setup` produce identical state** from a fresh clone. Both invocations are on the acceptance gate; bootstrap is not a thin wrapper that can drift from the just-side path.
- [ ] **OS/profile mismatch fails fast with a clear message.** Invoking `just setup profile=linux-workstation` on macOS, or `profile=mac-workstation` on Linux, or any unknown profile, exits non-zero with: `"Profile <X> is not valid for OS <uname>. Valid profiles for <uname>: ..."` and lists the allowlist for the current OS. No partial stow runs before the validation fires.
- [ ] **`setup` echoes the resolved profile** as its first line of output (e.g., `"Setup: profile=linux-remote (resolved from arg)"` or `"Setup: profile=linux-remote (resolved from $DOTFILES_PROFILE)"`). Source attribution is one of two strings (`arg`, `$DOTFILES_PROFILE`); there is no `OS default` source string anymore — that path now fails loud instead. Loud resolution prevents env-var-leak silent drift (e.g., a stray `DOTFILES_PROFILE=linux-remote` exported in a synced shell rc silently downgrading a workstation install).
- [ ] **`check-conflicts` is profile-aware.** Pre-flight walks only the buckets the resolved profile will stow. Otherwise the gate either falsely fails (reports a conflict for a workstation file that won't be stowed on remote) or falsely passes (skips checking a file that will be stowed). Same `profile=` plumbing as `setup`.
- [ ] **Package classification is explicit in the justfile.** Replaces the current three lists (`packages_common`, `packages_linux`, `packages_macos`) with profile-aware lists:
  - `packages_common_cli` — stowed for every profile (zsh tmux zellij nvim git bash bin yazi)
  - `packages_common_workstation` — stowed only for workstation profiles (ghostty)
  - `packages_linux_workstation` — stowed only for `linux-workstation` (zsh-linux bin-linux sway swaylock waybar mako wofi fontconfig environment.d)
  - `packages_linux_remote` — stowed only for `linux-remote` (zsh-linux only — keeps the linux-keyed conf.d snippets that include the cargo/opencode PATH guards and the zsh plugin source paths, both of which are valid on Debian/Ubuntu and Fedora alike)
  - `packages_macos_workstation` — stowed only for `mac-workstation` (zsh-macos aerospace sketchybar)
- [ ] **`install-deps` is split per profile.** `install-deps-linux-workstation` (current behavior, dnf-only, all GUI deps), `install-deps-linux-remote` (apt-or-dnf detect, CLI-only set, no copr, no flatpak, no fonts, no GRUB), `install-deps-mac-workstation` (current behavior). The dispatch happens in `setup`, keyed off the resolved profile.
- [ ] **Package-manager detection in `install-deps-linux-remote`** uses `command -v apt-get || command -v dnf`. apt-only and dnf-only branches are explicit. Any other PM (apk, pacman, zypper, …) fails loud with: `"Unsupported package manager. linux-remote v1 supports apt and dnf only. PRs welcome."`
- [ ] **`setup-sway-session` does not run on `linux-remote`.** The `setup` recipe gates it on profile, not OS.
- [ ] **vim alias is OS-keyed but distro-guarded.** `packages/linux/zsh-linux/.config/zsh/conf.d/os.linux/20-aliases.zsh` either drops `alias vim=vimx` or guards it with `command -v vimx >/dev/null && alias vim=vimx`. Latter preferred — fixes the latent Debian break for free.
- [ ] **`.bashrc` cargo guard.** `packages/common/bash/.bashrc:29` becomes `[ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"`. Aligns with the zsh equivalent.
- [ ] **`zp` function supports `/workspaces/*` in addition to `~/Code/*`.** `packages/common/zsh/.config/zsh/conf.d/40-functions.zsh` walks both roots (whichever exists). Keeps muscle memory across local and remote.
- [ ] **zoxide-init guard.** `packages/common/zsh/.config/zsh/conf.d/30-path.zsh:4` becomes `command -v zoxide >/dev/null && eval "$(zoxide init zsh)"` so a remote env where zoxide install was deferred or failed does not break shell startup. (Belt-and-braces; install-deps-linux-remote installs zoxide, but the shell snippet should not assume.)
- [ ] **Real-machine pre-merge verification on three target hosts.** Each profile runs end-to-end on its actual target before merge:
  - **Linux workstation (Fedora dnf, `linux-workstation`):** `just setup profile=linux-workstation` from a fresh checkout. Full GUI install + `setup-sway-session` runs. `just reload` works.
  - **Mac workstation (`mac-workstation`):** `just setup profile=mac-workstation` from a fresh checkout. brew installs all deps; AeroSpace and SketchyBar configured.
  - **Remote (Ubuntu apt via Ona, `linux-remote`):** `./bootstrap.sh` from a fresh clone. CLI deps install via apt; no GRUB/NVIDIA/flatpak/sway. Second `./bootstrap.sh` is idempotent. `zsh -i` produces working prompt + plugins; `nvim`, `tmux`, `zellij`, `git` on PATH.
  - All three machines must exit 0 and produce a usable interactive shell. (The original gate was a documented two-distro container test; dropped during design review — three real machines naturally cover all three profiles + both Linux PMs, and avoid container-as-uid-0 sudo edge cases. See "Design overrides" above.)
- [ ] **README updated.** New "Remote profile" section: what `linux-remote` includes, how to invoke (`just setup profile=linux-remote`, `DOTFILES_PROFILE=...`, `./bootstrap.sh`), the explicit list of what's skipped (sway/waybar/etc., GRUB, NVIDIA, flatpak), the "PR welcome for new package managers" note, the resolution-precedence rule (`profile=` arg > `$DOTFILES_PROFILE`; **no OS default — empty + empty fails loud**), a "How to recover from a leaked `DOTFILES_PROFILE`" note showing `unset DOTFILES_PROFILE` and how to confirm the resolved profile via `setup`'s first-line echo, and a "Migrating between profiles on the same host" subsection (`just unstow-all profile=linux-workstation && just setup profile=linux-remote`) for the workstation→remote case.

### Should Have

- [ ] **`just plan profile=linux-remote`** dry-runs the remote profile from any machine (workstation or remote), useful for verifying the bucket selection is correct before pushing a change. Mirrors the existing `just plan` behavior, profile-aware.
- [ ] **`unstow-all` profile-aware.** Invoking `just unstow-all profile=linux-remote` on a remote env unwinds only what was stowed. Today `unstow-all` references the all-Linux package list and would error on packages that were never linked. (Stow's `-D` is forgiving for missing links, but cleaner to gate on profile.)
- [ ] **`setup-sway-session` extracted from `setup`'s inline call site only via profile gate, not by changing the recipe itself.** `setup-sway-session` stays as-is (a clean system-level installer). The profile decision lives at the call site in `setup`: `if [ "$profile" = "linux-workstation" ]; then just setup-sway-session; fi`. Same pattern as the install-deps dispatch — gates live in `setup`, not in each downstream recipe.

### Nice to Have

- [ ] **Auto-detect remote profile in `bootstrap.sh`.** Sniff `CODESPACES`, `REMOTE_CONTAINERS`, `GITPOD_WORKSPACE_ID`, Ona's marker (TBD — confirm the actual env var) and elevate detection to "this is remote, default to linux-remote." v1 keeps the explicit default-to-remote behavior; auto-detect is a tightening once we have ≥2 confirmed env shapes.
- [ ] **CI matrix.** Wire a container-based smoke test (a recreation of the originally-planned two-distro test, or equivalent) into GitHub Actions on push so a workstation-side change can't silently break remote install when the maintainer doesn't manually re-verify on real machines. Out of v1 because there's no CI on this repo today; adding it is a separate scope. Real-machine verification covers v1; CI is a hedge for future drift.
- [ ] **Stripped `bin-remote` package** if/when portable scripts emerge that warrant grouping. Today `packages/common/bin` is empty (.gitkeep) and all `bin-linux` scripts are sway-coupled; nothing to put in remote-bin.

## Scope

### In Scope

- Adding `profile` as a `just setup` parameter and `DOTFILES_PROFILE` env-var fallback. Three v1 profiles: `linux-workstation`, `linux-remote`, `mac-workstation`. Profile is required (no OS default — empty arg + empty env fails loud).
- Restructuring `packages_common` / `packages_linux` / `packages_macos` justfile vars into the cli/workstation split described above.
- Splitting `install-deps` into `install-deps-linux-workstation`, `install-deps-linux-remote`, `install-deps-mac-workstation`. `linux-remote` detects apt vs dnf; the others stay single-PM.
- `bootstrap.sh` at repo root — minimal entrypoint that defaults to `linux-remote` and exec's `just setup`.
- Three small shell-config hardenings: zoxide guard, cargo guard in `.bashrc`, `zp` function `/workspaces/*` support, vim-alias `vimx`-guard.
- README "Remote profile" section (without a container test block — verification is on real hardware).
- Verifying by running `just setup` (or `./bootstrap.sh` on remote) on all three target hosts: Linux workstation, Mac workstation, remote.

### Out of Scope

- **`mac-remote` profile.** Running these dotfiles on a remote Mac (CI runner, Mac mini colo) is a real shape but not a current need. Architecture should not preclude it — adding `mac-remote` later means another `packages_macos_remote` list and a `install-deps-mac-remote` recipe — but no design or test work for it in v1.
- **Auto-detection of remote env in `bootstrap.sh`.** v1 defaults to `linux-remote` unconditionally because that's what `bootstrap.sh` is for. Sniffing `CODESPACES`/`REMOTE_CONTAINERS`/Ona env vars is Nice-to-Have.
- **Alpine, Arch, openSUSE, NixOS support.** apk/pacman/zypper detection is YAGNI. Fail loud with a clear "PRs welcome" message and revisit if and when one of these becomes a real env.
- **Windows / WSL.** Not a current need. WSL would land under `linux-remote` with apt detection; Windows native is a separate axis.
- **CI for any kind of automated install verification.** v1's gate is real-machine verification on the three target hosts. Adding container-based or GitHub Actions CI is a follow-up.
- **Migrating to chezmoi/home-manager/nix/devbox.** Stow stays.
- **Reworking nvim, zellij, tmux, or any tool's behavior** beyond what remote-compat demands (zoxide guard, vim-alias guard). Behavior changes are a separate change.
- **Per-machine `conf.d/local/` slot for remote-only secrets, identity, or proxy config.** Includes shell secrets, machine-local credentials, proxy config, **and per-env git identity (managed vs. personal `user.email`)**. Deferred unless a concrete env requires it. Today the `git` stow package's identity is shared across all envs; GitHub attributes commits to whichever account has the email registered, so shared identity usually works. If a managed GitHub org's SSO/compliance ever rejects a commit, cut a follow-up change.
- **Auditing `install-deps-linux-remote` for byte-perfect idempotency on partial reruns.** apt and dnf are idempotent for repeat installs; binary-installer recipes already guard with `command -v`. Good enough for v1.

## Non-Functional Requirements

- **Reliability:** `bootstrap.sh` and `just setup profile=linux-remote` are idempotent. Re-running on a partially-set-up remote produces no errors and no duplicate symlinks. The existing `check-conflicts` pre-flight covers stow-side idempotency; PM-side idempotency is delegated to apt/dnf.
- **No-sudo-explosion:** `linux-remote` issues exactly one `sudo` invocation — the package-manager install. No GRUB edits, no `/usr/local/bin` writes, no modprobe.d writes, no `/usr/share/wayland-sessions/*` writes. (sway-session install is workstation-only.)
- **Fail-safe shell:** All shell-config hardenings (zoxide guard, vim-alias guard, cargo guard) preserve the rule that a missing tool or a malformed snippet must not abort shell startup. Same NFR as WRK-001.
- **Speed:** Stow + shell-config work in `bootstrap.sh` is sub-second. End-to-end runtime is dominated by `apt-get`/`dnf install` and the binary-installer `curl` fetches (zellij, yazi); both are network-bound and not bounded by this PRD. No speed promise beyond "the dotfiles steps don't add appreciable time on top of the package manager."
- **Portability of the remote profile:** `linux-remote` works on apt-based and dnf-based distros without code changes. New distro families (apk, pacman, etc.) require a localized addition to `install-deps-linux-remote`'s package-manager dispatch — no other recipe changes.

## Constraints

- **Keep using stow.** No switch to a different dotfile manager.
- **Keep using `just`.** No switch to make/scripts.
- **No CI dependency.** v1 ships without CI; the gate is real-machine verification on the three target hosts. Adding CI (container-based or otherwise) is a follow-up change.
- **No new tools introduced.** Remote profile uses tools already managed by the repo (zsh, tmux, zellij, nvim, yazi, etc.). Adding a "remote-only" tool is a separate change.
- **No post-clone network git operations during install.** `install-deps-linux-remote` and the stow path may not invoke `git submodule`, `git fetch`, or any other git network call after the initial clone. Keeps the install path agent-forwarding-independent and fast in offline-after-clone envs. Verifiable by inspecting the recipes.
- **Solo maintainer.** No external review process.

## Dependencies

- **Depends on:**
  - WRK-001 (cross-OS restructure) — already merged. The `packages/{common,linux,macos}/` taxonomy and `conf.d` loader are prerequisites.
  - apt-get or dnf available on the target Linux box. Containers, VMs, SSH boxes, and cloud-shell envs all have one or the other in practice.
  - `git`, `curl`, and `just` available. `bootstrap.sh` does not bootstrap `just` itself; the missing-`just` error message points at the canonical install one-liner (`https://just.systems/install.sh`).
- **Blocks:**
  - Any future remote-env-specific tuning (Codespaces-specific shell tweaks, Ona-specific snippets) — cleanest to land the profile mechanism first.

## Risks

- [ ] **Profile resolution ambiguity.** Both `profile=` (just arg) and `DOTFILES_PROFILE` (env var) are sources. Risk: one overrides the other unexpectedly. **Mitigation:** justfile reads `profile` arg first, falls back to `DOTFILES_PROFILE`; if both are empty, fails loud (no OS default). Loud-banner echoes the source on every `setup` call so any override is immediately visible. Document precedence + recovery (`unset DOTFILES_PROFILE`) in the README.
- [ ] **Bucket misplacement: workstation-only thing lands in `common/cli` and breaks remote.** A future PR adds a tool to `packages_common_cli` that turns out to need a graphical lib (e.g., a yazi previewer, a clipboard tool that pulls in X). Remote install starts dragging in dependencies again. **Mitigation:** real-machine verification on the remote target host, run before merging any change that touches `install-deps` or `packages_common_cli`. The placement rule (Resolved Decision #5) is what's enforced; profile lists are allowed to diverge by design. (Future hedge: a CI smoke test — see Nice-to-Have CI matrix.)
- [ ] **conf.d snippet leak.** Someone adds an aerospace-specific snippet to `packages/common/zsh/conf.d/` instead of `packages/macos/zsh-macos/conf.d/os.darwin/`. The snippet sources on linux-remote and prints noise (or breaks). **Mitigation:** explicit rule in README's "Remote profile" section: workstation-specific shell config goes in workstation-OS buckets, never `common/`. The architectural rule from TL;DR — profile-awareness is via stow buckets, not snippet guards — depends on this discipline.
- [ ] **Cloud-shell `/etc/zshrc` interference.** Codespaces and similar ship a system-wide `/etc/zshrc` that vendors plugins or sets options. ZDOTDIR doesn't suppress it (`/etc/zshrc` runs first). Conflicts between system zsh-autosuggestions and our zsh-autosuggestions could double-bind keys. **Mitigation:** do nothing in v1. Document the risk. Add `unsetopt GLOBAL_RCS` in `.zshenv` only if a concrete breakage is observed on a real remote env.
- [ ] **`bootstrap.sh` distributed via `curl | bash` is a footgun.** Anyone who pastes a one-liner runs whatever the repo's `bootstrap.sh` says. **Mitigation:** README does not promote `curl | bash`. The intended usage is `git clone && ./bootstrap.sh` — explicit, auditable. Document this preference.
- [ ] **`vim` alias guard masks a missing-vim install.** With `command -v vimx >/dev/null && alias vim=vimx`, an environment with neither `vim` nor `vimx` falls through to "command not found" only when the user types `vim`. Probably fine but worth flagging. **Mitigation:** none needed; this is the correct fail-mode. (Remote should typically use `nvim` anyway.)

## Resolved Decisions

Items decided during initial drafting and self-critique (see "Open Questions" for items still open, "Needs Attention" for directional items the author should weigh in on):

1. **Profile is a justfile-only concept, not a fourth `packages/` bucket.** Confirmed: a `packages/remote/` directory would force awkward placement of cross-cutting configs (e.g., where does tmux config go if it's identical on remote and workstation? — it stays in `common/`, where it lives today). Profile selects which existing buckets to stow.
2. **Profile is required — no OS default.** `just setup` (and every other profile-aware recipe) with no `profile=` arg AND no `$DOTFILES_PROFILE` exits 1 with the valid-profiles-for-current-OS message. Workstation users either pass `profile=linux-workstation` (or `mac-workstation`) explicitly, or set `DOTFILES_PROFILE=...` once in their shell rc. `bootstrap.sh` defaults `DOTFILES_PROFILE=linux-remote` if unset, so `./bootstrap.sh` works without args. **Rationale:** safety > convenience for an install-time tool. The cost of "wrong install" (full GUI deps on a headless box, or vice versa) is high — partial stow + partial deps install across two profiles is messy to undo. Forcing an explicit choice eliminates that failure mode. Combined with the loud-banner echo, the user always sees and confirms which install is happening. Loses one-time muscle memory cost (`just setup` no longer Just Works on Linux); gain is "no path silently does the wrong install." (Originally PRD said `linux-workstation` was the implicit Linux default for back-compat; flipped during 2026-04-28 design review.)
3. **`bootstrap.sh` defaults to `linux-remote` unconditionally.** No env-var sniffing in v1. The script's purpose is to be a remote-friendly entrypoint; defaulting to remote is the whole point.
4. **v1 supports apt + dnf only.** apk, pacman, zypper, and other package managers fail loud with a "PRs welcome" message. Layer on as actual envs need them.
5. **Profiles are independent shapes, not a containment hierarchy.** `linux-workstation` and `linux-remote` are two different selections that happen to share `common/cli`. They are *not* required to be in a strict-superset relationship — workstation may have things remote doesn't (graphical tools, by design), and remote may have things workstation doesn't (remote-specific ergonomics, if any ever emerge). The placement rule is the one to enforce: headless-and-shared → `common/cli`; needs-a-desktop → `<os>/workstation`; remote-specific → `linux/remote`. Drift between the profile package lists is allowed and expected; the bucket placement is what matters. (Earlier drafts of this PRD claimed strict-superset; that was overengineered and is dropped.)
6. **conf.d snippets stay OS-keyed, not profile-keyed.** Workstation-only shell config lives in `packages/{linux,macos}/<workstation-pkg>/conf.d/os.<osname>/`. No profile guards inside snippet bodies. Same architectural principle as WRK-001's "no in-body OS conditionals."
7. **`yazi` is in `packages_common_cli`, not workstation-only.** yazi itself is a CLI file manager that works headless. Image previews via `resvg` are best-effort and a separate install step (`install-resvg`) that runs only on workstation profiles. Remote yazi just won't do image previews.
8. **`mac-remote` is explicitly out of scope.** No code, no architecture concession beyond "the design doesn't preclude adding it later by adding a `packages_macos_remote` list."
9. **Profile resolution precedence is `profile=` arg > `$DOTFILES_PROFILE` env > fail-loud.** First non-empty wins. If both are empty, exit 1 with the valid-profiles-for-current-OS message — there is no OS default (see Decision #2). `bootstrap.sh` only sets `DOTFILES_PROFILE` if unset (does not clobber a pre-existing value). The `setup` recipe's first-line echo loudly states the resolved profile and where it came from (`arg` or `$DOTFILES_PROFILE`), so an env-var leak is visible at run time rather than silent.
10. **`ghostty` config stays in `packages_common_workstation`.** Stowing a config for a binary that doesn't exist is harmless (a dangling-but-irrelevant symlink), but conceptually noise. Keep it in workstation for clarity; promotes to `cli` only if a remote env actually uses ghostty.
11. **`bootstrap.sh` does not install `just`; the missing-`just` error message points at `https://just.systems/install.sh`.** Caller is responsible for installing `just` first. The error message is the single canonical install hint (consistent across the missing-just path and any future docs). `curl | bash` from inside our own bootstrap script is a footgun we don't propagate. (Container acceptance test was the original load-bearing use of this install command; with the test dropped, this decision now only governs the bootstrap.sh error message and any README install hint.)
12. **Recipe-level dispatch in `setup`.** Profile-to-package-list mapping is a shell `case` inside the `setup` recipe (and `check-conflicts`, etc.) that sets `PKGS` and `INSTALL_DEPS_RECIPE` before a single stow loop. Avoids `just`'s string-only variable model trying to do list math. (Resolves the "just variable substitution" architectural concern.)
13. **Profile gates live at call sites in `setup` (and the few other profile-aware recipes), not inside downstream recipes.** `setup-sway-session`, `install-deps-linux-workstation`, `install-deps-linux-remote`, etc., all stay clean recipes that do what their name says. The profile decision is made once, in `setup`, and dispatches to the right downstream call. Trusts the user not to invoke a workstation-only recipe by hand on a remote box, but also keeps each recipe simple and runnable on its own.
14. **`reload` stays OS-keyed, not profile-keyed.** `reload` only does anything for sway/mako/waybar (linux-workstation tools). On remote those tools aren't installed, so the existing `pgrep` guards already make `reload` a no-op. Adding profile dispatch here would change behavior in zero cases. (Profile gates apply where they affect what runs; not as a stylistic global.)
15. **Per-env git identity (managed email vs. personal email) is deferred.** GitHub attributes commits to whichever account has the commit email registered, so a shared email can still attribute correctly in most cases. If a managed GitHub org's SSO/compliance check ever rejects a commit, cut a follow-up change for a `conf.d/local/`-style include slot. Not v1.

## Open Questions

Implementation-phase items that can be decided during SPEC or build:

- [x] ~~**Does `bootstrap.sh` install `just` if missing?**~~ *Resolved during 2026-04-28 design review (see Resolved Decision #11): no auto-install. `bootstrap.sh` fails loud with the install hint in the error message.*
- [ ] **Ona's actual environment-detection signal?** TBD — confirm the env var(s) Ona sets so a future Nice-to-Have auto-detect (`bootstrap.sh` sniffing) can key on it. Not blocking v1.

## References

- WRK-001 PRD: `changes/WRK-001_cross-os-restructure/WRK-001_cross-os-restructure_PRD.md` — establishes the cross-OS architecture this builds on.
- Current `justfile`: lines 1-5 (package lists), 89-93 (setup), 130-170 (install-deps), 247-290 (setup-sway-session) — the surface area this change rewrites.
- Current `packages/common/`: `zsh, tmux, ghostty, zellij, nvim, yazi, git, bash, bin` (file `ls` confirmed).
- Current `packages/linux/`: `bin-linux, environment.d, fontconfig, mako, sway, swaylock, waybar, wofi, zsh-linux`.
- Current `packages/macos/`: `aerospace, sketchybar, zsh-macos`.
- Files needing small hardenings: `packages/common/zsh/.config/zsh/conf.d/30-path.zsh` (zoxide guard), `packages/common/zsh/.config/zsh/conf.d/40-functions.zsh` (zp `/workspaces/*` support), `packages/common/bash/.bashrc:29` (cargo guard), `packages/linux/zsh-linux/.config/zsh/conf.d/os.linux/20-aliases.zsh` (vim-alias guard).
- Ona: <https://ona.com> (the immediate trigger for this change; Debian-based remote dev environment).
- Comparable remote envs: GitHub Codespaces (devcontainer-based), Gitpod, Coder, plain SSH boxes.
