#!/usr/bin/env zsh
SAVEHIST=1000000
HISTFILE=~/.zsh_history
touch $HISTFILE

export PATH="$HOME/.bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"
export PATH="$HOME/.config/emacs/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/.local/share/bob/nvim-bin:$PATH"



export EDITOR=nvim

export PATH="$HOME/.local/bin:$PATH"
export PATH="${GOPATH}/bin:${PATH}"
export GOPATH="$HOME/go"

# ------ devenv start
# zfunc
ZFUNC_DIR="$HOME/.config/zsh/zfunc"
[ -d ${ZFUNC_DIR} ] || mkdir -p ${ZFUNC_DIR}
fpath+=${ZFUNC_DIR}
# zfunc
# ---- ghc
[ -d "$HOME/.ghcup" ] && export PATH="$HOME/.ghcup/bin:$PATH"
# ---- ghc
# ---- ASDF VM
test -x "$(which asdf 2>/dev/null)" >/dev/null 2>&1 && {
        export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
        mkdir -p "${ASDF_DATA_DIR:-$HOME/.asdf}/completions"
        [ -f "${ASDF_DATA_DIR:-$HOME/.asdf}/completions/_asdf" ] || asdf completion zsh > "${ASDF_DATA_DIR:-$HOME/.asdf}/completions/_asdf"
        fpath=(${ASDF_DATA_DIR:-$HOME/.asdf}/completions $fpath)
	[ -d "$HOME/.asdf/plugins/java" ] && . ~/.asdf/plugins/java/set-java-home.zsh

}
# ---- ASDF VM
# ---- pnpm
hash pnpm >/dev/null 2>&1 && {
	export PNPM_HOME="$HOME/.local/share/pnpm"
	case ":$PATH:" in
		*":$PNPM_HOME/bin:"*) ;;
		*) export PATH="$PNPM_HOME/bin:$PATH" ;;
	esac
}
# ---- pnpm

# ---- yarn
hash yarn >/dev/null 2>&1 && {
	export PATH="$HOME/.yarn/bin:$PATH"
}
# ---- yarn

# ---- direnv
hash direnv >/dev/null 2>&1 && {
	eval "$(direnv hook zsh)"
}
# ---- direnv

# ---- python start
# ----- poetry start
command -v poetry >/dev/null 2>&1 && [ ! -f "$HOME/.config/zsh/zfunc/_poetry" ] && {
    mkdir -p ~/.config/zsh
	poetry completions zsh > $HOME/.config/zsh/zfunc/_poetry
}
# ----- poetry end
# ---- python end

# ------ devenv end

autoload -U colors && colors
autoload -U compinit && compinit



# ---- vi key bindings start
bindkey -v '^?' backward-delete-char
export KEYTIMEOUT=1
bindkey -v
function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]] ||
     [[ $1 = 'block' ]]; then
    echo -ne '\e[1 q'
  elif [[ ${KEYMAP} == main ]] ||
       [[ ${KEYMAP} == viins ]] ||
       [[ ${KEYMAP} = '' ]] ||
       [[ $1 = 'beam' ]]; then
    echo -ne '\e[5 q'
  fi
}
zle -N zle-keymap-select
zle-line-init() {
    zle -K viins
    echo -ne "\e[5 q"
}
zle -N zle-line-init
echo -ne '\e[5 q'
preexec() { echo -ne '\e[5 q' ;}
bindkey '^[[P' delete-char
zstyle ':completion:*' menu select
zstyle ':completion:*' rehash true
zmodload zsh/complist
bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'l' vi-forward-char
bindkey -M menuselect 'j' vi-down-line-or-history
# ---- vi key bindings end




# ---- edit command line start
autoload edit-command-line; zle -N edit-command-line
bindkey  ^x^e edit-command-line
# ---- edit command line end


# prompt
autoload -U colors && colors
PROMPT="%B%{$fg[green]%}[%{$fg[green]%}%n%{$fg[green]%}@%{$fg[magenta]%}%M %{$fg[green]%}%~%{$fg[green]%}]%{$reset_color%}%b [RET=%?]"
PROMPT+="
$ "
export PROMPT

hash starship >/dev/null 2>&1 && eval "$(starship init zsh)"
# prompt

# plugins
# from home manager
syntaxhighlight=$HOME/.local/share/zsh/zsh-fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh
[ -f ${syntaxhighlight} ] && source ${syntaxhighlight}
# plugins





# aliases
hash bat >/dev/null 2>&1 && alias cat='bat -pp'
alias v=nvim
alias t='tmux new-session -A -s' # create a named session `t <session-name>`
alias vv='NVIM_APPNAME=nvim-ide nvim'
if hash eza >/dev/null 2>&1; then
        alias l="eza -lagh --time-style '+%Y-%m-%d %H:%M' --group-directories-first"
        alias ll="eza -lagh --time-style '+%Y-%m-%d %H:%M' --group-directories-first"
else
	alias ll='ls -Flash'
	alias l='ls -Flash'
fi
alias z='zathura --fork'
alias gaa='git add .'
alias gp='git push'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../../'
alias ruff-fmt='ruff check --select I --fix; ruff format'

# aliases


stty -ixon

[ -f "$HOME/.zshrc.local" ] && source $HOME/.zshrc.local
