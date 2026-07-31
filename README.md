# ClaudeWorkflowMonitor

Dashboard local para ver en vivo qué hacen los **workflows y subagentes de Claude
Code** en tu máquina: cuáles corren, cuáles terminaron y cuáles murieron, qué prompt recibió
cada uno y qué está haciendo ahora. Es **100% de solo lectura**: observa las corridas, no las
gestiona — no puede pausar, relanzar ni modificar nada.

> Local, read-only dashboard for watching Claude Code workflow/subagent runs.
> Cross-platform core (Python stdlib); launchers for Windows and Linux/macOS. Docs are in
> Spanish.

[![Licencia: MIT + Commons Clause](https://img.shields.io/badge/licencia-MIT%20%2B%20Commons%20Clause-blue)](LICENSE)
![Plataforma: Windows | Linux | macOS](https://img.shields.io/badge/plataforma-Windows%20%7C%20Linux%20%7C%20macOS-0078D6)
![Python 3.9+ o exe standalone](https://img.shields.io/badge/python-3.9%2B%20o%20exe%20standalone-3776AB)
[![PRs bienvenidos](https://img.shields.io/badge/PRs-bienvenidos-brightgreen)](CONTRIBUTING.md)

Cuando Claude Code orquesta trabajo — la tool Workflow (un script que lanza decenas de
subagentes), la tool Agent, skills en background — cada corrida deja su estado en archivos en
disco. Este monitor lee esos archivos y los convierte en un dashboard web: estado de cada
agente, su transcript, su prompt completo con buscador full-text, y el plan declarado de cada
workflow.

## Inicio rápido

Requisitos: **Python 3.9 o superior** en el PATH, en cualquier SO (en Windows podés evitar
Python con el [exe standalone](#exe-standalone-solo-windows--sin-python)). El core está
probado en Windows y en Linux (con Python 3.9 y 3.12); en macOS debería andar igual, pero
todavía no está probado — issues bienvenidos.

```text
git clone https://github.com/diegodelafuenteDim/ClaudeWorkflowMonitor.git
cd ClaudeWorkflowMonitor
monitor-app.cmd        # Windows
./monitor-app.sh       # Linux / macOS
```

El launcher levanta el server en el puerto 8787 y abre el dashboard: en Windows, en una
ventana dedicada de Chrome (`--app`, sin pestañas; sin Chrome, el navegador por defecto); en
Linux/macOS, en el navegador por defecto (`xdg-open`/`open`). El dashboard queda en
`http://localhost:8787`.

## Qué muestra

- **Todos los runs** de todas las conversaciones y proyectos, con filtros (proyecto, texto,
  solo activos, últimas 24 h) y auto-refresh cada 4 s.
- **El plan declarado** de cada workflow — nombre, descripción y fases del `export const meta`
  de su script — junto al progreso real de agentes. Van separados a propósito: en disco no
  queda registro de qué fase ejecuta cada agente.
- **Cada agente**: su estado, su feed de eventos (tools, mensajes, resultados) con modo
  "seguir el final" tipo `tail -f`, y su **prompt completo** (los hay de 400 KB) con metadata.
- **Familias de prompt**: los agentes de un fan-out agrupados por el molde que comparten, con
  la parte variable de cada uno a la vista.
- **Buscador full-text** sobre los prompts de todos los runs a la vez.
- **Agentes sueltos** (tool Agent / skills en background, fuera de workflows): el server los
  lista como pseudo-runs por sesión.

## Cómo funciona

Claude Code escribe el estado de cada corrida en disco, y el monitor no usa nada más que eso:

```text
~/.claude/projects/<proyecto>/<sesion>/subagents/workflows/<wf_runId>/
    journal.jsonl          {"type":"started"|"result","agentId":...}
    agent-<id>.jsonl       transcript del agente (una línea JSON por evento; línea 0 = prompt)
    agent-<id>.meta.json   {agentType, description, spawnDepth}
~/.claude/projects/<proyecto>/<sesion>/workflows/scripts/<nombre>-<wf_runId>.js
```

(En Windows, `~/.claude` es `%USERPROFILE%\.claude`.)

El server — Python solo stdlib, multi-hilo, bind exclusivo en `127.0.0.1` — parsea esos
archivos en cada request; el dashboard es un único `index.html` sin dependencias. No hay base
de datos ni estado persistente — solo un cache en memoria de los prompts, que son inmutables:
refrescar la página siempre muestra el disco tal como está.

## Launcher

Hay dos launchers con el mismo comportamiento: `monitor-app.cmd` para Windows (la lógica vive
en `workflow-monitor/start-monitor.ps1`; el `.cmd` es un wrapper portable que resuelve su ruta
con `%~dp0`) y `monitor-app.sh` para Linux/macOS (POSIX sh, sin bashisms; acepta también los
nombres de flags del `.cmd`):

```text
monitor-app.cmd  [-Port 8788]  [-NoBrowser]   [-Restart]  [-Stop]      # Windows
./monitor-app.sh [--port 8788] [--no-browser] [--restart] [--stop]     # Linux / macOS
```

Sin flags: puerto 8787 y abre el navegador. `-Port`/`--port` cambia el puerto (el dashboard
usa URLs relativas: funciona igual en cualquiera); `-NoBrowser`/`--no-browser` levanta solo el
server; `-Restart`/`--restart` mata el server actual y levanta uno nuevo; `-Stop`/`--stop` lo
baja.

- **Idempotente**: si ya hay un monitor respondiendo en el puerto (lo verifica contra
  `/api/ping`, que responde con firma propia), reusa esa instancia en vez de levantar un
  segundo proceso. Si el puerto lo ocupa un proceso que **no** es el monitor, informa su PID y
  nombre y sale con código 1 sin tocarlo.
- **Para bajarlo usá `-Stop`/`--stop`**: resuelve el PID puntual desde el puerto y baja solo
  ese proceso. No mates procesos de Python por nombre (`python.exe`, `pkill python`) — en una
  máquina con MCPs u otras herramientas locales (otros servers Python) suele haber más de
  uno.
- Prefiere un binario standalone si existe (`dist\WorkflowMonitor.exe` en Windows;
  `dist/WorkflowMonitor` si compilaste uno con PyInstaller en Linux/macOS) y, si no, cae a
  `python server.py`. Sale con código 0 (OK) o 1 (sin Python ni binario, puerto ajeno, o
  server que no respondió tras ~8 s de polling).

A mano, sin launcher:

```text
python workflow-monitor/server.py [puerto]    # default 8787 (python3 en Linux/macOS)
dist\WorkflowMonitor.exe [puerto]             # Windows, si compilaste el exe (ver abajo)
```

## Exe standalone (solo Windows) — sin Python

`workflow-monitor/build-exe.ps1` compila el server con `index.html` embebido a un único
ejecutable de Windows (~8 MB) que **no necesita Python en la máquina donde corre**. En
Linux/macOS no hay binario publicado: se corre `server.py` directo — o compilás el tuyo con
PyInstaller en ese SO, y `monitor-app.sh` lo prefiere si aparece como `dist/WorkflowMonitor`:

```powershell
powershell -File workflow-monitor\build-exe.ps1           # -> dist\WorkflowMonitor.exe
powershell -File workflow-monitor\build-exe.ps1 -Clean    # borra .buildvenv/, build/, dist/ y *.spec, y recompila
```

Usa PyInstaller en `--onefile` dentro de un venv propio (`.buildvenv/`), así que no toca el
`site-packages` global. Python hace falta para **compilar**, no para ejecutar: en una máquina
sin Python alcanza con copiar `monitor-app.cmd` + `workflow-monitor\start-monitor.ps1` +
`dist\WorkflowMonitor.exe`.

Notas del exe:

- **El binario no se versiona** (`dist/` está gitignoreado): se recompila con el script.
- Está **sin firmar**: SmartScreen o un antivirus corporativo pueden frenarlo la primera vez.
- Deja la consola visible a propósito (`--console`), para poder cortarlo con Ctrl+C y ver
  errores.
- Después de recompilar, `monitor-app.cmd -Restart` levanta el binario nuevo.

## API

Todas las respuestas son JSON; los errores también (`{"error": ...}`, con status 404 o 500 —
salvo la validación de `/api/search`, que responde 200 con el error en el cuerpo).

| Ruta | Qué devuelve |
|---|---|
| `/api/ping` | liveness O(1) con firma: `{"ok": true, "app": "workflow-monitor"}` |
| `/api/runs` | todos los runs de todas las conversaciones + pseudo-runs de agentes sueltos |
| `/api/run?id=<wf_id>` | agentes de un run, con estado y actividad |
| `/api/agent?run=<wf_id>&id=<agent_id>` | últimos eventos del transcript de un agente |
| `/api/plan?run=<wf_id>` | plan declarado del workflow: nombre, descripción y fases |
| `/api/prompts?run=<wf_id>` | agentes agrupados por familia de prompt, con el molde común |
| `/api/prompt?run=<wf_id>&id=<agent_id>` | el prompt completo de un agente, con su metadata |
| `/api/search?q=<texto>&proyecto=&tipo=` | busca en los prompts de **todos** los runs (mínimo 2 caracteres, tope 200 agentes) |
| `/api/script?run=<wf_id>` | el `.js` del workflow |

`/api/ping` existe para chequear liveness: `/api/runs` recorre todo el árbol de
`~/.claude/projects` y con cientos de runs tarda segundos, así que no sirve como health check.

```text
> curl http://127.0.0.1:8787/api/ping
{"ok": true, "app": "workflow-monitor"}
```

(En PowerShell de Windows usá `curl.exe`: `curl` a secas es un alias de `Invoke-WebRequest`.)

## Estados de agente

El estado se infiere del journal del run y de la última escritura del transcript:

| Estado | Criterio |
| --- | --- |
| `TERMINADO` | el journal tiene su `result` |
| `ACTIVO` | transcript escrito hace menos de 60 s |
| `LENTO` | quieto entre 60 s y 5 min |
| `REEMPLAZADO` | quieto más de 5 min sin `result`, pero otro agente completó su prompt (el run se reanudó y ese prompt lo tomó otro agente) |
| `MUERTO` | quieto más de 5 min y sin `result` — las muertes no escriben journal |

A nivel run: `ACTIVO` si el agente más fresco escribió hace menos de 90 s, `TERMINADO` si el
journal cierra con un `result`, `ESTANCADO` en el resto. Los **agentes sueltos** no tienen
journal, así que uno quieto se reporta `TERMINADO`: no hay forma de distinguir una muerte.

## Skill de Claude Code — `/levantar-entorno`

[.claude/skills/levantar-entorno](.claude/skills/levantar-entorno/SKILL.md) envuelve el
launcher de Windows para Claude Code: `/levantar-entorno` levanta el monitor, abre Chrome y reporta
cuántos runs ve. El SKILL.md documenta los modos de falla y, sobre todo, lo que **no** hay que
hacer acá (matar árboles de procesos, "corregir" puertos, buscar una base de datos que no
existe).

## Monitor de consola — `FallBack/`

La versión original, en PowerShell puro (**solo Windows**): no necesita Python ni navegador,
pero **no es el camino principal**.

```text
FallBack\monitor-workflow.cmd -List            # runs de TODAS las conversaciones/proyectos
FallBack\monitor-workflow.cmd -Once            # un snapshot y sale
FallBack\monitor-workflow.cmd -IntervalSec 10  # cadencia del refresco (default 3 s)
```

No lo uses como fuente de verdad: solo ve runs de workflows (no agentes sueltos) y no
distingue `REEMPLAZADO`. El resto de los flags y sus límites están en
[FallBack/README.md](FallBack/README.md).

## Privacidad y seguridad

El dashboard muestra el contenido íntegro de tus conversaciones con Claude Code (prompts,
transcripts, resultados). El diseño acota qué puede pasar con eso:

- **Solo lectura garantizada**: nunca escribe, modifica ni borra nada bajo `~/.claude`. Podés
  levantarlo con workflows corriendo, sin riesgo de corromper sesiones.
- **Solo local**: el server bindea exclusivamente `127.0.0.1`; no queda expuesto a la red. No
  lo publiques con túneles ni port-forwarding — le estarías dando tus conversaciones a
  cualquiera.
- **Sin telemetría ni llamadas salientes**: cero dependencias externas (Python stdlib, HTML
  sin CDNs) y ninguna conexión que no inicie tu navegador contra `127.0.0.1`.
- Los ids que llegan por la API se validan con regex antes de tocar disco (sin path
  traversal).
- Con el dashboard abierto, **cuidado al compartir pantalla o subir capturas**: lo que se ve
  es el contenido real de tus sesiones.

## Solución de problemas

- **(Windows) Un script tarda ~2 s por request contra `localhost`** → `localhost` resuelve primero a
  `::1` y el server bindea solo IPv4, así que WinINet paga el fallback IPv6 antes de conectar.
  Usá `127.0.0.1` directo (el launcher ya lo hace; Chrome no lo sufre porque prueba ambas
  familias en paralelo).
- **(Windows) Cada corrida del launcher abre una ventana de Chrome nueva** aunque el server se reuse:
  Chrome no permite reenfocar de forma confiable una ventana `--app` existente. Con
  `-NoBrowser` levantás solo el server.
- **(Windows) SmartScreen frena el exe** → está sin firmar; es esperable la primera vez.
- **`El puerto NNNN lo tiene ocupado OTRO proceso`** → levantalo en otro puerto con
  `-Port`/`--port`; el dashboard funciona igual en cualquier puerto (URLs relativas).
- **(Windows)** Rutas que superan el `MAX_PATH` no tumban el server: saltea ese archivo y sigue.

## Aviso

- Proyecto **independiente**: no está afiliado a Anthropic ni respaldado por Anthropic. Claude
  y Claude Code son marcas de Anthropic PBC.
- El monitor lee **formatos internos de Claude Code que no son API pública** (`journal.jsonl`,
  `agent-*.jsonl`, scripts de workflows): una actualización de Claude Code puede cambiarlos y
  romper el parseo. Si te pasa, [abrí un issue](../../issues) indicando tu versión de Claude
  Code.

## Contribuir

Issues (bugs y solicitudes de mejora) y pull requests son bienvenidos — ver
[CONTRIBUTING.md](CONTRIBUTING.md). Regla clave del repo: los `.ps1` son **ASCII puro a
propósito** (PowerShell 5.1 rompe con UTF-8 sin BOM); el resto de las reglas está en ese
archivo.

## Licencia

[MIT + Commons Clause](LICENSE): podés usarlo, copiarlo y modificarlo libremente, también
en entornos comerciales, pero no está permitido **venderlo** — ni cobrarlo como producto o
servicio (hosting, soporte pago, etc.) cuyo valor derive sustancialmente de este software.
