# =============================================================================
# modules/network/outputs.tf — Valores que exporta el módulo de red
# =============================================================================
#
# ¿Para qué sirven los outputs de un módulo?
#   Cuando el main.tf raíz llama a este módulo, necesita saber los IDs
#   y nombres de los recursos creados para pasárselos a otros módulos.
#
#   Ejemplo:
#     - El módulo "aks" necesita el ID de la subnet de AKS
#     - El módulo "keyvault" necesita el ID de la subnet de Private Endpoints
#     - El módulo "acr" necesita el mismo subnet de Private Endpoints
#
#   Sin outputs, el main.tf no podría conectar los módulos entre sí.
#
# =============================================================================

# -----------------------------------------------------------------------------
# VNet Hub
# -----------------------------------------------------------------------------

output "hub_vnet_id" {
  description = "ID de la VNet hub. Se usa para configurar el VNet Peering en módulos de red adicionales."
  value       = azurerm_virtual_network.hub.id
}

output "hub_vnet_name" {
  description = "Nombre de la VNet hub."
  value       = azurerm_virtual_network.hub.name
}

# -----------------------------------------------------------------------------
# VNet Spoke
# -----------------------------------------------------------------------------

output "spoke_vnet_id" {
  description = "ID de la VNet spoke. Se usa para configurar el VNet Peering."
  value       = azurerm_virtual_network.spoke.id
}

output "spoke_vnet_name" {
  description = "Nombre de la VNet spoke."
  value       = azurerm_virtual_network.spoke.name
}

# -----------------------------------------------------------------------------
# Subnets del Spoke — los módulos AKS, ACR y Key Vault los necesitan
# -----------------------------------------------------------------------------

output "subnet_aks_id" {
  description = "ID de la subnet para nodos de AKS. Pasar a var.subnet_id en el módulo aks."
  value       = azurerm_subnet.spoke_aks.id
}

output "subnet_private_endpoints_id" {
  description = "ID de la subnet para Private Endpoints. Pasar al módulo keyvault y acr."
  value       = azurerm_subnet.spoke_private_endpoints.id
}

# -----------------------------------------------------------------------------
# Private DNS Zones — los módulos keyvault y acr las necesitan para vincular
# -----------------------------------------------------------------------------

output "private_dns_zone_acr_id" {
  description = "ID de la Private DNS Zone para ACR (privatelink.azurecr.io)."
  value       = azurerm_private_dns_zone.acr.id
}

output "private_dns_zone_keyvault_id" {
  description = "ID de la Private DNS Zone para Key Vault (privatelink.vaultcore.azure.net)."
  value       = azurerm_private_dns_zone.keyvault.id
}

output "private_dns_zone_aks_id" {
  description = "ID de la Private DNS Zone para AKS (privatelink.eastus2.azmk8s.io)."
  value       = azurerm_private_dns_zone.aks.id
}
