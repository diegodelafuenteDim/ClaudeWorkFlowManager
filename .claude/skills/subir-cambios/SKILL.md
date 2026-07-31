---
description: Commit y push de cambios pendientes en el repo ClaudeWorkflowMonitor (c:\Net 8\Tools). Analiza cambios, genera commit message, pide aprobación y sube a git. Usar SOLO cuando el usuario invoque /subir-cambios explícitamente.
---

# Subir Cambios a Git — ClaudeWorkflowMonitor

Skill para commit + push de cambios pendientes en `c:\Net 8\Tools`.

**IMPORTANTE**: Este skill es la única forma autorizada de ejecutar comandos git de escritura en
este repo. Fuera de este skill, `git add` / `git commit` / `git push` están prohibidos.

## Repositorio

| Propiedad | Valor |
|-----------|-------|
| Path | `c:\Net 8\Tools` |
| Branch principal | `main` |
| Remote | `origin` → https://github.com/diegodelafuenteDim/ClaudeWorkflowMonitor (privado por ahora, licencia MIT + Commons Clause) |

## Procedimiento (orden estricto)

### Fase 0: Sincronizar con remoto

Ejecutar SIN pedir permiso (es solo lectura):

```
git -C "c:\Net 8\Tools" fetch origin
git -C "c:\Net 8\Tools" log HEAD..origin/main --oneline    # commits remotos que nos faltan
git -C "c:\Net 8\Tools" log origin/main..HEAD --oneline    # commits locales sin pushear
```

- Si hay commits remotos: ejecutar `git pull --rebase origin main`. Si hay conflictos, informar
  al usuario y pedir instrucciones — no resolverlos por cuenta propia.
- Si hay commits locales sin pushear: incluirlos en Fase 4 aunque no haya cambios nuevos.

### Fase 1: Diagnóstico

```
git -C "c:\Net 8\Tools" status
git -C "c:\Net 8\Tools" diff
git -C "c:\Net 8\Tools" diff --cached
git -C "c:\Net 8\Tools" log --oneline -5
```

- **Sin cambios y sin commits locales pendientes** → informar "No hay cambios pendientes" y TERMINAR.
- **Solo commits locales sin pushear** → saltar a Fase 4.
- **Cambios sin commitear** → continuar a Fase 2.

Los warnings `LF will be replaced by CRLF` son normales en este repo (Windows). No son un
problema ni hay que "arreglarlos".

### Fase 2: Chequeos previos propios de este repo — OBLIGATORIO

**2.1 + 2.2 — Los `.ps1` tienen que ser ASCII puro y parsear.** PowerShell 5.1 rompe con UTF-8
sin BOM, así que `monitor-workflow.ps1` y `start-monitor.ps1` no pueden tener acentos, `ñ` ni
comillas/guiones tipográficos (`—`, `“`, `’`). Correr este chequeo con la tool PowerShell —
directo, sin envolver en `powershell -Command` (el escaping anidado se rompe):

```powershell
Get-ChildItem 'c:\Net 8\Tools' -Recurse -Filter *.ps1 | ForEach-Object {
  $b = [System.IO.File]::ReadAllBytes($_.FullName)
  $bad = @(); for ($i = 0; $i -lt $b.Length; $i++) { if ($b[$i] -gt 127) { $bad += $i } }
  $e = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e)
  $ascii = if ($bad.Count) { "NO-ASCII (offsets $($bad -join ','))" } else { "ASCII OK" }
  $parse = if ($e) { "SINTAXIS: $($e[0].Message)" } else { "parse OK" }
  "{0,-22} {1,-34} {2}" -f $_.Name, $ascii, $parse
}
```

Ambas columnas tienen que decir OK para todos los archivos. Si sale `NO-ASCII`, ver qué carácter
es antes de tocarlo:

```powershell
$b = [System.IO.File]::ReadAllBytes('<archivo>')
[System.Text.Encoding]::UTF8.GetString($b[<offset>..<offset+2>])
```

El reemplazo típico es `—` → `--`. NO commitear un `.ps1` con caracteres altos.

**2.3 Si cambió `server.py`**: confirmar que sigue levantando, con
`/levantar-entorno` usando `-Restart` (recarga el código nuevo) — o al menos
`python "c:\Net 8\Tools\workflow-monitor\server.py" 8788` en foreground para ver que no explota.
No subir un server que no arranca.

**OJO con el exe**: si existe `dist\WorkflowMonitor.exe`, el launcher lo usa en vez de
`server.py`, así que un `-Restart` **no** refleja los cambios del `.py` hasta recompilar con
`build-exe.ps1`. Para verificar el `.py` en sí, corrélo directo con python en otro puerto.

