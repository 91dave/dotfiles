#!/bin/bash

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SELF_DIR/command-guard.sh"

PASS=0
FAIL=0

guard() {  # guard <command> [cwd]
    jq -n --arg c "$1" --arg d "${2:-/mnt/c/Code/repo}" '{tool_input: {command: $c}, cwd: $d}' | bash "$SUT" 2>&1
    echo "exit=$?"
}

expect() {  # expect <name> <needle> <command> [cwd]
    local actual
    actual=$(guard "$3" "${4:-}")
    if [[ "$actual" == *"$2"* ]]; then
        PASS=$((PASS + 1))
        printf '  ok   %s\n' "$1"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL %s\n       %q not found in: %q\n' "$1" "$2" "$actual"
    fi
}

allowed() { expect "$1" "exit=0" "$2" "${3:-}"; }
blocked() { expect "$1" "$2" "$3" "${4:-}"; }

GREP="Use 'rg'"
FIND="Use 'fdfind'"
REPLACE="In rg, '-r' means --replace"
WRITE="Change files with the Write"

echo "tool choice"
blocked "grep in a pipe" "$GREP" "cat x | grep foo"
blocked "find at start" "$FIND" "find . -name '*.cs'"
blocked "docker" "podman" "docker ps"
blocked "dotnet without exe" "dotnet.exe" "dotnet build"
blocked "pwsh without exe" "pwsh.exe" "pwsh -File x.ps1"
allowed "grep inside quotes" "rg 'grep foo' notes.md"

echo "rg -r flag clusters"
blocked "rg -rn" "$REPLACE" "rg -rn foo src"
blocked "rg -nr" "$REPLACE" "rg -nr foo"
blocked "rg -rni" "$REPLACE" "rg -rni foo"
blocked "rg -rn via xargs" "$REPLACE" "fdfind -e cs | xargs rg -rn Foo"
blocked "rg -rn after other flags" "$REPLACE" "rg -i -rn foo"
allowed "sort -rn" "rg -o foo x | sort | uniq -c | sort -rn | head"
allowed "sort -nr" "jq -r .a x.json | sort -nr"
allowed "rg -r replacement" "rg -o 'v(\\d+)' -r '\$1' x"
allowed "rg -n then sort -rn" "rg -n foo . | sort -rn"

echo "git"
blocked "commit and push chained" "separate commands" "git commit -m x && git push"
expect "push asks" '"permissionDecision": "ask"' "git push origin main"
expect "pr merge asks" '"permissionDecision": "ask"' "gh pr merge 12"
allowed "stash push is local" "git stash push -m wip"

echo "jest"
blocked "unbounded jest" "maxWorkers" "npx jest"
allowed "bounded jest" "npx jest --maxWorkers=6 --workerIdleMemoryLimit=1GB"

echo "shell writes to repo files"
blocked "redirect into repo" "$WRITE" "echo x > src/file.cs"
blocked "append to gitignore" "$WRITE" "printf '*.todo.md\n' >> .gitignore"
blocked "tee into repo" "$WRITE" "echo x | tee notes.md"
blocked "sed -i" "$WRITE" "sed -i 's/a/b/' src/file.cs"
blocked "sed -i.bak" "$WRITE" "sed -i.bak 's/a/b/' src/file.cs"
blocked "perl -pi" "$WRITE" "perl -pi -e 's/a/b/' x.cs"
blocked "python heredoc edits repo file" "$WRITE" $'python3 - <<\'EOF\'\np=\'tmux-pick\'\ns=open(p).read()\nopen(p,\'w\').write(s)\nEOF'
blocked "python literal repo path" "$WRITE" $'python3 - <<\'EOF\'\nopen("src/x.py","w").write("")\nEOF'
blocked "python Path.open w" "$WRITE" $'python3 - <<\'EOF\'\nPath("/tmp/x").open("w")\nEOF'
blocked "python write_text" "$WRITE" $'python3 - <<\'EOF\'\nPath("x").write_text("")\nEOF'
blocked "variable pointing outside tmp" "$WRITE" "F=/mnt/c/Code/x.json; echo x > \$F"
blocked "tmp variable reassigned outside tmp" "$WRITE" "F=/tmp/a; F=/mnt/c/b; echo x > \$F"
blocked "unknown variable" "$WRITE" "echo x > \$OUT"
blocked "relative write after cd to repo" "$WRITE" "cd /mnt/c/Code/repo && echo x > out.json"
blocked "relative write after cd tmp then repo" "$WRITE" "cd /tmp/x; cd /mnt/c/Code/repo; echo x > out.json"
blocked "parent escape from tmp dir" "$WRITE" "cd /tmp/x && echo x > ../../home/dave/y"
blocked "relative write in tmp cwd escaping" "$WRITE" "echo x > ../../etc/y" "/tmp/x"

echo "shell writes to disposable targets"
allowed "redirect to /tmp" "echo x > /tmp/a.json"
allowed "redirect to /dev/null" "ls x 2>/dev/null"
allowed "stderr to stdout" "make 2>&1 | tail"
allowed "tee to /tmp" "make 2>&1 | tee /tmp/build.log | tail -n40"
allowed "redirect to tmp variable" $'F=/tmp/metrics.json; python3 - > $F <<\'EOF\'\nprint(1)\nEOF'
allowed "redirect to braced tmp variable" "D=/tmp/x; mkdir -p \$D; echo x > \${D}/a.json"
allowed "redirect to quoted tmp assignment" $'S="/tmp/claude-1002/s/scratchpad"; cat > $S/q.sh <<\'EOF\'\necho\nEOF'
allowed "exported tmp variable" "export F=/tmp/a.json; echo x > \$F"
allowed "tee to tmp variable" "S=/tmp/s; echo x | tee \$S/window.txt"
allowed "append to nested tmp variable" "S=/tmp/s; for i in a b; do echo \$i >> \$S/pi/rids.txt; done"
allowed "mktemp variable" "export AGENT_STATE_DIR=\$(mktemp -d); printf 'q\n' > \$AGENT_STATE_DIR/\$\$"
allowed "relative write after cd /tmp" $'mkdir -p /tmp/ncdcr && cd /tmp/ncdcr && cat > q.sh <<\'EOF\'\necho\nEOF'
allowed "relative write after cd tmp variable" "S=/tmp/s; mkdir -p \$S; cd \$S; jq . a.json > b.json"
allowed "relative write when cwd is tmp" "echo x > rds-q.json" "/tmp/claude-1002/s/scratchpad"
allowed "python writes tmp literals" $'cat > /tmp/pi/merge.py <<\'EOF\'\njson.dump(rows, open("/tmp/pi/merged.json","w"))\nwith open("/tmp/pi/merged.txt","w") as out:\n    out.writelines(x)\nEOF\npython3 /tmp/pi/merge.py'
allowed "python writes f-string tmp path" $'python3 - <<\'EOF\'\nopen(f"/tmp/pi/{i}.json", "w")\nEOF'
allowed "python writes relative in tmp dir" $'mkdir -p /tmp/lr && cd /tmp/lr && python3 - <<\'EOF\'\njson.dump(b,open("filters.json","w"))\nEOF'
allowed "python reads only" $'python3 - <<\'EOF\'\nd = json.load(open("src/x.json"))\nEOF'

echo "reads that look like writes"
allowed "sed -n on a -ci file" "sed -n 1,200p .github/workflows/iac-ci.yml | rg -n 'run:'"
allowed "sed print" "sed -n 20,29p content/_index.md"
allowed "comparison in test" "[ \$a -gt 1 ] && echo ok"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
