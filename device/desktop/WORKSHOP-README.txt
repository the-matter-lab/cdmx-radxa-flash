MATTER LAB INTERNATIONAL CONFERENCE 2026 - SATELLITE SCHOOL

INICIO RAPIDO

La barra inferior siempre permanece disponible:

  APPS       aplicaciones y ventanas abiertas
  Terminal   terminal nueva dentro de ~/workspace
  Code       editor grafico
  Agent      abre Pi Agent
  Monitor    CPU, memoria y procesos

AGENTS y BAYES son los dos escritorios. Cada ventana abierta aparece como un
boton en la barra inferior; haga clic para ocultarla o restaurarla.

El codigo del equipo vive en ~/workspace. Para descargarlo desde Terminal:

  ./get-bayesopt-code
  ./get-localai-code

No necesita una cuenta de GitHub. El script actualiza un clon existente sin
sobrescribir otros archivos.

FLUJO BAYESOPT

  ./get-bayesopt-code
  cd cdmx-bayesopt
  ./scripts/install-color-lab.sh

Abra http://equipoN.local:8010/ para controlar el LED y ver el sensor. Luego
edite examples/hardware_objective.py y ejecute:

  ./scripts/run-color-campaign.sh

Abra http://equipoN.local:8000/ para seguir la campana.

CABLEADO

TCS34725: VCC=pin 4, GND=pin 6, SCL=pin 8, SDA=pin 10.
NeoPixel: DIN=pin 19, GND=pin 20, 5V separado=pin 2.

QUICK START

The persistent bottom panel contains APPS, Terminal, Code, Agent, and Monitor.
AGENTS and BAYES are the two desktops. Open windows also appear in the panel;
click their buttons to hide or restore them.

Team code lives in ~/workspace. Download it from Terminal without a GitHub
account:

  ./get-bayesopt-code
  ./get-localai-code

BAYESOPT FLOW

  ./get-bayesopt-code
  cd cdmx-bayesopt
  ./scripts/install-color-lab.sh

Open http://equipoN.local:8010/ for LED control and sensor readings. Edit
examples/hardware_objective.py, run ./scripts/run-color-campaign.sh, and open
http://equipoN.local:8000/ to follow the campaign.

WIRING

TCS34725: VCC=pin 4, GND=pin 6, SCL=pin 8, SDA=pin 10.
NeoPixel: DIN=pin 19, GND=pin 20, separate 5V=pin 2.
