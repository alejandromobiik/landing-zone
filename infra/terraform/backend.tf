# =============================================================================
# backend.tf — Dónde Terraform guarda su "memoria" (el estado)
# =============================================================================
#
# ¿Qué es el tfstate y por qué importa?
#   Cuando Terraform crea recursos en Azure, guarda un registro de todo lo que
#   creó en un archivo llamado "terraform.tfstate". Este archivo es la
#   "memoria" de Terraform: le permite saber qué ya existe, qué cambió y
#   qué debe destruir.
#
#   Sin este archivo, Terraform no puede comparar el estado deseado (tu código)
#   con el estado real (lo que hay en Azure) y fallaría o duplicaría recursos.
#
# ¿Por qué guardarlo en Azure y no en tu máquina?
#   Si el estado vive solo en tu máquina:
#     ❌ Los pipelines de GitHub Actions no pueden leerlo ni escribirlo
#     ❌ Si pierdes tu máquina, Terraform "olvida" todo lo que creó
#     ❌ Si dos personas corren Terraform a la vez, los estados colisionan
#
#   Al guardarlo en Azure Storage Account:
#     ✅ Los pipelines acceden al estado de forma centralizada
#     ✅ Azure habilita automáticamente el "state locking" (bloqueo):
#        si un pipeline está corriendo "apply", otro no puede empezar
#        hasta que el primero termine — evita corrupción del estado
#     ✅ El Storage Account ya existe (creado por bootstrap.ps1 en la Fase 2)
#
# ¿Por qué el bloque backend no puede usar variables de Terraform?
#   Esta es una limitación conocida de Terraform: el backend se inicializa
#   ANTES de que las variables sean evaluadas, así que no puedes escribir
#   backend { storage_account_name = var.storage_account_name }.
#   Los valores deben ser literales (hardcoded). Por eso usamos el nombre
#   real del Storage Account directamente aquí.
#
# Recursos de Azure que usa este backend (todos creados por bootstrap.ps1):
#   - Resource Group:    rg-platform
#   - Storage Account:  stlztf86c66635
#   - Contenedor blob:  tfstate
#   - Archivo de estado: landing-zone.tfstate
#
# =============================================================================

terraform {
  backend "azurerm" {
    # ------------------------------------------------------------------
    # Resource Group donde vive el Storage Account del tfstate.
    # Creado en la Fase 2 por bootstrap.ps1.
    # ------------------------------------------------------------------
    resource_group_name = "rg-platform"

    # ------------------------------------------------------------------
    # Nombre del Storage Account donde se guarda el archivo de estado.
    # Nombre único: prefijo "stlztf" + últimos 8 chars del Subscription ID.
    # Creado en la Fase 2 por bootstrap.ps1.
    # ------------------------------------------------------------------
    storage_account_name = "stlztf86c66635"

    # ------------------------------------------------------------------
    # Contenedor de blobs dentro del Storage Account.
    # Un "contenedor" es como una carpeta dentro del Storage Account.
    # Creado en la Fase 2 por bootstrap.ps1.
    # ------------------------------------------------------------------
    container_name = "tfstate"

    # ------------------------------------------------------------------
    # Nombre del archivo .tfstate dentro del contenedor.
    # Si tuvieras múltiples proyectos en el mismo Storage Account,
    # cada uno usaría un "key" diferente para no pisarse entre sí.
    # Ejemplo: "network.tfstate", "app.tfstate", "landing-zone.tfstate"
    # ------------------------------------------------------------------
    key = "landing-zone.tfstate"

    # ------------------------------------------------------------------
    # ¿Cómo se autentica Terraform con el Storage Account?
    #
    # En local (cuando tú corres terraform init/plan/apply desde tu máquina):
    #   Terraform usa tu sesión activa de Azure CLI (az login) o de Az
    #   PowerShell (Connect-AzAccount). No necesitas configurar nada extra.
    #
    # En GitHub Actions (cuando el pipeline corre terraform):
    #   El pipeline usa OIDC + las variables de entorno:
    #     ARM_CLIENT_ID       → el AppId del Service Principal
    #     ARM_TENANT_ID       → el tenant de Azure
    #     ARM_SUBSCRIPTION_ID → la suscripción
    #   El Service Principal tiene el rol "Storage Blob Data Contributor"
    #   sobre este Storage Account (asignado por bootstrap.ps1 en la Fase 2).
    #
    # NO se usan access keys del Storage Account (use_azuread_auth = true
    # por defecto en azurerm >= 3.x cuando se usa OIDC). Esto es más seguro
    # porque evita manejar claves de acceso que podrían filtrarse.
    # ------------------------------------------------------------------
  }
}
