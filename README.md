# self-shell

Переносимое терминальное окружение: Fish + Tide, Kitty, tmux, Neovim,
Fastfetch и btop.

## Установка

```bash
git clone https://github.com/IUDA194/self-shell.git ~/self-shell
cd ~/self-shell
./install.sh
```

Установщик создаёт симлинки в домашнем каталоге. Существующие файлы не
удаляются: они перемещаются в
`~/.local/state/self-shell/backups/<дата-время>/`. Скрипт можно безопасно
запускать повторно.

Для установки без сетевого обновления Fisher и загрузки TPM:

```bash
SELF_SHELL_OFFLINE=1 ./install.sh
```

## Зависимости

Основные: `fish`, `git`, `curl`, `tmux`, `kitty`, `neovim`, `fastfetch`,
`btop`, `zoxide`, `wl-clipboard`, Nerd Font (в Kitty настроен
`JetBrainsMono Nerd Font Mono`). Для Neovim также полезны `ripgrep`, `fd`,
`lazygit`, компилятор C и языковые инструменты, которые используются в
конкретных проектах.

После первого запуска Fish установите плагины, если Fisher ещё не был
установлен:

```bash
fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source; fisher update"
```

Чтобы сделать Fish login-shell:

```bash
command -v fish | sudo tee -a /etc/shells
chsh -s "$(command -v fish)"
```

Перед добавлением строки в `/etc/shells` проверьте, что такого пути там ещё
нет.

## Обновление репозитория

Конфиги подключены симлинками, поэтому изменения внутри `~/.config/fish`,
`~/.config/kitty` и остальных каталогов сразу видны в репозитории:

```bash
cd ~/self-shell
git status
git add -A
git commit -m "update configs"
git push
```

`fish_variables`, история, кэши, логи и секреты намеренно не хранятся в Git.
Путь к картинке для `render_side_by_side.py` можно переопределить переменной
`FASTFETCH_WALLPAPER`.
