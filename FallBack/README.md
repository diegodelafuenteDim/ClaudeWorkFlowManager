# FallBack — monitor de consola

Monitor de workflows/subagentes en PowerShell puro (**solo Windows**). Fue la **primera**
versión de esta herramienta; hoy el camino principal es el dashboard web
(`../workflow-monitor/`, se levanta con `../monitor-app.cmd` en Windows o `../monitor-app.sh`
en Linux/macOS, o con el skill `/levantar-entorno`).

Se conserva porque es el único que **no necesita Python ni navegador** (aunque sí Windows con
PowerShell): sirve si Python se rompe, si querés un snapshot en consola (`-Once`), o si estás
en una sesión de Windows sin GUI.

```
monitor-workflow.cmd                    # autodetecta el run mas reciente, refresca cada 3s
monitor-workflow.cmd -Once              # un snapshot y sale
monitor-workflow.cmd -List              # runs de TODAS las conversaciones/proyectos
monitor-workflow.cmd -Run af60b0ed      # elegir run por prefijo del wf_id
monitor-workflow.cmd -Detail a4fbf981   # ultimos eventos de UN agente y sale
monitor-workflow.cmd -Follow a4fbf981   # sigue a UN agente en vivo (Ctrl+C para salir)
monitor-workflow.cmd -RunDir <path>     # apuntar a un wf_* especifico
```

## No es ground truth — lo que este monitor NO ve

El dashboard es un superconjunto funcional. Si usás el de consola, tené presente que:

| | consola | dashboard |
|---|---|---|
| Agentes sueltos (Agent tool / skills en background, fuera de workflows) | **no los ve** — solo globea `subagents\workflows\wf_*` | sí |
| Estado `REEMPLAZADO` (murió, pero otro agente completó su prompt tras un resume) | no lo distingue: los reporta como caídos | sí, cruzando las keys del journal |
| Profundidad de lectura del transcript | `Get-Content -Tail 6` | tail de 512 KB |
| Extracción de la misión del agente | regex `SOS EL...` + fallback corto | además saltea el boilerplate de paths |

Es decir: podés perderte agentes, y ver "viejo/caido" donde el dashboard dice `REEMPLAZADO`.
Para diagnosticar en serio, usá el dashboard.

**No se planea llevarlo a paridad**: sería duplicar en PowerShell lógica que ya vive en
`../workflow-monitor/server.py`.

## Nota de mantenimiento

`monitor-workflow.ps1` es **ASCII puro a propósito** — PowerShell 5.1 rompe con UTF-8 sin BOM.
No metas acentos, `ñ` ni guiones tipográficos. El skill `/subir-cambios` lo verifica antes de
cada commit.
