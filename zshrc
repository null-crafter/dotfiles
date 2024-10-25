#!/usr/bin/env zsh
SAVEHIST=1000000
HISTFILE=~/.zsh_history
touch $HISTFILE
cat() {
	if command -v bat >/dev/null 2>&1; then
    		bat -pp "$@"
	else
    		/bin/cat "$@"
	fi
}

autoload -U colors && colors PROMPT="%B%{$fg[green]%}[%{$fg[green]%}%n%{$fg[green]%}@%{$fg[magenta]%}%M %{$fg[green]%}%~%{$fg[green]%}]%{$reset_color%}%b [RET=%?]"
PROMPT+="
$ "
export PROMPT
export PATH="$HOME/.bin:$PATH"

# things
export EDITOR=nvim
# things

# Update path
export PATH="$HOME/.local/bin:$PATH"
export PATH="${GOPATH}/bin:${PATH}"
export GOPATH="$HOME/go"
[ -d "$HOME/.ghcup" ] && export PATH="$HOME/.ghcup/bin:$PATH"
# Update path


# aliases
alias v=nvim
if command -v lsd >/dev/null 2>&1; then
	alias ll='lsd -Flah --icon never'
	alias l='lsd -Flah --icon never'
else
	alias ll='ls -Flash'
	alias l='ls -Flash'
fi
alias z='zathura --fork'
alias gaa='git add .'
# aliases

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

autoload -U colors && colors

# ---- ASDF VM
[ -d "$HOME/.asdf" ] && {
	export ASDF_DIR="$HOME/.asdf"
	. "$ASDF_DIR/asdf.sh"
	fpath=(${ASDF_DIR}/completions $fpath)
}
# ---- ASDF VM
# ---- volta
[ -d "$HOME/.volta" ] && {
	export VOLTA_HOME=$HOME/.volta
	export PATH="$VOLTA_HOME/bin:$PATH"
}
# ---- volta

# ---- direnv
hash direnv >/dev/null 2>&1 && {
	eval "$(direnv hook zsh)"
}
# ---- direnv


autoload -U compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' rehash true
zmodload zsh/complist

bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'l' vi-forward-char
bindkey -M menuselect 'j' vi-down-line-or-history

# edit command line
autoload edit-command-line; zle -N edit-command-line
bindkey  ^x^e edit-command-line
stty -ixon
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"
