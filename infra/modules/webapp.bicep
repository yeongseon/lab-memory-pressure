@description('Web App name. Must be globally unique.')
param appName string

@description('Azure region')
param location string

@description('App Service Plan resource ID')
param planId string

@description('Memory to allocate on startup (MB)')
param allocMb int = 100

@description('ACR image reference. Leave empty to use direct Python deployment.')
param containerImage string = ''

@description('ACR login server (e.g. myregistry.azurecr.io).')
param acrLoginServer string = ''

@description('ACR name for resolving admin credentials.')
param acrName string = ''

@description('Resource group name containing ACR.')
param acrResourceGroupName string = resourceGroup().name

output defaultHostname string = webApp.properties.defaultHostName
output appName string = webApp.name

var useContainer = !empty(containerImage)
var useAcrCredentials = useContainer && !empty(acrName)

var linuxFxVersionValue = useContainer
  ? 'DOCKER|${containerImage}'
  : 'PYTHON|3.12'

var startupCommandValue = useContainer
  ? ''
  : 'gunicorn --bind=0.0.0.0:8000 --workers=1 --timeout=120 app:app'

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = if (useAcrCredentials) {
  name: acrName
  scope: resourceGroup(acrResourceGroupName)
}

var dockerRegistryServerUrl = !empty(acrLoginServer) ? 'https://${acrLoginServer}' : ''
var dockerRegistryUsername = useAcrCredentials ? acr!.listCredentials().username : ''
var dockerRegistryPassword = useAcrCredentials ? acr!.listCredentials().passwords[0].value : ''

var baseAppSettings = [
  {
    name: 'ALLOC_MB'
    value: string(allocMb)
  }
  {
    name: 'APP_NAME'
    value: appName
  }
  {
    name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
    value: 'false'
  }
  {
    name: 'ENABLE_ORYX_BUILD'
    value: 'false'
  }
]

var containerAppSettings = useContainer
  ? [
      {
        name: 'DOCKER_REGISTRY_SERVER_URL'
        value: dockerRegistryServerUrl
      }
      {
        name: 'DOCKER_REGISTRY_SERVER_USERNAME'
        value: dockerRegistryUsername
      }
      {
        name: 'DOCKER_REGISTRY_SERVER_PASSWORD'
        value: dockerRegistryPassword
      }
    ]
  : []

resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: appName
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: planId
    reserved: true
    siteConfig: {
      linuxFxVersion: linuxFxVersionValue
      alwaysOn: true
      appCommandLine: startupCommandValue
      appSettings: concat(baseAppSettings, containerAppSettings)
      healthCheckPath: '/health'
    }
    httpsOnly: true
  }
}
