# WWF4P Kaillera server

Kaillera-сервер для WWF WrestleMania на четверых (WWF4P): EmuLinker-K, коммит `214fe81`, с патчем **holefix**.
Патч устраняет найденную причину рассинхронов и вылетов клиента n02: сервер всегда шлёт пачки по 9 сообщений.

## Одно меню для всего

На арендованном сервере (от root) достаточно одной команды:

```bash
curl -fsSL https://raw.githubusercontent.com/barsik007/wwf4p/main/wwf4p.sh | bash
```

Откроется меню: установить или обновить Kaillera-сервер, установить Mednafen-сервер, собрать журналы, показать состояние и адрес для игроков, перезапустить серверы, посмотреть журналы служб. Порт, название и пароль скрипт спросит сам; Enter оставляет значение по умолчанию. После первого запуска меню открывается командой `wwf4p`. Пункт можно выбрать сразу, без меню: `... | bash -s -- 1`.

Отдельные команды ниже по-прежнему работают.

## Установка одной командой

На чистом VPS с Ubuntu 22.04/24.04 или Debian 12/13, от root:

```bash
curl -fsSL https://raw.githubusercontent.com/barsik007/wwf4p/main/install.sh | bash
```

Через 2–5 минут скрипт напишет адрес вида `IP:27888`. Игроки вводят его в Kaillera → **Custom IP**.

Что делает скрипт:
- ставит Java 17;
- скачивает готовый jar из папки `bin/` этого репозитория и проверяет SHA-256 `67f5e638…eb86`;
- если скачать не вышло, собирает сервер из исходников EmuLinker-K с патчем `patches/emulinker-wwf4p-holefix.patch`;
- настраивает службу systemd `wwf4p-kaillera` (автозапуск, перезапуск при сбое);
- открывает UDP 27888 в ufw/firewalld и проверяет готовность сервера.

Повторный запуск безопасен.

Опции передаются после `bash -s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/barsik007/wwf4p/main/install.sh | bash -s -- --port 27888 --name "WWF4P" --max-users 16
curl -fsSL https://raw.githubusercontent.com/barsik007/wwf4p/main/install.sh | bash -s -- --build   # только сборка из исходников
```

## Сервер Mednafen (отдельно)

Сервер сетевой игры Mednafen (`mednafen-server` 0.5.2, порт TCP 4046) одной командой:

```bash
curl -fsSL https://raw.githubusercontent.com/barsik007/wwf4p/main/install-mednafen.sh | bash
```

Скрипт собирает сервер из официального архива mednafen.github.io, настраивает службу `mednafen-server` с автозапуском и открывает порт. В Mednafen подключение: `/server IP 4046`. Опции: `bash -s -- --port 4046 --max-clients 32 --password СЕКРЕТ`. Журналы собирает та же команда `wwf4p-logs`.

## Журналы после игры

```bash
wwf4p-logs
```

Команда соберёт журналы сервера, журнал службы и сетевую статистику в `/root/wwf4p-logs-<дата>.tar.gz`. Архив заберите через WinSCP до удаления сервера. На сервере, установленном до появления этой команды:

```bash
curl -fsSL https://raw.githubusercontent.com/barsik007/wwf4p/main/collect-logs.sh | bash
```

## Управление

```bash
systemctl status wwf4p-kaillera --no-pager   # состояние
journalctl -u wwf4p-kaillera -f              # журнал в реальном времени
cat /opt/wwf4p-kaillera/emulinker.log        # журнал сервера: присылать при сбоях
```

Если игроки не подключаются, откройте **UDP 27888** в панели хостинга (Firewall / Security group).

Почасовую аренду после игры **удаляйте** в панели хостинга. Выключенный сервер тоже оплачивается.

## Лицензия

EmuLinker-K распространяется по GPL-2.0. Исходники: https://github.com/hopskipnfall/EmuLinker-K, коммит
`214fe81b3e1d52916933264c4bcdb41db87c9988`, плюс патч из `patches/`. Jar в `bin/` собран из них без других изменений.
