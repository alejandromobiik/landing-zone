# Bitácora de uso de Copilot

## Caso 1 — Revisión de recomendaciones de Defender (Fase 5.4.2)

**Contexto**
- Se habilitaron por Terraform los planes de Defender requeridos por el alcance del proyecto:
  - `VirtualMachines` (Standard, subplan `P2`)
  - `Containers` (Standard)
  - `KeyVaults` (Standard, subplan `PerKeyVault`)
- Objetivo de este caso: evidenciar la revisión de recomendaciones y documentar cuáles se consideran aplicadas vs. fuera de alcance.

**Comandos usados**
```bash
az security assessment list --query "[?status.code=='Unhealthy'].{recommendation:displayName,resource:resourceDetails.ResourceName,resourceType:resourceDetails.ResourceType}" -o table

az rest --method get --uri "https://management.azure.com/subscriptions/1989a8c1-76c1-4555-a228-c95f86c66635/providers/Microsoft.Security/pricings?api-version=2024-01-01" --query "value[].{name:name,pricingTier:properties.pricingTier,subPlan:properties.subPlan}" -o table
```

**Resultado observado**
- Confirmado por API de Microsoft.Security:
  - `VirtualMachines`: `Standard` (`P2`)
  - `Containers`: `Standard`
  - `KeyVaults`: `Standard` (`PerKeyVault`)
- En recomendaciones `Unhealthy` aparecen también items fuera del alcance/costo objetivo del proyecto, por ejemplo:
  - ACR con Private Link
  - Hardening de Storage Account de `tfstate` (red privada, shared key)
  - Defender adicionales no exigidos por el PDF (Resource Manager, Storage, etc.)

**Qué se considera aplicado en este proyecto**
- Habilitación de Defender para Servers, Containers y Key Vault en Terraform.
- Diagnostic Settings en AKS/Key Vault/NSG hacia Log Analytics para trazabilidad operativa.

**Qué queda explícitamente fuera de alcance (por costo o alcance funcional)**
- ACR con Private Link/Premium.
- Endurecimiento completo del Storage Account de backend con conectividad privada.
- Activar todos los planes Defender no requeridos por la evaluación.

**Nota**
- Tras cambios recientes de Defender, algunas recomendaciones pueden tardar en reflejar estado `Healthy` por latencia de evaluación de la plataforma.

## Caso 2 — Prueba de alerta KQL (Fase 6.3.3)

**Objetivo**
- Validar en entorno real la condición de disparo de la regla `alert-pods-failed-lz-dev` (Scheduled Query Rule v2).

**Prueba ejecutada**
```bash
az aks command invoke --resource-group rg-spoke-app-lz-dev --name aks-lz-dev --command "kubectl run lz-failed-test --image=busybox --restart=Never -- /bin/sh -c 'exit 1'"
az aks command invoke --resource-group rg-spoke-app-lz-dev --name aks-lz-dev --command "kubectl get pod lz-failed-test -o jsonpath='{.status.phase}'"
```

Resultado: `Failed`.

Se repitió con `lz-failed-test2` para asegurar registros dentro de múltiples ciclos de evaluación.

**Evidencia de ingesta en Log Analytics**
```bash
az monitor log-analytics query --workspace <customerId-law-lz-dev> --analytics-query "KubePodInventory | where TimeGenerated > ago(15m) | where Name == 'lz-failed-test2' | summarize failed_count=count() by PodStatus" -o table
```

Resultado observado:
- `PodStatus = Failed`
- `failed_count = 6` (en la ventana consultada)

**Interpretación**
- La consulta KQL de la regla (`PodStatus == "Failed"` en 5m) recibió datos reales que cumplen su umbral (`> 0`), por lo que la condición de activación quedó validada.
- Los pods de prueba se eliminaron al finalizar para no dejar ruido operativo.

## Caso 3 — Alta temporal de red pública para cargar secreto en Key Vault (Fase 5.1.3)

**Contexto**
- El vault `kv-lz-dev-66635` está con `publicNetworkAccess = Disabled` y Private Endpoint.
- Sin VPN/jumpbox/red privada, `az keyvault secret set` devuelve `ForbiddenByConnection`.

**Ejecución temporal (laboratorio)**
```bash
az keyvault update --name kv-lz-dev-66635 --public-network-access Enabled
az keyvault secret set --vault-name kv-lz-dev-66635 --name "app-message" --value "Hola desde Key Vault"
az keyvault secret show --vault-name kv-lz-dev-66635 --name "app-message"
az keyvault update --name kv-lz-dev-66635 --public-network-access Disabled
az keyvault show --name kv-lz-dev-66635 --query "{name:name, publicNetworkAccess:properties.publicNetworkAccess}"
```

**Resultado**
- Se creó y validó el secreto `app-message`.
- El vault volvió a estado seguro: `publicNetworkAccess = Disabled`.

**Regla operativa documentada**
- En entornos de prueba sin conectividad privada, abrir red pública solo durante la operación, validar y cerrar inmediatamente.
- En entorno productivo, preferir acceso desde red privada (VPN/jumpbox/runner en VNet) sin abrir red pública.
