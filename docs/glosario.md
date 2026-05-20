# Glosario — Landing Zone

> Términos técnicos que aparecen en este proyecto, explicados en lenguaje simple.
> Ordenados alfabéticamente.

---

## A

### ACR — Azure Container Registry
Es como un almacén privado de fotos, pero en lugar de fotos guarda **imágenes de contenedor** (los paquetes que contienen tu aplicación lista para ejecutarse). Solo tu clúster AKS tiene acceso — nadie más puede descargar imágenes desde internet.

### AKS — Azure Kubernetes Service
Es el servicio de Azure que ejecuta Kubernetes. Kubernetes es el sistema que administra los contenedores de tu aplicación: decide en qué máquina correr cada pieza, cuántas copias tener, y las reinicia automáticamente si se caen. AKS hace que Kubernetes sea más fácil de usar porque Azure gestiona la parte más compleja (el "control plane").

### apply — `terraform apply`
El comando que **realmente crea o modifica** los recursos en Azure. Antes de apply siempre hay un `plan`. Si el plan dice "voy a crear 3 cosas", el apply las crea. Es el paso que cobra dinero.

### ARM — Azure Resource Manager
El sistema interno de Azure que procesa todas las peticiones de creación, modificación y borrado de recursos. Cuando Terraform crea un recurso, habla con ARM a través de su API.

---

## B

### Backend (Terraform)
Dónde Terraform guarda su "memoria" del estado de la infraestructura (el archivo `tfstate`). En este proyecto el backend está en un Azure Storage Account, no en tu máquina. Eso permite que los pipelines y cualquier persona del equipo puedan leer el estado.

### Bootstrap
El paso previo a Terraform. El script `bootstrap.ps1` crea manualmente los recursos que Terraform necesita para poder funcionar (principalmente el Storage Account del estado). Es el "huevo antes que la gallina": no puedes usar Terraform para crear el lugar donde Terraform guardará su estado.

### Branch (rama)
Una copia paralela del código en Git. Creas una rama para trabajar en un cambio sin afectar la versión principal (`main`). Cuando terminas, haces un Pull Request para mezclar tu rama con `main`.

### Branch Protection
Reglas que protegen la rama `main` en GitHub. En este proyecto: nadie puede subir código directamente a `main` — todo debe pasar por un Pull Request con al menos 1 aprobación.

---

## C

### CAF — Cloud Adoption Framework
El conjunto de buenas prácticas de Microsoft para adoptar Azure en empresas. Define cómo organizar suscripciones, grupos de recursos, políticas y seguridad. En este proyecto seguimos el "espíritu" de CAF pero adaptado a una sola suscripción (sin management groups corporativos).

### CIDR
Forma de escribir un rango de IPs. `10.0.0.0/16` significa "todas las IPs que empiezan con 10.0, del .0.0 al .255.255" — son 65,536 IPs. El número después de `/` indica cuántas IPs tiene el rango: menor número = más IPs (`/16` > `/24` > `/27`).

### Clúster (AKS)
Un conjunto de máquinas virtuales (nodos) que trabajan juntas para ejecutar tus contenedores. AKS gestiona el clúster automáticamente: si un nodo falla, el tráfico se redirige a otros nodos.

### Commit
Una "fotografía" del estado de tu código en un momento específico. Cada commit tiene un mensaje que describe el cambio. Git guarda todos los commits y puedes volver a cualquiera de ellos.

### Contenedor
Un paquete que incluye tu aplicación y todo lo que necesita para ejecutarse (dependencias, configuración, sistema operativo mínimo). Es más ligero que una máquina virtual porque comparte el kernel del sistema operativo del host.

---

## D

### Data Source (Terraform)
Una consulta de **solo lectura** a Azure. En lugar de crear un recurso, le pregunta a Azure "dame información sobre este recurso que ya existe". En este proyecto se usa para leer el Resource Group `rg-platform` que creó el bootstrap — sin intentar recrearlo.

### Defender for Cloud
El servicio de seguridad de Azure que analiza tu infraestructura y te da recomendaciones. Detecta configuraciones inseguras, accesos sospechosos y vulnerabilidades. Se habilita por plan: uno para servidores, otro para contenedores, otro para Key Vault.

### Diagnostic Settings
La configuración que le dice a cada recurso de Azure: "envía tus logs a este workspace de Log Analytics". Sin esto, Log Analytics existe pero está vacío — los recursos no envían nada por defecto.

### DNS
Sistema que traduce nombres legibles (como `mi-app.azurecr.io`) a direcciones IP numéricas (como `10.1.5.4`). Es como el directorio telefónico de internet.

