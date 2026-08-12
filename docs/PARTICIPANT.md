# Tarjeta para participantes

Sustituya `N` por el número de su equipo.

1. Conéctese al Wi-Fi del taller en el recinto. Si la placa aún no está
   configurada, conéctese a `equipoN-setup`; la pantalla de configuración debe
   abrirse automáticamente en iPhone/iPad, macOS, Windows y Android. En Windows,
   pulse primero la notificación **Action needed** si aparece. Si el sistema no
   muestra nada, abra `http://10.42.N.1:8080/` y elija la red Wi-Fi del recinto.
2. Una persona del equipo abre `http://equipoN.local:6080/control.html`.
3. Las demás abren `http://equipoN.local:6080/view.html`.
4. Envíe un mensaje que mencione al bot de Telegram de su equipo. El bot solo
   funciona para las cinco personas autorizadas por el instructor.

El escritorio noVNC tiene una sola barra inferior. Sus botones `APPS`,
`Terminal`, `Code`, `Get code`, `Agent` y `Monitor` permanecen visibles aunque
cierre una aplicación. Cada ventana abierta aparece también en esa barra:
haga clic en su botón para ocultarla o restaurarla. Si la cierra con X, pulse
otra vez su lanzador. `WORK`, `AGENT` y `RUN` cambian entre los tres escritorios.

Pulse `Get code` para descargar o actualizar automáticamente `cdmx-bayesopt` y
`cdmx-local-ai`. También puede descargarlos por separado desde `APPS` o desde
una terminal:

```bash
cdmx-get-bayesopt
cdmx-get-local-ai
cdmx-get-workshop-repos
```

No necesita una cuenta de GitHub. El lanzador nunca sobrescribe una carpeta
que no sea un repositorio Git.

Otros medios de acceso:

```text
SSH:    ssh cdmx@equipoN.local
```

El directorio de código compartido es `~/workspace`. El enlace conserva el
almacenamiento protegido de PicoClaw sin mostrar su ruta interna. Guarde ahí
todo el trabajo del agente. No pegue claves de API ni tokens de bots
en el chat, en archivos de código fuente ni en la terminal.

La cuenta `cdmx` puede ejecutar `sudo` sin contraseña para instalar dependencias
y configurar GPIO/I²C/SPI durante el ejercicio. Utilícelo únicamente para el
trabajo del taller.

Antes de desconectar la placa, use `sudo poweroff` y espere a que termine la
actividad. Si se corta la energía inesperadamente, la placa debería
recuperarse en el siguiente arranque, pero una interrupción durante una
escritura aún puede dañar la tarjeta SD.
