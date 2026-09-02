#!/bin/sh
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/yesall-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
fake_bin=$test_dir/fake-bin
mkdir -p "$fake_bin"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

field() {
    key=$1
    file=$2
    sed -n "s/^# yesall:$key=//p" "$file"
}

fake_command=$test_dir/fake-command
cat >"$fake_command" <<'FAKE'
#!/bin/sh
printf 'binary=%s\n' "${0##*/}"
for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
done
printf 'env:OPENCODE_CONFIG_CONTENT=%s\n' "${OPENCODE_CONFIG_CONTENT-}"
printf 'env:GOOSE_MODE=%s\n' "${GOOSE_MODE-}"
exit "${YESALL_FAKE_EXIT:-0}"
FAKE
chmod 755 "$fake_command"

for provider in "$repo_dir"/providers/*; do
    grep -q '^# yesall:kind=provider$' "$provider" || continue
    sh -n "$provider"
    binary=$(field binary "$provider")
    [ -e "$fake_bin/$binary" ] || ln -s "$fake_command" "$fake_bin/$binary"
done
sh -n "$repo_dir/bin/yesall"
sh -n "$repo_dir/install.sh"
sh -n "$repo_dir/uninstall.sh"

for provider in "$repo_dir"/providers/*; do
    grep -q '^# yesall:kind=provider$' "$provider" || continue
    binary=$(field binary "$provider")
    prefix=$(field prefix "$provider")
    env_value=$(field env "$provider")
    actual=$(PATH="$fake_bin:$PATH" "$provider" 'two words' '*' '--flag=value')

    expected=$(
        printf 'binary=%s\n' "$binary"
        set -f
        old_ifs=$IFS
        IFS=' '
        # Provider prefixes are controlled, space-delimited argv metadata.
        # shellcheck disable=SC2086
        set -- $prefix
        IFS=$old_ifs
        for arg in "$@"; do
            [ -n "$arg" ] && printf 'arg=%s\n' "$arg"
        done
        printf 'arg=two words\narg=*\narg=--flag=value\n'
        opencode_value=
        goose_value=
        if [ "${env_value#OPENCODE_CONFIG_CONTENT=}" != "$env_value" ]; then
            opencode_value=${env_value#*=}
        fi
        if [ "${env_value#GOOSE_MODE=}" != "$env_value" ]; then
            goose_value=${env_value#*=}
        fi
        printf 'env:OPENCODE_CONFIG_CONTENT=%s\n' "$opencode_value"
        printf 'env:GOOSE_MODE=%s\n' "$goose_value"
    )

    [ "$actual" = "$expected" ] || fail "argument or environment forwarding: ${provider##*/}"
done

set +e
PATH="$fake_bin:$PATH" YESALL_FAKE_EXIT=37 "$repo_dir/providers/cld" >/dev/null
exit_status=$?
set -e
[ "$exit_status" -eq 37 ] || fail 'exit status forwarding'

"$repo_dir/bin/yesall" --help | grep -F 'update' >/dev/null || fail 'update subcommand in usage'

# Installation into an explicit directory, with the isolated home keeping the
# runner's own startup files out of reach.
generic_home=$test_dir/generic-home
mkdir -p "$generic_home"
install_bin=$test_dir/install-bin
export HOME="$generic_home" YESALL_NO_PATH=1
YESALL_BIN_DIR="$install_bin" "$repo_dir/install.sh" >/dev/null
YESALL_BIN_DIR="$install_bin" "$repo_dir/install.sh" >/dev/null
[ -x "$install_bin/yesall" ] || fail 'control command installation'
[ -x "$install_bin/cld" ] || fail 'provider installation'
PATH="$fake_bin:$install_bin:$PATH" "$install_bin/yesall" doctor >/dev/null
"$install_bin/yesall" list | grep 'Claude Code' >/dev/null || fail 'provider discovery'

YESALL_BIN_DIR="$install_bin" "$repo_dir/uninstall.sh" >/dev/null
[ ! -e "$install_bin/yesall" ] || fail 'control command removal'
[ ! -e "$install_bin/cld" ] || fail 'provider removal'

collision_bin=$test_dir/collision-bin
mkdir -p "$collision_bin"
printf 'user file\n' >"$collision_bin/cld"
set +e
YESALL_BIN_DIR="$collision_bin" "$repo_dir/install.sh" >/dev/null 2>&1
collision_status=$?
set -e
[ "$collision_status" -ne 0 ] || fail 'collision status'
[ "$(cat "$collision_bin/cld")" = 'user file' ] || fail 'collision preservation'
[ -x "$collision_bin/cdx" ] || fail 'partial installation after collision'
YESALL_BIN_DIR="$collision_bin" "$repo_dir/uninstall.sh" >/dev/null
[ "$(cat "$collision_bin/cld")" = 'user file' ] || fail 'uninstall preservation'
[ ! -e "$collision_bin/cdx" ] || fail 'managed collision-set removal'
unset HOME YESALL_NO_PATH

