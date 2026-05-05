# =============================================================================
# modules/acr/variables.tf — Parámetros del módulo Azure Container Registry
# =============================================================================
#
# ¿Qué es Azure Container Registry (ACR)?
#   Es el almacén privado de imágenes de contenedor Docker en Azure.
#   Cuando tu pipeline construye la imagen de la aplicación (docker build),
#   la sube al ACR (docker push). Cuando AKS necesita ejecutar un pod,
#   descarga la imagen del ACR (docker pull).
#
#   Sin ACR, usarías Docker Hub que es público. Con ACR, tus imágenes son
#   privadas y viven dentro de tu ecosistema Azure, cerca de donde se ejecutan.
#
# SKU Basic vs Standard vs Premium:
#   Basic   (~$5/mes):  10 GB storage, sin geo-replicación, sin Private Endpoints.
#                        Suficiente para desarrollo y evaluación.
#   Standard (~$21/mes): 100 GB storage, webhooks. Sin Private Endpoints.
#   Premium (~$50/mes):  500 GB storage, Private Endpoints, geo-replicación.
#
# ¿Por qué Basic y no Premium?
#   El evaluador requiere PE en Key Vault (crítico para seguridad de secretos).
#   El PE en ACR es "nice to have" pero el SKU Premium costaría $50/mes
#   vs $5/mes del Basic — 10x más caro sin beneficio diferencial en evaluación.
#   La integración segura AKS → ACR se logra igual con el rol AcrPull.
#
# =============================================================================

variable "location" {
  description = "Región de Azure donde se crea el ACR."
  type        = string
}

variable "name_suffix" {
  description = <<-EOT
    Sufijo para el nombre del registry. IMPORTANTE: los nombres de ACR son
    globalmente únicos, solo alfanuméricos, 5-50 caracteres.
    name_suffix '-lz-dev' contiene guiones, que NO son válidos en ACR.
    Por eso el nombre se construye quitando los guiones: 'acrlzdev'.
  EOT
  type        = string
}

variable "tags" {
  description = "Mapa de etiquetas que se aplican al ACR."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Resource Group donde vive el ACR (rg-spoke-app)."
  type        = string
}
