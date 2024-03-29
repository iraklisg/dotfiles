# XDG Base directory
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_DATA_HOME="$HOME/.local/share"

# ZSH
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
export HISTFILE="$ZDOTDIR/.zsh_history"

# zsh-nvm plugin
export NVM_AUTO_USE=true

export EDITOR="nvim"
export VISUAL="nvim"

# Workaround for zsh-autoswitch-virtualenv plugin
# see: https://github.com/MichaelAquilina/zsh-autoswitch-virtualenv/issues/111
export AUTOSWITCH_FILE=".autoswitch_venv"
