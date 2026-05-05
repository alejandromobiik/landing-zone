# =============================================================================
# modules/acr/outputs.tf — Valores que exporta el módulo ACR
# =============================================================================
#
# El módulo aks necesita:
#   acr_id           → para asignar el rol AcrPull a la kubelet identity de AKS
#   acr_login_server → para que los pipelines sepan a qué registry hacer push
#   acr_name         → para referencias en scripts y documentación
#
# =============================================================================

output "acr_id" {
  description = "ARM Resource ID del ACR. Se pasa al módulo aks para asignar el rol AcrPull a la kubelet identity."
  value       = azurerm_container_registry.main.id
}

output "acr_login_server" {
  description = "URL de login del registry (ej: acrlzdev.azurecr.io). Los pipelines de CI/CD hacen 'docker push' a este servidor."
  value       = azurerm_container_registry.main.login_server
}

output "acr_name" {
  description = "Nombre del ACR (ej: acrlzdev). Se puede usar con 'az acr login --name acrlzdev'."
  value       = azurerm_container_registry.main.name
}
