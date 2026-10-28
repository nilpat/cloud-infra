#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Shared configuration + helpers for the ECS lab.
# Every numbered script sources this file. Edit the values at the top if you
# want a different region / naming prefix.
# ---------------------------------------------------------------------------

export AWS_REGION="${AWS_REGION:-ap-south-1}"
export PREFIX="${PREFIX:-ecslab}"

export VPC_CIDR="10.20.0.0/16"
export SUBNET_A_CIDR="10.20.1.0/24"
export SUBNET_B_CIDR="10.20.2.0/24"

export APP_PORT=8080
export ECR_REPO="${PREFIX}-app"
export CLUSTER_NAME="${PREFIX}-cluster"
export SERVICE_NAME="${PREFIX}-svc"
export TASK_FAMILY="${PREFIX}-task"
export LOG_GROUP="/ecs/${PREFIX}"

export EXEC_ROLE_NAME="${PREFIX}-task-execution-role"
export TASK_ROLE_NAME="${PREFIX}-task-role"

# --- state file ------------------------------------------------------------
# Each script writes the IDs it created here so later scripts can read them.
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state.env"
export STATE_FILE
touch "$STATE_FILE"
# shellcheck disable=SC1090
source "$STATE_FILE"

save_state() {
  # save_state KEY VALUE  -> persists and exports immediately
  local key="$1" val="$2"
  # remove any previous line for this key
  if grep -q "^export ${key}=" "$STATE_FILE" 2>/dev/null; then
    grep -v "^export ${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
  fi
  echo "export ${key}=\"${val}\"" >> "$STATE_FILE"
  export "${key}=${val}"
  echo "  saved ${key}=${val}"
}

require_state() {
  # require_state VAR1 VAR2 ... -> fail early with a useful message
  local missing=0
  for v in "$@"; do
    if [[ -z "${!v:-}" ]]; then
      echo "ERROR: ${v} is not set. Did you run the previous script?" >&2
      missing=1
    fi
  done
  [[ $missing -eq 0 ]] || exit 1
}

step() { echo; echo "==> $*"; }

export ACCOUNT_ID="${ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)}"
