#!/bin/bash
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DF="$REPO_DIR/dotfiles"

REMOVE_BAK=false
for arg in "$@"; do
    case "$arg" in
        --remove-bak) REMOVE_BAK=true ;;
        *)
            echo "Unknown option: $arg" >&2
            echo "Usage: ./install.sh [--remove-bak]" >&2
            exit 2
            ;;
    esac
done

LINKED=()

link() {
    local src="$DF/$1"
    local dest="$2"
    if [ ! -e "$src" ]; then
        echo "  skip (not in repo): $1"
        return
    fi
    mkdir -p "$(dirname "$dest")"
    if [ -L "$dest" ]; then
        rm -f "$dest"
    elif [ -e "$dest" ]; then
        mv "$dest" "$dest.bak"
        echo "  backed up $dest -> $dest.bak"
    fi
    ln -s "$src" "$dest"
    LINKED+=("$dest")
    echo "  linked $dest"
}

echo "Shell config..."
link bash.sh   "$HOME/.bash_prefs"
link dircolors "$HOME/.dircolors"
link screenrc  "$HOME/.screenrc"
link vimrc     "$HOME/.vimrc"
link tmux.conf "$HOME/.tmux.conf"

echo "Lib scripts..."
link lib "$HOME/.dotfiles"

if ! grep -qF "# Settings imported from https://github.com/91dave/dotfiles" "$HOME/.bashrc" 2>/dev/null; then
    echo '# Settings imported from https://github.com/91dave/dotfiles' >> "$HOME/.bashrc"
    echo 'source ~/.bash_prefs' >> "$HOME/.bashrc"
fi

echo "atuin config..."
link atuin/config.toml "$HOME/.config/atuin/config.toml"

echo "Git config..."
link git/config         "$HOME/.gitconfig"
link git/config-windows "$HOME/.gitconfig-windows"
link git/ignore         "$HOME/.config/git/ignore"

echo "pi agent config..."
while IFS= read -r -d '' f; do
    rel="${f#"$DF"/pi/}"
    case "$rel" in auth.json) continue ;; esac
    link "pi/$rel" "$HOME/.pi/agent/$rel"
done < <(find "$DF/pi" -type f -print0)

echo "claude settings (leaves include/rules/skills/CLAUDE.md untouched)..."
link claude/settings.json "$HOME/.claude/settings.json"

echo "Building agent instruction files + skills..."
bash "$DF/agents/sync-agents.sh"

echo "systemd user units..."
link systemd/podman-tcp.socket  "$HOME/.config/systemd/user/podman-tcp.socket"
link systemd/podman-tcp.service "$HOME/.config/systemd/user/podman-tcp.service"
link systemd/podman-tcp.socket  "$HOME/.config/systemd/user/sockets.target.wants/podman-tcp.socket"

echo "bin scripts..."
link bin/repos           "$HOME/.local/bin/repos"
link bin/web             "$HOME/.local/bin/web"
link bin/claude-sessions "$HOME/.local/bin/claude-sessions"
link bin/pi-sessions     "$HOME/.local/bin/pi-sessions"
link bin/tmux-sessions   "$HOME/.local/bin/tmux-sessions"

if $REMOVE_BAK; then
    echo "Removing backups..."
    removed=0
    for dest in "${LINKED[@]}"; do
        if [ -e "$dest.bak" ]; then
            rm -rf "$dest.bak"
            echo "  removed $dest.bak"
            removed=$((removed + 1))
        fi
    done
    echo "  $removed backup(s) removed"
fi

echo "Done. Run 'exec bash' (or open a new shell) to pick up the changes."
