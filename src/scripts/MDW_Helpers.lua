--[[
  MDW_Helpers.lua
  Runtime helper functions for MDW (Mudlet Dockable Widgets).

  Contains all utility functions, lifecycle helpers, widget class helpers,
  and style generation. Separated from MDW_Config.lua so that Config
  remains a static-only data declaration file.

  Dependencies: MDW_Config.lua must be loaded first (provides mdw table and config)
]]

---------------------------------------------------------------------------
-- STYLE GENERATION
-- Pre-built stylesheets for consistency across components.
-- Why: Centralizing styles prevents duplication and ensures visual consistency.
-- Changes to appearance only need to happen in one place.
---------------------------------------------------------------------------

--- Generate all stylesheets from current config.
-- Why: Called after config changes to regenerate styles with new values.
function mdw.buildStyles()
  local cfg = mdw.config

  mdw.styles.sidebar = string.format([[
    background-color: %s;
  ]], cfg.sidebarBackground)

  mdw.styles.splitter = string.format([[
    QLabel { background-color: %s; }
    QLabel:hover { background-color: %s; }
  ]], cfg.splitterColor, cfg.splitterHoverColor)

  mdw.styles.titleBar = string.format([[
    background-color: %s;
    qproperty-alignment: 'AlignCenter';
    font-family: '%s';
    font-size: %dpx;
  ]], cfg.headerBackground, cfg.fontFamily, cfg.fontSize)

  mdw.styles.titleBarDragging = string.format([[
    background-color: %s;
    qproperty-alignment: 'AlignCenter';
    font-family: '%s';
    font-size: %dpx;
    opacity: 0.6;
  ]], cfg.headerBackground, cfg.fontFamily, cfg.fontSize)

  mdw.styles.widgetContent = string.format([[
    background-color: %s;
    font-family: '%s';
    font-size: %dpx;
  ]], cfg.widgetBackground, cfg.fontFamily, cfg.fontSize)

  mdw.styles.widgetContentDragging = string.format([[
    background-color: %s;
    font-family: '%s';
    font-size: %dpx;
    opacity: 0.6;
  ]], cfg.widgetBackground, cfg.fontFamily, cfg.fontSize)

  mdw.styles.headerPane = string.format([[
    background-color: %s;
    font-family: '%s';
    font-size: %dpx;
  ]], cfg.sidebarBackground, cfg.fontFamily, cfg.fontSize)

  mdw.styles.promptBar = string.format([[
    background-color: %s;
    font-family: '%s';
    font-size: %dpx;
    padding-left: %dpx;
  ]], cfg.sidebarBackground, cfg.fontFamily, cfg.fontSize, cfg.contentPaddingLeft)

  mdw.styles.headerButton = string.format([[
    QLabel {
      background-color: transparent;
      font-family: '%s';
      font-size: %dpx;
      padding-left: %dpx;
      border: 2px solid transparent;
    }
    QLabel:hover {
      background-color: rgb(51,51,51);
      border: 2px solid rgb(85,85,85);
    }
  ]], cfg.fontFamily, cfg.fontSize, cfg.menuPaddingLeft)

  -- Active state for header buttons when their menu is open
  mdw.styles.headerButtonActive = string.format([[
    QLabel {
      background-color: rgb(51,51,51);
      font-family: '%s';
      font-size: %dpx;
      padding-left: %dpx;
      border: 2px solid rgb(85,85,85);
    }
  ]], cfg.fontFamily, cfg.fontSize, cfg.menuPaddingLeft)

  mdw.styles.menuItem = string.format([[
    QLabel {
      background-color: transparent;
      font-family: '%s';
      font-size: %dpx;
      padding-left: %dpx;
    }
  ]], cfg.fontFamily, cfg.fontSize, cfg.menuPaddingLeft)

  mdw.styles.menuBackground = [[
    background-color: rgb(51,51,51);
    border: 2px solid rgb(85,85,85);
  ]]

  mdw.styles.dropIndicator = string.format([[
    background-color: %s;
  ]], cfg.dropIndicatorColor)

  mdw.styles.dockHighlight = string.format([[
    background-color: rgba(106,91,58,0.4);
    outline: 2px dashed %s;
  ]], cfg.dropIndicatorColor)

  mdw.styles.separatorLine = string.format([[
    background-color: %s;
  ]], cfg.splitterColor)

  mdw.styles.resizableSeparator = string.format([[
    QLabel { background-color: %s; }
    QLabel:hover { background-color: %s; }
  ]], cfg.splitterColor, cfg.splitterHoverColor)

  mdw.styles.tabBar = string.format([[
    background-color: %s;
  ]], cfg.headerBackground)

  mdw.styles.tabActive = string.format([[
    background-color: %s;
    qproperty-alignment: 'AlignCenter';
    font-family: '%s';
    font-size: %dpx;
    padding-left: %dpx;
    padding-right: %dpx;
  ]], cfg.tabActiveBackground, cfg.fontFamily, cfg.fontSize, cfg.tabPadding, cfg.tabPadding)

  mdw.styles.tabInactive = string.format([[
    background-color: %s;
    qproperty-alignment: 'AlignCenter';
    font-family: '%s';
    font-size: %dpx;
    padding-left: %dpx;
    padding-right: %dpx;
  ]], cfg.tabInactiveBackground, cfg.fontFamily, cfg.fontSize, cfg.tabPadding, cfg.tabPadding)