### DNS Privado / Private DNS Zone
Un DNS que solo funciona dentro de tu red privada de Azure. Cuando un recurso busca `mi-acr.azurecr.io`, en lugar de obtener la IP pública de internet, obtiene la IP interna del Private Endpoint. El tráfico nunca sale a internet.

### DNS Zone Link
La conexión entre una Private DNS Zone y una VNet. Le dice a Azure: "cuando recursos de esta VNet busquen nombres de esta zona, usa los registros privados".

---

## E

### Entra ID
El sistema de identidades de Microsoft (antes llamado Azure Active Directory / Azure AD). Gestiona usuarios, grupos, aplicaciones y Service Principals. Es el "guardián" que decide quién puede acceder a qué.

---

## F

### Federation Credential / OIDC
Un mecanismo para que GitHub Actions se autentique ante Azure **sin contraseñas**. En lugar de guardar un secreto en GitHub, se establece una relación de confianza: Azure le dice "confío en tokens que vengan de GitHub para este repositorio específico". Cada vez que el pipeline corre, GitHub genera un token temporal que Azure verifica directamente.

### fmt — `terraform fmt`
El comando que formatea automáticamente el código Terraform para que tenga la indentación y espaciado correcto. Es como el corrector de estilo automático de un editor de código.

---

## G

### GitHub Actions
El sistema de automatización de GitHub. Permite definir "workflows" (flujos de trabajo) que se ejecutan automáticamente cuando pasan cosas en el repositorio (un push, un PR, un merge). En este proyecto hay 3 workflows: uno que valida Terraform en PRs, uno que aplica Terraform al mergear, y uno que construye y despliega la app.

### Git
Sistema que lleva el historial completo de todos los cambios en el código. Permite trabajar en equipo sin pisarse, volver a versiones anteriores y ver quién cambió qué y cuándo.

---

## H

### HCL — HashiCorp Configuration Language
El lenguaje en que se escriben los archivos `.tf` de Terraform. Es más legible que JSON y menos estricto que YAML. Está diseñado específicamente para describir infraestructura.

### Hub-Spoke
Un patrón de red donde existe una red central ("hub") conectada a redes satélite ("spokes"). El hub aloja servicios compartidos (DNS privado, seguridad). Los spokes alojan las aplicaciones. La ventaja es que si el spoke de una app tiene un problema, no afecta al hub ni a otros spokes.

---

## I

### IaC — Infrastructure as Code
Describir la infraestructura (servidores, redes, bases de datos) en archivos de texto en lugar de crearla manualmente con clics. Las ventajas: el código se puede versionar en Git, reproducir exactamente, revisar en un PR y automatizar con pipelines.

### Idempotente
Un script o proceso que produce el mismo resultado sin importar cuántas veces se ejecute. Si el recurso ya existe, no falla ni lo duplica — simplemente lo detecta y continúa. El script `bootstrap.ps1` es idempotente.

---

## K

### Key Vault
La "caja fuerte" de Azure para secretos, contraseñas, certificados y claves de encriptación. En lugar de guardar una contraseña en el código o en una variable de entorno, la guardas en Key Vault y la aplicación la lee en tiempo de ejecución mediante su identidad (sin contraseñas).

### Key Vault — Control Plane vs Data Plane
En Key Vault hay dos capas de permisos:
- **Control plane**: crear/borrar/configurar el recurso (por ejemplo, rol `Owner` en suscripción).
- **Data plane**: leer/escribir **secretos, claves y certificados** dentro del vault (por ejemplo, `Key Vault Administrator`, `Key Vault Secrets Officer`, etc.).

Ser `Owner` de suscripción no siempre implica acceso total al contenido del vault cuando está usando RBAC de data plane.

### KQL — Kusto Query Language
El lenguaje para consultar los logs en Log Analytics. Similar a SQL pero optimizado para datos de series de tiempo y logs. Ejemplo: "dame todos los pods de AKS que fallaron en las últimas 24 horas".

### kubectl
La herramienta de línea de comandos para interactuar con Kubernetes. Con ella puedes ver pods (`kubectl get pods`), ver logs (`kubectl logs`), desplegar aplicaciones (`kubectl apply`) y diagnosticar problemas.

---

## L

### Landing Zone
La infraestructura base que una empresa prepara antes de desplegar sus aplicaciones. Incluye: redes, seguridad, permisos, monitoreo y automatización. Es como preparar el terreno y los cimientos antes de construir una casa.

### Lease (State Lock)
Un "candado" que Terraform coloca en el archivo de estado mientras está corriendo. Si dos personas intentan hacer `terraform apply` al mismo tiempo, la segunda espera a que la primera termine. Esto evita que el estado se corrompa. Se implementa como un "lease" (arrendamiento temporal) en el blob de Azure Storage.

