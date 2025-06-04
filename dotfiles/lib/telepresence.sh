#!/bin/bash

tphelp() {
    echo "Connect to namespace: tpc [namespace]"
    echo "Connection status: tps"
    echo "Intercept: tpi [component-name] [port-number]"
    echo "    - Run using tpii to auto-quit telepresence when you hit enter"
    echo "Leave telepresence: tpq"
}

tpc() {
    telepresence.exe connect -n $1 --manager-namespace $1
}

tpi() {

    component=$1
    port=$2

    if [ -n "$3" ]
    then
        env=$1
        component=$2
        port=$3

        tpc $env
    fi

    telepresence.exe intercept $component --port $port:http --mount false && echo $component > ~/.tpi.tmp
}

tpii() {
    tpi $1 $2 $3
    echo "Telepresence connection established... hit Enter to close"
    read
    tpq
}

tpq() {
    if [ -f ~/.tpi.tmp ]
    then
        component=$(cat ~/.tpi.tmp)
        echo "Closing intercept on $component..."
        telepresence.exe leave $component
        rm ~/.tpi.tmp
    fi

    echo "Closing telepresence connection..."
    telepresence.exe quit
}

alias tps="telepresence.exe status"
alias tpl="telepresence.exe list"
