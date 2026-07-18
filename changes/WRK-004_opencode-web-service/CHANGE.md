# Change: Reliable OpenCode Web service

**ID:** WRK-004
**Status:** In Progress
**Created:** 2026-07-17

## Problem

OpenCode's browser UI is useful for cross-device agent monitoring, but a manually started server is easy to lose and bare terminal invocations create separate backends. The Linux dotfiles need to make one private, recoverable OpenCode server the shared endpoint for terminal and tailnet browser clients without putting credentials in the public repository. `(user)`

## Why now

OpenCode Web has been validated as the desired cross-device session layer; reliability and a secure default boundary are prerequisites for using it day to day. `(user)`

## Approach

Add a Linux-only stow package installed by both workstation and remote profiles. It provides a restart-supervised `systemd --user` `opencode serve` service bound to loopback and an `oc` command that starts the service idempotently, waits for its authenticated health endpoint, and attaches an interactive TUI using the current worktree. `serve` is the service command because the v1.18.3 server includes the browser route without `web`'s browser-launch side effect. Both processes read the same private, mode-restricted environment file without printing its password, though automatic shell permission means an agent can access that inherited environment. A public lower-precedence `config.json` sets automatic permissions and disables sharing while preserving a user's existing higher-precedence `opencode.json` or `opencode.jsonc`; setup detects policy conflicts rather than overwriting them. Both Linux profiles validate OpenCode and user-systemd, reload and enable the stowed user service, and enable lingering. Only `linux-workstation` validates Tailscale and configures persistent private `tailscale serve --bg http://127.0.0.1:4096`; `linux-remote` is local-only and never requires or invokes Tailscale. Documentation covers profile-scoped prerequisites, existing-config migration, session recovery, and manual smoke checks. The dedicated package avoids `bin-linux`, which remote profiles intentionally omit. (`README.md:3`, `README.md:553-557`; `justfile:119-151`; OpenCode v1.18.3 `config.ts`, `server/auth.ts`)

**Key decisions:**

- **Decision-1 (supervised shared server):** Run one `systemd --user` server per Linux machine over a terminal-spawned server per session. Browser and terminal clients must share one live backend, and systemd provides restart and logs. `(user)`
- **Decision-2 (interactive attach only):** Ship `oc` over a scripted `ocrun` entry point. Initial use is human-steered; noninteractive task execution is deferred until it earns a separate safety model. `(user)`
- **Decision-3 (private loopback endpoint):** Bind OpenCode to loopback and expose it only through Tailscale Serve over binding it directly to a LAN or tailnet interface. This narrows the server's control-plane exposure. `(user)`
- **Decision-4 (public config, private secret):** Commit a secret-free unit and example only; require a mode-restricted local environment file for credentials. This repository is explicitly public-config-only. (`README.md:5`)
- **Decision-5 (fail-loud prerequisites):** Verify OpenCode, Tailscale, and a working user systemd manager before use over expanding `just setup` to install third-party tools. Existing dependency recipes install neither service. (`justfile:278-324`)
- **Decision-6 (service daemon):** Use `opencode serve` over `opencode web` in the user unit. The server retains the Web UI route while avoiding an attempt to open a browser from a background service. (OpenCode v1.18.3 `cmd/serve.ts`, `httpapi/server.ts`)
- **Decision-7 (trusted automatic permissions):** Configure `permission: {"*": "allow"}` over an ask-first policy. The user accepts the account-control risk for trusted agents/providers and keeps exposure limited by loopback binding, private Tailscale access, disabled public sharing, and a private password. `(user)`
- **Decision-8 (persistent remote availability):** Require user-service lingering and a persistent Tailscale Serve route over availability only while an interactive shell remains open. Phone access must survive logout. (systemd `loginctl`; Tailscale Serve docs)
- **Decision-9 (layered config migration):** Stow public defaults as lower-precedence `~/.config/opencode/config.json`, leaving existing `opencode.json` or `opencode.jsonc` in place. Before Stow, setup validates and backs up a conflicting `config.json`, then moves it to `opencode.json` or deep-merges it below an existing `opencode.json`; `opencode.jsonc` remains unchanged. OpenCode v1.18.3 deep-merges those files in order, preserving user-specific settings without copying them into the public repository; setup reports conflicting higher-precedence sharing or permission policies. (OpenCode v1.18.3 `config.ts`)
- **Decision-10 (profile-scoped tailnet exposure, superseding Decisions 3, 5, and 8):** Both Linux profiles provision the local OpenCode user service and lingering. Only `linux-workstation` requires connected Tailscale and creates the persistent private Serve route; `linux-remote` neither invokes nor requires Tailscale or a tailnet. This keeps the remote profile usable on headless hosts without widening its network dependency. `(user)`
- **Decision-11 (verified official OpenCode installation, superseding Decision 5 for OpenCode):** Every setup profile downloads OpenCode's pinned v1.18.3 official installer to a private temporary file, verifies its committed SHA-256 from the tagged source, then runs it with a system-only `PATH` and verifies the executable at `~/.opencode/bin/opencode`. Do not use Homebrew: its executable path conflicts with the Linux service contract; macOS zsh adds the official install directory to `PATH`. `(user)`

