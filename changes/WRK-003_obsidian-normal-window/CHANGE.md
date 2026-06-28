# Change: Obsidian as a normal Sway window (drop scratchpad special-casing)

**ID:** WRK-003
**Status:** Complete
**Created:** 2026-06-28

## Problem

Obsidian was special-cased in Sway as a scratchpad: `mod+n` ran a cycle script (hidden → left → right) and a `for_window` rule auto-moved every Obsidian window into the scratchpad. The cycle script has a dead branch — when Obsidian's process is alive but its window is unmapped (closed-to-background / minimized to tray), the script sees the running process, assumes "launched but not yet registered," and `exit 0`s. Result: `mod+n` becomes a permanent silent no-op until manual intervention (just hit this). The scratchpad overlay also fights actual usage — Obsidian is an app to live in (daily notes, PARA vault), not ephemeral summon-dismiss capture.

## Why now

Scratchpad just silently broke `mod+n`; cheaper to delete the special-casing than to keep patching the cycle script's failure modes.

## Approach

Strip all Obsidian-specific Sway config so it's a plain tiled window managed like any other app. Remove the scratchpad block from the Sway config, delete the cycle script + its stow symlink, reload Sway, and rescue the currently-scratchpadded window back into normal tiling. The generic scratchpad (`mod+grave` / `mod+Shift+grave`) stays, so Obsidian can still be tossed into a float ad hoc if ever wanted — it just loses its dedicated, special-cased version.

**Key decisions:**

- **Decision-1 (normal window over scratchpad):** Treat Obsidian as a normal tiled window over the dedicated scratchpad cycle. Scratchpad earns its complexity only for ephemeral summon-dismiss capture; Obsidian is an app the user lives in, and the cycle script's windowless-process dead-branch made `mod+n` brittle. `(user)`
- **Decision-2 (mod+n left unbound):** Pure option A — leave `mod+n` free rather than rebind it to focus-or-launch. User launches Obsidian via the normal app launcher; fewer bindings, less surface. `(user)`
- **Decision-3 (force XWayland for Obsidian):** Flip the flatpak override from `--socket=wayland` to `--nosocket=wayland` (`justfile:593`). Surfaced during testing: Obsidian's native-Wayland render path crashes on this Nvidia GPU (GPUCache wiped, `libcuda`/`kmsro` errors) so the window never maps — vault picker flashes, nothing opens. XWayland maps the window in <1s with GPU accel intact. The original `--socket=wayland` (commit `1a1273a`) existed for native-Wayland scratchpad matching, which Decision-1 removes — so its reason is gone and it's now actively harmful. `(user)`

## Checklist

- [x] Remove the "Obsidian scratchpad" block (comment + `bindsym $mod+n` + `for_window [app_id="obsidian"]`) from `packages/linux/sway/.config/sway/config`
- [x] Delete the `obsidian-scratchpad` script (`packages/linux/bin-linux/.local/bin/obsidian-scratchpad`) and its dangling stow symlink `~/.local/bin/obsidian-scratchpad`
- [x] Reload Sway and rescue the currently-scratchpadded Obsidian window into normal tiling
- [x] Clean up `/tmp/obsidian-scratchpad-state` and `/tmp/obsidian-scratchpad.lock`
- [x] Flip `justfile:593` flatpak override to `--nosocket=wayland` so setup forces XWayland (Decision-3)
- [x] Apply the same override machine-local (`flatpak override --user --nosocket=wayland md.obsidian.Obsidian`) so this box is fixed now

## Done when

`mod+n` does nothing, and launching Obsidian via the app launcher gives a normal tiled window that actually opens (no scratchpad auto-move, no Nvidia render crash) — managed like any other app.

## Followups

- (none yet)
