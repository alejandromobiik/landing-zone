# =============================================================================
# modules/aks/variables.tf — Parámetros del módulo Azure Kubernetes Service
# =============================================================================
#
# ¿Qué es AKS?
#   Azure Kubernetes Service es el servicio de Kubernetes gestionado de Azure.
#   Kubernetes es el sistema de orquestación de contenedores más usado del mundo:
#   toma las imágenes del ACR, las despliega como "pods" (contenedores en
#   ejecución), gestiona el escalado automático, los reinicios tras fallos, etc.
#
#   Con AKS, Azure gestiona el "control plane" (el cerebro de Kubernetes)
#   de forma gratuita. Tú solo pagas por los nodos worker (las VMs donde
#   corren tus pods).
#
# SKU Free vs Standard:
#   Free:     Control plane gratuito. SLA del 99.5%. Para dev/eval.
#   Standard: Control plane ~$73/mes. SLA del 99.95%. Para producción.
#   → Usamos Free: $0 por el control plane.
#
# Nodo worker:
#   Standard_B2s: 2 vCPU, 4 GB RAM. ~$0.048/hora = ~$34/mes.
#   Es el mínimo viable para correr AKS con pods reales.
#   IMPORTANTE: parar el cluster cuando no se trabaje (az aks stop).
#
# =============================================================================

variable "location" {
  description = "Región de Azure donde se crea el cluster AKS."
  type        = string
}

variable "name_suffix" {
  description = "Sufijo para el nombre del cluster. Ejemplo: '-lz-dev'. Resulta en 'aks-lz-dev'."
  type        = string
}

variable "tags" {
  description = "Mapa de etiquetas que se aplican al cluster AKS."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Resource Group donde vive el cluster AKS (rg-spoke-app)."
  type        = string
}

# -----------------------------------------------------------------------------
# Networking — recibe outputs del módulo network
# -----------------------------------------------------------------------------

variable "subnet_aks_id" {
  description = "ID de la subnet donde se despliegan los nodos de AKS (subnet-aks, 10.1.0.0/22). Viene de module.network.subnet_aks_id."
  type        = string
}

# -----------------------------------------------------------------------------
# Monitoring — recibe outputs del módulo monitoring
# -----------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  description = <<-EOT
    ARM Resource ID del Log Analytics Workspace donde AKS envía logs y métricas.
    Requerido por el add-on oms_agent (Monitor add-on).
    Viene de module.monitoring.workspace_resource_id.
  EOT
  type        = string
}

# -----------------------------------------------------------------------------
# Integración con ACR — recibe output del módulo acr
# -----------------------------------------------------------------------------

variable "acr_id" {
  description = "ARM Resource ID del ACR. AKS necesita este ID para que Terraform asigne el rol AcrPull a su kubelet identity y pueda descargar imágenes sin contraseña."
  type        = string
}

# -----------------------------------------------------------------------------
# Configuración del cluster
# -----------------------------------------------------------------------------

variable "kubernetes_version" {
  description = <<-EOT
    Versión de Kubernetes. Usa 'az aks get-versions --location eastus2' para ver
    las disponibles. AKS soporta N-2 versiones menores.
    No especificamos version para que Azure elija la más reciente disponible.
  EOT
  type        = string
  default     = null
}

variable "node_vm_size" {
  description = "Tamaño de VM para los nodos worker. Standard_D2s_v3 (2 vCPU, 8 GB) es el mínimo disponible en suscripciones Free Trial en eastus2. ~$70/mes. PARAR cuando no se use: az aks stop."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "node_count" {
  description = "Número de nodos en el default node pool (system). Mínimo 1. Cada nodo es una VM con costo por hora. Mantener en 1 para dev."
  type        = number
  default     = 1

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 5
    error_message = "node_count debe estar entre 1 y 5 para entornos de desarrollo."
  }
}

# -----------------------------------------------------------------------------
# Configuración del USER node pool
#
# El PDF de la evaluación exige "AKS privado con node pool de sistema y de usuario".
# El system pool (default_node_pool) corre los componentes internos de Kubernetes
# (CoreDNS, metrics-server, etc.). El user pool corre TUS aplicaciones.
# Separarlos evita que tu app le robe CPU/RAM al sistema y lo deje inestable.
#
# Costo: 1 nodo extra Standard_D2s_v3 ≈ $70/mes adicional. Total con system: ~$140/mes.
# RECUERDA: parar el cluster con `az aks stop` cuando no trabajes para ahorrar.
# -----------------------------------------------------------------------------

variable "user_node_vm_size" {
  description = "Tamaño de VM para los nodos del user node pool. Por defecto el mismo que el system pool. En suscripciones Free Trial usar Standard_D2s_v3."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "user_node_count" {
  description = "Número de nodos en el user node pool. Mínimo 1. Mantener en 1 para dev."
  type        = number
  default     = 1

  validation {
    condition     = var.user_node_count >= 1 && var.user_node_count <= 5
    error_message = "user_node_count debe estar entre 1 y 5 para entornos de desarrollo."
  }
}
