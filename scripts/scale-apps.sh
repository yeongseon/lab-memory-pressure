#!/usr/bin/env bash
set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-memory-pressure-lab}"
NAME_PREFIX="${NAME_PREFIX:-memlabapp}"
NEW_COUNT="${1:?Usage: $0 <new_app_count> [alloc_mb]}"
ALLOC_MB="${2:-100}"
PLAN_SKU="${PLAN_SKU:-B1}"
CONTAINER_IMAGE="${CONTAINER_IMAGE:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/../infra"
APP_DIR="${SCRIPT_DIR}/../app-flask"

echo "=== Scaling to ${NEW_COUNT} apps (${ALLOC_MB} MB each) ==="

DEPLOY_OUTPUT=$(az deployment group create \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${INFRA_DIR}/main.bicep" \
  --parameters \
      namePrefix="${NAME_PREFIX}" \
      planSku="${PLAN_SKU}" \
      appCount="${NEW_COUNT}" \
      allocMbPerApp="${ALLOC_MB}" \
      containerImage="${CONTAINER_IMAGE}" \
  --output json)

APP_NAMES=$(echo "${DEPLOY_OUTPUT}" | jq -r '.properties.outputs.appNames.value[]')

if [[ -n "${CONTAINER_IMAGE}" ]]; then
  echo "Container mode: skipping ZIP deploy (apps pull image from ACR)"
else
  cd "${APP_DIR}"
  zip -q app.zip app.py requirements.txt

  for APP_NAME in ${APP_NAMES}; do
    echo "  Re-deploying code to ${APP_NAME}..."
    az webapp deployment source config-zip \
      --resource-group "${RESOURCE_GROUP}" \
      --name "${APP_NAME}" \
      --src app.zip \
      --output none 2>/dev/null || {
        echo "  WARN: config-zip failed for ${APP_NAME}, trying az webapp deploy..."
        az webapp deploy \
          --resource-group "${RESOURCE_GROUP}" \
          --name "${APP_NAME}" \
          --src-path app.zip \
          --type zip \
          --output none
      }
  done

  rm -f app.zip
  cd - > /dev/null
fi

echo "Done. ${NEW_COUNT} apps running with ALLOC_MB=${ALLOC_MB}."
