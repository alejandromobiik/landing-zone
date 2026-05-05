# =============================================================================
# modules/network/main.tf — Red hub-spoke completa
# =============================================================================
#
# ¿Qué crea este módulo?
#
#   VNet Hub (10.0.0.0/16) — en rg-network-hub-lz-dev
#   ├── subnet-private-dns (10.0.1.0/24)   → recursos de DNS privado
#   └── NSG hub                             → bloquea tráfico de internet
#
#   VNet Spoke (10.1.0.0/16) — en rg-spoke-app-lz-dev
#   ├── subnet-aks (10.1.1.0/22)           → nodos del clúster AKS
#   ├── subnet-private-endpoints (10.1.10.0/24) → ACR, Key Vault
#   └── NSG spoke                           → least-privilege
#
#   VNet Peering (bidireccional hub ↔ spoke)
#   └── permite que los recursos de ambas VNets se comuniquen
#
#   Private DNS Zones (en rg-network-hub-lz-dev)
#   ├── privatelink.azurecr.io              → para ACR
#   ├── privatelink.vaultcore.azure.net     → para Key Vault
#   └── privatelink.eastus2.azmk8s.io       → para AKS
#
#   DNS Zone Links (vincula cada zona al spoke para que resuelva nombres)
#
# ¿Por qué hub-spoke?
#   El hub centraliza servicios compartidos (DNS privado, seguridad).
#   El spoke aloja las cargas de trabajo (AKS, ACR, Key Vault).
#   Separarlos limita el radio de impacto: un problema en el spoke
#   no afecta los servicios centrales del hub.
#
# =============================================================================

# =============================================================================
# VNet HUB
# =============================================================================

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub${var.name_suffix}"
  location            = var.location
  resource_group_name = var.hub_resource_group_name
  address_space       = [var.hub_vnet_cidr]
  tags                = var.tags
}

# Subnet para recursos de DNS privado dentro del hub
resource "azurerm_subnet" "hub_private_dns" {
  name                 = "subnet-private-dns"
  resource_group_name  = var.hub_resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.hub_subnet_private_dns_cidr]
}

# =============================================================================
# NSG HUB — Firewall de la VNet hub
#
# Regla de diseño: bloquear todo el tráfico de internet entrante al hub.
# El hub solo debe recibir tráfico desde el spoke (via peering) y
# desde servicios internos de Azure (AzureLoadBalancer, etc.).
# =============================================================================

resource "azurerm_network_security_group" "hub" {
  name                = "nsg-hub${var.name_suffix}"
  location            = var.location
  resource_group_name = var.hub_resource_group_name
  tags                = var.tags

  # Denegar todo el tráfico de internet entrante al hub.
  # La prioridad más baja (100) gana sobre reglas con mayor número.
  # "DenyAllInbound" de Azure (prioridad 65500) ya existe por defecto,
  # pero esta regla explícita documenta la intención de diseño.
  security_rule {
    name                       = "DenyInternetInbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

# Asociar el NSG hub a la subnet del hub
resource "azurerm_subnet_network_security_group_association" "hub_private_dns" {
  subnet_id                 = azurerm_subnet.hub_private_dns.id
  network_security_group_id = azurerm_network_security_group.hub.id
}

# =============================================================================
# VNet SPOKE
# =============================================================================

resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-spoke${var.name_suffix}"
  location            = var.location
  resource_group_name = var.spoke_resource_group_name
  address_space       = [var.spoke_vnet_cidr]
  tags                = var.tags
}

# Subnet para los nodos de AKS.
# /22 = 1024 IPs. AKS necesita IPs para nodos y para los pods
# (cuando se usa Azure CNI, cada pod recibe una IP de la subnet).
resource "azurerm_subnet" "spoke_aks" {
  name                 = "subnet-aks"
  resource_group_name  = var.spoke_resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.spoke_subnet_aks_cidr]
}

# Subnet para Private Endpoints de ACR y Key Vault.
# Los Private Endpoints necesitan que las network policies estén deshabilitadas.
resource "azurerm_subnet" "spoke_private_endpoints" {
  name                 = "subnet-private-endpoints"
  resource_group_name  = var.spoke_resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.spoke_subnet_pe_cidr]

  # Requerido para que los Private Endpoints funcionen en esta subnet.
  # "Disabled" significa que Azure no aplica políticas de red restrictivas
  # sobre los Private Endpoints, permitiendo que reciban tráfico.
  private_endpoint_network_policies = "Disabled"
}

