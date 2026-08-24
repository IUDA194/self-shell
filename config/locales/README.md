# Locales

`ru.json` is the fallback locale. To add a language, copy it to `<code>.json`,
translate values without changing keys, and set `SELF_SHELL_LANG=<code>`.

Placeholders such as `{0}` must be preserved. The locale is selected from
`SELF_SHELL_LANG`, then `LC_ALL`, `LC_MESSAGES`, and `LANG`.
