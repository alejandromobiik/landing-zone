# =============================================================================
# modules/keyvault/variables.tf — Parámetros del módulo Key Vault
# =============================================================================
#
# ¿Qué es Azure Key Vault?
#   Key Vault es la caja fuerte de Azure. Almacena tres tipos de objetos:
#     - Secrets:      contraseñas, cadenas de conexión, API keys
#     - Keys:         claves criptográficas para cifrado/descifrado
#     - Certificates: certificados TLS/SSL
#
#   La regla de oro: NUNCA escribas un secreto en el código. Si la aplicación
#   necesita una contraseña de base de datos, la lee del Key Vault en tiempo
#   de ejecución usando su identidad (Managed Identity), sin que ningún
#   humano tenga que ver ni copiar esa contraseña.
#
# ¿Por qué Private Endpoint?
#   Sin Private Endpoint, Key Vault tiene una URL pública (*.vault.azure.net).
#   Cualquiera en internet podría intentar atacarla. Con Private Endpoint,
#   el vault solo es accesible desde dentro de tu red privada (la VNet spoke).
#   Combinado con public_network_access_enabled = false, el vault es
#   completamente invisible desde internet.
#
# =============================================================================

variable "location" {
  description = "Región de Azure donde se crea el Key Vault."
  type        = string
}

variable "name_suffix" {
  description = "Sufijo para el nombre del vault. Ejemplo: '-lz-dev'. Resulta en 'kv-lz-dev'. IMPORTANTE: los nombres de Key Vault son globalmente únicos en Azure."
  type        = string
}

variable "tags" {
  description = "Mapa de etiquetas que se aplican al vault y al Private Endpoint."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Resource Groups
# -----------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Resource Group donde vive el Key Vault (rg-spoke-app)."
  type        = string
}

variable "hub_resource_group_name" {
  description = "Resource Group donde están las Private DNS Zones del hub (rg-network-hub). Se usa para la DNS zone group del Private Endpoint."
  type        = string
}

# -----------------------------------------------------------------------------
# Identidad y acceso
# -----------------------------------------------------------------------------

variable "tenant_id" {
  description = "Tenant ID de Azure AD. Requerido por Key Vault para saber qué directorio gestiona las identidades. Se obtiene de data.azurerm_client_config.current.tenant_id."
  type        = string
}

# -----------------------------------------------------------------------------
# Networking — recibe outputs del módulo network
# -----------------------------------------------------------------------------

variable "subnet_private_endpoints_id" {
  description = "ID de la subnet donde se crea el Private Endpoint del vault. Viene de module.network.subnet_private_endpoints_id."
  type        = string
}

variable "private_dns_zone_keyvault_id" {
  description = "ID de la Private DNS Zone 'privatelink.vaultcore.azure.net'. Viene de module.network.private_dns_zone_keyvault_id. Se usa para registrar el PE en la zona DNS y permitir la resolución de nombres."
  type        = string
}
