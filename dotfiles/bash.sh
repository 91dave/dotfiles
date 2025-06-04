#!/bin/bash

[ -z "$HOST_NICKNAME" ] && HOST_NICKNAME=$HOSTNAME

export PS1="\[\033[01;32m\]\u\[\033[01;00m\]@\[\033[01;33m\]$HOST_NICKNAME\[\033[00m\]:\[\033[01;34m\]\W\[\033[00m\]\$ "

# include directory colors
[ -e "$HOME/.dircolors" ] && DIR_COLORS="$HOME/.dircolors"
[ -e "$DIR_COLORS" ] || DIR_COLORS=""
eval "`dircolors -b $DIR_COLORS`"

screen -r >& /dev/null && \
    echo "You were automatically logged into an open screen session." && \
    echo -e "You have now been logged out of \033[01;33m$(hostname)\033[00m entirely" && \
    exit

set bell-style none

alias time='$(which time) --format="Time: %E CPU: %P RAM: %M kB"'
