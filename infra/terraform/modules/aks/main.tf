# =============================================================================
# modules/aks/main.tf — Azure Kubernetes Service cluster
# =============================================================================
#
# Recursos que crea este módulo:
#   1. azurerm_kubernetes_cluster — el cluster AKS en sí
#   2. azurerm_role_assignment    — AcrPull para la kubelet identity sobre el ACR
#
# Arquitectura de identidades:
#   - El cluster tiene una "system-assigned identity" (control plane).
#   - Los nodos tienen una "kubelet identity" (user-assigned, auto-creada por AKS).
#   - La kubelet identity necesita AcrPull sobre el ACR para descargar imágenes.
#   - Terraform asigna ese rol automáticamente tras conocer el ID de la kubelet identity.
#
# ¿Por qué identity { type = "SystemAssigned" }?
#   AKS puede usar una identidad propia (SystemAssigned) o una pre-existente
#   (UserAssigned). SystemAssigned es más simple: Azure la crea y gestiona
#   automáticamente. La kubelet identity (para los nodos) también se crea
#   automáticamente y se expone en kubelet_identity[0].object_id.
#
# ¿Qué es oms_agent?
#   OMS (Operations Management Suite) es el add-on que envía métricas y logs
#   del cluster al Log Analytics Workspace. Sin él, el workspace estaría vacío.
#   Habilita: métricas de CPU/RAM de pods, logs de contenedores, eventos del
#   kube-apiserver, alertas de salud del cluster.
#
# ¿Por qué network_plugin = "azure"?
#   Con el plugin "azure" (Azure CNI), cada pod recibe una IP real de la subnet.
#   Esto permite que las Private DNS Zones y los NSGs vean el tráfico de los pods
#   directamente. Es el plugin recomendado para landing zones con red privada.
#
# COSTO ESTIMADO:
#   Control plane: $0 (SKU Free)
#   1 nodo Standard_B2s: ~$34/mes (~$1.14/día)
#   → PARAR cuando no se trabaje: az aks stop --name aks-lz-dev --resource-group rg-spoke-app-lz-dev
#
# =============================================================================

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks${var.name_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = "aks${replace(var.name_suffix, "-", "")}"

  # Versión de Kubernetes — null = la versión estable más reciente disponible
  kubernetes_version = var.kubernetes_version

  # SKU Free = control plane gratuito con SLA del 99.5%
  # Para producción usar "Standard" (~$73/mes, SLA 99.95%)
  sku_tier = "Free"

  # Default node pool — los nodos worker donde corren los pods
  default_node_pool {
    name           = "system"
    node_count     = var.node_count
    vm_size        = var.node_vm_size
    vnet_subnet_id = var.subnet_aks_id

    # Tipo de agente: VirtualMachineScaleSets permite escalar nodos.
    # AvailabilityZones no disponible en B2s en algunas regiones.
    type = "VirtualMachineScaleSets"

    # Desactiva el auto-scaler para mantener costos predecibles en dev.
    auto_scaling_enabled = false
  }

  # Identidad del control plane del cluster.
  # SystemAssigned: Azure crea y gestiona la identidad automáticamente.
  # La kubelet identity (para los nodos) se crea aparte y se expone en
  # azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  identity {
    type = "SystemAssigned"
  }

  # Add-on de monitoreo: envía logs y métricas al Log Analytics Workspace.
  # Habilita: Container Insights, métricas de pods, alertas de salud.
  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  # Red: Azure CNI — cada pod recibe IP real de la subnet.
  # network_policy = "azure": reglas de red a nivel de pod (microsegmentación).
  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Rol AcrPull — permite que AKS descargue imágenes del ACR sin contraseña
#
# ¿Cómo funciona?
#   1. AKS crea automáticamente una "kubelet identity" (Managed Identity)
#      para los nodos worker al crear el cluster.
#   2. Asignamos el rol AcrPull a esa kubelet identity sobre el scope del ACR.
#   3. Cuando un pod necesita una imagen, los nodos se autentican ante el ACR
#      usando la kubelet identity — sin contraseñas, sin tokens, sin secretos.
#
# azurerm_role_assignment.acr_pull depende implícitamente del cluster (ya que
# usa su kubelet_identity), así que Terraform lo crea después del cluster.
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
