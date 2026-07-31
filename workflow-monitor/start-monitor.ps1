# start-monitor.ps1 - levanta el Workflow Monitor (si no esta arriba) y abre el dashboard en Chrome.
# (archivo ASCII puro: PowerShell 5.1 rompe con UTF-8 sin BOM -- ver ..\FallBack\monitor-workflow.ps1)
#
# Uso:
#   powershell -File start-monitor.ps1                # puerto 8787, abre ventana de Chrome
#   powershell -File start-monitor.ps1 -Port 9000     # otro puerto (index.html usa URLs relativas)
#   powershell -File start-monitor.ps1 -NoBrowser     # solo el server, sin abrir nada
#   powershell -File start-monitor.ps1 -Restart       # mata el server actual y levanta uno nuevo
#   powershell -File start-monitor.ps1 -Stop          # baja el server y sale
#
# Idempotente: si el server ya responde, lo reusa (no levanta un segundo proceso).
# Salidas: 0 = OK, 1 = error (python ausente o viejo, puerto ajeno, server no responde).
param(
    [int]$Port = 8787,
    [switch]$NoBrowser,
    [switch]$Restart,
    [switch]$Stop
)

if ($Port -lt 1 -or $Port -gt 65535) {
    $host.UI.WriteErrorLine("Puerto fuera de rango: $Port (1-65535).")
    exit 1
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$serverPy = Join-Path $here "server.py"

# DOS urls a proposito:
#  $probe = 127.0.0.1 -> para los health checks. 'localhost' resuelve primero a ::1 y el
#    server bindea solo 127.0.0.1, asi que WinINet intenta IPv6, espera ~2s y recien
#    entonces cae a IPv4: con timeouts cortos eso da falsos negativos. Por IP: ~20ms.
#  $base = localhost -> para mostrar y abrir en el navegador (Chrome hace Happy Eyeballs,
#    prueba ambas familias en paralelo, no paga esa penalidad).
$probe = "http://127.0.0.1:$Port"
$base = "http://localhost:$Port"

function Get-Listener {
    Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Test-Monitor {
    # Confirma que quien escucha el puerto es NUESTRO monitor y no otra cosa.
    # OJO: probar con /api/runs NO sirve -- ese endpoint recorre todo ~/.claude/projects
    # y tarda segundos cuando hay cientos de runs, asi que un timeout corto da falsos
    # negativos ("el puerto lo tiene otro proceso" sobre nuestro propio server).
    # /api/ping es O(1) y devuelve una firma.
    try {
        $r = Invoke-WebRequest "$probe/api/ping" -UseBasicParsing -TimeoutSec 5
        if ($r.Content -like '*workflow-monitor*') { return $true }
    } catch {}
    # Fallback: instancia vieja levantada antes de que /api/ping existiera.
    try {
        $r = Invoke-WebRequest "$probe/api/runs" -UseBasicParsing -TimeoutSec 20
        return ($r.StatusCode -eq 200)
    } catch {
        return $false
    }
}

function Stop-Monitor {
    # SOLO mata si quien escucha es NUESTRO monitor (firma de /api/ping) -- igual que el
    # launcher .sh. Antes mataba al dueno del puerto sin verificar: si otro proceso habia
    # tomado el 8787, -Stop lo bajaba igual.
    # Devuelve: 'bajado' | 'nada' | 'ajeno' | 'error'
    $l = Get-Listener
    if (-not $l) { return 'nada' }
    if (-not (Test-Monitor)) { return 'ajeno' }
    try {
        Stop-Process -Id $l.OwningProcess -Force -ErrorAction Stop
        Start-Sleep -Milliseconds 500
        return 'bajado'
    } catch {
        $host.UI.WriteErrorLine("No pude matar el PID $($l.OwningProcess): $($_.Exception.Message)")
        return 'error'
    }
}

function Find-Python {
    foreach ($name in @("python", "py")) {
        $c = Get-Command $name -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
    }
    return $null
}

function Find-Exe {
    # Build standalone de PyInstaller (ver build-exe.ps1). Si existe lo preferimos:
    # no necesita Python, asi que el launcher funciona en maquinas que no lo tienen.
    foreach ($p in @(
        (Join-Path (Split-Path -Parent $here) "dist\WorkflowMonitor.exe"),
        (Join-Path $here "WorkflowMonitor.exe")
    )) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Find-Chrome {
    $cands = @(
        (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
    )
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
    try {
        $reg = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -ErrorAction Stop).'(default)'
        if ($reg -and (Test-Path $reg)) { return $reg }
    } catch {}
    return $null
}

$exe = Find-Exe
if (-not $exe -and -not (Test-Path $serverPy)) {
    $host.UI.WriteErrorLine("No encuentro ni el exe (dist\WorkflowMonitor.exe) ni server.py junto a este script.")
    exit 1
}

if ($Stop) {
    switch (Stop-Monitor) {
        'bajado' { Write-Host "Monitor detenido (puerto $Port liberado)."; exit 0 }
        'nada'   { Write-Host "No habia nada escuchando en el puerto $Port."; exit 0 }
        'ajeno'  { $host.UI.WriteErrorLine("El puerto $Port lo tiene OTRO proceso (no es el monitor): no lo toco."); exit 1 }
        default  { exit 1 }
    }
}

if ($Restart) {
    switch (Stop-Monitor) {
        'bajado' { Write-Host "Server anterior detenido." }
        'nada'   { }
        'ajeno'  {
            $host.UI.WriteErrorLine("El puerto $Port lo tiene OTRO proceso (no es el monitor): no lo mato. Usa -Port para otro puerto.")
            exit 1
        }
        default  { exit 1 }
    }
}

# --- 1. Server: reusar el que este arriba, o levantar uno ---
$yaEstaba = $false
$listener = Get-Listener
if ($listener) {
    if (Test-Monitor) {
        $yaEstaba = $true
        Write-Host "El monitor ya estaba corriendo (PID $($listener.OwningProcess)) -- reuso esa instancia."
    } else {
        $nombre = "?"
        try { $nombre = (Get-Process -Id $listener.OwningProcess -ErrorAction Stop).ProcessName } catch {}
        $host.UI.WriteErrorLine("El puerto $Port lo tiene ocupado OTRO proceso: PID $($listener.OwningProcess) ($nombre).")
        $host.UI.WriteErrorLine("Levanta el monitor en otro puerto (-Port 8788) o cerra ese proceso.")
        exit 1
    }
}

if (-not $yaEstaba) {
    # Preferimos el exe standalone; si no esta, python + server.py.
    if ($exe) {
        Start-Process -FilePath $exe -ArgumentList "$Port" -WindowStyle Minimized
        $comoArranco = "exe"
        $aMano = "`"$exe`" $Port"
    } else {
        $python = Find-Python
        if (-not $python) {
            $host.UI.WriteErrorLine("No encuentro python en el PATH, y tampoco hay exe compilado.")
            $host.UI.WriteErrorLine("Instala Python, o compila el exe con: powershell -File `"$here\build-exe.ps1`"")
            exit 1
        }
        # server.py usa removeprefix/removesuffix (Python 3.9+): chequear aca da un error
        # claro en vez de un server que crashea al primer request. Mismo chequeo que el .sh.
        & $python -c "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)"
        if ($LASTEXITCODE -ne 0) {
            $host.UI.WriteErrorLine("Necesito Python 3.9 o superior (encontre: $(& $python -V 2>&1)).")
            exit 1
        }
        Start-Process -FilePath $python -ArgumentList @("`"$serverPy`"", "$Port") -WindowStyle Minimized
        $comoArranco = "python"
        $aMano = "python `"$serverPy`" $Port"
    }

    $ok = $false
    foreach ($i in 1..20) {
        if (Test-Monitor) { $ok = $true; break }
        Start-Sleep -Milliseconds 400
    }
    if (-not $ok) {
        $host.UI.WriteErrorLine("El server no respondio en $base despues de ~8s.")
        $host.UI.WriteErrorLine("Proba a mano para ver el error: $aMano")
        exit 1
    }
    Write-Host "Monitor levantado en $base ($comoArranco)"
}

# --- 2. Cuantos runs ve (sanity check, no es critico) ---
try {
    # Timeout generoso a proposito: este endpoint escanea el disco y con cientos de runs
    # tarda varios segundos. Si falla no es critico, solo nos perdemos el conteo.
    $runs = (Invoke-WebRequest "$probe/api/runs" -UseBasicParsing -TimeoutSec 30).Content | ConvertFrom-Json
    $activos = @($runs | Where-Object { $_.estado -eq "ACTIVO" }).Count
    Write-Host ("Runs visibles: {0} (activos ahora: {1})" -f @($runs).Count, $activos)
} catch {
    Write-Host "El server responde pero /api/runs fallo: $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- 3. Ventana de Chrome ---
if ($NoBrowser) {
    Write-Host "(-NoBrowser: no abro navegador). Dashboard en $base"
    exit 0
}

$chrome = Find-Chrome
if ($chrome) {
    # --app: ventana dedicada, sin barra de direcciones ni pestanas -- se comporta como app.
    Start-Process -FilePath $chrome -ArgumentList "--app=$base"
    Write-Host "Ventana de Chrome abierta en $base"
} else {
    Write-Host "No encontre chrome.exe -- abro con el navegador por defecto." -ForegroundColor Yellow
    Start-Process $base
}
exit 0
