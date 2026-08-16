local palette_path = vim.fn.expand("~/.cache/self-shell/text-theme.json")
local last_mtime = 0
local uv = vim.uv or vim.loop

local function apply_text_theme(force)
  local stat = uv.fs_stat(palette_path)
  if not stat then return end
  local mtime = stat.mtime.sec
  if not force and mtime == last_mtime then return end

  local file = io.open(palette_path, "r")
  if not file then return end
  local ok, data = pcall(vim.json.decode, file:read("*a"))
  file:close()
  if not ok or type(data) ~= "table" or type(data.colors) ~= "table" then return end
  last_mtime = mtime

  local c = data.colors
  local groups = {
    Normal = { fg = c.foreground, bg = "NONE" },
    NormalNC = { fg = c.foregroundSoft, bg = "NONE" },
    Comment = { fg = c.muted, italic = true },
    Constant = { fg = c.accentHover },
    String = { fg = c.success },
    Character = { fg = c.success },
    Number = { fg = c.accentHover },
    Boolean = { fg = c.accent },
    Identifier = { fg = c.foregroundSoft },
    Function = { fg = c.accentHover, bold = true },
    Statement = { fg = c.accent },
    Keyword = { fg = c.accent, italic = true },
    Operator = { fg = c.foregroundSoft },
    Type = { fg = c.accentHover },
    Special = { fg = c.accent },
    LineNr = { fg = c.muted, bg = "NONE" },
    CursorLineNr = { fg = c.accent, bg = "NONE", bold = true },
    CursorLine = { bg = c.surface },
    Visual = { bg = c.selected },
    Search = { bg = c.selected, fg = c.foreground, bold = true },
    DiagnosticError = { fg = c.critical },
    DiagnosticWarn = { fg = c.accent },
    DiagnosticInfo = { fg = c.accentHover },
    DiagnosticHint = { fg = c.muted },
    FloatBorder = { fg = c.accent, bg = "NONE" },
    Pmenu = { fg = c.foreground, bg = c.surface },
    PmenuSel = { fg = c.foreground, bg = c.selected, bold = true },
    Directory = { fg = c.accentHover, bold = true },
    Title = { fg = c.accent, bold = true },
    TelescopeNormal = { fg = c.foreground, bg = "NONE" },
    TelescopeBorder = { fg = c.accent, bg = "NONE" },
    TelescopeTitle = { fg = c.accent, bg = "NONE", bold = true },
    TelescopePromptNormal = { fg = c.foreground, bg = "NONE" },
    TelescopePromptBorder = { fg = c.accent, bg = "NONE" },
    TelescopePromptTitle = { fg = c.accent, bg = "NONE", bold = true },
    TelescopePromptPrefix = { fg = c.accentHover, bg = "NONE" },
    TelescopeResultsNormal = { fg = c.foreground, bg = "NONE" },
    TelescopeResultsBorder = { fg = c.accent, bg = "NONE" },
    TelescopeResultsTitle = { fg = c.accent, bg = "NONE", bold = true },
    TelescopePreviewNormal = { fg = c.foreground, bg = "NONE" },
    TelescopePreviewBorder = { fg = c.accent, bg = "NONE" },
    TelescopePreviewTitle = { fg = c.accent, bg = "NONE", bold = true },
    TelescopeSelection = { fg = c.foreground, bg = c.selected, bold = true },
    TelescopeSelectionCaret = { fg = c.accent, bg = c.selected, bold = true },
    TelescopeMatching = { fg = c.accentHover, bold = true },
    TelescopeMultiSelection = { fg = c.accent, bg = "NONE", bold = true },
    TelescopeMultiIcon = { fg = c.accentHover, bg = "NONE" },
    TelescopePreviewLine = { bg = c.selected },
    TelescopePreviewMatch = { fg = c.accentHover, bold = true },
    TelescopePromptCounter = { fg = c.muted, bg = "NONE" },
    TelescopePreviewDirectory = { fg = c.accentHover, bg = "NONE", bold = true },
    TelescopeDirectoryIcon = { fg = c.accentHover, bg = "NONE" },
    NvimTreeNormal = { fg = c.foreground, bg = "NONE" },
    NvimTreeFolderIcon = { fg = c.accentHover },
    NvimTreeFolderName = { fg = c.accentHover },
    NvimTreeOpenedFolderName = { fg = c.accent, bold = true },
    NeoTreeNormal = { fg = c.foreground, bg = "NONE" },
    NeoTreeNormalNC = { fg = c.foregroundSoft, bg = "NONE" },
    NeoTreeDirectoryIcon = { fg = c.accentHover },
    NeoTreeDirectoryName = { fg = c.accentHover },
    NeoTreeCursorLine = { bg = c.selected },
    OilDir = { fg = c.accentHover, bold = true },
    OilDirIcon = { fg = c.accent },
    NoiceCmdline = { fg = c.foreground, bg = "NONE" },
    NoiceCmdlinePrompt = { fg = c.accent, bg = "NONE", bold = true },
    NoiceCmdlineIcon = { fg = c.accentHover, bg = "NONE", bold = true },
    NoiceCmdlineIconSearch = { fg = c.success, bg = "NONE", bold = true },
    NoiceCmdlinePopup = { fg = c.foreground, bg = "NONE" },
    NoiceCmdlinePopupBorder = { fg = c.accent, bg = "NONE" },
    NoiceCmdlinePopupBorderSearch = { fg = c.success, bg = "NONE" },
    NoiceCmdlinePopupTitle = { fg = c.accent, bg = "NONE", bold = true },
    NoiceConfirm = { fg = c.foreground, bg = "NONE" },
    NoiceConfirmBorder = { fg = c.accent, bg = "NONE" },
    NoicePopup = { fg = c.foreground, bg = "NONE" },
    NoicePopupBorder = { fg = c.accent, bg = "NONE" },
    NoicePopupmenu = { fg = c.foreground, bg = c.surface },
    NoicePopupmenuBorder = { fg = c.accent, bg = "NONE" },
    NoicePopupmenuMatch = { fg = c.accentHover, bold = true },
    NoicePopupmenuSelected = { fg = c.foreground, bg = c.selected, bold = true },
    NoiceMini = { fg = c.foregroundSoft, bg = "NONE" },
    NoiceCursor = { fg = c.background, bg = c.accent },
  }
  for group, opts in pairs(groups) do
    vim.api.nvim_set_hl(0, group, opts)
  end

  -- Noice creates formatter-specific groups (Cmdline, Lua, Help, Search…).
  -- Override those too, since a colorscheme may replace their inherited link.
  for _, group in ipairs(vim.fn.getcompletion("NoiceCmdline", "highlight")) do
    if group:find("PopupBorder") then
      vim.api.nvim_set_hl(0, group, { fg = group:find("Search") and c.success or c.accent, bg = "NONE" })
    elseif group:find("PopupTitle") then
      vim.api.nvim_set_hl(0, group, { fg = c.accent, bg = "NONE", bold = true })
    elseif group:find("Icon") then
      vim.api.nvim_set_hl(0, group, { fg = c.accentHover, bg = "NONE", bold = true })
    end
  end
end

vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    last_mtime = 0
    vim.schedule(apply_text_theme)
  end,
})

vim.defer_fn(apply_text_theme, 100)
local timer = uv.new_timer()
timer:start(1000, 1000, vim.schedule_wrap(function() apply_text_theme(true) end))
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    if timer then timer:stop(); timer:close() end
  end,
})
