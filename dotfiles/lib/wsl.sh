#!/bin/bash

function wsl_help() {
    echo "🐧 WSL Helpers"
    echo ""
    echo "  wsl_get_bin [bins...]     Find first available binary (.exe or native)"
    echo "  wsl_fix_exe               Enable WSL interop for .exe files"
}

function wsl_get_bin() {

    for bin in $@
    do
        if [ -n "$(which ${bin}.exe)" ]
        then
            echo ${bin}.exe
            return
        fi

        if [ -n "$(which $bin)" ]
        then
            echo $bin
            return
        fi
    done

}

function wsl_fix_exe() {

    if [ -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]
    then
        echo "✅ WSL interop already enabled"
    else
        echo "🔧 Enabling WSL interop..."
        sudo sh -c 'echo :WSLInterop:M::MZ::/init:PF > /proc/sys/fs/binfmt_misc/register'
        echo "✅ WSL interop enabled"
    fi

}

