#!/usr/bin/env bash
# 05 - Cluster, task definition, service. Then wait for it to go healthy.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./env.sh
require_state REPO_URI IMAGE_TAG EXEC_ROLE_ARN TASK_ROLE_ARN TG_ARN SUBNET_A SUBNET_B TASK_SG ALB_DNS

DESIRED_COUNT="${DESIRED_COUNT:-2}"

step "Creating cluster ${CLUSTER_NAME}"
aws ecs create-cluster --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --capacity-providers FARGATE FARGATE_SPOT \
  --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 \
  --settings name=containerInsights,value=enabled >/dev/null
echo "  ok"

step "Rendering task definition"
RENDERED="$(mktemp)"
sed \
  -e "s|__TASK_FAMILY__|${TASK_FAMILY}|g" \
  -e "s|__EXEC_ROLE_ARN__|${EXEC_ROLE_ARN}|g" \
  -e "s|__TASK_ROLE_ARN__|${TASK_ROLE_ARN}|g" \
  -e "s|__IMAGE__|${REPO_URI}:${IMAGE_TAG}|g" \
  -e "s|__IMAGE_TAG__|${IMAGE_TAG}|g" \
  -e "s|__APP_PORT__|${APP_PORT}|g" \
  -e "s|__LOG_GROUP__|${LOG_GROUP}|g" \
  -e "s|__AWS_REGION__|${AWS_REGION}|g" \
  task-definition.json.tpl > "$RENDERED"
echo "  rendered to ${RENDERED}"

step "Registering task definition"
td_arn=$(aws ecs register-task-definition --region "$AWS_REGION" \
  --cli-input-json "file://${RENDERED}" \
  --query 'taskDefinition.taskDefinitionArn' --output text)
save_state TASK_DEF_ARN "$td_arn"
echo "  ${td_arn}"

step "Creating service ${SERVICE_NAME} (desired count ${DESIRED_COUNT})"
aws ecs create-service --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" \
  --service-name "$SERVICE_NAME" \
  --task-definition "$td_arn" \
  --desired-count "$DESIRED_COUNT" \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_A},${SUBNET_B}],securityGroups=[${TASK_SG}],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=${TG_ARN},containerName=web,containerPort=${APP_PORT}" \
  --health-check-grace-period-seconds 30 \
  --deployment-configuration "maximumPercent=200,minimumHealthyPercent=100,deploymentCircuitBreaker={enable=true,rollback=true}" \
  >/dev/null
echo "  created"

step "Waiting for the service to stabilise (a few minutes is normal)"
if aws ecs wait services-stable --region "$AWS_REGION" \
     --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME"; then
  echo "  stable"
else
  echo "  did NOT stabilise. Run ./debug.sh to see why." >&2
  exit 1
fi

echo
echo "-------------------------------------------------------------"
echo " Try it:   curl http://${ALB_DNS}/"
echo " Repeat it a few times and watch served_by change between tasks."
echo "-------------------------------------------------------------"
