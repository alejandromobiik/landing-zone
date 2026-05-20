# Prácticas y Reglas del Proyecto — Landing Zone

> Este documento registra los errores reales que ocurrieron durante el proyecto
> y las reglas que se establecieron para prevenirlos en el futuro.
> Se actualiza cada vez que aparece un problema nuevo.

---

## Reglas generales

### R-01 · Todo el trabajo va dentro del repositorio

**Regla:** A partir de la Fase 3, ningún archivo de trabajo se crea fuera de `landing-zone/`. El único archivo externo permitido es `documentos/plan-de-trabajo.md` (referencia de evaluación).

**Razón:** Mantener el código, documentación y scripts en un único lugar permite que los pipelines y colaboradores encuentren todo en el repositorio sin dependencias externas.

---

### R-02 · Nunca hagas push directo a `main`

**Regla:** Crea siempre una rama con prefijo `feat/`, `fix/` o `docs/` → commit → push → PR → merge.

```bash
git checkout -b feat/nombre-descriptivo
# ... editar archivos ...
git add .
git commit -m "tipo(alcance): descripción corta"
git push origin feat/nombre-descriptivo
# → abrir PR en GitHub
```

**Razón:** La rama `main` tiene branch protection activa (ruleset `main-protection`). Un push directo devuelve `GH013: Repository rule violations found`. Además, el flujo de PR activa el pipeline `terraform-plan.yml` automáticamente.

---

### R-03 · Siempre `fmt` antes de `validate` antes de `plan`

**Regla:** El orden correcto es siempre:

```bash
terraform fmt -recursive    # 1. corrige formato
terraform validate          # 2. verifica sintaxis
terraform plan -out=tfplan  # 3. calcula cambios
terraform apply "tfplan"    # 4. aplica lo calculado
```

**Razón:** `validate` puede fallar por problemas de formato. `plan` puede mostrar resultados confusos si hay errores de sintaxis no detectados. El orden asegura que cada paso parte de una base limpia.

---

### R-04 · Nunca guardes secretos en archivos `.tf` o en el repositorio

**Regla:** Los valores sensibles (contraseñas, tokens, IDs de tenant) nunca van escritos directamente en el código. Usa:

- `sensitive = true` en outputs de Terraform
- Variables de entorno en los pipelines
- Azure Key Vault para secretos de la aplicación
- GitHub Secrets para credenciales de CI/CD

**Verificación antes de cada commit:**

```bash
git grep -r "password\|secret\|client_secret\|token" infra/
```

Si devuelve algo, revisa si es un nombre de variable (aceptable) o un valor real (inaceptable).

---

### R-05 · Ahorro de costos con scripts `cost-down-off` / `cost-down-on`

**Regla:** Para parar compute de AKS y opcionalmente vaciar imágenes ACR sin tocar Terraform state, usa los scripts en `scripts/` y el runbook [runbook-cost-shutdown.md](runbook-cost-shutdown.md). No mezcles `terraform apply` con `cost-down-off` sin coordinación.

**Razón:** Evita drift, pérdida de estado en `stlztf*` y pods en CrashLoop si ACR quedó vacío sin redeploy.

---

## Errores de Azure / Terraform

### E-01 · `terraform plan` se cuelga en "Acquiring state lock"

**Síntoma:** El comando `terraform plan` muestra `Acquiring state lock. This may take a few moments...` y no avanza después de 2+ minutos.

**Causa raíz:** El usuario tiene `Owner` en la suscripción (plano de gestión de Azure) pero **no tiene** `Storage Blob Data Contributor` en el Storage Account (plano de datos). Son dos planos de autorización completamente separados en Azure. El state lock de Terraform requiere hacer un `PUT lease` en el blob, que es una operación del plano de datos.

**Solución:**

```bash
# 1. Obtener el Object ID del usuario actual
$me = (az ad signed-in-user show --query id --output tsv)

# 2. Asignar el rol en el Storage Account del tfstate
az role assignment create `
  --assignee-object-id $me `
  --assignee-principal-type User `
  --role "Storage Blob Data Contributor" `
  --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-platform/providers/Microsoft.Storage/storageAccounts/stlztf86c66635"

# 3. Esperar ~2 minutos para que el RBAC propague, luego reintentar
terraform plan -out=tfplan
```

