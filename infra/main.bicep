targetScope = 'resourceGroup'

@description('Azure region. Defaults to resource group location.')
param location string = resourceGroup().location

@description('Prefix for all resource names. Must be lowercase letters and numbers only.')
@maxLength(12)
param namePrefix string = 'memlabapp'

@description('App Service Plan SKU. B1=1vCPU/1.75GB, B2=2vCPU/3.5GB.')
@allowed(['B1', 'B2'])
param planSku string = 'B1'

@description('Number of Web Apps to deploy on the same plan.')
@minValue(1)
@maxValue(10)
param appCount int = 2

@description('Memory to hold per app (MB). Adjust per experiment step.')
@minValue(10)
@maxValue(500)
param allocMbPerApp int = 100

@description('Docker container image (e.g. myregistry.azurecr.io/memlab:latest). Leave empty for direct Python zip deploy.')
param containerImage string = ''

@description('Deploy Azure Container Registry (ACR).')
param deployAcr bool = false

@description('ACR name. Must be globally unique and contain only alphanumeric characters.')
param acrName string = '${namePrefix}acr'

var planName = '${namePrefix}-plan'
var containerRegistryLoginServer = !empty(containerImage)
  ? (deployAcr ? acr.outputs.acrLoginServer : split(containerImage, '/')[0])
  : ''

module plan 'modules/appservice-plan.bicep' = {
  name: 'deploy-plan'
  params: {
    planName: planName
    location: location
    planSku: planSku
  }
}

module acr 'modules/acr.bicep' = if (deployAcr) {
  name: 'deploy-acr'
  params: {
    acrName: acrName
    location: location
  }
}

module webApps 'modules/webapp.bicep' = [for i in range(0, appCount): {
  name: 'deploy-webapp-${i + 1}'
  params: {
    appName: '${namePrefix}-${i + 1}'
    location: location
    planId: plan.outputs.planId
    allocMb: allocMbPerApp
    containerImage: containerImage
    acrLoginServer: containerRegistryLoginServer
    acrName: !empty(containerImage) ? acrName : ''
    acrResourceGroupName: resourceGroup().name
  }
}]

output planName string = plan.outputs.planName
output appHostnames array = [for i in range(0, appCount): webApps[i].outputs.defaultHostname]
output appNames array = [for i in range(0, appCount): webApps[i].outputs.appName]
output acrLoginServer string = deployAcr ? acr.outputs.acrLoginServer : ''
