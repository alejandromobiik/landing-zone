# =============================================================================
# modules/policy/main.tf — Asignaciones de Azure Policy a nivel de suscripción
# =============================================================================
#
# Este módulo asigna 5 políticas builtin de Azure:
#
#   1. require_tag_environment  → Tag "Environment" obligatorio en todos los recursos
#   2. require_tag_project      → Tag "Project" obligatorio en todos los recursos
#   3. require_tag_owner        → Tag "Owner" obligatorio en todos los recursos
#   4. allowed_locations        → Solo permite crear recursos en regiones autorizadas
#   5. storage_deny_public      → Audita Storage Accounts con acceso público habilitado
#
# ¿Por qué enforce = false?
#   Permite que las políticas sean visibles en el portal y reporten conformidad
#   sin riesgo de bloquear operaciones. Los recursos existentes ya cumplen
#   (tienen los 3 tags y están en eastus2), pero esta configuración es más
#   segura para un entorno de aprendizaje.
#
# ¿Por qué políticas builtin y no custom?
#   Las políticas builtin están mantenidas por Microsoft, auditadas, y cubren
#   los casos más comunes. Crear una policy custom requiere definir la regla
#   completa en JSON, lo que añade complejidad sin beneficio adicional para
#   estos casos.
#
# IDs de las políticas builtin usadas:
#   96670d01-0a4d-4649-9c89-2d3abc0a5025 → "Require a tag on resources"
#   e56962a6-4747-49cd-b67b-bf8b01975c4c → "Allowed locations"
#   b2982f36-99f2-4db5-8eff-283140c09693 → "Storage accounts should prevent shared key access"
#
# COSTO: $0 — las asignaciones de Azure Policy no tienen costo.
#
# =============================================================================

# -----------------------------------------------------------------------------
# POLÍTICA 1: Tags obligatorios — Environment
#
# Builtin: "Require a tag on resources"
# ID: 96670d01-0a4d-4649-9c89-2d3abc0a5025
#
# Todos los recursos de Terraform en este proyecto reciben el tag "Environment"
# a través de local.common_tags → son conformes automáticamente.
# -----------------------------------------------------------------------------
resource "azurerm_subscription_policy_assignment" "require_tag_environment" {
  name                 = "require-tag-environment"
  subscription_id      = var.subscription_id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025"
  display_name         = "LZ: Require tag Environment on resources"
  description          = "Todos los recursos deben tener la etiqueta 'Environment'. Asignada por la Landing Zone para cumplimiento de tagging."
  enforce              = false

  parameters = jsonencode({
    tagName = { value = "Environment" }
  })

  non_compliance_message {
    content = "El recurso no tiene la etiqueta 'Environment'. Agrega tags al crearlo con Terraform usando var.tags."
  }
}

# -----------------------------------------------------------------------------
# POLÍTICA 2: Tags obligatorios — Project
#
# Misma definición builtin, distinto parámetro.
# El tag "Project" existe en local.common_tags → conformes automáticamente.
# -----------------------------------------------------------------------------
resource "azurerm_subscription_policy_assignment" "require_tag_project" {
  name                 = "require-tag-project"
  subscription_id      = var.subscription_id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025"
  display_name         = "LZ: Require tag Project on resources"
  description          = "Todos los recursos deben tener la etiqueta 'Project'. Asignada por la Landing Zone para cumplimiento de tagging."
  enforce              = false

  parameters = jsonencode({
    tagName = { value = "Project" }
  })

  non_compliance_message {
    content = "El recurso no tiene la etiqueta 'Project'. Agrega tags al crearlo con Terraform usando var.tags."
  }
}

# -----------------------------------------------------------------------------
# POLÍTICA 3: Tags obligatorios — Owner
#
# El tag "Owner" existe en tags_default en variables.tf → conformes.
# -----------------------------------------------------------------------------
resource "azurerm_subscription_policy_assignment" "require_tag_owner" {
  name                 = "require-tag-owner"
  subscription_id      = var.subscription_id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025"
  display_name         = "LZ: Require tag Owner on resources"
  description          = "Todos los recursos deben tener la etiqueta 'Owner'. Asignada por la Landing Zone para cumplimiento de tagging."
  enforce              = false

  parameters = jsonencode({
    tagName = { value = "Owner" }
  })

  non_compliance_message {
    content = "El recurso no tiene la etiqueta 'Owner'. Agrega tags al crearlo con Terraform usando var.tags."
  }
}

# -----------------------------------------------------------------------------
# POLÍTICA 4: Ubicaciones permitidas
#
# Builtin: "Allowed locations"
# ID: e56962a6-4747-49cd-b67b-bf8b01975c4c
#
# Solo permite crear recursos en las regiones de var.allowed_locations.
# Todos los recursos de esta LZ están en eastus2 → conformes.
#
# NOTA: Esta política se aplica a recursos (no a Resource Groups).
#       Los RGs tienen su propia política builtin separada.
# -----------------------------------------------------------------------------
resource "azurerm_subscription_policy_assignment" "allowed_locations" {
  name                 = "allowed-locations-lz"
  subscription_id      = var.subscription_id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
  display_name         = "LZ: Allowed locations for resources"
  description          = "Solo se permiten recursos en las regiones autorizadas por la Landing Zone."
  enforce              = false

  parameters = jsonencode({
    listOfAllowedLocations = { value = var.allowed_locations }
  })

  non_compliance_message {
    content = "El recurso está en una región no autorizada. Usa solo las regiones listadas en var.allowed_locations."
  }
}

# -----------------------------------------------------------------------------
# POLÍTICA 5: Storage Accounts — acceso público restringido
#
# Builtin: "Storage accounts should prevent shared key access"
# ID: b2982f36-99f2-4db5-8eff-283140c09693
#
# Audita Storage Accounts que permiten acceso mediante Shared Key (clave de cuenta).
# Best practice: usar Azure AD (Entra ID) para autenticarse, no claves de cuenta.
# El Storage Account del tfstate (stlztf86c66635) usa Entra ID via OIDC → conforme.
# -----------------------------------------------------------------------------
resource "azurerm_subscription_policy_assignment" "storage_shared_key" {
  name                 = "storage-deny-shared-key-lz"
  subscription_id      = var.subscription_id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54"
  display_name         = "LZ: Storage accounts should disable public network access"
  description          = "Los Storage Accounts no deben permitir acceso público a la red. Solo acceso desde redes autorizadas."
  enforce              = false

  non_compliance_message {
    content = "El Storage Account tiene acceso público a la red habilitado. Configura network_rules con default_action = 'Deny'."
  }
}