## Checklist

- [x] Define the secret boundary and OpenCode defaults: private password environment file used by both service and helper, sharing disabled, and the explicit global `permission: {"*": "allow"}` policy; detect, back up, and merge any existing global OpenCode config before stowing it.
- [x] Add a Linux-only `opencode-web` stow package with a loopback-bound, restart-supervised `systemd --user` OpenCode server unit that terminates its process group on stop and resolves the documented OpenCode executable without an interactive-shell PATH.
- [x] Add the interactive `oc` helper that verifies prerequisites, starts the service, reads the private environment file without logging it, waits for authenticated health, and attaches to the current working directory.
- [x] Verify `opencode-web` participates in both Linux profiles' existing Stow conflict checks.
- [x] Document prerequisites, user-service lingering, one-time persistent Tailscale Serve setup targeting `127.0.0.1:4096`, intended-device ACL restriction, install/enable commands, normal worktree/session use, recovery, archival, and log inspection.
- [x] Correct setup profile scope: both Linux profiles stow and provision the OpenCode user service; only `linux-workstation` validates and configures persistent Tailscale Serve, while `linux-remote` remains local-only.
- [x] Install pinned OpenCode v1.18.3 through a SHA-256-verified official installer for `linux-workstation`, `linux-remote`, and `mac-workstation`; isolate the installer from Homebrew/global `PATH` entries, assert the exact executable/version contract at `~/.opencode/bin/opencode`, and add that macOS path to zsh.
- [ ] [e2e] Add and run a manual smoke-verification procedure for prerequisite failures, config migration, idempotent authenticated attach, shared Web/TUI session visibility, restart persistence, post-logout availability, and private-tailnet phone access.

## Done when

`just setup` installs OpenCode v1.18.3 at `~/.opencode/bin/opencode` for every supported profile without using Homebrew. On a Linux host with the documented remaining prerequisites, it installs the OpenCode integration without overwriting an existing config; `oc` starts or reuses one local service and attaches it to the current worktree; the same session is visible in OpenCode Web over the private tailnet after logout; a service restart preserves its history; and no secret appears in the repository or stowed files.

**e2e/obs:** e2e: [e2e] manual smoke-verification procedure · obs: documented `systemctl --user status` and `journalctl --user` recovery commands

## Open Questions

- [x] **SAFETY ACK: remote control authority:** An authenticated tailnet client can use the OpenCode server as the local Unix account, including responding to permission requests. The user explicitly accepts automatic permissions for trusted agents/providers and will limit access with loopback binding, private Tailscale ACLs, disabled public sharing, and a private password. (OpenCode permissions docs; user)
- [x] **SAFETY ACK: agent-visible password:** With `permission: {"*": "allow"}`, an agent can run a shell command that reads `OPENCODE_SERVER_PASSWORD` from its inherited environment and sends it elsewhere. The user accepts this as part of the trusted-agent threat model; private file permissions do not mitigate it after the server starts. (OpenCode v1.18.3 shell tool; user)

## Followups

- **[followup]** Build a separate task-status board that links work items to OpenCode sessions and renders last-message timestamps. `(user)`
<!-- plan-critic: ran 2026-07-17 sha=cc801edb -->
