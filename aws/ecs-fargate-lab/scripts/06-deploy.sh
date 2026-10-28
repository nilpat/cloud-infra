#!/usr/bin/env bash
# 06 - Ship a new version and watch the rolling deployment.
#
# Usage: ./06-deploy.sh v2
#
# This is the loop you will repeat forever in real life: build, push,
# register a new task definition revision, update the service.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./env.sh
require_state REPO_URI EXEC_ROLE_ARN TASK_ROLE_ARN ALB_DNS

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  echo "Usage: $0 <tag>   e.g. $0 v2" >&2
  exit 1
fi

./02-ecr-build-push.sh "$TAG"
source "$STATE_FILE"

step "Registering new revision with image tag ${TAG}"
RENDERED="$(mktemp)"
sed \
  -e "s|__TASK_FAMILY__|${TASK_FAMILY}|g" \
  -e "s|__EXEC_ROLE_ARN__|${EXEC_ROLE_ARN}|g" \
  -e "s|__TASK_ROLE_ARN__|${TASK_ROLE_ARN}|g" \
  -e "s|__IMAGE__|${REPO_URI}:${TAG}|g" \
  -e "s|__IMAGE_TAG__|${TAG}|g" \
  -e "s|__APP_PORT__|${APP_PORT}|g" \
  -e "s|__LOG_GROUP__|${LOG_GROUP}|g" \
  -e "s|__AWS_REGION__|${AWS_REGION}|g" \
  task-definition.json.tpl > "$RENDERED"

td_arn=$(aws ecs register-task-definition --region "$AWS_REGION" \
  --cli-input-json "file://${RENDERED}" \
  --query 'taskDefinition.taskDefinitionArn' --output text)
save_state TASK_DEF_ARN "$td_arn"
echo "  ${td_arn}"

step "Updating service"
aws ecs update-service --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" \
  --task-definition "$td_arn" >/dev/null

echo
echo "Deployment started. In another terminal, poll the app and watch the"
echo "version flip over as old tasks drain:"
echo
echo "  while true; do curl -s http://${ALB_DNS}/ | head -c 200; echo; sleep 1; done"
echo

step "Waiting for the rollout to finish"
aws ecs wait services-stable --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME"
echo "  done - everything is now running ${TAG}"
