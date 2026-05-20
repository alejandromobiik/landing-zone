# =============================================================================
# modules/monitoring/variables.tf — Parámetros de entrada del módulo de observabilidad
# =============================================================================
#
# Este módulo crea el Log Analytics Workspace (LAW), que es el repositorio
# central de logs de toda la landing zone. Todos los recursos (AKS, Key Vault,
# NSGs) enviarán sus logs aquí para poder consultarlos y crear alertas.
#
# ¿Por qué un módulo separado para monitoring?
#   El workspace de Log Analytics debe crearse ANTES que AKS, Key Vault, etc.,
#   porque todos ellos necesitan su ID para configurar el envío de logs.
#   Separarlo en un módulo garantiza ese orden de creación y permite
#   reutilizarlo si en el futuro añadimos más spokes a la landing zone.
#
# =============================================================================

# -----------------------------------------------------------------------------
# Identificación y ubicación
# -----------------------------------------------------------------------------

variable "location" {
  description = "Región de Azure donde se creará el Log Analytics Workspace."
  type        = string
}

variable "name_suffix" {
  description = "Sufijo para el nombre del workspace. Ejemplo: '-lz-dev'. Resulta en 'law-lz-dev'."
  type        = string
}

variable "tags" {
  description = "Mapa de etiquetas que se aplican al workspace."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Nombre del Resource Group donde se crea el workspace. Se recomienda rg-platform, donde ya vive el Storage Account del tfstate."
  type        = string
}

# -----------------------------------------------------------------------------
# Configuración del workspace
# -----------------------------------------------------------------------------

variable "retention_in_days" {
  description = <<-EOT
    Días que se conservan los logs en el workspace.
    Mínimo: 30 días (cumplimiento básico).
    Máximo sin costo adicional en el tier PerGB2018: 31 días.
    Los primeros 5 GB/mes son gratuitos. Retención más larga = mayor costo.
  EOT
  type        = number
  default     = 30

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "La retención debe estar entre 30 y 730 días."
  }
}

# -----------------------------------------------------------------------------
# Diagnostic Settings — recursos evaluados por el PDF (no incluyen AKS aquí)
# -----------------------------------------------------------------------------

variable "keyvault_id" {
  description = "ARM Resource ID del Key Vault. Destino de Diagnostic Settings (audit logs)."
  type        = string
}

variable "nsg_hub_id" {
  description = "ARM Resource ID del NSG del hub. Para logs de flujo y contadores de reglas."
  type        = string
}

variable "nsg_spoke_id" {
  description = "ARM Resource ID del NSG del spoke."
  type        = string
}
