#!/usr/bin/env bash
# 04 - Application Load Balancer, target group, listener.
#
# The target group MUST be --target-type ip for Fargate with awsvpc
# networking. "instance" targets are for EC2 launch type with bridge mode.
# Getting this wrong is the single most common first-time ECS failure.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./env.sh
require_state VPC_ID SUBNET_A SUBNET_B ALB_SG

step "Creating ALB"
alb_arn=$(aws elbv2 create-load-balancer --region "$AWS_REGION" \
  --name "${PREFIX}-alb" \
  --subnets "$SUBNET_A" "$SUBNET_B" \
  --security-groups "$ALB_SG" \
  --scheme internet-facing --type application --ip-address-type ipv4 \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)
save_state ALB_ARN "$alb_arn"

alb_dns=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" \
  --load-balancer-arns "$alb_arn" \
  --query 'LoadBalancers[0].DNSName' --output text)
save_state ALB_DNS "$alb_dns"

step "Creating target group (type=ip, health check /health)"
tg_arn=$(aws elbv2 create-target-group --region "$AWS_REGION" \
  --name "${PREFIX}-tg" \
  --protocol HTTP --port "$APP_PORT" \
  --vpc-id "$VPC_ID" \
  --target-type ip \
  --health-check-protocol HTTP \
  --health-check-path /health \
  --health-check-interval-seconds 15 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2 \
  --matcher HttpCode=200 \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
save_state TG_ARN "$tg_arn"

# Fargate tasks start fast; 30s beats the 300s default when you are iterating.
aws elbv2 modify-target-group-attributes --region "$AWS_REGION" \
  --target-group-arn "$tg_arn" \
  --attributes Key=deregistration_delay.timeout_seconds,Value=30 >/dev/null

step "Creating listener on port 80"
listener_arn=$(aws elbv2 create-listener --region "$AWS_REGION" \
  --load-balancer-arn "$alb_arn" \
  --protocol HTTP --port 80 \
  --default-actions "Type=forward,TargetGroupArn=${tg_arn}" \
  --query 'Listeners[0].ListenerArn' --output text)
save_state LISTENER_ARN "$listener_arn"

echo
echo "ALB ready at: http://${alb_dns}"
echo "(It will 503 until the service is running - that is expected.)"
echo "Next: ./05-ecs-service.sh"
