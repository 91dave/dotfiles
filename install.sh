#!/bin/bash

## Install all supported bash aliases
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
