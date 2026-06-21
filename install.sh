#!/bin/sh
# install.sh: install the `vsvim` launcher onto $PATH and wire up vsvim's
# isolated Neovim config scope.
#
# vsvim gets its OWN Neovim scope via $NVIM_APPNAME=vsvim (see :help
# $NVIM_APPNAME), so it never touches the user's ~/.config/nvim. For that to
# work, Neovim needs to find init.lua / lua/ / plugin/ under the vsvim config
# directory. This script does both jobs:
#
#   1. Installs the `vsvim` launcher into:
#        ~/.local/bin/vsvim       when run as a normal user
#        /usr/local/bin/vsvim     when run as root (EUID 0)
#   2. Wires the vsvim config dir ($XDG_CONFIG_HOME/vsvim, default
#      ~/.config/vsvim) to point at the repo's config files, so `require()`,
#      runtimepath, and auto-sourced plugin/ files all work.
#
# By default both are SYMLINKS back to this repo, so editing files here takes
# effect immediately. Pass --copy for a frozen, self-contained install.
#
# Usage:
#   ./install.sh                 # symlink launcher + config dir (live)
#   ./install.sh --copy          # copy the tree, then link into place (frozen)
#   ./install.sh --prefix=DIR    # --copy destination (default ~/.local/share/vsvim)
#   ./install.sh --bindir=DIR    # override launcher bin dir
#   ./install.sh --configdir=DIR # override vsvim config dir
#   ./install.sh --uninstall     # remove everything this script creates
#   ./install.sh --dry-run       # show what would happen, change nothing
#   ./install.sh --quiet         # suppress informational output (used by
#                                # `vsvim update` when re-running install.sh)
#
# Environment overrides:
#   BINDIR, CONFIGDIR, PREFIX   (same-named flags win)

set -eu

