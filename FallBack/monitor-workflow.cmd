@echo off
rem Monitor de consola (fallback sin dependencias). Ver FallBack\README.md.
rem %~dp0 = esta carpeta, asi que funciona desde cualquier clon o ruta.
@powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0monitor-workflow.ps1" %*
