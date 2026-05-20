# =============================================================================
# modules/aks/main.tf — Azure Kubernetes Service cluster
# =============================================================================
#
# Recursos que crea este módulo:
#   1. azurerm_kubernetes_cluster              — el cluster AKS privado
#   2. azurerm_kubernetes_cluster_node_pool    — node pool de USUARIO (apps)
#   3. azurerm_role_assignment.acr_pull        — AcrPull para la kubelet identity
#
# El PDF de la evaluación exige (sección 3.3):
#   • "AKS privado con node pool de sistema y de usuario"
#   • "integrado con ACR mediante managed identity"
#   • "Los secretos se consumen desde el workload vía CSI driver o workload identity"
#   • "Workload Identity Federation (OIDC) entre GitHub y Azure"
#
# Cómo lo cumple este módulo:
#   - private_cluster_enabled = true        → el API server NO es accesible desde internet
#   - default_node_pool (mode = system)     → corre los componentes internos de Kubernetes
#   - azurerm_kubernetes_cluster_node_pool  → node pool USER para tus aplicaciones
#   - oidc_issuer_enabled = true            → habilita el emisor OIDC del cluster
#   - workload_identity_enabled = true      → permite que pods se autentiquen ante Azure
#   - role_assignment AcrPull               → AKS descarga imágenes del ACR sin contraseña
#
# Arquitectura de identidades:
#   - Control plane: SystemAssigned identity (Azure la crea automáticamente)
#   - Nodos worker: kubelet identity (UserAssigned, también auto-creada por AKS)
#   - La kubelet identity recibe el rol AcrPull sobre el ACR
#
# DNS privado del cluster (private_dns_zone_id = "System"):
#   AKS crea y administra automáticamente una Private DNS Zone para el API
#   server en el Resource Group MC_<rg>_<aks>_<region> (gestionado por AKS).
#   La zona privatelink.eastus2.azmk8s.io del hub queda como demostración del
#   patrón hub-spoke pero NO se usa para este cluster (cero costo).
#
# COSTO ESTIMADO:
#   - Control plane: $0 (SKU Free, SLA 99.5%)
#   - 1 nodo system Standard_D2s_v3: ~$70/mes (~$2.30/día)
#   - 1 nodo user   Standard_D2s_v3: ~$70/mes (~$2.30/día)
#   - TOTAL: ~$140/mes con cluster encendido 24/7
#
#   PARAR cuando no trabajes para ahorrar:
#     az aks stop  --name aks-lz-dev --resource-group rg-spoke-app-lz-dev
#     az aks start --name aks-lz-dev --resource-group rg-spoke-app-lz-dev
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

  # ---------------------------------------------------------------------------
  # CLUSTER PRIVADO — exigencia del PDF (sección 3.3)
  #
  # private_cluster_enabled = true:
  #   El API server de Kubernetes (el "cerebro" del cluster) NO es accesible
  #   desde internet. Solo se puede llegar a él desde:
  #     - dentro de la VNet spoke (donde están los nodos)
  #     - desde el hub vía VNet peering
  #     - desde una jumpbox / VPN / Bastion
  #     - desde el comando `az aks command invoke` (tunneliza por Azure ARM)
  #
  # private_dns_zone_id = "System":
  #   AKS crea y administra automáticamente la Private DNS Zone que resuelve
  #   el FQDN del API server a la IP privada. Es la opción más simple — no
  #   requiere User-Assigned Managed Identity ni asignaciones extra de roles.
  #
  # NOTA: cambiar private_cluster_enabled requiere RECREAR el cluster.
  # ---------------------------------------------------------------------------
  private_cluster_enabled = true
  private_dns_zone_id     = "System"

  # ---------------------------------------------------------------------------
  # WORKLOAD IDENTITY FEDERATION — exigencia del PDF (sección 3.2)
  #
  # oidc_issuer_enabled = true:
  #   Habilita un emisor de tokens OIDC en el cluster. Este emisor permite que:
  #     - GitHub Actions se autentique ante Azure sin contraseñas (vía OIDC)
  #     - los pods de la aplicación obtengan tokens de Azure usando una
  #       Managed Identity (sin almacenar credenciales en el contenedor)
  #
  # workload_identity_enabled = true:
  #   Habilita el webhook de Workload Identity en AKS. Cuando un pod tiene la
  #   anotación `azure.workload.identity/use: "true"`, AKS le inyecta un token
  #   OIDC que el pod puede intercambiar por un token de Azure AD para acceder
  #   a Key Vault, Storage, etc. SIN cadenas de conexión ni secretos.
  #
  # Estos dos parámetros juntos son la base de la "Workload Identity Federation"
  # que pide el PDF. La configuración de las federation credentials específicas
  # del workload se hace en la Fase 5 del plan de trabajo.
  # ---------------------------------------------------------------------------
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # ---------------------------------------------------------------------------
  # SYSTEM NODE POOL — corre los componentes internos de Kubernetes
  #
  # Lo que vive aquí: CoreDNS, metrics-server, konnectivity-agent, etc.
  # NO debe correr aplicaciones del usuario — para eso está el user node pool.
  #
  # El "taint" CriticalAddonsOnly se podría agregar para garantizar que solo
  # pods del sistema corran aquí, pero en dev lo dejamos sin taint para
  # simplicidad (puedes agregarlo después con: only_critical_addons_enabled).
  # ---------------------------------------------------------------------------
  default_node_pool {
    name           = "system"
    node_count     = var.node_count
    vm_size        = var.node_vm_size
    vnet_subnet_id = var.subnet_aks_id

    # Tipo de agente: VirtualMachineScaleSets permite escalar nodos.
    type = "VirtualMachineScaleSets"

    # Desactiva el auto-scaler para mantener costos predecibles en dev.
    auto_scaling_enabled = false

    # Alineado con lo que devuelve la API de AKS (evita drift y updates innecesarios).
    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }

    tags = var.tags
  }

  # ---------------------------------------------------------------------------
  # IDENTIDAD del control plane
  #
  # SystemAssigned: Azure crea y gestiona la identidad automáticamente.
  # La kubelet identity (de los nodos worker) se crea aparte como UserAssigned
  # y se expone en azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  # El PDF exige "Managed Identities (system y user-assigned)" — el cluster
  # tiene SystemAssigned (control plane) Y kubelet UserAssigned (nodos),
  # cumpliendo ambas categorías.
  # ---------------------------------------------------------------------------
  identity {
    type = "SystemAssigned"
  }

  # ---------------------------------------------------------------------------
  # OBSERVABILIDAD — Container Insights vía oms_agent
  #
  # Envía métricas y logs del cluster al Log Analytics Workspace.
  # Sin este add-on el workspace estaría vacío para AKS.
  # Habilita: métricas de CPU/RAM por pod, logs de contenedores, eventos
  # del kube-apiserver, alertas de salud del cluster.
  # ---------------------------------------------------------------------------
  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  # ---------------------------------------------------------------------------
  # RED — Azure CNI
  #
  # network_plugin = "azure": cada pod recibe una IP real de la subnet de AKS.
  # Esto permite que las Private DNS Zones y los NSGs vean el tráfico de los
  # pods directamente. Es el plugin recomendado para landing zones con red
  # privada y Private Endpoints.
  #
  # network_policy = "azure": reglas de red a nivel de pod (microsegmentación).
  # Permite definir NetworkPolicies de Kubernetes que Azure aplica a nivel de
  # red, no solo a nivel de software.
  # ---------------------------------------------------------------------------
  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
  }

  tags = var.tags
}

