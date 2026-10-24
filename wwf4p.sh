#!/usr/bin/env bash
# WWF4P: одно меню для арендованного сервера (от root):
#     curl -fsSL https://raw.githubusercontent.com/barsik007/wwf4p/main/wwf4p.sh | bash
# После первого запуска меню доступно командой:  wwf4p
# Без меню (например, из другого скрипта):  ... | bash -s -- 1      (номер пункта)
# Пункты меню запускают те же скрипты репозитория: install.sh, install-mednafen.sh, collect-logs.sh.
set -uo pipefail

REPO=barsik007/wwf4p
BASE="${WWF4P_BASE:-https://raw.githubusercontent.com/$REPO/main}"
K_SVC=wwf4p-kaillera; M_SVC=mednafen-server
K_CFG=/opt/wwf4p-kaillera/conf/emulinker.cfg; M_CFG=/opt/mednafen-server/standard.conf

[ "$(id -u)" = 0 ] || { echo "Запустите от root:  sudo bash  (или войдите как root)"; exit 1; }

# При запуске через  curl | bash  стандартный ввод занят самим скриптом - вопросы читаем с терминала.
TTY=/dev/tty
if ! { : < "$TTY"; } 2>/dev/null; then TTY=""; fi
ask(){ # ask "Вопрос" "по умолчанию" -> ответ в $REPLY
  local q="$1" def="${2:-}"
  if [ -z "$TTY" ]; then REPLY="$def"; return; fi
  if [ -n "$def" ]; then printf '%s [%s]: ' "$q" "$def" > "$TTY"; else printf '%s: ' "$q" > "$TTY"; fi
  IFS= read -r REPLY < "$TTY" || REPLY=""
  [ -n "$REPLY" ] || REPLY="$def"
}
pause(){ [ -z "$TTY" ] || { printf '\nНажмите Enter, чтобы вернуться в меню...' > "$TTY"; read -r _ < "$TTY" || true; }; }

# Скачать скрипт репозитория и запустить с параметрами (свежая версия при каждом запуске).
run_repo(){ # run_repo install.sh [опции...]
  local name="$1"; shift
  local tmp; tmp=$(mktemp /tmp/wwf4p-XXXXXX.sh)
  if ! curl -fsSL --retry 3 "$BASE/$name" -o "$tmp"; then echo "Не удалось скачать $BASE/$name"; rm -f "$tmp"; return 1; fi
  bash "$tmp" "$@" < /dev/null; local rc=$?
  rm -f "$tmp"; return $rc
}

ip4(){ curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}'; }
cfgval(){ grep -E "^$2=" "$1" 2>/dev/null | head -1 | cut -d= -f2-; }
svc_state(){ if systemctl list-unit-files "$1.service" 2>/dev/null | grep -q "^$1"; then systemctl is-active "$1" 2>/dev/null; else echo "не установлен"; fi; }

status(){
  local ip; ip=$(ip4)
  echo
  echo "=== Состояние сервера ($(hostname), IP $ip)"
  local ks; ks=$(svc_state $K_SVC)
  echo "Kaillera (WWF4P):  $ks"
  if [ "$ks" != "не установлен" ]; then
    local kp; kp=$(cfgval "$K_CFG" controllers.connect.port); kp=${kp:-27888}
    echo "   игрокам: Kaillera -> Custom IP -> $ip:$kp   (UDP $kp)"
    ss -uan 2>/dev/null | grep -q ":$kp " && echo "   порт UDP $kp слушается" || echo "   ВНИМАНИЕ: порт UDP $kp не слушается"
  fi
  local ms; ms=$(svc_state $M_SVC)
  echo "Mednafen:          $ms"
  if [ "$ms" != "не установлен" ]; then
    local mp; mp=$(awk '$1=="port"{print $2}' "$M_CFG" 2>/dev/null | head -1); mp=${mp:-4046}
    echo "   игрокам: /server $ip $mp   (TCP $mp)"
  fi
  echo "Память: $(free -m | awk '/Mem:/{print $3" из "$2" МБ занято"}');  нагрузка: $(cut -d' ' -f1-3 /proc/loadavg)"
  ls /root/wwf4p-logs-*.tar.gz >/dev/null 2>&1 && { echo "Архивы журналов в /root:"; ls -1sh /root/wwf4p-logs-*.tar.gz | tail -5; }
}

