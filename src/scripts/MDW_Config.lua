--[[
  MDW_Config.lua
  Configuration, styles, and shared state for MDW (Mudlet Dockable Widgets).

  This module centralizes all user-adjustable values and visual styling.
  Modify config values here to customize the UI appearance and behavior.

  Dependencies: None (this is the root configuration module)
]]

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------

mdw = mdw or {}
mdw.packageName = "MDW"

---------------------------------------------------------------------------
-- CONFIGURATION
-- User-adjustable values. Modify these to customize behavior.
---------------------------------------------------------------------------

mdw.config = {
  -- Layout: Dock dimensions
  leftDockWidth = 250,           -- Initial width of left sidebar
  rightDockWidth = 250,          -- Initial width of right sidebar
  minDockWidth = 150,            -- Minimum width when resizing docks
  maxDockWidth = 1000,           -- Maximum width when resizing docks

  -- Layout: Widget dimensions
  widgetHeight = 200,            -- Default height for new widgets
  titleHeight = 25,              -- Height of widget title bars
  minWidgetHeight = 50,          -- Minimum height when resizing widgets
  minWidgetWidth = 50,           -- Minimum width when resizing side-by-side widgets
  minFloatingWidth = 100,        -- Minimum width for floating widgets

  -- Layout: Splitters and borders
  splitterWidth = 2,             -- Width of dock edge splitters
  dropIndicatorHeight = 2,       -- Height of drop target indicators
  widgetSplitterHeight = 2,      -- Height of between-widget splitters
  resizeBorderWidth = 2,         -- Width of floating widget resize handles

  -- Layout: Header and prompt bar
  headerHeight = 30,             -- Height of top header bar
  promptBarHeight = 30,          -- Height of bottom prompt bar

  -- Layout: Tabbed widgets
  tabBarHeight = 22,             -- Height of tab button bar
  tabPadding = 5,                -- Horizontal padding inside tab buttons

  -- Layout: Menus
  menuItemHeight = 28,           -- Height of dropdown menu items
  menuPadding = 8,               -- Vertical padding inside dropdown menus
  menuPaddingLeft = 10,          -- Left padding for menu items (px)
  headerButtonWidth = 80,        -- Width of header menu buttons
  menuWidth = 150,               -- Width of dropdown menus
  menuOverlap = 4,               -- Overlap between menu and header button border

  -- Layout: Margins
  widgetMargin = 5,              -- Margin around widgets in docks (px)
  contentPaddingLeft = 5,        -- Left padding inside widget content area (px)
  contentPaddingTop = 5,         -- Top padding inside widget content area (px)
  floatingStartX = 100,          -- Default X position for new floating widgets
  floatingStartY = 100,          -- Default Y position for new floating widgets

  -- Drag behavior: Controls how drag operations feel
  dragThreshold = 5,             -- Pixels of movement before click becomes drag
  dockDropBuffer = 200,          -- Extra detection area beyond dock bounds (px)
  snapThreshold = 15,            -- Distance for height snap between widgets (px)
  sideBySideOffset = 20,         -- Offset required to trigger side-by-side docking (px)

  -- Drop zone percentages (0.0-1.0): Control where drops trigger different behaviors
  verticalInsertZone = 0.1,      -- Top/bottom 10% of row triggers vertical insert
  sideBySideZone = 0.2,          -- Top/bottom 20% disallows side-by-side placement

  -- Colors: Background (CSS format for Labels, RGB tables for MiniConsoles)
  sidebarBackground = "rgb(26,24,21)",
  widgetBackground = "rgb(30,30,30)",
  widgetBackgroundRGB = {30, 30, 30},
  widgetForegroundRGB = {200, 200, 200},
  headerBackground = "rgb(38,38,38)",
  menuBackground = "rgb(50,48,45)",

  -- Colors: Accents
  splitterColor = "rgb(57,53,49)",
  splitterHoverColor = "rgb(106,91,58)",
  dropIndicatorColor = "rgb(106,91,58)",
  resizeBorderColor = "rgb(57,53,49)",
  checkboxColor = "rgb(140,120,80)",

  -- Colors: Text (decho format: R,G,B)
  headerTextColor = "140,120,80",
  menuTextColor = "230,221,202",           -- Normal menu item text color
  menuHighlightColor = "196,169,106",      -- Highlighted menu item text color
  tabActiveTextColor = "196,169,106",      -- Active tab text color
  tabInactiveTextColor = "140,120,80",     -- Inactive tab text color

  -- Colors: Tab backgrounds
  tabActiveBackground = "rgb(50,48,45)",   -- Active tab background
  tabInactiveBackground = "rgb(38,38,38)", -- Inactive tab background

  -- Typography
  fontFamily = "JetBrains Mono NL",
  fontSize = 11,
}

