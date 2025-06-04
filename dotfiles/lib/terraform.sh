#!/bin/bash

# Terraform support
function tffmt() {
  terraform.exe fmt -recursive
}
function tfvalid() {
  terraform.exe validate
}
function tfplan() {
  [ -z "$1" ] && echo "usage: tfplan [vars-file] plan-name" && return 0
  [ -n "$2" ] && WORKSPACE=$1 && PLAN=$2
  [ -z "$2" ] && WORKSPACE=playground && PLAN=$1

  mkdir -p ./plans
  echo "Generating plan ($PLAN.tfplan) using var file envs/$WORKSPACE.tfvars"
  terraform.exe plan -out plans/$PLAN.tfplan -var-file=envs/$WORKSPACE.tfvars
}
function tfdestroy() {
  [ -z "$1" ] && echo "usage: tfplan [vars-file] plan-name" && return 0
  [ -n "$2" ] && WORKSPACE=$1 && PLAN=$2
  [ -z "$2" ] && WORKSPACE=playground && PLAN=$1

  mkdir -p ./plans
  echo "Generating plan ($PLAN.tfplan) using var file envs/$WORKSPACE.tfvars"
  terraform.exe plan -destroy -out plans/$PLAN.tfplan -var-file=envs/$WORKSPACE.tfvars
}
function tfdestroy() {
  [ -z "$1" ] && echo "usage: tfdestroy [vars-file] plan-name" && return 0
  [ -n "$2" ] && WORKSPACE=$1 && PLAN=$2
  [ -z "$2" ] && WORKSPACE=playground && PLAN=$1

  mkdir -p ./plans
  echo "Generating destruction plan ($PLAN.tfplan) using var file envs/$WORKSPACE.tfvars"
  terraform.exe plan -out plans/$PLAN.tfplan -var-file=envs/$WORKSPACE.tfvars -destroy
}
tftest() {
  touch envs/playground.tfvars

  echo -e "terraform { \n  backend \"local\" { }\n}" >> backend_override.tf
}

alias tf="terraform.exe"
alias terraform="terraform.exe"
alias tfinit="terraform.exe init"