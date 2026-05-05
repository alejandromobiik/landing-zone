# =============================================================================
# modules/keyvault/main.tf — Azure Key Vault con Private Endpoint
# =============================================================================
#
# Recursos que crea este módulo:
#   1. azurerm_key_vault          — la caja fuerte de secretos
#   2. azurerm_private_endpoint   — punto de acceso privado en la VNet spoke
#   3. (el DNS zone group se configura dentro del private_endpoint)
#
# Arquitectura de acceso al vault:
#
#   AKS pod ──→ Private Endpoint ──→ Key Vault
#   (dentro de la VNet)  (subnet-private-endpoints)
#
#   La resolución DNS funciona así:
#     kv-lz-dev.vault.azure.net → kv-lz-dev.privatelink.vaultcore.azure.net
#     → 10.1.10.X (IP privada del Private Endpoint)
#
# ¿Por qué purge_protection_enabled = true?
#   Protección contra borrado accidental o malicioso. Un vault con purge
#   protection tarda 90 días en eliminarse definitivamente después de ser
#   "soft-deleted". En producción es obligatorio. Aquí lo activamos para
#   demostrar buenas prácticas.
#
# COSTO ESTIMADO:
#   Key Vault Standard: ~$0.03/10,000 operaciones. En dev = ~$0/mes.
#   Private Endpoint:   ~$0.01/hora (~$7.20/mes). COSTO PRINCIPAL.
#
# =============================================================================

# Nota: los nombres de Key Vault deben ser globalmente únicos en Azure,
# tener entre 3 y 24 caracteres, y contener solo letras, números y guiones.
# "kv" + name_suffix (-lz-dev) = "kv-lz-dev" (9 chars) ✓
resource "azurerm_key_vault" "main" {
  name                = "kv${var.name_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  # SEGURIDAD: Deshabilita el acceso desde internet.
  # Solo accesible desde la VNet a través del Private Endpoint.
  public_network_access_enabled = false

  # Protección contra eliminación accidental.
  # El vault pasará por un período de "soft delete" de 90 días antes de
  # eliminarse permanentemente. Fundamental en producción.
  purge_protection_enabled = true

  # Días que se conservan los objetos borrados antes de eliminación permanente.
  soft_delete_retention_days = 7

  # ¿Quién puede acceder a los secretos?
  # Con rbac_authorization_enabled = true, el acceso se gestiona con roles
  # de Azure RBAC (como "Key Vault Secrets User") en lugar de Access Policies.
  # RBAC es el modelo moderno y recomendado — más granular y auditable.
  rbac_authorization_enabled = true

  # No se crean network_acls: la política es deny-all desde internet
  # (public_network_access_enabled = false). El acceso es solo por PE.

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Private Endpoint — punto de acceso privado en la subnet del spoke
#
# ¿Qué hace exactamente el Private Endpoint?
#   1. Crea una NIC (Network Interface Card) en la subnet de Private Endpoints
#   2. Esa NIC recibe una IP privada (ej: 10.1.10.4)
#   3. La Private DNS Zone registra: kv-lz-dev.privatelink.vaultcore.azure.net → 10.1.10.4
#   4. Desde cualquier VM/pod dentro de la VNet spoke (o hub via peering),
#      la resolución DNS devuelve la IP privada → tráfico nunca sale a internet
#
# "vault" es el subresource_name para Key Vault.
# Otros servicios tienen nombres diferentes (ej: "blob" para Storage, "registry" para ACR).
# -----------------------------------------------------------------------------
resource "azurerm_private_endpoint" "keyvault" {
  name                = "pe-kv${var.name_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnet_private_endpoints_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-kv${var.name_suffix}"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  # DNS zone group: registra automáticamente el PE en la Private DNS Zone.
  # Cuando se crea el PE, Azure escribe el registro A en la zona DNS del hub.
  # Esto hace que kv-lz-dev.vault.azure.net resuelva a la IP privada del PE.
  private_dns_zone_group {
    name                 = "dns-group-kv${var.name_suffix}"
    private_dns_zone_ids = [var.private_dns_zone_keyvault_id]
  }
}
