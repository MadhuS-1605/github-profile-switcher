# ◉ ghswitch

> **GitHub Account Switcher for the terminal** — switch git identities instantly, GitKraken-style, from the command line.

```
╔══════════════════════════════════════════╗
║  ◉ ghswitch  GitHub Account Switcher   ║
╚══════════════════════════════════════════╝

▸ Switch global profile
  ↑↓ / j k to navigate · Enter to select · q to quit

  ██  › work                  ● active
      personal
      client-acme
```

---

## Features

- **Arrow-key TUI** — navigate profiles like GitKraken's profile switcher
- **Per-repo override** — apply a profile locally without touching global config
- **Full identity stack** — manages git config, SSH keys, GPG signing, and gh CLI
- **bash 3.2+ compatible** — works on macOS (default bash), Linux, and Windows Git Bash / WSL
- **Zero dependencies** — just bash + git. No npm, no Python, no package manager.
- **Direct switch** — `ghswitch work` with no menu for scripting and speed

---

## Installation

```bash
# 1. Download
curl -O https://raw.githubusercontent.com/MadhuS-1605/Github-Profile-Switcher/main/ghswitch.sh

# 2. Make executable
chmod +x ghswitch.sh

# 3. Install globally
sudo cp ghswitch.sh /usr/local/bin/ghswitch

# 4. Verify
ghswitch help
```

**Linux (no sudo)**
```bash
mkdir -p ~/.local/bin
cp ghswitch.sh ~/.local/bin/ghswitch
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
```

**Windows (Git Bash)**
```bash
mkdir -p ~/bin
cp ghswitch.sh ~/bin/ghswitch
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
```

> **Important:** Always use `git@github.com:...` (SSH) remote URLs — not HTTPS — so ghswitch's key management takes effect.

---

## Quick Start

```bash
# Add your accounts
ghswitch add          # prompts: name, email, SSH key, GPG key, gh host

# See all profiles
ghswitch list

# Launch the TUI switcher
ghswitch

# Or switch directly by name
ghswitch work
ghswitch personal
```

---

## Commands

| Command | Description |
|---|---|
| `ghswitch` | Interactive arrow-key profile switcher |
| `ghswitch add` | Add a new profile (guided prompts) |
| `ghswitch list` | List all profiles with active marker |
| `ghswitch local` | Apply profile to current repo only (`git --local`) |
| `ghswitch status` | Show current git identity + gh CLI auth |
| `ghswitch unset` | Clear global git identity |
| `ghswitch edit` | Open `profiles.conf` in `$EDITOR` |
| `ghswitch delete` | Remove a profile |
| `ghswitch <name>` | Switch directly, e.g. `ghswitch work` |
| `ghswitch help` | Show help |

---

## What It Manages

| Layer | Config Key | Effect |
|---|---|---|
| Git identity | `user.name` / `user.email` | Commit author, global or per-repo |
| SSH key | `core.sshCommand` | Forces specific key with `IdentitiesOnly=yes` |
| SSH agent | *(runtime)* | Adds key to agent if socket is active |
| GPG signing | `user.signingKey` + `commit.gpgSign` | Signed commits with your key |
| gh CLI | *(runtime check)* | Verifies `gh auth status` for the configured host |

---

## Config File

Located at `~/.config/ghswitch/profiles.conf`. Created automatically on first run.

```ini
[work]
name=Jane Doe
email=jane@company.com
ssh_key=~/.ssh/id_ed25519_work
gpg_key=ABCD1234
gh_host=github.com

[personal]
name=Jane Doe
email=jane@gmail.com
ssh_key=~/.ssh/id_ed25519_personal
gh_host=github.com

[client-acme]
name=Jane Doe
email=jane@acme.io
ssh_key=~/.ssh/id_ed25519_acme
gh_host=github.com
```

All fields except `name` and `email` are optional.

---

## SSH Key Setup

Generate a separate key per account and add each public key to the respective GitHub account under **Settings → SSH and GPG keys**.

```bash
# Work
ssh-keygen -t ed25519 -C "you@company.com" -f ~/.ssh/id_ed25519_work

# Personal
ssh-keygen -t ed25519 -C "you@gmail.com" -f ~/.ssh/id_ed25519_personal

# Copy public key to clipboard (macOS)
cat ~/.ssh/id_ed25519_work.pub | pbcopy
```

Fix permissions if you see SSH warnings:
```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519_work      # private key
chmod 644 ~/.ssh/id_ed25519_work.pub  # public key
```

---

## Per-repo Override

Apply a profile to a single repo without changing your global identity:

```bash
cd ~/projects/client-website
ghswitch local          # pick "client-acme" from the menu
git config user.email   # confirms local override is active
```

---

## Troubleshooting

**Blank output / no prompts**
```bash
bash -x ghswitch add 2>&1 | head -40
# If line 2 shows "set -euo pipefail" — old version is still installed
sudo cp ghswitch.sh $(which ghswitch)
```

**403 on git push**
```bash
# Switch remote from HTTPS to SSH
git remote set-url origin git@github.com:USERNAME/REPO.git

# Clear stale macOS Keychain credentials
git credential-osxkeychain erase <<EOF
protocol=https
host=github.com
EOF
```

**Wrong key being used**
```bash
ghswitch status         # check active profile and sshCommand
ghswitch edit           # fix ssh_key path — must point to private key, not .pub
```

**gh CLI warning on switch**
```bash
gh auth login --hostname github.com
```

---

## Compatibility

| Platform | Shell | Status |
|---|---|---|
| macOS (12+) | bash 3.2 (system) | ✅ Tested |
| macOS (12+) | zsh (via bash shebang) | ✅ Works |
| Ubuntu / Debian | bash 5.x | ✅ Tested |
| Windows | Git Bash (MINGW) | ✅ Works |
| Windows | WSL2 | ✅ Works |

---

## License

MIT