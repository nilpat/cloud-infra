#!/usr/bin/env bash
# Tear everything down in the SAFE order:
#   1. Delete Kubernetes objects that own AWS resources (Ingress -> ALB, PVC -> EBS)
#      while the Load Balancer Controller and EBS CSI driver are still running.
#   2. Wait until AWS has actually removed the ALB.
#   3. terraform destroy (controller, nodes, cluster, VPC, IAM).
#   4. Check for anything left behind that would keep billing.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" != "-y" ]]; then
  read -r -p "Destroy the practice cluster and everything in it? [y/N] " ok
  [[ "$ok" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

CLUSTER=$(terraform output -raw cluster_name 2>/dev/null || echo "eks-practice")
REGION=$(terraform output -raw region 2>/dev/null || echo "ap-south-1")

if aws eks describe-cluster --region "$REGION" --name "$CLUSTER" >/dev/null 2>&1; then
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null

  echo "==> Deleting demo namespace (Ingresses -> ALB, PVCs -> EBS volumes)"
  kubectl delete namespace demo --ignore-not-found --wait=true --timeout=10m
  kubectl delete storageclass gp3-encrypted --ignore-not-found

  echo "==> Waiting for the controller to delete the ALB..."
  for _ in $(seq 1 30); do
    left=$(aws resourcegroupstaggingapi get-resources --region "$REGION" \
      --tag-filters "Key=elbv2.k8s.aws/cluster,Values=$CLUSTER" \
      --resource-type-filters elasticloadbalancing:loadbalancer \
      --query 'length(ResourceTagMappingList)' --output text)
    [[ "$left" == "0" ]] && { echo "   ALB gone."; break; }
    sleep 10
  done
else
  echo "==> Cluster not found; skipping Kubernetes cleanup"
fi

echo "==> terraform destroy"
terraform destroy -auto-approve -input=false

echo
echo "==> Leftover check (anything listed here may still be billing):"
echo "-- Load balancers / target groups created by the controller:"
aws resourcegroupstaggingapi get-resources --region "$REGION" \
  --tag-filters "Key=elbv2.k8s.aws/cluster,Values=$CLUSTER" \
  --query 'ResourceTagMappingList[].ResourceARN' --output text
echo "-- Unattached EBS volumes created by the EBS CSI driver (any cluster in this Region):"
aws ec2 describe-volumes --region "$REGION" \
  --filters Name=status,Values=available Name=tag-key,Values=ebs.csi.aws.com/cluster \
  --query 'Volumes[].[VolumeId,Size,CreateTime]' --output text
echo "-- EKS clusters still in $REGION:"
aws eks list-clusters --region "$REGION" --query 'clusters' --output text
echo
echo "Done. If the lists above are empty, nothing from this practice setup is billing."
