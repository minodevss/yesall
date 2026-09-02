#!/bin/sh
set -eu

bin_dir=${YESALL_BIN_DIR:-$HOME/.yesall/bin}
marker='# yesall:managed'
path_begin='# yesall:path begin'
path_end='# yesall:path end'
raw_base=${YESALL_RAW_BASE:-https://raw.githubusercontent.com/minodevss/yesall/main}
shell_kind=${SHELL##*/}
status=0
installed=0
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
source_dir=
tmp_dir=

case $bin_dir in
    "$HOME"/*) bin_expr="\$HOME${bin_dir#"$HOME"}" ;;
    *) bin_expr=$bin_dir ;;
esac

if [ -f "$script_dir/bin/yesall" ] && [ -d "$script_dir/providers" ]; then
    source_dir=$script_dir
else
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

tilde() {
    case $1 in
        "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
        *) printf '%s' "$1" ;;
    esac
}

render_block() {
    printf '%s\n' "$path_begin"
    if [ "$shell_kind" = fish ]; then
        printf 'fish_add_path -g "%s"\n' "$bin_expr"
    else
        printf 'case ":$PATH:" in\n'
        printf '    *":%s:"*) ;;\n' "$bin_expr"
        printf '    *) PATH="%s:$PATH" ;;\n' "$bin_expr"
        printf 'esac\n'
        printf 'export PATH\n'
    fi
    printf '%s\n' "$path_end"
}

# Writes the managed PATH block into one startup file. Returns 0 when the file
# changed, 1 when it already carried the exact block.
sync_path_file() {
    file=$1
    dir=${file%/*}

    [ "$dir" = "$file" ] || [ -d "$dir" ] || mkdir -p "$dir"
    [ -e "$file" ] || : >"$file"

    if grep -Fq "$path_begin" "$file"; then
        current=$(awk -v begin="$path_begin" -v end="$path_end" '
            $0 == begin { inside = 1 }
            inside { print }
            $0 == end { inside = 0 }
        ' "$file")
        [ "$current" = "$(render_block)" ] && return 1

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
    fi

    { printf '\n'; render_block; } >>"$file"
}

configure_path() {
    [ "${YESALL_NO_PATH:-}" = 1 ] && return 0

    # A caller-chosen directory that already resolves needs no startup file edit.
    if [ "${YESALL_BIN_DIR+x}" = x ]; then
        case :${PATH:-}: in
            *:"$bin_dir":*) return 0 ;;
        esac
    fi

    case $shell_kind in
        zsh) set -- "$HOME/.zshrc" ;;
        bash) set -- "$HOME/.bashrc" "$HOME/.bash_profile" ;;
        fish) set -- "$HOME/.config/fish/config.fish" ;;
        *) set -- "$HOME/.profile" ;;
    esac

    primary=$1
    updated=
    for file do
        if sync_path_file "$file"; then
            updated="${updated}${updated:+, }$(tilde "$file")"
        fi
    done

    printf '\n'
    if [ -n "$updated" ]; then
        printf 'yesall: added %s to PATH in %s\n' "$(tilde "$bin_dir")" "$updated"
    else
        printf 'yesall: PATH already configured in %s\n' "$(tilde "$primary")"
    fi

    case :${PATH:-}: in
        *:"$bin_dir":*)
            printf 'yesall: ready to use\n'
            ;;
        *)
            printf 'Open a new terminal, or run this once:\n\n'
            printf '  source %s\n' "$(tilde "$primary")"
            ;;
    esac
}

install_one "$source_dir/bin/yesall"
for provider in "$source_dir"/providers/*; do
    [ -f "$provider" ] || continue
    grep -q '^# yesall:kind=provider$' "$provider" || continue
    install_one "$provider"
done

printf 'yesall: installed %s commands in %s\n' "$installed" "$(tilde "$bin_dir")"
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
