# Retro: Reliable OpenCode Web service

**ID:** WRK-004
**Status:** In Progress
**Change:** ./CHANGE.md

## Followups

### Critical

### High

### Medium

### Low

## Surprises

- [S-1] Expected a migration script to merge a stowed `opencode.json`, found that Stow would conflict with an existing file before migration. Public lower-precedence `config.json` preserves existing user config without copying it.
- [S-2] `just --fmt --check` reports existing whole-file formatting changes, so this unit used shell syntax, JSON assertions, and `just --show` parsing checks instead.
- [S-3] A pre-existing lower-precedence `config.json` also blocks Stow, so setup must migrate it locally without touching `opencode.jsonc`.

## Notes

- [M-1] Stack grounding: PROCEED after verifying OpenCode v1.18.3 layering, authentication, health, and attach contracts; all six units have an in-bounds plan.
