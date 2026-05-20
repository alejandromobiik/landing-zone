# =============================================================================
# main.tf — Punto de entrada principal de Terraform
# =============================================================================
#
# ¿Qué es el main.tf raíz?
#   Es el archivo principal que "orquesta" toda la infraestructura.
#   No crea recursos directamente (eso lo hacen los módulos), sino que:
#     1. Define los Resource Groups (las "carpetas" de Azure)
#     2. Llama a cada módulo pasándole los parámetros que necesita
#
#   Piénsalo como el director de orquesta: él no toca ningún instrumento,
#   pero coordina a todos los músicos (módulos) para que toquen juntos.
#
# ¿Por qué separar en módulos en lugar de poner todo aquí?
#   - Reutilización: el módulo "network" puede usarse para crear una red
#     hub y una red spoke con el mismo código, solo cambiando los parámetros
#   - Mantenimiento: si cambia algo en la red, solo editas modules/network
#     sin tocar el resto del código
#   - Comprensión: main.tf queda limpio y legible — ves la arquitectura
#     completa de un vistazo sin perderte en detalles de implementación
#
# ESTADO ACTUAL (post Fases 4-6 en código):
#   4 RGs + módulos network, monitoring (+ Defender + diag KV/NSG), policy,
#   keyvault, acr, aks; en raíz: diag AKS, alertas, identidad workload + federación.
#
# =============================================================================

# =============================================================================
# LOCALS — Valores calculados y reutilizables
#
# ¿Qué es un local?
#   Un "local" es como una variable interna que Terraform calcula a partir
#   de otras variables. No se puede pasar desde fuera (a diferencia de
#   las variables en variables.tf) — solo se usa dentro de este archivo
#   y de los módulos que lo heredan.
#
#   Sirven para evitar repetir la misma expresión en 10 lugares.
#   Ejemplo: el sufijo "-dev" al final de cada nombre de recurso.
# =============================================================================
locals {
  # Sufijo estándar para nombres de recursos.
  # Resultado: "-lz-dev" (con los defaults de variables.tf)
  # Se agrega al final de cada recurso para identificar proyecto + entorno.
  # Ejemplo: "rg-platform-lz-dev", "aks-lz-dev", "kv-lz-dev"
  name_suffix = "-${var.project_name}-${var.environment}"

  # Sufijo único para recursos con nombres globalmente únicos en Azure
  # (Key Vault, Storage Accounts, ACR). Usa los últimos 5 caracteres del
  # subscription ID para garantizar unicidad entre suscripciones.
  # Ejemplo: "-lz-dev-66635"
  unique_suffix = "${local.name_suffix}-${substr(data.azurerm_subscription.current.subscription_id, 31, 5)}"

  # Tags completos que se aplican a TODOS los recursos.
  # merge() combina dos maps: si la misma clave aparece en ambos,
  # gana el segundo. Esto permite que cada módulo agregue sus propios tags
  # sin perder los globales.
  common_tags = merge(var.tags_default, {
    # Sobreescribimos Environment con el valor real de la variable
    # (en caso de que var.tags_default tenga un valor hardcodeado)
    Environment = var.environment
  })
}

