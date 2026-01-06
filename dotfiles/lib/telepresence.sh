#!/bin/bash

tphelp() {
    echo "🔌 Telepresence Helpers"
    echo ""
    echo "  tpc <namespace>           🔗 Connect to namespace"
    echo "  tps                       📊 Connection status"
    echo "  tpl                       📋 List active intercepts"
    echo "  tpi <component> <port>    🎯 Intercept traffic"
    echo "  tpii <component> <port>   🎯 Intercept (auto-quit on Enter)"
    echo "  tpq                       👋 Quit telepresence"
}

tpc() {
    echo "🔗 Connecting to namespace $1..."
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

    echo "🎯 Intercepting $component on port $port..."
    telepresence.exe intercept $component --port $port:http --mount false && echo $component > ~/.tpi.tmp
    echo "✅ Intercept active"
}

tpii() {
    tpi $1 $2 $3
    echo ""
    echo "🎯 Telepresence active — press Enter to disconnect"
    read
    tpq
}

tpq() {
    if [ -f ~/.tpi.tmp ]
    then
        component=$(cat ~/.tpi.tmp)
        echo "🔌 Closing intercept on $component..."
        telepresence.exe leave $component
        rm ~/.tpi.tmp
    fi

    echo "👋 Disconnecting from telepresence..."
    telepresence.exe quit
}

alias tps="telepresence.exe status"
alias tpl="telepresence.exe list"