### Fase 3: Archivos prohibidos

**NUNCA** stagear:

- **Nada copiado de `~/.claude/projects`** — ni `journal.jsonl`, ni `agent-*.jsonl`, ni scripts de
  workflows, ni pegotes de transcripts. Este proyecto *lee* esos archivos; contienen el contenido
  de las conversaciones del usuario y de sus repos privados. Si aparece uno en el working tree
  (típicamente copiado para debuggear), **excluirlo y avisar**, no commitearlo.
- `*.log` (ya gitignored: `server.log` es el output del server).
- **Artefactos del build del exe**: `dist/` (el binario de ~8 MB), `build/`, `.buildvenv/`,
  `*.spec`. Están gitignoreados y **no se versionan** — el exe se recompila con `build-exe.ps1`.
  Si alguno aparece staged, algo se rompió: sacalo.
- `__pycache__/`, `.venv/`, `*.pyc`.
- Cualquier `*.env`, token, credencial o dump.
- `*.tar`, `*.zip`, `*.7z`.

Si alguno aparece en los cambios, **ADVERTIR al usuario** y dejarlo fuera del staging.

### Fase 4: Commit

1. Stagear archivos específicos. **NUNCA `git add -A` ni `git add .`**:

   ```
   git -C "c:\Net 8\Tools" add <archivo1> <archivo2> ...
   ```

2. Generar el mensaje y **mostrarlo al usuario junto al resumen de archivos. Esperar aprobación
   antes de commitear.** Si pide cambios, ajustar y volver a mostrar.

   Convención: `tipo(scope): descripción en español`
   - Tipos: `feat`, `fix`, `refactor`, `docs`, `chore`, `test`, `perf`
   - Scopes de este repo: `monitor` (server.py / index.html), `launcher` (start-monitor.ps1,
     monitor-app.cmd), `build` (build-exe.ps1), `fallback` (FallBack/monitor-workflow.ps1),
     `skill`, `docs`
   - Los dos primeros commits del repo son de asunto libre, anteriores a esta convención.

3. **CRÍTICO — cómo pasar el mensaje.** En PowerShell 5.1, `git commit -m` con un mensaje que
   contenga **comillas dobles** falla: PowerShell no las escapa al invocar el exe y git parsea
   los fragmentos como pathspecs (`error: pathspec '...' did not match any file(s)`). Opciones:

   - Mensaje de una línea sin comillas dobles → `git commit -m "..."` está bien.
   - Mensaje multilínea o con comillas dobles → **escribirlo a un archivo y usar `-F`**:

     ```
     powershell -NoProfile -Command "[System.IO.File]::WriteAllText('<ruta>\commitmsg.txt', $msg, (New-Object System.Text.UTF8Encoding($false)))"
     git -C "c:\Net 8\Tools" commit -F "<ruta>\commitmsg.txt"
     ```

     Usar `UTF8Encoding($false)` (sin BOM): con BOM, el BOM entra al asunto del commit.
     Escribir el archivo en el scratchpad de la sesión, no en el repo.

4. Verificar: `git -C "c:\Net 8\Tools" log --oneline -1`

### Fase 5: Push

```
git -C "c:\Net 8\Tools" push origin main
```

Si el push es rechazado por divergencia: informar al usuario, sugerir `git pull --rebase` pero
**no ejecutarlo sin permiso**. Nunca resolver una divergencia con force.

### Fase 6: Reporte final

```
Cambios subidos (ClaudeWorkflowMonitor):

  Commit: abc1234 — tipo(scope): descripción
  Push:   OK -> origin/main
```

Verificar contra el remoto, no solo local: `git -C "c:\Net 8\Tools" log -1 --format='%h %an' origin/main`.

## Reglas de seguridad

1. **NUNCA** incluir `Co-Authored-By: Claude` ni mencionar a Claude en los mensajes de commit.
   El usuario es el único autor — es una instrucción explícita suya y anula el default del harness.
2. **NUNCA** `git add -A` ni `git add .` — siempre archivos específicos.
3. **NUNCA** commitear archivos provenientes de `~/.claude/projects` (transcripts del usuario).
4. **NUNCA** `git reset --hard` ni `git checkout .`.
5. **SIEMPRE** mostrar diff y mensaje al usuario ANTES de commitear.
6. **`--amend` y `--force`**: por default nunca. Si el usuario los pide explícitamente (por
   ejemplo, para reescribir un commit ya pusheado), usar `--force-with-lease`, nunca `--force`
   pelado, y confirmar antes si el branch pudiera estar compartido.