# ---------------------------------------------------------------------------
# Locate the repo root (the dir this script lives in), following symlinks so
# `sh /some/path/install.sh` works too.
# ---------------------------------------------------------------------------
prog="$0"
while [ -h "$prog" ]; do
	prog_dir="$(cd "$(dirname "$prog")" && pwd)"
	prog="$(readlink "$prog")"
	case "$prog" in
		/*) : ;;
		*) prog="$prog_dir/$prog" ;;
	esac
done
REPO="$(cd "$(dirname "$prog")" && pwd)"

if [ ! -f "$REPO/vsvim" ] || [ ! -f "$REPO/init.lua" ]; then
	echo "install: error: could not locate the vsvim repo (missing ./vsvim or ./init.lua)." >&2
	echo "  resolved repo dir: $REPO" >&2
	exit 1
fi

# ---------------------------------------------------------------------------
# Effective home directory: when invoked via sudo, target the *real* user's
# home so we wire their ~/.config/vsvim rather than root's.
# ---------------------------------------------------------------------------
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ]; then
	EFFECTIVE_USER="$SUDO_USER"
else
	EFFECTIVE_USER="$(id -un)"
fi
# Resolve the home dir without relying on ~ (which $USER controls).
EFFECTIVE_HOME="$(getent passwd "$EFFECTIVE_USER" 2>/dev/null | cut -d: -f6 || true)"
if [ -z "$EFFECTIVE_HOME" ]; then
	EFFECTIVE_HOME="$HOME"
fi
EFFECTIVE_XDG_CONFIG="${XDG_CONFIG_HOME:-$EFFECTIVE_HOME/.config}"

# ---------------------------------------------------------------------------
# Defaults based on root vs. user
# ---------------------------------------------------------------------------
is_root=0
[ "$(id -u)" = 0 ] && is_root=1

if [ "$is_root" = 1 ]; then
	DEFAULT_BINDIR="/usr/local/bin"
	DEFAULT_PREFIX="/usr/local/share/vsvim"
else
	DEFAULT_BINDIR="$EFFECTIVE_HOME/.local/bin"
	DEFAULT_PREFIX="$EFFECTIVE_HOME/.local/share/vsvim"
fi
DEFAULT_CONFIGDIR="$EFFECTIVE_XDG_CONFIG/vsvim"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
COPY=0
UNINSTALL=0
DRY_RUN=0
QUIET=0
BINDIR="${BINDIR:-}"
CONFIGDIR="${CONFIGDIR:-}"
PREFIX="${PREFIX:-}"

show_help() {
	awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
}

while [ $# -gt 0 ]; do
	arg="$1"
	case "$arg" in
		--copy)         COPY=1 ;;
		--uninstall)    UNINSTALL=1 ;;
		--dry-run)      DRY_RUN=1 ;;
		--quiet)        QUIET=1 ;;
		--prefix=*)     PREFIX="${arg#*=}" ;;
		--prefix)       shift; PREFIX="${1:?--prefix needs a value}" ;;
		--bindir=*)     BINDIR="${arg#*=}" ;;
		--bindir)       shift; BINDIR="${1:?--bindir needs a value}" ;;
		--configdir=*)  CONFIGDIR="${arg#*=}" ;;
		--configdir)    shift; CONFIGDIR="${1:?--configdir needs a value}" ;;
		-h|--help)      show_help; exit 0 ;;
		*) echo "install: unknown option: $arg (--help for usage)" >&2; exit 2 ;;
	esac
	shift
done

[ -z "$BINDIR" ]    && BINDIR="$DEFAULT_BINDIR"
[ -z "$PREFIX" ]    && PREFIX="$DEFAULT_PREFIX"
[ -z "$CONFIGDIR" ] && CONFIGDIR="$DEFAULT_CONFIGDIR"

# Files/dirs from the repo that make up the runtime config. These get linked
# (or copied) into the vsvim config dir.
RUNTIME_ITEMS="init.lua lua plugin nvim-pack-lock.json"

DEST="$BINDIR/vsvim"

# Helpers ---------------------------------------------------------------
# run: echo in dry-run, execute otherwise.
run() {
	if [ "$DRY_RUN" = 1 ]; then
		printf '  dr %s\n' "$*"
	else
		"$@"
	fi
}
note()  { [ "$QUIET" = 1 ] || printf '  %s\n' "$*"; }
log()   { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
exists() { [ -e "$1" ] || [ -L "$1" ]; }

remove_path() {
	# Remove a file/symlink/dir if present (dry-run aware).
	if exists "$1"; then
		run rm -rf -- "$1"
		return 0
	fi
	return 1
}

# link_or_copy SRC DST: in symlink mode make DST a symlink to SRC; in copy
# mode copy SRC into DST. DST's parent must exist.
link_or_copy() {
	_src="$1"; _dst="$2"
	if [ "$COPY" = 1 ]; then
		run cp -R -- "$_src" "$_dst"
	else
		run ln -s "$_src" "$_dst"
	fi
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------
if [ "$UNINSTALL" = 1 ]; then
	log "Uninstalling vsvim:"
	log "  launcher: $DEST"
	if remove_path "$DEST"; then note "removed"; else note "not present, skipping"; fi

	log "  config:   $CONFIGDIR"
	# Config dir is shared user state; only remove the bits we own, and only
	# if they're our symlinks (symlink mode). A real/copied config dir may hold
	# the user's keybindings.json, so leave it unless --copy was also passed.
	if [ -L "$CONFIGDIR/init.lua" ]; then
		for item in $RUNTIME_ITEMS; do
			remove_path "$CONFIGDIR/$item" || true
		done
		# Remove the dir only if it's now empty.
		if [ -z "$(ls -A "$CONFIGDIR" 2>/dev/null || true)" ]; then
			remove_path "$CONFIGDIR" && note "removed (now empty)" || true
		else
			note "kept non-empty dir (contains user files)"
		fi
	elif [ "$COPY" = 1 ] && [ -f "$CONFIGDIR/init.lua" ]; then
		for item in $RUNTIME_ITEMS; do
			remove_path "$CONFIGDIR/$item" || true
		done
		if [ -z "$(ls -A "$CONFIGDIR" 2>/dev/null || true)" ]; then
			remove_path "$CONFIGDIR" && note "removed (now empty)" || true
		else
			note "kept non-empty dir (contains user files)"
		fi
	else
		note "not wired by this installer, skipping"
	fi

	if [ "$COPY" = 1 ]; then
		log "  tree:     $PREFIX"
		if remove_path "$PREFIX"; then note "removed"; else note "not present, skipping"; fi
	fi
	exit 0
fi

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
log "Installing vsvim:"
log "  repo:     $REPO"
log "  bindir:   $BINDIR"
log "  config:   $CONFIGDIR"
log "  mode:     $( [ "$COPY" = 1 ] && echo copy || echo symlink )"

# Source root: where the real files live. In copy mode we first clone the tree
# into $PREFIX and use that as the source for everything else.
if [ "$COPY" = 1 ]; then
	log "  tree:     $PREFIX"
	if exists "$PREFIX" && [ "$PREFIX" != "/" ]; then
		run rm -rf -- "$PREFIX"
	fi
	run mkdir -p -- "$PREFIX"
	for item in $RUNTIME_ITEMS vsvim LICENSE README.md VERSION; do
		if [ -e "$REPO/$item" ]; then
			run cp -R -- "$REPO/$item" "$PREFIX/"
		fi
	done
	if [ "$DRY_RUN" != 1 ]; then
		chmod +x "$PREFIX/vsvim" 2>/dev/null || true
	fi
	SRCDIR="$PREFIX"
else
	SRCDIR="$REPO"
fi

# 1) Launcher on $PATH -> $SRCDIR/vsvim.
if [ ! -d "$BINDIR" ]; then
	run mkdir -p -- "$BINDIR"
fi
if exists "$DEST"; then
	run rm -f -- "$DEST"
fi
link_or_copy "$SRCDIR/vsvim" "$DEST"
if [ "$DRY_RUN" != 1 ]; then
	chmod +x "$DEST" 2>/dev/null || true
fi

# 1b) In --copy mode the launcher is a standalone file (not a symlink into the
#     repo), so bake the install prefix and version into it by replacing the
#     @@VSVIM_*@@ marker comments. This lets `vsvim --version` and
#     `vsvim update` work without the repo or a VERSION file next to the
#     launcher. Symlink mode leaves the markers as no-op comments and the
#     launcher reads VERSION from the repo at runtime.
if [ "$COPY" = 1 ] && [ "$DRY_RUN" != 1 ]; then
	inst_version="$(cat "$PREFIX/VERSION" 2>/dev/null || echo unknown)"
	[ -n "$inst_version" ] || inst_version="unknown"
	# Escape characters that are special in a sed replacement: \, &, and our
	# delimiter |. Paths rarely contain |, but escape it for safety.
	pfx_esc="$(printf '%s' "$PREFIX" | sed 's/[\\&|]/\\&/g')"
	ver_esc="$(printf '%s' "$inst_version" | sed 's/[\\&|]/\\&/g')"
	sed \
		-e "s|^# @@VSVIM_PREFIX@@$|VSVIM_INSTALL_PREFIX=\"$pfx_esc\"|" \
		-e "s|^# @@VSVIM_VERSION@@$|VSVIM_VERSION_BAKED=\"$ver_esc\"|" \
		"$DEST" > "$DEST.tmp" && mv -f "$DEST.tmp" "$DEST"
	chmod +x "$DEST" 2>/dev/null || true
fi

# 2) Wire the vsvim config dir so Neovim (via NVIM_APPNAME=vsvim) finds
#    init.lua / lua/ / plugin/ there. Existing files are left untouched so
#    users can drop their own overrides alongside (e.g. an extra lua/ module
#    or a real init.lua); we only (re)link our own runtime items.
if [ ! -d "$CONFIGDIR" ]; then
	run mkdir -p -- "$CONFIGDIR"
fi
for item in $RUNTIME_ITEMS; do
	if [ ! -e "$SRCDIR/$item" ]; then
		continue
	fi
	target="$CONFIGDIR/$item"
	if [ -L "$target" ]; then
		# Refresh our own symlink in place.
		run rm -f -- "$target"
		link_or_copy "$SRCDIR/$item" "$target"
	elif exists "$target" ]; then
		note "kept existing $item in config dir (not overwritten)"
	else
		link_or_copy "$SRCDIR/$item" "$target"
	fi
done

# 3) Record install metadata so `vsvim update` can reinstall with the same
#    paths. Written into the source root ($PREFIX in copy mode, $REPO in
#    symlink mode) as a shell-sourceable file.
if [ "$DRY_RUN" != 1 ]; then
	meta_version="$(cat "$SRCDIR/VERSION" 2>/dev/null || echo unknown)"
	meta_mode="$( [ "$COPY" = 1 ] && echo copy || echo symlink )"
	{
		echo "MODE=$meta_mode"
		echo "PREFIX=$SRCDIR"
		echo "BINDIR=$BINDIR"
		echo "CONFIGDIR=$CONFIGDIR"
		echo "VERSION=$meta_version"
	} > "$SRCDIR/.vsvim-meta"
fi

log
if [ "$DRY_RUN" = 1 ]; then
	log "(dry run, nothing was changed)"
else
	log "Done. Installed: $DEST"
fi

# ---------------------------------------------------------------------------
# PATH hint
# ---------------------------------------------------------------------------
case ":$PATH:" in
	*":$BINDIR:"*)
		note "$BINDIR is already on your PATH."
		;;
	*)
		log
		log "NOTE: $BINDIR is not on your PATH."
		log "  Add this to your shell rc (e.g. ~/.bashrc, ~/.zshrc):"
		log "    export PATH=\"$BINDIR:\$PATH\""
		;;
esac
