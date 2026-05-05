# =============================================================================
# modules/policy/variables.tf — Parámetros de entrada del módulo de políticas
# =============================================================================
#
# ¿Qué son las Azure Policies?
#   Son reglas automáticas que Azure aplica a los recursos. A diferencia de
#   los permisos RBAC (que controlan QUIÉN puede hacer algo), las policies
#   controlan QUÉ se puede crear y con qué configuración.
#
#   Ejemplo:
#     - RBAC: "Solo el equipo de infraestructura puede crear redes"
#     - Policy: "Todas las redes deben estar en eastus2 y tener la etiqueta Environment"
#
# Tipos de efecto (effect):
#   - Deny:  Bloquea la creación/modificación de recursos no conformes
#   - Audit: Solo registra la no-conformidad, no bloquea nada
#   - AuditIfNotExists: Audita si falta un recurso relacionado
#
# enforcement_mode en Terraform:
#   - true  (default): Aplica el efecto de la política (Deny = bloquea)
#   - false (DoNotEnforce): La política reporta conformidad pero no bloquea nada
#
# En este módulo usamos enforcement_mode = false para que las políticas
# sean visibles en el portal y reporten conformidad sin riesgo de bloquear
# operaciones existentes o futuras.
#
# =============================================================================

# -----------------------------------------------------------------------------
# Scope de aplicación
# -----------------------------------------------------------------------------

variable "subscription_id" {
  description = <<-EOT
    ARM ID completo de la suscripción donde se asignan las políticas.
    Formato: "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    En el main.tf raíz: data.azurerm_subscription.current.id
  EOT
  type        = string
}

# -----------------------------------------------------------------------------
# Configuración de políticas
# -----------------------------------------------------------------------------

variable "allowed_locations" {
  description = <<-EOT
    Lista de regiones de Azure permitidas para crear recursos.
    Cualquier recurso creado en una región no listada aquí será marcado
    como no conforme (o bloqueado si enforcement_mode = true).
    Debe incluir la región principal del proyecto (eastus2).
  EOT
  type        = list(string)
  default     = ["eastus2", "eastus", "brazilsouth"]
}

variable "required_tags" {
  description = <<-EOT
    Lista de nombres de etiquetas que deben existir en todos los recursos.
    La política "Require a tag on resources" se asigna una vez por cada
    tag requerido. El valor del tag no se valida, solo su presencia.
  EOT
  type        = list(string)
  default     = ["Environment", "Project", "Owner"]
}

variable "tags" {
  description = "Etiquetas que se aplican a las asignaciones de política."
  type        = map(string)
  default     = {}
}
