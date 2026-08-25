MATTER LAB INTERNATIONAL CONFERENCE 2026 - SATELLITE SCHOOL

INICIO RAPIDO

La barra inferior tiene APPS, Terminal, Code, Agent y Monitor. AGENTS y BAYES
son los dos escritorios. El codigo del equipo vive en ~/workspace. Reset, a la
derecha del reloj, pide confirmacion y borra solo ~/workspace/cdmx-bayesopt.

LABORATORIO DE COLOR (manual)

  ./get-bayesopt-code
  cd cdmx-bayesopt
  ./scripts/color-lab.sh

Abra http://equipoN.local:8010/. Ctrl-C detiene el sitio y el muestreo.

BAYESOPT

Primero detenga Color Lab. Luego:

  ./scripts/bayesopt.sh '#4A80C0'

Abra http://equipoN.local:8000/. Ctrl-C detiene la campana. BayesOpt usa el
sensor y el LED directamente; no deja Color Lab abierto.

Los GPIO permanecen configurados durante todo el taller:
TCS34725: VCC=4, GND=6, SCL=8, SDA=10.
NeoPixel: VCC=2, DIN=19, GND=20.

QUICK START

The bottom panel has APPS, Terminal, Code, Agent, and Monitor. AGENTS and BAYES
are the two desktops. Team code lives in ~/workspace. Reset, to the right of
the clock, asks for confirmation and removes only ~/workspace/cdmx-bayesopt.

COLOR LAB (manual)

  ./get-bayesopt-code
  cd cdmx-bayesopt
  ./scripts/color-lab.sh

Open http://equipoN.local:8010/. Ctrl-C stops both the site and sampling.

BAYESOPT

Stop Color Lab first, then run:

  ./scripts/bayesopt.sh '#4A80C0'

Open http://equipoN.local:8000/. Ctrl-C stops the campaign. BayesOpt uses the
sensor and LED directly; it does not leave Color Lab running.

GPIO stays configured throughout the workshop:
TCS34725: VCC=4, GND=6, SCL=8, SDA=10.
NeoPixel: VCC=2, DIN=19, GND=20.
