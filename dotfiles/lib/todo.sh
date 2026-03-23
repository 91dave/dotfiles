#!/bin/bash

bash_debug "Loading todo.sh"

TODO_FILE="$HOME/.todo"
_TODO_SHOWN_MARKER="$HOME/.cache/todo-shown"

_todo_help() {
    echo "📋 Usage: todo <command> [args]"
    echo ""
    echo "  ➕ add <description>   Add a new item"
    echo "  📌 top <description>   Add a new item at the top"
    echo "  ⬆️  promote <N>        Move item N up one spot"
    echo "  ✅ done <N>            Mark item N as done"
    echo "  ↩️  undo <N>            Mark item N as not done"
    echo "  🗑️  rm <N>              Remove item N"
    echo "  📄 ls                  List all items"
    echo "  🧹 clear               Remove completed items"
    echo "  ❓ help                Show this help"
}

_todo_list() {
    if [[ ! -f "$TODO_FILE" ]] || [[ ! -s "$TODO_FILE" ]]; then
        echo "🎉 No items!"
        return
    fi
    echo ""
    local total done_count
    total=$(wc -l < "$TODO_FILE")
    done_count=$(grep -c '^\[x\]' "$TODO_FILE" || true)
    local i=1
    if (( done_count > 0 )); then
        echo "📋 TODO: (✅ $done_count/$total)"
    else
        echo "📋 TODO:"
    fi
    while IFS= read -r line; do
        echo "  $i. $line"
        ((i++))
    done < "$TODO_FILE"
    echo ""
}

_todo_add() {
    if [[ -z "$1" ]]; then
        echo "Usage: todo add <description>"
        return 1
    fi
    echo "[ ] $*" >> "$TODO_FILE"
    echo "➕ Added: $*"
}

_todo_top() {
    if [[ -z "$1" ]]; then
        echo "Usage: todo top <description>"
        return 1
    fi
    local tmp
    tmp=$(mktemp)
    echo "[ ] $*" > "$tmp"
    [[ -f "$TODO_FILE" ]] && cat "$TODO_FILE" >> "$tmp"
    mv "$tmp" "$TODO_FILE"
    echo "📌 Added to top: $*"
}

_todo_promote() {
    local n="$1"
    local total
    total=$(wc -l < "$TODO_FILE" 2>/dev/null || echo 0)

    if [[ -z "$n" ]] || ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 2 || n > total )); then
        echo "Usage: todo promote <N> (2-$total)"
        return 1
    fi

    local prev=$((n - 1))
    sed -i "${prev}{h;d};${n}G" "$TODO_FILE"
    echo "⬆️  Promoted: $(sed -n "${prev}p" "$TODO_FILE")"
}

_todo_done() {
    local n="$1"
    local total
    total=$(wc -l < "$TODO_FILE" 2>/dev/null || echo 0)

    if [[ -z "$n" ]] || ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > total )); then
        echo "Usage: todo done <N> (1-$total)"
        return 1
    fi

    sed -i "${n}s/^\[ \]/[x]/" "$TODO_FILE"
    echo "✅ Done: $(sed -n "${n}p" "$TODO_FILE")"
}

_todo_undo() {
    local n="$1"
    local total
    total=$(wc -l < "$TODO_FILE" 2>/dev/null || echo 0)

    if [[ -z "$n" ]] || ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > total )); then
        echo "Usage: todo undo <N> (1-$total)"
        return 1
    fi

    sed -i "${n}s/^\[x\]/[ ]/" "$TODO_FILE"
    echo "↩️  Undone: $(sed -n "${n}p" "$TODO_FILE")"
}

_todo_rm() {
    local n="$1"
    local total
    total=$(wc -l < "$TODO_FILE" 2>/dev/null || echo 0)

    if [[ -z "$n" ]] || ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > total )); then
        echo "Usage: todo rm <N> (1-$total)"
        return 1
    fi

    local item
    item=$(sed -n "${n}p" "$TODO_FILE")
    sed -i "${n}d" "$TODO_FILE"
    echo "🗑️  Removed: $item"
}

_todo_clear() {
    if [[ ! -f "$TODO_FILE" ]]; then return; fi
    sed -i '/^\[x\]/d' "$TODO_FILE"
    echo "🧹 Cleared completed items."
}

todo() {
    local cmd="${1:-ls}"
    case "$cmd" in
        add)  shift; _todo_add "$@" ;;
        top)  shift; _todo_top "$@" ;;
        promote) _todo_promote "$2" ;;
        done) _todo_done "$2" ;;
        undo) _todo_undo "$2" ;;
        rm)   _todo_rm "$2" ;;
        ls)   _todo_list ;;
        clear) _todo_clear ;;
        help) _todo_help ;;
        *)    _todo_help ;;
    esac
}

# Show on interactive shell startup if not shown in last 10 minutes
_todo_startup() {
    [[ ! -f "$TODO_FILE" ]] || [[ ! -s "$TODO_FILE" ]] && return

    mkdir -p "$HOME/.cache"

    if [[ -f "$_TODO_SHOWN_MARKER" ]]; then
        local last now
        last=$(cat "$_TODO_SHOWN_MARKER")
        now=$(date +%s)
        (( now - last < 600 )) && return
    fi

    date +%s > "$_TODO_SHOWN_MARKER"
    _todo_list
}

[[ $- == *i* ]] && _todo_startup
