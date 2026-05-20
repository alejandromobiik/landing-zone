# lz-app — Flask + Key Vault (Workload Identity)

Aplicación mínima de la **Fase 8** del plan de trabajo: `/health` y `/` (lee el secreto `app-message` del Key Vault mediante Workload Identity).

## Prerrequisitos

- Docker
- Azure CLI autenticado (sin errores SSL/proxy)
- Secreto `app-message` en `kv-lz-dev-66635`
- Cluster `aks-lz-dev` en estado **Running**
- `terraform output -raw workload_app_identity_client_id` disponible (identidad `mi-applzdev` federada con `system:serviceaccount:default:lz-app-sa`)

## Verificaciones Azure (solo lectura)

```powershell
az acr show --name acrlzdev66635 --query "{sku:sku.name,adminEnabled:adminUserEnabled}" -o table
az aks check-acr --name aks-lz-dev --resource-group rg-spoke-app-lz-dev --acr acrlzdev66635
az aks show --name aks-lz-dev --resource-group rg-spoke-app-lz-dev --query powerState.code -o tsv
az keyvault secret show --vault-name kv-lz-dev-66635 --name app-message
```

Si `az keyvault` falla por red privada, ver `docs/runbook-kv-temporal-access.md`.

## Build local (opcional)

```powershell
cd app
docker build -t lz-app:local .
docker run --rm -p 8080:8080 lz-app:local
# En otro terminal: curl http://localhost:8080/health
```

La ruta `/` en local normalmente **no** podrá leer Key Vault sin credencial compatible; la prueba real es en AKS.

## Despliegue (build + push + apply)

Desde `landing-zone/app`:

```powershell
pwsh -File scripts/deploy-phase8.ps1
```

Con client ID manual si no puedes ejecutar `terraform output`:

```powershell
pwsh -File scripts/deploy-phase8.ps1 -WorkloadClientId "<guid>"
```

Solo generar `app/.generated/all.yaml` sin Docker ni Azure:

```powershell
pwsh -File scripts/deploy-phase8.ps1 -SkipPush -WorkloadClientId "<guid>"
```

El script genera `.generated/all.yaml` (no versionar; está en `.gitignore`) con el ServiceAccount ya renderizado.

### Notas del entorno de desarrollo

- Si `docker build` falla con error de pipe/named pipe, **inicia Docker Desktop** y vuelve a intentar.
- Si `az` o `terraform output` fallan con **SSL certificate verify failed**, suele ser proxy/certificado corporativo: corrige el bundle de CA o usa la guía de Microsoft para Azure CLI detrás de proxy.

## Manifiestos

- `k8s/serviceaccount.yaml` — contiene placeholder `REPLACE_ME_WORKLOAD_MI_CLIENT_ID` (lo sustituye el script).
- `k8s/deployment.yaml` — imagen `acrlzdev66635.azurecr.io/lz-app:latest`, etiqueta Workload Identity.
- `k8s/service.yaml` — ClusterIP puerto 8080.
