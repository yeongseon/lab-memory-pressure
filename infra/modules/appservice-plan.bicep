@description('App Service Plan name')
param planName string = 'asp-memory-pressure-lab'

@description('Azure region')
param location string = resourceGroup().location

@allowed(['B1', 'B2', 'B3'])
@description('SKU. B1 for initial lab, B2 if B1 is too tight.')
param planSku string = 'B1'

output planId string = appServicePlan.id
output planName string = appServicePlan.name

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: planName
  location: location
  kind: 'linux'
  sku: {
    name: planSku
    tier: 'Basic'
    size: planSku
    capacity: 1
  }
  properties: {
    reserved: true
  }
}