**Prevención:** El script `bootstrap.ps1` (Paso 7) ya asigna este rol automáticamente tanto al Service Principal como al usuario que ejecuta el script. Si aparece este error en una máquina nueva, ejecutar `bootstrap.ps1` de nuevo (es idempotente).

---

### E-02 · `terraform validate` falla con "Missing required provider"

**Síntoma:**
```
Error: Missing required provider
This configuration requires provider registry.terraform.io/hashicorp/azurerm,
but that provider isn't available.
```

**Causa:** La carpeta `.terraform/` no existe o fue borrada. Terraform necesita tener descargados localmente los providers para poder validar.

**Solución:**

```bash
terraform init
terraform validate
```

**Prevención:** No borrar la carpeta `.terraform/`. Está en `.gitignore` (no se commitea), pero debe existir en cada máquina donde se trabaje. Si clonas el repositorio en una máquina nueva, siempre ejecuta `terraform init` primero.

---

### E-03 · `az ad app federated-credential create` falla por comillas en PowerShell

**Síntoma:** El comando `az` recibe el JSON mal formado cuando se pasa inline en PowerShell:
```
ERROR: az: error: unrecognized arguments: ...
```

**Causa:** PowerShell y el shell subyacente tienen reglas de escape de comillas incompatibles cuando se pasan strings JSON inline.

**Solución:** Escribir el JSON a un archivo temporal y pasar la ruta:

```powershell
$tempFile = [System.IO.Path]::GetTempFileName()
$json = @{
    name      = "nombre-credencial"
    issuer    = "https://token.actions.githubusercontent.com"
    subject   = "repo:org/repo:ref:refs/heads/main"
    audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json
Set-Content -Path $tempFile -Value $json -Encoding UTF8
az ad app federated-credential create --id $appId --parameters "@$tempFile"
Remove-Item $tempFile
```

**Prevención:** Nunca pasar JSON inline a `az` desde PowerShell. Siempre usar archivo temporal o here-string guardado en variable.

---

### E-04 · `Get-AzADAppFederatedIdentityCredential` no existe

**Síntoma:**
```
Get-AzADAppFederatedIdentityCredential: The term 'Get-AzADAppFederatedIdentityCredential'
is not recognized as a name of a cmdlet
```

**Causa:** El módulo Az instalado en la máquina es una versión antigua que no incluye este cmdlet (se añadió en versiones más recientes del módulo Az).

**Solución:** Usar `az` CLI en lugar de PowerShell para operaciones de Federation Credentials:

```bash
az ad app federated-credential list --id $appId
az ad app federated-credential create --id $appId --parameters "@archivo.json"
```

**Prevención:** El script `bootstrap.ps1` ya usa `az` CLI para todas las operaciones de Federation Credentials, evitando esta dependencia de versión del módulo Az.

---

### E-05 · `terraform plan` incoherente después de matar el terminal

**Síntoma:** Después de matar un `terraform plan` o `terraform apply` a mitad de ejecución, el siguiente plan muestra cambios inesperados o el state lock no se libera.

**Diagnóstico:**

```bash
# Verificar si el blob tiene un lease activo (state lock sin liberar)
$key = (az storage account keys list --account-name stlztf86c66635 --resource-group rg-platform --query "[0].value" -o tsv)
az storage blob show --account-name stlztf86c66635 --container-name tfstate --name "landing-zone.tfstate" --account-key $key --query "{leaseState:properties.leaseState, leaseStatus:properties.leaseStatus}" -o json
```

**Solución si `leaseState = "leased"`:**

```bash
# Romper el lease forzosamente (requiere Storage Blob Data Contributor)
az storage blob lease break --account-name stlztf86c66635 --container-name tfstate --blob-name "landing-zone.tfstate" --account-key $key
```

**Solución alternativa (Terraform):**

```bash
terraform force-unlock <LOCK_ID>
# El LOCK_ID aparece en el mensaje de error de terraform plan
```

**Prevención:** No matar el terminal mientras Terraform está corriendo. Si es inevitable, verificar siempre el estado del lease antes del siguiente plan.

---

## Errores de Git / GitHub

### E-06 · Push directo a `main` bloqueado

**Síntoma:**
```
remote: error: GH013: Repository rule violations found for refs/heads/main.
```

**Causa:** La rama `main` tiene branch protection activa (ruleset `main-protection`). Todo cambio debe pasar por Pull Request.

**Solución:**

