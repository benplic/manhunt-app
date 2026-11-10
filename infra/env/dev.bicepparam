using '../main.bicep'

param envName = 'dev'
param postgresAdminLogin = 'manhunt'
param postgresAdminPassword = 'replace-in-pipeline'
param containerImage = 'ghcr.io/example/manhunt-server:dev'
param minReplicas = 0
param maxReplicas = 1
param sessionSigningKey = 'replace-in-pipeline'
param qrSigningKey = 'replace-in-pipeline'
param trailKey = 'replace-in-pipeline'
param apnsKeyId = ''
param apnsTeamId = ''
