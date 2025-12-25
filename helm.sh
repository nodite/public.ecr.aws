#!/bin/bash

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load helm configuration
source "$SCRIPT_DIR/helm.conf"

ECR_REGISTRY=public.ecr.aws
ECR_NAMESPACE=oscaner
STATE_FILE="$SCRIPT_DIR/.pushed_charts.txt"
TEMP_DIR="$SCRIPT_DIR/.helm_temp"

# Create temp directory
mkdir -p "$TEMP_DIR"

# Clean expired entries
clean_expired_entries() {
  [ ! -f "$STATE_FILE" ] && return
  [ ! -s "$STATE_FILE" ] && return

  local NOW=$(date +%s)
  local WEEK_AGO=$((NOW - 604800))
  local TEMP_FILE="$STATE_FILE.tmp"

  > "$TEMP_FILE"

  # Process each line without using pipe to avoid subshell
  while IFS='|' read -r CHART TIMESTAMP; do
    [ -n "$TIMESTAMP" ] && [ "$TIMESTAMP" -gt "$WEEK_AGO" ] && echo "$CHART|$TIMESTAMP" >> "$TEMP_FILE"
  done < "$STATE_FILE"

  mv "$TEMP_FILE" "$STATE_FILE" || rm -f "$TEMP_FILE"
}

# Check if chart is already pushed
check_chart_pushed() {
  local CHART=$1
  [ -f "$STATE_FILE" ] && grep -q "^$CHART|" "$STATE_FILE"
}

# Mark chart as pushed
mark_chart_pushed() {
  local CHART=$1
  local TIMESTAMP=$(date +%s)
  echo "$CHART|$TIMESTAMP" >> "$STATE_FILE"
}

# Clean expired entries at start
clean_expired_entries

# Function to create or update ECR repository
create_or_update_repository() {
  local REPO_NAME=$1
  local CHART_NAME=$2
  local REPO_URL=$3
  local repo_exists

  repo_exists=$(aws ecr-public describe-repositories --repository-names $REPO_NAME --region us-east-1 --profile me.oscaner --no-cli-pager 2>/dev/null || true)
  catalog_data='{"description":"[Helm Chart] '$CHART_NAME'","aboutText":"Helm Chart from '$REPO_URL'","usageText":"https://github.com/Oscaner/public.ecr.aws"}'

  if [ -z "$repo_exists" ]; then
    aws ecr-public create-repository \
      --repository-name $REPO_NAME \
      --catalog-data "$catalog_data" \
      --region us-east-1 \
      --no-cli-pager \
      --profile me.oscaner
  else
    aws ecr-public put-repository-catalog-data \
      --repository-name $REPO_NAME \
      --catalog-data "$catalog_data" \
      --region us-east-1 \
      --no-cli-pager \
      --profile me.oscaner
  fi
}

# Process each helm chart
for CHART_INFO in "${HELM_CHARTS[@]}"; do
  # Parse chart info: REPO_NAME|REPO_URL|CHART_NAME|CHART_VERSION
  REPO_NAME=$(echo $CHART_INFO | cut -d'|' -f1)
  REPO_URL=$(echo $CHART_INFO | cut -d'|' -f2)
  CHART_NAME=$(echo $CHART_INFO | cut -d'|' -f3)
  CHART_VERSION=$(echo $CHART_INFO | cut -d'|' -f4)

  echo "Processing: $CHART_NAME:$CHART_VERSION from $REPO_NAME"

  # ECR repository name with repo/chart structure
  ECR_REPO_NAME="$REPO_NAME/$CHART_NAME"
  TARGET_CHART="$ECR_REGISTRY/$ECR_NAMESPACE/$ECR_REPO_NAME:$CHART_VERSION"
  echo "TARGET_CHART: $TARGET_CHART"

  if ! check_chart_pushed "$TARGET_CHART"; then
    # Add helm repo if not exists
    helm repo add $REPO_NAME $REPO_URL 2>/dev/null || true
    helm repo update $REPO_NAME

    # Pull chart
    cd "$TEMP_DIR"
    helm pull $REPO_NAME/$CHART_NAME --version $CHART_VERSION

    # Package chart
    CHART_FILE="${CHART_NAME}-${CHART_VERSION}.tgz"

    if [ -f "$CHART_FILE" ]; then
      # Create or update ECR repository with repo/chart name
      create_or_update_repository "$ECR_REPO_NAME" "$CHART_NAME" "$REPO_URL"

      # Login to ECR
      aws ecr-public get-login-password --region us-east-1 --profile me.oscaner | \
        helm registry login --username AWS --password-stdin $ECR_REGISTRY

      # Push chart to ECR with repo/chart structure
      helm push "$CHART_FILE" oci://$ECR_REGISTRY/$ECR_NAMESPACE/$REPO_NAME

      mark_chart_pushed "$TARGET_CHART"

      # Clean up
      rm -f "$CHART_FILE"

      echo "Successfully pushed $TARGET_CHART"
    else
      echo "Error: Chart file $CHART_FILE not found"
    fi
  else
    echo "Chart $TARGET_CHART already pushed, skipping"
  fi

  echo "====================================="
  echo "====================================="
done

# Clean up temp directory
rm -rf "$TEMP_DIR"

echo "All charts processed successfully!"
