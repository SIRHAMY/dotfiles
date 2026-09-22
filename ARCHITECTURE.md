# Architecture

This repo makes development environments repeatable across workstations and remote machines. Git owns reviewed defaults; applications can maintain mutable state; EFS intentionally shares selected live state between machines. Keep these boundaries explicit when changing setup.

The [README](README.md) contains commands and operational details. This document records the major choices and their reasons; update it when those choices change.

## Machine requirements

| Profile | Needs | Boundary |
| --- | --- | --- |
| `linux-workstation` | Fedora CLI tools, Ghostty, Sway desktop, OpenCode Web through Tailscale | Full interactive workstation |
| `mac-workstation` | Homebrew CLI tools, Ghostty, AeroSpace desktop | macOS equivalents of the shared environment |
| `linux-remote` | Headless CLI tools on apt/dnf systems, OpenCode backend, AI config, optional EFS | No desktop packages or Tailscale dependency |

Desired Codex coverage is CLI on every profile and desktop app on workstations only. **Not fully implemented:** Linux profiles install the CLI; macOS CLI and desktop app installation are not managed here yet. The Codex version-pinning policy remains undecided.

## Setup and ownership

[justfile](justfile) resolves an explicit profile, installs dependencies, checks conflicts, stows packages, then provisions profile-specific services. `profile=` overrides `DOTFILES_PROFILE`; missing selection fails. [bootstrap.sh](bootstrap.sh) defaults to `linux-remote` for remote provisioning.

Public OS/tool configuration lives here. Common packages plus OS-specific packages compose each profile; Stow links them into the home directory. Filesystem-based OS separation keeps shared config readable. Preserve the [loader contract](README.md#3-loader-contract--5-rules) when extending it.

Private `ai-dotfiles` owns portable agent instructions, skills, and preferences. Only the remote profile automatically runs [setup-ai-dotfiles.sh](scripts/setup-ai-dotfiles.sh), then [setup-efs-state.sh](scripts/setup-efs-state.sh). Workstations manage AI configuration separately. Keeping installation here and AI defaults there avoids duplicating ownership.

## Git, EFS, and machine-local state

| Home | Purpose |
| --- | --- |
| Git | Reviewed, reproducible defaults and portable preferences; never credentials |
| EFS | Live mutable configuration and useful history/session state, writable by connected machines without a Git round trip |
| Machine-local | Host-specific paths, trust decisions, services, caches, runtime databases, and long-lived credentials |

EFS sharing is intentional, not merely a backup. It does not provide application-level conflict resolution for concurrent writers. Revocable login tokens may also be shared on a single-user EFS volume; never commit them.

The [EFS setup](README.md#efs-runtime-state) supports two layouts: Mode A mounts EFS over home and excludes paths back to prebuilt storage; Mode B symlinks selected files/directories into EFS. Mode A shares anything not excluded. Its defaults do **not** exclude every agent cache/database, so the machine-local boundary above still needs explicit exclusions for those paths.

## Codex configuration

`~/.codex/config.toml` mixes portable preferences with app-written settings and host-specific data. A direct symlink into Git lets app writes dirty the source checkout; replacing the whole file can erase useful settings.

Instead, `ai-dotfiles` merges managed defaults into the effective config. Its current `scripts/sync_codex_config.py` manages top-level scalar preferences and preserves other root settings and all TOML tables. Portable desktop preferences and plugin selections should also be managed declaratively where appropriate; host-specific fields should remain local. **Gap:** table-level ownership is not implemented, and sharing the whole effective TOML through EFS also shares any host-specific fields inside it.

**EFS compatibility gap:** Mode B's config symlink is currently rejected by the sync unless forced; forcing replaces the symlink with a regular file. EFS setup also leaves pre-existing Git symlinks unchanged. The intended fix is to preserve the EFS link and merge into its target. Mode A's regular file on an EFS-mounted home does not have this per-file symlink problem.

## Other integration choices

**OpenCode:** both Linux profiles use one loopback user service for Web and `oc`, so terminal and browser share sessions. Only workstations publish it through Tailscale Serve. Credentials belong in local `server.env`. See the [service contract](README.md#16-opencode-web-service-linux).

**Install sources:** use upstream distributions and verify provenance separately from deciding whether to pin versions. OpenCode currently pins its official installer and checks its hash. Codex currently downloads an unpinned official GitHub release without a checksum check and skips any existing `codex` executable; this does not enforce upgrades or validate an existing installation's source.
