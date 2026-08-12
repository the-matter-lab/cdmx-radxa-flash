# Flujo de trabajo para las tarjetas del taller

## Flujo recomendado: macOS o Windows

1. Abra `https://cdmx-radxaflash.mantilla.ca`.
2. Elija macOS, Windows o Linux y copie la línea para Terminal o PowerShell.
3. Inserte una SD de al menos 8.08 GB.
4. Abra el ayudante con privilegios de administrador.
5. Seleccione el disco extraíble y `equipo0`–`equipo9` o `admin`.
6. Confirme el borrado exacto y espere a 100% antes de retirar la tarjeta.

El ayudante obtiene `manifest.json` desde el sitio central. Descarga la imagen
solo cuando no está en caché, comprueba el SHA‑512, escribe el flujo XZ, vuelve a
leer los 8,074,662,912 bytes y escribe `cdmx-team.env` directamente en la
partición FAT de configuración. Esa última operación funciona también en
Windows aunque el sistema no asigne una letra a la partición de Radxa.

La única interfaz está en `https://cdmx-radxaflash.mantilla.ca`. El servicio en
`127.0.0.1:8766` es solo el puente privado hacia el disco, no acepta conexiones
desde la LAN y redirige su raíz a la web pública.

La acción **Desinstalar** de la web muestra un comando por sistema operativo.
Elimina el código descargado, `.venv-imager` y la imagen en caché, y detiene
solo el proceso `imager_app.py` instalado por este lector. No toca las SD.

## Desde el código fuente en macOS

Abra `host/start-imager.command`. La primera ejecución crea `.venv-imager` e
instala las dependencias fijadas; macOS pide una autorización para abrir el
disco extraíble. Mientras la terminal siga abierta no vuelve a pedirla entre
tarjetas.

## Construcción manual de la imagen

Ejecute desde la raíz del repositorio:

```bash
./host/download-stock-image.sh
./host/build-workshop-image.sh
```

La construcción no contiene credenciales de Wi‑Fi, API ni bots. Incluye la
clave pública SSH del instructor encontrada en `~/.ssh` y el agente del commit
de `image/cdmx-local-ai.env`.

El flujo CLI alternativo en macOS/Linux es:

```bash
./host/flash-team.sh --team 0 --disk /dev/DISK
```

## Publicar una versión

1. Ejecute `make test` y construya la nueva imagen.
2. Calcule su SHA‑512 y tamaños comprimido/descomprimido.
3. Actualice `site/manifest.json` con una versión nueva.
4. Publique la imagen Docker con esa misma versión.
5. Copie `site/`, la imagen y el sidecar a Lepton.
6. Cree y empuje un tag `v*` cuando necesite publicar ayudantes empaquetados;
   GitHub Actions construirá las versiones macOS y Windows. El flujo recomendado
   usa los lanzadores auditables de `site/` para evitar depender de una app sin
   firma.

Use el mismo modelo y capacidad de tarjeta cuando sea posible. Nunca arranque
dos tarjetas con la misma identidad en la misma red.
