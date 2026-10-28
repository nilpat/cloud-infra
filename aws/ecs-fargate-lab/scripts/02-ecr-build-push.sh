#!/usr/bin/env bash
# 02 - Build the image locally, create the ECR repo, push.
#
# Usage: ./02-ecr-build-push.sh [tag]      (tag defaults to v1)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./env.sh

TAG="${1:-v1}"

step "Ensuring ECR repository ${ECR_REPO} exists"
if ! aws ecr describe-repositories --region "$AWS_REGION" \
      --repository-names "$ECR_REPO" >/dev/null 2>&1; then
  aws ecr create-repository --region "$AWS_REGION" \
    --repository-name "$ECR_REPO" \
    --image-scanning-configuration scanOnPush=true >/dev/null
  echo "  created"
else
  echo "  already exists"
fi

REPO_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"
save_state REPO_URI "$REPO_URI"

step "Logging Docker in to ECR"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin \
      "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

step "Building ${REPO_URI}:${TAG}"
# --provenance=false keeps the pushed artifact a plain image manifest. Without
# it, buildx can push an OCI image index that older tooling reads oddly.
docker build --platform linux/amd64 --provenance=false \
  -t "${REPO_URI}:${TAG}" ../app

step "Pushing"
docker push "${REPO_URI}:${TAG}"

save_state IMAGE_TAG "$TAG"
echo
echo "Pushed ${REPO_URI}:${TAG}. Next: ./03-iam.sh"