### Locals (Terraform)
Valores calculados internamente en Terraform, a partir de otras variables. No se pueden pasar desde afuera. Sirven para evitar repetir la misma expresión en muchos lugares. Ejemplo: `name_suffix = "-lz-dev"` se calcula una vez y se usa en todos los nombres de recursos.

### Log Analytics Workspace
El repositorio central de logs en Azure. Todos los recursos (AKS, Key Vault, NSGs) envían sus logs aquí. Desde aquí puedes consultarlos con KQL, crear alertas y hacer dashboards.

---

## M

### main (rama Git)
La rama principal del repositorio. Es la versión "oficial" y estable del código. En este proyecto está protegida: nadie puede subir directamente a ella, todo debe pasar por un Pull Request.

### main.tf
Por convención, el archivo principal de Terraform donde se declaran los recursos o se llaman los módulos. No es un nombre reservado — Terraform lee todos los archivos `.tf` de la carpeta.

### Managed Identity
Una identidad de Azure que se asigna directamente a un recurso (como AKS) en lugar de a una persona. Permite que el recurso acceda a otros servicios (como ACR o Key Vault) sin contraseñas. Azure gestiona automáticamente las credenciales de esta identidad.

### Management Group
Un contenedor en Azure que agrupa múltiples suscripciones para aplicar políticas y permisos de forma centralizada. En empresas grandes, los Management Groups definen la jerarquía corporativa. En este proyecto **no tenemos acceso** a Management Groups, así que usamos Resource Groups como sustituto.

### Módulo (Terraform)
Una carpeta con archivos `.tf` que agrupa recursos relacionados y los expone con una interfaz simple (variables de entrada y outputs). Es como una función en programación: la llamas con parámetros y hace su trabajo sin que tengas que ver cómo funciona por dentro.

### Monorepo
Un único repositorio de Git que contiene todo el proyecto: infraestructura, aplicación, pipelines y documentación. La alternativa sería tener un repo para cada parte, lo que complica la coordinación.

---

## N

### Node Pool
Un grupo de máquinas virtuales dentro de AKS con el mismo tamaño y configuración. AKS recomienda tener al menos dos node pools: uno "de sistema" (para los componentes internos de Kubernetes) y uno "de usuario" (para tu aplicación). Esto evita que tu app compita por recursos con el sistema.

### NSG — Network Security Group
Un firewall a nivel de subnet. Define reglas de "permitir" o "denegar" tráfico basado en origen, destino, protocolo y puerto. En este proyecto el NSG del spoke bloquea tráfico de internet directo a los nodos de AKS.

---

## O

### Output (Terraform)
Un valor que un módulo "expone" para que otros módulos o el usuario puedan usarlo. Ejemplo: el módulo `network` expone el ID de la subnet de AKS para que el módulo `aks` sepa dónde crear el clúster.

### OIDC — OpenID Connect
Un protocolo de autenticación basado en tokens. En este proyecto permite que GitHub Actions se autentique ante Azure sin contraseñas: GitHub emite un token firmado, Azure lo verifica. Los tokens son temporales (expiran en minutos).

---

## P

### Peering (VNet Peering)
Una conexión directa entre dos VNets de Azure que les permite comunicarse como si fueran la misma red. En este proyecto conecta el hub con el spoke. Debe ser bidireccional: se crea una conexión en cada dirección.

### Pipeline
Un flujo de trabajo automatizado que se ejecuta cuando pasa algo en el repositorio (un commit, un PR, un merge). Los pipelines de este proyecto corren en GitHub Actions y hacen cosas como validar Terraform, aplicar cambios en Azure y desplegar la aplicación.

### Plan — `terraform plan`
El comando que calcula qué cambios haría Terraform **sin hacerlos**. Muestra exactamente qué recursos se crearán (`+`), modificarán (`~`) o destruirán (`-`). Es el "ensayo general" antes del `apply`.

### Private Endpoint
Un recurso de Azure que da a un servicio (como ACR o Key Vault) una dirección IP privada dentro de tu VNet. Sin Private Endpoint, el servicio solo tiene una IP pública accesible desde internet. Con Private Endpoint, el tráfico nunca sale de tu red privada.

### Provider (Terraform)
Un plugin que le enseña a Terraform a hablar con un servicio específico. `azurerm` es el provider de Azure Resource Manager, `azuread` es para Azure Active Directory/Entra ID. Sin providers, Terraform no sabe cómo crear recursos en Azure.