# =============================================================================
# NSG SPOKE — Firewall de la VNet spoke
#
# El spoke protege los nodos de AKS y los Private Endpoints.
# Reglas de least-privilege: solo el tráfico estrictamente necesario.
# =============================================================================

resource "azurerm_network_security_group" "spoke" {
  name                = "nsg-spoke${var.name_suffix}"
  location            = var.location
  resource_group_name = var.spoke_resource_group_name
  tags                = var.tags

  # Permitir tráfico del hub al spoke (necesario para DNS privado).
  # Sin esta regla, los pods de AKS no pueden resolver nombres privados
  # como "mi-acr.azurecr.io" porque no llegan al servidor DNS del hub.
  security_rule {
    name                       = "AllowHubInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.hub_vnet_cidr
    destination_address_prefix = "*"
  }

  # Bloquear tráfico de internet directo a los nodos de AKS.
  # Los nodos AKS no deben ser accesibles desde internet —
  # solo desde el hub y desde los balanceadores de Azure.
  security_rule {
    name                       = "DenyInternetInbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

# Asociar NSG spoke a subnet de AKS
resource "azurerm_subnet_network_security_group_association" "spoke_aks" {
  subnet_id                 = azurerm_subnet.spoke_aks.id
  network_security_group_id = azurerm_network_security_group.spoke.id
}

# Asociar NSG spoke a subnet de Private Endpoints
resource "azurerm_subnet_network_security_group_association" "spoke_pe" {
  subnet_id                 = azurerm_subnet.spoke_private_endpoints.id
  network_security_group_id = azurerm_network_security_group.spoke.id
}

# =============================================================================
# VNet PEERING — Cable virtual bidireccional hub ↔ spoke
#
# El peering debe crearse en ambas direcciones:
#   - hub → spoke: el hub puede iniciar conexiones al spoke
#   - spoke → hub: el spoke puede iniciar conexiones al hub (DNS)
#
# Sin peering bidireccional, una red puede enviar pero no recibir respuestas.
# =============================================================================

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "hub-to-spoke"
  resource_group_name       = var.hub_resource_group_name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke.id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "spoke-to-hub"
  resource_group_name       = var.spoke_resource_group_name
  virtual_network_name      = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
  allow_forwarded_traffic   = true
  use_remote_gateways       = false
}

# =============================================================================
# PRIVATE DNS ZONES — Directorio telefónico interno de la red
#
# ¿Para qué sirven?
#   Sin DNS privado, "mi-acr.azurecr.io" resuelve a una IP pública.
#   Con DNS privado, resuelve a una IP interna del Private Endpoint.
#   Esto garantiza que el tráfico a ACR, Key Vault y AKS nunca salga
#   a internet — va directamente por la red privada de Azure.
#
# Las zonas viven en el hub (recursos compartidos).
# Se vinculan al spoke para que los recursos del spoke puedan usarlas.
# =============================================================================

resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = var.hub_resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.hub_resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "aks" {
  name                = "privatelink.eastus2.azmk8s.io"
  resource_group_name = var.hub_resource_group_name
  tags                = var.tags
}

# =============================================================================
# DNS ZONE LINKS — Conectar las zonas al spoke
#
# Un DNS Zone Link le dice a Azure: "cuando un recurso de esta VNet
# busque un nombre de esta zona, usa los registros privados en lugar
# de los públicos".
#
# registration_enabled = false: la zona solo resuelve nombres (no registra
# automáticamente los recursos de la VNet). Los Private Endpoints registran
# sus propios registros A cuando se crean.
# =============================================================================

resource "azurerm_private_dns_zone_virtual_network_link" "acr_to_spoke" {
  name                  = "link-acr-to-spoke"
  resource_group_name   = var.hub_resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault_to_spoke" {
  name                  = "link-keyvault-to-spoke"
  resource_group_name   = var.hub_resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aks_to_spoke" {
  name                  = "link-aks-to-spoke"
  resource_group_name   = var.hub_resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.aks.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = var.tags
}
