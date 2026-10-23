#!/usr/bin/env bash
# Сервер сетевой игры Mednafen (mednafen-server) на VPS с Linux - одной командой (от root):
#     curl -fsSL https://raw.githubusercontent.com/barsik007/wwf4p/main/install-mednafen.sh | bash
# Опции (после  bash -s -- ):  --port 4046  --password СЕКРЕТ  --max-clients 32  --version 0.5.2
# Подходит для Ubuntu 22.04/24.04 и Debian 12/13. Повторный запуск безопасен.
set -euo pipefail
PORT=4046; PASSWORD=""; MAXCLIENTS=32; VER=0.5.2
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; shift 2;;
    --password) PASSWORD="$2"; shift 2;;
    --max-clients) MAXCLIENTS="$2"; shift 2;;
    --version) VER="$2"; shift 2;;
    *) echo "Неизвестная опция: $1"; exit 1;;
  esac
done
[ "$(id -u)" = 0 ] || { echo "Запустите от root"; exit 1; }
DIR=/opt/mednafen-server; SVC=mednafen-server; USR=mednafen; REPO=barsik007/wwf4p
say(){ echo; echo "=== $*"; }

say "1/5 Пакеты для сборки"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q build-essential curl ca-certificates xz-utils

say "2/5 Сборка mednafen-server $VER"
BUILD=/opt/mednafen-server-build; rm -rf "$BUILD"; mkdir -p "$BUILD"; cd "$BUILD"
curl -fL --retry 3 -o server.tar.xz "https://mednafen.github.io/releases/files/mednafen-server-$VER.tar.xz"
tar xJf server.tar.xz
# Папка с исходниками - та, где лежит configure (найти по файлу, а не по имени папки:
# имя самой папки сборки тоже начинается с mednafen-server).
CONF=$(find "$BUILD" -mindepth 2 -maxdepth 3 -type f -name configure | head -1)
[ -n "$CONF" ] || { echo "В архиве нет configure:"; find "$BUILD" -maxdepth 3 | head -30; exit 1; }
SRC=$(dirname "$CONF"); cd "$SRC"; echo "Исходники: $SRC"
sh ./configure -q >/dev/null
make -s -j"$(nproc)"
[ -x src/mednafen-server ] || { echo "Сборка не дала src/mednafen-server"; exit 1; }

say "3/5 Установка в $DIR"
id "$USR" >/dev/null 2>&1 || useradd --system --home "$DIR" --shell /usr/sbin/nologin "$USR"
mkdir -p "$DIR"
install -m 755 src/mednafen-server "$DIR/mednafen-server"
CFG="$DIR/standard.conf"
[ -f "$CFG" ] || cp standard.conf "$CFG"
setcfg(){ # "ключ значение" в стиле standard.conf; ключ меняется, только если уже есть в файле
  if grep -qE "^[;#]?[[:space:]]*$1([[:space:]]|$)" "$CFG"; then sed -i -E "s|^[;#]?[[:space:]]*$1([[:space:]].*)?$|$1 $2|" "$CFG"; else echo "$1 $2" >> "$CFG"; fi; }
setcfg port "$PORT"
setcfg maxclients "$MAXCLIENTS"
if [ -n "$PASSWORD" ]; then setcfg password "$PASSWORD"; else sed -i -E 's|^password([[:space:]].*)?$|;password|' "$CFG"; fi
chown -R "$USR:$USR" "$DIR"
echo "Настройки ($CFG):"; grep -vE '^[[:space:]]*(;|#|$)' "$CFG" | sed 's/^password .*/password ******/'

say "4/5 Служба systemd ($SVC)"
cat > /etc/systemd/system/$SVC.service <<UNIT
[Unit]
Description=Mednafen netplay server $VER
After=network-online.target
Wants=network-online.target

[Service]
User=$USR
WorkingDirectory=$DIR
ExecStart=$DIR/mednafen-server $DIR/standard.conf
Restart=on-failure
RestartSec=5
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload; systemctl enable -q $SVC; systemctl restart $SVC
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then ufw allow "$PORT/tcp" >/dev/null && echo "ufw: открыт $PORT/tcp"
elif command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then firewall-cmd -q --permanent --add-port="$PORT/tcp" && firewall-cmd -q --reload && echo "firewalld: открыт $PORT/tcp"
else echo "Локальный брандмауэр не включён - ничего не меняю."; fi
curl -fsSL "https://raw.githubusercontent.com/$REPO/main/collect-logs.sh" -o /usr/local/bin/wwf4p-logs && chmod 755 /usr/local/bin/wwf4p-logs || true

say "5/5 Проверка"
OK=0; for i in $(seq 1 15); do ss -ltn | grep -q ":$PORT " && { OK=1; break; }; sleep 1; done
journalctl -u $SVC -n 8 --no-pager -q || true
IP=$(curl -fsS4 --max-time 5 https://api.ipify.org || hostname -I | awk '{print $1}')
echo
[ "$OK" = 1 ] || { echo "Сервер не слушает порт $PORT. Смотрите: journalctl -u $SVC -n 50"; exit 1; }
echo "ГОТОВО. Mednafen-сервер работает:  $IP  порт $PORT (TCP)"
echo "В Mednafen:  /server $IP $PORT   (в окне сетевой игры, клавиша T), затем /nick, /game, /join."
[ -n "$PASSWORD" ] && echo "Пароль сервера задан - игрокам нужна настройка netplay.password."
echo "Если не подключаются - откройте TCP $PORT в панели хостинга. Журналы: wwf4p-logs"
