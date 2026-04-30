# Remote dev images often start bash as a login shell, which reads
# ~/.bash_profile instead of ~/.bashrc. Preserve platform-provided ~/.profile
# setup first, then hand off through the dotfiles-managed bashrc.
[ -r "$HOME/.profile" ] && . "$HOME/.profile"
[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"
