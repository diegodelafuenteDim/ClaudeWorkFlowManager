# monitor-workflow.ps1 - monitor en vivo de workflows/subagentes de Claude Code leyendo su estado en disco.
# (archivo ASCII puro: PowerShell 5.1 rompe con UTF-8 sin BOM)
# Uso:
#   powershell -File monitor-workflow.ps1                  # autodetecta el run mas reciente, refresca cada 3s
#   powershell -File monitor-workflow.ps1 -Once            # un snapshot y sale
#   powershell -File monitor-workflow.ps1 -RunDir <path>   # apuntar a un wf_* especifico
# Estado en disco:
#   ~\.claude\projects\<proyecto>\<sesion>\subagents\workflows\<wf_runId>\
#     journal.jsonl        -> {"type":"started"|"result", "agentId":...} (result = agente terminado, con su retorno)
#     agent-<id>.jsonl     -> transcript del agente, una linea JSON por evento (crece = esta vivo)
#   powershell -File monitor-workflow.ps1 -Detail a4fbf981   # ultimos eventos de UN agente (prefijo del id) y sale
#   powershell -File monitor-workflow.ps1 -Follow a4fbf981   # sigue a UN agente en vivo (Ctrl+C para salir)
#   powershell -File monitor-workflow.ps1 -List              # runs de TODAS las conversaciones/proyectos
#   powershell -File monitor-workflow.ps1 -Run af60b0ed      # elegir run por prefijo del wf_id (combinable con -Detail/-Follow)
param(
    [string]$RunDir,
    [switch]$Once,
    [int]$IntervalSec = 3,
    [string]$Detail,
    [string]$Follow,
    [switch]$List,
    [string]$Run
)

function Get-LatestRunDir {
    Get-ChildItem "$env:USERPROFILE\.claude\projects\*\*\subagents\workflows\wf_*" -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}

function Get-Mision([string]$file) {
    # La mision viene en el prompt (primera linea "user"): "SOS EL RELEVADOR DEL FORM", etc.
    try {
        $head = Get-Content $file -TotalCount 3 -ErrorAction Stop
        foreach ($l in $head) {
            if ($l -cmatch 'SOS (EL |LA )?([A-Z][A-Z ]{3,50})') { return $Matches[2].Trim() }
        }
        # Fallback: primeros caracteres del prompt (workflows con otra convencion)
        foreach ($l in $head) {
            if ($l -match '"content":"((?:[^"\\]|\\.){10,60})') {
                return (($Matches[1] -replace '\\n', ' ').Substring(0, [Math]::Min(45, $Matches[1].Length)))
            }
        }
    } catch {}
    return "?"
}

