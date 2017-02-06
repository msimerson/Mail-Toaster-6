#!/bin/sh

install_bash()
{
    tell_status "installing bash"
    stage_pkg_install bash || exit
    stage_exec chpass -s /usr/local/bin/bash

    local _profile="$1/root/.bash_profile"
    if [ -f "$_profile" ]; then
        tell_status "preseving $_profile"
        return
    fi

    tell_status "adding .bash_profile for root@jail"
    configure_bash "$_profile"
}

install_zsh()
{
    tell_status "installing zsh"
    stage_pkg_install zsh || exit
    stage_exec chpass -s /usr/local/bin/zsh
}

configure_bash()
{
    tee -a "$1" <<'EO_BASH_PROFILE'

export EDITOR="vim"
export BLOCKSIZE=K;
export HISTSIZE=10000
export HISTCONTROL=ignoredups:erasedups
export HISTIGNORE="&:[bf]g:exit"
shopt -s histappend
shopt -s cdspell
bind Space:magic-space
alias h="history 200"
alias ll="ls -alFG"
PS1="$(whoami)@$(hostname -s):\\w # "
EO_BASH_PROFILE
}

configure_bourne_shell()
{
    if grep -q ^PS1 "$1/etc/profile"; then
        tell_status "bourne shell configured"
        return
    fi

    tell_status "customizing bourne shell prompt"
    tee -a "$1/etc/profile" <<'EO_BOURNE_SHELL'
alias h='fc -l'
alias j=jobs
alias m=$PAGER
alias ll="ls -alFG"
alias l='ls -l'
alias g='egrep -i'

PS1="$(whoami)@$(hostname -s):\\w "
case $(id -u) in
    0) PS1="${PS1}# ";;
    *) PS1="${PS1}$ ";;
esac
EO_BOURNE_SHELL
}

configure_csh_shell()
{
    _cshrc="$1/etc/csh.cshrc"
    if grep -q prompt "$_cshrc"; then
        tell_status "preseving $_cshrc"
        return
    fi

    tell_status "configure C shell"
    tee -a "$_cshrc" <<'EO_CSHRC'
alias h         history 25
alias j         jobs -l
alias la        ls -aF
alias lf        ls -FA
alias ll        ls -lAFG

setenv  EDITOR  vi
setenv  PAGER   less
setenv  BLOCKSIZE       K

if ($?prompt) then
        # An interactive shell -- set some stuff up
        set prompt = "%N@%m:%~ %# "
        set promptchars = "%#"

        set filec
        set history = 1000
        set savehist = (1000 merge)
        set autolist = ambiguous
        # Use history to aid expansion
        set autoexpand
        set autorehash
        if ( $?tcsh ) then
                bindkey "^W" backward-delete-word
                bindkey -k up history-search-backward
                bindkey -k down history-search-forward
        endif

endif
EO_CSHRC
}

configure_zsh_shell()
{
    tell_status "making zsh more comfy with ZIM"

    fetch -o - https://github.com/Infern1/Mail-Toaster-6/raw/master/contrib/zim.tar.gz \
    | tar -C "$1/root/" -xf -  || echo "Zsh config failed!"
    stage_exec zsh -c '. /root/.zshrc;  source /root/.zlogin'
}
