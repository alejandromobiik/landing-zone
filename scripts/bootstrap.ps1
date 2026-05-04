<#
.SYNOPSIS
    Prepara Azure para que Terraform pueda guardar su estado remoto (tfstate).

.DESCRIPTION
    Este script es el "bootstrap" (arranque) de la Landing Zone.
    Debe ejecutarse UNA VEZ, antes de usar Terraform por primera vez.

    Hace exactamente tres cosas:
      1. Crea el Resource Group y Storage Account donde Terraform guarda su estado
      2. Crea las Federation Credentials OIDC en el Service Principal
         (permite que GitHub Actions se autentique ante Azure SIN contraseñas)
      3. Asigna el rol "Storage Blob Data Contributor" al Service Principal
         sobre el Storage Account

    El script es IDEMPOTENTE: puedes ejecutarlo múltiples veces sin error.
    Si un recurso ya existe, lo detecta, informa y continúa sin duplicarlo.

    PRE-REQUISITOS:
      - PowerShell 7 (pwsh)
      - Módulo Az instalado:    Install-Module -Name Az -Scope CurrentUser -Force
      - Sesión activa en Azure: Connect-AzAccount -Tenant '<TenantId>'
      - Service Principal ya creado (ejecutar antes: scripts\sp-landing-zone-cicd.ps1)

.PARAMETER SubscriptionId
    ID de la suscripción Azure donde se crearán los recursos.
    Por defecto usa la suscripción personal del proyecto.

.PARAMETER TenantId
    ID del tenant (directorio) de Azure Entra ID.

.PARAMETER Location
    Región de Azure donde se crearán los recursos. Por defecto: eastus2.

.PARAMETER ResourceGroupName
    Nombre del Resource Group que contendrá el Storage Account del tfstate.
    Por defecto: rg-platform.

.PARAMETER StorageAccountName
    Nombre del Storage Account donde Terraform guardará su estado.
    Debe ser único globalmente en Azure (solo minúsculas y números, 3-24 caracteres).

.PARAMETER ContainerName
    Nombre del contenedor de blobs dentro del Storage Account.
    Por defecto: tfstate.

.PARAMETER ServicePrincipalAppId
    AppId (Client ID) del Service Principal creado por sp-landing-zone-cicd.ps1.

.PARAMETER GitHubOrg
    Nombre de la organización o usuario de GitHub dueño del repositorio.

.PARAMETER GitHubRepo
    Nombre del repositorio de GitHub.

.PARAMETER WhatIf
    Si se especifica, el script muestra qué haría sin crear ningún recurso real.
    Úsalo para validar antes de ejecutar en modo real.

.EXAMPLE
    # Modo simulación (no crea nada, solo muestra qué haría)
    .\bootstrap.ps1 -WhatIf

.EXAMPLE
    # Ejecución real con los valores por defecto del proyecto
    .\bootstrap.ps1

.EXAMPLE
    # Segunda ejecución — verifica idempotencia (debe mostrar [AVISO] en todo)
    .\bootstrap.ps1
#>

param(
    [string]$SubscriptionId        = "1989a8c1-76c1-4555-a228-c95f86c66635",
    [string]$TenantId              = "a239f11b-222e-4897-bc79-b4df74609f63",
    [string]$Location              = "eastus2",
    [string]$ResourceGroupName     = "rg-platform",
    [string]$StorageAccountName    = "stlztf86c66635",   # único: prefijo + últimos 8 chars del Subscription ID
    [string]$ContainerName         = "tfstate",
    [string]$ServicePrincipalAppId = "0e8a5476-b963-4a39-8820-8b3404b6a805",
    [string]$GitHubOrg             = "alejandromobiik",
    [string]$GitHubRepo            = "landing-zone",
    [switch]$WhatIf
)

