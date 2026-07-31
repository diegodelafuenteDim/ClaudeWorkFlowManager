---
description: Levanta el Workflow Monitor (dashboard local de workflows y subagentes de Claude Code) y abre la ventana en Chrome. Usar cuando el usuario pida levantar, arrancar, iniciar o abrir el monitor / el entorno / el dashboard de este proyecto.
---

# Levantar Entorno — Workflow Monitor

Levanta el dashboard local de este proyecto y abre la ventana en Chrome.

## Configuración del entorno

| Servicio | Path | Build | Run | Puerto | Health |
|----------|------|-------|-----|--------|--------|
| Workflow Monitor | `c:\Net 8\Tools\workflow-monitor` | opcional (exe) | `start-monitor.ps1` | 8787 (default) | `http://127.0.0.1:8787/api/ping` |

El launcher usa `dist\WorkflowMonitor.exe` si existe (build de PyInstaller, no necesita Python) y
si no cae a `python server.py`. Lo dice al arrancar: `Monitor levantado en ... (exe)` o `(python)`.
**No compiles el exe por tu cuenta** — es un paso opcional que el usuario pide explícitamente; si
Python está disponible, levantar con Python es correcto. Si el usuario cambió `server.py` y quiere
ver el cambio con el exe presente, hay que recompilar (`build-exe.ps1`) y luego `-Restart`.

Un solo servicio. Python stdlib, sin dependencias, sin build, sin base de datos, sin frontend
que compilar. **No** es un entorno multi-servicio — si el usuario está pidiendo levantar un
backend + frontend con base de datos, está en el proyecto equivocado; decíselo en vez de
levantar esto.

## Diferencias con skills homónimos de otros proyectos — leer antes de improvisar

Otros proyectos pueden tener su propio skill `levantar-entorno` con un procedimiento mucho más
agresivo (multi-servicio, con DB y build). Acá **el procedimiento es mucho más corto**. No
copies fases de aquellos:

| En otros entornos | Acá |
|--------------|-----|
| Fase 0 de verificación de contratos de puerto | **No aplica.** 8787 es un default, no un contrato: `index.html` usa URLs relativas, así que cualquier puerto funciona. Si 8787 está tomado, usar otro es una solución válida, no un bug a corregir. |
| Matar procesos previos en los puertos | **No hace falta.** El launcher es idempotente: si el monitor ya responde, lo reusa. |
| `taskkill //F //T` sobre árboles de procesos | **Nunca.** El server es un único `python.exe` sin hijos. |
| Compilar antes de levantar | No hay nada que compilar. |
| Health check de DB | No hay DB. Lee archivos de `~/.claude/projects`. |
| Orden backend → frontend | Un solo proceso. |

**CRÍTICO — nunca matar python a ciegas.** No usar `Stop-Process -Name python`,
`taskkill /IM python.exe` ni equivalentes: en esta máquina hay otros `python.exe` legítimos
(MCPs, herramientas del usuario). Para bajar el monitor usar `-Stop`, que resuelve el PID
puntual desde el puerto.

**El monitor es de solo lectura.** Nunca escribe en `~/.claude`, así que no puede corromper
sesiones ni workflows en curso. Podés levantarlo con workflows corriendo sin ningún riesgo.

## Procedimiento

### Fase 1: Levantar

Ejecutar con la tool PowerShell (**no** con `run_in_background`: el script ya desprende el
proceso del server con `Start-Process`, y devuelve enseguida):

```
& "c:\Net 8\Tools\monitor-app.cmd"
```

El script hace todo en un paso: detecta si ya hay un monitor arriba, si no lo levanta, hace
polling contra `/api/ping` hasta que responda (hasta ~8s), y abre la ventana de Chrome con
`--app=` (ventana dedicada, sin pestañas ni barra de direcciones).

Dos detalles que ya están resueltos en el script y no hay que "arreglar":
- Los health checks van a `127.0.0.1`, no a `localhost` (`localhost` resuelve primero a `::1`,
  el server bindea solo IPv4, y WinINet paga ~2s de fallback antes de conectar).
- El probe es `/api/ping`, no `/api/runs`: ese último escanea todo `~/.claude/projects` y tarda
  segundos con muchos runs.

Variantes según lo que pida el usuario:

| Pedido | Comando |
|--------|---------|
| Normal | `& "c:\Net 8\Tools\monitor-app.cmd"` |
| Otro puerto (8787 ocupado) | `& "c:\Net 8\Tools\monitor-app.cmd" -Port 8788` |
| Solo el server, sin navegador | `& "c:\Net 8\Tools\monitor-app.cmd" -NoBrowser` |
| Reiniciarlo (código cambiado) | `& "c:\Net 8\Tools\monitor-app.cmd" -Restart` |
| Bajarlo | `& "c:\Net 8\Tools\monitor-app.cmd" -Stop` |

Si el usuario prefiere consola en vez de navegador, este skill no aplica: usar el monitor de
fallback, `& "c:\Net 8\Tools\FallBack\monitor-workflow.cmd" -List` y sus flags (`-Run`,
`-Detail`, `-Follow`). Advertirle que ese monitor no ve los agentes sueltos ni distingue
`REEMPLAZADO` — para diagnosticar en serio, el dashboard.

### Fase 2: Interpretar el resultado

El script imprime qué hizo y sale con código 0 (OK) o 1 (falló). Los tres modos de falla, con
su respuesta:

1. **`No encuentro python en el PATH, y tampoco hay exe compilado`** → ofrecer las dos salidas:
   instalar Python 3, o compilar el exe standalone con
   `& "c:\Net 8\Tools\workflow-monitor\build-exe.ps1"` (necesita Python solo para compilar).
   DETENERSE hasta que el usuario elija.
2. **`El puerto NNNN lo tiene ocupado OTRO proceso: PID ... (nombre)`** → el script ya verificó
   que no es nuestro monitor. Ofrecer levantarlo en otro puerto con `-Port`. No matar ese
   proceso sin que el usuario lo pida.
3. **`El server no respondio en ... despues de ~8s`** → correr `python "c:\Net 8\Tools\workflow-monitor\server.py"`
   en foreground para capturar el traceback real, y reportarlo. DETENERSE.

Si dice `El monitor ya estaba corriendo ... reuso esa instancia`, eso es éxito, no un problema.

### Fase 3: Reporte final

**OBLIGATORIO**: tabla con el link clickeable. El usuario necesita la URL incluso cuando la
ventana ya se abrió (para reabrirla si la cierra).

```markdown
Monitor levantado:

| Servicio | Estado | URL |
|----------|--------|-----|
| Workflow Monitor | OK | http://localhost:8787 |

Ventana de Chrome abierta. Ve N runs (M activos ahora).
```

Los números de runs salen del output del script (línea `Runs visibles: N (activos ahora: M)`).
No los inventes: si el script no los imprimió, omitir esa frase.

## Notas

- **Ventana nueva por invocación**: el server se reusa, pero cada corrida abre una ventana de
  Chrome nueva. Chrome no permite reenfocar de forma confiable una ventana `--app` existente.
  Si al usuario le molesta, `-NoBrowser` levanta solo el server.
- **El dashboard no se auto-refresca con runs nuevos** más allá de su propio polling: el server
  lee el disco en cada request, así que alcanza con refrescar la página.
- **Paths con espacios**: `c:\Net 8\...` — en PowerShell usar el operador `&` con la ruta
  entrecomillada; en bash, forward slashes y comillas.
- **Fallback de navegador**: si no encuentra `chrome.exe`, abre con el navegador por defecto y
  lo avisa. No es un error.