# =============================================================================
# RESOURCE GROUPS — Las "carpetas" de Azure
#
# ¿Qué es un Resource Group?
#   Un Resource Group (RG) es un contenedor lógico en Azure que agrupa
#   recursos relacionados. Piénsalo como una carpeta en tu computadora:
#   puedes borrar la carpeta completa y eliminar todo lo que contiene,
#   o ver el costo de todos los recursos de una carpeta juntos.
#
# ¿Por qué 4 Resource Groups y no uno solo?
#   Separar en RGs por función tiene varias ventajas:
#     - Seguridad: puedes dar acceso solo al RG de red sin dar acceso
#       al RG de la aplicación
#     - Costo: ves cuánto cuesta la red separado de la aplicación
#     - Ciclo de vida: si recreáramos solo la aplicación sin tocar la red,
#       hacemos destroy/apply solo del RG correspondiente
#     - Organización: imita la separación que las empresas tienen entre
#       equipos (equipo de red, equipo de plataforma, equipo de app)
#
# Los 4 RGs siguen el patrón del plan de trabajo:
#   rg-platform    → infraestructura de soporte (Log Analytics, tfstate)
#   rg-network-hub → red central compartida (VNet hub, DNS privado, NSGs)
#   rg-spoke-app   → aplicación y sus servicios (AKS, ACR, Key Vault)
#   rg-shared      → recursos compartidos entre múltiples aplicaciones
#
# NOTA IMPORTANTE sobre rg-platform:
#   Este Resource Group YA EXISTE en Azure — lo creó bootstrap.ps1 en la Fase 2.
#   Terraform no lo crea de nuevo; en cambio, lo declara con un data source
#   (una consulta de solo lectura) para poder referenciar su nombre y ubicación
#   en otros módulos sin hardcodearlo.
# =============================================================================

# -----------------------------------------------------------------------------
# rg-platform (ya existe — creado por bootstrap.ps1)
#
# ¿Por qué un data source y no un resource?
#   Si usáramos "resource", Terraform intentaría crear el RG y fallaría
#   porque ya existe. Con "data source" le decimos: "no lo crees, solo
#   léelo y dame sus datos para usarlos en el resto del código".
# -----------------------------------------------------------------------------
data "azurerm_resource_group" "platform" {
  name = "rg-platform"
}

# -----------------------------------------------------------------------------
# rg-network-hub — Red central compartida (hub)
#
# Contendrá:
#   - VNet Hub (10.0.0.0/16)
#   - Private DNS Zones (para ACR, Key Vault y AKS)
#   - NSG del hub
#   - En el futuro: Azure Bastion o Azure Firewall
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "network_hub" {
  name     = "rg-network-hub${local.name_suffix}"
  location = var.location
  tags     = local.common_tags
}

# -----------------------------------------------------------------------------
# rg-spoke-app — Aplicación y servicios de la landing zone
#
# Contendrá:
#   - VNet Spoke (10.1.0.0/16)
#   - AKS (clúster de Kubernetes privado)
#   - ACR (registro de imágenes de contenedor)
#   - Key Vault (caja fuerte de secretos)
#   - NSG del spoke
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "spoke_app" {
  name     = "rg-spoke-app${local.name_suffix}"
  location = var.location
  tags     = local.common_tags
}

# -----------------------------------------------------------------------------
# rg-shared — Recursos compartidos entre múltiples aplicaciones
#
# En este proyecto es un RG vacío que refleja la arquitectura empresarial
# real donde existen recursos compartidos (p.ej. un ACR central que sirve
# imágenes a múltiples clústeres AKS de diferentes aplicaciones).
#
# En la evaluación demuestra que entiendes la separación de responsabilidades.
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "shared" {
  name     = "rg-shared${local.name_suffix}"
  location = var.location
  tags     = local.common_tags
}

# =============================================================================
# MÓDULO NETWORK — Red hub-spoke completa
#
# Este módulo crea toda la infraestructura de red:
#   - VNet hub (10.0.0.0/16) con subnet de DNS privado y NSG
#   - VNet spoke (10.1.0.0/16) con subnets para AKS y Private Endpoints y NSG
#   - VNet Peering bidireccional hub ↔ spoke
#   - 3 Private DNS Zones: azurecr.io, vaultcore.azure.net, azmk8s.io
#   - DNS Zone Links del hub hacia el spoke
#
# Los outputs de este módulo (subnet IDs, DNS zone IDs) se usarán como
# inputs para los módulos de AKS, ACR y Key Vault.
#
# depends_on garantiza que los Resource Groups existan antes de crear
# cualquier recurso de red dentro de ellos.
# =============================================================================
module "network" {
  source = "./modules/network"

  # Ubicación y nombres
  location    = var.location
  name_suffix = local.name_suffix
  tags        = local.common_tags