# ---------------------------------------------------------------------------
# Configuración de PowerShell:
#   Set-StrictMode  → fuerza buenas prácticas (variables sin inicializar dan error)
#   $ErrorActionPreference → detiene el script en cualquier error en vez de
#   continuar silenciosamente
# ---------------------------------------------------------------------------
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# FUNCIONES DE VALIDACIÓN
# Cada una verifica un prerequisito antes de ejecutar el flujo principal.
# ---------------------------------------------------------------------------

function Assert-AzModuleInstalled {
    <#
    Verifica que el módulo Az esté instalado en PowerShell.
    Sin el módulo, cmdlets como New-AzResourceGroup no existen.
    #>
    if (-not (Get-Module -Name Az.Accounts -ListAvailable)) {
        throw (
            "El módulo Az no está instalado. Instálalo con:`n" +
            "  Install-Module -Name Az -Scope CurrentUser -Force"
        )
    }
}

function Assert-AzConnected {
    <#
    Verifica que hay una sesión activa de Azure PowerShell.
    Si no la hay, el script para y te indica cómo iniciarla.
    #>
    $context = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $context -or -not $context.Account) {
        throw (
            "No hay sesión activa en Azure PowerShell.`n" +
            "Ejecuta: Connect-AzAccount -Tenant '$TenantId' -UseDeviceAuthentication"
        )
    }
    Write-Host "[INFO] Sesión activa como: $($context.Account.Id)" -ForegroundColor Cyan
}

function Assert-SubscriptionAccess {
    param(
        [string]$SubscriptionId,
        [string]$TenantId
    )
    <#
    Verifica que la cuenta actual tenga acceso real a la suscripción y tenant.
    Sin este check, los errores posteriores serían mensajes genéricos e incomprensibles.
    #>
    $subscription = Get-AzSubscription -SubscriptionId $SubscriptionId -TenantId $TenantId -ErrorAction SilentlyContinue
    if (-not $subscription) {
        throw (
            "No se encontró acceso a la suscripción '$SubscriptionId' en el tenant '$TenantId'.`n" +
            "Asegúrate de iniciar sesión en el tenant correcto:`n" +
            "  Disconnect-AzAccount -Scope Process`n" +
            "  Connect-AzAccount -Tenant '$TenantId' -UseDeviceAuthentication`n" +
            "  Set-AzContext -SubscriptionId '$SubscriptionId' -TenantId '$TenantId'"
        )
    }
}

function Wait-UntilReady {
    <#
    .SYNOPSIS
        Espera hasta que un recurso de Azure esté realmente disponible.

    .DESCRIPTION
        Azure puede tardar varios segundos en propagar un recurso recién creado.
        Esta función ejecuta un bloque de verificación ($CheckScript) en bucle:
          - Si el bloque devuelve algo distinto de $null → el recurso está listo.
          - Si devuelve $null → espera $IntervalSeconds segundos y reintenta.
        Después de $MaxAttempts intentos sin éxito lanza un error.

        Se usa entre cada paso de creación para evitar que el siguiente paso
        falle con errores como "NotFound" o "ResourceNotFound".

    .PARAMETER ResourceDescription
        Texto descriptivo del recurso que se está esperando (para los mensajes).

    .PARAMETER CheckScript
        Bloque de código que intenta obtener el recurso. Debe devolver el objeto
        si existe, o $null / lanzar error si aún no está disponible.

    .PARAMETER MaxAttempts
        Número máximo de intentos antes de fallar. Por defecto: 20.

    .PARAMETER IntervalSeconds
        Segundos de espera entre cada intento. Por defecto: 10.
    #>
    param(
        [string]    $ResourceDescription,
        [scriptblock]$CheckScript,
        [int]       $MaxAttempts    = 20,
        [int]       $IntervalSeconds = 10
    )

    $attempt = 0
    while ($attempt -lt $MaxAttempts) {
        $attempt++
        try {
            $result = & $CheckScript
            if ($result) {
                Write-Host "[INFO] '$ResourceDescription' confirmado disponible (intento $attempt/$MaxAttempts)." -ForegroundColor Cyan
                return $result
            }
        }
        catch {
            # El recurso aún no existe o no está listo — ignoramos el error y reintentamos
        }

        if ($attempt -lt $MaxAttempts) {
            Write-Host "[ESPERA] '$ResourceDescription' aún no disponible. Reintentando en $IntervalSeconds s... ($attempt/$MaxAttempts)" -ForegroundColor DarkYellow
            Start-Sleep -Seconds $IntervalSeconds
        }
    }

    throw "'$ResourceDescription' no estuvo disponible después de $($MaxAttempts * $IntervalSeconds) segundos. Verifica el estado en el portal de Azure."
}

