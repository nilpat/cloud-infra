#!/usr/bin/env bash
# debug.sh - The four things to look at when a service will not come up,
#            in the order an experienced person looks at them.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./env.sh
require_state CLUSTER_NAME

step "1. Service events (read bottom-up; the newest is first)"
aws ecs describe-services --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" \
  --query 'services[0].events[0:8].[createdAt,message]' --output table || true

step "2. Why recent tasks STOPPED (this is where the real error lives)"
stopped=$(aws ecs list-tasks --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" --desired-status STOPPED \
  --query 'taskArns[0:5]' --output text 2>/dev/null || true)
if [[ -n "$stopped" && "$stopped" != "None" ]]; then
  # shellcheck disable=SC2086
  aws ecs describe-tasks --region "$AWS_REGION" \
    --cluster "$CLUSTER_NAME" --tasks $stopped \
    --query 'tasks[].{stoppedReason:stoppedReason,container:containers[0].name,exitCode:containers[0].exitCode,containerReason:containers[0].reason}' \
    --output table
else
  echo "  no stopped tasks"
fi

step "3. Target group health (is the ALB happy with the tasks?)"
if [[ -n "${TG_ARN:-}" ]]; then
  aws elbv2 describe-target-health --region "$AWS_REGION" \
    --target-group-arn "$TG_ARN" \
    --query 'TargetHealthDescriptions[].{target:Target.Id,port:Target.Port,state:TargetHealth.State,reason:TargetHealth.Reason,desc:TargetHealth.Description}' \
    --output table || true
else
  echo "  TG_ARN not in state"
fi

step "4. Latest application logs"
stream=$(aws logs describe-log-streams --region "$AWS_REGION" \
  --log-group-name "$LOG_GROUP" --order-by LastEventTime --descending \
  --max-items 1 --query 'logStreams[0].logStreamName' --output text 2>/dev/null || true)
if [[ -n "$stream" && "$stream" != "None" ]]; then
  echo "  stream: ${stream}"
  aws logs get-log-events --region "$AWS_REGION" \
    --log-group-name "$LOG_GROUP" --log-stream-name "$stream" \
    --limit 30 --query 'events[].message' --output text || true
else
  echo "  no log streams yet - if tasks never started, the failure is above"
fi

cat <<'EOF'

--- Common causes, mapped to what you just saw -------------------------
CannotPullContainerError          -> execution role, or no route to ECR
                                     (public subnet without assignPublicIp)
ResourceInitializationError       -> same family: networking/egress
Task failed ELB health checks     -> wrong containerPort, app not on 0.0.0.0,
                                     /health not returning 200, or task SG
                                     does not allow the ALB SG
exitCode 1 with app logs present  -> your code; read section 4
Target state "unused"             -> target group not attached to a listener
Service stuck at 0 running        -> read section 1, it always says why
------------------------------------------------------------------------
EOF