  # Resource Groups donde vivirán los recursos de red
  hub_resource_group_name   = azurerm_resource_group.network_hub.name
  spoke_resource_group_name = azurerm_resource_group.spoke_app.name

  # Espacios de direcciones IP — usando los valores por defecto del módulo:
  #   hub_vnet_cidr               = "10.0.0.0/16"
  #   hub_subnet_private_dns_cidr = "10.0.1.0/24"
  #   spoke_vnet_cidr             = "10.1.0.0/16"
  #   spoke_subnet_aks_cidr       = "10.1.0.0/22"
  #   spoke_subnet_pe_cidr        = "10.1.10.0/24"

  depends_on = [
    azurerm_resource_group.network_hub,
    azurerm_resource_group.spoke_app,
  ]
}

# =============================================================================
# MÓDULO MONITORING — Log Analytics Workspace
#
# Crea el workspace central de logs que recibe telemetría de AKS, Key Vault
# y los NSGs. Debe desplegarse ANTES que AKS, porque el clúster necesita
# el workspace_resource_id para configurar el add-on de monitoreo (oms_agent).
#
# Se coloca en rg-platform porque es infraestructura de soporte, igual que
# el Storage Account del tfstate. Comparten el mismo ciclo de vida: se crean
# en el bootstrap y raramente se eliminan.
#
# COSTO: ~$0/mes (los primeros 5 GB de logs/mes son gratuitos en PerGB2018)
# =============================================================================
module "monitoring" {
  source = "./modules/monitoring"

  location            = var.location
  name_suffix         = local.name_suffix
  tags                = local.common_tags
  resource_group_name = data.azurerm_resource_group.platform.name
  retention_in_days   = 30

  keyvault_id  = module.keyvault.keyvault_id
  nsg_hub_id   = module.network.nsg_hub_id
  nsg_spoke_id = module.network.nsg_spoke_id
}

# =============================================================================
# MÓDULO POLICY — Asignaciones de Azure Policy a nivel de suscripción
#
# Asigna 5 políticas builtin de Microsoft:
#   1. Require tag "Environment" en todos los recursos
#   2. Require tag "Project" en todos los recursos
#   3. Require tag "Owner" en todos los recursos
#   4. Solo ubicaciones permitidas (eastus2, eastus, brazilsouth)
#   5. Storage Accounts sin acceso público a la red
#
# Todas las políticas están en modo DoNotEnforce (enforcement_mode = false):
# reportan conformidad en el portal pero no bloquean operaciones.
# Los recursos existentes son conformes: tienen los 3 tags y están en eastus2.
#
# COSTO: $0 — las asignaciones de Policy no tienen cargo.
# =============================================================================
module "policy" {
  source = "./modules/policy"

  subscription_id   = data.azurerm_subscription.current.id
  allowed_locations = var.allowed_locations
  tags              = local.common_tags
}

# =============================================================================
# MÓDULO KEY VAULT — Caja fuerte de secretos con acceso solo privado
#
# Crea un Key Vault Standard con:
#   - public_network_access_enabled = false  (invisible desde internet)
#   - Private Endpoint en subnet-private-endpoints del spoke
#   - DNS zone group que registra el PE en la zona privada del hub
#   - enable_rbac_authorization = true (control de acceso via roles, no access policies)
#   - purge_protection = true (protección contra borrado accidental)
#
# Los secrets de la aplicación se guardarán aquí (Fase 5 — az CLI tras RBAC).
# La identidad del POD (User-Assigned MI + Workload Identity Federation) recibe
# el rol Key Vault Secrets User en main.tf raíz — ver azurerm_user_assigned_identity.workload_app.
#
# COSTO: ~$7/mes (Private Endpoint ~$0.01/h + ops de KV ~$0/mes en dev)
# =============================================================================
module "keyvault" {
  source = "./modules/keyvault"

  location                = var.location
  name_suffix             = local.unique_suffix
  tags                    = local.common_tags
  resource_group_name     = azurerm_resource_group.spoke_app.name
  hub_resource_group_name = azurerm_resource_group.network_hub.name
  tenant_id               = data.azurerm_client_config.current.tenant_id

