# Todo List

A simple file-based todo list manager, shown automatically on shell startup.

## Configuration

```bash
# Todo file location
TODO_FILE="$HOME/.todo"
```

## Commands

```bash
todo [command] [args]
```

| Command | Description |
|---------|-------------|
| `todo ls` | List all items (default when no command given) |
| `todo add <description>` | Add a new item to the end |
| `todo top <description>` | Add a new item at the top |
| `todo promote <N>` | Move item N up one position |
| `todo done <N>` | Mark item N as done |
| `todo undo <N>` | Mark item N as not done |
| `todo rm <N>` | Remove item N |
| `todo clear` | Remove all completed items |
| `todo help` | Show help message |

## Examples

```bash
# Add items
todo add "Review PR for auth service"
todo add "Update deployment docs"
todo top "Urgent: fix broken pipeline"

# Manage items
todo done 1        # Mark first item as done
todo undo 1        # Undo completion
todo promote 3     # Move item 3 up one spot
todo rm 2          # Remove item 2
todo clear         # Remove all completed items
```

## File Format

The todo file (`~/.todo`) uses a simple plain-text format:

```
[ ] Uncompleted item
[x] Completed item
```

## Shell Startup

On interactive shell startup, the todo list is automatically displayed if:
- The todo file exists and is non-empty
- It hasn't been shown in the last 10 minutes

This prevents the list from appearing repeatedly when opening multiple terminals in quick succession.