# =============================================================================
# USER NODE POOL — donde corren TUS aplicaciones
#
# El PDF exige "node pool de sistema y de usuario". Esto es el de usuario:
#   - mode = "User": no recibe pods del sistema de Kubernetes
#   - corre solo los workloads que TÚ despliegues (Fase 8 del plan)
#   - usa la misma subnet que el system pool (subnet-aks)
#
# Separar pools tiene dos ventajas:
#   1. Tu app no compite por CPU/RAM con CoreDNS/metrics-server
#   2. Si un día quieres escalar solo apps (no sistema), escalas este pool
#
# Costo adicional: 1 nodo Standard_D2s_v3 ≈ $70/mes.
# Si paras el cluster con `az aks stop`, se detienen ambos pools.
# =============================================================================
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id

  vm_size        = var.user_node_vm_size
  node_count     = var.user_node_count
  vnet_subnet_id = var.subnet_aks_id

  mode = "User"

  # Sin auto-scaling para tener costos predecibles en dev.
  auto_scaling_enabled = false

  upgrade_settings {
    max_surge                     = "10%"
    drain_timeout_in_minutes      = 0
    node_soak_duration_in_minutes = 0
  }

  tags = var.tags
}

# =============================================================================
# ROL AcrPull — AKS descarga imágenes del ACR sin contraseña
#
# ¿Cómo funciona?
#   1. AKS crea automáticamente una "kubelet identity" (Managed Identity
#      UserAssigned) para los nodos worker al crear el cluster.
#   2. Asignamos el rol AcrPull a esa kubelet identity sobre el scope del ACR.
#   3. Cuando un pod necesita una imagen, los nodos se autentican ante el ACR
#      usando la kubelet identity — sin contraseñas, sin tokens, sin secretos.
#
# Esto cumple el ítem del checklist del PDF:
#   "ACR integrado con AKS por managed identity (sin admin user)"
# =============================================================================
resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
