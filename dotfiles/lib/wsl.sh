#!/bin/bash


# Windows echo helper
function wecho() {
    OUTPUT=$(cmd.exe /c echo $@ 2> /dev/null)
    echo "$OUTPUT" | sed -e "s|\r||g"
}

## Windows Home variables
export USERPROFILE_WIN=$(wecho %USERPROFILE% | sed -e "s|\\\|/|g")
export USERPROFILE_WSL=$(wslpath $USERPROFILE_WIN)

bash_debug "Loading wsl.sh"

function wsl_help() {
    echo "🐧 WSL Helpers"
    echo ""
    echo "  wslexe <cmd>    Manage WSL interop (get, check, fix, help)"
    echo "  wecho <args>    Echo with windows variable substitution e.g. %USERPROFILE%"
    echo "  wsltop [-q]     RAM/CPU by distro, podman split, host vs permitted"
    echo "  wsltop -s       Two-line summary (runtimes, RAM, CPU)"
    echo "  wsltop -c       One-line summary, for shell startup"
}

function wslexe() {
    local cmd="${1:-help}"

    case "$cmd" in
        check)
            if [ -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]; then
                [ "$2" = "-v" ] && echo "✅ WSL interop enabled"
                return 0
            else
                echo "❌ WSL interop is not enabled. Run 'wslexe fix' to fix."
                return 1
            fi
            ;;
        fix)
            if [ -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]; then
                echo "✅ WSL interop already enabled"
            else
                echo "🔧 Enabling WSL interop..."
                sudo sh -c 'echo :WSLInterop:M::MZ::/init:PF > /proc/sys/fs/binfmt_misc/register'
                echo "✅ WSL interop enabled"
            fi
            ;;
        get)
            shift
            if [ -z "$1" ]; then
                echo "Usage: wslexe get <binary...>"
                return 1
            fi
            for bin in "$@"; do
                if [ -n "$(which ${bin}.exe 2>/dev/null)" ]; then
                    echo ${bin}.exe
                    return
                fi
                if [ -n "$(which $bin 2>/dev/null)" ]; then
                    echo $bin
                    return
                fi
            done
            ;;
        -h|--help|help|*)
            echo "🔧 wslexe - WSL interop manager"
            echo ""
            echo "Usage: wslexe <command>"
            echo ""
            echo "Commands:"
            echo "  get <bin...>  Find first available binary (.exe or native)"
            echo "  check [-v]    Check if WSL interop is working (-v for verbose)"
            echo "  fix           Enable WSL interop for .exe files"
            echo "  help          Show this help message"
            ;;
    esac
}

# Check WSL interop on interactive shell startup
[[ $- == *i* ]] && wslexe check

# Restore the terminal title in the outer shell. tmux owns the title while
# attached (set-titles); this re-asserts it on every prompt once we're back
# out, so detaching/exiting tmux resets it. Skipped inside tmux so it never
# fights set-titles in the panes. Folder name only, matching the \W prompt.
_set_term_title() {
    [ -n "$TMUX" ] && return
    local dir
    [ "$PWD" = "$HOME" ] && dir="~" || dir="${PWD##*/}"
    printf '\033]0;%s@%s: %s\007' "$USER" "${HOST_NICKNAME:-${HOSTNAME%%.*}}" "$dir"
}
[[ "$PROMPT_COMMAND" == *_set_term_title* ]] || \
    PROMPT_COMMAND="_set_term_title${PROMPT_COMMAND:+; $PROMPT_COMMAND}"






# All WSL2 distros share one utility VM, so /proc/meminfo is identical in each
# and per-distro memory is not a kernel-level fact. It has to be summed from
# inside each distro, hence the interop fan-out below. Newlines do not survive
# `wsl.exe -d X -- sh -c`, so the probe travels base64-encoded.
_wsltop_probe_source() {
cat <<'PROBE'
interval="${1:-1}"
TCK=$(getconf CLK_TCK 2>/dev/null || echo 100)

snapshot() {
    awk '
        { split(FILENAME, f, "/"); pid = f[3]; base = f[4] }
        base == "status" && /^RssAnon:/ { anon[pid] = $2 }
        base == "cgroup" && /libpod-|podman-/ {
            pod[pid] = 1
            if ($0 ~ /libpod-/ && $0 !~ /libpod-conmon-/ &&
                match($0, /libpod-[^\/]*\.scope/)) ids[substr($0, RSTART, RLENGTH)] = 1
        }
        base == "stat" {
            line = $0; sub(/^[^)]*\) /, "", line); split(line, g, " ")
            jif[pid] = g[12] + g[13]
        }
        END {
            for (p in anon) { t += anon[p]; if (p in pod) pa += anon[p] }
            for (p in jif)  { tj += jif[p];  if (p in pod) pj += jif[p] }
            n = 0; for (i in ids) n++
            print t+0, pa+0, tj+0, pj+0, n
        }
    ' /proc/[0-9]*/status /proc/[0-9]*/cgroup /proc/[0-9]*/stat 2>/dev/null </dev/null
}

