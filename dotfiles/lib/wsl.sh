#!/bin/bash

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
        echo "WSL interop for running .exe files appears enabled"
    else
        sudo sh -c 'echo :WSLInterop:M::MZ::/init:PF > /proc/sys/fs/binfmt_misc/register'
    fi

}

