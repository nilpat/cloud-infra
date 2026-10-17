# cloud-infra

Reusable infrastructure-as-code and notes from hands-on cloud work — Terraform
modules, Kubernetes manifests, and the decisions and troubleshooting behind them,
organized by provider.

## AWS

| Topic | Description |
|---|---|
| [`aws/eks-cost-optimized-practice-cluster`](aws/eks-cost-optimized-practice-cluster/) | EKS cluster on Spot nodes with no NAT Gateway, one ALB shared across apps via the AWS Load Balancer Controller, and clean up/down automation that handles controller-owned resources Terraform doesn't track. |
