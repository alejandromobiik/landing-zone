#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Enciende AKS y espera hasta que el cluster y los nodos estén listos.

.DESCRIPTION
  No crea recursos Terraform ni toca bootstrap/tfstate.
  Tras purgar ACR con cost-down-off, vuelve a ejecutar app\scripts\deploy-phase8.ps1 para la app.

.PARAMETER WhatIf
  Solo muestra qué haría (no llama az aks start).

.PARAMETER SubscriptionId
  Suscripción Azure.

.PARAMETER ResourceGroupAks
  RG del cluster (default rg-spoke-app-lz-dev).

.PARAMETER AksName
  Nombre del cluster (default aks-lz-dev).

.PARAMETER PollIntervalSeconds
  Segundos entre comprobaciones de estado (default 20).

.PARAMETER MaxWaitMinutes
  Tiempo máximo de espera para Running/Succeeded y nodos Ready (default 35).

.PARAMETER OpenKeyVaultPublicFirst
  Tras fijar suscripción, habilita publicNetworkAccess en Key Vault (laboratorio). Este script no vuelve a cerrar el vault.

.PARAMETER KeyVaultName
  Vault a abrir con -OpenKeyVaultPublicFirst (por defecto kv-lz-dev-66635).
#>
param(
    [switch]$WhatIf,
    [string]$SubscriptionId = "1989a8c1-76c1-4555-a228-c95f86c66635",
    [string]$ResourceGroupAks = "rg-spoke-app-lz-dev",
    [string]$AksName = "aks-lz-dev",
    [int]$PollIntervalSeconds = 20,
    [int]$MaxWaitMinutes = 35,
    [switch]$OpenKeyVaultPublicFirst,
    [string]$KeyVaultName = "kv-lz-dev-66635"
)

$ErrorActionPreference = "Stop"

if ($SubscriptionId -and -not $WhatIf) {
    az account set --subscription $SubscriptionId
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "az account set falló (código $LASTEXITCODE). Revisa cadena de certificados local o SSL: https://learn.microsoft.com/cli/azure/use-cli-effectively#work-behind-a-proxy"
    }
}

if ($OpenKeyVaultPublicFirst -and -not $WhatIf) {
    Write-Host "Key Vault $KeyVaultName : habilitar acceso público (se mantiene abierto; no lo cierra este script)"
    az keyvault update --name $KeyVaultName --public-network-access Enabled
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "az keyvault update falló (código $LASTEXITCODE)."
    }
}

function Get-AksState {
    $json = az aks show --resource-group $ResourceGroupAks --name $AksName --query "{power:powerState.code,prov:provisioningState}" -o json 2>$null
    if (-not $json) { return $null }
    return $json | ConvertFrom-Json
}

if ($WhatIf) {
    Write-Host "[WhatIf] az account set -s $SubscriptionId"
    if ($OpenKeyVaultPublicFirst) {
        Write-Host "[WhatIf] az keyvault update --name $KeyVaultName --public-network-access Enabled (se mantiene abierto)"
    }
    Write-Host "[WhatIf] az aks start -g $ResourceGroupAks -n $AksName"
    Write-Host "[WhatIf] Bucle de espera hasta power=Running, prov=Succeeded y nodos Ready."
    exit 0
}

$state0 = Get-AksState
if ($state0.power -eq "Running" -and $state0.prov -eq "Succeeded") {
    Write-Host "AKS ya está Running/Succeeded; se omite az aks start."
}
else {
    Write-Host "Iniciando AKS $AksName..."
    az aks start --resource-group $ResourceGroupAks --name $AksName
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "az aks start falló (código $LASTEXITCODE). Revisa SSL o estado del cluster."
    }
}

$deadline = (Get-Date).AddMinutes($MaxWaitMinutes)
Write-Host "Esperando estado operativo (máx $MaxWaitMinutes min, intervalo ${PollIntervalSeconds}s)..."

while ((Get-Date) -lt $deadline) {
    $s = Get-AksState
    if (-not $s) {
        Write-Warning "No se pudo leer estado del cluster; reintento..."
        Start-Sleep -Seconds $PollIntervalSeconds
        continue
    }
    Write-Host "$(Get-Date -Format o) power=$($s.power) prov=$($s.prov)"
    if ($s.power -eq "Running" -and $s.prov -eq "Succeeded") {
        break
    }
    Start-Sleep -Seconds $PollIntervalSeconds
}

$sFinal = Get-AksState
if (-not ($sFinal.power -eq "Running" -and $sFinal.prov -eq "Succeeded")) {
    Write-Error "Timeout: el cluster no alcanzó Running/Succeeded. Revisa el portal o az aks show."
}

Write-Host "Esperando nodos Ready (kubectl wait)..."
$waitCmd = "kubectl wait --for=condition=Ready nodes --all --timeout=600s"
az aks command invoke `
    --resource-group $ResourceGroupAks `
    --name $AksName `
    --command $waitCmd
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "kubectl wait en AKS falló (código $LASTEXITCODE)."
}

Write-Host "Estado de nodos:"
az aks command invoke `
    --resource-group $ResourceGroupAks `
    --name $AksName `
    --command "kubectl get nodes -o wide"
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "kubectl get nodes falló (código $LASTEXITCODE)."
}

Write-Host ""
Write-Host "=== Listo ==="
Write-Host "Si purgaste imágenes ACR, redeploy: cd app; pwsh -File scripts\deploy-phase8.ps1"
