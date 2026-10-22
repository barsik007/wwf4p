#!/usr/bin/env bash
# WWF4P: развернуть пропатченный Kaillera-сервер (EmuLinker-K 214fe81 + holefix) на VPS с Linux.
# Подходит для Ubuntu 22.04/24.04 и Debian 12/13. Одна команда (от root):
#     curl -fsSL https://raw.githubusercontent.com/barsik007/wwf4p/main/install.sh | bash
# По умолчанию скачивает готовый jar из релиза репозитория (проверка SHA-256); если не вышло - собирает сам.
#     ... | bash -s -- --build          # принудительно собрать из исходников EmuLinker-K + патч
#     ... | bash -s -- --jar FILE.jar   # взять jar с диска
# Опции: --port 27888  --name "WWF4P"  --max-users 16
# Повторный запуск безопасен: обновит jar, сохранит ваши правки в conf/ (кроме тех, что задают опции).
set -euo pipefail

PORT=27888; NAME="WWF4P private"; MAXUSERS=16; JAR=""; BUILD_ONLY=0
REPO="barsik007/wwf4p"; RELEASE_TAG=holefix-214fe81
COMMIT=214fe81b3e1d52916933264c4bcdb41db87c9988
JAR_SHA_EXPECTED=67f5e638cc8de89be8c81da105f7e67417140e7b473fbd2dd6115f2fdfa1eb86   # jar, собранный на ПК
DIR=/opt/wwf4p-kaillera; SVC=wwf4p-kaillera; USR=kaillera
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --max-users) MAXUSERS="$2"; shift 2;;
    --jar) JAR="$(readlink -f "$2")"; shift 2;;
    --build) BUILD_ONLY=1; shift;;
    *) echo "Неизвестная опция: $1"; exit 1;;
  esac
done
[ "$(id -u)" = 0 ] || { echo "Запустите от root (sudo bash $0)"; exit 1; }
say(){ echo; echo "=== $*"; }

say "1/6 Пакеты (Java 17, git, curl)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q curl ca-certificates
if [ -z "$JAR" ] && [ "$BUILD_ONLY" = 0 ]; then
  URL="https://github.com/$REPO/releases/download/$RELEASE_TAG/emulinker-k-holefix-214fe81.jar"
  echo "Скачиваю готовый jar: $URL"
  if curl -fL --retry 3 -o /tmp/emulinker-k-holefix-214fe81.jar "$URL" \
     && [ "$(sha256sum /tmp/emulinker-k-holefix-214fe81.jar | cut -d' ' -f1)" = "$JAR_SHA_EXPECTED" ]; then
    JAR=/tmp/emulinker-k-holefix-214fe81.jar
  else
    echo "Готовый jar недоступен или SHA-256 не совпал - соберу из исходников."
  fi
fi
if [ -n "$JAR" ]; then PKGS="openjdk-17-jre-headless curl"; else PKGS="openjdk-17-jdk-headless git curl ca-certificates"; fi
apt-get install -y -q $PKGS
JAVA=/usr/lib/jvm/java-17-openjdk-$(dpkg --print-architecture)/bin/java
[ -x "$JAVA" ] || JAVA=$(command -v java)

BUILD=/opt/wwf4p-build
if [ -z "$JAR" ]; then
  say "2/6 Сборка EmuLinker-K $COMMIT + патч holefix (5-10 минут)"
  MEM=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
  if [ "$MEM" -lt 1900 ] && ! swapon --show | grep -q /swapfile-wwf4p; then
    echo "Памяти ${MEM} МБ - добавляю временный swap 2 ГБ для сборки"
    fallocate -l 2G /swapfile-wwf4p || dd if=/dev/zero of=/swapfile-wwf4p bs=1M count=2048
    chmod 600 /swapfile-wwf4p; mkswap /swapfile-wwf4p >/dev/null; swapon /swapfile-wwf4p
  fi
  rm -rf "$BUILD"; mkdir -p "$BUILD"; cd "$BUILD"
  git init -q src && cd src
  git remote add origin https://github.com/hopskipnfall/EmuLinker-K.git
  git fetch -q --depth 1 origin "$COMMIT" && git checkout -q FETCH_HEAD
  cat > /tmp/wwf4p-holefix.patch <<'PATCH'
