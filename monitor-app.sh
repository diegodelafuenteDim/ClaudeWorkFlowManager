#!/bin/sh
# Launcher del Workflow Monitor para Linux/macOS (paridad con monitor-app.cmd de Windows).
# POSIX sh a proposito: sin bashisms, corre con dash/ash/bash/zsh.
# ASCII puro, sin acentos, para viajar bien entre locales (ver CONTRIBUTING.md).
#
# Uso: ./monitor-app.sh [--port N] [--no-browser] [--restart] [--stop]
# Acepta tambien los nombres de flags del launcher de Windows (-Port, -NoBrowser, ...).

set -u

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
[ -n "$DIR" ] || { echo "No pude resolver el directorio del script." >&2; exit 1; }
PORT=8787
NOBROWSER=0
RESTART=0
STOP=0

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--port|-Port) shift; PORT=${1:-} ;;
    --port=*|-Port=*) PORT=${1#*=} ;;
    --no-browser|-NoBrowser) NOBROWSER=1 ;;
    --restart|-Restart) RESTART=1 ;;
    --stop|-Stop) STOP=1 ;;
    -h|--help)
      echo "Uso: ./monitor-app.sh [--port N] [--no-browser] [--restart] [--stop]"
      echo "  --port N       puerto del server (default 8787)"
      echo "  --no-browser   levanta solo el server, sin abrir el navegador"
      echo "  --restart      baja el monitor actual y levanta uno nuevo"
      echo "  --stop         baja el monitor"
      exit 0 ;;
    *) echo "Parametro desconocido: $1 (ver --help)" >&2; exit 1 ;;
  esac
  shift
done

# Validar el puerto ANTES de usarlo: con set -u un PORT no numerico rompe la
# aritmetica de dash, y un valor basura da diagnosticos enganosos recien a los 8s.
case "$PORT" in
  ''|*[!0-9]*) echo "Puerto invalido: '$PORT' (tiene que ser un numero)" >&2; exit 1 ;;
esac
if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  echo "Puerto fuera de rango: $PORT (1-65535)" >&2
  exit 1
fi

URL="http://127.0.0.1:$PORT"
PY=$( { command -v python3 || command -v python; } 2>/dev/null || true)

if [ -z "$PY" ] && ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  echo "OJO: sin curl, wget ni python no puedo chequear el server por HTTP; los diagnosticos de puerto no son confiables." >&2
fi

# sleep con fraccion no es POSIX estricto: si el sleep local no lo soporta, 1 s.
dormir() { sleep 0.4 2>/dev/null || sleep 1; }

# GET con lo que haya a mano: curl, wget o python.
http_get() {
  _u=$1; _t=${2:-3}
  if command -v curl >/dev/null 2>&1; then curl -fsS --max-time "$_t" "$_u" 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then wget -qO- -T "$_t" "$_u" 2>/dev/null
  elif [ -n "$PY" ]; then
    "$PY" -c 'import sys,urllib.request as u; sys.stdout.write(u.urlopen(sys.argv[1], timeout=float(sys.argv[2])).read().decode())' "$_u" "$_t" 2>/dev/null
  fi
}

# Es NUESTRO monitor el que responde en el puerto? (firma de /api/ping)
is_monitor() { http_get "$URL/api/ping" 3 | grep -q "workflow-monitor"; }

# PID del proceso escuchando en el puerto, con la herramienta que exista.
# OJO: el lsof de busybox ignora los flags y lista TODO; por eso se lo saltea
# y toda salida se valida como numerica antes de usarla.
pid_on_port() {
  _p=""
  if command -v ss >/dev/null 2>&1; then
    _p=$(ss -ltnp 2>/dev/null | grep ":$PORT " | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | head -n1)
  fi
  if [ -z "$_p" ] && command -v lsof >/dev/null 2>&1 && ! lsof -h 2>&1 | grep -qi busybox; then
    _p=$(lsof -ti "tcp:$PORT" -sTCP:LISTEN 2>/dev/null | head -n1)
  fi
  if [ -z "$_p" ] && command -v fuser >/dev/null 2>&1; then
    _p=$(fuser "$PORT/tcp" 2>/dev/null | tr -s ' \t' '\n' | grep -E '^[0-9]+$' | head -n1)
  fi
  case "$_p" in
    ''|*[!0-9]*) : ;;
    *) echo "$_p" ;;
  esac
}

