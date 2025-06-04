#!/bin/bash

function aws_role_clear() {
    export AWS_ACCESS_KEY_ID=""
    export AWS_SECRET_ACCESS_KEY=""
    export AWS_SESSION_TOKEN=""

    echo "To clear AWS credentials from Windows"
    echo "set AWS_ACCESS_KEY_ID="
    echo "set AWS_SECRET_ACCESS_KEY="
    echo "set AWS_SESSION_TOKEN="
}

function aws_role_assume() {

    export AWS_ACCESS_KEY_ID=""
    export AWS_SECRET_ACCESS_KEY=""
    export AWS_SESSION_TOKEN=""

    if [ -n "$1" ]
    then
        aws sts assume-role --role-arn $1 --role-session-name session > __assume_role.tmp


        ak=$(cat __assume_role.tmp | jq .Credentials.AccessKeyId -r)
        sk=$(cat __assume_role.tmp | jq .Credentials.SecretAccessKey -r)
        st=$(cat __assume_role.tmp | jq .Credentials.SessionToken -r)

        export AWS_ACCESS_KEY_ID="$ak"
        export AWS_SECRET_ACCESS_KEY="$sk"
        export AWS_SESSION_TOKEN="$st"

        echo "Now logged in as $(aws sts get-caller-identity | jq .Arn -r)"

        echo "To set AWS credentials from Windows"
        echo "set AWS_ACCESS_KEY_ID=$ak"
        echo "set AWS_SECRET_ACCESS_KEY=$sk"
        echo "set AWS_SESSION_TOKEN=$st"
    else
        echo "AWS credentials cleared from WSL"
        echo "To clear AWS credentials from Windows"
        echo "set AWS_ACCESS_KEY_ID="
        echo "set AWS_SECRET_ACCESS_KEY="
        echo "set AWS_SESSION_TOKEN="
    fi

}

function aws_ecr() {
    account_id=$(aws sts get-caller-identity | jq .Account -r)
    region=$1

    aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $account_id.dkr.ecr.$region.amazonaws.com
}