set -- $(snapshot); a0=$1 pa0=$2 tj0=$3 pj0=$4
[ "$interval" != "0" ] && sleep "$interval"
set -- $(snapshot); a1=$1 pa1=$2 tj1=$3 pj1=$4 c1=$5

echo "anon=$((a1*1024)) podanon=$((pa1*1024)) cpu=$(( (tj1-tj0)*1000000/TCK )) podcpu=$(( (pj1-pj0)*1000000/TCK )) ctrs=$c1"
PROBE
}

_wsltop_rule() {
    local prefix="── ${1} " pad
    pad=$(( 62 - ${#prefix} )); [ "$pad" -lt 0 ] && pad=0
    printf '  \033[2m%s%s\033[0m\n' "$prefix" "$(printf '─%.0s' $(seq 1 $pad))"
}

_wsltop_human() {
    awk -v b="${1:-0}" 'BEGIN{
        if (b>=1073741824) printf "%.1f GB", b/1073741824
        else if (b>=1048576) printf "%.0f MB", b/1048576
        else if (b>=1024)    printf "%.0f KB", b/1024
        else                 printf "%d B", b
    }'
}

_wsltop_bar() {
    awk -v p="${1:-0}" -v w="${2:-20}" 'BEGIN{
        n=int(p*w/100+0.5); if(n>w)n=w; if(n<0)n=0
        for(i=0;i<n;i++) s=s"█"
        for(i=n;i<w;i++) s=s"░"
        print s
    }'
}

_wsltop_to_mb() {
    awk -v v="${1:-}" 'BEGIN{
        if (v=="") { print ""; exit }
        n=v+0
        if (v ~ /[Gg][Bb]?$/) print int(n*1024)
        else if (v ~ /[Mm][Bb]?$/) print int(n)
        else if (v ~ /[Kk][Bb]?$/) print int(n/1024)
        else print int(n/1048576)
    }'
}

_wsltop_distros() {
    wsl.exe -l -v 2>/dev/null | tr -d '\0\r' | awk '
        NR>1 && NF>=3 {
            star = ($1=="*")
            name  = star ? $2 : $1
            state = star ? $3 : $2
            if (name != "") print name "\t" state
        }'
}

_wsltop_host_facts() {
    pwsh.exe -NoProfile -NonInteractive -Command '
        $cs = Get-CimInstance Win32_ComputerSystem
        $os = Get-CimInstance Win32_OperatingSystem
        $vm = Get-Process vmmem,vmmemWSL -ErrorAction SilentlyContinue | Select-Object -First 1
        "{0} {1} {2} {3}" -f [int]($cs.TotalPhysicalMemory/1MB), [int]($os.FreePhysicalMemory/1KB),
                             $cs.NumberOfLogicalProcessors, [int]($vm.WorkingSet64/1MB)
    ' 2>/dev/null | tr -d '\r'
}

_wsltop_meminfo() {
    awk '/^MemTotal/{t=$2} /^MemAvailable/{a=$2} /^Cached:/{c=$2} /^AnonPages/{an=$2}
         /^SwapTotal/{st=$2} /^SwapFree/{sf=$2}
         END{print t*1024, (t-a)*1024, c*1024, (st-sf)*1024, st*1024, an*1024}' /proc/meminfo
}

_wsltop_glyph() {
    local state="$1" ctrs="$2"
    case "$ctrs" in ''|*[!0-9]*) ctrs=0 ;; esac
    if [ "$state" != "Running" ]; then printf '🔴'
    elif [ "$ctrs" -gt 0 ]; then printf '🟢'
    else printf '🟡'; fi
}

