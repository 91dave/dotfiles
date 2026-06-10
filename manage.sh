#!/bin/bash

case "$1" in
    get)
        rm dotfiles/lib/*
        cp ~/.dotfiles/*{.sh,.bash} dotfiles/lib
        rm dotfiles/*secret* >& /dev/null
        cp ~/.bash_prefs dotfiles/bash.sh 
        
        cp ~/.dircolors dotfiles/dircolors
        cp ~/.screenrc dotfiles/screenrc
        cp ~/.vimrc dotfiles/vimrc

        #claude_windows="%USERPROFILE\.claude"
        claude_windows="C:\\Code\\_docs\docs-claude-helpers"
        claude_folder=$(wslpath $claude_windows | sed -e 's/\r//g')

        cp $claude_folder/settings.json dotfiles/claude/

        # pi
        cp ~/.pi/agent/settings.json dotfiles/pi/
        cp ~/.pi/agent/extensions/subagent/index.ts dotfiles/pi/extensions/subagent/
        cp ~/.pi/agent/extensions/subagent/agents.ts dotfiles/pi/extensions/subagent/
        cp ~/.pi/agent/extensions/reset-title-on-exit.ts dotfiles/pi/extensions/
        cp ~/.pi/agent/extensions/permission-gate.ts dotfiles/pi/extensions/
        cp ~/.pi/agent/extensions/readonly-mode/index.ts dotfiles/pi/extensions/readonly-mode/
        cp ~/.pi/agent/extensions/readonly-mode/utils.ts dotfiles/pi/extensions/readonly-mode/
        # agents/template.md and agents/skills are the source of truth (symlinked outward
        # by sync-agents.sh), so there is nothing to pull back here.

        # bin
        cp ~/.local/bin/repo-find dotfiles/bin/
        cp ~/.local/bin/web dotfiles/bin/
        ;;
    install)
            cd dotfiles
            mkdir -p ~/.dotfiles
            cp bash.sh ~/.bash_prefs
            cp lib/* ~/.dotfiles

            if grep ~/.bashrc "# Settings imported from https://github.com/91dave/dotfiles"; then
                :
            else
                echo '# Settings imported from https://github.com/91dave/dotfiles' >> ~/.bashrc
                echo 'source ~/.bash_prefs' >> ~/.bashrc
            fi

            cp dircolors ~/.dircolors
            cp screenrc ~/.screenrc
            cp vimrc ~/.vimrc

            # pi
            mkdir -p ~/.pi/agent/extensions/subagent
            cp pi/settings.json ~/.pi/agent/
            cp pi/extensions/subagent/index.ts ~/.pi/agent/extensions/subagent/
            cp pi/extensions/subagent/agents.ts ~/.pi/agent/extensions/subagent/
            cp pi/extensions/reset-title-on-exit.ts ~/.pi/agent/extensions/
            cp pi/extensions/permission-gate.ts ~/.pi/agent/extensions/
            mkdir -p ~/.pi/agent/extensions/readonly-mode
            cp pi/extensions/readonly-mode/index.ts ~/.pi/agent/extensions/readonly-mode/
            cp pi/extensions/readonly-mode/utils.ts ~/.pi/agent/extensions/readonly-mode/

            # agents: build CLAUDE.md + AGENTS.md and symlink personal + work skills
            bash agents/sync-agents.sh

            # bin
            mkdir -p ~/.local/bin
            cp bin/repo-find ~/.local/bin/
            chmod +x ~/.local/bin/repo-find
            cp bin/web ~/.local/bin/
            chmod +x ~/.local/bin/web

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
