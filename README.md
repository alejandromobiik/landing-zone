# Landing Zone — Mini Plataforma en Azure con CI/CD y GitHub Copilot

> Evaluación final del path de capacitación · Modalidad individual · 16 h
> Autor: Alejandro Arelis · [@alejandromobiik](https://github.com/alejandromobiik)

---

## ¿Qué es este proyecto?

Este repositorio construye una **landing zone** (zona de aterrizaje) en Azure.
Una landing zone es la infraestructura base que una empresa monta *antes* de desplegar sus aplicaciones: redes, seguridad, registros, permisos y automatización listos para usar.

En lugar de hacer clic en el portal de Azure, todo se escribe como código. Eso significa que:
- Cualquier cambio queda registrado en Git (historial completo).
- Un robot (pipeline de GitHub Actions) valida y despliega los cambios automáticamente.
- Si algo se rompe, se puede volver atrás con un solo comando.

El código se escribe con la asistencia de **GitHub Copilot**, documentando cómo se usó el asistente en cada pieza.

---

## Arquitectura

```mermaid
graph TB
    subgraph GitHub
        PR[Pull Request] -->|terraform plan| GHA_PLAN[workflow: terraform-plan]
        MERGE[Merge a main] -->|terraform apply| GHA_APPLY[workflow: terraform-apply]
        GHA_BUILD[workflow: app-build-deploy] -->|kubectl apply| AKS
    end

    subgraph Azure["Azure — Suscripción 1989a8c1"]
        subgraph RG_PLATFORM["rg-platform"]
            SA[Storage Account\nstlztf86c66635\ntfstate remoto]
            LAW[Log Analytics\nlaw-lz-dev]
        end

        subgraph RG_HUB["rg-network-hub-lz-dev"]
            VNET_HUB[VNet Hub\n10.0.0.0/16]
            DNS[Private DNS Zones\nazurecr.io\nvaultcore.azure.net\nazmk8s.io]
            NSG_HUB[NSG Hub]
        end

        subgraph RG_SPOKE["rg-spoke-app-lz-dev"]
            VNET_SPOKE[VNet Spoke\n10.1.0.0/16]
            AKS[AKS PRIVADO\naks-lz-dev\nsystem + user pool\nOIDC + Workload Identity]
            ACR[ACR Basic\nacrlzdev66635]
            KV[Key Vault\nkv-lz-dev-66635]
            NSG_SPOKE[NSG Spoke]
        end

        subgraph RG_SHARED["rg-shared-lz-dev"]
            SHARED[Recursos compartidos\nentre spokes]
        end

        VNET_HUB <-->|VNet Peering| VNET_SPOKE
        LAW --> AKS
        LAW --> KV
        LAW --> NSG_HUB
        LAW --> NSG_SPOKE
        AKS -->|managed identity| ACR
        AKS -->|CSI driver| KV
    end

    GHA_PLAN -->|OIDC sin contraseñas| Azure
    GHA_APPLY -->|OIDC sin contraseñas| Azure
    GHA_BUILD -->|OIDC sin contraseñas| Azure
```

---

## Cómo sustituimos lo que normalmente vive en el tenant

La evaluación exige trabajar **solo con permisos de suscripción** (sin management groups corporativos). Esta tabla explica cómo se resuelve cada limitación:

| Lo que normalmente está en el tenant | Cómo lo sustituimos aquí |
|--------------------------------------|--------------------------|
| Management Groups y jerarquía corporativa | 4 Resource Groups por tier (`rg-platform`, `rg-network-hub`, `rg-spoke-app`, `rg-shared`) con la jerarquía documentada |
| Azure Policy a nivel tenant/MG | 3 policies builtin a nivel de suscripción y RG: tags obligatorios, ubicaciones permitidas, deny de acceso público en Storage |
| Hub central compartido con ExpressRoute | Hub-spoke dentro de la suscripción con VNet Peering local, NSGs y Private Endpoints |
| Administración de Entra ID | Managed Identities (system y user-assigned) + RBAC sobre recursos concretos |
| Defender for Cloud corporativo | Planes de Defender habilitados a nivel de suscripción (Servers, Containers, Key Vault) |
| Log Analytics workspace central del tenant | Workspace propio en `rg-platform` con diagnostic settings desde cada recurso |

---

## Estructura del repositorio

```
landing-zone/
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml      # Se ejecuta en cada Pull Request
│       ├── terraform-apply.yml     # Se ejecuta al hacer merge a main
│       └── app-build-deploy.yml    # Build de imagen Docker → push ACR → deploy AKS
├── app/
│   ├── app.py                      # Aplicación Flask mínima
│   ├── requirements.txt
│   └── Dockerfile                  # Multi-stage: build + imagen final ligera
├── infra/
│   └── terraform/
│       ├── modules/
│       │   ├── network/            # VNets, subnets, NSGs, peering, DNS privado
│       │   ├── aks/                # Clúster Kubernetes privado
│       │   ├── acr/                # Azure Container Registry
│       │   ├── keyvault/           # Key Vault con Private Endpoint
│       │   ├── monitoring/         # Log Analytics, alertas, KQL
│       │   └── policy/             # Azure Policies (tags, ubicaciones, storage)
│       ├── main.tf                 # Orquestador: llama a todos los módulos
│       ├── variables.tf            # Variables de entrada (location, environment…)
│       ├── outputs.tf              # Valores que expone el módulo raíz
│       ├── providers.tf            # Versiones de Terraform y proveedores Az
│       ├── backend.tf              # Dónde se guarda el estado (Azure Storage)
│       └── .terraform.lock.hcl    # Lock de versiones exactas de providers
├── docs/
│   ├── commands-log.txt            # Registro cronológico de todos los comandos
│   ├── copilot-log.md              # Bitácora de uso de GitHub Copilot
│   ├── architecture.md             # Diagrama detallado y decisiones de diseño
│   └── practicas-y-reglas.md      # Reglas y lecciones aprendidas del proyecto
├── scripts/
│   └── bootstrap.ps1              # Script de preparación de Azure (idempotente)
└── README.md                       # Este archivo
```

---

## Estado actual del proyecto

### ✅ Completado

| Fase | Descripción | Recursos en Azure |
|------|-------------|-------------------|
| **Fase 0** | Herramientas instaladas (VS Code, Git, Azure CLI, Terraform, pwsh, kubectl, Docker) | — |
| **Fase 1** | Repositorio GitHub con branch protection en `main` (PR obligatorio + 1 approval) | — |
| **Fase 2** | Script `bootstrap.ps1` idempotente con `-WhatIf`, Federation Credentials OIDC, RBAC | `rg-platform`, Storage Account `stlztf86c66635`, contenedor `tfstate` |
| **Fase 3** | Backend remoto, providers, variables, outputs, `main.tf` con 4 Resource Groups + 6 módulos (network, monitoring, policy, keyvault, acr, aks). El módulo AKS cumple el PDF: privado, OIDC, Workload Identity, system + user node pool. | `rg-network-hub-lz-dev`, `rg-spoke-app-lz-dev`, `rg-shared-lz-dev`, red hub-spoke, `law-lz-dev`, 5 policies, `kv-lz-dev-66635` + PE, `acrlzdev66635`, `aks-lz-dev` |
| **Fase 4** | Hub-spoke, DNS privado y NSGs (implementados en el módulo `network` de la Fase 3). **Bastion omitido** — el PDF lo marca opcional (§3.3); costo $0 y acceso al cluster vía `az aks command invoke`. | Igual que recursos de red anteriores; checklist cerrado en el plan |
| **Fase 5** | Defender for Cloud (VMs, Containers, Key Vault); Managed Identity del workload + federación OIDC + `Key Vault Secrets User`; secreto en KV documentado abajo (paso manual con RBAC). | Planes Defender; `mi-applzdev`; federation credential `fc-applzdev`; RBAC KV para la app |
| **Fase 6** | Diagnostic Settings (AKS, KV, NSGs → LAW); alerta métrica CPU API server AKS > 80 % (métricas de nodo PREVIEW no admitidas en alerta métrica clásica) y regla KQL pods `Failed`; prueba de disparo pendiente. | `diag-aks`, `diag-kv`, `diag-nsg-*`; `alert-aks-cpu`, `alert-pods-failed`; Action Group `ag-lz` |

### ⏳ Pendiente

| Fase | Descripción |
|------|-------------|
| **Manual post-apply** | Tras `terraform apply`: asignarte rol **Key Vault Secrets Officer** sobre el vault y ejecutar `az keyvault secret set` para `app-message`. Opcional: probar disparo de alertas (pod de estrés / pod fallido). |
| **Fase 7** | Verificaciones `az acr show`, `az aks check-acr`, `az aks command invoke` (nodos Ready). |
| **Fase 8** | App Flask en `app/` + Dockerfile multi-stage + manifiestos K8s + script `app/scripts/deploy-phase8.ps1` (ejecutar con Docker/Azure CLI operativos) |
| **Fase 9** | Pipelines GitHub Actions con OIDC (plan en PR, apply en merge, build+deploy) |
| **Fase 10** | Documentación final, bitácora de Copilot, diagrama en `/docs` |

---

## Cómo reproducir este proyecto desde cero

### Prerequisitos

- Cuenta de Azure con suscripción activa
- [Visual Studio Code](https://code.visualstudio.com) con extensiones: GitHub Copilot, Terraform, Azure Tools, YAML
- [Git](https://git-scm.com)
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) — verifica con `az --version`
- [Terraform >= 1.7](https://developer.hashicorp.com/terraform/downloads)
- [PowerShell 7](https://github.com/PowerShell/PowerShell/releases) (`pwsh`) con módulo Az instalado
- [kubectl](https://kubernetes.io/docs/tasks/tools/) y [Docker Desktop](https://www.docker.com/products/docker-desktop/)

### Paso 1 — Clonar el repositorio

```bash
git clone https://github.com/alejandromobiik/landing-zone.git
cd landing-zone
```

### Paso 2 — Ejecutar el bootstrap de Azure

El script crea el Resource Group y Storage Account donde Terraform guarda su estado, las credenciales OIDC del Service Principal y el RBAC necesario.

```powershell
# Primero simula qué haría (sin crear nada)
pwsh -File scripts\bootstrap.ps1 -WhatIf

# Luego ejecuta de verdad
pwsh -File scripts\bootstrap.ps1
```

> El script es **idempotente**: puedes ejecutarlo varias veces sin error. Si un recurso ya existe, lo detecta y continúa.

### Paso 3 — Inicializar Terraform

```bash
cd infra/terraform
terraform init      # descarga los providers y conecta con el backend de Azure
terraform validate  # verifica la sintaxis
terraform plan -out=tfplan  # calcula los cambios (sin aplicarlos)
terraform apply "tfplan"    # crea/modifica los recursos
```

### Paso 4 — Flujo de cambios (después de la configuración inicial)

Cualquier cambio al código de infraestructura sigue este flujo:

```
1. Crea una rama: git checkout -b feat/mi-cambio
2. Edita los archivos .tf
3. Verifica: terraform fmt -recursive && terraform validate
4. Commit y push: git add . && git commit -m "descripción" && git push origin feat/mi-cambio
5. Abre un Pull Request en GitHub
   → El pipeline terraform-plan.yml se ejecuta automáticamente
   → El resultado del plan aparece como comentario en el PR
6. Aprueba el PR y haz merge a main
   → El pipeline terraform-apply.yml se ejecuta y aplica los cambios
```

---

## Decisiones de diseño importantes

### ¿Por qué Terraform y no Bicep?
Terraform es agnóstico de proveedor (funciona con Azure, AWS, GCP), tiene un ecosistema de módulos muy maduro y es la herramienta más demandada en el mercado para IaC multi-cloud.

### ¿Por qué estado remoto en Azure Storage?
El estado local (en tu máquina) hace imposible que los pipelines de CI/CD funcionen. Azure Storage habilita automáticamente el "state locking": si dos pipelines intentan aplicar cambios al mismo tiempo, el segundo espera — evitando corrupción del estado.

### ¿Por qué OIDC en lugar de Client Secret?
Un Client Secret es una contraseña que puede filtrarse si alguien accede al repositorio. OIDC genera un token temporal que Azure verifica directamente con GitHub — sin contraseñas almacenadas, sin riesgo de filtración.

### ¿Por qué ACR Basic en lugar de Premium?
El proyecto usa una suscripción de Free Trial con presupuesto limitado. ACR Basic cuesta ~$0.17/día vs ~$1.67/día de Premium. Los Private Endpoints de ACR (que requieren Premium) se implementan a nivel de NSG en su lugar.

### ¿Por qué AKS con `Standard_D2s_v3` y dos node pools?
El PDF de la evaluación exige *"AKS privado con node pool de sistema y de usuario"* (sección 3.3). El cluster por tanto tiene **dos** node pools:

- **system** (1 nodo `Standard_D2s_v3`): corre los componentes internos de Kubernetes (CoreDNS, metrics-server, etc.).
- **user** (1 nodo `Standard_D2s_v3`): corre tus aplicaciones (Fase 8 del plan).

`Standard_B2s` (más barato) no está disponible en suscripciones Free Trial en `eastus2`. `Standard_D2s_v3` (2 vCPU, 8 GB, ~$70/mes por nodo) es el más económico permitido por la suscripción. El cluster usa SKU Free (control plane gratis).

**Costo total con cluster encendido 24/7: ~$140/mes (2 nodos × ~$70/mes).** Con el crédito Free Trial de 200 USD por 30 días, el cluster encendido 24/7 lo consume en ~43 días. Por eso es **indispensable** parar el cluster cuando no trabajes:

```bash
az aks stop  --name aks-lz-dev --resource-group rg-spoke-app-lz-dev
az aks start --name aks-lz-dev --resource-group rg-spoke-app-lz-dev
```

### ¿Cómo se accede a un AKS privado?
Como el API server NO es accesible desde internet, `kubectl` desde tu máquina o desde GitHub Actions no funciona directamente. Hay tres opciones, en orden de simplicidad:

1. **`az aks command invoke`** (recomendado, sin costo extra): tunneliza comandos `kubectl` por Azure ARM, sin necesidad de estar en la VNet. Ejemplo:
   ```bash
   az aks command invoke --resource-group rg-spoke-app-lz-dev --name aks-lz-dev --command "kubectl get nodes"
   ```
2. **Self-hosted GitHub Actions runner** desplegado dentro de la VNet spoke (Fase 9 del plan).
3. **Jumpbox** (VM `Standard_B1s` ~$8/mes) o **Azure Bastion** (~$140/mes) en el hub.

---

## Seguridad

- **Cero secretos en el repositorio**: los valores sensibles se marcan como `sensitive = true` en Terraform y se consumen desde Key Vault en runtime.
- **OIDC para CI/CD**: los pipelines se autentican mediante Workload Identity Federation, sin credenciales de larga duración.
- **AKS privado**: el API server del cluster no es accesible desde internet. El acceso se hace por `az aks command invoke` o desde dentro de la red.
- **OIDC + Workload Identity en AKS**: los pods se autentican ante Azure (Key Vault, etc.) usando tokens temporales emitidos por el cluster, sin almacenar credenciales en el contenedor.
- **Mínimo privilegio**: el Service Principal solo tiene `Contributor` en la suscripción y `Storage Blob Data Contributor` en el Storage Account del tfstate.
- **Network isolation**: Key Vault tiene Private Endpoint (sin acceso público). AKS usa Azure CNI en subnet privada. ACR Basic protegido por managed identity (`admin_enabled = false`) — el PDF no exige Private Endpoint para ACR, solo "integrado por managed identity".

---

## Uso de GitHub Copilot

Todo el código de este proyecto fue escrito con asistencia de GitHub Copilot. La bitácora completa de prompts, sugerencias aceptadas/rechazadas y casos donde Copilot se equivocó está en [docs/copilot-log.md](docs/copilot-log.md).

---

## Licencia

Proyecto de evaluación educativa · Sin licencia de producción.
