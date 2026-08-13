# Compact left rail for Quickshell

Run it with (this stops Waybar first so the panels do not overlap):

```sh
~/.config/quickshell/start.sh
```

The bar follows the previous Waybar layout: Hyprland workspaces at the top,
time and date in the middle, and keyboard, Wi-Fi, lock, volume, and power
controls at the bottom.

Helper scripts and the Rofi theme are bundled in `scripts/` and `themes/`, so
the configuration does not depend on a separate Waybar or Hypr config tree.

To autostart it, replace the Waybar `exec-once` line in Hyprland with:

```ini
exec-once = ~/.config/quickshell/start.sh
```
