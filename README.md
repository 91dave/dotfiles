# Shell Preferences

Quick and easy way of adding some sensible default settings for the following programs, along with scripts and aliases for working with my preferred technologies.

- GNU Screen (Terminal Multiplexer)
- VIM (VI IMproved text editor)
- BASH (Bourne Again SHell)

## Overview

I'm a software engineer using a Windows machine, developing applications and pipelines. I use BASH on WSL2 as my primary shell, and work daily with the following technologies and providers:

- [.NET](https://dotnet.microsoft.com/)
- [Amazon Web Services](https://aws.amazon.com/)
- [GitHub](https://github.com/) and [GitHub Actions](https://docs.github.com/en/actions)
- [Kubernetes](https://kubernetes.io/)
- [Terraform](https://developer.hashicorp.com/terraform)
- [Telepresence](https://telepresence.io/)

The config files and scripts in `/dotfiles` are my basic BASH and terminal preferences. Each of the scripts in `/dotfiles/lib` provides opinionated functions and aliases for working with the associated technology in Windows.

These scripts make extensive use of natively calling `.exe` files from within WSL2, and assume the technologies are installed and configured in your windows environment. No need for things like `sudo apt install git` in WSL2 when you almost certainly have Git already installed in your windows environment!

## Getting started

These can be installed by running the following in a terminal:

```bash
cd
git clone https://github.com/91dave/bash-prefs.git
chmod +x manage.sh
./manage.sh install
```

Additonally, you might like to use the very helpful [ANSI Code generator](https://github.com/fidian/ansi) to easily colourize output in your scripts.
```bash
curl -OL git.io/ansi
chmod 755 ansi
sudo mv ansi /usr/local/bin/
```

## Usage

- Run `khelp` to get a list of all the Kubernetes aliases and functions
- Run `tphelp` to get a list of all the Telepresence aliases and functions
