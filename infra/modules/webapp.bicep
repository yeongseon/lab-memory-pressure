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

output defaultHostname string = webApp.properties.defaultHostName
output appName string = webApp.name

var useContainer = !empty(containerImage)

var linuxFxVersionValue = useContainer
  ? 'DOCKER|${containerImage}'
  : 'PYTHON|3.12'

var startupCommandValue = useContainer
  ? ''
  : 'gunicorn --bind=0.0.0.0:8000 --workers=1 --timeout=120 app:app'

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
      appSettings: [
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
      healthCheckPath: '/health'
    }
    httpsOnly: true
  }
}


