#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

mt6-include shell

create_base_filesystem()
{
	if [ -e "$BASE_MNT/dev/null" ]; then
		echo "unmounting $BASE_MNT/dev"
		umount "$BASE_MNT/dev" || exit
	fi

	if zfs_filesystem_exists "$BASE_VOL"; then
		echo "$BASE_VOL already exists"
		return
	fi

	zfs_create_fs "$BASE_VOL"
}

freebsd_update()
{
	if [ ! -t 0 ]; then
		echo "No tty, can't update FreeBSD with freebsd-update"
		return
	fi

	tell_status "apply FreeBSD security updates to base jail"
	sed -i .bak -e 's/^Components.*/Components world/' "$BASE_MNT/etc/freebsd-update.conf"
	freebsd-update -b "$BASE_MNT" -f "$BASE_MNT/etc/freebsd-update.conf" fetch install
}

install_freebsd()
{
	if [ -f "$BASE_MNT/COPYRIGHT" ]; then
		echo "FreeBSD already installed"
		return
	fi

	if [ -n "$USE_BSDINSTALL" ]; then
		export BSDINSTALL_DISTSITE;
		BSDINSTALL_DISTSITE="$FBSD_MIRROR/pub/FreeBSD/releases/$(uname -m)/$(uname -m)/$FBSD_REL_VER"
		bsdinstall jail "$BASE_MNT"
	else
		stage_fbsd_package base "$BASE_MNT"
	fi
}

install_ssmtp()
{
	tell_status "installing ssmtp"
	stage_pkg_install ssmtp || exit

	tell_status "configuring ssmtp"
	cp "$BASE_MNT/usr/local/etc/ssmtp/revaliases.sample" \
	   "$BASE_MNT/usr/local/etc/ssmtp/revaliases" || exit

	sed -e "/^root=/ s/postmaster/$TOASTER_ADMIN_EMAIL/" \
		-e "/^mailhub=/ s/=mail/=haraka/" \
		-e "/^rewriteDomain=/ s/=\$/=$TOASTER_MAIL_DOMAIN/" \
		-e '/^#FromLineOverride=YES/ s/#//' \
		"$BASE_MNT/usr/local/etc/ssmtp/ssmtp.conf.sample" \
		> "$BASE_MNT/usr/local/etc/ssmtp/ssmtp.conf" || exit

	tee "$BASE_MNT/etc/mail/mailer.conf" <<EO_MAILER_CONF
sendmail	/usr/local/sbin/ssmtp
send-mail	/usr/local/sbin/ssmtp
mailq		/usr/local/sbin/ssmtp
newaliases	/usr/local/sbin/ssmtp
hoststat	/usr/bin/true
purgestat	/usr/bin/true
EO_MAILER_CONF
}

configure_syslog()
{
	tell_status "forwarding syslog to host"
	tee "$BASE_MNT/etc/syslog.conf" <<EO_SYSLOG
*.*			@syslog
EO_SYSLOG

	disable_newsyslog
}

disable_newsyslog()
{
	tell_status "disabling newsyslog"
	sysrc -f "$BASE_MNT/etc/rc.conf" newsyslog_enable=NO
	sed -i .bak \
		-e '/^0.*newsyslog/ s/^0/#0/' \
		"$BASE_MNT/etc/crontab"
}

disable_syslog()
{
	tell_status "disabling syslog"
	sysrc -f "$BASE_MNT/etc/rc.conf" syslogd_enable=NO
	disable_newsyslog
}

disable_root_password()
{
	if ! grep -q '^root::' "$BASE_MNT/etc/master.passwd"; then
		return
	fi

	# prevent a nightly email notice about the empty root password
	tell_status "disabling passwordless root account"
	sed -i .bak -e 's/^root::/root:*:/' "$BASE_MNT/etc/master.passwd"
	stage_exec pwd_mkdb /etc/master.passwd || exit
}

disable_cron_jobs()
{
	if grep -q '^1.*adjkerntz' "$BASE_MNT/etc/crontab"; then
		tell_status "cron jobs already configured"
		return
	fi

	tell_status "disabling adjkerntz, save-entropy, & atrun"
	# nobody uses atrun, safe-entropy is done by the host, and
	# the jail doesn't have permission to run adjkerntz.
	sed -i .bak \
		-e '/^1.*adjkerntz/ s/^1/#1/'  \
		-e '/^\*.*atrun/    s/^\*/#*/' \
		-e '/^\*.*entropy/  s/^\*/#*/' \
		"$BASE_MNT/etc/crontab" || exit

	echo "done"
}

