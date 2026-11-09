using '../main.bicep'

param envName = 'prod'
param postgresAdminLogin = 'manhunt'
param postgresAdminPassword = 'replace-in-pipeline'
param containerImage = 'ghcr.io/example/manhunt-server:prod'
param minReplicas = 0
param maxReplicas = 1
