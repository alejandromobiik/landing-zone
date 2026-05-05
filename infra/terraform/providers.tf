# =============================================================================
# providers.tf — Declaración de proveedores de Terraform
# =============================================================================
#
# ¿Qué es un proveedor?
#   Terraform por sí solo no sabe cómo hablar con Azure, AWS, GCP, etc.
#   Los "proveedores" son plugins que añaden esa capacidad. Piénsalos como
#   adaptadores: el proveedor "azurerm" traduce el código Terraform en
#   llamadas a la API REST de Azure.
#
# ¿Por qué fijamos versiones?
#   Si no fijamos versión, Terraform podría descargar automáticamente una
#   versión nueva del proveedor que cambie el comportamiento del código y
#   rompa el plan. Fijar versiones garantiza que todos (tú, tus pipelines,
#   tus compañeros) usen exactamente el mismo proveedor.
#   El operador "~>" significa "acepta parches pero no cambios de versión mayor".
#   Ejemplo: ~> 4.0 acepta 4.1, 4.9 pero NO 5.0.
#
# =============================================================================

terraform {
  # ------------------------------------------------------------------
  # Versión mínima de Terraform requerida.
  # La sintaxis de HCL y algunos recursos cambian entre versiones.
  # >= 1.7 trae mejoras importantes en el manejo del backend remoto.
  # ------------------------------------------------------------------
  required_version = ">= 1.7"

  # ------------------------------------------------------------------
  # Proveedores necesarios para este proyecto.
  # Terraform los descarga automáticamente al ejecutar "terraform init".
  # ------------------------------------------------------------------
  required_providers {

    # azurerm: el proveedor oficial de Microsoft para Azure.
    # Es el que permite crear Resource Groups, VNets, AKS, etc.
    # Documentación: https://registry.terraform.io/providers/hashicorp/azurerm/latest
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    # azuread: proveedor separado para recursos de Entra ID (antes Azure AD).
    # Se usa para leer datos del tenant, del Service Principal, etc.
    # Está separado de azurerm porque maneja identidades, no infraestructura.
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }

    # random: genera valores aleatorios (sufijos únicos para nombres de recursos).
    # Útil para nombres que deben ser globalmente únicos en Azure,
    # como Storage Accounts o Key Vaults.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# =============================================================================
# Configuración del proveedor azurerm
#
# ¿Por qué "features {}"?
#   El bloque features{} es OBLIGATORIO en azurerm aunque esté vacío.
#   Permite activar comportamientos opcionales del proveedor, como:
#     - Que Key Vault borre secretos permanentemente al hacer destroy
#     - Que AKS se elimine aunque tenga node pools adicionales
#   En este proyecto usamos los defaults seguros de cada feature.
#
# ¿Por qué no ponemos subscription_id aquí?
#   Porque lo leerá automáticamente de la variable de entorno
#   ARM_SUBSCRIPTION_ID, que los pipelines de GitHub Actions configuran
#   usando OIDC. Esto evita hardcodear el ID en el código.
# =============================================================================
provider "azurerm" {
  features {
    # ------------------------------------------------------------------
    # Key Vault: evitar borrado permanente accidental de secretos.
    # Con purge_soft_delete_on_destroy = false, al hacer "terraform destroy"
    # el vault queda en estado "soft-deleted" (recuperable 90 días).
    # Esto es una red de seguridad contra borrados accidentales.
    # ------------------------------------------------------------------
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }

    # ------------------------------------------------------------------
    # Resource Group: si el RG contiene recursos que Terraform no gestiona,
    # con prevent_deletion_if_contains_resources = true el destroy falla
    # en lugar de borrar silenciosamente esos recursos huérfanos.
    # ------------------------------------------------------------------
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

# =============================================================================
# Configuración del proveedor azuread
#
# Sin parámetros adicionales: hereda el tenant de la sesión activa
# (la misma que usa azurerm). No es necesario duplicar el tenant_id aquí.
# =============================================================================
provider "azuread" {}

# =============================================================================
# Data sources: información que Terraform LEE de Azure, no crea.
#
# ¿Qué es un data source?
#   Un "data source" es como una consulta de solo lectura.
#   En vez de crear un recurso, Terraform pregunta a Azure:
#   "dame los datos de este recurso que ya existe".
#   Son útiles para obtener el ID del tenant, la suscripción actual, etc.
#
# Estos dos data sources se usan en varios módulos para no repetir
# la misma consulta en cada uno.
# =============================================================================

# Devuelve información de la sesión activa: tenant_id, object_id, client_id.
# Útil para configurar Key Vault access policies, Role Assignments, etc.
data "azurerm_client_config" "current" {}

# Devuelve información de la suscripción activa: id, display_name, tenant_id.
# Útil para construir scopes de RBAC y Policy sin hardcodear el ID.
data "azurerm_subscription" "current" {}
