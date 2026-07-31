# build-exe.ps1 - compila el Workflow Monitor a un .exe standalone con PyInstaller.
# (archivo ASCII puro: PowerShell 5.1 rompe con UTF-8 sin BOM)
#
# El exe resultante NO necesita Python en la maquina donde corre. index.html queda
# embebido en el bundle (server.py lo busca via sys._MEIPASS).
#
# Uso:
#   powershell -File build-exe.ps1              # compila a <repo>\dist\WorkflowMonitor.exe
#   powershell -File build-exe.ps1 -Clean       # borra venv/build/spec previos y recompila
#
# Requisitos: Python 3 en el PATH (solo para COMPILAR; el exe ya no lo necesita).
# El venv de build y los intermedios viven fuera del repo (estan gitignoreados igual).
param(
    [switch]$Clean
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent $here
$dist = Join-Path $repo "dist"
$work = Join-Path $repo "build"
$venv = Join-Path $repo ".buildvenv"
$venvPy = Join-Path $venv "Scripts\python.exe"
$serverPy = Join-Path $here "server.py"
$indexHtml = Join-Path $here "index.html"

foreach ($req in @($serverPy, $indexHtml)) {
    if (-not (Test-Path $req)) { Write-Host "Falta $req" -ForegroundColor Red; exit 1 }
}

if ($Clean) {
    foreach ($d in @($venv, $work, $dist)) {
        if (Test-Path $d) { Remove-Item $d -Recurse -Force; Write-Host "borrado: $d" }
    }
    Get-ChildItem $repo -Filter *.spec -ErrorAction SilentlyContinue | Remove-Item -Force
}

# --- venv de build (aislado: no toca el site-packages global) ---
if (-not (Test-Path $venvPy)) {
    $python = $null
    foreach ($n in @("python", "py")) {
        $c = Get-Command $n -ErrorAction SilentlyContinue
        if ($c) { $python = $c.Source; break }
    }
    if (-not $python) { Write-Host "No encuentro python en el PATH (se necesita para compilar)." -ForegroundColor Red; exit 1 }
    Write-Host "Creando venv de build en $venv ..."
    & $python -m venv $venv
    if (-not (Test-Path $venvPy)) { Write-Host "No pude crear el venv." -ForegroundColor Red; exit 1 }
}

Write-Host "Instalando/actualizando PyInstaller ..."
& $venvPy -m pip install --quiet --upgrade pip pyinstaller
if ($LASTEXITCODE -ne 0) { Write-Host "Fallo la instalacion de PyInstaller." -ForegroundColor Red; exit 1 }

# --- build ---
# --onefile: un solo .exe. --console: dejamos la consola a proposito, asi se puede
#   cortar con Ctrl+C y se ven los errores si algo falla.
# --add-data "origen;destino": el ';' es el separador en Windows. '.' = raiz del bundle.
Write-Host "Compilando ..."
& $venvPy -m PyInstaller `
    --onefile `
    --console `
    --name WorkflowMonitor `
    --add-data "$indexHtml;." `
    --distpath $dist `
    --workpath $work `
    --specpath $repo `
    --noconfirm `
    $serverPy
if ($LASTEXITCODE -ne 0) { Write-Host "PyInstaller fallo." -ForegroundColor Red; exit 1 }

$exe = Join-Path $dist "WorkflowMonitor.exe"
if (-not (Test-Path $exe)) { Write-Host "PyInstaller termino OK pero no encuentro $exe" -ForegroundColor Red; exit 1 }

$mb = [math]::Round((Get-Item $exe).Length / 1MB, 1)
Write-Host ""
Write-Host "OK -> $exe  ($mb MB)" -ForegroundColor Green
Write-Host "Ya no necesita Python. start-monitor.ps1 lo usa automaticamente si existe."
exit 0
