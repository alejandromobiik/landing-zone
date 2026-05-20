#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Reduce costos operativos: limpia la app Fase 8 en AKS, para el cluster y opcionalmente purga repos ACR.

.DESCRIPTION
  NO toca el Storage Account del tfstate (stlztf*, contenedor tfstate) ni rg-platform/bootstrap.
  NO desactiva Defender ni borra Log Analytics Workspace (usar Terraform o Portal para eso).

.PARAMETER WhatIf
  Solo muestra las acciones que ejecutaría.

.PARAMETER SubscriptionId
  Suscripción Azure (por defecto la del proyecto).

.PARAMETER ResourceGroupAks
  RG del cluster (default rg-spoke-app-lz-dev).

.PARAMETER AksName
  Nombre del cluster (default aks-lz-dev).

.PARAMETER AcrName
  Nombre del ACR (default acrlzdev66635).

.PARAMETER SkipK8sCleanup
  No ejecuta kubectl delete (útil si el cluster ya está parado).

.PARAMETER SkipAcrPurge
  No borra repositorios en ACR.

.PARAMETER AcrRepositoriesToDelete
  Lista de nombres de repositorio ACR a eliminar (por defecto solo lz-app).

.PARAMETER ConfirmAcrPurge
  Obligatorio junto con no-WhatIf para ejecutar borrado en ACR (doble confirmación).

.PARAMETER OpenKeyVaultPublicFirst
  Si se indica, lo primero (tras fijar suscripción) habilita publicNetworkAccess en Key Vault (laboratorio). El script no vuelve a cerrar el vault: queda abierto hasta que lo cambies tú o Terraform.

.PARAMETER KeyVaultName
  Vault a abrir con -OpenKeyVaultPublicFirst (por defecto kv-lz-dev-66635).
#>
param(
    [switch]$WhatIf,
    [string]$SubscriptionId = "1989a8c1-76c1-4555-a228-c95f86c66635",
    [string]$ResourceGroupAks = "rg-spoke-app-lz-dev",
    [string]$AksName = "aks-lz-dev",
    [string]$AcrName = "acrlzdev66635",
    [switch]$SkipK8sCleanup,
    [switch]$SkipAcrPurge,
    [string[]]$AcrRepositoriesToDelete = @("lz-app"),
    [switch]$ConfirmAcrPurge,
    [switch]$OpenKeyVaultPublicFirst,
    [string]$KeyVaultName = "kv-lz-dev-66635"
)

$ErrorActionPreference = "Stop"

function Invoke-Step {
    param([string]$Message, [scriptblock]$Action)
    if ($WhatIf) {
        Write-Host "[WhatIf] $Message"
        return
    }
    Write-Host $Message
    & $Action
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "Falló: $Message (código de salida $LASTEXITCODE). Si aparece SSLCertVerificationError, revisa cadena de certificados local, antivirus (inspección HTTPS) o documentación de red: https://learn.microsoft.com/cli/azure/use-cli-effectively#work-behind-a-proxy"
    }
}

# --- Bloqueo explícito: nunca tocar tfstate por nombre conocido ---
$protectedStoragePrefix = "stlztf"
Write-Host "Política: no se modifica Storage Account '$protectedStoragePrefix*' ni contenedor tfstate."

if ($SubscriptionId) {
    # No usar pipeline a Out-Null: oculta el código de salida real de az.
    Invoke-Step "Seleccionar suscripción $SubscriptionId" { az account set --subscription $SubscriptionId }
}

$currentSub = az account show --query id -o tsv 2>$null
if ($currentSub -and $SubscriptionId -and ($currentSub -ne $SubscriptionId)) {
    Write-Warning "Suscripción activa ($currentSub) no coincide con -SubscriptionId ($SubscriptionId)."
}

# --- 0) Red de laboratorio: Key Vault accesible sin PE (opcional; no se revierte aquí) ---
if ($OpenKeyVaultPublicFirst) {
    Invoke-Step "Key Vault $KeyVaultName : habilitar acceso público (se mantiene abierto; no lo cierra este script)" {
        az keyvault update --name $KeyVaultName --public-network-access Enabled
    }
}

# --- 1) Limpieza Kubernetes (solo si el cluster está Running) ---
if (-not $SkipK8sCleanup) {
    $power = az aks show --resource-group $ResourceGroupAks --name $AksName --query "powerState.code" -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($power)) {
        Write-Warning "No se pudo leer powerState de AKS (salida vacía). Suele ser TLS/certificados locales, recurso inexistente o falta de sesión `az`. Prueba: az aks show -g $ResourceGroupAks -n $AksName"
    }
    if ($power -eq "Running") {
        $k8sCmd = "kubectl delete deployment lz-app -n default --ignore-not-found; kubectl delete service lz-app -n default --ignore-not-found; kubectl delete serviceaccount lz-app-sa -n default --ignore-not-found"
        Invoke-Step "Limpieza Fase 8 en AKS (deployment/service/sa lz-app*)" {
            az aks command invoke `
                --resource-group $ResourceGroupAks `
                --name $AksName `
                --command $k8sCmd
        }
    }
    else {
        Write-Host "AKS no está Running (estado: '$power'). Se omite kubectl cleanup."
    }
}
else {
    Write-Host "SkipK8sCleanup: no se ejecuta limpieza en el cluster."
}

# --- 2) Parar AKS ---
$powerStop = az aks show --resource-group $ResourceGroupAks --name $AksName --query "powerState.code" -o tsv 2>$null
if ([string]::IsNullOrWhiteSpace($powerStop)) {
    Write-Warning "No se pudo leer powerState antes de parar AKS (salida vacía). Si el siguiente comando falla, revisa TLS/certificados o sesión `az`."
}
if ($powerStop -eq "Stopped") {
    Write-Host "AKS ya está Stopped; no se llama az aks stop."
}
else {
    Invoke-Step "Parar cluster AKS $AksName" {
        az aks stop --resource-group $ResourceGroupAks --name $AksName
    }
}

# --- 3) Purga opcional ACR ---
if (-not $SkipAcrPurge) {
    if ($WhatIf) {
        foreach ($repo in $AcrRepositoriesToDelete) {
            Write-Host "[WhatIf] Eliminaría repositorio ACR '$repo' en $AcrName (requiere -ConfirmAcrPurge en ejecución real)."
        }
    }
    else {
        if (-not $ConfirmAcrPurge) {
            Write-Host "ACR: no se borró nada. Para purgar repos, vuelve a ejecutar con -ConfirmAcrPurge."
        }
        else {
            foreach ($repo in $AcrRepositoriesToDelete) {
                if ([string]::IsNullOrWhiteSpace($repo)) { continue }
                Invoke-Step "Eliminando repositorio ACR: $repo" {
                    az acr repository delete --name $AcrName --repository $repo --yes
                }
            }
        }
    }
}
else {
    Write-Host "SkipAcrPurge: no se modifica ACR."
}

Write-Host ""
Write-Host "=== Resumen ==="
Write-Host "- AKS debería estar Stopped (compute de nodos detenido). Pueden quedar costos de disco/MC_, ACR base, LAW, Defender."
Write-Host "- Para volver a encender: scripts\cost-down-on.ps1"
Write-Host "- Si purgaste ACR, redeploy Fase 8: app\scripts\deploy-phase8.ps1"