_wsltop_label() {
    local state="$1" ctrs="$2"
    case "$ctrs" in ''|*[!0-9]*) ctrs=0 ;; esac
    if [ "$state" != "Running" ]; then printf 'stopped'
    elif [ "$ctrs" -gt 0 ]; then printf '%s running' "$ctrs"
    else printf 'idle'; fi
}

_wsltop_runtime_line() {
    local sep="$1" with_label="$2" self_bullet="$3" other_bullet="$4"
    local self="${WSL_DISTRO_NAME:-$(cat /etc/hostname 2>/dev/null)}"
    local name state ctrs entry selfline="" others=""
    while IFS=$'\t' read -r name state ctrs; do
        [ -n "$name" ] || continue
        entry="$name $(_wsltop_glyph "$state" "$ctrs")"
        [ "$with_label" = "1" ] && entry="$entry $(_wsltop_label "$state" "$ctrs")"
        if [ "$name" = "$self" ]; then
            selfline="${self_bullet:+$self_bullet }$entry"
        else
            others="${others}${others:+$sep}${other_bullet:+$other_bullet }$entry"
        fi
    done
    printf '%s' "${selfline}${others:+$sep}${others}"
}

_wsltop_cache_path() { printf '%s/wsltop-distros.cache' "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"; }

_wsltop_cache_fresh() {
    local cache="$1" max_age="$2" mtime
    [ -f "$cache" ] || return 1
    mtime=$(stat -c %Y "$cache" 2>/dev/null) || return 1
    [ $(( $(date +%s) - mtime )) -lt "$max_age" ]
}

_wsltop_refresh_cache() {
    local cache tmp b64 self name state ctrs
    cache=$(_wsltop_cache_path); tmp="$cache.$$"
    b64=$(_wsltop_probe_source | base64 -w0)
    self="${WSL_DISTRO_NAME:-$(cat /etc/hostname 2>/dev/null)}"
    _wsltop_distros 2>/dev/null | while IFS=$'\t' read -r name state; do
        ctrs=0
        if [ "$state" = "Running" ]; then
            if [ "$name" = "$self" ]; then
                ctrs=$(printf '%s' "$b64" | base64 -d | sh -s 0 2>/dev/null | _wsltop_field ctrs)
            else
                ctrs=$(wsl.exe -d "$name" -- sh -c "echo $b64 | base64 -d | sh -s 0" 2>/dev/null | tr -d '\r' | _wsltop_field ctrs)
            fi
        fi
        printf '%s\t%s\t%s\n' "$name" "$state" "${ctrs:-0}"
    done > "$tmp" 2>/dev/null
    mv -f "$tmp" "$cache" 2>/dev/null
}

_wsltop_field() {
    awk -v k="$1" '{for(i=1;i<=NF;i++) if($i ~ "^" k "=") { sub("^" k "=","",$i); print $i }}'
}

_wsltop_cached_distros() {
    local cache; cache=$(_wsltop_cache_path)
    _wsltop_cache_fresh "$cache" "${WSLTOP_CACHE_SECONDS:-60}" || _wsltop_refresh_cache
    cat "$cache" 2>/dev/null
}

_wsltop_brief() {
    local mode="$1" line pct cpus load1
    local vm_total vm_used vm_cache swap_used swap_total vm_anon
    read -r vm_total vm_used vm_cache swap_used swap_total vm_anon <<< "$(_wsltop_meminfo)"
    cpus=$(nproc); load1=$(awk '{print $1}' /proc/loadavg)
    pct=$(awk -v u="$vm_used" -v t="$vm_total" 'BEGIN{printf "%.0f", t?u*100/t:0}')

    if [ "$mode" = "compact" ]; then
        line=$(_wsltop_cached_distros | _wsltop_runtime_line ' · ' 0 '📦' '')
        printf '\360\237\223\212 %s/%s (%s%%) \302\267 load %s/%s \302\267 %s\n' \
            "$(_wsltop_human $vm_used)" "$(_wsltop_human $vm_total)" "$pct" "$load1" "$cpus" "$line"
    else
        line=$(_wsltop_cached_distros | _wsltop_runtime_line '    ' 1 '📦' '📦')
        printf '\n%s\n' "$line"
        printf '\360\237\223\212 %s / %s (%s%%)  %s  \302\267  load %s over %s vCPU\n\n' \
            "$(_wsltop_human $vm_used)" "$(_wsltop_human $vm_total)" "$pct" \
            "$(_wsltop_bar "$pct" 10)" "$load1" "$cpus"
    fi
}

