#!/bin/bash

function dev_help() {
    echo "🛠️  Dev Helpers"
    echo ""
    echo "  epoch [timestamp]         Convert Unix timestamp to date"
    echo "  get_nuget_config          Get path to Windows NuGet.Config"
    echo "  push_docker               Build Docker image with NuGet config"
    echo ""
    echo "💡 Aliases:"
    echo "  docker, docker-compose → podman.exe"
    echo "  dotnet → dotnet.exe"
    echo "  gh → gh.exe"
}

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

    echo "🐳 Building Docker image..."
    cp $nuget_conf .
    $DOCKER_BIN build . -t temp
    rm $(basename $nuget_conf)
    echo "✅ Build complete"

}
