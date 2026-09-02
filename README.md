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

Commands are installed into `~/.yesall/bin`. Add it to your current shell's PATH:

```sh
export PATH="$HOME/.yesall/bin:$PATH"
```

Set `YESALL_BIN_DIR` to choose another directory:

```sh
curl -fsSL https://raw.githubusercontent.com/minodevss/yesall/main/install.sh | YESALL_BIN_DIR=/usr/local/bin sh
```

The installer never overwrites an unmanaged file. Re-running it updates only files carrying the `yesall` marker.

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

The provider files are the source of truth, and `providers/index` lets the raw installer fetch them without cloning the repository. Gemini CLI is intentionally not included.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/minodevss/yesall/main/uninstall.sh | sh
```

Only files carrying the `yesall` marker are removed.

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