# ---------------------------------------------------------------------------
# FLUJO PRINCIPAL
# Envuelto en try/catch para capturar cualquier error y mostrar un mensaje
# claro en lugar de un stack trace técnico.
# ---------------------------------------------------------------------------

try {
    Write-Host ""
    Write-Host "=== Bootstrap: Preparando Azure para Terraform ===" -ForegroundColor Cyan
    if ($WhatIf) {
        Write-Host "[WHATIF] Modo simulación activado — no se creará ningún recurso real." -ForegroundColor Magenta
    }
    Write-Host ""

    # ------------------------------------------------------------------
    # PASO 1: Validar prerequisitos
    # Siempre valida primero antes de hacer cambios en Azure.
    # ------------------------------------------------------------------
    Write-Host "[1/7] Verificando prerequisitos..." -ForegroundColor Yellow
    Assert-AzModuleInstalled
    Assert-AzConnected
    Assert-SubscriptionAccess -SubscriptionId $SubscriptionId -TenantId $TenantId

    # ------------------------------------------------------------------
    # PASO 2: Configurar el contexto de Azure
    #
    # Aunque estés en WhatIf, sí ejecutamos Set-AzContext porque los pasos
    # siguientes necesitan el contexto correcto para verificar si los
    # recursos ya existen.
    # ------------------------------------------------------------------
    Write-Host "[2/7] Configurando suscripción '$SubscriptionId' y tenant '$TenantId'..." -ForegroundColor Yellow
    Set-AzContext -SubscriptionId $SubscriptionId -TenantId $TenantId | Out-Null
    if ($WhatIf) {
        Write-Host "[WHATIF] Contexto configurado para validación (necesario incluso en modo simulación)." -ForegroundColor Magenta
    }

    # ------------------------------------------------------------------
    # PASO 3: Crear el Resource Group rg-platform
    #
    # Un Resource Group es una carpeta lógica en Azure que agrupa recursos
    # relacionados. "rg-platform" alojará el Storage Account del tfstate
    # y más adelante el Log Analytics Workspace.
    # ------------------------------------------------------------------
    Write-Host "[3/7] Creando Resource Group '$ResourceGroupName' en '$Location'..." -ForegroundColor Yellow

    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if ($rg) {
        Write-Host "[AVISO] El Resource Group '$ResourceGroupName' ya existe. Se omite la creación." -ForegroundColor Magenta
    }
    elseif ($WhatIf) {
        Write-Host "[WHATIF] Se crearía: Resource Group '$ResourceGroupName' en la región '$Location'." -ForegroundColor Magenta
    }
    else {
        New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
        Write-Host "[INFO] Resource Group '$ResourceGroupName' creado. Esperando disponibilidad..." -ForegroundColor Cyan
        # Azure puede tardar varios segundos en propagar el RG aunque ya lo haya creado.
        # Wait-UntilReady reintenta la verificación cada 10 segundos hasta confirmar
        # que el RG existe y es accesible, evitando el error 'NotFound' en el paso siguiente.
        Wait-UntilReady `
            -ResourceDescription "Resource Group '$ResourceGroupName'" `
            -CheckScript { Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue } | Out-Null
    }

    # ------------------------------------------------------------------
    # PASO 4: Crear el Storage Account para el tfstate de Terraform
    #
    # Terraform necesita guardar su "memoria" (el estado de la infraestructura)
    # en un lugar centralizado accesible desde los pipelines de GitHub Actions.
    # El Storage Account actúa como esa memoria compartida.
    #
    # Configuración de seguridad aplicada:
    #   Standard_LRS         → replicación local, suficiente y económico para tfstate
    #   StorageV2            → versión más moderna y funcional
    #   TLS1_2               → rechaza conexiones con versiones antiguas e inseguras de TLS
    #   AllowBlobPublicAccess → false: nadie en internet puede leer el tfstate
    #   EnableHttpsTrafficOnly → true: solo acepta conexiones cifradas (HTTPS)
    #
    # IMPORTANTE: En suscripciones nuevas, el proveedor 'Microsoft.Storage' puede
    # no estar registrado. Sin el registro, New-AzStorageAccount falla con 'NotFound'.
    # El script lo registra automáticamente si hace falta y espera hasta que el
    # registro esté completo antes de crear el Storage Account.
    # ------------------------------------------------------------------
    Write-Host "[4/7] Creando Storage Account '$StorageAccountName'..." -ForegroundColor Yellow

    if (-not $WhatIf) {
        # Verificar y registrar el proveedor Microsoft.Storage si no está registrado.
        # Un proveedor de recursos es el "plugin" de Azure que sabe cómo crear recursos
        # de un tipo dado. En suscripciones nuevas algunos proveedores no están activos.
        $provider = Get-AzResourceProvider -ProviderNamespace "Microsoft.Storage" -ErrorAction SilentlyContinue
        $regState = $provider | Select-Object -ExpandProperty RegistrationState -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($regState -ne "Registered") {
            Write-Host "[INFO] Registrando proveedor 'Microsoft.Storage' (necesario en suscripciones nuevas)..." -ForegroundColor Cyan
            Register-AzResourceProvider -ProviderNamespace "Microsoft.Storage" | Out-Null

            Wait-UntilReady `
                -ResourceDescription "Proveedor 'Microsoft.Storage'" `
                -MaxAttempts 30 `
                -IntervalSeconds 10 `
                -CheckScript {
                    $p = Get-AzResourceProvider -ProviderNamespace "Microsoft.Storage" -ErrorAction SilentlyContinue
                    $state = $p | Select-Object -ExpandProperty RegistrationState | Select-Object -First 1
                    if ($state -eq "Registered") { return $p } else { return $null }
                } | Out-Null

            Write-Host "[INFO] Proveedor 'Microsoft.Storage' registrado correctamente." -ForegroundColor Cyan
        }
        else {
            Write-Host "[INFO] Proveedor 'Microsoft.Storage' ya estaba registrado." -ForegroundColor Cyan
        }
    }

    # Búsqueda ampliada: primero en nuestro RG, luego en toda la suscripción.
    # Esto cubre el caso donde el SA fue creado parcialmente en un intento anterior.
    $sa = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
    if (-not $sa) {
        $sa = Get-AzStorageAccount -ErrorAction SilentlyContinue | Where-Object { $_.StorageAccountName -eq $StorageAccountName } | Select-Object -First 1
    }

    if ($sa) {
        Write-Host "[AVISO] El Storage Account '$StorageAccountName' ya existe. Se omite la creación." -ForegroundColor Magenta
    }
    elseif ($WhatIf) {
        Write-Host "[WHATIF] Se crearía: Storage Account '$StorageAccountName' (SKU: Standard_LRS, TLS 1.2, sin acceso público)." -ForegroundColor Magenta
    }
    else {
        # Verificar disponibilidad del nombre ANTES de intentar crear.
        # Los nombres de Storage Account son GLOBALMENTE únicos en todo Azure.
        # Si el nombre está tomado por otro cliente de Azure, el script falla con
        # un mensaje claro en lugar de un error técnico incomprensible.
        $nameCheck = Invoke-AzRestMethod `
            -Method POST `
            -Path "/subscriptions/$SubscriptionId/providers/Microsoft.Storage/checkNameAvailability?api-version=2023-01-01" `
            -Payload (@{ name = $StorageAccountName; type = "Microsoft.Storage/storageAccounts" } | ConvertTo-Json)

        $nameResult = $nameCheck.Content | ConvertFrom-Json
        if (-not $nameResult.nameAvailable) {
            # El nombre no está disponible. Si la razón es AlreadyExists Y el dueño
            # somos nosotros mismos, lo tratamos como idempotencia.
            if ($nameResult.reason -eq "AlreadyExists") {
                Write-Host "[AVISO] El nombre '$StorageAccountName' ya existe en Azure. Verificando si es nuestro..." -ForegroundColor Magenta
                # Buscamos una vez más; si lo encontramos, continuamos; si no, falla.
                $sa = Wait-UntilReady `
                    -ResourceDescription "Storage Account '$StorageAccountName' (verificando propietario)" `
                    -MaxAttempts 6 `
                    -IntervalSeconds 5 `
                    -CheckScript {
                        $s = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
                        if (-not $s) {
                            $s = Get-AzStorageAccount -ErrorAction SilentlyContinue | Where-Object { $_.StorageAccountName -eq $StorageAccountName } | Select-Object -First 1
                        }
                        return $s
                    }
            }
            else {
                # El nombre está tomado por OTRA cuenta de Azure (razón: AccountNameInvalid u otra).
                # Sugerimos un nombre alternativo único basado en el Subscription ID.
                $suggestedName = "stlztf" + $SubscriptionId.Replace("-","").Substring(24, 8)
                throw (
                    "El nombre '$StorageAccountName' no está disponible en Azure ($($nameResult.reason)).`n" +
                    "Los nombres de Storage Account son únicos en TODO Azure, no solo en tu suscripción.`n`n" +
                    "Solución: ejecuta el script con un nombre diferente, por ejemplo:`n" +
                    "  .\bootstrap.ps1 -StorageAccountName '$suggestedName'`n`n" +
                    "Y actualiza también el valor en backend.tf de Terraform (Fase 3)."
                )
            }
        }
        else {
            # Nombre disponible: crear el Storage Account
            New-AzStorageAccount `
                -ResourceGroupName       $ResourceGroupName `
                -Name                    $StorageAccountName `
                -Location                $Location `
                -SkuName                 "Standard_LRS" `
                -Kind                    "StorageV2" `
                -MinimumTlsVersion       "TLS1_2" `
                -AllowBlobPublicAccess   $false `
                -EnableHttpsTrafficOnly  $true | Out-Null

            Write-Host "[INFO] Storage Account '$StorageAccountName' creado. Esperando disponibilidad..." -ForegroundColor Cyan
            # Espera a que ProvisioningState sea 'Succeeded' antes de continuar al contenedor.
            $sa = Wait-UntilReady `
                -ResourceDescription "Storage Account '$StorageAccountName'" `
                -CheckScript {
                    $s = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
                    if ($s -and $s.ProvisioningState -eq 'Succeeded') { return $s } else { return $null }
                }
        }
    }

    # ------------------------------------------------------------------
    # PASO 5: Crear el contenedor de blobs para el tfstate
    #
    # Dentro del Storage Account, el tfstate se guarda como un archivo
    # en un "contenedor" (una carpeta virtual dentro del Storage Account).
    # backend.tf de Terraform apuntará a este contenedor y archivo.
    # ------------------------------------------------------------------
    Write-Host "[5/7] Creando contenedor de blobs '$ContainerName'..." -ForegroundColor Yellow

    if ($WhatIf) {
        Write-Host "[WHATIF] Se crearía: contenedor '$ContainerName' en '$StorageAccountName' (acceso privado)." -ForegroundColor Magenta
    }
    else {
        # Obtenemos el contexto de almacenamiento para operar dentro del Storage Account
        $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
        $ctx = $storageAccount.Context

        $container = Get-AzStorageContainer -Name $ContainerName -Context $ctx -ErrorAction SilentlyContinue
        if ($container) {
            Write-Host "[AVISO] El contenedor '$ContainerName' ya existe. Se omite la creación." -ForegroundColor Magenta
        }
        else {
            # Permission Off = el contenedor NO es accesible públicamente
            New-AzStorageContainer -Name $ContainerName -Context $ctx -Permission Off | Out-Null
            Write-Host "[INFO] Contenedor '$ContainerName' creado. Esperando disponibilidad..." -ForegroundColor Cyan
            # Esperamos a que el contenedor sea consultable antes de continuar.
            Wait-UntilReady `
                -ResourceDescription "Contenedor '$ContainerName'" `
                -CheckScript { Get-AzStorageContainer -Name $ContainerName -Context $ctx -ErrorAction SilentlyContinue } | Out-Null
        }
    }

    # ------------------------------------------------------------------
    # PASO 6: Crear las Federation Credentials OIDC en el Service Principal
    #
    # OIDC (OpenID Connect) permite que GitHub Actions se autentique ante
    # Azure sin contraseñas de larga duración. Funciona así:
    #   1. GitHub genera un token JWT firmado para cada ejecución de workflow
    #   2. Azure verifica la firma usando el issuer de GitHub Actions
    #   3. Si el "subject" del token coincide con una Federation Credential, permite el acceso
    #
    # Se crean 3 Federation Credentials porque los pipelines se ejecutan
    # en 3 contextos diferentes que generan subjects distintos:
    #
    #   github-main     → workflows que se ejecutan en push a la rama main
    #                     (usado por terraform-apply.yml, Fase 9.3)
    #
    #   github-env-prod → workflows que hacen deploy al environment "prod"
    #                     con required reviewer activado
    #                     (usado por terraform-apply.yml con environment: prod, Fase 9.1)
    #
    #   github-pr       → workflows que se ejecutan en Pull Requests
    #                     (usado por terraform-plan.yml, Fase 9.2)
    #
    # Si falta alguna de las 3, el pipeline fallará con el error:
    # "AADSTS700024: No matching federated identity record found"
    #
    # NOTA TÉCNICA: Usamos la Microsoft Graph REST API directamente con un token
    # obtenido por Get-AzAccessToken. Esto funciona con CUALQUIER versión del
    # módulo Az, sin depender de cmdlets específicos como
    # Get-AzADAppFederatedIdentityCredential que pueden no existir en versiones antiguas.
    # ------------------------------------------------------------------
    Write-Host "[6/7] Creando Federation Credentials OIDC en el Service Principal..." -ForegroundColor Yellow

    # Obtenemos el Application por AppId para conseguir su ObjectId interno
    $app = Get-AzADApplication -ApplicationId $ServicePrincipalAppId -ErrorAction SilentlyContinue
    if (-not $app) {
        throw (
            "No se encontró el Application con AppId '$ServicePrincipalAppId'.`n" +
            "Verifica que el Service Principal fue creado correctamente ejecutando:`n" +
            "  scripts\sp-landing-zone-cicd.ps1"
        )
    }
    $appObjectId = $app.Id

    # Definición de las 3 Federation Credentials a crear
    $fedCreds = @(
        @{
            Name     = "github-main"
            Subject  = "repo:$GitHubOrg/${GitHubRepo}:ref:refs/heads/main"
            Audience = "api://AzureADTokenExchange"
        },
        @{
            Name     = "github-env-prod"
            Subject  = "repo:$GitHubOrg/${GitHubRepo}:environment:prod"
            Audience = "api://AzureADTokenExchange"
        },
        @{
            Name     = "github-pr"
            Subject  = "repo:$GitHubOrg/${GitHubRepo}:pull_request"
            Audience = "api://AzureADTokenExchange"
        }
    )

    # Verificamos que az CLI esté disponible — es necesario para crear
    # Federation Credentials porque el token que proporciona az maneja
    # automáticamente los permisos de Microsoft Graph, a diferencia de los
    # tokens ARM que devuelve Get-AzAccessToken.
    if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
        throw (
            "Azure CLI ('az') no encontrado. Instálalo desde https://aka.ms/installazurecli`n" +
            "Es necesario para crear las Federation Credentials en Entra ID."
        )
    }

    if (-not $WhatIf) {
        # Aseguramos que az CLI esté autenticado
        $azAccount = az account show --output json 2>$null | ConvertFrom-Json
        if (-not $azAccount) {
            Write-Host "[INFO] Az CLI no autenticado. Iniciando login..." -ForegroundColor Cyan
            az login --tenant $TenantId --output none
        }
        az account set --subscription $SubscriptionId 2>$null

        # Listar las credentials existentes una sola vez (idempotencia)
        $existingCredsJson = az ad app federated-credential list --id $ServicePrincipalAppId --output json 2>$null
        $existingCreds = if ($existingCredsJson) { $existingCredsJson | ConvertFrom-Json } else { @() }
    }

    foreach ($cred in $fedCreds) {
        if ($WhatIf) {
            Write-Host "[WHATIF] Se crearía: Federation Credential '$($cred.Name)'" -ForegroundColor Magenta
            Write-Host "         Subject: '$($cred.Subject)'" -ForegroundColor Magenta
            continue
        }

        $alreadyExists = $existingCreds | Where-Object { $_.name -eq $cred.Name }

        if ($alreadyExists) {
            Write-Host "[AVISO] Federation Credential '$($cred.Name)' ya existe. Se omite." -ForegroundColor Magenta
        }
        else {
            # PowerShell + az CLI tiene problemas de quoting al pasar JSON en línea.
            # La solución más robusta es escribir el JSON en un archivo temporal
            # y pasar la ruta del archivo a --parameters.
            $tmpJson = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$($cred.Name).json")
            @{
                name      = $cred.Name
                issuer    = "https://token.actions.githubusercontent.com"
                subject   = $cred.Subject
                audiences = @($cred.Audience)
            } | ConvertTo-Json | Set-Content -Path $tmpJson -Encoding UTF8

            az ad app federated-credential create `
                --id         $ServicePrincipalAppId `
                --parameters $tmpJson `
                --output     none

            Remove-Item -Path $tmpJson -Force -ErrorAction SilentlyContinue

            if ($LASTEXITCODE -ne 0) {
                throw "Error al crear Federation Credential '$($cred.Name)' con az CLI."
            }

            Write-Host "[INFO] Federation Credential '$($cred.Name)' creada. Esperando disponibilidad..." -ForegroundColor Cyan
            # Esperamos a que Entra ID propague la credential antes de crear la siguiente.
            $credName = $cred.Name
            Wait-UntilReady `
                -ResourceDescription "Federation Credential '$credName'" `
                -CheckScript {
                    $checkJson = az ad app federated-credential list --id $ServicePrincipalAppId --output json 2>$null
                    if ($checkJson) {
                        ($checkJson | ConvertFrom-Json) | Where-Object { $_.name -eq $credName }
                    }
                } | Out-Null
        }
    }

    # ------------------------------------------------------------------
    # PASO 7: Asignar rol "Storage Blob Data Contributor" al Service Principal
    #
    # Aunque el Service Principal ya tiene el rol "Contributor" en la
    # suscripción (creado por sp-landing-zone-cicd.ps1), ese rol NO es
    # suficiente para leer y escribir datos dentro del Storage Account.
    # En Azure, el acceso a los DATOS de un storage (los blobs) requiere
    # un rol específico del plano de datos: "Storage Blob Data Contributor".
    #
    # Este rol se asigna solo sobre el Storage Account del tfstate
    # (no sobre toda la suscripción) para respetar el principio de
    # mínimo privilegio: el SP solo accede al storage que necesita.
    # ------------------------------------------------------------------
    Write-Host "[7/7] Asignando rol 'Storage Blob Data Contributor' al Service Principal..." -ForegroundColor Yellow

    $sp = Get-AzADServicePrincipal -ApplicationId $ServicePrincipalAppId -ErrorAction SilentlyContinue
    if (-not $sp) {
        throw "No se encontró el Service Principal con AppId '$ServicePrincipalAppId'."
    }

    $roleName    = "Storage Blob Data Contributor"
    $storageScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$StorageAccountName"

    if ($WhatIf) {
        Write-Host "[WHATIF] Se asignaría: rol '$roleName' al SP '$ServicePrincipalAppId'" -ForegroundColor Magenta
        Write-Host "         Scope: $storageScope" -ForegroundColor Magenta
    }
    else {
        $existingRole = Get-AzRoleAssignment `
            -ObjectId           $sp.Id `
            -RoleDefinitionName $roleName `
            -Scope              $storageScope `
            -ErrorAction        SilentlyContinue

        if ($existingRole) {
            Write-Host "[AVISO] El rol '$roleName' ya estaba asignado. No se duplica." -ForegroundColor Magenta
        }
        else {
            New-AzRoleAssignment `
                -ObjectId           $sp.Id `
                -RoleDefinitionName $roleName `
                -Scope              $storageScope | Out-Null

            Write-Host "[INFO] Rol '$roleName' asignado correctamente." -ForegroundColor Cyan
        }
    }

    # ------------------------------------------------------------------
    # RESULTADO FINAL
    # ------------------------------------------------------------------
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green

    if ($WhatIf) {
        Write-Host " [WHATIF] Simulación completada — no se creó ningún recurso.  " -ForegroundColor Magenta
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host " Ejecuta el script sin -WhatIf para crear los recursos reales:" -ForegroundColor Yellow
        Write-Host "   .\bootstrap.ps1"
    }
    else {
        Write-Host " [OK] Bootstrap completado exitosamente                      " -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host " Recursos creados / verificados:" -ForegroundColor Yellow
        Write-Host "   Resource Group:       $ResourceGroupName"
        Write-Host "   Storage Account:      $StorageAccountName"
        Write-Host "   Contenedor blob:      $ContainerName"
        Write-Host "   Fed. Credentials:     github-main, github-env-prod, github-pr"
        Write-Host "   Rol RBAC (storage):   $roleName"
        Write-Host ""
        Write-Host " SIGUIENTE PASO — Fase 3: crear los archivos Terraform." -ForegroundColor Yellow
        Write-Host " El archivo backend.tf debe apuntar a:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "   terraform {"
        Write-Host "     backend `"azurerm`" {"
        Write-Host "       resource_group_name  = `"$ResourceGroupName`""
        Write-Host "       storage_account_name = `"$StorageAccountName`""
        Write-Host "       container_name       = `"$ContainerName`""
        Write-Host "       key                  = `"landing-zone.tfstate`""
        Write-Host "     }"
        Write-Host "   }"
    }

    Write-Host ""
}
catch {
    # Ayuda adicional para el error más común: tenant incorrecto
    if ($_.Exception.Message -match "valid tenant|valid subscription|AADSTS") {
        Write-Host ""
        Write-Host "[AYUDA] Parece que estás autenticado en el tenant incorrecto." -ForegroundColor Yellow
        Write-Host "Ejecuta estos comandos y vuelve a correr el script:" -ForegroundColor Yellow
        Write-Host "  Disconnect-AzAccount -Scope Process"
        Write-Host "  Connect-AzAccount -Tenant '$TenantId' -UseDeviceAuthentication"
        Write-Host "  Set-AzContext -SubscriptionId '$SubscriptionId' -TenantId '$TenantId'"
        Write-Host ""
    }
    Write-Error "[ERROR] $($_.Exception.Message)"
    exit 1
}
