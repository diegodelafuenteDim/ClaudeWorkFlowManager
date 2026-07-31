## Qué cambia

## Por qué

## Cómo lo probaste

<!-- SO y versión de Python; PowerShell si tocaste .ps1/.cmd; shell/distro si tocaste monitor-app.sh. Qué corriste. -->

## Checklist

- [ ] Los `.ps1` siguen siendo ASCII puro (sin acentos, ñ ni tipografía curva)
- [ ] `monitor-app.sh` sigue siendo POSIX sh (sin bashisms) con fin de línea LF
- [ ] `server.py` sigue usando solo stdlib (sin dependencias nuevas) y multiplataforma
- [ ] El monitor sigue siendo read-only sobre `~/.claude`
- [ ] Probado en la plataforma del componente tocado (core: cualquier SO con Python 3.9+; `.ps1`/`.cmd`/exe: Windows con PowerShell 5.1; `monitor-app.sh`: Linux o macOS)
