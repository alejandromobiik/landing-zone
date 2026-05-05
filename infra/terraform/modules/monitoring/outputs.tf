# =============================================================================
# modules/monitoring/outputs.tf — Valores que exporta el módulo de monitoreo
# =============================================================================
#
# Estos outputs son esenciales para conectar el workspace con otros módulos:
#
#   workspace_id           → AKS lo necesita para el add-on oms_agent
#                            (envío de métricas y logs del cluster)
#   workspace_resource_id  → Mismo uso que workspace_id pero en formato
#                            ARM (Resource ID completo). Algunos recursos
#                            de Azure requieren el ARM ID en lugar del GUID.
#   workspace_name         → Para construir URLs del portal o referencias
#                            en otros recursos de diagnóstico.
#
# =============================================================================

# GUID del workspace — usado por algunos recursos de Azure para referenciar el LAW
output "workspace_id" {
  description = "GUID del Log Analytics Workspace. Requerido por AKS (oms_agent) y Diagnostic Settings."
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# ARM Resource ID completo (/subscriptions/.../workspaces/law-lz-dev)
output "workspace_resource_id" {
  description = "ARM Resource ID completo del workspace. Requerido por azurerm_monitor_diagnostic_setting y azurerm_kubernetes_cluster."
  value       = azurerm_log_analytics_workspace.main.id
}

# Nombre legible del workspace
output "workspace_name" {
  description = "Nombre del Log Analytics Workspace (ej: law-lz-dev)."
  value       = azurerm_log_analytics_workspace.main.name
}
