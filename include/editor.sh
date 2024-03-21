#!/bin/sh

configure_vim_tiny()
{
	if jail_is_running stage; then
		stage_pkg_install vim-tiny
	else
		pkg install vim-tiny
	fi

	install_vimrc

	# vim-tiny has no syntax or color files, so disable some stuff
	sed -i '' \
		-e 's/^syntax on/" syntax on/' \
		-e 's/^colorscheme/" colorscheme/' \
		-e 's/^set number/" set number/' \
		-e 's/^set cursorline/" set cursorline/' \
		-e 's/^set relativenumber/" set relativenumber/' \
		"$_base/usr/local/etc/vim/vimrc"
}

configure_vim()
{
	if jail_is_running stage; then
		stage_pkg_install vim
	else
		pkg install vim
	fi

	install_vimrc

	sed -i '' \
		-e 's/set termguicolors/" set termguicolors/' \
		-e 's/^set number/" set number/' \
		-e 's/^set cursorline/" set cursorline/' \
		-e 's/^set relativenumber/" set relativenumber/' \
		"$_base/usr/local/etc/vim/vimrc"

	if fetch -m -o /usr/local/share/vim/vim91/colors/gruvbox.vim https://raw.githubusercontent.com/morhetz/gruvbox/master/colors/gruvbox.vim;
	then
		sed -i '' \
			-e 's/^colorscheme.*/colorscheme gruvbox/' \
			"$_base/usr/local/etc/vim/vimrc"
	fi
}

install_vimrc()
{
	tell_status "installing vimrc"

	local _vimdir="$_base/usr/local/etc/vim"
	if [ ! -d "$_vimdir" ]; then
		mkdir -p "$_vimdir" || exit
	fi

	fetch -m -o "$_vimdir/vimrc" https://raw.githubusercontent.com/nandalopes/vim-for-server/main/vimrc
}

configure_neovim()
{
	if jail_is_running stage; then
		stage_pkg_install neovim
	else
		pkg install neovim
	fi

	# todo
}

configure_editor()
{
	local _base=${1:-""}

	case "$TOASTER_EDITOR" in
		neovim)
			configure_neovim
			;;
		vim-tiny)
			configure_vim_tiny
			;;
		vim)
			configure_vim
			;;
		vi) ;;
		*)  ;;
	esac
}
