# =============================================================================
# modules/acr/main.tf — Azure Container Registry (SKU Basic)
# =============================================================================
#
# ¿Por qué SKU Basic?
#   Free Trial budget: ~$200 de crédito. ACR Basic = ~$5/mes.
#   ACR Premium (necesario para Private Endpoint) = ~$50/mes.
#   La integración segura con AKS se logra con el rol AcrPull sobre la
#   kubelet identity del cluster, sin necesidad de Private Endpoint.
#
# admin_enabled = false:
#   Si admin_enabled = true, se crea un usuario/contraseña fijo para el registry.
#   Eso es una mala práctica de seguridad — las credenciales podrían filtrarse.
#   Con false, la autenticación es solo via Azure AD (Managed Identity o OIDC).
#   AKS usa su kubelet identity con el rol AcrPull — nunca necesita contraseña.
#
# Nombre del ACR:
#   Los nombres de ACR son globalmente únicos y solo admiten letras y números
#   (sin guiones ni puntos). El sufijo '-lz-dev' tiene guiones, por lo que
#   los eliminamos con replace(). Resultado: 'acrlzdev'.
#
# COSTO ESTIMADO: ~$5/mes (SKU Basic, 10 GB de almacenamiento incluido)
#
# =============================================================================

locals {
  # Elimina guiones del name_suffix para cumplir con las restricciones de ACR.
  # Ejemplo: "-lz-dev" → "lzdev" → "acr" + "lzdev" = "acrlzdev"
  acr_name = "acr${replace(var.name_suffix, "-", "")}"
}

resource "azurerm_container_registry" "main" {
  name                = local.acr_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic"

  # SEGURIDAD: Deshabilita el usuario admin del registry.
  # La autenticación es exclusivamente via Managed Identity (rol AcrPull).
  # El módulo aks asignará el rol AcrPull a la kubelet identity del cluster.
  admin_enabled = false

  tags = var.tags
}
