#!/bin/bash


export AWS_CONFIG_WSL=true

function aws_key_rotate() {

    USERNAME=$(aws iam get-user --query 'User.UserName' --output text)
    KEY_COUNT=$(aws iam list-access-keys --user-name "$USERNAME" --query 'AccessKeyMetadata' --output json | jq length)

    echo "Rotating AWS access keys for $USERNAME"
    if [ "$KEY_COUNT" -ge 2 ]; then
      echo "❌ You already have 2 access keys. Please delete or deactivate one before creating a new key."
      exit 1
    fi

    echo "Creating new access key for $USERNAME..."
    NEW_KEY_JSON=$(aws iam create-access-key --user-name "$USERNAME" )
    NEW_ACCESS_KEY=$(echo "$NEW_KEY_JSON" | jq -r '.AccessKey.AccessKeyId')
    NEW_SECRET_KEY=$(echo "$NEW_KEY_JSON" | jq -r '.AccessKey.SecretAccessKey')

    OLD_ACCESS_KEY=$(aws iam list-access-keys --user-name "$USERNAME" \
        --query 'AccessKeyMetadata[?Status==`Active` && AccessKeyId!=`'"$NEW_ACCESS_KEY"'`].AccessKeyId' --output text)

    aws configure set aws_access_key_id "$NEW_ACCESS_KEY"
    aws configure set aws_secret_access_key "$NEW_SECRET_KEY"
    [ "$AWS_CONFIG_WSL" = "true" ] && aws.exe configure set aws_access_key_id "$NEW_ACCESS_KEY"
    [ "$AWS_CONFIG_WSL" = "true" ] && aws.exe configure set aws_secret_access_key "$NEW_SECRET_KEY"

    sleep 5

    echo "Disabling and deleting old access key $OLD_ACCESS_KEY..."
    aws iam update-access-key --access-key-id "$OLD_ACCESS_KEY" --status Inactive --user-name "$USERNAME"
    aws iam delete-access-key --access-key-id "$OLD_ACCESS_KEY" --user-name "$USERNAME"

    echo "Testing credentials: if an error message is displayed here, you will need to rectify this manually!"
    aws sts get-caller-identity
    [ "$AWS_CONFIG_WSL" = "true" ] && aws.exe sts get-caller-identity
}


function aws_secrets_json_validity() {

    search=$(echo $1 | sed -e "s|/|\\\\/|g")

    aws secretsmanager list-secrets | jq .SecretList[].Name -r | grep -e "$search" | while read secret
    do
        aws secretsmanager get-secret-value --secret-id $secret | jq .SecretString -r > .secret.tmp
        cat .secret.tmp | (jq > /dev/null 2>&1) || echo "Secret $secret is not valid JSON"
    done

}


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
