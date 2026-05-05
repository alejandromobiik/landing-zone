# =============================================================================
# modules/policy/outputs.tf — IDs de las asignaciones de política
# =============================================================================
#
# Exporta los IDs de las 5 asignaciones de política.
# Se pueden usar para:
#   - Referencia en otros módulos o en el main.tf raíz
#   - Consulta del estado de conformidad via Azure CLI:
#     az policy assignment show --id <assignment_id>
#   - Importar en Terraform si las políticas ya existen fuera de este módulo
#
# =============================================================================

output "policy_assignment_ids" {
  description = "Mapa con los IDs de todas las asignaciones de política creadas por este módulo."
  value = {
    require_tag_environment = azurerm_subscription_policy_assignment.require_tag_environment.id
    require_tag_project     = azurerm_subscription_policy_assignment.require_tag_project.id
    require_tag_owner       = azurerm_subscription_policy_assignment.require_tag_owner.id
    allowed_locations       = azurerm_subscription_policy_assignment.allowed_locations.id
    storage_shared_key      = azurerm_subscription_policy_assignment.storage_shared_key.id
  }
}
