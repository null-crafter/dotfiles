#!/usr/bin/env zsh
for b in firefox librewolf chromium-browser chromium brave;do
	hash "$b" >/dev/null 2>&1 && {
		export BROWSER="$b"
		break
	}
done
for e in nvim vim nano vi emacs; do
	hash "$e" >/dev/null 2>&1 && {
		export EDITOR="$e"
		break
	}
done
export PATH="$HOME/.local/bin:$PATH"
export PATH="${GOPATH}/bin:${PATH}"
export GOPATH="$HOME/go"
export PATH="$HOME/.bun/bin:$PATH"
[ -d "$HOME/.ghcup" ] && export PATH="$HOME/.ghcup/bin:$PATH"

export LANG="en_US.UTF-8"
export LC_COLLATE="C"
export LC_ALL="en_US.UTF-8"
export NVIM_TUI_ENABLE_TRUE_COLOR=1
export _JAVA_AWT_WM_NONREPARENTING=1 # fix java gui programs on dwm and bspwm
[ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ] >/dev/null 2>&1 && {
	export MOZ_ENABLE_WAYLAND=1
	export XDG_SESSION_TYPE=wayland
	export QT_QPA_PLATFORM=wayland
}
[ -f "$HOME/.zprofile.local" ] && source "$HOME/.zprofile.local"