---------------------------------------------------------------------------
-- STYLES
-- Pre-built stylesheets for consistency across components.
-- Why: Centralizing styles prevents duplication and ensures visual consistency.
-- Changes to appearance only need to happen in one place.
---------------------------------------------------------------------------

mdw.styles = {}

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

-- Build styles on load
mdw.buildStyles()

---------------------------------------------------------------------------
-- SHARED STATE
-- Module-level state shared across all UI components.
-- Why: Centralizing state prevents scattered globals and makes
-- cleanup/reset operations straightforward.
---------------------------------------------------------------------------

-- UI element tracking for cleanup
mdw.widgets = {}
mdw.elements = {}
mdw.handlers = {}

-- Drag state for widget movement
mdw.drag = {
  active = false,
  widget = nil,
  offsetX = 0,
  offsetY = 0,
  startMouseX = 0,
  startMouseY = 0,
  hasMoved = false,
  -- Drop target info (populated during drag)
  insertSide = nil,
  dropType = nil,
  rowIndex = nil,
  positionInRow = nil,
  targetWidget = nil,
  -- Original dock info (for cancel/restore)
  originalDock = nil,
  originalRow = nil,
  originalRowPosition = nil,
  -- Debug tracking
  lastDebugKey = nil,
}

-- Splitter drag state for dock resizing
mdw.splitterDrag = {
  active = false,
  side = nil,
  offsetX = 0,
}

-- Widget splitter drag state for vertical resize
mdw.widgetSplitterDrag = {
  active = false,
  widget = nil,
  side = nil,
  index = nil,
  offsetY = 0,
}

-- Vertical widget splitter drag state for horizontal resize
mdw.verticalWidgetSplitterDrag = {
  active = false,
  splitter = nil,
  leftWidget = nil,
  rightWidget = nil,
  side = nil,
  offsetX = 0,
  leftStartWidth = 0,
  rightStartWidth = 0,
  startMouseX = 0,
}

-- Floating widget resize drag state
mdw.resizeDrag = {
  active = false,
  widget = nil,
  edge = nil,
  startX = 0,
  startY = 0,
  startWidth = 0,
  startHeight = 0,
  startMouseX = 0,
  startMouseY = 0,
}

-- Visibility toggles for layout components
mdw.visibility = {
  leftSidebar = true,
  rightSidebar = true,
  promptBar = true,
}

-- Menu state
mdw.menus = {
  layoutOpen = false,
  widgetsOpen = false,
}

-- Splitter tracking (horizontal splitters for vertical resize)
mdw.widgetSplitters = {
  left = {},
  right = {},
}

-- Vertical splitter tracking (for horizontal resize between side-by-side widgets)
mdw.verticalWidgetSplitters = {
  left = {},
  right = {},
}

-- Update flag to prevent teardown during package update
mdw.isUpdating = false

---------------------------------------------------------------------------
-- DEBUG
---------------------------------------------------------------------------

mdw.debugMode = false

--- Output debug message if debug mode is enabled.
-- Why: Conditional debug output helps diagnose drag/drop issues without
-- cluttering normal operation. Set mdw.debugMode = true to enable.
function mdw.debugEcho(msg)
  if mdw.debugMode then
    cecho("<dim_gray>[DEBUG] " .. msg .. "\n")
  end
end

---------------------------------------------------------------------------
-- HELPER FUNCTIONS
-- Shared utilities used across all UI modules.
---------------------------------------------------------------------------

--- Output a formatted message to the console.
-- @param msg string The message to display
function mdw.echo(msg)
  cecho("<gray>[<white>MDW<gray>] " .. msg .. "\n")
end

