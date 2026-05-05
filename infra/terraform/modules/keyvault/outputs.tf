# =============================================================================
# modules/keyvault/outputs.tf — Valores que exporta el módulo Key Vault
# =============================================================================
#
# Los módulos downstream (aks, y futuros módulos de aplicación) necesitan:
#   keyvault_id   → para asignar roles RBAC (ej: "Key Vault Secrets User")
#   keyvault_uri  → para que la aplicación sepa a qué URL conectarse
#   keyvault_name → para referencias en scripts y documentación
#
# =============================================================================

output "keyvault_id" {
  description = "ARM Resource ID del Key Vault. Se usa para asignar roles RBAC sobre el vault."
  value       = azurerm_key_vault.main.id
}

output "keyvault_uri" {
  description = "URI del Key Vault (ej: https://kv-lz-dev.vault.azure.net/). La aplicación lo usa para leer secretos vía SDK o CSI driver."
  value       = azurerm_key_vault.main.vault_uri
}

output "keyvault_name" {
  description = "Nombre del Key Vault (ej: kv-lz-dev)."
  value       = azurerm_key_vault.main.name
}
