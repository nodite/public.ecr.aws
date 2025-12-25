#!/bin/bash

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load image configuration
source "$SCRIPT_DIR/images.conf"

ECR_REGISTRY=public.ecr.aws/oscaner
STATE_FILE="$SCRIPT_DIR/.pushed_images.txt"

# Clean expired entries
clean_expired_entries() {
  [ ! -f "$STATE_FILE" ] && return
  [ ! -s "$STATE_FILE" ] && return

  local NOW=$(date +%s)
  local WEEK_AGO=$((NOW - 604800))
  local TEMP_FILE="$STATE_FILE.tmp"

  > "$TEMP_FILE"

  # Process each line without using pipe to avoid subshell
  while IFS='|' read -r IMAGE TIMESTAMP; do
    [ -n "$TIMESTAMP" ] && [ "$TIMESTAMP" -gt "$WEEK_AGO" ] && echo "$IMAGE|$TIMESTAMP" >> "$TEMP_FILE"
  done < "$STATE_FILE"

  mv "$TEMP_FILE" "$STATE_FILE" || rm -f "$TEMP_FILE"
}

# Check if image is already pushed
check_image_pushed() {
  local IMAGE=$1
  [ -f "$STATE_FILE" ] && grep -q "^$IMAGE|" "$STATE_FILE"
}

# Mark image as pushed
mark_image_pushed() {
  local IMAGE=$1
  local TIMESTAMP=$(date +%s)
  echo "$IMAGE|$TIMESTAMP" >> "$STATE_FILE"
}

# Clean expired entries at start
clean_expired_entries

# Generate image list dynamically