enable_security_periodic()
{
	local _daily="$BASE_MNT/usr/local/etc/periodic/daily"
	if [ ! -d "$_daily" ]; then
		mkdir -p "$_daily"
	fi

	tee "$_daily/auto_security_upgrades" <<EO_PKG_SECURITY
#!/bin/sh
/usr/sbin/pkg audit | grep curl && pkg install -y curl
EO_PKG_SECURITY
}

configure_ssl_dirs()
{
	if [ ! -d "$BASE_MNT/etc/ssl/certs" ]; then
		mkdir "$BASE_MNT/etc/ssl/certs"
	fi

	if [ ! -d "$BASE_MNT/etc/ssl/private" ]; then
		mkdir "$BASE_MNT/etc/ssl/private"
	fi

	chmod o-r "$BASE_MNT/etc/ssl/private"
}

configure_tls_dhparams()
{
	if [ -f "$BASE_MNT/etc/ssl/dhparam.pem" ]; then
		return
	fi

	local DHP="/etc/ssl/dhparam.pem"
	if [ ! -f "$DHP" ]; then
		# for upgrade compatibilty
		tell_status "Generating a 2048 bit $DHP"
		openssl dhparam -out "$DHP" 2048 || exit
	fi

	cp "$DHP" "$BASE_MNT/etc/ssl/dhparam.pem" || exit
}

configure_make_conf() {
	local _make="$BASE_MNT/etc/make.conf"
	if grep -qs WRKDIRPREFIX "$_make"; then
		return
	fi

	tell_status "setting base jail make.conf variables"
	tee -a "$_make" <<EO_MAKE_CONF
WITH_PKGNG=yes
WRKDIRPREFIX?=/tmp/portbuild
EO_MAKE_CONF
}

configure_base()
{
	if [ ! -d "$BASE_MNT/usr/ports" ]; then
		mkdir "$BASE_MNT/usr/ports" || exit
	fi

	tell_status "adding base jail resolv.conf"
	cp /etc/resolv.conf "$BASE_MNT/etc" || exit

	tell_status "setting base jail timezone (to hosts)"
	cp /etc/localtime "$BASE_MNT/etc" || exit

	configure_make_conf

	# shellcheck disable=2016
	sysrc -f "$BASE_MNT/etc/rc.conf" \
		hostname=base \
		cron_flags='$cron_flags -J 15' \
		syslogd_flags="-s -cc" \
		sendmail_enable=NONE \
		update_motd=NO

	configure_pkg_latest "$BASE_MNT"
	configure_ssl_dirs
	configure_tls_dhparams
	disable_cron_jobs
	enable_security_periodic
	configure_syslog
	configure_bourne_shell "$BASE_MNT"
	configure_csh_shell "$BASE_MNT"
}

install_periodic_conf()
{
	tell_status "installing /etc/periodic.conf"
	tee "$BASE_MNT/etc/periodic.conf" <<EO_PERIODIC
# periodic.conf tuned for periodic inside jails
# increase the signal, decrease the noise

# some versions of FreeBSD bark b/c these are defined in
# /etc/defaults/periodic.conf and do not exist. Hush.
daily_local=""
weekly_local=""
monthly_local=""

# in case /etc/aliases isn't set up properly
daily_output="$TOASTER_ADMIN_EMAIL"
weekly_output="$TOASTER_ADMIN_EMAIL"
monthly_output="$TOASTER_ADMIN_EMAIL"

security_show_success="NO"
security_show_info="NO"
security_status_pkgaudit_enable="YES"
security_status_tcpwrap_enable="YES"
daily_status_security_inline="NO"
weekly_status_security_inline="NO"
monthly_status_security_inline="NO"
daily_status_security_pkgaudit_quiet="YES"

# These are redundant within a jail
security_status_chkmounts_enable="NO"
security_status_chksetuid_enable="NO"
security_status_neggrpperm_enable="NO"
security_status_ipfwlimit_enable="NO"
security_status_ipfwdenied_enable="NO"
security_status_pfdenied_enable="NO"
security_status_kernelmsg_enable="NO"

daily_accounting_enable="NO"
daily_accounting_compress="YES"
daily_clean_disks_enable="NO"
daily_clean_disks_verbose="NO"
daily_clean_hoststat_enable="NO"
daily_clean_tmps_enable="YES"
daily_clean_tmps_verbose="NO"
daily_news_expire_enable="NO"

daily_show_success="NO"
daily_show_info="NO"
daily_show_badconfig="YES"

daily_status_disks_enable="NO"
daily_status_include_submit_mailq="NO"
daily_status_mail_rejects_enable="NO"
daily_status_mailq_enable="NO"
daily_status_network_enable="NO"
daily_status_rwho_enable="NO"
daily_submit_queuerun="NO"

weekly_accounting_enable="NO"
weekly_show_success="NO"
weekly_show_info="NO"
weekly_show_badconfig="YES"
weekly_whatis_enable="NO"

monthly_accounting_enable="NO"
monthly_show_success="NO"
monthly_show_info="NO"
monthly_show_badconfig="YES"
EO_PERIODIC
}

