# Podman

Podman runs natively inside the `Ubuntu-24.04` WSL distribution. The Windows `podman.exe`
client talks to it over a loopback TCP socket, so the Linux and Windows CLIs drive one
container environment rather than two.

## How it is wired

```
Windows                          WSL (Ubuntu-24.04)
-------                          ------------------
podman.exe  ──tcp://127.0.0.1:8899──▶  podman-tcp.socket
                                         │ socket activation
                                         ▼
                                       podman system service
                                         │
                                       podman 4.9.3
```

| Piece | Where |
|---|---|
| Socket unit | `dotfiles/systemd/podman-tcp.socket`, listening on `127.0.0.1:8899` |
| Service unit | `dotfiles/systemd/podman-tcp.service`, socket-activated |
| Windows connection | `wsl-ubuntu`, `tcp://127.0.0.1:8899`, set as default |
| Connection store | `%APPDATA%\containers\podman-connections.json` |

WSL2 forwards loopback from Windows into the distro, so no port mapping is needed.

`install.sh` links both units into `~/.config/systemd/user/`, plus a third symlink into
`sockets.target.wants/` which is what enables the socket at login.

## Everyday use

Both clients hit the same store, so either works:

```bash
podman ps          # native Linux client, no network hop
podman.exe ps      # Windows client, over the TCP socket
```

The Windows client translates Windows paths for bind mounts, so both of these work:

```bash
podman.exe run --rm -v 'C:\Code\_personal\dotfiles:/m:ro' <image> ls /m
podman.exe run --rm -v '/mnt/c/Code/_personal/dotfiles:/m:ro' <image> ls /m
```

`ce check` reports whether the engine is reachable and `ce fix` starts the socket. `wsltop`
shows container counts and podman's memory and CPU share per distro.

## Gotchas

**Never run `systemctl --user disable podman-tcp.socket`.** The unit files are symlinks into
this repo, and systemd treats a symlinked unit in the config directory as an enablement
symlink, so `disable` deletes it. Run `./install.sh` to put it back. Enablement is handled by
the `sockets.target.wants` symlink that `install.sh` creates, which is why `ce fix` only ever
starts the socket and never enables it.

**Linger.** Without `sudo loginctl enable-linger $USER` the user systemd manager can stop when
no shell is open in the distro, taking the socket with it. Everything works while a shell is
open either way.

**The socket is unauthenticated.** Podman's own help describes `tcp://` as "not secured". Any
process on the Windows host that can reach `127.0.0.1:8899` has full control of podman, which
is root inside containers. This is an accepted trade-off for a single-user development
machine, not a pattern to copy onto a shared host.

**Version skew.** The Windows client is 5.2.2 against a 4.9.3 server, because Ubuntu 24.04
ships 4.9.3. Everyday commands work, but this is not a combination upstream tests, and newer
client endpoints can fail against the older server.

## Known limitation: Podman Desktop

Podman Desktop cannot use this setup. It does not read podman's connection list. It connects
to a Windows named pipe, which only `podman machine start` creates:

```
win-sshproxy.exe podman-machine-default <config-dir>
  npipe:////./pipe/podman-machine-default  ssh://root@localhost:59740/run/podman/podman.sock  <identity>
  npipe:////./pipe/docker_engine           ssh://root@localhost:59740/run/podman/podman.sock  <identity>
```

That proxy bridges a named pipe to an `ssh://` endpoint and nothing else. Podman Desktop's
[remote access documentation](https://podman-desktop.io/docs/podman/podman-remote) confirms
only `ssh://` connections are supported, `tcp://` is not, and keys must be ed25519 rather than
RSA.

So with the podman machine stopped, Podman Desktop reports "No Container Engine". This is by
design, not a misconfiguration, and no setting will surface a `tcp://` connection to it.

## Future work: move to SSH

Switching the transport from TCP to SSH would serve the CLI and Podman Desktop from one
connection, and would remove the unauthenticated socket described above. Outline:

1. Install `openssh-server` in the distro. This is a new dependency.
2. Generate an ed25519 key. RSA is rejected by Podman Desktop.
3. Add the public key to `~/.ssh/authorized_keys`.
4. Keep the already-active user socket, `systemctl --user status podman.socket`.
5. Replace the connection:

   ```bash
   podman.exe system connection add --identity <abs-path-to-key> wsl-ubuntu \
       ssh://dave@127.0.0.1:22/run/user/1002/podman/podman.sock
   ```

   Podman Desktop needs an absolute identity path on Windows. A `~` prefix will not resolve.
6. Enable the Podman Desktop setting that surfaces CLI connections, then confirm it lists the
   containers.

Verify the setting exists before dismantling anything. Podman Desktop 1.12.0 dates from July
2024 and may predate it, in which case this also means upgrading Podman Desktop.

## The old machine

`podman-machine-default` is still registered and holds a **126.2 GB non-sparse** `ext4.vhdx`,
despite being unused since June. Removing it reclaims that space:

```bash
podman.exe machine rm podman-machine-default
```

This also deletes the two `podman-machine-default*` connections, which are no longer the
default so nothing depends on them. Keep it only if Podman Desktop is worth the disk.
