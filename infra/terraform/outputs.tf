# =============================================================================
# outputs.tf — Valores que Terraform expone al terminar
# =============================================================================
#
# ¿Qué es un output en Terraform?
#   Un output es un valor que Terraform imprime en pantalla al terminar
#   "terraform apply". Es útil para ver datos clave sin tener que buscarlos
#   en el portal de Azure.
#
#   También sirven para comunicar datos entre módulos: el output de un
#   módulo puede ser el input (variable) de otro módulo.
#   Ejemplo: el módulo "network" exporta el ID de la subnet de AKS, y el
#   módulo "aks" lo recibe como variable para saber dónde colocar los nodos.
#
# ¿Por qué `sensitive = true` en algunos outputs?
#   Terraform marca ese valor como sensible y no lo imprime en los logs
#   del pipeline. Aun así el valor está en el tfstate — por eso el tfstate
#   debe estar en un Storage Account privado (ya configurado en backend.tf).
#
# NOTA: Los outputs de infraestructura real (IDs de AKS, ACR, etc.) se
#   agregarán en los pasos 4, 5 y 6 cuando se creen los módulos correspondientes.
#   Este archivo solo define los outputs de los data sources del paso 1,
#   que ya están disponibles sin necesidad de crear recursos nuevos.
#
# =============================================================================

# -----------------------------------------------------------------------------
# OUTPUT: subscription_id
#
# ID de la suscripción Azure activa donde Terraform está operando.
# Útil para confirmar visualmente que estás en la suscripción correcta
# antes de hacer un "terraform apply" que crea recursos con costo.
# -----------------------------------------------------------------------------
output "subscription_id" {
  description = "ID de la suscripción Azure donde se despliega la infraestructura."
  value       = data.azurerm_subscription.current.subscription_id
}

# -----------------------------------------------------------------------------
# OUTPUT: subscription_display_name
#
# Nombre legible de la suscripción (ej: "Azure subscription 1").
# Ayuda a confirmar la suscripción activa de forma más descriptiva que el ID.
# -----------------------------------------------------------------------------
output "subscription_display_name" {
  description = "Nombre visible de la suscripción Azure activa."
  value       = data.azurerm_subscription.current.display_name
}

# -----------------------------------------------------------------------------
# OUTPUT: tenant_id
#
# ID del tenant (directorio) de Azure Entra ID donde vive la suscripción.
# Necesario para configurar Key Vault access policies y Federation Credentials.
# Se marca sensitive porque es un dato de identidad que no debería
# aparecer en logs públicos del pipeline.
# -----------------------------------------------------------------------------
output "tenant_id" {
  description = "ID del tenant de Azure Entra ID."
  value       = data.azurerm_client_config.current.tenant_id
  sensitive   = true
}

# -----------------------------------------------------------------------------
# OUTPUT: terraform_caller_object_id
#
# Object ID (ID único interno de Entra ID) de quien está corriendo Terraform.
# En local: tu usuario personal.
# En pipeline: el Service Principal sp-landing-zone-cicd.
#
# ¿Para qué sirve?
#   Se usa para asignar permisos en Key Vault. Por ejemplo, para que la
#   identidad que corre Terraform pueda leer/escribir secretos durante el deploy,
#   necesitas asignarle el rol "Key Vault Secrets Officer" usando este Object ID.
# -----------------------------------------------------------------------------
output "terraform_caller_object_id" {
  description = "Object ID de la identidad que ejecuta Terraform (usuario local o Service Principal en pipeline)."
  value       = data.azurerm_client_config.current.object_id
  sensitive   = true
}

# -----------------------------------------------------------------------------
# OUTPUT: location
# OUTPUT: environment
# OUTPUT: project_name
#
# Reflejan los valores de las variables globales para confirmar
# con qué configuración se ejecutó el plan/apply.
# Útil cuando el pipeline guarda los outputs en un artefacto para auditoría.
# -----------------------------------------------------------------------------
output "location" {
  description = "Región de Azure donde se despliega la infraestructura."
  value       = var.location
}

output "environment" {
  description = "Entorno de despliegue (dev, staging, prod)."
  value       = var.environment
}

output "project_name" {
  description = "Nombre corto del proyecto usado como prefijo en los nombres de recursos."
  value       = var.project_name
}
