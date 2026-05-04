<#
.SYNOPSIS
    Crea un Service Principal en Azure Entra ID para pipelines de CI/CD con GitHub Actions.

.DESCRIPTION
    Este script usa el MODULO AZ DE POWERSHELL (no Azure CLI) porque es la forma
    mas robusta en Windows: los comandos son cmdlets nativos de PowerShell, sin
    problemas de parseo con flags como '--name' o '--role'.

    Al terminar, imprime los tres valores que debes copiar en GitHub Secrets.

    PRE-REQUISITOS:
      - PowerShell 7 (pwsh)
      - Modulo Az instalado: Install-Module -Name Az -Scope CurrentUser -Force
      - Sesion activa:       Connect-AzAccount

.PARAMETER SubscriptionId
    ID de la suscripcion donde el Service Principal tendra el rol Contributor.
    Por defecto usa tu nueva suscripcion personal.

.PARAMETER TenantId
    ID del inquilino (tenant) donde se creara el App Registration.

.PARAMETER SpName
    Nombre visible del Service Principal en Azure Entra ID.

.EXAMPLE
    # Ejecutar con valores por defecto
    .\sp-landing-zone-cicd.ps1

.EXAMPLE
    # Ejecutar con un nombre personalizado
    .\sp-landing-zone-cicd.ps1 -SpName "mi-sp-custom"
#>

param(
    [string]$SubscriptionId = "1989a8c1-76c1-4555-a228-c95f86c66635",
    [string]$TenantId       = "a239f11b-222e-4897-bc79-b4df74609f63",
    [string]$SpName         = "sp-landing-zone-cicd"
)

# ---------------------------------------------------------------------------
# Configuracion de PowerShell:
#   Set-StrictMode  → fuerza buenas practicas (variables sin inicializar dan error)
#   $ErrorActionPreference → hace que cualquier error detenga el script en vez
#   de continuar silenciosamente
# ---------------------------------------------------------------------------
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# FUNCIONES DE VALIDACION
# Las funciones hacen el codigo mas legible y reutilizable.
# Cada una valida un prerequisito antes de ejecutar el flujo principal.
# ---------------------------------------------------------------------------

function Assert-AzModuleInstalled {
    <#
    Verifica que el modulo Az este instalado en PowerShell.
    Sin el modulo, los cmdlets New-AzADApplication, etc. no existen.
    #>
    if (-not (Get-Module -Name Az.Accounts -ListAvailable)) {
        throw (
            "El modulo Az no esta instalado. Instálalo con:`n" +
            "  Install-Module -Name Az -Scope CurrentUser -Force"
        )
    }
}

function Assert-AzConnected {
    <#
    Verifica que hay una sesion activa de Azure PowerShell.
    Si no la hay, el script para y te indica como iniciarla.
    #>
    $context = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $context -or -not $context.Account) {
        throw (
            "No hay sesion activa en Azure PowerShell.`n" +
            "Ejecuta: Connect-AzAccount"
        )
    }
    Write-Host "[INFO] Sesion activa como: $($context.Account.Id)" -ForegroundColor Cyan
}

function Assert-SubscriptionAccess {
    param(
        [string]$SubscriptionId,
        [string]$TenantId
    )

    <#
    Verifica que la cuenta actual tenga acceso real al tenant y a la suscripcion.
    Si no hay acceso, Set-AzContext falla con mensajes genericos.
    #>
    $subscription = Get-AzSubscription -SubscriptionId $SubscriptionId -TenantId $TenantId -ErrorAction SilentlyContinue
    if (-not $subscription) {
        throw (
            "No se encontro acceso a la suscripcion '$SubscriptionId' en el tenant '$TenantId'.`n" +
            "Asegurate de iniciar sesion en el tenant correcto:`n" +
            "  Disconnect-AzAccount -Scope Process`n" +
            "  Connect-AzAccount -Tenant '$TenantId' -UseDeviceAuthentication`n" +
            "  Set-AzContext -SubscriptionId '$SubscriptionId' -TenantId '$TenantId'"
        )
    }
}

# ---------------------------------------------------------------------------
# FLUJO PRINCIPAL
# Envuelto en try/catch para capturar cualquier error y mostrar un mensaje
# claro en lugar de un stack trace tecnico.
# ---------------------------------------------------------------------------

