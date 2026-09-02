#!/bin/sh
set -eu

bin_dir=${YESALL_BIN_DIR:-$HOME/.yesall/bin}
marker='# yesall:managed'
path_begin='# yesall:path begin'
path_end='# yesall:path end'
status=0
installed=0
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
source_dir=
tmp_dir=

if [ -f "$script_dir/bin/yesall" ] && [ -d "$script_dir/providers" ]; then
    source_dir=$script_dir
else
    raw_base=${YESALL_RAW_BASE:-https://raw.githubusercontent.com/minodevss/yesall/main}
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/yesall-install.XXXXXX")
    trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
    source_dir=$tmp_dir/repo
    mkdir -p "$source_dir/bin" "$source_dir/providers"
    curl -fsSL "$raw_base/bin/yesall" -o "$source_dir/bin/yesall"
    curl -fsSL "$raw_base/providers/index" -o "$tmp_dir/index"
    if [ ! -s "$tmp_dir/index" ]; then
        printf 'yesall: provider index is empty\n' >&2
        exit 1
    fi
    while IFS= read -r shortcut || [ -n "$shortcut" ]; do
        [ -n "$shortcut" ] || continue
        curl -fsSL "$raw_base/providers/$shortcut" -o "$source_dir/providers/$shortcut"
    done <"$tmp_dir/index"
fi

mkdir -p "$bin_dir"

is_managed() {
    [ -f "$1" ] && [ ! -L "$1" ] && [ "$(sed -n '2p' "$1")" = "$marker" ]
}

install_one() {
    source_file=$1
    name=${source_file##*/}
    target=$bin_dir/$name

    if [ -e "$target" ] || [ -L "$target" ]; then
        if ! is_managed "$target"; then
            printf 'yesall: preserving existing %s\n' "$target" >&2
            status=1
            return
        fi
    fi

    temp_file=$(mktemp "$bin_dir/.yesall.XXXXXX")
    if ! cp "$source_file" "$temp_file" || ! chmod 755 "$temp_file"; then
        rm -f "$temp_file"
        return 1
    fi
    mv -f "$temp_file" "$target"
    installed=$((installed + 1))
}

field() {
    key=$1
    file=$2
    sed -n "s/^# yesall:$key=//p" "$file"
}

configure_path() {
    [ "${YESALL_BIN_DIR+x}" = x ] && return

    case ${SHELL##*/} in
        zsh) path_file=$HOME/.zshrc ;;
        bash) path_file=$HOME/.bashrc ;;
        *) path_file= ;;
    esac

    case :${PATH:-}: in
        *:"$bin_dir":*) return ;;
    esac

    if [ -n "$path_file" ]; then
        touch "$path_file"
        if ! grep -Fq "$path_begin" "$path_file"; then
            {
                printf '\n%s\n' "$path_begin"
                printf "export PATH=\"%s:\$PATH\"\n" "$bin_dir"
                printf '%s\n' "$path_end"
            } >>"$path_file"
        fi
        printf 'yesall: added %s to %s\n' "$bin_dir" "$path_file" >&2
        printf 'yesall: run: source %s\n' "$path_file" >&2
    else
        printf 'yesall: add this to your shell:\n' >&2
        printf "  export PATH=\"%s:\$PATH\"\n" "$bin_dir" >&2
    fi
}

install_one "$source_dir/bin/yesall"
for provider in "$source_dir"/providers/*; do
    [ -f "$provider" ] || continue
    grep -q '^# yesall:kind=provider$' "$provider" || continue
    install_one "$provider"
done

printf 'yesall: installed %s commands in %s\n' "$installed" "$bin_dir"
printf '\nAvailable commands:\n'
for provider in "$source_dir"/providers/*; do
    [ -f "$provider" ] || continue
    grep -q '^# yesall:kind=provider$' "$provider" || continue
    name=${provider##*/}
    if is_managed "$bin_dir/$name"; then
        printf '  %-5s %s\n' "$name" "$(field name "$provider")"
    fi
done
configure_path

exit "$status"
