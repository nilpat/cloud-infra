#!/usr/bin/env bash
# 99 - Tear everything down. Run this at the end of every session.
#
# The ALB is the item that actually costs money while idle (~$16-18/month if
# you leave it running). Do not skip this.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./env.sh

read -rp "Delete all ${PREFIX} resources in ${AWS_REGION}? [y/N] " ans
[[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "aborted"; exit 0; }

quiet() { "$@" >/dev/null 2>&1 || true; }

step "Scaling service to 0 and deleting it"
quiet aws ecs update-service --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" --desired-count 0
quiet aws ecs delete-service --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" --force
echo "  waiting for tasks to stop"
quiet aws ecs wait services-inactive --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME"

step "Deleting listener, target group, ALB"
quiet aws elbv2 delete-listener --region "$AWS_REGION" --listener-arn "${LISTENER_ARN:-}"
quiet aws elbv2 delete-load-balancer --region "$AWS_REGION" --load-balancer-arn "${ALB_ARN:-}"
# The ALB must be gone before its ENIs release the security group.
echo "  waiting ~30s for ALB network interfaces to clear"
quiet aws elbv2 wait load-balancers-deleted --region "$AWS_REGION" \
  --load-balancer-arns "${ALB_ARN:-}"
quiet aws elbv2 delete-target-group --region "$AWS_REGION" --target-group-arn "${TG_ARN:-}"

step "Deregistering task definitions"
for arn in $(aws ecs list-task-definitions --region "$AWS_REGION" \
              --family-prefix "$TASK_FAMILY" --query 'taskDefinitionArns[]' \
              --output text 2>/dev/null || true); do
  quiet aws ecs deregister-task-definition --region "$AWS_REGION" --task-definition "$arn"
done

step "Deleting cluster and log group"
quiet aws ecs delete-cluster --region "$AWS_REGION" --cluster "$CLUSTER_NAME"
quiet aws logs delete-log-group --region "$AWS_REGION" --log-group-name "$LOG_GROUP"

step "Deleting ECR repository (including images)"
quiet aws ecr delete-repository --region "$AWS_REGION" \
  --repository-name "$ECR_REPO" --force

step "Deleting IAM roles"
quiet aws iam detach-role-policy --role-name "$EXEC_ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
quiet aws iam delete-role-policy --role-name "$EXEC_ROLE_NAME" \
  --policy-name "${PREFIX}-read-params"
quiet aws iam delete-role --role-name "$EXEC_ROLE_NAME"
quiet aws iam detach-role-policy --role-name "$TASK_ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
quiet aws iam delete-role --role-name "$TASK_ROLE_NAME"

step "Deleting SSM parameters"
quiet aws ssm delete-parameter --region "$AWS_REGION" --name "/${PREFIX}/greeting"

step "Deleting security groups, subnets, route table, IGW, VPC"
# Security groups can take a moment after the ALB/ENIs go away.
for attempt in 1 2 3 4 5 6; do
  if aws ec2 delete-security-group --region "$AWS_REGION" --group-id "${TASK_SG:-}" 2>/dev/null \
     && aws ec2 delete-security-group --region "$AWS_REGION" --group-id "${ALB_SG:-}" 2>/dev/null; then
    break
  fi
  echo "  ENIs still detaching, retry ${attempt}/6"
  aws ec2 wait network-interface-available --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID:-none}" 2>/dev/null || true
done
quiet aws ec2 delete-security-group --region "$AWS_REGION" --group-id "${TASK_SG:-}"
quiet aws ec2 delete-security-group --region "$AWS_REGION" --group-id "${ALB_SG:-}"

quiet aws ec2 delete-subnet --region "$AWS_REGION" --subnet-id "${SUBNET_A:-}"
quiet aws ec2 delete-subnet --region "$AWS_REGION" --subnet-id "${SUBNET_B:-}"
quiet aws ec2 delete-route-table --region "$AWS_REGION" --route-table-id "${RTB_ID:-}"
quiet aws ec2 detach-internet-gateway --region "$AWS_REGION" \
  --internet-gateway-id "${IGW_ID:-}" --vpc-id "${VPC_ID:-}"
quiet aws ec2 delete-internet-gateway --region "$AWS_REGION" --internet-gateway-id "${IGW_ID:-}"
quiet aws ec2 delete-vpc --region "$AWS_REGION" --vpc-id "${VPC_ID:-}"

rm -f "$STATE_FILE"
echo
echo "Torn down. state.env removed."
echo "Sanity check in the console: EC2 > Load Balancers, and VPC > Your VPCs."
