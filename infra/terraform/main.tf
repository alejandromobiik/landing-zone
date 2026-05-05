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
# ESTADO ACTUAL (Paso 3 — Fase 3):
#   Solo creamos los 4 Resource Groups. Los módulos de red, AKS, ACR,
#   Key Vault, etc., se agregarán en los pasos siguientes de la Fase 3
#   y en las Fases 4, 5, 6 y 7.
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
