#!/bin/bash

alias docker="podman.exe"
alias docker-compose="podman.exe compose"
alias dotnet="dotnet.exe"
alias gh="gh.exe"

function fixtime {
    sudo hwclock -s
    sudo ntpdate time.windows.com
}