end

---------------------------------------------------------------------------
-- DEBUG
---------------------------------------------------------------------------

--- Output debug message if debug mode is enabled.
-- Why: Conditional debug output helps diagnose drag/drop issues without
-- cluttering normal operation. Set mdw.debugMode = true to enable.
-- Supports format strings: mdw.debugEcho("value=%s, count=%d", name, count)
function mdw.debugEcho(msg, ...)
  if mdw.debugMode then
    local formatted = select("#", ...) > 0 and string.format(msg, ...) or msg
    cecho("<dim_gray>[DEBUG] " .. formatted .. "\n")
  end
end

---------------------------------------------------------------------------
-- GENERAL UTILITIES
-- Shared utilities used across all UI modules.
---------------------------------------------------------------------------

function mdw.echo(msg)
  debugc("[MDW] " .. msg)
end

--- Clamp a value between min and max bounds.
-- Why: Prevents dimension values from exceeding valid ranges,
-- which would cause layout corruption or negative coordinates.
function mdw.clamp(value, min, max)
  return math.max(min, math.min(max, value))
end

--- Calculate wrap value for a MiniConsole based on pixel width.
-- Uses calcFontSize to get exact character width for the configured font.
function mdw.calculateWrap(pixelWidth)
  local cfg = mdw.config
  local charWidth, _ = calcFontSize(cfg.fontSize, cfg.fontFamily)
  if charWidth and charWidth > 0 then
    return math.floor(pixelWidth / charWidth)
  end
  -- Fallback: assume ~7px per character for typical monospace fonts
  return math.floor(pixelWidth / 7)
end

--- Check if a sidebar is currently visible.
-- Why: Centralizes the visibility check that appears in multiple places,
-- making the code more readable and the logic easier to update.
function mdw.isSidebarVisible(side)
  if side == "left" then return mdw.visibility.leftSidebar end
  if side == "right" then return mdw.visibility.rightSidebar end
  return true
end

--- Show appropriate content for a widget (mapper or default content).
-- Why: When a widget has an embedded mapper, the default content is hidden.
-- This helper ensures the correct element is shown/hidden when the widget becomes visible.
function mdw.showWidgetContent(widget)
  if widget.mapper then
    widget.mapper:show()
    widget.mapper:raise()
    if widget.content then widget.content:hide() end
  elseif widget.content then
    widget.content:show()
  end
end

---------------------------------------------------------------------------
-- TEXT TRUNCATION
-- Utilities for truncating formatted text while preserving color codes.
-- Used by overflow="ellipsis" mode to truncate long lines with "...".
---------------------------------------------------------------------------