# PATH configuration. Each case gets its own home so a stray write is visible.
home_for() {
    home_dir=$test_dir/home-$1
    mkdir -p "$home_dir"
    printf '%s' "$home_dir"
}

install_as() {
    install_home=$1
    install_shell=$2
    install_path=$3
    shift 3
    env -i \
        HOME="$install_home" \
        SHELL="$install_shell" \
        PATH="$install_path" \
        TMPDIR="${TMPDIR:-/tmp}" \
        "$@" "$repo_dir/install.sh" >/dev/null 2>&1
}

base_path=/usr/bin:/bin
marker_begin='# yesall:path begin'

zsh_home=$(home_for zsh)
install_as "$zsh_home" /bin/zsh "$base_path"
grep -Fq "$marker_begin" "$zsh_home/.zshrc" || fail 'zsh path configuration'

# The generated block must actually put the directory on PATH, and stay
# harmless when the startup file is evaluated more than once.
sourced_path=$(HOME="$zsh_home" PATH="$base_path" sh -c '. "$HOME/.zshrc" >/dev/null 2>&1; . "$HOME/.zshrc" >/dev/null 2>&1; printf "%s" "$PATH"')
case ":$sourced_path:" in
    *":$zsh_home/.yesall/bin:"*) ;;
    *) fail 'path block does not export the bin directory' ;;
esac
[ "$(printf '%s' "$sourced_path" | tr ':' '\n' | grep -c '\.yesall/bin$')" -eq 1 ] ||
    fail 'path block duplicates the bin directory'

install_as "$zsh_home" /bin/zsh "$base_path"
[ "$(grep -Fc "$marker_begin" "$zsh_home/.zshrc")" -eq 1 ] || fail 'path configuration idempotence'

# bash reads .bash_profile when it starts as a login shell and .bashrc when it
# does not, so both have to carry the block.
bash_home=$(home_for bash)
: >"$bash_home/.bash_profile"
install_as "$bash_home" /bin/bash "$base_path"
grep -Fq "$marker_begin" "$bash_home/.bashrc" || fail 'bash .bashrc configuration'
grep -Fq "$marker_begin" "$bash_home/.bash_profile" || fail 'bash .bash_profile configuration'

fish_home=$(home_for fish)
install_as "$fish_home" /opt/homebrew/bin/fish "$base_path"
grep -Fq 'fish_add_path' "$fish_home/.config/fish/config.fish" || fail 'fish path configuration'

# A directory that is already on PATH for this process says nothing about the
# next shell, so the startup file still has to be written.
preset_home=$(home_for preset)
install_as "$preset_home" /bin/zsh "$preset_home/.yesall/bin:$base_path"
grep -Fq "$marker_begin" "$preset_home/.zshrc" || fail 'path persisted when already on PATH'

custom_home=$(home_for custom)
custom_bin=$test_dir/custom-bin
install_as "$custom_home" /bin/zsh "$base_path" YESALL_BIN_DIR="$custom_bin"
grep -Fq "$custom_bin" "$custom_home/.zshrc" || fail 'custom bin dir path configuration'

optout_home=$(home_for optout)
install_as "$optout_home" /bin/zsh "$base_path" YESALL_NO_PATH=1
[ ! -e "$optout_home/.zshrc" ] || fail 'YESALL_NO_PATH opt-out'

# Dotfiles are commonly symlinks into a managed repository; rewriting must
# follow the link instead of replacing it.
symlink_home=$(home_for symlink)
real_rc=$test_dir/real-zshrc
printf 'keep me\n' >"$real_rc"
ln -s "$real_rc" "$symlink_home/.zshrc"
install_as "$symlink_home" /bin/zsh "$base_path"
[ -L "$symlink_home/.zshrc" ] || fail 'symlinked startup file replaced'
grep -Fq 'keep me' "$real_rc" || fail 'symlink target content lost'
grep -Fq "$marker_begin" "$real_rc" || fail 'symlink target not configured'

# Uninstall clears every startup file it can find, and repeated cycles must not
# accumulate blank lines.
cleanup_home=$(home_for cleanup)
: >"$cleanup_home/.bash_profile"
install_as "$cleanup_home" /bin/bash "$base_path"
HOME="$cleanup_home" PATH="$base_path" "$repo_dir/uninstall.sh" >/dev/null 2>&1
grep -Fq "$marker_begin" "$cleanup_home/.bashrc" && fail 'bashrc path removal'
grep -Fq "$marker_begin" "$cleanup_home/.bash_profile" && fail 'bash_profile path removal'

roundtrip_home=$(home_for roundtrip)
printf 'original\n' >"$roundtrip_home/.zshrc"
for _ in 1 2 3; do
    install_as "$roundtrip_home" /bin/zsh "$base_path"
    HOME="$roundtrip_home" PATH="$base_path" "$repo_dir/uninstall.sh" >/dev/null 2>&1
done
[ "$(cat "$roundtrip_home/.zshrc")" = 'original' ] || fail 'startup file roundtrip cleanliness'

printf 'PASS: yesall\n'
