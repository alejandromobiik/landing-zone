# =============================================================================
# modules/monitoring/main.tf — Log Analytics Workspace
# =============================================================================
#
# ¿Qué es Log Analytics Workspace?
#   Es la base de datos de logs de Azure. Todos los recursos (AKS, Key Vault,
#   NSGs, etc.) envían sus registros aquí. Desde el workspace puedes:
#     - Escribir consultas KQL para analizar logs
#     - Crear alertas automáticas (ej: "avísame si hay más de 5 errores en 1 min")
#     - Ver dashboards de métricas de rendimiento
#
# ¿Qué es PerGB2018?
#   Es el modelo de precios "pago por lo que usas". Los primeros 5 GB/mes
#   son gratuitos. Después se cobra por GB ingerido. Para esta landing zone
#   de desarrollo, los logs son tan pequeños que el costo será $0.
#
# ¿Por qué 30 días de retención?
#   Es el mínimo recomendado para poder investigar incidentes.
#   Azure guarda los logs en "hot storage" durante este período y luego
#   los elimina automáticamente. Retención mayor = mayor costo.
#
# COSTO ESTIMADO: ~$0/mes para cargas de trabajo de desarrollo
#   (los logs generados por 1 nodo AKS en desarrollo están muy por debajo
#   de los 5 GB gratuitos mensuales)
#
# =============================================================================

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law${var.name_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days
  tags                = var.tags
}