do_kaillera(){
  local cur; cur=$(cfgval "$K_CFG" controllers.connect.port)
  ask "Порт Kaillera (UDP)" "${cur:-27888}"; local port="$REPLY"
  case "$port" in ''|*[!0-9]*) echo "Порт должен быть числом"; return 1;; esac
  local curname; curname=$(cfgval "$K_CFG" masterList.serverName)
  ask "Название сервера" "${curname:-WWF4P private}"; local name="$REPLY"
  run_repo install.sh --port "$port" --name "$name"
}
do_mednafen(){
  local cur; cur=$(awk '$1=="port"{print $2}' "$M_CFG" 2>/dev/null | head -1)
  ask "Порт Mednafen (TCP)" "${cur:-4046}"; local port="$REPLY"
  case "$port" in ''|*[!0-9]*) echo "Порт должен быть числом"; return 1;; esac
  ask "Пароль сервера (Enter - без пароля)" ""; local pw="$REPLY"
  if [ -n "$pw" ]; then run_repo install-mednafen.sh --port "$port" --password "$pw"; else run_repo install-mednafen.sh --port "$port"; fi
}
do_restart(){
  local any=0
  for s in $K_SVC $M_SVC; do
    if [ "$(svc_state $s)" != "не установлен" ]; then systemctl restart $s && echo "Перезапущен: $s"; any=1; fi
  done
  [ $any = 1 ] || echo "Ни один сервер не установлен."
}
do_journal(){
  for s in $K_SVC $M_SVC; do
    [ "$(svc_state $s)" = "не установлен" ] || { echo; echo "=== $s: последние 30 строк"; journalctl -u $s -n 30 --no-pager -q; }
  done
}
do_self(){ # поставить/обновить команду wwf4p
  curl -fsSL --retry 3 "$BASE/wwf4p.sh" -o /usr/local/bin/wwf4p.new && chmod 755 /usr/local/bin/wwf4p.new \
    && mv -f /usr/local/bin/wwf4p.new /usr/local/bin/wwf4p && echo "Команда меню: wwf4p" || rm -f /usr/local/bin/wwf4p.new
}

action(){
  case "$1" in
    1) do_kaillera ;;
    2) do_mednafen ;;
    3) run_repo collect-logs.sh; echo "Забрать архив: WinSCP -> папка /root" ;;
    4) status ;;
    5) do_restart ;;
    6) do_journal ;;
    *) echo "Нет такого пункта: $1"; return 1 ;;
  esac
}

[ -x /usr/local/bin/wwf4p ] || do_self >/dev/null 2>&1 || true

if [ $# -gt 0 ]; then action "$1"; exit $?; fi
if [ -z "$TTY" ]; then
  echo "Нет терминала для меню. Укажите пункт:  ... | bash -s -- 1   (1 Kaillera, 2 Mednafen, 3 журналы, 4 состояние)"
  status; exit 0
fi

while true; do
  status
  cat > "$TTY" <<'MENU'

=== WWF4P - что сделать?
  1) Установить / обновить Kaillera-сервер (WWF4P, EmuLinker-K + holefix)
  2) Установить / обновить Mednafen-сервер
  3) Собрать журналы для разбора сбоя (архив в /root)
  4) Показать состояние и адрес для игроков
  5) Перезапустить серверы
  6) Последние строки журналов служб
  0) Выход
MENU
  ask "Пункт" "0"
  case "$REPLY" in
    0|q|Q|"") echo "Меню снова:  wwf4p"; exit 0 ;;
    *) action "$REPLY"; pause ;;
  esac
done
