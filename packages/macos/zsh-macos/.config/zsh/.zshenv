# Bootstrap Homebrew's env for every zsh, not just login shells.
# /etc/zprofile usually does this but (a) non-login shells skip it, (b) a
# managed Mac may not have it. Idempotent: no-op if already set.
#
# The `${HOMEBREW_PREFIX-}` form returns empty rather than erroring under
# `set -u`. Apple Silicon path tried first, Intel fallback.
if [ -z "${HOMEBREW_PREFIX-}" ]; then
  if   [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ];    then eval "$(/usr/local/bin/brew shellenv)"
  fi
fi
