#!/bin/bash

bash_debug "Loading containers.sh"

pod() {
    local docker_bin=$(wslexe get podman docker)
    cid=$($docker_bin ps --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}" | fzf --header-lines=1 --preview 'podman.exe logs -f {1}' --layout=reverse | awk '{print $1}')
    
    case "$1" in

        logs)       echo "" ;;
        stop)       $docker_bin stop "$cid" ;;
        attach)     $docker_bin attach "$cid" ;;
        rm)         $docker_bin rm "$cid" ;;
        sh)         $docker_bin exec -it "$cid" sh;;

    esac
}


