# Imagen y flasheo de las Radxa del taller CDMX

🇲🇽 [![Español](https://img.shields.io/badge/lang-Español-yellow.svg)](README.md) ·
🇬🇧 [![English](https://img.shields.io/badge/lang-English-blue.svg)](README.en.md)

Este es el repositorio de infraestructura del taller. Construye la imagen
RadxaOS reproducible para las ZERO 3W, prepara `equipo0`–`equipo9` y `admin`, y
contiene el portal de Wi‑Fi, el escritorio Openbox/noVNC y los ayudantes de
flasheo para macOS y Windows.

Los participantes trabajan en dos repositorios separados:

- [`the-matter-lab/cdmx-local-ai`](https://github.com/the-matter-lab/cdmx-local-ai): agente Pi/PicoClaw y canales Telegram/Discord.
- [`the-matter-lab/cdmx-bayesopt`](https://github.com/the-matter-lab/cdmx-bayesopt): laboratorio de optimización bayesiana.

## Flashear una tarjeta

Abra **[cdmx-radxaflash.mantilla.ca](https://cdmx-radxaflash.mantilla.ca)** y
descargue el ayudante para su sistema:

1. Inserte una tarjeta SD de al menos 8 GB.
2. En macOS, abra `Start-CDMX-Radxa-Flasher.command` dentro del ZIP. En Windows,
   ejecute `CDMX-Radxa-Flasher.exe` como administrador.
3. Seleccione la unidad extraíble y `equipo0`–`equipo9` o `admin`.
4. Confirme el borrado y espere a que la escritura **y la lectura de
   verificación** lleguen a 100%.

La web pública nunca puede acceder directamente a un disco de la laptop. El
ayudante privilegiado escucha solo en `127.0.0.1`, muestra únicamente unidades
USB/SD extraíbles, vuelve a comprobar el destino antes de borrarlo y descarga la
versión indicada en [`site/manifest.json`](site/manifest.json). La imagen y su
SHA‑512 se guardan en caché para las tarjetas siguientes.

Los binarios todavía no tienen firma comercial, por lo que Gatekeeper o
SmartScreen puede pedir una confirmación adicional. El código de los binarios
se construye públicamente en GitHub Actions desde este repositorio.

### Ejecutar desde el código fuente en macOS

```bash
git clone https://github.com/the-matter-lab/cdmx-radxa-flash.git
cd cdmx-radxa-flash
open host/start-imager.command
```

El lanzador crea un entorno Python local, instala el escritor FAT fijado y pide
una sola autorización de administrador. También se puede usar la línea de
comandos existente con `host/flash-team.sh`.

## Qué contiene la imagen

- RadxaOS Debian 12 Bookworm arm64 para ZERO 3, versión fijada `rsdk-b1`.
- Escritorio Openbox ligero de 1280×720, tres espacios de trabajo, terminal,
  Geany, monitor de CPU/RAM/temperatura y fondo de Matter Lab.
- noVNC compartido: control en `control.html` y observación en `view.html`.
- Portal cautivo para introducir el Wi‑Fi del recinto sin teclado.
- SSH mediante clave pública, `sudo` local sin contraseña y servicios systemd
  que vuelven a iniciar después de un ciclo normal de energía.
- Dependencias Python y overlays I2C4-M0/SPI3-M1 para el laboratorio de color.
- Una versión exacta de `cdmx-local-ai`, fijada en
  [`image/cdmx-local-ai.env`](image/cdmx-local-ai.env); el código del agente no
  se duplica aquí.
- Un lanzador que clona o actualiza `cdmx-local-ai` y `cdmx-bayesopt` cuando el
  participante lo elige. Los repositorios de ejercicios no se clonan de
  antemano.

Samba no forma parte de las tarjetas del taller. La imagen elimina KDE,
navegadores locales y paquetes Samba para reducir almacenamiento y RAM en las
placas de 1 GB.

## Red y acceso el día del taller

Sin una red guardada, cada placa publica `equipoN-setup` (o `admin-setup`). El
portal debe aparecer automáticamente en iPhone/iPad, macOS, Windows y Android;
si el sistema no lo abre, use:

```text
equipoN: http://10.42.N.1:8080/
admin:   http://10.42.10.1:8080/
```

Después de guardar el Wi‑Fi, vuelva a conectar la laptop o el teléfono a esa
misma LAN:

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

Antes de publicar, actualice `version`, tamaños, SHA‑512 y `docker` en
`site/manifest.json`. El mismo archivo alimenta la web pública y ambos
ayudantes, de modo que todos graban exactamente la misma versión.

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
