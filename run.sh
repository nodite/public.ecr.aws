#!/bin/bash

set -e

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载镜像配置
source "$SCRIPT_DIR/images.conf"

ECR_REGISTRY=public.ecr.aws/oscaner

# 动态生成镜像列表

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

  create_or_update_repository "$BASE_IMAGE_NAME" "$BASE_REGISTRY/$BASE_IMAGE_NAME"

  docker pull --platform linux/amd64 $BASE_IMAGE
  docker tag $BASE_IMAGE $TARGET_IMAGE_FOR_AMD64
  docker push $TARGET_IMAGE_FOR_AMD64

  docker pull --platform linux/arm64 $BASE_IMAGE
  docker tag $BASE_IMAGE $TARGET_IMAGE_FOR_ARM64
  docker push $TARGET_IMAGE_FOR_ARM64

  docker manifest create $TARGET_IMAGE --amend $TARGET_IMAGE_FOR_AMD64 --amend $TARGET_IMAGE_FOR_ARM64
  docker manifest push $TARGET_IMAGE

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

  create_or_update_repository "$BASE_IMAGE_NAME" "$BASE_REGISTRY/$BASE_IMAGE_NAME"

  docker pull --platform linux/amd64 $BASE_IMAGE
  docker tag $BASE_IMAGE $TARGET_IMAGE_FOR_AMD64
  docker push $TARGET_IMAGE_FOR_AMD64

  docker manifest create $TARGET_IMAGE --amend $TARGET_IMAGE_FOR_AMD64
  docker manifest push $TARGET_IMAGE

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

  create_or_update_repository "$BASE_IMAGE_NAME" "$BASE_REGISTRY/$BASE_IMAGE_NAME"

  docker pull --platform linux/arm64 $BASE_IMAGE
  docker tag $BASE_IMAGE $TARGET_IMAGE_FOR_ARM64
  docker push $TARGET_IMAGE_FOR_ARM64

  docker manifest create $TARGET_IMAGE --amend $TARGET_IMAGE_FOR_ARM64
  docker manifest push $TARGET_IMAGE

  echo "====================================="
  echo "====================================="
done
