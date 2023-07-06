#!/bin/sh

install_bash()
{
	tell_status "installing bash"
	stage_pkg_install bash || exit
	stage_exec chpass -s /usr/local/bin/bash

	local _profile="$1/usr/local/etc/profile"
	if [ -f "$_profile" ]; then
		tell_status "preserving $_profile"
		return
	fi

	_profile="$1/root/.bash_profile"
	if [ -f "$_profile" ]; then
		tell_status "preserving $_profile"
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
alias h="history 200"
EO_BASH_PROFILE

	if ! grep -qs profile "$1"; then
		tee -a "$1" <<EO_INCL
. /etc/profile
EO_INCL
	fi
}

configure_bourne_shell()
{
	_f="$1/etc/profile.d/toaster.sh"
	if ! grep -qs ^PS1 "$_f"; then
		tell_status "customizing bourne shell prompt"
		tee -a "$_f" <<'EO_BOURNE_SHELL'
alias h='fc -l'
alias m=$PAGER
alias ll="ls -alFG"
alias g='egrep -i'

PS1="$(whoami)@$(hostname -s):\\w "
case $(id -u) in
    0) PS1="${PS1}# ";;
    *) PS1="${PS1}$ ";;
esac
EO_BOURNE_SHELL
	fi

	if ! grep -qs profile "/root/.profile"; then
		tee -a "/root/.profile" <<EO_INCL
. /etc/profile
EO_INCL
	fi
}

configure_csh_shell()
{
	_cshrc="$1/etc/csh.cshrc"
	if grep -q prompt "$_cshrc"; then
		tell_status "preserving $_cshrc"
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
	stage_exec mkdir /root/.config
	stage_exec cp /root/.zim/modules/prompt/external-themes/liquidprompt/liquidpromptrc-dist /root/.config/liquidpromptrc
	stage_exec sed -i.bak \
		-e 's/^LP_HOSTNAME_ALWAYS=0/LP_HOSTNAME_ALWAYS=1/' \
		"/root/.config/liquidpromptrc" || exit

}
