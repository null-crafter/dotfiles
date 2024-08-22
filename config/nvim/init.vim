nnoremap <SPACE> <Nop>
let mapleader =" "

if ! filereadable(system('printf "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/autoload/plug.vim"'))
	silent !mkdir -p ${XDG_CONFIG_HOME:-$HOME/.config}/nvim/autoload/
	silent !curl "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" > ${XDG_CONFIG_HOME:-$HOME/.config}/nvim/autoload/plug.vim
	autocmd VimEnter * PlugInstall
endif


call plug#begin(system('printf "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/plugged"'))
Plug 'vim-airline/vim-airline'
Plug 'ap/vim-css-color'
Plug 'tpope/vim-surround'
call plug#end()

set title
set bg=dark
set go=a
set mouse=a
set nohlsearch
set clipboard+=unnamedplus
set noshowmode
set noruler
set laststatus=0
set noshowcmd

nnoremap c "_c
set nocompatible
filetype plugin on
syntax on
set encoding=utf-8
set number
set wildmode=longest,list,full
autocmd FileType * setlocal formatoptions-=c formatoptions-=r formatoptions-=o
vnoremap . :normal .<CR>


if !exists('g:airline_symbols')
	let g:airline_symbols = {}
endif
let g:airline_symbols.colnr = ' C: '
let g:airline_symbols.linenr = ' L:'
let g:airline_symbols.maxlinenr = ' MAXL: '

" shell check
map <leader>s :!clear && shellcheck -x %<CR>

" trilling spaces
autocmd BufWritePre * let currPos = getpos(".")
autocmd BufWritePre * %s/\s\+$//e
autocmd BufWritePre * %s/\n\+\%$//e

autocmd BufWritePre *.[ch] %s/\%$/\r/e "ANSI C

autocmd BufWritePre * cal cursor(currPos[1], currPos[2]) "cursor position

if &diff
    highlight! link DiffText MatchParen
endif
