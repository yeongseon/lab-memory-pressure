#!/usr/bin/env bash
set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-memory-pressure-lab}"
LOCATION="${LOCATION:-koreacentral}"
NAME_PREFIX="${NAME_PREFIX:-memlabapp}"
PLAN_SKU="${PLAN_SKU:-B1}"
APP_COUNT="${APP_COUNT:-2}"
ALLOC_MB="${ALLOC_MB:-100}"
ACR_NAME="${ACR_NAME:-${NAME_PREFIX}acr}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/../infra"
APP_NODE_DIR="${SCRIPT_DIR}/../app-node"
IMAGE_NAME="memlab-node"
FULL_IMAGE="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"

echo "=== Memory Pressure Lab - Container Deploy ==="
echo "  Resource Group : ${RESOURCE_GROUP}"
echo "  Location       : ${LOCATION}"
echo "  Name Prefix    : ${NAME_PREFIX}"
echo "  Plan SKU       : ${PLAN_SKU}"
echo "  App Count      : ${APP_COUNT}"
echo "  Alloc MB/App   : ${ALLOC_MB}"
echo "  ACR Name       : ${ACR_NAME}"
echo "  Image Name     : ${IMAGE_NAME}"
echo "  Image Tag      : ${IMAGE_TAG}"
echo "  Full Image     : ${FULL_IMAGE}"
echo ""

echo "[1/8] Creating resource group..."
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --output none

echo "[2/8] Deploying infrastructure (Bicep) for container mode..."
DEPLOY_OUTPUT=$(az deployment group create \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${INFRA_DIR}/main.bicep" \
  --parameters \
      namePrefix="${NAME_PREFIX}" \
      planSku="${PLAN_SKU}" \
      appCount="${APP_COUNT}" \
      allocMbPerApp="${ALLOC_MB}" \
      deployAcr=true \
      containerImage="${FULL_IMAGE}" \
  --output json)

APP_HOSTNAMES=$(echo "${DEPLOY_OUTPUT}" | jq -r '.properties.outputs.appHostnames.value[]')

echo "[3/8] Logging in to Azure Container Registry..."
az acr login --name "${ACR_NAME}"

echo "[4/8] Building Docker image..."
docker build -t "${FULL_IMAGE}" "${APP_NODE_DIR}"

echo "[5/8] Pushing Docker image to ACR..."
docker push "${FULL_IMAGE}"

echo "[6/8] Restarting web apps so they pull the new image..."
for i in $(seq 1 "${APP_COUNT}"); do
  APP_NAME="${NAME_PREFIX}-${i}"
  echo "  Restarting ${APP_NAME}..."
  az webapp restart \
    --name "${APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --output none
done

echo "[7/8] Deployment complete."
echo ""
echo "App endpoints:"
for HOSTNAME in ${APP_HOSTNAMES}; do
  echo "  https://${HOSTNAME}/health"
done

echo ""
echo "[8/8] Next steps"
echo "To generate traffic:"
echo "  python3 scripts/traffic-gen.py --rg ${RESOURCE_GROUP} --prefix ${NAME_PREFIX} --count ${APP_COUNT}"
echo ""
echo "To monitor metrics:"
echo "  python3 scripts/monitor.py --rg ${RESOURCE_GROUP} --prefix ${NAME_PREFIX} --count ${APP_COUNT}"
