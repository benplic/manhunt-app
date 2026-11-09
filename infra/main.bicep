// Azure Container Apps consumption, minReplicas 0, Postgres Flexible B1ms always on.
// Images come from GHCR. Secrets land in Key Vault and are referenced, never copied.

targetScope = 'resourceGroup'

param location string = resourceGroup().location
param envName string
param postgresAdminLogin string
@secure()
param postgresAdminPassword string
param containerImage string
param minReplicas int = 0
param maxReplicas int = 1

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-manhunt-${envName}'
  location: location
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
  }
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: 'psql-manhunt-${envName}'
  location: location
  sku: { name: 'Standard_B1ms', tier: 'Burstable' }
  properties: {
    version: '16'
    administratorLogin: postgresAdminLogin
    administratorLoginPassword: postgresAdminPassword
    storage: { storageSizeGB: 32 }
    backup: { backupRetentionDays: 7 }
  }
}

resource log 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-manhunt-${envName}'
  location: location
  properties: { sku: { name: 'PerGB2018' }, retentionInDays: 30, workspaceCapping: { dailyQuotaGb: 1 } }
}

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-manhunt-${envName}'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: log.properties.customerId
        sharedKey: log.listKeys().primarySharedKey
      }
    }
  }
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-manhunt-${envName}'
  location: location
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      ingress: { external: true, targetPort: 8000, transport: 'http' }
      secrets: [
        { name: 'db-url', keyVaultUrl: '${kv.properties.vaultUri}secrets/database-url', identity: 'system' }
        { name: 'session-key', keyVaultUrl: '${kv.properties.vaultUri}secrets/session-signing-key', identity: 'system' }
        { name: 'qr-key', keyVaultUrl: '${kv.properties.vaultUri}secrets/qr-signing-key', identity: 'system' }
        { name: 'trail-key', keyVaultUrl: '${kv.properties.vaultUri}secrets/trail-key', identity: 'system' }
      ]
    }
    template: {
      containers: [
        {
          name: 'server'
          image: containerImage
          resources: { cpu: json('0.5'), memory: '1Gi' }
          env: [
            { name: 'MANHUNT_ENV', value: 'azure' }
            { name: 'MANHUNT_DEV_AUTH', value: 'false' }
            { name: 'MANHUNT_TICK_LOOP', value: 'true' }
            { name: 'MANHUNT_DATABASE_URL', secretRef: 'db-url' }
            { name: 'MANHUNT_SESSION_SIGNING_KEY', secretRef: 'session-key' }
            { name: 'MANHUNT_QR_SIGNING_KEY', secretRef: 'qr-key' }
            { name: 'MANHUNT_TRAIL_KEY', secretRef: 'trail-key' }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        cooldownPeriod: 300
        rules: [
          {
            name: 'http'
            http: { metadata: { concurrentRequests: '10' } }
          }
        ]
      }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
output keyVaultName string = kv.name
output postgresName string = postgres.name
