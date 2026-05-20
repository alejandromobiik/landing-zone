# Runbook — Acceso temporal a Key Vault sin VPN

## Objetivo
Crear/actualizar secretos en `kv-lz-dev-66635` cuando no existe conectividad privada (VPN/jumpbox/VNet), minimizando riesgo y dejando evidencia.

## Cuándo usarlo
- Entorno de laboratorio o prueba.
- `publicNetworkAccess` del Key Vault está en `Disabled`.
- La operación falla con `ForbiddenByConnection`.

## Cuándo NO usarlo
- Producción con alternativa privada disponible.
- Ventanas sin supervisión o sin capacidad de rollback inmediato.

## Prerrequisitos
- Azure CLI autenticado en la suscripción correcta.
- Rol data-plane suficiente sobre el vault (recomendado: `Key Vault Administrator` o `Key Vault Secrets Officer` para secretos).
- Nombre del vault: `kv-lz-dev-66635`.

## Pre-checks
```bash
az account show --query "{subscription:id,user:user.name}" -o table
az keyvault show --name kv-lz-dev-66635 --query "{name:name, publicNetworkAccess:properties.publicNetworkAccess}" -o table
```

## Procedimiento (paso a paso)

1. **Habilitar acceso público temporal**
```bash
az keyvault update --name kv-lz-dev-66635 --public-network-access Enabled
```

2. **Crear o actualizar secreto**
```bash
az keyvault secret set --vault-name kv-lz-dev-66635 --name "app-message" --value "Hola desde Key Vault"
```

3. **Validar secreto**
```bash
az keyvault secret show --vault-name kv-lz-dev-66635 --name "app-message" --query "{name:name,enabled:attributes.enabled,updated:attributes.updated}" -o table
```

4. **Cerrar acceso público inmediatamente**
```bash
az keyvault update --name kv-lz-dev-66635 --public-network-access Disabled
```

5. **Validar estado final seguro**
```bash
az keyvault show --name kv-lz-dev-66635 --query "{name:name, publicNetworkAccess:properties.publicNetworkAccess}" -o table
```

Resultado esperado: `publicNetworkAccess = Disabled`.

## Verificación adicional de permisos RBAC (opcional)
```bash
$uid = az ad signed-in-user show --query id -o tsv
az role assignment list --assignee-object-id $uid --scope "/subscriptions/1989a8c1-76c1-4555-a228-c95f86c66635/resourceGroups/rg-spoke-app-lz-dev/providers/Microsoft.KeyVault/vaults/kv-lz-dev-66635" --query "[].{role:roleDefinitionName,scope:scope}" -o table
```

## Rollback / contingencia
- Si falla la carga del secreto, **cerrar acceso público de inmediato**:
```bash
az keyvault update --name kv-lz-dev-66635 --public-network-access Disabled
```
- Confirmar estado:
```bash
az keyvault show --name kv-lz-dev-66635 --query "properties.publicNetworkAccess" -o tsv
```

## Riesgos y mitigaciones
- **Riesgo**: exposición temporal por habilitar acceso público.
- **Mitigación**: ventana mínima, operador presente, validación y cierre inmediato.
- **Riesgo**: confusión de permisos (`Owner` no implica data-plane completo).
- **Mitigación**: usar rol de Key Vault RBAC adecuado (`Key Vault Administrator` / `Secrets Officer`).

## Evidencia mínima para defensa
- Salida de:
  - `az keyvault secret show ... app-message`
  - `az keyvault show ... publicNetworkAccess`
- Registro en:
  - `docs/commands-log.txt`
  - `docs/copilot-log.md`
