#!/bin/bash

alias docker="podman.exe"
alias docker-compose="podman.exe compose"
alias dotnet="dotnet.exe"
alias gh="gh.exe"

function epoch() {
    date -d "@$1"
}

function get_nuget_config() {

    wslpath "$(cmd.exe /k "echo %appdata%\\NuGet\\NuGet.Config & exit" 2>/dev/null)"

}

function push_docker() {

    nuget_conf=$(get_nuget_config)
    DOCKER_BIN=$(wsl2_get_bin docker podman)

    cp $nuget_conf .
    $DOCKER_BIN build . -t temp
    rm $(basename $nuget_conf)

}
