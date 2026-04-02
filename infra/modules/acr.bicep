@description('Azure Container Registry name. Must be globally unique and alphanumeric only.')
param acrName string

@description('Azure region')
param location string = resourceGroup().location

@description('ACR SKU. Basic is sufficient for this lab.')
param sku string = 'Basic'

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: true
  }
}

output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output acrId string = acr.id
