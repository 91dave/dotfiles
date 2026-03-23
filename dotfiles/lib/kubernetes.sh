#!/bin/bash

bash_debug "Loading kubernetes.sh"

## CONFIGURATION
# Kubernetes cluster nicknames
PREF_k8s_clusters="dev test prod"
PREF_k8s_audit_clusters="test dev"
PREF_k8s_audit_namespaces="testing qa uat dev stage"

# Map cluster nicknames to kubectl contexts
PREF_k8s_dev=development
PREF_k8s_test=testing
PREF_k8s_prod=production

## ALIASES AND FUNCTIONS
# Create aliases to quickly switch between clusters
for cluster in $PREF_k8s_clusters
do
    var="PREF_k8s_$cluster"
    context="${!var}"

    alias use-$cluster="kubectl config use-context $context"
done

# Help
function khelp {
    echo "☸️  Kubernetes Helpers"
    echo ""
    echo "🔄 Context switching:"
    echo "  use-<cluster>             Switch to <cluster> context"
    echo ""
    echo "📋 Listing:"
    echo "  kgns                      List namespaces"
    echo "  kgs <ns>                  List services"
    echo "  kgp <ns> [app]            List pods (optionally filter by app)"
    echo "  kgn                       List nodes"
    echo "  kgo <ns>                  List non-ready/terminating pods"
    echo "  kg <ns> <resource>        Get any resource"
    echo ""
    echo "🔍 Details:"
    echo "  kdp <ns> <pod>            Describe pod"
    echo "  kdn <node>                Describe node"
    echo "  kd <ns> <resource>        Describe any resource"
    echo "  kgl <ns> <pod>            Get pod logs"
    echo "  kgr <ns> <svc>            Get rollout status"
    echo ""
    echo "⚡ Actions:"
    echo "  kgx <ns> <pod> <cmd>      Execute command in pod"
    echo "  kgxx <ns> <pod>           Exec interactive shell"
    echo "  kkp <ns> <pod>            Kill pod"
    echo "  kcp <ns> <app> <src> <dest>  Copy file to pods"
    echo ""
    echo "🎯 Interactive:"
    echo "  k8s [ns] [cmd]            Interactive pod manager (k8s help)"
    echo ""
    echo "📊 Stats:"
    echo "  kppn [ns]                 Pods per node count"
    echo "  kaudit                    Audit nodes and pods across clusters"
    echo ""
    echo "🎡 Helm:"
    echo "  hls <ns>                  List helm releases"
    echo "  hla                       List broken/pending releases"
}
alias kkp='kubectl delete pod -n'
alias kgs='kubectl get services -n'
alias kgns='kubectl get namespaces'
alias kdp='kubectl describe pod -n'
alias kgn='kubectl get nodes'
alias kdn='kubectl describe node'
alias kgl='kubectl logs -n'
alias kgxx='kubectl exec -tin'
alias kg='kubectl get -n'
alias kd='kubectl describe -n'
alias hls='helm list -an'

function hla {
  helm ls -aA | awk '$8 != "deployed" || NR==1'
}

function kgp {
    env=$1
    app=$2

    if [ -z "$app" ]
    then
        kubectl get pods -n $env
    else
        kubectl get pods -n $env | grep $app
    fi
}

function kgr {
    env=$1
    app=$2

    kubectl rollout status deployment/$app -n $env
}

function kgxh {
    env=$1
    app=$2
    cmd=${@:3}

    pod=$(kubectl get pods -n $env | grep $app | grep -v '0/' | grep -v Terminating | head -n1 | awk '{ print $1 }')

    echo "🔗 Connecting to $pod..."
    echo "   kubectl exec -tin $env $pod -- $cmd"
    kubectl exec -tin $env $pod -- $cmd

}

function kgx {
    env=$1
    app=$2
    cmd=${@:3}

    pod=$(kubectl get pods -n $env | grep $app | grep -v '0/' | grep -v Terminating | head -n1 | awk '{ print $1 }')

    kubectl exec -tin $env $pod -- $cmd

}


function kcp {
    env=$1
    app=$2
    src=$3
    dest=$4

    kgp $env $app | while read line
    do
        pod=$(echo $line | awk '{print $1}')

        kubectl cp -n $env $src $pod:$dest
    done
}


function kppn {

    if [ -z "$1" ]
    then
        pods=$(kubectl get pods --all-namespaces | tail -n+2 | wc -l)
        nodes=$(kubectl get nodes | tail -n+2 | wc -l)

        echo "📊 $pods pods across $nodes nodes (all namespaces)"
        kubectl get pods --all-namespaces -o wide --sort-by=.spec.nodeName | tail -n+2 | awk '{print $8}' | uniq -c | sort -n
    else
        env=$1
        pods=$(kubectl get pods -n $env | tail -n+2 | wc -l)
        nodes=$(kubectl get pods -n $env -o wide --sort-by=.spec.nodeName | tail -n+2 | awk '{print $7}' | uniq | wc -l)

        echo "📊 $pods pods across $nodes nodes ($env)"
        kubectl get pods -n $env -o wide --sort-by=.spec.nodeName | tail -n+2 | awk '{print $7}' | uniq -c | sort -n
    fi

}

