# ssh-migrate

Make a fresh server feel like home in one command: copy your **GitHub CLI (`gh`)** and **git** configuration over SSH, and install your **SSH public key** into the remote `authorized_keys`.

```bash
curl -fsSL https://github.com/Ivanbeethoven/ssh-migrate/releases/latest/download/ssh-migrate -o ~/.local/bin/ssh-migrate \
  && chmod +x ~/.local/bin/ssh-migrate \
  && ssh-migrate <user@host>
```

That single line installs the script to `~/.local/bin` and runs it against `<user@host>`.
Prefer a system-wide install (needs `sudo`):

```bash
curl -fsSL https://github.com/Ivanbeethoven/ssh-migrate/releases/latest/download/ssh-migrate | sudo tee /usr/local/bin/ssh-migrate >/dev/null \
  && sudo chmod +x /usr/local/bin/ssh-migrate \
  && ssh-migrate <user@host>
```

Run it without installing anything:

```bash
curl -fsSL https://github.com/Ivanbeethoven/ssh-migrate/releases/latest/download/ssh-migrate | bash -s -- <user@host>
```

## What it does

Everything is migrated by default — no extra flags needed:

1. **SSH public key** — appends your public key to the remote `~/.ssh/authorized_keys` (idempotent; existing entries are skipped, the file is backed up first, permissions set to `700`/`600`).
2. **gh config** — copies `~/.config/gh/hosts.yml` and `config.yml`. If your token lives in the OS keyring instead of `hosts.yml`, it is fetched locally with `gh auth token` and re-applied on the remote via `gh auth login --with-token`.
3. **git config** — copies `~/.config/git/config` and/or `~/.gitconfig`.

Existing remote files are backed up with a `.bak-<timestamp>` suffix before being overwritten.

## Usage

```
ssh-migrate [options] <[user@]host>
```

`<host>` can be a plain hostname or a **`Host` alias from `~/.ssh/config`**; the alias' `User`, `HostName`, `Port` and `IdentityFile` are honoured automatically.

### Options

| Option | Description |
| --- | --- |
| `-n`, `--dry-run` | Show what would happen, change nothing |
| `-p`, `--port PORT` | SSH port |
| `-i`, `--identity FILE` | SSH private key (its `.pub` is also installed) |
| `--no-key` | Skip installing the SSH public key |
| `--no-gh` | Skip `~/.config/gh` |
| `--no-git` | Skip git config |
| `--pubkey FILE` | Public key file to install (repeatable) |
| `--credentials` | Also copy `~/.git-credentials` (plaintext secrets) |
| `-h`, `--help` | Show help |

### Examples

```bash
ssh-migrate myserver                      # migrate everything to an ssh-config alias
ssh-migrate -n root@203.0.113.10          # dry run against a plain host
ssh-migrate -p 2222 -i ~/.ssh/deploy user@host   # custom port and key
ssh-migrate --no-git --no-gh myserver     # only install the SSH public key
ssh-migrate --pubkey ~/.ssh/id_ed25519.pub myserver
```

## Requirements

- `bash`, `ssh`, `tar` on the local machine (and `bash`, `tar` on the remote).
- `gh` on the remote for the gh-config migration and auth verification.
- You must already be able to SSH into the host (password or an existing key) — that is how the migration is delivered.

## Security notes

- Tokens and keys are only transferred over the encrypted SSH channel; nothing is sent anywhere else.
- `~/.git-credentials` is **not** copied unless you pass `--credentials`.
- Always review a tool before piping it into a shell: read the source at [`ssh-migrate`](./ssh-migrate).

## License

MIT
