# Share one Yarn store across all git worktrees on the workstation, so a fresh
# worktree hardlinks from it instead of re-installing a full node_modules.
#
# hardlinks-global hardlinks into a content store under globalFolder; hardlinks
# can't cross filesystems, so the store must live on the same mount as the
# worktrees (/workspaces, ext4) — not $HOME on a different device.
if [ -d /workspaces ]; then
  export YARN_ENABLE_GLOBAL_CACHE=true
  export YARN_GLOBAL_FOLDER=/workspaces/.yarn-global
  export YARN_NM_MODE=hardlinks-global
fi
