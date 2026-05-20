# Runbook — Ahorro de costos (AKS + ACR) sin tocar Terraform state

## Objetivo

Bajar el gasto recurrente del laboratorio (sobre todo **compute de AKS** y **almacenamiento de imágenes en ACR**) sin destruir la landing zone ni el backend de estado de Terraform.

## Qué hace cada script

| Script | Acción principal |
|--------|-------------------|
| [scripts/cost-down-off.ps1](../scripts/cost-down-off.ps1) | Limpia despliegue Fase 8 (`lz-app`), **para AKS**, opcionalmente purga repos ACR con `-ConfirmAcrPurge`. |
| [scripts/cost-down-on.ps1](../scripts/cost-down-on.ps1) | **Arranca AKS** y espera a `Running`/`Succeeded` y nodos **Ready**. |

## Qué no hacen (importante)

- **No** borran ni vacían el contenedor **`tfstate`** del Storage Account **`stlztf86c66635`** (bootstrap / `rg-platform`). Romperlo deja Terraform sin estado.
- **No** eliminan Log Analytics Workspace (`law-lz-dev`). El coste de LAW suele venir de **ingesta y retención**; para reducirlo hay que bajar retención o ajustar diagnósticos en Terraform o Portal (fuera de estos scripts).
- **No** desactivan **Defender for Cloud** ni policies de suscripción (evita drift con el código Terraform y requisitos de evaluación).

## Red de laboratorio (Key Vault) vs error TLS a Microsoft

En esta landing zone el Key Vault suele tener **`publicNetworkAccess = Disabled`** y acceso por Private Endpoint (ver [runbook-kv-temporal-access.md](runbook-kv-temporal-access.md)). Desde tu PC **sin** VPN/VNet, conviene **abrir el vault primero** si vas a tocar secretos o quieres dejar la capa de datos accesible durante la sesión.

Los scripts admiten **`-OpenKeyVaultPublicFirst`**: ejecutan `az keyvault update ... --public-network-access Enabled` al inicio y **no vuelven a cerrar** el vault (queda abierto hasta que lo cambies tú o Terraform), como pediste para operar con la red “abierta”.

Eso **no sustituye** una cadena TLS correcta hacia **`login.microsoftonline.com`**: si `az` falla ahí al renovar token, el problema es de **confianza de certificados en el equipo o en la ruta TLS** (no del Key Vault). En ese caso sigue fallando también `az aks stop` hasta que `az account show` funcione sin error.

## Uso recomendado

### Simulación

```powershell
cd landing-zone
pwsh -File scripts/cost-down-off.ps1 -WhatIf
pwsh -File scripts/cost-down-on.ps1 -WhatIf
```

### Apagar (producción del comando)

```powershell
# Opcional (laboratorio): abrir Key Vault al inicio y dejarlo en público
pwsh -File scripts/cost-down-off.ps1 -OpenKeyVaultPublicFirst

# Sin borrar imágenes ACR (solo K8s + stop AKS)
pwsh -File scripts/cost-down-off.ps1

# También borrar repo(s) ACR (irreversible): requiere flag explícito
pwsh -File scripts/cost-down-off.ps1 -ConfirmAcrPurge

# Sin tocar ACR ni kubectl (solo stop AKS)
pwsh -File scripts/cost-down-off.ps1 -SkipK8sCleanup -SkipAcrPurge
```

### Encender

```powershell
pwsh -File scripts/cost-down-on.ps1 -OpenKeyVaultPublicFirst   # opcional, mismo criterio que al apagar
pwsh -File scripts/cost-down-on.ps1
```

Parámetros opcionales: `-MaxWaitMinutes 45`, `-PollIntervalSeconds 30`.

### Tras purgar ACR

Vuelve a construir y desplegar la app (Fase 8):

```powershell
cd app
pwsh -File scripts/deploy-phase8.ps1
```

Ver [app/README.md](../app/README.md).

## Costos que pueden seguir apareciendo

- **ACR Basic**: coste base pequeño aunque el registry esté vacío.
- **Discos / recursos MC_** asociados a AKS: pueden generar coste residual según SKU (consulta Cost Management).
- **Log Analytics**: histórico ya ingerido y retención.
- **Red** (VNet, DNS privado, peering): costes típicamente bajos frente a compute.

## Coordinación con Terraform

No ejecutes `terraform apply` al mismo tiempo que `cost-down-off` sobre el mismo cluster: el provider puede fallar si AKS está en transición o parado.

## Referencias

- Bootstrap: [scripts/bootstrap.ps1](../scripts/bootstrap.ps1)
- Backend tfstate: [infra/terraform/backend.tf](../infra/terraform/backend.tf)
- Despliegue app: [app/scripts/deploy-phase8.ps1](../app/scripts/deploy-phase8.ps1)
