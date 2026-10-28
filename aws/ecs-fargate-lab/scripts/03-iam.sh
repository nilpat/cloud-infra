#!/usr/bin/env bash
# 03 - IAM: the two roles people most often confuse.
#
#   execution role -> used by the ECS AGENT, before your code runs.
#                     Pulls the image, writes to CloudWatch Logs, reads the
#                     SSM/Secrets values named in the task definition.
#
#   task role      -> used by YOUR CODE at runtime, via the SDK.
#                     S3, DynamoDB, whatever the app actually calls.
#
# If your task fails with "CannotPullContainerError" the execution role is the
# suspect. If your app gets AccessDenied from boto3, it is the task role.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./env.sh

TRUST='{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ecs-tasks.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}'

ensure_role() {
  local name="$1"
  if aws iam get-role --role-name "$name" >/dev/null 2>&1; then
    echo "  role ${name} already exists"
  else
    aws iam create-role --role-name "$name" \
      --assume-role-policy-document "$TRUST" \
      --description "ECS lab (${PREFIX})" >/dev/null
    echo "  created ${name}"
  fi
}

step "Execution role"
ensure_role "$EXEC_ROLE_NAME"
aws iam attach-role-policy --role-name "$EXEC_ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Needed for the SSM Parameter Store exercise later. Scoped to this lab's
# parameter path rather than "*", because habits form early.
step "Allowing the execution role to read /${PREFIX}/* parameters"
aws iam put-role-policy --role-name "$EXEC_ROLE_NAME" \
  --policy-name "${PREFIX}-read-params" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": [\"ssm:GetParameters\"],
      \"Resource\": \"arn:aws:ssm:${AWS_REGION}:${ACCOUNT_ID}:parameter/${PREFIX}/*\"
    }]
  }"

step "Task role"
ensure_role "$TASK_ROLE_NAME"
# Nothing attached on purpose -- the app makes no AWS calls yet. Attach
# something here when you extend the app, and watch the difference.
aws iam attach-role-policy --role-name "$TASK_ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null \
  || echo "  (optional policy attach skipped)"

save_state EXEC_ROLE_ARN "arn:aws:iam::${ACCOUNT_ID}:role/${EXEC_ROLE_NAME}"
save_state TASK_ROLE_ARN "arn:aws:iam::${ACCOUNT_ID}:role/${TASK_ROLE_NAME}"

step "Creating CloudWatch log group ${LOG_GROUP}"
aws logs create-log-group --region "$AWS_REGION" \
  --log-group-name "$LOG_GROUP" 2>/dev/null || echo "  already exists"
aws logs put-retention-policy --region "$AWS_REGION" \
  --log-group-name "$LOG_GROUP" --retention-in-days 7

echo
echo "IAM ready. Next: ./04-alb.sh"
