#!/bin/sh
set -eu

bin_dir=${YESALL_BIN_DIR:-$HOME/.yesall/bin}
marker='# yesall:managed'
path_begin='# yesall:path begin'
path_end='# yesall:path end'
removed=0
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
provider_dir=
tmp_dir=

if [ -d "$script_dir/providers" ]; then
    provider_dir=$script_dir/providers
else
    raw_base=${YESALL_RAW_BASE:-https://raw.githubusercontent.com/minodevss/yesall/main}
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/yesall-uninstall.XXXXXX")
    trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
    provider_dir=$tmp_dir/providers
    mkdir -p "$provider_dir"
    curl -fsSL "$raw_base/providers/index" -o "$tmp_dir/index"
    if [ ! -s "$tmp_dir/index" ]; then
        printf 'yesall: provider index is empty\n' >&2
        exit 1
    fi
    while IFS= read -r shortcut || [ -n "$shortcut" ]; do
        [ -n "$shortcut" ] || continue
        printf '# yesall:kind=provider\n' >"$provider_dir/$shortcut"
    done <"$tmp_dir/index"
fi

remove_name() {
    name=$1
    target=$bin_dir/$name

    [ -e "$target" ] || [ -L "$target" ] || return
    if [ -f "$target" ] && [ ! -L "$target" ] && [ "$(sed -n '2p' "$target")" = "$marker" ]; then
        rm -f "$target"
        removed=$((removed + 1))
    else
        printf 'yesall: preserving unmanaged %s\n' "$target" >&2
    fi
}

remove_path_config() {
    [ "${YESALL_BIN_DIR+x}" = x ] && return

    case ${SHELL##*/} in
        zsh) path_file=$HOME/.zshrc ;;
        bash) path_file=$HOME/.bashrc ;;
        *) return ;;
    esac
    [ -f "$path_file" ] || return
    grep -Fq "$path_begin" "$path_file" || return

    temp_file=$(mktemp "${path_file}.yesall.XXXXXX")
    awk -v begin="$path_begin" -v end="$path_end" '
        $0 == begin { skip = 1; next }
        $0 == end { skip = 0; next }
        !skip { print }
    ' "$path_file" >"$temp_file"
    mv "$temp_file" "$path_file"
    printf 'yesall: removed %s from %s\n' "$bin_dir" "$path_file"
}

remove_name yesall
for provider in "$provider_dir"/*; do
    [ -f "$provider" ] || continue
    grep -q '^# yesall:kind=provider$' "$provider" || continue
    remove_name "${provider##*/}"
done
remove_path_config

printf 'yesall: removed %s commands from %s\n' "$removed" "$bin_dir"