install_vimrc()
{
	tell_status "installing a jail-wide vimrc"
	local _vimdir="$BASE_MNT/usr/local/etc/vim"
	if [ ! -d "$_vimdir" ]; then
		mkdir -p "$_vimdir" || exit
	fi

	tee  "$_vimdir/vimrc" <<EO_VIMRC
"==========================================
" ProjectLink: https://github.com/wklken/vim-for-server
" Author:  wklken
" Version: 0.2
" Email: wklken@yeah.net
" BlogPost: http://www.wklken.me
" Donation: http://www.wklken.me/pages/donation.html
" ReadMe: README.md
" Last_modify: 2015-07-07
" Desc: simple vim config for server, without any plugins.
"==========================================

" leader
let mapleader = ','
let g:mapleader = ','

" syntax
syntax on

" history : how many lines of history VIM has to remember
set history=2000

" filetype
filetype on
" Enable filetype plugins
filetype plugin on
filetype indent on


" base
set nocompatible                " don't bother with vi compatibility
set autoread                    " reload files when changed on disk
set shortmess=atI

set magic                       " For regular expressions turn magic on
set title                       " change the terminal's title
set nobackup                    " do not keep a backup file

set novisualbell                " turn off visual bell
set noerrorbells                " don't beep
set visualbell t_vb=            " turn off error beep/flash
set t_vb=
set tm=500


" show location
set cursorcolumn
set cursorline


" movement
set scrolloff=7                 " keep 3 lines when scrolling


" show
set ruler                       " show the current row and column
set number                      " show line numbers
set nowrap
set showcmd                     " display incomplete commands
set showmode                    " display current modes
set showmatch                   " jump to matches when entering parentheses
set matchtime=2                 " tenths of a second to show the matching parenthesis


" search
set hlsearch                    " highlight searches
set incsearch                   " do incremental searching, search as you type
set ignorecase                  " ignore case when searching
set smartcase                   " no ignorecase if Uppercase char present


" tab
set expandtab                   " expand tabs to spaces
set smarttab
set shiftround

" indent
set autoindent smartindent shiftround
set shiftwidth=4
set tabstop=4
set softtabstop=4                " insert mode tab and backspace use 4 spaces

" NOT SUPPORT
" fold
set foldenable
set foldmethod=indent
set foldlevel=99
let g:FoldMethod = 0
map <leader>zz :call ToggleFold()<cr>
fun! ToggleFold()
    if g:FoldMethod == 0
        exe "normal! zM"
        let g:FoldMethod = 1
    else
        exe "normal! zR"
        let g:FoldMethod = 0
    endif
endfun

" encoding
set encoding=utf-8
set fileencodings=ucs-bom,utf-8,cp936,gb18030,big5,euc-jp,euc-kr,latin1
set termencoding=utf-8
set ffs=unix,dos,mac
set formatoptions+=m
set formatoptions+=B

" select & complete
set selection=inclusive
set selectmode=mouse,key

set completeopt=longest,menu
set wildmenu                           " show a navigable menu for tab completion"
set wildmode=longest,list,full
set wildignore=*.o,*~,*.pyc,*.class

" others
set backspace=indent,eol,start  " make that backspace key work the way it should
set whichwrap+=<,>,h,l

" if this not work ,make sure .viminfo is writable for you
if has("autocmd")
  au BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif
endif

" NOT SUPPORT
" Enable basic mouse behavior such as resizing buffers.
" set mouse=a


" ============================ theme and status line ============================

" theme
set background=dark
colorscheme desert

" set mark column color
hi! link SignColumn   LineNr
hi! link ShowMarksHLl DiffAdd
hi! link ShowMarksHLu DiffChange

" status line
set statusline=%<%f\ %h%m%r%=%k[%{(&fenc==\"\")?&enc:&fenc}%{(&bomb?\",BOM\":\"\")}]\ %-14.(%l,%c%V%)\ %P
set laststatus=2   " Always show the status line - use 2 lines for the status bar


" ============================ specific file type ===========================

autocmd FileType python set tabstop=4 shiftwidth=4 expandtab ai
autocmd FileType ruby set tabstop=2 shiftwidth=2 softtabstop=2 expandtab ai
autocmd BufRead,BufNew *.md,*.mkd,*.markdown  set filetype=markdown.mkd

autocmd BufNewFile *.sh,*.py exec ":call AutoSetFileHead()"
function! AutoSetFileHead()
    " .sh
    if &filetype == 'sh'
        call setline(1, "\#!/bin/sh")
    endif

    " python
    if &filetype == 'python'
        call setline(1, "\#!/usr/bin/env python")
        call append(1, "\# encoding: utf-8")
    endif

    normal G
    normal o
    normal o
endfunc

autocmd FileType c,cpp,java,go,php,javascript,puppet,python,rust,twig,xml,yml,perl autocmd BufWritePre <buffer> :call <SID>StripTrailingWhitespaces()
fun! <SID>StripTrailingWhitespaces()
    let l = line(".")
    let c = col(".")
    %s/\s\+$//e
    call cursor(l, c)
endfun

" ============================ key map ============================

nnoremap k gk
nnoremap gk k
nnoremap j gj
nnoremap gj j

map <C-j> <C-W>j
map <C-k> <C-W>k
map <C-h> <C-W>h
map <C-l> <C-W>l

nnoremap <F2> :set nu! nu?<CR>
nnoremap <F3> :set list! list?<CR>
nnoremap <F4> :set wrap! wrap?<CR>
set pastetoggle=<F5>            "    when in insert mode, press <F5> to go to
                                "    paste mode, where you can paste mass data
                                "    that won't be autoindented
au InsertLeave * set nopaste
nnoremap <F6> :exec exists('syntax_on') ? 'syn off' : 'syn on'<CR>

" kj 替换 Esc
inoremap kj <Esc>

" Quickly close the current window
nnoremap <leader>q :q<CR>
" Quickly save the current file
nnoremap <leader>w :w<CR>

" select all
map <Leader>sa ggVG"

" remap U to <C-r> for easier redo
nnoremap U <C-r>

" switch # *
" nnoremap # *
" nnoremap * #

"Keep search pattern at the center of the screen."
nnoremap <silent> n nzz
nnoremap <silent> N Nzz
nnoremap <silent> * *zz
nnoremap <silent> # #zz
nnoremap <silent> g* g*zz

" remove highlight
noremap <silent><leader>/ :nohls<CR>

"Reselect visual block after indent/outdent.调整缩进后自动选中，方便再次操作
vnoremap < <gv
vnoremap > >gv

" y$ -> Y Make Y behave like other capitals
map Y y$

"Map ; to : and save a million keystrokes
" ex mode commands made easy 用于快速进入命令行
nnoremap ; :

" save
cmap w!! w !sudo tee >/dev/null %

" command mode, ctrl-a to head， ctrl-e to tail
cnoremap <C-j> <t_kd>
cnoremap <C-k> <t_ku>
cnoremap <C-a> <Home>
cnoremap <C-e> <End>
EO_VIMRC
}

install_base()
{
	tell_status "installing packages desired in every jail"
	stage_pkg_install pkg vim-console ca_root_nss || exit

	stage_exec newaliases

	if [ "$BOURNE_SHELL" = "bash" ]; then
		install_bash "$BASE_MNT"
	elif [ "$BOURNE_SHELL" = "zsh" ]; then
		install_zsh
		configure_zsh_shell "$BASE_MNT"
	fi

	install_ssmtp
	disable_root_password
	install_periodic_conf
	install_vimrc
	stage_exec pkg upgrade -y
}

zfs_snapshot_exists "$BASE_SNAP" && exit 0
jail -r stage 2>/dev/null
create_base_filesystem
install_freebsd
freebsd_update
configure_base
start_staged_jail base "$BASE_MNT" || exit
install_base
jail -r stage
umount "$BASE_MNT/dev"
rm -rf "$BASE_MNT/var/cache/pkg/*"
echo "zfs snapshot ${BASE_SNAP}"
zfs snapshot "${BASE_SNAP}" || exit

proclaim_success base