--- Clamp a value between min and max bounds.
-- Why: Prevents dimension values from exceeding valid ranges,
-- which would cause layout corruption or negative coordinates.
-- @param value number The value to clamp
-- @param min number Minimum allowed value
-- @param max number Maximum allowed value
-- @return number The clamped value
function mdw.clamp(value, min, max)
  return math.max(min, math.min(max, value))
end

--- Calculate wrap value for a MiniConsole based on pixel width.
-- Uses calcFontSize to get exact character width for the configured font.
-- @param pixelWidth number The width of the console in pixels
-- @return number The number of characters to wrap at
function mdw.calculateWrap(pixelWidth)
  local cfg = mdw.config
  local charWidth, _ = calcFontSize(cfg.fontSize, cfg.fontFamily)
  if charWidth and charWidth > 0 then
    return math.floor(pixelWidth / charWidth)
  end
  -- Fallback: assume ~7px per character for typical monospace fonts
  return math.floor(pixelWidth / 7)
end

--- Get configuration values for a specific dock side.
-- Why: Reduces repetitive if/else blocks throughout the codebase when
-- operations differ only by which dock side they target.
-- @param side string "left" or "right"
-- @return table Configuration for the specified dock
function mdw.getDockConfig(side)
  local cfg = mdw.config
  local winW = getMainWindowSize()

  local totalMargin = cfg.widgetMargin * 2  -- margin on both sides

  if side == "left" then
    return {
      dock = mdw.leftDock,
      splitter = mdw.leftSplitter,
      dropIndicator = mdw.leftDropIndicator,
      width = cfg.leftDockWidth,
      fullWidgetWidth = cfg.leftDockWidth - totalMargin - cfg.splitterWidth,
      xPos = cfg.widgetMargin,
      widgetSplitters = mdw.widgetSplitters.left,
      verticalSplitters = mdw.verticalWidgetSplitters.left,
      setBorder = setBorderLeft,
      visibilityKey = "leftSidebar",
    }
  else
    return {
      dock = mdw.rightDock,
      splitter = mdw.rightSplitter,
      dropIndicator = mdw.rightDropIndicator,
      width = cfg.rightDockWidth,
      fullWidgetWidth = cfg.rightDockWidth - totalMargin - cfg.splitterWidth,
      xPos = winW - cfg.rightDockWidth + cfg.splitterWidth + cfg.widgetMargin,
      widgetSplitters = mdw.widgetSplitters.right,
      verticalSplitters = mdw.verticalWidgetSplitters.right,
      setBorder = setBorderRight,
      visibilityKey = "rightSidebar",
    }
  end
end

--- Register a UI element for cleanup on package uninstall.
-- Why: Mudlet doesn't automatically clean up Geyser elements when
-- packages are removed, leading to orphaned UI and memory leaks.
-- @param element Geyser element to track
-- @return The same element (for chaining)
function mdw.trackElement(element)
  mdw.elements[#mdw.elements + 1] = element
  return element
end

--- Register a named event handler for cleanup.
-- Why: Named handlers can accumulate if not properly cleaned up on
-- package reinstall, causing duplicate event processing.
-- @param event string The event name to listen for
-- @param name string Unique identifier for this handler
-- @param func function|string The handler function or function name
function mdw.registerHandler(event, name, func)
  local handlerName = mdw.packageName .. "_" .. name
  registerNamedEventHandler(mdw.packageName, handlerName, event, func)
  mdw.handlers[handlerName] = true
end

--- Kill all registered event handlers.
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
  -- Helper to safely delete a label by name
  local function safeDeleteLabel(name)
    if Geyser.Label.all and Geyser.Label.all[name] then
      pcall(function()
        Geyser.Label.all[name]:hide()
      end)
      pcall(deleteLabel, name)
    end
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

  -- Also delete any splitters by name pattern to catch orphans
  -- This handles splitters that weren't properly tracked
  for _, side in ipairs({"left", "right"}) do
    for i = 1, 20 do
      safeDeleteLabel("MDW_WidgetSplitter_" .. side .. "_" .. i)
      safeDeleteLabel("MDW_VertWidgetSplitter_" .. side .. "_" .. i)
    end
  end

  mdw.elements = {}
  mdw.widgets = {}

  -- Reset splitter tracking arrays to prevent stale references
  mdw.widgetSplitters = { left = {}, right = {} }
  mdw.verticalWidgetSplitters = { left = {}, right = {} }
end