--- Count visible characters in formatted text (excluding color codes).
function mdw.visibleLength(text, method)
  if method == "echo" then return #text end
  if method == "cecho" or method == "decho" then
    return #(text:gsub("<[^>]*>", ""))
  end
  if method == "hecho" then
    return #(text:gsub("#%x%x%x%x%x%x", ""):gsub("#r", ""))
  end
  return #text
end

--- Truncate a single line of formatted text to maxVisible visible chars.
-- Walks through text tracking format codes vs visible chars, cuts at
-- (maxVisible - 3) and appends "...".
function mdw.truncateLine(text, method, maxVisible)
  if maxVisible < 4 then return text end
  local visLen = mdw.visibleLength(text, method)
  if visLen <= maxVisible then return text end

  local cutAt = maxVisible - 3

  if method == "echo" then
    return text:sub(1, cutAt) .. "..."
  end

  if method == "cecho" or method == "decho" then
    local result = {}
    local n = 0
    local visCount = 0
    local i = 1
    local len = #text
    while i <= len and visCount < cutAt do
      if text:sub(i, i) == "<" then
        local j = text:find(">", i + 1, true)
        if j then
          n = n + 1
          result[n] = text:sub(i, j)
          i = j + 1
        else
          n = n + 1
          result[n] = text:sub(i, i)
          visCount = visCount + 1
          i = i + 1
        end
      else
        n = n + 1
        result[n] = text:sub(i, i)
        visCount = visCount + 1
        i = i + 1
      end
    end
    n = n + 1
    result[n] = "..."
    return table.concat(result)
  end

  if method == "hecho" then
    local result = {}
    local n = 0
    local visCount = 0
    local i = 1
    local len = #text
    while i <= len and visCount < cutAt do
      if text:sub(i, i) == "#" then
        if i + 6 <= len and text:sub(i + 1, i + 6):match("^%x%x%x%x%x%x$") then
          n = n + 1
          result[n] = text:sub(i, i + 6)
          i = i + 7
        elseif i + 1 <= len and text:sub(i + 1, i + 1) == "r" then
          n = n + 1
          result[n] = "#r"
          i = i + 2
        else
          n = n + 1
          result[n] = "#"
          visCount = visCount + 1
          i = i + 1
        end
      else
        n = n + 1
        result[n] = text:sub(i, i)
        visCount = visCount + 1
        i = i + 1
      end
    end
    n = n + 1
    result[n] = "..."
    return table.concat(result)
  end

  return text:sub(1, cutAt) .. "..."
end

--- Truncate formatted text line-by-line.
-- Splits on newlines, truncates each line independently, rejoins.
function mdw.truncateFormatted(text, method, maxChars)
  if not text or maxChars < 1 then return text end
  if not text:find("\n", 1, true) then
    return mdw.truncateLine(text, method, maxChars)
  end

  local result = {}
  local n = 0
  local start = 1
  while true do
    local nlPos = text:find("\n", start, true)
    if nlPos then
      n = n + 1
      result[n] = mdw.truncateLine(text:sub(start, nlPos - 1), method, maxChars)
      start = nlPos + 1
    else
      n = n + 1
      result[n] = mdw.truncateLine(text:sub(start), method, maxChars)
      break
    end
  end
  return table.concat(result, "\n")
end

---------------------------------------------------------------------------
-- ELEMENT/HANDLER LIFECYCLE
-- Tracking and cleanup for UI elements and event handlers.
---------------------------------------------------------------------------

