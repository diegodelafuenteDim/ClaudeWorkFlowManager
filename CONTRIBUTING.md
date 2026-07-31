# Contribuir a ClaudeWorkflowMonitor

Gracias por el interés. Este proyecto acepta reportes de bugs, solicitudes de mejora y
pull requests.

## Reportar un bug o pedir una mejora

Abrí un [issue](../../issues/new/choose) usando el template que corresponda:

- **Reporte de bug** — algo no funciona como debería. Incluí tu SO y versión (Windows, Linux
  o macOS), la versión de Python y — si estás en Windows — la de PowerShell, o indicá si usás
  el exe compilado; sumá los pasos para reproducir.
- **Solicitud de mejora** — una funcionalidad o cambio que te gustaría ver.

Al pegar logs o capturas, tené en cuenta que el monitor muestra contenido de tus propias
conversaciones de Claude Code: **no pegues prompts o transcripts con información sensible**.

## Pull requests

1. Hacé un fork del repo y creá una rama desde `main`.
2. Hacé el cambio siguiendo las reglas de abajo.
3. Abrí el PR contra `main` explicando qué cambia, por qué, y cómo lo probaste.

Para cambios grandes conviene abrir primero un issue y charlarlo — así no invertís trabajo
en algo que después no encaja con el alcance del proyecto.

Revisamos los PRs a medida que podemos; puede que pidamos cambios o que rechacemos un PR
que se aleje del alcance (herramienta local, read-only, sin dependencias externas).

## Reglas del código

- **Los `.ps1` son ASCII puro** — PowerShell 5.1 rompe con UTF-8 sin BOM. Sin acentos, `ñ`,
  ni comillas o guiones tipográficos (`—`, `“`, `’`).
- **`monitor-app.sh` es POSIX sh** — sin bashisms (corre con dash/ash/bash/zsh), y se
  commitea con fin de línea LF (lo fuerza `.gitattributes`).
- **`server.py` usa solo stdlib de Python** (3.9+) y **tiene que seguir siendo
  multiplataforma** — nada específico de un SO sin fallback.
- **El monitor es read-only**: nunca escribe, modifica ni borra nada bajo `~/.claude`.
- Probar según el componente tocado antes de abrir el PR: `server.py`/`index.html` (core) →
  cualquier SO con Python 3.9+; `.ps1`/`.cmd`/exe → Windows con PowerShell 5.1;
  `monitor-app.sh` → Linux o macOS.
- Documentación y mensajes de commit en español, con la convención
  `tipo(scope): descripción` (`feat`, `fix`, `refactor`, `docs`, `chore`, `test`, `perf`).

## Licencia de las contribuciones

Al enviar un pull request aceptás que tu contribución se publique bajo la misma licencia
del repositorio ([MIT + Commons Clause](LICENSE)).
