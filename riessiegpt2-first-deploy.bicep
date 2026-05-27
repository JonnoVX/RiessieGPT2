@description('Existing ACA managed environment name')
param existingManagedEnvironmentName string = 'vscode-dev-dff093-aca-env'

@description('Existing storage account used for the Azure Files share')
param existingStorageAccountName string = 'sty5kfkze4x3zdw'

@description('Existing Azure Files share to persist Open WebUI data')
param existingFileShareName string = 'classic-fileshare-riessiegpt2'

@description('New ACA environment storage-link name')
param environmentStorageLinkName string = 'riessiegpt2-data'

@description('New Container App name')
param openWebUiContainerAppName string = 'capps-riessiegpt2-webui'

@description('Pinned Open WebUI image. Replace with your own fork image later if you have one published.')
param openWebUiImage string = 'ghcr.io/open-webui/open-webui:v0.9.5'

@description('Expose the app publicly')
param openWebUiExternal bool = true

@description('Admin email created on first startup')
param openWebUiAdminEmail string

@secure()
@description('Admin password created on first startup')
param openWebUiAdminPassword string

@secure()
@description('Open WebUI secret key used for session signing/encryption')
param openWebUiSecretKey string

resource managedEnvironment 'Microsoft.App/managedEnvironments@2026-01-01' existing = {
  name: existingManagedEnvironmentName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-08-01' existing = {
  name: existingStorageAccountName
}

resource acaEnvironmentStorage 'Microsoft.App/managedEnvironments/storages@2026-01-01' = {
  parent: managedEnvironment
  name: environmentStorageLinkName
  properties: {
    azureFile: {
      accessMode: 'ReadWrite'
      accountName: storageAccount.name
      accountKey: listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value
      shareName: existingFileShareName
    }
  }
}

resource openWebUiApp 'Microsoft.App/containerApps@2026-01-01' = {
  name: openWebUiContainerAppName
  location: managedEnvironment.location
  dependsOn: [
    acaEnvironmentStorage
  ]
  properties: {
    managedEnvironmentId: managedEnvironment.id
    environmentId: managedEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: openWebUiExternal
        allowInsecure: false
        targetPort: 8080
        transport: 'Auto'
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      secrets: [
        {
          name: 'webui-secret-key'
          value: openWebUiSecretKey
        }
        {
          name: 'webui-admin-password'
          value: openWebUiAdminPassword
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'open-webui'
          image: openWebUiImage
          env: [
            {
              name: 'WEBUI_SECRET_KEY'
              secretRef: 'webui-secret-key'
            }
            {
              name: 'WEBUI_ADMIN_EMAIL'
              value: openWebUiAdminEmail
            }
            {
              name: 'WEBUI_ADMIN_PASSWORD'
              secretRef: 'webui-admin-password'
            }
            {
              name: 'ENABLE_SIGNUP'
              value: 'false'
            }
          ]
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 10
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 30
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 30
              periodSeconds: 30
              timeoutSeconds: 5
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 15
              periodSeconds: 15
              timeoutSeconds: 5
              failureThreshold: 3
            }
          ]
          resources: {
            cpu: 1
            memory: '2Gi'
          }
          volumeMounts: [
            {
              volumeName: 'webui-data'
              mountPath: '/app/backend/data'
            }
          ]
        }
      ]
      volumes: [
        {
          name: 'webui-data'
          storageType: 'AzureFile'
          storageName: acaEnvironmentStorage.name
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

output openWebUiFqdn string = openWebUiApp.properties.configuration.ingress.fqdn
output openWebUiUrl string = 'https://${openWebUiApp.properties.configuration.ingress.fqdn}'