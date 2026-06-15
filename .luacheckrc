-- Luacheck configuration for MDW (Mudlet Dockable Widgets).
-- Mudlet runs Lua 5.1 / LuaJIT and injects a large global API surface,
-- so the bulk of this file whitelists the Mudlet functions the package uses.

std = "lua51+luajit"

-- Matches the /code-review column_limit. Note: CLAUDE.md prefers <100 as a
-- soft target; 150 is the hard ceiling the linter enforces.
max_line_length = 150

-- The package's single namespace table is written to across every file.
globals = {
  "mdw",
}

-- Mudlet API used by the package (read-only globals). Mudlet also extends the
-- standard `table` and `io` libraries with helpers, declared via fields.
read_globals = {
  "calcFontSize",
  "cecho",
  "copy2decho",
  "debugc",
  "deleteLabel",
  "deleteLine",
  "deleteNamedEventHandler",
  "deselect",
  "Geyser",
  "getMainWindowSize",
  "getMudletHomeDir",
  "mudlet",
  "raiseEvent",
  "registerNamedEventHandler",
  "selectCurrentLine",
  "setBgColor",
  "setBorderBottom",
  "setBorderLeft",
  "setBorderRight",
  "setBorderTop",
  "setFgColor",
  "setFontSize",
  "setLabelClickCallback",
  "setLabelMoveCallback",
  "setLabelOnEnter",
  "setLabelOnLeave",
  "setLabelReleaseCallback",
  "tempTimer",
  io = { fields = { "exists" } },
  table = { fields = { "save", "load" } },
}

ignore = {
  "212", -- Unused argument (project convention: prefix with _ when intentional)
}

-- Test specs (if/when added) run under busted.
files["spec/**/*.lua"] = {
  std = "+busted",
}
