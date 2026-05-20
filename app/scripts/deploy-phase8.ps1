#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Construye la imagen lz-app, la sube a ACR y aplica manifiestos en AKS (cluster privado).

.PARAMETER WorkloadClientId
  Client ID (appId) de la User-Assigned MI del workload. Si se omite, se intenta leer con
  terraform output -raw workload_app_identity_client_id desde infra/terraform.

.PARAMETER SkipPush
  Solo genera .generated/all.yaml (sin docker build, sin login ACR, sin push ni apply).

.PARAMETER SkipDeploy
  Build + push pero no kubectl apply.
#>
param(
    [string]$WorkloadClientId = "",
    [switch]$SkipPush,
    [switch]$SkipDeploy
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$K8sDir = Join-Path $Root "k8s"
$GeneratedDir = Join-Path $Root ".generated"
New-Item -ItemType Directory -Force -Path $GeneratedDir | Out-Null

if (-not $WorkloadClientId) {
    $TfDir = Join-Path $Root ".." "infra" "terraform"
    Push-Location $TfDir
    try {
        $WorkloadClientId = terraform output -raw workload_app_identity_client_id 2>$null
    }
    finally {
        Pop-Location
    }
}

if (-not $WorkloadClientId) {
    Write-Error "No se obtuvo WorkloadClientId. Ejecuta con -WorkloadClientId '<guid>' o arregla auth Azure/terraform output."
}

$saRaw = Get-Content (Join-Path $K8sDir "serviceaccount.yaml") -Raw
$saRendered = $saRaw -replace "REPLACE_ME_WORKLOAD_MI_CLIENT_ID", $WorkloadClientId.Trim()

$combined = @()
$combined += $saRendered.TrimEnd()
$combined += "---"
$combined += (Get-Content (Join-Path $K8sDir "deployment.yaml") -Raw).TrimEnd()
$combined += "---"
$combined += (Get-Content (Join-Path $K8sDir "service.yaml") -Raw).TrimEnd()

$allPath = Join-Path $GeneratedDir "all.yaml"
($combined -join "`n") | Set-Content -Path $allPath -Encoding utf8
Write-Host "Manifiesto generado: $allPath"

if ($SkipPush) {
    Write-Host "SkipPush: omitiendo docker build, login, push y apply."
    exit 0
}

Push-Location $Root
try {
    docker build -t acrlzdev66635.azurecr.io/lz-app:latest .
}
finally {
    Pop-Location
}

az acr login --name acrlzdev66635
docker push acrlzdev66635.azurecr.io/lz-app:latest

if ($SkipDeploy) {
    Write-Host "SkipDeploy: no se invoca aks command invoke."
    exit 0
}

az aks command invoke `
    --resource-group rg-spoke-app-lz-dev `
    --name aks-lz-dev `
    --command "kubectl apply -f all.yaml" `
    --file $allPath

az aks command invoke `
    --resource-group rg-spoke-app-lz-dev `
    --name aks-lz-dev `
    --command "kubectl rollout status deployment/lz-app --timeout=120s"

az aks command invoke `
    --resource-group rg-spoke-app-lz-dev `
    --name aks-lz-dev `
    --command "kubectl get pods -l app=lz-app -o wide"

az aks command invoke `
    --resource-group rg-spoke-app-lz-dev `
    --name aks-lz-dev `
    --command "kubectl logs deployment/lz-app --tail=80"