--- Register a UI element for cleanup on package uninstall.
-- Why: Mudlet doesn't automatically clean up Geyser elements when
-- packages are removed, leading to orphaned UI and memory leaks.
function mdw.trackElement(element)
  mdw.elements[#mdw.elements + 1] = element
  return element
end

--- Register a named event handler for cleanup.
-- Why: Named handlers can accumulate if not properly cleaned up on
-- package reinstall, causing duplicate event processing.
function mdw.registerHandler(event, name, func)
  local handlerName = mdw.packageName .. "_" .. name
  registerNamedEventHandler(mdw.packageName, handlerName, event, func)
  mdw.handlers[handlerName] = true
end

-- Why: Essential for clean package uninstall to prevent orphaned handlers.
function mdw.killAllHandlers()
  for handlerName in pairs(mdw.handlers) do
    deleteNamedEventHandler(mdw.packageName, handlerName)
  end
  mdw.handlers = {}
end

--- Destroy all tracked UI elements.
-- Why: Ensures complete cleanup on uninstall, preventing visual artifacts
-- and memory leaks from orphaned Geyser elements.
function mdw.destroyAllElements()
  -- Destroy all row splitters first
  if mdw.destroyAllRowSplitters then
    mdw.destroyAllRowSplitters()
  end

  -- Delete all tracked elements
  for _, element in ipairs(mdw.elements) do
    if element then
      pcall(function()
        if element.hide then element:hide() end
      end)
      pcall(function()
        if element.name then
          deleteLabel(element.name)
        end
      end)
    end
  end

  mdw.elements = {}
  mdw.widgets = {}
end

---------------------------------------------------------------------------
-- WIDGET CLASS HELPERS
-- Shared behavior for Widget and TabbedWidget classes.
-- Why: Both classes have nearly identical dock/visibility/position methods.
-- These helpers centralize the logic to avoid duplication.
---------------------------------------------------------------------------

--- Dock a widget class instance to a sidebar.
function mdw.dockWidgetClass(widget, side, row)
  assert(side == "left" or side == "right", "dock side must be 'left' or 'right'")

  widget.docked = side

  if row then
    widget.row = row
    widget.rowPosition = 0
    widget.subRow = 0
  else
    local docked = mdw.getDockedWidgets(side, widget)
    local maxRow = -1
    for _, w in ipairs(docked) do
      maxRow = math.max(maxRow, w.row or 0)
    end
    widget.row = maxRow + 1
    widget.rowPosition = 0
    widget.subRow = 0
  end

  mdw.hideResizeHandles(widget)
  mdw.reorganizeDock(side)
end

--- Undock a widget class instance (make it floating).
function mdw.undockWidgetClass(widget, x, y)
  local previousDock = widget.docked

  widget.docked = nil
  widget.row = nil
  widget.rowPosition = nil
  widget.subRow = nil

  if x and y then
    widget.container:move(x, y)
  end

  mdw.showResizeHandles(widget)
  mdw.updateResizeBorders(widget)

  if previousDock then
    mdw.reorganizeDock(previousDock)
  end

  mdw.saveLayout()
end

--- Show a widget class instance.
function mdw.showWidgetClass(widget, showContentFunc)
  widget.visible = true
  widget.container:show()

  if showContentFunc then
    showContentFunc()
  else
    mdw.showWidgetContent(widget)
  end

  if widget.docked then
    mdw.hideResizeHandles(widget)
    mdw.reorganizeDock(widget.docked)
  else
    mdw.showResizeHandles(widget)
  end

  if mdw.updateWidgetsMenuState then
    mdw.updateWidgetsMenuState()
  end
end

--- Hide a widget class instance.
function mdw.hideWidgetClass(widget)
  widget.visible = false
  widget.container:hide()
  mdw.hideResizeHandles(widget)

  if widget.docked then
    mdw.reorganizeDock(widget.docked)
  end

  if mdw.updateWidgetsMenuState then
    mdw.updateWidgetsMenuState()
  end

  if widget.onClose then
    widget.onClose(widget)
  end
end

--- Resize a widget class instance.
function mdw.resizeWidgetClass(widget, width, height, resizeContentFunc)
  widget.container:resize(width, height)
  local actualWidth = width or widget.container:get_width()
  local actualHeight = height or widget.container:get_height()
  resizeContentFunc(widget, actualWidth, actualHeight)

  if widget.docked then
    mdw.reorganizeDock(widget.docked)
  else
    mdw.updateResizeBorders(widget)
  end
end

--- Move a widget class instance (floating only).
function mdw.moveWidgetClass(widget, x, y)
  if widget.docked then
    mdw.debugEcho("Cannot move docked widget - undock it first")
    return
  end

  widget.container:move(x, y)
  mdw.updateResizeBorders(widget)
end

--- Destroy a widget class instance.
function mdw.destroyWidgetClass(widget)
  widget:hide()

  mdw.widgets[widget.name] = nil

  if widget.resizeLeft then widget.resizeLeft:hide() end
  if widget.resizeRight then widget.resizeRight:hide() end
  if widget.resizeTop then widget.resizeTop:hide() end
  if widget.resizeBottom then widget.resizeBottom:hide() end
  if widget.mapper then widget.mapper:hide() end

  widget.container:hide()

  if mdw.rebuildWidgetsMenu then
    mdw.rebuildWidgetsMenu()
  end
end

--- Apply pending layout to a widget during creation.
-- Why: Widget and TabbedWidget both need identical layout restoration logic.
-- Extracting to a shared helper prevents duplication and ensures consistency.
function mdw.applyPendingLayout(widget)
  if not mdw.pendingLayouts or not mdw.pendingLayouts[widget.name] then
    return false, nil
  end

  local saved = mdw.pendingLayouts[widget.name]

  -- Apply size first
  if saved.width and saved.height then
    widget:resize(saved.width, saved.height)
  end

  -- Apply dock state - but check if sidebar is visible
  if saved.dock then
    local sidebarVisible = mdw.isSidebarVisible(saved.dock)

    if sidebarVisible then
      -- Sidebar is visible, dock normally
      widget.row = saved.row
      widget.rowPosition = saved.rowPosition
      widget.subRow = saved.subRow or 0
      widget.widthRatio = saved.widthRatio
      widget.docked = saved.dock
      mdw.hideResizeHandles(widget)
      mdw.reorganizeDock(saved.dock)
    else
      -- Sidebar is hidden, remember the dock and hide the widget
      widget.originalDock = saved.dock
      widget.row = saved.row
      widget.rowPosition = saved.rowPosition
      widget.subRow = saved.subRow or 0
      widget.widthRatio = saved.widthRatio
      widget.docked = nil
      widget:hide()
    end
  elseif saved.x and saved.y then
    widget:undock(saved.x, saved.y)
  end

  -- Apply visibility (only if not already hidden due to hidden sidebar)
  if saved.visible == false and widget.visible ~= false then
    widget:hide()
  end

  mdw.pendingLayouts[widget.name] = nil
  return true, saved
end

---------------------------------------------------------------------------
-- DOCK CONFIGURATION
---------------------------------------------------------------------------

--- Get configuration values for a specific dock side.
-- Why: Reduces repetitive if/else blocks throughout the codebase when
-- operations differ only by which dock side they target.
-- NOTE: Returns a new table each call. Not suitable for hot paths;
-- cache the result if calling repeatedly within the same operation.
function mdw.getDockConfig(side)
  local cfg = mdw.config
  local winW = getMainWindowSize()

  local totalMargin = cfg.widgetMargin * 2  -- margin on both sides

  if side == "left" then
    return {
      dock = mdw.leftDock,
      dockHighlight = mdw.leftDockHighlight,
      splitter = mdw.leftSplitter,
      dropIndicator = mdw.leftDropIndicator,
      width = cfg.leftDockWidth,
      fullWidgetWidth = cfg.leftDockWidth - totalMargin - cfg.dockSplitterWidth,
      xPos = cfg.widgetMargin,
      setBorder = setBorderLeft,
      visibilityKey = "leftSidebar",
    }
  else
    return {
      dock = mdw.rightDock,
      dockHighlight = mdw.rightDockHighlight,
      splitter = mdw.rightSplitter,
      dropIndicator = mdw.rightDropIndicator,
      width = cfg.rightDockWidth,
      fullWidgetWidth = cfg.rightDockWidth - totalMargin - cfg.dockSplitterWidth,
      xPos = winW - cfg.rightDockWidth + cfg.dockSplitterWidth + cfg.widgetMargin,
      setBorder = setBorderRight,
      visibilityKey = "rightSidebar",
    }
  end
end

---------------------------------------------------------------------------
-- Build styles on load
---------------------------------------------------------------------------

mdw.buildStyles()
