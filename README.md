# self-shell

Полностью переносимое окружение для Hyprland: весь Quickshell (панель,
уведомления, launcher, dashboard, clipboard, password picker и выбор обоев),
Fish + Tide, tmux, Kitty, Neovim, Fastfetch, btop и `awww`.

## Демо

[▶ Посмотреть видео](assets/demo.mp4)

## Установка одной командой

На Fedora 43/44 или новее, а также на Arch Linux:

```bash
bash -c 'set -e; if ! command -v git >/dev/null; then if command -v dnf >/dev/null; then sudo dnf install -y git; elif command -v pacman >/dev/null; then sudo pacman -S --needed --noconfirm git; else echo "Нужен Git" >&2; exit 1; fi; fi; dir="$HOME/self-shell"; if [[ -d "$dir/.git" ]]; then git -C "$dir" pull --ff-only; else git clone https://github.com/IUDA194/self-shell.git "$dir"; fi; "$dir/install.sh"'
```

Установщик по умолчанию:

- ставит системные зависимости через DNF или pacman;
- на Fedora собирает `awww` 0.12.1 из официального репозитория Codeberg;
- на Fedora 44+ устанавливает Quickshell из штатного репозитория, а на Fedora 43
  автоматически подключает рекомендованный `errornointernet/quickshell` COPR;
- устанавливает `ffmpeg-free` на Fedora для превью, OCR и мультимедиа;
- ставит `mpvpaper`, чтобы wallpaper picker работал и с видео;
- устанавливает JetBrainsMono Nerd Font, Fisher, Fish-плагины и TPM-плагины;
- создаёт Python-окружение для Google Calendar в dashboard;
- подключает все конфиги симлинками и сохраняет заменённые файлы в backup;
- делает Fish login-shell. Интерактивный Fish автоматически открывает или
  создаёт tmux-сессию `main`;
- при старте Hyprland запускает обои через `awww`, всю панель Quickshell,
  launcher, уведомления, dashboard и clipboard watcher.

После установки выберите сессию Hyprland в дисплейном менеджере и откройте
Kitty. Если сессия уже запущена, перелогиньтесь, чтобы применился новый
login-shell.

## Режимы установки

Не устанавливать системные пакеты, но подключить конфиги:

```bash
SELF_SHELL_SKIP_PACKAGES=1 ./install.sh
```

Не менять login-shell:

```bash
SELF_SHELL_SKIP_CHSH=1 ./install.sh
```

Не загружать Fisher/TPM и Python-пакеты:

```bash
SELF_SHELL_OFFLINE=1 SELF_SHELL_SKIP_PACKAGES=1 ./install.sh
```

## Что переносится

- `config/hypr` — полный Hyprland-конфиг и все дополнительные Quickshell
  экраны/backend-скрипты;
- `config/quickshell` — панель, центр и toast-уведомления, power menu и
  сетевые скрипты;
- `config/tmux` и `home/.tmux.conf` — tmux вместе с автозапуском Fish;
- `config/waypaper` и `bin/self-shell-wallpaper` — состояние выбора обоев,
  запуск `awww-daemon` и восстановление последних обоев;
- `config/nautilus/settings.ini` — вид папок и состояние окна Nautilus,
  применяемые установщиком через dconf;
- остальные каталоги в `config` — терминальное окружение целиком.

Runtime-кэш `~/.cache/awww` не переносится: он генерируется автоматически и
может занимать сотни мегабайт. В репозитории есть стартовые обои; свои файлы
можно положить в `~/Documents/Wallpapers`.

Конфиги подключаются симлинками. Изменения в `~/.config/hypr`,
`~/.config/quickshell`, `~/.config/tmux` и остальных подключённых каталогах
сразу видны в репозитории. Повторный запуск установщика безопасен.
