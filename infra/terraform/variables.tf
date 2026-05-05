# =============================================================================
# variables.tf — Variables globales del proyecto
# =============================================================================
#
# ¿Qué es una variable en Terraform?
#   Una variable es un parámetro de entrada para el código. En vez de escribir
#   "eastus2" directamente en cada recurso, defines una variable "location"
#   y todos los recursos la usan. Si un día cambias de región, solo cambias
#   la variable — no tienes que buscar y reemplazar en 30 archivos.
#
# ¿Cómo reciben valor las variables?
#   Hay 4 formas, en orden de prioridad (de mayor a menor):
#     1. Línea de comandos:   terraform plan -var="environment=prod"
#     2. Archivo .tfvars:     terraform plan -var-file="prod.tfvars"
#     3. Variable de entorno: export TF_VAR_environment=prod
#     4. Valor default:       el que está definido en este archivo con `default =`
#
#   En este proyecto usamos los `default` para ejecución local y archivos
#   .tfvars para los pipelines de GitHub Actions (Fase 9).
#
# ¿Qué es `validation`?
#   El bloque `validation` dentro de una variable permite que Terraform
#   rechace valores incorrectos ANTES de intentar crear recursos en Azure.
#   Es como una validación de formulario: falla rápido con un mensaje claro
#   en lugar de crear recursos a medias y fallar a mitad del proceso.
#
# =============================================================================

# -----------------------------------------------------------------------------
# VARIABLE: location
#
# La región de Azure donde se crearán los recursos.
# Todas las regiones disponibles: az account list-locations --output table
#
# ¿Por qué eastus2?
#   - Es una de las regiones más completas de Azure (todos los servicios disponibles)
#   - Tiene buenos precios
#   - Es la que usó el bootstrap — los nuevos recursos deben estar en la misma región
#     que el Resource Group rg-platform (que ya existe en eastus2)
# -----------------------------------------------------------------------------
variable "location" {
  type        = string
  description = "Región de Azure donde se crearán todos los recursos del proyecto."
  default     = "eastus2"

  validation {
    # Solo permitimos las regiones que usaremos en este proyecto.
    # Esto evita crear recursos accidentalmente en una región cara o no permitida.
    condition = contains([
      "eastus",
      "eastus2",
      "westus2",
      "westeurope",
      "brazilsouth",
    ], var.location)
    error_message = "La región '${var.location}' no está en la lista permitida. Usa: eastus, eastus2, westus2, westeurope o brazilsouth."
  }
}

# -----------------------------------------------------------------------------
# VARIABLE: environment
#
# El entorno al que pertenecen los recursos. Se usa como sufijo en los nombres
# de recursos (ej: "aks-lz-dev", "aks-lz-prod") y como tag obligatorio.
#
# ¿Por qué es útil?
#   Terraform puede crear la misma infraestructura en entornos diferentes
#   usando exactamente el mismo código. Solo cambia esta variable.
#   Hoy tienes "dev" en tu suscripción de prueba; si mañana tienes una
#   suscripción de producción, corres el mismo código con environment="prod".
# -----------------------------------------------------------------------------
variable "environment" {
  type        = string
  description = "Entorno de despliegue. Se incluye en los nombres de recursos y en los tags."
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "El entorno '${var.environment}' no es válido. Usa: dev, staging o prod."
  }
}

# -----------------------------------------------------------------------------
# VARIABLE: project_name
#
# Nombre corto del proyecto. Se usa como prefijo en los nombres de recursos
# para identificar a qué proyecto pertenecen.
#
# Restricciones de nomenclatura en Azure:
#   - Solo letras minúsculas y guiones (algunos recursos no aceptan guiones)
#   - Máximo 8 caracteres (para que los nombres completos quepan en el límite
#     de caracteres de recursos como Storage Accounts o Key Vaults)
# -----------------------------------------------------------------------------
variable "project_name" {
  type        = string
  description = "Nombre corto del proyecto (máx 8 caracteres, solo letras minúsculas). Se usa como prefijo en nombres de recursos."
  default     = "lz"

  validation {
    condition     = can(regex("^[a-z]{2,8}$", var.project_name))
    error_message = "El nombre del proyecto debe tener entre 2 y 8 letras minúsculas sin espacios ni caracteres especiales."
  }
}

# -----------------------------------------------------------------------------
# VARIABLE: tags_default
#
# Tags que se aplicarán a TODOS los recursos del proyecto.
#
# ¿Qué son los tags?
#   Son etiquetas clave=valor que se adjuntan a los recursos de Azure.
#   Sirven para:
#     - Facturación: saber cuánto cuesta cada proyecto o equipo
#     - Búsqueda: filtrar recursos en el portal por proyecto o dueño
#     - Políticas: la Azure Policy de la Fase 5 exigirá que todos los recursos tengan tags
#
# ¿Por qué type = map(string)?
#   Un map(string) es un diccionario de pares clave-valor donde todos los
#   valores son strings. Es la estructura perfecta para los tags de Azure.
# -----------------------------------------------------------------------------
variable "tags_default" {
  type        = map(string)
  description = "Tags que se aplican a todos los recursos. Se fusionan con tags específicos de cada módulo."
  default = {
    Project     = "landing-zone"
    Environment = "dev" # se sobreescribe en pipeline con var.environment
    Owner       = "alejandromobiik"
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------------------------------------
# VARIABLE: allowed_locations
#
# Lista de regiones donde se permite crear recursos.
# Se usa en el módulo de Azure Policy (Fase 5) para configurar la policy
# "Allowed locations" que bloquea creación de recursos en otras regiones.
#
# ¿Por qué definirlo aquí y no hardcodearlo en el módulo de policy?
#   Porque si agregas otra región al proyecto, solo cambias esta variable
#   y la policy se actualiza automáticamente en el próximo apply.
# -----------------------------------------------------------------------------
variable "allowed_locations" {
  type        = list(string)
  description = "Regiones de Azure donde se permite crear recursos (usado por Azure Policy)."
  default     = ["eastus", "eastus2", "brazilsouth"]
}
