@echo off
rem Lanza el Workflow Monitor (server local, solo lectura) y abre el dashboard en Chrome.
rem Toda la logica vive en start-monitor.ps1 (idempotente: reusa el server si ya esta arriba).
rem Acepta los mismos parametros: -Port 9000 / -NoBrowser / -Restart / -Stop
@powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0workflow-monitor\start-monitor.ps1" %*