```bash
# Si ya hiciste commits en main local
git checkout -b feat/mi-rama      # crear rama desde donde estás
git push origin feat/mi-rama      # subir la rama
# → abrir PR en GitHub
```

**Prevención:** Antes de empezar cualquier cambio, verificar en qué rama estás:
```bash
git branch --show-current
```
Si dice `main`, crea una rama antes de editar.

---

### E-07 · Rama `feat/bootstrap` desactualizada respecto a `main`

**Síntoma:** Al crear una nueva rama desde `feat/bootstrap` en lugar de desde `main` actualizado, la rama nueva no tiene los commits del PR mergeado.

**Solución:**

```bash
git checkout main
git pull origin main              # traer los últimos cambios de main
git checkout -b feat/nueva-rama   # crear rama desde main actualizado
```

**Prevención:** Antes de crear cualquier rama nueva, siempre:
1. `git checkout main`
2. `git pull origin main`
3. `git checkout -b feat/nombre`

---

## Prácticas de Terraform

### P-01 · Usa `-out=tfplan` y aplica el archivo, nunca `apply` directo

```bash
# Bien ✅
terraform plan -out=tfplan
terraform apply "tfplan"

# Evitar ❌ (puede aplicar cambios diferentes si el estado cambió entre plan y apply)
terraform apply
```

**Razón:** Con `-out=tfplan`, Terraform garantiza que lo que se aplica es exactamente lo que se revisó en el plan. Sin él, entre el `plan` y el `apply` podría haber cambiado algo en Azure.

---

### P-02 · Commits incrementales — un módulo a la vez

**Regla:** Hacer `terraform apply` después de completar cada módulo, no al final de todos.

**Razón:** Si un apply falla a mitad de 20 recursos, el state queda parcialmente aplicado y es difícil depurar. Con applies incrementales, cada apply parte de un estado conocido y funcional.

---

### P-03 · El `.terraform.lock.hcl` SÍ se commitea

```
.terraform/          → en .gitignore (binarios de providers, pesados)
.terraform.lock.hcl  → SÍ se commitea (lock de versiones)
```

**Razón:** El lock file garantiza que todos los entornos (tu máquina, pipelines, compañeros) usen exactamente las mismas versiones de providers. Sin él, un pipeline podría usar una versión diferente de `azurerm` y comportarse distinto.

---

### P-04 · Nunca hardcodees IDs de suscripción en recursos

**Bien:**
```hcl
scope = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
```

**Evitar:**
```hcl
scope = "/subscriptions/1989a8c1-76c1-4555-a228-c95f86c66635"  # hardcoded ❌
```

**Razón:** El subscription ID puede cambiar si el proyecto se mueve a otra suscripción (staging, prod). Usar `data.azurerm_client_config.current.subscription_id` hace el código reutilizable.

---

## Checklist antes de cada commit

Antes de hacer `git add . && git commit`, verificar:

```bash
# 1. Estoy en la rama correcta (NO en main)
git branch --show-current

# 2. El código de Terraform tiene formato correcto
terraform fmt -check -recursive

# 3. La sintaxis de Terraform es válida
terraform validate

# 4. No hay secretos en el código
git grep -r "password\|client_secret\|access_key" infra/ app/

# 5. Los archivos que voy a commitear son los que espero
git status
git diff --staged
```

---

## Referencias rápidas

| Situación | Comando |
|-----------|---------|
| Ver rama actual | `git branch --show-current` |
| Sincronizar main | `git checkout main && git pull origin main` |
| Crear rama nueva | `git checkout -b feat/nombre` |
| Formatear Terraform | `terraform fmt -recursive` |
| Validar sintaxis | `terraform validate` |
| Plan incremental | `terraform plan -out=tfplan` |
| Aplicar plan | `terraform apply "tfplan"` |
| Ver estado actual | `terraform show` |
| Ver outputs | `terraform output` |
| Ver resources en state | `terraform state list` |
| Verificar lease del blob | `az storage blob show --account-name stlztf86c66635 --container-name tfstate --name "landing-zone.tfstate" --account-key $(az storage account keys list --account-name stlztf86c66635 --resource-group rg-platform --query "[0].value" -o tsv) --query "properties.leaseState" -o tsv` |
| Parar AKS (ahorrar dinero) | `az aks stop --name aks-lz-dev --resource-group rg-spoke-app-lz-dev` |
| Iniciar AKS | `az aks start --name aks-lz-dev --resource-group rg-spoke-app-lz-dev` |
