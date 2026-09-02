# yesall

Short commands that launch coding-agent CLIs with the most autonomous mode each tool officially supports.

```sh
cld "fix the failing test"
cdx "review this repository"
kmi
```

These commands deliberately reduce or remove approval checks. Use them only where you are comfortable letting the underlying agent act without confirmation.

## Install

One-line install from GitHub:

```sh
curl -fsSL https://raw.githubusercontent.com/minodevss/yesall/main/install.sh | sh
```

This is a `curl | sh` installer. It fetches the command wrappers directly from `raw.githubusercontent.com`; no clone or local checkout is required. Review `install.sh` before using it in a new environment.

Commands are installed into `~/.yesall/bin`, and the installer adds that directory to your PATH in the startup files your shell actually reads — `.zshrc` for zsh, both `.bashrc` and `.bash_profile` for bash, `config.fish` for fish. New terminals work with no further setup.

Only the shell you ran the installer in needs one more step, because a `curl | sh` pipeline cannot modify its parent shell:

```sh
source ~/.zshrc
```

The installer prints the exact line for your shell when it finishes.

Options:

| Variable | Effect |
| --- | --- |
| `YESALL_BIN_DIR` | Install into another directory. PATH is still configured unless the directory already resolves. |
| `YESALL_NO_PATH=1` | Install the commands and leave every startup file untouched. |

```sh
curl -fsSL https://raw.githubusercontent.com/minodevss/yesall/main/install.sh | YESALL_BIN_DIR=/usr/local/bin sh
```

The installer never overwrites an unmanaged file. Re-running it updates only files carrying the `yesall` marker, and the PATH block it writes is guarded so it cannot duplicate an entry no matter how often it is evaluated.

## Commands

| Shortcut | Agent | Mode |
| --- | --- | --- |
| `adr` | Aider | `--yes-always` |
| `amx` | Amp | `--dangerously-allow-all` |
| `cdx` | Codex CLI | `--dangerously-bypass-approvals-and-sandbox` |
| `cld` | Claude Code | `--dangerously-skip-permissions` |
| `cln` | Cline CLI | `--yolo` |
| `cpl` | GitHub Copilot CLI | `--allow-all-tools --allow-all-paths --allow-all-urls` |
| `cur` | Cursor Agent | `--force` |
| `grk` | Grok Build | `--permission-mode bypassPermissions` |
| `gse` | Goose | `GOOSE_MODE=auto` |
| `kir` | Kiro CLI | `chat --trust-all-tools` |
| `kmi` | Kimi Code | `--auto` |
| `opc` | OpenCode | permissive config |
| `qdev` | Amazon Q Developer | `chat --trust-all-tools` |
| `qwn` | Qwen Code | `--yolo` |

List every included shortcut and the command it launches:

```sh
yesall
```

Check which underlying CLIs are installed:

```sh
yesall doctor
```

Pull the latest shortcuts:

```sh
yesall update
```

The provider files are the source of truth, and `providers/index` lets the raw installer fetch them without cloning the repository. Gemini CLI is intentionally not included.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/minodevss/yesall/main/uninstall.sh | sh
```

Only files carrying the `yesall` marker are removed, including the PATH block in your startup files.

## Add a provider

Create one executable file in `providers/`. Its filename is the shortcut:

```sh
#!/bin/sh
# yesall:managed
# yesall:kind=provider
# yesall:name=Example Agent
# yesall:binary=example-agent
# yesall:prefix=--maximum-autonomy
# yesall:env=
# yesall:source=https://example.com/official-cli-reference
exec example-agent --maximum-autonomy "$@"
```

The installer, uninstaller, command listing, dependency doctor, and test suite discover it automatically.

## Test

```sh
./tests/run.sh
```