  # Outputs del módulo network
  subnet_private_endpoints_id  = module.network.subnet_private_endpoints_id
  private_dns_zone_keyvault_id = module.network.private_dns_zone_keyvault_id

  depends_on = [module.network]
}

# =============================================================================
# MÓDULO ACR — Azure Container Registry (SKU Basic)
#
# Crea un registry privado de imágenes de contenedor:
#   - SKU Basic: ~$5/mes (suficiente para dev, sin Private Endpoint)
#   - admin_enabled = false: autenticación solo via Managed Identity
#   - Nombre: acrlzdev (los guiones no son válidos en nombres de ACR)
#
# El módulo aks asignará el rol "AcrPull" a la kubelet identity del cluster,
# permitiendo que AKS descargue imágenes sin contraseñas ni credenciales
# explícitas — esto es Workload Identity integrado con ACR.
#
# Los pipelines de CI/CD usarán OIDC (ya configurado en bootstrap) para
# hacer docker push al registry.
#
# COSTO: ~$5/mes (SKU Basic, 10 GB de almacenamiento incluido)
# =============================================================================
module "acr" {
  source = "./modules/acr"

  location            = var.location
  name_suffix         = local.unique_suffix
  tags                = local.common_tags
  resource_group_name = azurerm_resource_group.spoke_app.name
}

# =============================================================================
# MÓDULO AKS — Azure Kubernetes Service privado (cumple PDF sección 3.3)
#
# Crea el cluster de Kubernetes con la configuración EXACTA que pide el PDF:
#   - Control plane gratuito (SKU Free)
#   - PRIVADO: el API server no es accesible desde internet
#   - System node pool (1 nodo Standard_D2s_v3, ~$70/mes) — componentes de Kubernetes
#   - User   node pool (1 nodo Standard_D2s_v3, ~$70/mes) — aplicaciones del usuario
#   - OIDC issuer + Workload Identity habilitados (para autenticar pods sin contraseñas)
#   - SystemAssigned identity (control plane) + kubelet identity UserAssigned (nodos)
#   - oms_agent: envía logs al Log Analytics Workspace (Container Insights)
#   - Azure CNI: cada pod recibe IP real de la subnet-aks (10.1.0.0/22)
#   - AcrPull: rol asignado automáticamente a la kubelet identity sobre el ACR
#
# ⚠️ IMPORTANTE — Parar el cluster cuando no trabajes:
#   az aks stop --name aks-lz-dev --resource-group rg-spoke-app-lz-dev
#   az aks start --name aks-lz-dev --resource-group rg-spoke-app-lz-dev
#
# ⚠️ Standard_B2s (más barato) NO está permitido en suscripciones Free Trial.
#    Standard_D2s_v3 es el mínimo permitido en esta suscripción.
#
# COSTO: ~$0/mes control plane + ~$140/mes (2 nodos D2s_v3, ~$4.60/día)
#         → Parar el cluster ahorra todo el costo de los nodos.
#         → Con Free Trial $200 USD por 30 días: el cluster encendido 24/7 lo
#           consume en ~43 días, así que parar diariamente es indispensable.
# =============================================================================
module "aks" {
  source = "./modules/aks"

  location            = var.location
  name_suffix         = local.name_suffix
  tags                = local.common_tags
  resource_group_name = azurerm_resource_group.spoke_app.name

  # Outputs del módulo network
  subnet_aks_id = module.network.subnet_aks_id

  # Output del módulo monitoring — AKS enviará logs a este workspace
  log_analytics_workspace_id = module.monitoring.workspace_resource_id

  # Output del módulo acr — para asignar AcrPull a la kubelet identity
  acr_id = module.acr.acr_id

  # System node pool (componentes internos de Kubernetes)
  node_vm_size = "Standard_D2s_v3"
  node_count   = 1

  # User node pool (aplicaciones del usuario — exigido por PDF sección 3.3)
  user_node_vm_size = "Standard_D2s_v3"
  user_node_count   = 1

