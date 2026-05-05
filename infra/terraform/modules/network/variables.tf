# =============================================================================
# modules/network/variables.tf — Parámetros de entrada del módulo de red
# =============================================================================
#
# Estos son los "botones" del módulo: valores que el main.tf raíz pasa
# al módulo para personalizar la red sin tocar el código interno.
#
# Separar variables en su propio archivo (en lugar de ponerlas en main.tf)
# sigue la convención estándar de Terraform y facilita la documentación.
#
# =============================================================================

# -----------------------------------------------------------------------------
# Identificación y ubicación
# -----------------------------------------------------------------------------

variable "location" {
  description = "Región de Azure donde se crearán las VNets y recursos de red."
  type        = string
}

variable "name_suffix" {
  description = "Sufijo para nombres de recursos. Ejemplo: '-lz-dev'. Se concatena al final de cada nombre para identificar proyecto y entorno."
  type        = string
}

variable "tags" {
  description = "Mapa de etiquetas que se aplican a todos los recursos del módulo."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Resource Groups donde viven los recursos de red
# -----------------------------------------------------------------------------

variable "hub_resource_group_name" {
  description = "Nombre del Resource Group donde se crea la VNet hub y los recursos compartidos (Private DNS Zones, NSG hub)."
  type        = string
}

variable "spoke_resource_group_name" {
  description = "Nombre del Resource Group donde se crea la VNet spoke con subnets para AKS y Private Endpoints."
  type        = string
}

# -----------------------------------------------------------------------------
# Espacios de direcciones IP (CIDRs)
#
# ¿Qué es un CIDR?
#   Un CIDR (ej: 10.0.0.0/16) define un rango de IPs.
#   /16 = 65,536 IPs disponibles
#   /24 = 256 IPs disponibles
#   /27 = 32 IPs disponibles
#
# Regla de diseño hub-spoke:
#   Los rangos hub y spoke no deben solaparse. Si hub es 10.0.0.0/16,
#   spoke debe empezar en 10.1.0.0/16 o más. Azure rechaza el peering
#   si los rangos se superponen.
# -----------------------------------------------------------------------------

variable "hub_vnet_cidr" {
  description = "Espacio de direcciones de la VNet hub. Debe ser un rango /16 o mayor. No debe solaparse con spoke_vnet_cidr."
  type        = string
  default     = "10.0.0.0/16"
}

variable "hub_subnet_private_dns_cidr" {
  description = "Subred del hub destinada a recursos de DNS privado. /24 es suficiente."
  type        = string
  default     = "10.0.1.0/24"
}

variable "spoke_vnet_cidr" {
  description = "Espacio de direcciones de la VNet spoke. Debe ser un rango /16 o mayor. No debe solaparse con hub_vnet_cidr."
  type        = string
  default     = "10.1.0.0/16"
}

variable "spoke_subnet_aks_cidr" {
  description = "Subred del spoke para los nodos de AKS. /22 = 1024 IPs, suficiente para un cluster pequeño con espacio para crecer."
  type        = string
  default     = "10.1.0.0/22"
}

variable "spoke_subnet_pe_cidr" {
  description = "Subred del spoke para Private Endpoints (ACR, Key Vault). /24 = 256 IPs, más que suficiente para endpoints."
  type        = string
  default     = "10.1.10.0/24"
}
