#!/bin/bash
# Interactive glue for repos. Logic lives in repos-core.bash (also used by bin/repos).

# cd needs the current shell to change directory, so it stays here rather than in the bin/repos subshell
repos() {
    if [[ "$1" == "cd" ]]; then
        _repos_cd "$2"
    else
        _repos_dispatch "$@"
    fi
}

alias repo='repos'

# fzf completion for repos command
_fzf_complete_repos() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local cmd="${COMP_WORDS[1]:-}"

    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "ls find status fetch main clear reset code edit ide cmd cd resolve claude cc view work cache help" -- "$cur") )
        return
    fi

    case "$cmd" in
        ls)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--readonly --modified --active" -- "$cur") )
                return
            fi
            ;&
        find|code|cmd|cd|resolve|claude|cc|edit|ide|vs|view|work|reset)
            local -a matches
            mapfile -t matches < <(_repos_picker_list | cut -f1 | grep -- "$cur")

            if [[ ${#matches[@]} -eq 1 ]]; then
                COMPREPLY=( "${matches[0]}" )
                return
            fi

            local selected
            selected=$(_repos_picker_list | fzf --height=70% --layout=reverse --query="$cur" \
                --delimiter='\t' --with-nth=1 --preview "$EZA_PREVIEW {2}" | cut -f1)
            if [[ -n "$selected" ]]; then
                COMPREPLY=( "$selected" )
            fi
            printf '\e[5n'
            ;;
    esac
}
complete -F _fzf_complete_repos -o default -o bashdefault repos repo
