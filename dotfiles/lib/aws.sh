#!/bin/bash

export AWS_CONFIG_WSL=true

function aws_help() {
    echo "☁️  AWS Helpers"
    echo ""
    echo "🔑 Credentials:"
    echo "  aws_key_rotate            Rotate your AWS access keys"
    echo "  aws_role_assume [arn]     Assume a role (clears if no ARN)"
    echo "  aws_role_clear            Clear assumed role credentials"
    echo ""
    echo "🔍 Utilities:"
    echo "  aws_secrets_json_validity [pattern]   Check JSON validity of secrets"
    echo "  aws_ecr [region]          Login to ECR in specified region"
}

function aws_key_rotate() {

    USERNAME=$(aws iam get-user --query 'User.UserName' --output text)
    KEY_COUNT=$(aws iam list-access-keys --user-name "$USERNAME" --query 'AccessKeyMetadata' --output json | jq length)

    echo "🔑 Rotating AWS access keys for $USERNAME"
    if [ "$KEY_COUNT" -ge 2 ]; then
      echo "❌ You already have 2 access keys. Please delete or deactivate one before creating a new key."
      exit 1
    fi

    echo "➕ Creating new access key..."
    NEW_KEY_JSON=$(aws iam create-access-key --user-name "$USERNAME" )
    NEW_ACCESS_KEY=$(echo "$NEW_KEY_JSON" | jq -r '.AccessKey.AccessKeyId')
    NEW_SECRET_KEY=$(echo "$NEW_KEY_JSON" | jq -r '.AccessKey.SecretAccessKey')

    OLD_ACCESS_KEY=$(aws iam list-access-keys --user-name "$USERNAME" \
        --query 'AccessKeyMetadata[?Status==`Active` && AccessKeyId!=`'"$NEW_ACCESS_KEY"'`].AccessKeyId' --output text)

    echo "🔄 Updating credentials..."
    aws configure set aws_access_key_id "$NEW_ACCESS_KEY"
    aws configure set aws_secret_access_key "$NEW_SECRET_KEY"
    [ "$AWS_CONFIG_WSL" = "true" ] && aws.exe configure set aws_access_key_id "$NEW_ACCESS_KEY"
    [ "$AWS_CONFIG_WSL" = "true" ] && aws.exe configure set aws_secret_access_key "$NEW_SECRET_KEY"

    sleep 5

    echo "🗑️  Disabling old key $OLD_ACCESS_KEY..."
    aws iam update-access-key --access-key-id "$OLD_ACCESS_KEY" --status Inactive --user-name "$USERNAME"
    aws iam delete-access-key --access-key-id "$OLD_ACCESS_KEY" --user-name "$USERNAME"

    echo "🧪 Testing credentials..."
    aws sts get-caller-identity
    [ "$AWS_CONFIG_WSL" = "true" ] && aws.exe sts get-caller-identity
    echo "✅ Key rotation complete"
}


function aws_secrets_json_validity() {

    search=$(echo $1 | sed -e "s|/|\\\\/|g")

    echo "🔍 Checking JSON validity for secrets matching '$1'..."
    aws secretsmanager list-secrets | jq .SecretList[].Name -r | grep -e "$search" | while read secret
    do
        aws secretsmanager get-secret-value --secret-id $secret | jq .SecretString -r > .secret.tmp
        first_char=$(head -c1 .secret.tmp)

        # Skip plaintext secrets (only validate if starts with { or [)
        if [[ "$first_char" != "{" && "$first_char" != "[" ]]; then
            echo "  ⏭️  $secret (plaintext, skipped)"
            continue
        fi

        if cat .secret.tmp | jq > /dev/null 2>&1; then
            echo "  ✅ $secret"
        else
            echo "  ❌ $secret (invalid JSON)"
        fi
    done

}


function aws_role_clear() {
    export AWS_ACCESS_KEY_ID=""
    export AWS_SECRET_ACCESS_KEY=""
    export AWS_SESSION_TOKEN=""

    echo "🔓 AWS credentials cleared from WSL"
    echo ""
    echo "📋 To clear from Windows:"
    echo "   set AWS_ACCESS_KEY_ID="
    echo "   set AWS_SECRET_ACCESS_KEY="
    echo "   set AWS_SESSION_TOKEN="
}

function aws_role_assume() {

    export AWS_ACCESS_KEY_ID=""
    export AWS_SECRET_ACCESS_KEY=""
    export AWS_SESSION_TOKEN=""

    if [ -n "$1" ]
    then
        echo "🔐 Assuming role..."
        aws sts assume-role --role-arn $1 --role-session-name session > __assume_role.tmp


        ak=$(cat __assume_role.tmp | jq .Credentials.AccessKeyId -r)
        sk=$(cat __assume_role.tmp | jq .Credentials.SecretAccessKey -r)
        st=$(cat __assume_role.tmp | jq .Credentials.SessionToken -r)

        export AWS_ACCESS_KEY_ID="$ak"
        export AWS_SECRET_ACCESS_KEY="$sk"
        export AWS_SESSION_TOKEN="$st"

        echo "✅ Now logged in as $(aws sts get-caller-identity | jq .Arn -r)"
        echo ""
        echo "📋 Windows credentials (copy to CMD):"
        echo "   set AWS_ACCESS_KEY_ID=$ak"
        echo "   set AWS_SECRET_ACCESS_KEY=$sk"
        echo "   set AWS_SESSION_TOKEN=$st"
    else
        echo "🔓 AWS credentials cleared from WSL"
        echo ""
        echo "📋 To clear from Windows:"
        echo "   set AWS_ACCESS_KEY_ID="
        echo "   set AWS_SECRET_ACCESS_KEY="
        echo "   set AWS_SESSION_TOKEN="
    fi

}

function aws_ecr() {
    account_id=$(aws sts get-caller-identity | jq .Account -r)
    region=$1

    echo "🐳 Logging into ECR ($region)..."
    aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $account_id.dkr.ecr.$region.amazonaws.com
    echo "✅ Logged in to $account_id.dkr.ecr.$region.amazonaws.com"
}