diff --git a/emulinker/src/main/java/org/emulinker/kaillera/controller/v086/V086ClientHandler.kt b/emulinker/src/main/java/org/emulinker/kaillera/controller/v086/V086ClientHandler.kt
index b2797a7..86ff9e3 100644
--- a/emulinker/src/main/java/org/emulinker/kaillera/controller/v086/V086ClientHandler.kt
+++ b/emulinker/src/main/java/org/emulinker/kaillera/controller/v086/V086ClientHandler.kt
@@ -377,8 +377,10 @@ class V086ClientHandler(
     // if ((System.currentTimeMillis() - lastResend) > (user.getPing()*3))
     if (System.currentTimeMillis() - lastResend > maxPingMs) {
       // int numToSend = (3+timeoutCounter);
-      var numToSend = 3 * timeoutCounter
-      if (numToSend > V086Controller.MAX_BUNDLE_SIZE) numToSend = V086Controller.MAX_BUNDLE_SIZE
+      // WWF4P (2026-10-20): always resend the maximum bundle. A 3-message resend can be shorter
+      // than the gap of a client that lost several datagrams; the n02 client then reserves
+      // in-cache slots for the missing serials that are never filled (wrong input / crash).
+      val numToSend = V086Controller.MAX_BUNDLE_SIZE
 
       stripFromProdBinary {
         logger.atFinest().log("%s: resending last %d messages", this, numToSend)
@@ -409,7 +411,8 @@ class V086ClientHandler(
     }
   }
 
-  fun send(outMessage: V086Message, numToSend: Int = 5) {
+  // WWF4P (2026-10-20): 9 instead of 5 so every datagram covers any gap n02 accepts (< 10).
+  fun send(outMessage: V086Message, numToSend: Int = V086Controller.MAX_BUNDLE_SIZE) {
     synchronized(sendMutex) {
       outMessage.messageNumber = getAndIncrementSendMessageNumber()
       var numToSend = numToSend
PATCH
  git apply /tmp/wwf4p-holefix.patch
  grep -q "WWF4P (2026-10-20)" emulinker/src/main/java/org/emulinker/kaillera/controller/v086/V086ClientHandler.kt
  export GRADLE_OPTS="-Xmx1g"
  ./gradlew --no-daemon -q jar -PprodBuild=true
  JAR=$(ls "$BUILD"/src/emulinker/build/libs/emulinker-k-*.jar | head -1)
  RELEASE="$BUILD/src/release"
else
  say "2/6 Готовый jar: $JAR"
  SHA=$(sha256sum "$JAR" | cut -d' ' -f1)
  [ "$SHA" = "$JAR_SHA_EXPECTED" ] && echo "SHA-256 совпадает с jar из пакета WWF4P" || echo "ВНИМАНИЕ: SHA-256 $SHA не совпадает с jar из пакета ($JAR_SHA_EXPECTED)"
  RELEASE=""
fi

say "3/6 Установка в $DIR"
id "$USR" >/dev/null 2>&1 || useradd --system --home "$DIR" --shell /usr/sbin/nologin "$USR"
mkdir -p "$DIR/lib" "$DIR/conf"
install -m 644 "$JAR" "$DIR/lib/emulinker-k.jar"
if [ ! -f "$DIR/conf/emulinker.cfg" ]; then
  if [ -n "$RELEASE" ]; then
    cp "$RELEASE"/{emulinker.cfg,access.cfg,language.properties,log4j2.properties} "$DIR/conf/"
  else
    # конфиги из исходников того же коммита (нужен только curl)
    for f in emulinker.cfg access.cfg language.properties log4j2.properties; do
      curl -fsSL "https://raw.githubusercontent.com/hopskipnfall/EmuLinker-K/$COMMIT/release/$f" -o "$DIR/conf/$f"
    done
  fi
fi
CFG="$DIR/conf/emulinker.cfg"
setcfg(){ grep -q "^$1=" "$CFG" && sed -i "s|^$1=.*|$1=$2|" "$CFG" || echo "$1=$2" >> "$CFG"; }
setcfg controllers.connect.port "$PORT"
setcfg emulinker.charset Windows-1251
setcfg emulinker.language en
setcfg masterList.serverName "$NAME"
setcfg masterList.touchKaillera false
setcfg masterList.touchEmulinker false
setcfg server.maxUsers "$MAXUSERS"
setcfg server.maxGames 4
chown -R "$USR:$USR" "$DIR"

say "4/6 Служба systemd ($SVC): автозапуск и перезапуск при сбое"
cat > /etc/systemd/system/$SVC.service <<UNIT
[Unit]
Description=WWF4P Kaillera server (EmuLinker-K $COMMIT + holefix)
After=network-online.target
Wants=network-online.target

[Service]
User=$USR
WorkingDirectory=$DIR
ExecStart=$JAVA -Xms64m -Xmx256m -XX:+UseSerialGC -cp conf:lib/emulinker-k.jar org.emulinker.kaillera.pico.ServerMainKt
Restart=on-failure
RestartSec=5
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable -q $SVC
systemctl restart $SVC

say "5/6 Брандмауэр: UDP $PORT"
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then ufw allow "$PORT/udp" >/dev/null && echo "ufw: открыт $PORT/udp"
elif command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then firewall-cmd -q --permanent --add-port="$PORT/udp" && firewall-cmd -q --reload && echo "firewalld: открыт $PORT/udp"
else echo "Локальный брандмауэр не включён - ничего не меняю."; fi
if swapon --show | grep -q /swapfile-wwf4p; then swapoff /swapfile-wwf4p; rm -f /swapfile-wwf4p; fi

say "6/6 Проверка"
for i in $(seq 1 30); do
  if journalctl -u $SVC --since "-2min" --no-pager -q | grep -q "Ready to accept connections"; then OK=1; break; fi
  sleep 1
done
journalctl -u $SVC -n 8 --no-pager -q || true
IP=$(curl -fsS4 --max-time 5 https://api.ipify.org || hostname -I | awk '{print $1}')
echo
if [ "${OK:-0}" = 1 ]; then
  echo "ГОТОВО. Сервер работает. Игрокам: в Kaillera -> Custom IP ->  $IP:$PORT"
else
  echo "Сервер не сообщил о готовности. Смотрите: journalctl -u $SVC -n 50"; exit 1
fi
echo "Если не подключаются - откройте UDP $PORT в панели хостинга (Firewall / Security group)."
echo "Управление: systemctl status|restart|stop $SVC ; логи: journalctl -u $SVC -f ; файл $DIR/emulinker.log"
