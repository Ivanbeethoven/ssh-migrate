# ssh-migrate

Make a fresh server feel like home in one command: copy your **GitHub CLI (`gh`)** and **git** configuration over SSH, and install your **SSH public key** into the remote `authorized_keys`.

Works on **Linux, macOS, WSL, Git Bash / MSYS2 / Cygwin** (bash) and **Windows PowerShell**.

## Install & run (one line)

**Linux / macOS / WSL / Git Bash** — installs to `~/.local/bin` and runs:

```bash
curl -fsSL https://github.com/Ivanbeethoven/ssh-migrate/releases/latest/download/ssh-migrate -o ~/.local/bin/ssh-migrate \
  && chmod +x ~/.local/bin/ssh-migrate \
  && ssh-migrate <user@host>
```

**Windows PowerShell** — downloads the script and runs it:

```powershell
iwr -useb https://github.com/Ivanbeethoven/ssh-migrate/releases/latest/download/ssh-migrate.ps1 -OutFile "$env:TEMP\ssh-migrate.ps1"; & "$env:TEMP\ssh-migrate.ps1" <user@host>
```

System-wide bash install (needs `sudo`):

```bash
curl -fsSL https://github.com/Ivanbeethoven/ssh-migrate/releases/latest/download/ssh-migrate | sudo tee /usr/local/bin/ssh-migrate >/dev/null \
  && sudo chmod +x /usr/local/bin/ssh-migrate \
  && ssh-migrate <user@host>
```

Run the bash version without installing anything:

```bash
curl -fsSL https://github.com/Ivanbeethoven/ssh-migrate/releases/latest/download/ssh-migrate | bash -s -- <user@host>
```

## What it does

Everything is migrated by default — no extra flags needed:

1. **SSH public key** — appends your public key to the remote `~/.ssh/authorized_keys` (idempotent; existing entries are skipped, the file is backed up first, permissions set to `700`/`600`).
2. **gh config** — copies `hosts.yml` and `config.yml`. If your token lives in the OS keyring instead of `hosts.yml`, it is fetched locally with `gh auth token` and re-applied on the remote via `gh auth login --with-token`.
3. **git config** — copies the XDG config and/or `~/.gitconfig`.

Existing remote files are backed up with a `.bak-<timestamp>` suffix before being overwritten.

Local config locations are detected per platform:

| | Linux / macOS / WSL | Windows |
| --- | --- | --- |
| gh | `~/.config/gh` (or `$GH_CONFIG_DIR`) | `%APPDATA%\GitHub CLI` |
| git | `~/.config/git/config`, `~/.gitconfig` | `%USERPROFILE%\.gitconfig` |
| ssh | `~/.ssh` | `%USERPROFILE%\.ssh` |

## Usage

```
ssh-migrate [options] <[user@]host>
```

`<host>` can be a plain hostname or a **`Host` alias from `~/.ssh/config`**; the alias' `User`, `HostName`, `Port` and `IdentityFile` are honoured automatically.

### Options

The same options exist in both scripts (PowerShell uses the usual `-Name` form, e.g. `-DryRun`, `-NoGit`).

| Option | Description |
| --- | --- |
| `-n`, `--dry-run` / `-DryRun` | Show what would happen, change nothing |
| `-p`, `--port PORT` / `-Port` | SSH port |
| `-i`, `--identity FILE` / `-Identity` | SSH private key (its `.pub` is also installed) |
| `--no-key` / `-NoKey` | Skip installing the SSH public key |
| `--no-gh` / `-NoGh` | Skip the gh configuration |
| `--no-git` / `-NoGit` | Skip git config |
| `--pubkey FILE` / `-Pubkey` | Public key file to install (repeatable) |
| `--credentials` / `-Credentials` | Also copy `~/.git-credentials` (plaintext secrets) |
| `-h`, `--help` | Show help (bash) |

### Examples

```bash
ssh-migrate myserver                      # migrate everything to an ssh-config alias
ssh-migrate -n root@203.0.113.10          # dry run against a plain host
ssh-migrate -p 2222 -i ~/.ssh/deploy user@host   # custom port and key
ssh-migrate --no-git --no-gh myserver     # only install the SSH public key
ssh-migrate --pubkey ~/.ssh/id_ed25519.pub myserver
```

```powershell
.\ssh-migrate.ps1 myserver
.\ssh-migrate.ps1 -DryRun root@203.0.113.10
.\ssh-migrate.ps1 -Port 2222 -Identity $HOME\.ssh\deploy user@host
.\ssh-migrate.ps1 -NoGit -NoGh myserver
```

## Requirements

- Local: `ssh` and, for the bash script, `bash` and `tar`. On Windows the PowerShell script uses the built-in OpenSSH client (Windows 10+).
- Remote: `bash`, `base64` and `tar` (any normal Linux/macOS host).
- `gh` on the remote for the gh-config migration and auth verification.
- You must already be able to SSH into the host (password or an existing key) — that is how the migration is delivered.

## Security notes

- Tokens and keys are only transferred over the encrypted SSH channel; nothing is sent anywhere else.
- `~/.git-credentials` is **not** copied unless you pass `--credentials` / `-Credentials`.
- Always review a tool before piping it into a shell: read the source at [`ssh-migrate`](./ssh-migrate) and [`ssh-migrate.ps1`](./ssh-migrate.ps1).

## License

MIT
