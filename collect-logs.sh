#!/usr/bin/env bash
# WWF4P: собрать журналы и статистику Kaillera-сервера в один архив (для разбора сбоев).
# Запуск от root:  wwf4p-logs
#   или:  curl -fsSL https://raw.githubusercontent.com/barsik007/wwf4p/main/collect-logs.sh | bash
# Результат: /root/wwf4p-logs-<дата-время>.tar.gz — забрать через WinSCP (папка /root).
set -uo pipefail
DIR=/opt/wwf4p-kaillera; SVC=wwf4p-kaillera
STAMP=$(date +%Y%m%d-%H%M%S)
OUT=/root/wwf4p-logs-$STAMP.tar.gz
TMP=$(mktemp -d)/wwf4p-logs-$STAMP; mkdir -p "$TMP"
run(){ echo "\$ $*"; "$@" 2>&1; echo; }

# журналы сервера EmuLinker-K (включая старые части после ротации)
if [ -d "$DIR" ]; then
  find "$DIR" -maxdepth 2 \( -name '*.log' -o -name '*.log.*' -o -name '*.gz' \) -type f -exec cp --parents {} "$TMP" \; 2>/dev/null
  mkdir -p "$TMP/conf" && cp "$DIR"/conf/*.cfg "$DIR"/conf/*.properties "$TMP/conf/" 2>/dev/null
fi
# журнал службы systemd (запуски, падения, перезапуски) - за последние 7 дней
journalctl -u $SVC --no-pager --since "-7d" -o short-iso > "$TMP/journal.txt" 2>&1
# Mednafen-сервер (install-mednafen.sh), если установлен
if systemctl list-unit-files mednafen-server.service >/dev/null 2>&1 && [ -d /opt/mednafen-server ]; then
  journalctl -u mednafen-server --no-pager --since "-7d" -o short-iso > "$TMP/mednafen-journal.txt" 2>&1
  grep -vE '^password' /opt/mednafen-server/standard.conf > "$TMP/mednafen-standard.conf" 2>/dev/null
fi

# статистика сервера и сети
{
  run date -Is
  run uptime
  run hostname -I
  run systemctl status $SVC --no-pager
  run free -m
  run df -h /
  run ss -uanp
  run ss -tanp
  run cat /proc/net/snmp            # UDP: InErrors, RcvbufErrors, SndbufErrors = потери на сервере
  run ip -s link
  run sysctl net.core.rmem_max net.core.wmem_max net.core.rmem_default net.core.wmem_default
  run cat /proc/loadavg
} > "$TMP/stats.txt"

tar czf "$OUT" -C "$(dirname "$TMP")" "$(basename "$TMP")"
rm -rf "$(dirname "$TMP")"
echo "Готово: $OUT ($(du -h "$OUT" | cut -f1))"
echo "Заберите через WinSCP из папки /root и положите в D:\\MAME 0.129\\bugs"
