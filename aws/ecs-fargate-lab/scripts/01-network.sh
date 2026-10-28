#!/usr/bin/env bash
# 01 - Network: VPC, two public subnets in different AZs, IGW, route table,
#      and the two security groups (ALB -> task).
#
# Deliberately NO NAT gateway. Tasks run in public subnets with a public IP so
# they can pull from ECR. That is not how you would build production, but a NAT
# gateway is ~$35/month and this is a lab. The README explains the swap.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./env.sh

if [[ -n "${VPC_ID:-}" ]]; then
  echo "VPC ${VPC_ID} already in state.env - skipping. Run ./99-teardown.sh to start over."
  exit 0
fi

step "Picking two availability zones in ${AWS_REGION}"
mapfile -t AZS < <(aws ec2 describe-availability-zones \
  --region "$AWS_REGION" \
  --filters "Name=state,Values=available" \
  --query 'AvailabilityZones[0:2].ZoneName' --output text | tr '\t' '\n')
echo "  using ${AZS[0]} and ${AZS[1]}"

step "Creating VPC ${VPC_CIDR}"
vpc_id=$(aws ec2 create-vpc \
  --region "$AWS_REGION" \
  --cidr-block "$VPC_CIDR" \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PREFIX}-vpc}]" \
  --query 'Vpc.VpcId' --output text)
save_state VPC_ID "$vpc_id"

# DNS hostnames are required for ECR pulls over the public path to resolve.
aws ec2 modify-vpc-attribute --region "$AWS_REGION" --vpc-id "$vpc_id" --enable-dns-hostnames
aws ec2 modify-vpc-attribute --region "$AWS_REGION" --vpc-id "$vpc_id" --enable-dns-support

step "Creating internet gateway"
igw_id=$(aws ec2 create-internet-gateway \
  --region "$AWS_REGION" \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PREFIX}-igw}]" \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --region "$AWS_REGION" \
  --internet-gateway-id "$igw_id" --vpc-id "$vpc_id"
save_state IGW_ID "$igw_id"

create_subnet() {
  local cidr="$1" az="$2" name="$3"
  local sid
  sid=$(aws ec2 create-subnet \
    --region "$AWS_REGION" \
    --vpc-id "$vpc_id" --cidr-block "$cidr" --availability-zone "$az" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${name}}]" \
    --query 'Subnet.SubnetId' --output text)
  aws ec2 modify-subnet-attribute --region "$AWS_REGION" \
    --subnet-id "$sid" --map-public-ip-on-launch >/dev/null
  echo "$sid"
}

step "Creating two public subnets"
subnet_a=$(create_subnet "$SUBNET_A_CIDR" "${AZS[0]}" "${PREFIX}-public-a")
subnet_b=$(create_subnet "$SUBNET_B_CIDR" "${AZS[1]}" "${PREFIX}-public-b")
save_state SUBNET_A "$subnet_a"
save_state SUBNET_B "$subnet_b"

step "Creating route table with default route to the IGW"
rtb_id=$(aws ec2 create-route-table \
  --region "$AWS_REGION" --vpc-id "$vpc_id" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PREFIX}-public-rtb}]" \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --region "$AWS_REGION" \
  --route-table-id "$rtb_id" --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$igw_id" >/dev/null
aws ec2 associate-route-table --region "$AWS_REGION" \
  --route-table-id "$rtb_id" --subnet-id "$subnet_a" >/dev/null
aws ec2 associate-route-table --region "$AWS_REGION" \
  --route-table-id "$rtb_id" --subnet-id "$subnet_b" >/dev/null
save_state RTB_ID "$rtb_id"

step "Creating security groups"
# ALB: open to the world on 80.
alb_sg=$(aws ec2 create-security-group \
  --region "$AWS_REGION" \
  --group-name "${PREFIX}-alb-sg" \
  --description "ALB ingress from internet" \
  --vpc-id "$vpc_id" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --region "$AWS_REGION" \
  --group-id "$alb_sg" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null

# Task: accepts traffic ONLY from the ALB security group, not from a CIDR.
# This SG-referencing-SG pattern is the thing worth remembering here.
task_sg=$(aws ec2 create-security-group \
  --region "$AWS_REGION" \
  --group-name "${PREFIX}-task-sg" \
  --description "Fargate tasks - from ALB only" \
  --vpc-id "$vpc_id" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --region "$AWS_REGION" \
  --group-id "$task_sg" --protocol tcp --port "$APP_PORT" \
  --source-group "$alb_sg" >/dev/null

save_state ALB_SG "$alb_sg"
save_state TASK_SG "$task_sg"

echo
echo "Network ready. Next: ./02-ecr-build-push.sh"
