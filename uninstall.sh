#!/bin/sh
set -eu

bin_dir=${YESALL_BIN_DIR:-$HOME/.yesall/bin}
marker='# yesall:managed'
path_begin='# yesall:path begin'
path_end='# yesall:path end'
raw_base=${YESALL_RAW_BASE:-https://raw.githubusercontent.com/minodevss/yesall/main}
removed=0
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
provider_dir=
tmp_dir=

if [ -d "$script_dir/providers" ]; then
    provider_dir=$script_dir/providers
else
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

tilde() {
    case $1 in
        "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
        *) printf '%s' "$1" ;;
    esac
}

remove_name() {
    name=$1
    target=$bin_dir/$name

    [ -e "$target" ] || [ -L "$target" ] || return 0
    if [ -f "$target" ] && [ ! -L "$target" ] && [ "$(sed -n '2p' "$target")" = "$marker" ]; then
        rm -f "$target"
        removed=$((removed + 1))
    else
        printf 'yesall: preserving unmanaged %s\n' "$target" >&2
    fi
}

remove_path_config() {
    [ "${YESALL_NO_PATH:-}" = 1 ] && return 0

    set -- "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zshenv" \
        "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" \
        "$HOME/.profile" "$HOME/.config/fish/config.fish"

    cleaned=
    for file do
        [ -f "$file" ] || continue
        grep -Fq "$path_begin" "$file" || continue

        temp_file=$(mktemp "${TMPDIR:-/tmp}/yesall-rc.XXXXXX")
        awk -v begin="$path_begin" -v end="$path_end" '
            skip { if ($0 == end) skip = 0; next }
            $0 == begin { skip = 1; pending = 0; next }
            $0 == "" { pending++; next }
            { for (i = 0; i < pending; i++) print ""; pending = 0; print }
            END { for (i = 0; i < pending; i++) print "" }
        ' "$file" >"$temp_file"
        # Rewrite in place so symlinked dotfiles keep pointing at their target.
        cat "$temp_file" >"$file"
        rm -f "$temp_file"
        cleaned="${cleaned}${cleaned:+, }$(tilde "$file")"
    done

    [ -n "$cleaned" ] && printf 'yesall: removed PATH entry from %s\n' "$cleaned"
    return 0
}

remove_name yesall
for provider in "$provider_dir"/*; do
    [ -f "$provider" ] || continue
    grep -q '^# yesall:kind=provider$' "$provider" || continue
    remove_name "${provider##*/}"
done

printf 'yesall: removed %s commands from %s\n' "$removed" "$(tilde "$bin_dir")"
remove_path_config

if [ -d "$HOME/.yesall/bin" ] && [ "${YESALL_BIN_DIR+x}" != x ]; then
    rmdir "$HOME/.yesall/bin" 2>/dev/null || true
    rmdir "$HOME/.yesall" 2>/dev/null || true
fi
