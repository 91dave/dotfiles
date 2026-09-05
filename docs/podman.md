# Podman

Podman runs natively inside the `Ubuntu-24.04` WSL distribution. The Windows `podman.exe`
client and Podman Desktop both reach it over SSH, so the Linux CLI, the Windows CLI and the
desktop app drive one container environment rather than three.

## How it is wired

```
Windows                             WSL (Ubuntu-24.04)
-------                             ------------------
podman.exe     ─┐                   sshd (127.0.0.1:22)
Podman Desktop ─┴─ssh://dave@127.0.0.1:22─▶ │
                                            ▼
                                          podman.socket
                                            │ socket activation
                                            ▼
                                          podman system service
                                            │
                                          podman 4.9.3
```

| Piece | Where |
|---|---|
| API socket | `podman.socket`, shipped by the distro, listening on `/run/user/1002/podman/podman.sock` |
| SSH server | `openssh-server`, configured by `dotfiles/ssh/sshd-podman.conf` |
| Key | `~/.ssh/podman_ed25519`, public half in `~/.ssh/authorized_keys` |
| Windows copy of the key | `C:\Users\DaveA\.ssh\podman_ed25519` |
| Windows connection | `wsl-ubuntu`, `ssh://dave@127.0.0.1:22/run/user/1002/podman/podman.sock`, set as default |
| Connection store | `%APPDATA%\containers\podman-connections.json` |
| Podman Desktop | preference `podman.system.connections.remote` set to `true` |

WSL2 forwards loopback from Windows into the distro, so no port mapping is needed. `sshd`
binds `127.0.0.1` only, so nothing on the LAN can reach it.

## Setup on a new machine

`install.sh` does not cover this: the SSH server needs root, and the key is machine-specific.

```bash
sudo apt-get update && sudo apt-get install -y openssh-server
sudo cp dotfiles/ssh/sshd-podman.conf /etc/ssh/sshd_config.d/10-podman-wsl.conf
sudo systemctl enable --now ssh

ssh-keygen -t ed25519 -N '' -f ~/.ssh/podman_ed25519 -C "podman-wsl-$(hostname)"
cat ~/.ssh/podman_ed25519.pub >> ~/.ssh/authorized_keys
cp ~/.ssh/podman_ed25519 "$USERPROFILE_WIN/.ssh/podman_ed25519"

podman.exe system connection add --identity 'C:/Users/DaveA/.ssh/podman_ed25519' \
    wsl-ubuntu 'ssh://dave@127.0.0.1:22/run/user/1002/podman/podman.sock'
podman.exe system connection default wsl-ubuntu
```

Then in Podman Desktop, Settings, Preferences, Extension: Podman, tick **Load remote system
connections (ssh)** and restart it. The same preference can be set directly in
`C:\Users\DaveA\.local\share\containers\podman-desktop\configuration\settings.json` while the
app is closed.

## Everyday use

All three clients hit the same store:

```bash
podman ps          # native Linux client, no network hop
podman.exe ps      # Windows client, over SSH
```

The Windows client translates Windows paths for bind mounts, so both of these work:

```bash
podman.exe run --rm -v 'C:\Code\_personal\dotfiles:/m:ro' <image> ls /m
podman.exe run --rm -v '/mnt/c/Code/_personal/dotfiles:/m:ro' <image> ls /m
```

`ce check` reports whether the engine is reachable and `ce fix` starts `podman.socket`.
`wsltop` shows container counts and podman's memory and CPU share per distro.

## Gotchas

**The key must be ed25519 and the identity path absolute.** Podman Desktop rejects RSA, and a
`~` prefix in the identity path does not resolve on Windows.

**Two copies of the private key exist.** The WSL copy at `~/.ssh/podman_ed25519` is the
canonical one, the copy in the Windows profile is what `podman.exe` and Podman Desktop read.
Regenerating the key means replacing both and updating `authorized_keys`.

**sshd needs root, so a fresh distro is not fully set up by `install.sh`.** Follow the setup
section above. If `ce fix` fails, check `systemctl is-active ssh` first.

**Linger.** Without `sudo loginctl enable-linger $USER` the user systemd manager can stop when
no shell is open in the distro, taking `podman.socket` with it. Everything works while a shell
is open either way.

**Version skew.** The Windows client is 5.2.2 against a 4.9.3 server, because Ubuntu 24.04
ships 4.9.3. Everyday commands work, but this is not a combination upstream tests, and newer
client endpoints can fail against the older server.

## History: the TCP socket

Before SSH, `podman.exe` reached the distro over an unauthenticated `tcp://127.0.0.1:8899`
socket, served by `podman-tcp.socket` and `podman-tcp.service` in this repo. Podman Desktop
could not use it, since it only supports `ssh://` connections, and any process on the Windows
host could drive podman through it. SSH replaced both problems at once, so those units are
gone.

## The old machine

`podman-machine-default` is still registered and holds a **126.2 GB non-sparse** `ext4.vhdx`,
despite being unused since June. Nothing depends on it now that Podman Desktop uses the SSH
connection. Removing it reclaims that space:

```bash
podman.exe machine rm podman-machine-default
```

This also deletes the two `podman-machine-default*` connections.
