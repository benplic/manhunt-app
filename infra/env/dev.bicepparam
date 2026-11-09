using '../main.bicep'

param envName = 'dev'
param postgresAdminLogin = 'manhunt'
param postgresAdminPassword = 'replace-in-pipeline'
param containerImage = 'ghcr.io/example/manhunt-server:dev'
param minReplicas = 0
param maxReplicas = 1
