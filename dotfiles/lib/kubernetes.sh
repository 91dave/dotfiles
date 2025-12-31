#!/bin/bash

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
    echo "use-[cluster]             : Switch context to [cluster]"
    echo "kgns                      : List namespaces on current cluster"
    echo "kgs [namespace]           : List services for [namespace]"
    echo "kgp [namespace] [app?]    : List pods for [namespace]"
    echo "kgr [namespace] [svc?]    : Get status of an ongoing rollout against [svc]"
    echo "kgo [namespace]           : List outstanding pods for [namespace]"
    echo "kdp [namespace] [pod]     : Describe pod [pod] within [namespace]"
    echo "kkp [namespace] [pod]     : Kill pod [pod] within [namespace]"
    echo "kgl [namespace] [pod]     : Get logs for [pod] within [namespace]"
    echo "kgx [ns] [search|pod] [cmd]   : Execute [command] against [pod] (or first pod matching [search] within namespace [ns]"
    echo "kgn                       : Get nodes for cluster"
    echo "kppn                      : Count of pods per node in the cluster"
    echo "kdn [node]                : Describe [node]"
    echo "kaudit                    : Audit running nodes and pods in selected clusters"
    echo "kaudit_nodes [cluster]    : Audit running nodes in [cluster]"
    echo "kaudit_pods [cluster]     : Audit running pods in [cluster]"
    echo "hls [namespace]           : List helm services in [namespace]"
    echo "hla                       : List all broken or pending helm services across all namespaces"
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

    echo kubectl exec -tin $env $pod -- $cmd
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

        echo "$pods Pods on $nodes Nodes"
        kubectl get pods --all-namespaces -o wide --sort-by=.spec.nodeName | tail -n+2 | awk '{print $8}' | uniq -c | sort -n
    else
        env=$1
        pods=$(kubectl get pods -n $env | tail -n+2 | wc -l)
        nodes=$(kubectl get pods -n $env -o wide --sort-by=.spec.nodeName | tail -n+2 | awk '{print $7}' | uniq | wc -l)

        echo "$pods Pods on $nodes Nodes"
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
    echo "$cluster nodes: ($count total)"
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
    echo "$cluster pods: ($count total)"
    kubectl get pods --all-namespaces | grep -E "^($filter)" | awk '{print $1}' | sort | uniq -c
    echo "";

    kubectl config use-context $original >& /dev/null
}

function kaudit {
    for cluster in $PREF_k8s_audit_clusters
    do
        kaudit_nodes $cluster
        kaudit_pods $cluster
    done
}
