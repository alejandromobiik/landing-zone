# =============================================================================
# modules/monitoring/main.tf — Log Analytics + Defender + Diagnostic Settings (Hub/KV/NSG)
# =============================================================================
#
# Este módulo agrupa la observabilidad "central" que NO puede vivir en el módulo
# AKS sin crear dependencias circulares:
#   - El workspace LAW debe existir ANTES que AKS (oms_agent).
#   - Los Diagnostic Settings del Key Vault y los NSGs solo necesitan el LAW + IDs
#     de esos recursos — sin referencia al cluster.
#
# Los Diagnostic Settings del AKS se declaran en main.tf raíz (después del módulo
# aks) porque AKS ya depende del LAW — meter diag AKS aquí crearía un ciclo.
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

# -----------------------------------------------------------------------------
# Microsoft Defender for Cloud — planes a nivel de suscripción (PDF §2)
#
# El PDF exige habilitar planes para Servers (VMs / nodos), Containers y Key Vault.
# En Terraform cada uno es un recurso separado con resource_type distinto.
#
# Free Trial: cargos pueden aparecer como $0 durante el período promocional según
# la promoción activa en tu suscripción.
# -----------------------------------------------------------------------------

resource "azurerm_security_center_subscription_pricing" "servers" {
  tier          = "Standard"
  resource_type = "VirtualMachines"
  # Azure asigna subplan por defecto (p. ej. P2); omitirlo fuerza replace en cada apply.
  subplan = "P2"
}

resource "azurerm_security_center_subscription_pricing" "containers" {
  tier          = "Standard"
  resource_type = "Containers"
}

resource "azurerm_security_center_subscription_pricing" "keyvault" {
  tier          = "Standard"
  resource_type = "KeyVaults"
  subplan       = "PerKeyVault"
}

# -----------------------------------------------------------------------------
# Diagnostic Settings → Log Analytics (PDF checklist: KV + NSGs)
# -----------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  name                       = "diag-kv${var.name_suffix}"
  target_resource_id         = var.keyvault_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
}

resource "azurerm_monitor_diagnostic_setting" "nsg_hub" {
  name                       = "diag-nsg-hub${var.name_suffix}"
  target_resource_id         = var.nsg_hub_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "NetworkSecurityGroupEvent"
  }

  enabled_log {
    category = "NetworkSecurityGroupRuleCounter"
  }
}

resource "azurerm_monitor_diagnostic_setting" "nsg_spoke" {
  name                       = "diag-nsg-spoke${var.name_suffix}"
  target_resource_id         = var.nsg_spoke_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "NetworkSecurityGroupEvent"
  }

  enabled_log {
    category = "NetworkSecurityGroupRuleCounter"
  }
}
