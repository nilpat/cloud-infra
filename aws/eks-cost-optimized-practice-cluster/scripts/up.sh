#!/usr/bin/env bash
# Spin up the practice EKS cluster + sample apps behind ONE shared ALB.
# Takes ~15-20 minutes (the EKS control plane alone is ~10 min).
set -euo pipefail
cd "$(dirname "$0")/.."

for bin in terraform aws kubectl; do
  command -v "$bin" >/dev/null || { echo "ERROR: '$bin' is not installed"; exit 1; }
done

echo "==> AWS identity in use:"
aws sts get-caller-identity --output table

echo "==> Creating VPC, EKS cluster, Spot nodes, add-ons, Load Balancer Controller..."
terraform init -upgrade -input=false
terraform apply -auto-approve -input=false

CLUSTER=$(terraform output -raw cluster_name)
REGION=$(terraform output -raw region)

echo "==> Configuring kubectl"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER"
kubectl get nodes -o wide

echo "==> Deploying sample apps, Ingresses and StatefulSet"
# Retry: the controller's admission webhook can take a few seconds to become ready
for attempt in 1 2 3 4 5; do
  if kubectl apply -f k8s/; then break; fi
  echo "   apply failed (attempt $attempt), retrying in 15s..."; sleep 15
  [[ $attempt -eq 5 ]] && { echo "ERROR: kubectl apply kept failing"; exit 1; }
done

echo "==> Waiting for the shared ALB hostname (2-3 min)..."
ALB=""
for _ in $(seq 1 40); do
  ALB=$(kubectl get ingress web -n demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [[ -n "$ALB" ]] && break
  sleep 10
done

kubectl get pods,svc,ingress,pvc -n demo
echo
if [[ -n "$ALB" ]]; then
  echo "ALB:  http://$ALB/        -> web (nginx)"
  echo "      http://$ALB/echo    -> echo service"
  echo "(DNS and target health can take another 1-2 minutes before it responds.)"
else
  echo "ALB not ready yet. Check: kubectl describe ingress -n demo"
  echo "      and: kubectl logs -n kube-system deploy/aws-load-balancer-controller"
fi
echo
echo "Cluster is billing (~\$0.25-0.35/hr). When done:  ./scripts/down.sh"
