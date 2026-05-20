# =============================================================================
# modules/aks/outputs.tf — Valores que exporta el módulo AKS
# =============================================================================
#
# Outputs clave:
#   aks_id                      → para referencias en otros módulos o pipelines
#   aks_name                    → para scripts: az aks get-credentials --name <aks_name>
#   aks_fqdn                    → URL del API server de Kubernetes
#   kubelet_identity_object_id  → para asignar roles RBAC a los nodos
#                                  (Key Vault Secrets User, otros)
#   kube_config                 → credenciales para kubectl (sensitive)
#
# =============================================================================

output "aks_id" {
  description = "ARM Resource ID del cluster AKS."
  value       = azurerm_kubernetes_cluster.main.id
}

output "aks_name" {
  description = "Nombre del cluster AKS (ej: aks-lz-dev). Usar en: az aks get-credentials --name <aks_name> --resource-group <rg>"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_fqdn" {
  description = "FQDN del API server de Kubernetes. Es la URL a la que kubectl se conecta."
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "kubelet_identity_object_id" {
  description = "Object ID de la kubelet identity (Managed Identity de los nodos). Se usa para asignar roles RBAC adicionales (ej: Key Vault Secrets User)."
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

output "kube_config" {
  description = "Credenciales kubeconfig para conectarse al cluster con kubectl. SENSITIVE: no imprimir en logs."
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Outputs para Workload Identity Federation
#
# Para que un pod se autentique ante Azure usando Workload Identity, hace falta:
#   1. Una User-Assigned Managed Identity en Azure (creada en Fase 5)
#   2. Una Federation Credential que confíe en este OIDC issuer
#   3. Un ServiceAccount de Kubernetes con la anotación correcta
#
# Estos outputs se usan en los pasos 1 y 2 (federation credential).
# -----------------------------------------------------------------------------

output "oidc_issuer_url" {
  description = "URL del emisor OIDC del cluster AKS. Se usa para crear Federation Credentials que permiten que los pods se autentiquen ante Azure sin contraseñas."
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "user_node_pool_name" {
  description = "Nombre del user node pool (donde corren las aplicaciones del usuario)."
  value       = azurerm_kubernetes_cluster_node_pool.user.name
}
