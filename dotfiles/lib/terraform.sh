#!/bin/bash

# Terraform support
function tfhelp() {
    echo "🏗️  Terraform Helpers"
    echo ""
    echo "📋 Planning:"
    echo "  tfplan [vars] <name>      Generate a plan"
    echo "  tfdestroy [vars] <name>   Generate a destruction plan"
    echo ""
    echo "🔧 Utilities:"
    echo "  tfinit                    Initialize terraform"
    echo "  tffmt                     Format terraform files"
    echo "  tfvalid                   Validate terraform config"
    echo "  tftest                    Setup local test environment"
    echo ""
    echo "💡 Aliases: tf, terraform → terraform.exe"
}

function tffmt() {
  terraform.exe fmt -recursive
}
function tfvalid() {
  terraform.exe validate
}
function tfplan() {
  [ -z "$1" ] && echo "⚠️  Usage: tfplan [vars-file] plan-name" && return 0
  [ -n "$2" ] && WORKSPACE=$1 && PLAN=$2
  [ -z "$2" ] && WORKSPACE=playground && PLAN=$1

  mkdir -p ./plans
  echo "📋 Generating plan: $PLAN.tfplan"
  echo "   📁 Vars: envs/$WORKSPACE.tfvars"
  terraform.exe plan -out plans/$PLAN.tfplan -var-file=envs/$WORKSPACE.tfvars
}
function tfdestroy() {
  [ -z "$1" ] && echo "⚠️  Usage: tfdestroy [vars-file] plan-name" && return 0
  [ -n "$2" ] && WORKSPACE=$1 && PLAN=$2
  [ -z "$2" ] && WORKSPACE=playground && PLAN=$1

  mkdir -p ./plans
  echo "💥 Generating destruction plan: $PLAN.tfplan"
  echo "   📁 Vars: envs/$WORKSPACE.tfvars"
  terraform.exe plan -out plans/$PLAN.tfplan -var-file=envs/$WORKSPACE.tfvars -destroy
}
tftest() {
  echo "🧪 Setting up local test environment..."
  touch envs/playground.tfvars
  echo -e "terraform { \n  backend \"local\" { }\n}" >> backend_override.tf
  echo "✅ Created envs/playground.tfvars"
  echo "✅ Created backend_override.tf"
}

alias tf="terraform.exe"
alias terraform="terraform.exe"
alias tfinit="terraform.exe init"