  depends_on = [module.network, module.monitoring, module.acr]
}

# =============================================================================
# WORKLOAD IDENTITY — Managed Identity de la aplicación (pod)
#
# El PDF exige consumir secretos del Key Vault vía CSI o Workload Identity.
# Esta User-Assigned MI es la identidad que el pod usará (anotación en ServiceAccount
# Fase 8). La federación enlaza el issuer OIDC del cluster con el subject del SA.
# =============================================================================

resource "azurerm_user_assigned_identity" "workload_app" {
  name                = "mi-app${replace(local.name_suffix, "-", "")}"
  location            = var.location
  resource_group_name = azurerm_resource_group.spoke_app.name
  tags                = local.common_tags
}

resource "azurerm_federated_identity_credential" "workload_app" {
  name                       = "fc-app${replace(local.name_suffix, "-", "")}"
  user_assigned_identity_id  = azurerm_user_assigned_identity.workload_app.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:default:lz-app-sa"

  depends_on = [module.aks, azurerm_user_assigned_identity.workload_app]
}

resource "azurerm_role_assignment" "workload_app_kv_secrets_user" {
  scope                = module.keyvault.keyvault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.workload_app.principal_id
}

# =============================================================================
# DIAGNOSTIC SETTINGS — AKS → Log Analytics (evita ciclo con el módulo monitoring)
# =============================================================================

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "diag-aks${local.name_suffix}"
  target_resource_id         = module.aks.aks_id
  log_analytics_workspace_id = module.monitoring.workspace_resource_id

  enabled_log {
    category = "kube-apiserver"
  }

  enabled_log {
    category = "kube-audit"
  }

  enabled_log {
    category = "kube-controller-manager"
  }

  enabled_log {
    category = "guard"
  }

  enabled_metric {
    category = "AllMetrics"
  }

  depends_on = [module.aks, module.monitoring]
}

# =============================================================================
# ALERTAS — métrica CPU nodos AKS + logs KQL pods Failed (PDF §3.3 / Fase 6)
# =============================================================================

resource "azurerm_monitor_action_group" "lz_alerts" {
  name                = "ag-lz${replace(local.name_suffix, "-", "")}"
  resource_group_name = data.azurerm_resource_group.platform.name
  short_name          = "lzalertrg"

  tags = local.common_tags
}

resource "azurerm_monitor_metric_alert" "aks_node_cpu_high" {
  name                = "alert-aks-cpu${local.name_suffix}"
  resource_group_name = data.azurerm_resource_group.platform.name
  scopes              = [module.aks.aks_id]
  description         = "CPU del API server del cluster AKS supera 80 % (métrica GA). Las métricas por nodo están en PREVIEW y la API de alertas métricas las rechaza sin soporte adicional."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  enabled             = true

  criteria {
    metric_namespace       = "Microsoft.ContainerService/managedClusters"
    metric_name            = "apiserver_cpu_usage_percentage"
    aggregation            = "Average"
    operator               = "GreaterThan"
    threshold              = 80
    skip_metric_validation = false
  }

  action {
    action_group_id = azurerm_monitor_action_group.lz_alerts.id
  }

  tags = local.common_tags

  depends_on = [module.aks, azurerm_monitor_action_group.lz_alerts]
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "pods_failed" {
  name                = "alert-pods-failed${local.name_suffix}"
  resource_group_name = data.azurerm_resource_group.platform.name
  location            = var.location

  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  scopes               = [module.monitoring.workspace_resource_id]

  severity = 2

  criteria {
    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Total"

    query = <<-KQL
      KubePodInventory
      | where TimeGenerated > ago(5m)
      | where PodStatus == "Failed"
      | summarize pod_failed_count = count()
    KQL

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }

    metric_measure_column = "pod_failed_count"
  }

  identity {
    type = "SystemAssigned"
  }

  action {
    action_groups = [azurerm_monitor_action_group.lz_alerts.id]
  }

  tags = local.common_tags

  depends_on = [module.monitoring, azurerm_monitor_action_group.lz_alerts]
}