### Pull Request (PR)
Una solicitud para mezclar ("mergear") el código de una rama con la rama `main`. Antes de aprobarlo, se puede revisar el código, ver el resultado del pipeline automático y dejar comentarios. En este proyecto todos los cambios a `main` pasan por un PR.

---

## R

### RBAC — Role-Based Access Control
Sistema de permisos de Azure. En lugar de dar acceso total a alguien, le asignas un **rol** específico (como "Contributor", "Reader", "Storage Blob Data Contributor") sobre un **scope** específico (suscripción, resource group, o un recurso concreto). Principio de mínimo privilegio: solo los permisos estrictamente necesarios.

En Key Vault con red privada también aplica una segunda condición: aunque tengas RBAC correcto, si `publicNetworkAccess = Disabled` solo podrás operar desde una red permitida (Private Endpoint/VNet/VPN/jumpbox) o abriendo acceso público temporalmente para pruebas.

### README
El archivo `README.md` en la raíz del repositorio. Es la "portada" del proyecto: explica qué es, cómo funciona y cómo usarlo. GitHub lo muestra automáticamente al entrar al repositorio.

### Resource Group (RG)
Un contenedor lógico en Azure que agrupa recursos relacionados. Puedes pensar en él como una carpeta. Borrar el Resource Group borra todo lo que contiene. Los costos se pueden ver por Resource Group.

---

## S

### Service Principal
Una identidad de aplicación en Azure Entra ID (como un "usuario robot"). En este proyecto, el Service Principal `sp-landing-zone-cicd` es la identidad que usan los pipelines de GitHub Actions para autenticarse ante Azure. Tiene solo los permisos mínimos necesarios.

### SKU
El "modelo" o "nivel" de un servicio de Azure. Cada SKU tiene diferentes capacidades y costos. Ejemplo: ACR tiene SKU Basic (~$0.17/día), Standard y Premium (~$1.67/día). AKS tiene SKU Free (para el control plane) y Standard.

### State / tfstate
El archivo donde Terraform guarda el mapa de todos los recursos que gestionó y sus configuraciones actuales. Es la "memoria" de Terraform. Sin él, Terraform no sabe qué ya existe en Azure.

### State Lock
Ver **Lease**.

### Subnet
Una subdivisión de una VNet. Permite separar recursos por función y aplicar reglas de seguridad diferentes a cada grupo. Ejemplo: una subnet para AKS, otra para Private Endpoints.

---

## T

### Tags (Etiquetas)
Pares clave-valor que se asignan a los recursos de Azure para organizarlos. Ejemplo: `Environment=dev`, `Project=landing-zone`. Las policies pueden exigir que todos los recursos tengan ciertos tags.

### Terraform
La herramienta de Infrastructure as Code que usamos en este proyecto. Lees archivos `.tf` que describen el estado deseado de la infraestructura y Terraform calcula y aplica los cambios necesarios para llegar a ese estado.

### tfplan
El archivo binario que guarda el resultado de `terraform plan`. Usarlo en `terraform apply "tfplan"` garantiza que se aplica exactamente lo que se revisó, sin recalcular.

### Tenant
El "inquilino" de Azure — el directorio de Entra ID de una organización. Una empresa puede tener múltiples suscripciones dentro de un mismo tenant. En este proyecto el tenant es personal (`a239f11b-...`).

---

## V

### validate — `terraform validate`
El comando que verifica que la sintaxis del código HCL es correcta. No se conecta a Azure — solo analiza el texto de los archivos `.tf`. Es más rápido que el `plan`.

### Variable (Terraform)
Un parámetro de entrada que hace el código reutilizable. En lugar de escribir `"eastus2"` en cada recurso, defines una variable `location` con ese valor por defecto y todos los recursos la usan.

### VNet — Virtual Network
La red privada de Azure. Es el espacio IP donde viven todos los recursos del proyecto. Similar a una LAN corporativa, pero en la nube. Los recursos dentro de una VNet se comunican entre sí directamente; los de fuera necesitan reglas explícitas de acceso.

---

## W

### Workflow (GitHub Actions)
Un archivo YAML en `.github/workflows/` que define qué hacer y cuándo. Ejemplo: "cuando alguien abre un Pull Request que toca archivos en `infra/terraform/`, ejecuta `terraform plan` y publica el resultado como comentario en el PR".

### Workload Identity
Un mecanismo que permite que los pods de Kubernetes (tu aplicación) accedan a servicios de Azure (como Key Vault) usando una Managed Identity, sin contraseñas. El pod tiene una identidad de Azure y puede obtener tokens para autenticarse.

---

## Z

### Zone Link
Ver **DNS Zone Link**.