stop_monitor() {
  if is_monitor; then
    _pid=$(pid_on_port)
    if [ -z "$_pid" ]; then
      echo "El monitor responde en el puerto $PORT pero no pude resolver su PID (falta lsof/ss/fuser)." >&2
      return 1
    fi
    if ! kill "$_pid" 2>/dev/null; then
      echo "No pude senalizar el proceso $_pid (permisos? lo levanto otro usuario?)." >&2
      return 1
    fi
    # Confirmar que el proceso murio (hasta ~4 s) ANTES de declarar exito:
    # un kill silenciosamente fallido o un shutdown lento no son "Monitor bajado".
    _i=0
    while [ $_i -lt 10 ] && kill -0 "$_pid" 2>/dev/null; do dormir; _i=$((_i + 1)); done
    if kill -0 "$_pid" 2>/dev/null; then
      echo "El proceso $_pid sigue vivo despues de ~4s (request larga en curso?). Reintenta, o kill -9 $_pid." >&2
      return 1
    fi
    echo "Monitor bajado (PID $_pid, puerto $PORT)."
    return 0
  fi
  echo "No hay monitor corriendo en el puerto $PORT."
  return 0
}

if [ "$STOP" = 1 ]; then stop_monitor; exit $?; fi
if [ "$RESTART" = 1 ]; then stop_monitor || exit 1; fi

if is_monitor; then
  echo "El monitor ya estaba corriendo en $URL - reuso esa instancia."
else
  _pid=$(pid_on_port)
  if [ -n "$_pid" ]; then
    _nom=$(ps -p "$_pid" -o comm= 2>/dev/null | head -n1)
    echo "El puerto $PORT lo tiene ocupado OTRO proceso: PID $_pid${_nom:+ ($_nom)}. Proba con --port $((PORT + 1))." >&2
    exit 1
  fi

  # En Windows la consola minimizada del server ES su log visible; aca el server corre
  # detachado, asi que stdout/stderr (banner con version + tracebacks de requests) van a
  # un archivo. Append a proposito: los reinicios no pisan el historial.
  LOG="${TMPDIR:-/tmp}/workflow-monitor.log"

  # Igual que en Windows: si hay un binario de PyInstaller compilado en ESTE sistema
  # operativo, usarlo; si no, python3.
  BIN="$DIR/dist/WorkflowMonitor"
  if [ -x "$BIN" ]; then
    nohup "$BIN" "$PORT" >>"$LOG" 2>&1 &
    MODO="binario"
  else
    if [ -z "$PY" ]; then
      echo "No encuentro python3 en el PATH, y tampoco hay binario compilado en dist/." >&2
      exit 1
    fi
    if ! "$PY" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null; then
      echo "Necesito Python 3.9 o superior (encontre: $("$PY" -V 2>&1))." >&2
      exit 1
    fi
    nohup "$PY" "$DIR/workflow-monitor/server.py" "$PORT" >>"$LOG" 2>&1 &
    MODO="python"
  fi

  # Polling hasta ~8 s, como el launcher de Windows.
  _i=0; _ok=0
  while [ $_i -lt 20 ]; do
    if is_monitor; then _ok=1; break; fi
    dormir; _i=$((_i + 1))
  done
  if [ "$_ok" != 1 ]; then
    echo "El server no respondio en $URL despues de ~8s." >&2
    echo "Ultimas lineas del log ($LOG):" >&2
    tail -n 20 "$LOG" >&2 2>/dev/null || true
    if [ "$MODO" = "binario" ]; then
      echo "Corre en foreground para ver el error: \"$BIN\" $PORT" >&2
    else
      echo "Corre en foreground para ver el error: \"$PY\" \"$DIR/workflow-monitor/server.py\" $PORT" >&2
    fi
    exit 1
  fi
  echo "Monitor levantado en $URL ($MODO). Log: $LOG"
fi

# Sanity no critico: cuantos runs ve.
if [ -n "$PY" ]; then
  _runs=$(http_get "$URL/api/runs" 10 | "$PY" -c 'import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d, list) else len(d.get("runs", [])))' 2>/dev/null || true)
  [ -n "${_runs:-}" ] && echo "Runs visibles: $_runs"
fi

if [ "$NOBROWSER" = 0 ]; then
  BURL="http://localhost:$PORT"
  if [ "$(uname)" = "Darwin" ] && command -v open >/dev/null 2>&1; then
    open "$BURL"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$BURL" >/dev/null 2>&1 &
  else
    echo "Abri $BURL en tu navegador (no encontre open/xdg-open)."
  fi
fi

exit 0
