#!/bin/bash

case "$1" in
    get)
        cp ~/.dotfiles/*.sh dotfiles/lib
        cp ~/.bash_prefs dotfiles/bash.sh 
        
        cp ~/.dircolors dotfiles/dircolors
        cp ~/.screenrc dotfiles/screenrc
        cp ~/.vimrc dotfiles/vimrc
        ;;
    install)
            cd dotfiles
            mkdir -p ~/.dotfiles
            cp bash.sh ~/.bash_prefs
            cp lib/* ~/.dotfiles

            echo '# Settings imported from https://github.com/91dave/dotfiles' >> ~/.bashrc
            echo 'source ~/.bash_prefs' >> ~/.bashrc
            echo 'for f in ~/.dotfiles/*; do source $f; done' >> ~/.bashrc
            echo '' >> ~/.bashrc

            cp dircolors ../.dircolors
            cp screenrc ../.screenrc
            cp vimrc ../.vimrc
            cd
            bash ; exit

        ;;
    *)
        echo "-- Management helper scripts --"
        echo "This file isn't strictly part of my dotfiles, it simply helps me manage them"
        echo "and keep this repo in sync with the actual files I'm using day-to-day"
        echo ""
        echo "Commands"
        echo "  install   apply the dotfiles (WSL scripts only - not claude settings)"
        echo "  get       the inverse of install: update this repo with latest versions of in-use dotfiles"
        ;;
esac