wsltop() {
    local mode=full quick=0 interval=1
    case "${1:-}" in
        -q|--quick)  mode=quick; quick=1; interval=0 ;;
        -s|--short)   mode=short ;;
        -c|--compact) mode=compact ;;
        -h|--help|help)
            echo "📊 wsltop - WSL resource overview"
            echo ""
            echo "Usage: wsltop [-q | -s | -c]"
            echo ""
            echo "  -q, --quick   This distro only; skips the Windows and interop calls"
            echo "  -s, --short   Two lines: runtimes plus RAM and CPU (cached, startup-safe)"
            echo "  -c, --compact One line, for prompts and shell startup"
            return 0
            ;;
    esac

    if [ "$mode" = "short" ] || [ "$mode" = "compact" ]; then
        _wsltop_brief "$mode"
        return 0
    fi

    find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'wsltop.*' -mmin +60 -exec rm -rf {} + 2>/dev/null

    local work; work=$(mktemp -d -t wsltop.XXXXXXXX)
    trap 'rm -rf "$work"' RETURN

    local b64; b64=$(_wsltop_probe_source | base64 -w0)
    local self="${WSL_DISTRO_NAME:-$(cat /etc/hostname 2>/dev/null)}"

    if [ "$quick" -eq 0 ]; then
        _wsltop_distros > "$work/distros" 2>/dev/null
    else
        printf '%s\tRunning\n' "$self" > "$work/distros"
    fi

    # Interactive bash announces every background job as "[1] 12345" whether or
    # not monitor mode is on, so the parallel probes run in a subshell, where
    # job control is off and the notices are never printed.
    local name state
    (
        if [ "$quick" -eq 0 ]; then
            _wsltop_host_facts > "$work/host" &
        fi
        while IFS=$'\t' read -r name state; do
            [ "$state" = "Running" ] || continue
            if [ "$name" = "$self" ]; then
                printf '%s' "$b64" | base64 -d | sh -s "$interval" > "$work/d.$name" 2>/dev/null &
            else
                wsl.exe -d "$name" -- sh -c "echo $b64 | base64 -d | sh -s $interval" \
                    2>/dev/null | tr -d '\r' > "$work/d.$name" &
            fi
        done < "$work/distros"
        wait
    )

    local ctrs
    while IFS=$'\t' read -r name state; do
        ctrs=0
        [ -f "$work/d.$name" ] && ctrs=$(_wsltop_field ctrs < "$work/d.$name")
        printf '%s\t%s\t%s\n' "$name" "$state" "${ctrs:-0}"
    done < "$work/distros" > "$work/runtime"
    [ "$quick" -eq 0 ] && cp -f "$work/runtime" "$(_wsltop_cache_path)" 2>/dev/null

    local vm_total vm_used vm_cache swap_used swap_total vm_anon
    read -r vm_total vm_used vm_cache swap_used swap_total vm_anon <<< "$(_wsltop_meminfo)"
    local cpus; cpus=$(nproc)
    local load; load=$(awk '{print $1"  "$2"  "$3}' /proc/loadavg)

    printf '\n📊 \033[1mWSL Resources\033[0m%*s%s\n' 34 '' "$(date '+%a %-d %b, %H:%M')"
    printf '  %s\n\n' "$(_wsltop_runtime_line '    ' 1 '📦' '📦' < "$work/runtime")"

    if [ "$quick" -eq 0 ]; then
        local cfg="${USERPROFILE_WSL:-$HOME}/.wslconfig"
        local c_mem c_proc c_swap
        if [ -f "$cfg" ]; then
            c_mem=$(_wsltop_to_mb "$(awk -F= '/^[[:space:]]*memory[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); print $2}' "$cfg")")
            c_swap=$(_wsltop_to_mb "$(awk -F= '/^[[:space:]]*swap[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); print $2}' "$cfg")")
            c_proc=$(awk -F= '/^[[:space:]]*processors[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); print $2}' "$cfg")

            local drift=0
            [ -n "$c_proc" ] && [ "$c_proc" != "$cpus" ] && drift=1
            [ -n "$c_mem" ] && [ "$(awk -v a="$c_mem" -v b="$((vm_total/1048576))" 'BEGIN{d=(a-b)/a; if(d<0)d=-d; if(d>0.12) print 1; else print 0}')" = "1" ] && drift=1
            [ -n "$c_swap" ] && [ "$(awk -v a="$c_swap" -v b="$((swap_total/1048576))" 'BEGIN{d=(a-b)/a; if(d<0)d=-d; if(d>0.12) print 1; else print 0}')" = "1" ] && drift=1

            if [ "$drift" -eq 1 ]; then
                printf '  \033[33m⚠  .wslconfig is not in effect - run `wsl --shutdown`\033[0m\n'
                printf '       %-12s %-10s %-10s %s\n' "permitted" \
                    "${c_mem:+$(_wsltop_human $((c_mem*1048576)))}" "${c_proc:-?} vCPU" "${c_swap:+$(_wsltop_human $((c_swap*1048576))) swap}"
                printf '       %-12s %-10s %-10s %s\n\n' "in effect" \
                    "$(_wsltop_human $vm_total)" "$cpus vCPU" "$(_wsltop_human $swap_total) swap"
            fi
        fi

        local h_total h_free h_cpus h_vm
        read -r h_total h_free h_cpus h_vm < "$work/host" 2>/dev/null
        if [ -n "$h_total" ]; then
            printf '  %-20s %10s total  %10s free  %s logical CPU\n' "HOST" \
                "$(_wsltop_human $((h_total*1048576)))" "$(_wsltop_human $((h_free*1048576)))" "$h_cpus"
            printf '  %-20s %10s working set\n\n' "WSL VM (vmmemWSL)" "$(_wsltop_human $((h_vm*1048576)))"
        fi
    fi

    local used_pct; used_pct=$(awk -v u="$vm_used" -v t="$vm_total" 'BEGIN{printf "%.0f", t?u*100/t:0}')
    _wsltop_rule "inside the VM"
    printf '  %-7s %s / %s  (%s%%)   %s\n' "RAM" "$(_wsltop_human $vm_used)" "$(_wsltop_human $vm_total)" "$used_pct" "$(_wsltop_bar "$used_pct")"
    printf '  %-7s %-24s swap  %s / %s\n' "cache" "$(_wsltop_human $vm_cache)" "$(_wsltop_human $swap_used)" "$(_wsltop_human $swap_total)"
    printf '  %-7s load %s  over %s vCPU\n\n' "CPU" "$load" "$cpus"

    _wsltop_rule "by distro"
    local attributed=0
    while IFS=$'\t' read -r name state; do
        if [ "$state" != "Running" ]; then
            printf '  %-38s %9s %7s   \033[2m%s\033[0m\n' "$name" "-" "-" "$state"
            continue
        fi
        local anon=0 podanon=0 cpu=0 podcpu=0 ctrs=0
        [ -f "$work/d.$name" ] && eval "$(awk '{for(i=1;i<=NF;i++) print $i}' "$work/d.$name" | tr '\n' ';')"
        attributed=$((attributed + anon))
        local pct_all pct_pod
        pct_all=$(awk -v c="$((cpu-podcpu))" -v i="$interval" -v n="$cpus" 'BEGIN{if(i>0) printf "%.1f%%", c*100/(i*1000000*n); else printf "-"}')
        pct_pod=$(awk -v c="$podcpu" -v i="$interval" -v n="$cpus" 'BEGIN{if(i>0) printf "%.1f%%", c*100/(i*1000000*n); else printf "-"}')
        printf '  %-24s %-13s %9s %7s   \033[2m%s\033[0m\n' "$name" "ex-podman" "$(_wsltop_human $((anon-podanon)))" "$pct_all" "$state"
        printf '  %-24s %-13s %9s %7s   \033[2m%s containers\033[0m\n' "" "podman" "$(_wsltop_human $podanon)" "$pct_pod" "$ctrs"
    done < "$work/distros"
    printf '\n  \033[2mattributed %s of %s anonymous; %s cache and kernel unattributed\033[0m\n\n' \
        "$(_wsltop_human $attributed)" "$(_wsltop_human $vm_anon)" "$(_wsltop_human $vm_cache)"

    _wsltop_rule "heaviest in $self"
    ps -eo rss,comm --sort=-rss 2>/dev/null | awk 'NR>1 && NR<=6 {printf "  %8.0f MB  %s\n", $1/1024, $2}'
    echo
}

[[ $- == *i* ]] && wsltop --short
