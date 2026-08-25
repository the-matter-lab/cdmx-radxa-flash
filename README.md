# Imagen y flasheo de las Radxa del taller CDMX

🇲🇽 [![Español](https://img.shields.io/badge/lang-Español-yellow.svg)](README.md) ·
🇬🇧 [![English](https://img.shields.io/badge/lang-English-blue.svg)](README.en.md)

Este es el repositorio de infraestructura del taller. Construye la imagen
RadxaOS reproducible para las ZERO 3W, admite `equipo0`–`equipo98` y `admin`, y
contiene el portal de Wi‑Fi, el escritorio Openbox/noVNC y los ayudantes de
flasheo para macOS y Windows.

Los participantes trabajan en dos repositorios separados:

- [`the-matter-lab/cdmx-local-ai`](https://github.com/the-matter-lab/cdmx-local-ai): agente Pi/PicoClaw y canales Telegram/Discord.
- [`the-matter-lab/cdmx-bayesopt`](https://github.com/the-matter-lab/cdmx-bayesopt): laboratorio de optimización bayesiana.

## Flashear una tarjeta

Abra **[cdmx-radxaflash.mantilla.ca](https://cdmx-radxaflash.mantilla.ca)**:

1. Inserte una tarjeta SD de al menos 8 GB.
2. Elija macOS, Windows o Linux en la web y copie el comando. Péguelo en
   Terminal o en PowerShell como administrador.
3. Seleccione la unidad extraíble y `equipo0`–`equipo11` o `admin`.
4. Confirme el borrado y espere a que la escritura **y la lectura de
   verificación** lleguen a 100%.

La web muestra actualmente doce equipos (`equipo0`–`equipo11`). La imagen y el
ayudante ya aceptan identidades numéricas hasta `equipo98`; `admin` reserva el
índice de red `99`. Para añadir equipos más adelante, solo cambie `TEAM_COUNT`
en `site/index.html`, sin reconstruir la imagen SD.

La web pública nunca puede acceder directamente a un disco de la laptop. El
ayudante privilegiado escucha solo en `127.0.0.1`, muestra únicamente unidades
extraíbles de lectores SD integrados, adaptadores USB-A/USB-C y buses SD/MMC,
vuelve a comprobar el destino antes de borrarlo y descarga la
versión indicada en [`site/manifest.json`](site/manifest.json). La imagen y su
SHA‑512 se guardan en caché para las tarjetas siguientes.

Solo existe una interfaz de usuario: la web pública. `127.0.0.1:8766` es el
puente local privado y su raíz redirige a la web pública; no presenta una
segunda pantalla de flasheo.

Use Chrome, Chromium o Edge y acepte **acceso a dispositivos locales** cuando
el navegador lo solicite. Safari bloquea la comunicación HTTPS→loopback HTTP;
por eso el lanzador de macOS abre Chrome automáticamente.

Los tres comandos descargan un snapshot de código fuente fijado por commit,
comprueban su SHA‑256 y lo ejecutan con Python local. En macOS esto evita el
bloqueo de Gatekeeper para aplicaciones sin firma. La contraseña solo autoriza
acceso al disco extraíble: no se guarda ni se escribe en la Radxa.

### Ejecutar desde el código fuente

```bash
# macOS
/bin/bash -c "$(curl -fsSL https://cdmx-radxaflash.mantilla.ca/start-macos.sh)"

# Linux
/bin/bash -c "$(curl -fsSL https://cdmx-radxaflash.mantilla.ca/start-linux.sh)"
```

En Windows, abra PowerShell como administrador y copie el comando que muestra
la web. Los enlaces “Ver script” permiten inspeccionar los tres lanzadores.

Para quitar el lector, elija el sistema operativo y presione **Desinstalar** en
la misma web. Copie el comando mostrado: detiene únicamente el ayudante CDMX y
elimina su código, entorno Python e imagen en caché. No modifica tarjetas SD.

El lanzador crea un entorno Python local, instala el escritor FAT fijado y pide
una sola autorización de administrador. También se puede usar la línea de
comandos existente con `host/flash-team.sh`.

## Qué contiene la imagen

- RadxaOS Debian 12 Bookworm arm64 para ZERO 3, versión fijada `rsdk-b1`.
- Escritorio Openbox ligero de 1280×720 con panel inferior persistente, reloj
  de Ciudad de México, dos espacios `AGENTS`/`BAYES`, terminal, Geany, monitor
  y fondo de Matter Lab.
- noVNC compartido: control en `control.html` y observación en `view.html`.
  El panel Clipboard acepta hasta 1 MiB desde la laptop y sincroniza las
  selecciones X11 CLIPBOARD/PRIMARY; pegue con `Ctrl+V` en Geany o
  `Ctrl+Shift+V`/`Shift+Insert` en la terminal.
- Portal cautivo para introducir el Wi‑Fi del recinto sin teclado.
- SSH mediante clave pública, `sudo` local sin contraseña y servicios systemd
  que vuelven a iniciar después de un ciclo normal de energía.
- Dependencias Python, I²C por GPIO en los pines físicos 8/10 y SPI3-M1 para el
  laboratorio de color. El overlay propio desactiva FIQ/UART2 en esos pines.
- La configuración GPIO permanece activa desde el arranque; Color Lab se abre
  manualmente con `scripts/color-lab.sh` y `Ctrl-C` detiene sitio y muestreo.
- Los ejecutables PicoClaw y Pi se instalan mediante una versión fijada del
  instalador de `cdmx-local-ai` en
  [`image/cdmx-local-ai.env`](image/cdmx-local-ai.env). El repositorio, sus
  skills, sus tools y `AGENT.md` no se incluyen en la imagen.
- Exactamente tres archivos visibles en un `~/workspace` nuevo o reiniciado:
  `README.md`, `get-localai-code` y `get-bayesopt-code`. Los dos scripts clonan
  o actualizan solamente el repositorio elegido; BayesOpt también prepara su
  entorno Python sin pedir `sudo`.
- Reset pide confirmación, elimina ambos clones y la configuración local del
  agente, y restaura esos mismos tres archivos para el siguiente equipo.
- Ruta sencilla `~/workspace`, botones para reabrir aplicaciones y límites de
  memoria distintos para los equipos de 1 GB y la placa admin de 2 GB.

Samba no forma parte de las tarjetas del taller. La imagen elimina KDE,
navegadores locales y paquetes Samba para reducir almacenamiento y RAM en las
placas de 1 GB.

Cableado fijado en la imagen: TCS34725 `VCC→4`, `GND→6`, `SCL→8`, `SDA→10`;
NeoPixel `DIN→19`, `GND→20` y alimentación de 5 V separada desde el pin 2.

## Red y acceso el día del taller

Sin una red guardada, cada placa publica `equipoN-setup` (o `admin-setup`). El
portal debe aparecer automáticamente en iPhone/iPad, macOS, Windows y Android;
si el sistema no lo abre, use:

```text
equipoN: http://10.42.N.1:8080/
admin:   http://10.42.99.1:8080/
```

Después de guardar el Wi‑Fi, vuelva a conectar la laptop o el teléfono a esa
misma LAN:

Si la red guardada deja de estar disponible, la placa intenta reconectarse y,
tras aproximadamente 60–75 segundos sin conexión, vuelve a publicar
`equipoN-setup` (o `admin-setup`). Conéctese otra vez a esa red para introducir
un SSID y una contraseña nuevos; no hace falta volver a grabar la tarjeta.

| Propósito | Dirección |
|---|---|
| Control noVNC | `http://equipoN.local:6080/control.html` |
| noVNC de solo lectura | `http://equipoN.local:6080/view.html` |
| SSH | `ssh cdmx@equipoN.local` |
| Reiniciar incorporación | `sudo cdmx-network reset` |

La ZERO 3W tiene un solo radio. El punto de acceso `-setup` sirve para
incorporación y recuperación, no para mantener simultáneamente una segunda red.
Para 50 participantes se recomienda un router dedicado sin aislamiento entre
clientes.

## Construir una imagen nueva

En una Mac con Docker Desktop y una clave pública SSH:

```bash
./host/download-stock-image.sh
./host/build-workshop-image.sh
make test
```

La construcción usa un snapshot del commit actual, descarga el agente desde el
commit fijado, modifica una copia de la imagen oficial en un contenedor ARM64,
limpia identificadores y claves de host y produce:

```text
image/cdmx-workshop-golden.img.xz
image/cdmx-workshop-golden.img.xz.sha512
```

Antes de publicar, actualice `version`, tamaños, SHA‑512, `docker` y los commits
inmutables de `simulator` en `site/manifest.json`. El mismo archivo alimenta la
web pública, ambos ayudantes y
[el simulador del taller](https://radxa-simulator.mantilla.ca), de modo que
todos usan exactamente la misma versión. Lepton consulta el manifiesto cada
cinco minutos y actualiza el simulador cuando cambia ese fingerprint.

## Docker y publicación

La imagen también se divide en capas y se publica en
[`bestquark/cdmx-radxa-zero3w`](https://hub.docker.com/r/bestquark/cdmx-radxa-zero3w):

```bash
./docker/prepare-image-parts.sh
docker buildx build --platform linux/amd64,linux/arm64 \
  --build-arg IMAGE_VERSION=VERSION \
  -f docker/Dockerfile.sd-image image \
  -t bestquark/cdmx-radxa-zero3w:VERSION \
  -t bestquark/cdmx-radxa-zero3w:latest --push
```

`host/pull-workshop-image.sh` reconstruye la imagen desde Docker y verifica la
suma. Los artefactos de varios gigabytes se excluyen de Git; solo el código,
metadatos y sumas se versionan.

Un tag `v*` construye automáticamente los ayudantes macOS y Windows y crea un
GitHub Release. El contenido de `site/` y la imagen verificada se sirven desde
Lepton mediante Caddy y Cloudflare Tunnel. La configuración reproducible del
sitio está en [`deploy/`](deploy/README.md).

El lector SD integrado de la Mac y los lectores microSD conectados por USB-A o
USB-C son compatibles; también se aceptan adaptadores que declaran la tarjeta
como medio fijo. Los discos de arranque y del sistema siguen excluidos.

La web pública habla únicamente con el ayudante privilegiado en
`127.0.0.1:8766`: muestra los discos extraíbles, las identidades y el progreso,
pero la lectura y escritura física siempre ocurre en la laptop. El puente CORS
acepta solo el origen público de Matter Lab y conserva el token de confirmación
para cada proceso del ayudante.

## Seguridad y confiabilidad

- La selección de disco rechaza el disco del sistema, particiones individuales,
  unidades internas fijas, unidades menores de 4 GB y destinos que dejan de ser
  extraíbles antes de escribir.
- Cada tarjeta se verifica leyendo los bytes escritos y comparándolos con el
  flujo descomprimido. La identidad se escribe después en la partición FAT y se
  vuelve a leer.
- Las claves SSH de host y el identificador de máquina se regeneran después de
  clonar. Los registros son volátiles y limitados; ext4 con journal, zram y
  servicios reiniciables reducen desgaste y recuperan el funcionamiento tras
  encender de nuevo.
- Una pérdida de energía durante una escritura puede dañar cualquier SD. Use
  `sudo poweroff` cuando sea posible y mantenga tarjetas de repuesto verificadas.
- noVNC y el punto de acceso de configuración son deliberadamente abiertos en
  la LAN del taller; nunca deben publicarse directamente en Internet.

Detalles de operación: [`host/WORKFLOW.md`](host/WORKFLOW.md). Lista para el
instructor: [`docs/INSTRUCTOR-CHECKLIST.md`](docs/INSTRUCTOR-CHECKLIST.md).
