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

	configure_bash "$1"
}

install_zsh()
{
	tell_status "installing zsh"
	stage_pkg_install zsh || exit
	stage_exec chpass -s /usr/local/bin/zsh
}

install_fish()
{
	tell_status "installing fish"
	stage_pkg_install fish
	stage_exec chpass -s /usr/local/bin/fish
}

configure_bash()
{
	if ! grep -q profile "$1/root/.profile"; then
		tell_status "telling bash to read /etc/profile"
		sed -i '' \
			-e '/PAGER$/ a\
\
if [ -n "\$BASH" ]; then . /etc/profile; fi' \
			"$1/root/.profile"
		echo '' >> "$1/root/.profile"
		echo 'if [ -n "$BASH" ] && [ -r ~/.bashrc ]; then . ~/.bashrc; fi' >> "$1/root/.profile"
	fi

	if [ ! -e "$1/root/.bashrc" ]; then
		tell_status "creating $1/root/.bashrc"
		cat <<'EO_BASH_RC' > "$1/root/.bashrc"

export HISTSIZE=10000
export HISTCONTROL=ignoredups:erasedups
export HISTIGNORE="&:[bf]g:exit"

shopt -s histappend
shopt -s cdspell
#set -o vi

if [[ $- == *i* ]]
then
    bind '"\e[A": history-search-backward'
    bind '"\e[B": history-search-forward'
fi

PS1="[\u@\[\033[0;36m\]\h\[\033[0m\]] \w "
case $(id -u) in
    0) PS1="${PS1}# ";;
    *) PS1="${PS1}$ ";;
esac
EO_BASH_RC
	fi
}

configure_bourne_shell()
{
	_f="$1/etc/profile.d/toaster.sh"
	if ! grep -qs ^PS1 "$_f"; then
		tell_status "customizing bourne shell prompt"
		cat <<EO_BOURNE_SHELL > "$_f"
export EDITOR="$TOASTER_EDITOR"
export BLOCKSIZE=K;

alias h='fc -l'
alias m=\$PAGER
alias ls="ls -FG"
alias ll="ls -alFG"
alias g='egrep -i'
#alias df="df -h -tnodevfs,procfs,nullfs,tmpfs"

# set prompt for bourne shell (/bin/sh)
PS1="\$(whoami)@\$(hostname -s):\\w "
case \$(id -u) in
    0) PS1="\${PS1}# ";;
    *) PS1="\${PS1}\$ ";;
esac

jexecl() {
  if   [ -z "\$1" ]; then /usr/sbin/jexec;
  elif [ -n "\$2" ]; then /usr/sbin/jexec \${@:1};
  else /usr/sbin/jexec \$1 login -f -h $(hostname) root;
  fi
}
EO_BOURNE_SHELL
	fi

	if ! grep -qs profile "/root/.profile"; then
		echo ". /etc/profile" >> "/root/.profile"
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
	cat <<EO_CSHRC > "$_cshrc"
alias h         history 25
alias j         jobs -l
alias la        ls -aF
alias lf        ls -FA
alias ll        ls -lAFG

setenv  EDITOR  $TOASTER_EDITOR
setenv  PAGER   less
setenv  BLOCKSIZE       K

if (\$?prompt) then
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
        if ( \$?tcsh ) then
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
