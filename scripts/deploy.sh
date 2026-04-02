#!/usr/bin/env bash
set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-memory-pressure-lab}"
LOCATION="${LOCATION:-koreacentral}"
NAME_PREFIX="${NAME_PREFIX:-memlabapp}"
PLAN_SKU="${PLAN_SKU:-B1}"
APP_COUNT="${APP_COUNT:-2}"
ALLOC_MB="${ALLOC_MB:-100}"
CONTAINER_IMAGE="${CONTAINER_IMAGE:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/../infra"
APP_DIR="${SCRIPT_DIR}/../app-flask"

echo "=== Memory Pressure Lab - Deploy ==="
echo "  Resource Group : ${RESOURCE_GROUP}"
echo "  Location       : ${LOCATION}"
echo "  Name Prefix    : ${NAME_PREFIX}"
echo "  Plan SKU       : ${PLAN_SKU}"
echo "  App Count      : ${APP_COUNT}"
echo "  Alloc MB/App   : ${ALLOC_MB}"
echo ""

az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --output none

echo "[1/3] Deploying infrastructure (Bicep)..."
DEPLOY_OUTPUT=$(az deployment group create \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${INFRA_DIR}/main.bicep" \
  --parameters \
      namePrefix="${NAME_PREFIX}" \
      planSku="${PLAN_SKU}" \
      appCount="${APP_COUNT}" \
      allocMbPerApp="${ALLOC_MB}" \
      containerImage="${CONTAINER_IMAGE}" \
  --output json)

APP_NAMES=$(echo "${DEPLOY_OUTPUT}" | jq -r '.properties.outputs.appNames.value[]')
APP_HOSTNAMES=$(echo "${DEPLOY_OUTPUT}" | jq -r '.properties.outputs.appHostnames.value[]')

if [[ -n "${CONTAINER_IMAGE}" ]]; then
  echo "[2/3] Container mode: skipping ZIP deploy (apps pull image from ACR)"
else
  echo "[2/3] Deploying application code via ZIP deploy..."

  cd "${APP_DIR}"
  zip -q app.zip app.py requirements.txt

  for APP_NAME in ${APP_NAMES}; do
    echo "  Deploying to ${APP_NAME}..."
    az webapp deploy \
      --resource-group "${RESOURCE_GROUP}" \
      --name "${APP_NAME}" \
      --src-path app.zip \
      --type zip \
      --output none
  done

  rm -f app.zip
  cd - > /dev/null
fi

echo "[3/3] Deployment complete."
echo ""
echo "App endpoints:"
for HOSTNAME in ${APP_HOSTNAMES}; do
  echo "  https://${HOSTNAME}/health"
done

echo ""
echo "To generate traffic:"
echo "  python3 scripts/traffic-gen.py --rg ${RESOURCE_GROUP} --prefix ${NAME_PREFIX} --count ${APP_COUNT}"
echo ""
echo "To monitor metrics:"
echo "  python3 scripts/monitor.py --rg ${RESOURCE_GROUP} --prefix ${NAME_PREFIX} --count ${APP_COUNT}"