function Get-ActividadActual([string]$file) {
    # Ultima tool call del transcript, sin parsear JSON completo (las lineas pueden ser enormes).
    try {
        $tail = Get-Content $file -Tail 6 -ErrorAction Stop
        for ($i = $tail.Count - 1; $i -ge 0; $i--) {
            $l = $tail[$i]
            if ($l -match '"type":"tool_use".{0,200}?"name":"([^"]+)"') {
                $tool = $Matches[1]
                $hint = ""
                if ($l -match '"(file_path|pattern|sql|tableName|command)":"((?:[^"\\]|\\.){5,90})') {
                    $hint = ($Matches[2] -replace '\\\\', '\') -replace '^.*\\', ''
                }
                return ("$tool $hint").Trim()
            }
            if ($l -match '"type":"text"') { return "(redactando)" }
        }
    } catch {}
    return "?"
}

function Format-Evento([string]$l) {
    # Convierte una linea JSONL del transcript en una linea legible. Sin ConvertFrom-Json
    # (las lineas con tool_result pueden pesar cientos de KB) -- regex sobre el texto crudo.
    $ts = ""
    if ($l -match '"timestamp":"[^"]*T([0-9:]{8})') { $ts = $Matches[1] }

    if ($l -match '"type":"assistant"') {
        $tools = [regex]::Matches($l, '"type":"tool_use".{0,200}?"name":"([^"]+)"')
        if ($tools.Count -gt 0) {
            $desc = foreach ($t in $tools) { $t.Groups[1].Value }
            $hint = ""
            if ($l -match '"(file_path|pattern|sql|tableName|procedureName|command)":"((?:[^"\\]|\\.){5,120})') {
                $hint = " -> " + (($Matches[2] -replace '\\\\', '\') -replace '\\n', ' ')
            }
            return "$ts  TOOL  $($desc -join ', ')$hint"
        }
        if ($l -match '"type":"text","text":"((?:[^"\\]|\\.){1,180})') {
            $txt = $Matches[1] -replace '\\n', ' '
            return "$ts  DICE  $txt..."
        }
        return "$ts  (assistant)"
    }
    if ($l -match '"type":"user"' -and $l -match '"type":"tool_result"') {
        return ("$ts  <-    resultado ({0} KB)" -f [int]($l.Length / 1kb))
    }
    return $null
}

function Resolve-AgentFile([string]$runDir, [string]$prefix) {
    $f = Get-ChildItem "$runDir\agent-$prefix*.jsonl" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $f) { Write-Host "No hay agente con prefijo '$prefix' en $runDir"; exit 1 }
    return $f
}

function Get-AllRunDirs {
    Get-ChildItem "$env:USERPROFILE\.claude\projects\*\*\subagents\workflows\wf_*" -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
}

function Get-WorkflowName([System.IO.DirectoryInfo]$runDirInfo) {
    # El script del workflow vive en <sesion>\workflows\scripts\<nombre>-<wf_id>.js
    $sessionDir = $runDirInfo.Parent.Parent.Parent.FullName
    $leaf = $runDirInfo.Name
    $script = Get-ChildItem "$sessionDir\workflows\scripts\*$leaf.js" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($script) { return ($script.BaseName -replace "-$leaf$", '') }
    return "?"
}

if ($List) {
    $filas = foreach ($d in Get-AllRunDirs) {
        $terminados = 0
        $j = Join-Path $d.FullName "journal.jsonl"
        if (Test-Path $j) { $terminados = @(Select-String -Path $j -Pattern '"type":"result"' -ErrorAction SilentlyContinue).Count }
        $wfName = Get-WorkflowName $d
        if ($wfName.Length -gt 38) { $wfName = $wfName.Substring(0, 38) }
        [pscustomobject]@{
            Run       = $d.Name
            UltimaAct = $d.LastWriteTime.ToString("dd/MM HH:mm")
            Ag        = @(Get-ChildItem "$($d.FullName)\agent-*.jsonl" -ErrorAction SilentlyContinue).Count
            Listos    = $terminados
            Proyecto  = ($d.Parent.Parent.Parent.Parent.Name -replace '^[Cc]--Net-8-', '')
            Sesion    = $d.Parent.Parent.Parent.Name.Substring(0, 8)
            Workflow  = $wfName
        }
    }
    $filas | Format-Table -AutoSize
    Write-Host "Elegi un run con: -Run <prefijo del wf_id>  (agrega -Detail/-Follow/-Once segun necesites)"
    exit 0
}

if ($Run) {
    $match = Get-AllRunDirs | Where-Object { $_.Name -like "wf_$($Run -replace '^wf_', '')*" } | Select-Object -First 1
    if (-not $match) { Write-Host "No hay run que empiece con '$Run'. Proba -List."; exit 1 }
    $RunDir = $match.FullName
}

if (-not $RunDir) { $RunDir = Get-LatestRunDir }
if (-not $RunDir -or -not (Test-Path $RunDir)) { Write-Host "No se encontro ningun run de workflow."; exit 1 }

if ($Detail) {
    $f = Resolve-AgentFile $RunDir $Detail
    Write-Host ("AGENTE {0} - {1}" -f $f.BaseName, (Get-Mision $f.FullName)) -ForegroundColor Cyan
    Get-Content $f.FullName -Tail 40 | ForEach-Object { $e = Format-Evento $_; if ($e) { Write-Host $e } }
    exit 0
}

if ($Follow) {
    $f = Resolve-AgentFile $RunDir $Follow
    Write-Host ("SIGUIENDO {0} - {1}  (Ctrl+C para salir)" -f $f.BaseName, (Get-Mision $f.FullName)) -ForegroundColor Cyan
    Get-Content $f.FullName -Wait -Tail 10 | ForEach-Object { $e = Format-Evento $_; if ($e) { Write-Host $e } }
    exit 0
}

do {
    if (-not $Once) { Clear-Host }
    $journal = Join-Path $RunDir "journal.jsonl"
    $terminados = @{}
    $arrancados = 0
    if (Test-Path $journal) {
        foreach ($l in Get-Content $journal) {
            if ($l -match '"type":"started"') { $arrancados++ }
            if ($l -match '"type":"result"' -and $l -match '"agentId":"([a-f0-9]+)"') { $terminados[$Matches[1]] = $true }
        }
    }

    Write-Host ("RUN: {0}   {1:HH:mm:ss}" -f (Split-Path $RunDir -Leaf), (Get-Date)) -ForegroundColor Cyan
    Write-Host ("journal: {0} arranques, {1} terminados" -f $arrancados, $terminados.Count)
    Write-Host ""

    $filas = foreach ($f in (Get-ChildItem "$RunDir\agent-*.jsonl" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        $id = $f.BaseName -replace '^agent-', ''
        $edadSeg = [int]((Get-Date) - $f.LastWriteTime).TotalSeconds
        $estado = if ($terminados[$id]) { "TERMINADO" }
                  elseif ($edadSeg -lt 30) { "ACTIVO" }
                  elseif ($edadSeg -lt 180) { "lento ($edadSeg s)" }
                  else { "viejo/caido ($edadSeg s)" }
        [pscustomobject]@{
            Agente    = $id.Substring(0, 8)
            Estado    = $estado
            KB        = [int]($f.Length / 1kb)
            Mision    = Get-Mision $f.FullName
            Actividad = if ($terminados[$id]) { "-" } else { Get-ActividadActual $f.FullName }
        }
    }
    $filas | Format-Table -AutoSize

    if (-not $Once) { Start-Sleep -Seconds $IntervalSec }
} while (-not $Once)