# func to create-repository or update-repository
create_or_update_repository() {
  local REPO_NAME=$1
  local BASE_IMAGE=$2
  local repo_exists

  repo_exists=$(aws ecr-public describe-repositories --repository-names $REPO_NAME --region us-east-1 --profile me.oscaner --no-cli-pager || true)
  catalog_data='{"description":"[Official Image] '$BASE_IMAGE'","aboutText":"'$BASE_IMAGE'","usageText":"https://github.com/Oscaner/public.ecr.aws"}'


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

for BASE_IMAGE in "${BASE_IMAGES[@]}"; do
  echo "BASE_IMAGE: $BASE_IMAGE"

  BASE_REGISTRY=$(echo $BASE_IMAGE | cut -d'/' -f1)
  BASE_IMAGE_NAME=$(echo $BASE_IMAGE | cut -d'/' -f2- | cut -d':' -f1)
  BASE_IMAGE_TAG=$(echo $BASE_IMAGE | cut -d':' -f2)

  TARGET_IMAGE_FOR_AMD64=$ECR_REGISTRY/$BASE_IMAGE_NAME:$BASE_IMAGE_TAG-amd64
  echo "TARGET_IMAGE_FOR_AMD64: $TARGET_IMAGE_FOR_AMD64"

  TARGET_IMAGE_FOR_ARM64=$ECR_REGISTRY/$BASE_IMAGE_NAME:$BASE_IMAGE_TAG-arm64
  echo "TARGET_IMAGE_FOR_ARM64: $TARGET_IMAGE_FOR_ARM64"

  TARGET_IMAGE=$ECR_REGISTRY/$BASE_IMAGE_NAME:$BASE_IMAGE_TAG
  echo "TARGET_IMAGE: $TARGET_IMAGE"

  if ! check_image_pushed "$TARGET_IMAGE"; then
    create_or_update_repository "$BASE_IMAGE_NAME" "$BASE_REGISTRY/$BASE_IMAGE_NAME"

    docker pull --platform linux/amd64 $BASE_IMAGE
    docker tag $BASE_IMAGE $TARGET_IMAGE_FOR_AMD64
    docker push $TARGET_IMAGE_FOR_AMD64

    docker pull --platform linux/arm64 $BASE_IMAGE
    docker tag $BASE_IMAGE $TARGET_IMAGE_FOR_ARM64
    docker push $TARGET_IMAGE_FOR_ARM64

    docker manifest create $TARGET_IMAGE --amend $TARGET_IMAGE_FOR_AMD64 --amend $TARGET_IMAGE_FOR_ARM64
    docker manifest push $TARGET_IMAGE

    mark_image_pushed "$TARGET_IMAGE"

    docker rmi -f $BASE_IMAGE $TARGET_IMAGE_FOR_AMD64 $TARGET_IMAGE_FOR_ARM64 || true
    docker manifest rm $TARGET_IMAGE || true
  else
    echo "Image $TARGET_IMAGE already pushed, skipping"
  fi

  echo "====================================="
  echo "====================================="

  LAST_PART=$(echo $BASE_IMAGE_NAME | rev | cut -d'/' -f1 | rev)
  if [[ "$BASE_IMAGE_NAME" == *"$LAST_PART/$LAST_PART"* ]]; then
    DEDUP_IMAGE_NAME=$LAST_PART

    DEDUP_TARGET_IMAGE_FOR_AMD64=$ECR_REGISTRY/$DEDUP_IMAGE_NAME:$BASE_IMAGE_TAG-amd64
    echo "DEDUP_TARGET_IMAGE_FOR_AMD64: $DEDUP_TARGET_IMAGE_FOR_AMD64"

    DEDUP_TARGET_IMAGE_FOR_ARM64=$ECR_REGISTRY/$DEDUP_IMAGE_NAME:$BASE_IMAGE_TAG-arm64
    echo "DEDUP_TARGET_IMAGE_FOR_ARM64: $DEDUP_TARGET_IMAGE_FOR_ARM64"

    DEDUP_TARGET_IMAGE=$ECR_REGISTRY/$DEDUP_IMAGE_NAME:$BASE_IMAGE_TAG
    echo "DEDUP_TARGET_IMAGE: $DEDUP_TARGET_IMAGE"

    if ! check_image_pushed "$DEDUP_TARGET_IMAGE"; then
      create_or_update_repository "$DEDUP_IMAGE_NAME" "$BASE_REGISTRY/$DEDUP_IMAGE_NAME"

      docker pull --platform linux/amd64 $BASE_IMAGE
      docker tag $BASE_IMAGE $DEDUP_TARGET_IMAGE_FOR_AMD64
      docker push $DEDUP_TARGET_IMAGE_FOR_AMD64

      docker pull --platform linux/arm64 $BASE_IMAGE
      docker tag $BASE_IMAGE $DEDUP_TARGET_IMAGE_FOR_ARM64
      docker push $DEDUP_TARGET_IMAGE_FOR_ARM64

      docker manifest create $DEDUP_TARGET_IMAGE --amend $DEDUP_TARGET_IMAGE_FOR_AMD64 --amend $DEDUP_TARGET_IMAGE_FOR_ARM64
      docker manifest push $DEDUP_TARGET_IMAGE

      mark_image_pushed "$DEDUP_TARGET_IMAGE"

      docker rmi -f $DEDUP_TARGET_IMAGE_FOR_AMD64 $DEDUP_TARGET_IMAGE_FOR_ARM64 || true
      docker manifest rm $DEDUP_TARGET_IMAGE || true
    else
      echo "Image $DEDUP_TARGET_IMAGE already pushed, skipping"
    fi
  fi

  DANGLING_IMAGES=$(docker images -f "dangling=true" -q)
  if [ -n "$DANGLING_IMAGES" ]; then
    docker rmi -f $DANGLING_IMAGES || true
  fi

  echo "====================================="
  echo "====================================="
done

for BASE_IMAGE in "${AMD64_IMAGES[@]}"; do
  echo "BASE_IMAGE: $BASE_IMAGE"

  BASE_REGISTRY=$(echo $BASE_IMAGE | cut -d'/' -f1)
  BASE_IMAGE_NAME=$(echo $BASE_IMAGE | cut -d'/' -f2- | cut -d':' -f1)
  BASE_IMAGE_TAG=$(echo $BASE_IMAGE | cut -d':' -f2)

  TARGET_IMAGE_FOR_AMD64=$ECR_REGISTRY/$BASE_IMAGE_NAME:$BASE_IMAGE_TAG-amd64
  echo "TARGET_IMAGE_FOR_AMD64: $TARGET_IMAGE_FOR_AMD64"

  TARGET_IMAGE=$ECR_REGISTRY/$BASE_IMAGE_NAME:$BASE_IMAGE_TAG
  echo "TARGET_IMAGE: $TARGET_IMAGE"

  if ! check_image_pushed "$TARGET_IMAGE"; then
    create_or_update_repository "$BASE_IMAGE_NAME" "$BASE_REGISTRY/$BASE_IMAGE_NAME"

    docker pull --platform linux/amd64 $BASE_IMAGE
    docker tag $BASE_IMAGE $TARGET_IMAGE_FOR_AMD64
    docker push $TARGET_IMAGE_FOR_AMD64

    docker manifest create $TARGET_IMAGE --amend $TARGET_IMAGE_FOR_AMD64
    docker manifest push $TARGET_IMAGE

    mark_image_pushed "$TARGET_IMAGE"

    docker rmi -f $BASE_IMAGE $TARGET_IMAGE_FOR_AMD64 || true
    docker manifest rm $TARGET_IMAGE || true
  else
    echo "Image $TARGET_IMAGE already pushed, skipping"
  fi

  echo "====================================="
  echo "====================================="

  LAST_PART=$(echo $BASE_IMAGE_NAME | rev | cut -d'/' -f1 | rev)
  if [[ "$BASE_IMAGE_NAME" == *"$LAST_PART/$LAST_PART"* ]]; then
    DEDUP_IMAGE_NAME=$LAST_PART

    DEDUP_TARGET_IMAGE_FOR_AMD64=$ECR_REGISTRY/$DEDUP_IMAGE_NAME:$BASE_IMAGE_TAG-amd64
    echo "DEDUP_TARGET_IMAGE_FOR_AMD64: $DEDUP_TARGET_IMAGE_FOR_AMD64"

    DEDUP_TARGET_IMAGE=$ECR_REGISTRY/$DEDUP_IMAGE_NAME:$BASE_IMAGE_TAG
    echo "DEDUP_TARGET_IMAGE: $DEDUP_TARGET_IMAGE"

    if ! check_image_pushed "$DEDUP_TARGET_IMAGE"; then
      create_or_update_repository "$DEDUP_IMAGE_NAME" "$BASE_REGISTRY/$DEDUP_IMAGE_NAME"

      docker pull --platform linux/amd64 $BASE_IMAGE
      docker tag $BASE_IMAGE $DEDUP_TARGET_IMAGE_FOR_AMD64
      docker push $DEDUP_TARGET_IMAGE_FOR_AMD64

      docker manifest create $DEDUP_TARGET_IMAGE --amend $DEDUP_TARGET_IMAGE_FOR_AMD64
      docker manifest push $DEDUP_TARGET_IMAGE

      mark_image_pushed "$DEDUP_TARGET_IMAGE"

      docker rmi -f $DEDUP_TARGET_IMAGE_FOR_AMD64 || true
      docker manifest rm $DEDUP_TARGET_IMAGE || true
    else
      echo "Image $DEDUP_TARGET_IMAGE already pushed, skipping"
    fi
  fi

  DANGLING_IMAGES=$(docker images -f "dangling=true" -q)
  if [ -n "$DANGLING_IMAGES" ]; then
    docker rmi -f $DANGLING_IMAGES || true
  fi

  echo "====================================="
  echo "====================================="
done

for BASE_IMAGE in "${ARM64_IMAGES[@]}"; do
  echo "BASE_IMAGE: $BASE_IMAGE"

  BASE_REGISTRY=$(echo $BASE_IMAGE | cut -d'/' -f1)
  BASE_IMAGE_NAME=$(echo $BASE_IMAGE | cut -d'/' -f2- | cut -d':' -f1)
  BASE_IMAGE_TAG=$(echo $BASE_IMAGE | cut -d':' -f2)

  TARGET_IMAGE_FOR_ARM64=$ECR_REGISTRY/$BASE_IMAGE_NAME:$BASE_IMAGE_TAG-arm64
  echo "TARGET_IMAGE_FOR_ARM64: $TARGET_IMAGE_FOR_ARM64"

  TARGET_IMAGE=$ECR_REGISTRY/$BASE_IMAGE_NAME:$BASE_IMAGE_TAG
  echo "TARGET_IMAGE: $TARGET_IMAGE"

  if ! check_image_pushed "$TARGET_IMAGE"; then
    create_or_update_repository "$BASE_IMAGE_NAME" "$BASE_REGISTRY/$BASE_IMAGE_NAME"

    docker pull --platform linux/arm64 $BASE_IMAGE
    docker tag $BASE_IMAGE $TARGET_IMAGE_FOR_ARM64
    docker push $TARGET_IMAGE_FOR_ARM64

    docker manifest create $TARGET_IMAGE --amend $TARGET_IMAGE_FOR_ARM64
    docker manifest push $TARGET_IMAGE

    mark_image_pushed "$TARGET_IMAGE"

    docker rmi -f $BASE_IMAGE $TARGET_IMAGE_FOR_ARM64 || true
    docker manifest rm $TARGET_IMAGE || true
  else
    echo "Image $TARGET_IMAGE already pushed, skipping"
  fi

  echo "====================================="
  echo "====================================="

  LAST_PART=$(echo $BASE_IMAGE_NAME | rev | cut -d'/' -f1 | rev)
  if [[ "$BASE_IMAGE_NAME" == *"$LAST_PART/$LAST_PART"* ]]; then
    DEDUP_IMAGE_NAME=$LAST_PART

    DEDUP_TARGET_IMAGE_FOR_ARM64=$ECR_REGISTRY/$DEDUP_IMAGE_NAME:$BASE_IMAGE_TAG-arm64
    echo "DEDUP_TARGET_IMAGE_FOR_ARM64: $DEDUP_TARGET_IMAGE_FOR_ARM64"

    DEDUP_TARGET_IMAGE=$ECR_REGISTRY/$DEDUP_IMAGE_NAME:$BASE_IMAGE_TAG
    echo "DEDUP_TARGET_IMAGE: $DEDUP_TARGET_IMAGE"

    if ! check_image_pushed "$DEDUP_TARGET_IMAGE"; then
      create_or_update_repository "$DEDUP_IMAGE_NAME" "$BASE_REGISTRY/$DEDUP_IMAGE_NAME"

      docker pull --platform linux/arm64 $BASE_IMAGE
      docker tag $BASE_IMAGE $DEDUP_TARGET_IMAGE_FOR_ARM64
      docker push $DEDUP_TARGET_IMAGE_FOR_ARM64

      docker manifest create $DEDUP_TARGET_IMAGE --amend $DEDUP_TARGET_IMAGE_FOR_ARM64
      docker manifest push $DEDUP_TARGET_IMAGE

      mark_image_pushed "$DEDUP_TARGET_IMAGE"

      docker rmi -f $DEDUP_TARGET_IMAGE_FOR_ARM64 || true
      docker manifest rm $DEDUP_TARGET_IMAGE || true
    else
      echo "Image $DEDUP_TARGET_IMAGE already pushed, skipping"
    fi
  fi

  DANGLING_IMAGES=$(docker images -f "dangling=true" -q)
  if [ -n "$DANGLING_IMAGES" ]; then
    docker rmi -f $DANGLING_IMAGES || true
  fi

  echo "====================================="
  echo "====================================="
done