try {
    Write-Host ""
    Write-Host "=== Creando Service Principal para CI/CD ===" -ForegroundColor Cyan
    Write-Host ""

    # ------------------------------------------------------------------
    # PASO 1: Validar prerequisitos
    # Siempre valida primero antes de hacer cambios en Azure.
    # ------------------------------------------------------------------
    Write-Host "[1/4] Verificando prerequisitos..." -ForegroundColor Yellow
    Assert-AzModuleInstalled
    Assert-AzConnected
    Assert-SubscriptionAccess -SubscriptionId $SubscriptionId -TenantId $TenantId

    # ------------------------------------------------------------------
    # PASO 2: Apuntar al contexto de la suscripcion/tenant correctos
    # Si tienes varias suscripciones, esto garantiza que trabajas en la
    # suscripcion y tenant esperados, y no en otros por error.
    # ------------------------------------------------------------------
    Write-Host "[2/4] Configurando suscripcion '$SubscriptionId' y tenant '$TenantId'..." -ForegroundColor Yellow
    Set-AzContext -SubscriptionId $SubscriptionId -TenantId $TenantId | Out-Null

    # ------------------------------------------------------------------
    # PASO 3: Crear el Application Registration (idempotente)
    #
    # Un "Application Registration" es el registro de identidad en
    # Entra ID (antes llamado Azure Active Directory).
    # Es como crear el "usuario robot" que usaran los pipelines.
    #
    # El script verifica si ya existe para no crear duplicados
    # (comportamiento idempotente: puedes correrlo varias veces).
    # ------------------------------------------------------------------
    Write-Host "[3/4] Creando Application Registration '$SpName'..." -ForegroundColor Yellow

    $existingApp = Get-AzADApplication -DisplayName $SpName -ErrorAction SilentlyContinue

    if ($existingApp) {
        Write-Host "[AVISO] Ya existe un Application con el nombre '$SpName'. Se usara el existente." -ForegroundColor Magenta
        $app = $existingApp
    }
    else {
        # New-AzADApplication: crea el registro en Entra ID
        $app = New-AzADApplication -DisplayName $SpName
        Write-Host "[INFO] Application Registration creado. AppId: $($app.AppId)" -ForegroundColor Cyan
    }

    # Ahora crea el Service Principal asociado al Application.
    # La diferencia:
    #   Application Registration = la definicion global de la identidad
    #   Service Principal        = la instancia de esa identidad en tu suscripcion
    $sp = Get-AzADServicePrincipal -ApplicationId $app.AppId -ErrorAction SilentlyContinue

    if (-not $sp) {
        $sp = New-AzADServicePrincipal -ApplicationId $app.AppId
        Write-Host "[INFO] Service Principal creado. ObjectId: $($sp.Id)" -ForegroundColor Cyan

        # Azure necesita unos segundos para propagar el nuevo Service Principal
        # antes de poder asignarle un rol. Sin esta espera, el paso 4 puede fallar.
        Write-Host "[INFO] Esperando propagacion en Azure (15 segundos)..." -ForegroundColor Cyan
        Start-Sleep -Seconds 15
    }
    else {
        Write-Host "[AVISO] El Service Principal ya existia. Se usara el existente." -ForegroundColor Magenta
    }

    # ------------------------------------------------------------------
    # PASO 4: Asignar el rol Contributor en la suscripcion
    #
    # "Contributor" permite crear y modificar recursos de Azure,
    # pero NO puede cambiar permisos ni politicas.
    # Es el minimo necesario para que Terraform pueda crear infraestructura.
    #
    # El script verifica si el rol ya fue asignado para no duplicarlo.
    # ------------------------------------------------------------------
    Write-Host "[4/4] Asignando rol 'Contributor' en la suscripcion..." -ForegroundColor Yellow

    $scope = "/subscriptions/$SubscriptionId"

    $existingRole = Get-AzRoleAssignment `
        -ObjectId         $sp.Id `
        -RoleDefinitionName "Contributor" `
        -Scope            $scope `
        -ErrorAction      SilentlyContinue

    if ($existingRole) {
        Write-Host "[AVISO] El rol 'Contributor' ya estaba asignado. No se duplica." -ForegroundColor Magenta
    }
    else {
        # New-AzRoleAssignment: asigna el rol al Service Principal en el scope indicado
        New-AzRoleAssignment `
            -ObjectId           $sp.Id `
            -RoleDefinitionName "Contributor" `
            -Scope              $scope | Out-Null

        Write-Host "[INFO] Rol asignado correctamente." -ForegroundColor Cyan
    }

    # ------------------------------------------------------------------
    # RESULTADO FINAL
    # Imprime los tres valores que necesitas copiar en GitHub Secrets.
    # Estos valores NO son secretos por si solos — el secreto real es
    # el token OIDC temporal que GitHub genera en cada pipeline.
    # ------------------------------------------------------------------
    $tenantId = (Get-AzContext).Tenant.Id

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host " [OK] Service Principal listo para GitHub Actions + OIDC    " -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host " Copia estos tres valores en GitHub Secrets:" -ForegroundColor Yellow
    Write-Host " (GitHub → tu repo → Settings → Secrets and variables → Actions)"
    Write-Host ""
    Write-Host " AZURE_CLIENT_ID       = $($app.AppId)"
    Write-Host " AZURE_TENANT_ID       = $tenantId"
    Write-Host " AZURE_SUBSCRIPTION_ID = $SubscriptionId"
    Write-Host ""
    Write-Host " SIGUIENTE PASO:" -ForegroundColor Yellow
    Write-Host " La Federation Credential (OIDC) la crea el script bootstrap.ps1 en la Fase 2." -ForegroundColor Yellow
    Write-Host ""
}
catch {
    # Si algo falla, muestra el mensaje de error de forma clara y termina con codigo 1
    # (codigo de salida distinto de 0 indica error a los sistemas automatizados)
    if ($_.Exception.Message -match "valid tenant|valid subscription") {
        Write-Host "" 
        Write-Host "[AYUDA] Parece que estas autenticado en otro tenant." -ForegroundColor Yellow
        Write-Host "Ejecuta estos comandos y vuelve a correr el script:" -ForegroundColor Yellow
        Write-Host "  Disconnect-AzAccount -Scope Process"
        Write-Host "  Connect-AzAccount -Tenant '$TenantId' -UseDeviceAuthentication"
        Write-Host "  Set-AzContext -SubscriptionId '$SubscriptionId' -TenantId '$TenantId'"
        Write-Host ""
    }
    Write-Error "[ERROR] $($_.Exception.Message)"
    exit 1
}