function kgo {

    kubectl get pods -n $1 | grep '0/\|Terminating'

}

function kaudit_nodes {
    cluster=$1

    var="PREF_k8s_$cluster"
    context="${!var}"
    original=$(kubectl config get-contexts | grep '*' | awk '{print $2}')
    kubectl config use-context $context >& /dev/null

    count=$(kubectl get nodes | grep -v ^NAME | wc -l)
    echo "🖥️  $cluster nodes ($count total)"
    kubectl get nodes | awk '{print $3}' | grep -v ^ROLES | sort | uniq -c
    echo "";

    kubectl config use-context $original >& /dev/null
}

function kaudit_pods {
    cluster=$1

    var="PREF_k8s_$cluster"
    context="${!var}"
    original=$(kubectl config get-contexts | grep '*' | awk '{print $2}')
    kubectl config use-context $context >& /dev/null

    filter=$(echo $PREF_k8s_audit_namespaces | tr ' ' '|')

    count=$(kubectl get pods --all-namespaces | grep -E "^($filter)" | grep -v ^NAME | wc -l)
    echo "🫛 $cluster pods ($count total)"
    kubectl get pods --all-namespaces | grep -E "^($filter)" | awk '{print $1}' | sort | uniq -c
    echo "";

    kubectl config use-context $original >& /dev/null
}

function kaudit {
    echo "📊 Kubernetes Audit"
    echo ""
    for cluster in $PREF_k8s_audit_clusters
    do
        kaudit_nodes $cluster
        kaudit_pods $cluster
    done
}

function k8s {
    # Help
    if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
        echo "☸️  Interactive Kubernetes Pod Manager"
        echo ""
        echo "Usage: k8s <ns> [cmd]"
        echo ""
        echo "📋 Modes:"
        echo "  k8s                       Select namespace, then pod, then describe"
        echo "  k8s <ns>                  Select pod in namespace, then describe"
        echo "  k8s <ns> [cmd]            Select pod and run command"
        echo ""
        echo "⚡ Commands (defaults to describe):"
        echo "  describe                  Describe pod"
        echo "  logs                      View pod logs"
        echo "  sh                        Shell into pod"
        echo "  rm                        Delete pod"
        echo ""
        echo "⌨️  Keybindings:"
        echo "  Ctrl + /                  Toggle pod details preview"
        return
    fi

    ns=$1
    cmd=$2

    # If no namespace provided, select one via fzf
    if [ -z "$ns" ]; then
        # Original (fast, no pod counts):
        # ns=$((echo "HELP: Use Ctrl + / to toggle pod list" ; kubectl get namespaces) | fzf --header-lines=2 --layout=reverse \
        #     --preview-window=hidden \
        #     --bind 'ctrl-/:toggle-preview' \
        #     --preview "kubectl get pods -n {1}" \
        #     | awk '{print $1}')

        # With pod counts (adds ~1-2s latency):
        ns=$((echo "HELP: Use Ctrl + / to toggle pod list" ; printf "%-40s %s\n" "NAME" "PODS"; join -a1 -e0 -o '1.1 2.2' \
            <(kubectl get ns --no-headers | awk '{print $1}' | sort) \
            <(kubectl get pods -A --no-headers | awk '{count[$1]++} END {for(ns in count) print ns, count[ns]}' | sort) \
            | awk '{printf "%-40s %s\n", $1, $2}') \
            | fzf --header-lines=2 --layout=reverse \
            --preview-window=hidden \
            --bind 'ctrl-/:toggle-preview' \
            --preview "kubectl get pods -n {1}" \
            | awk '{print $1}')

        [ -z "$ns" ] && return
        cmd="describe"
    fi

    # Select pod via fzf with preview (Ctrl-/ to toggle)
    pod=$((echo "HELP: Use Ctrl + / to toggle pod details" ; kubectl get pods -n "$ns") | fzf --header-lines=2 --layout=reverse \
        --preview-window=hidden \
        --bind 'ctrl-/:toggle-preview' \
        --preview "kubectl get pod {1} -n $ns -o wide && echo '' && \
                   kubectl get pod {1} -n $ns -o jsonpath='{.spec.containers[*].image}' && echo -e '\n' && \
                   echo '--- EVENTS ---' && \
                   kubectl describe pod {1} -n $ns | grep -A 20 '^Events:' && \
                   echo -e '\n--- LOGS (last 50) ---' && \
                   kubectl logs --tail=50 {1} -n $ns 2>/dev/null" \
        | awk '{print $1}')

    # Exit if no selection
    [ -z "$pod" ] && return

    case "$cmd" in
        logs)       kubectl logs -n "$ns" "$pod" ;;
        sh)         kubectl exec -it -n "$ns" "$pod" -- sh ;;
        rm)         kubectl delete pod -n "$ns" "$pod" ;;
        *)          kubectl describe pod -n "$ns" "$pod" ;;
    esac
}

