--[[
  MDW_Config.lua
  Configuration and shared state for MDW (Mudlet Dockable Widgets).

  This module contains only static data declarations: user-adjustable config
  values, style table initialization, and shared state tables. All runtime
  functions live in MDW_Helpers.lua.

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
  dockSplitterWidth = 4,         -- Width of vertical dock edge splitters (resize handles)
  separatorHeight = 2,           -- Height of horizontal separator lines (header/prompt)
  dropIndicatorHeight = 2,       -- Height of drop target indicators
  widgetSplitterHeight = 2,      -- Height of between-widget splitters (vertical resize)
  widgetSplitterWidth = 2,       -- Width of between-widget splitters (horizontal resize)
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
  widgetMargin = 2,              -- Margin around widgets in docks (px)
  contentPaddingLeft = 5,        -- Left padding inside widget content area (px)
  contentPaddingTop = 5,         -- Top padding inside widget content area (px)
  promptBarTopPadding = 2,       -- Top padding inside prompt bar (px)
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

  -- Layout Menu Items
  -- Define the items that appear in the Layout dropdown menu.
  -- Each item has: name (visibility key), label (display text)
  layoutMenuItems = {
    {name = "leftSidebar", label = "Left Sidebar"},
    {name = "rightSidebar", label = "Right Sidebar"},
    {name = "promptBar", label = "Prompt Bar"},
  },
}

---------------------------------------------------------------------------
-- STYLES
-- Populated by mdw.buildStyles() in MDW_Helpers.lua.
---------------------------------------------------------------------------

mdw.styles = {}

---------------------------------------------------------------------------
-- SHARED STATE
-- Module-level state shared across all UI components.
-- Why: Centralizing state prevents scattered globals and makes
-- cleanup/reset operations straightforward.
---------------------------------------------------------------------------

-- Widget storage: maps widget name -> Widget/TabbedWidget class instance
-- Access widgets directly: mdw.widgets["MyWidget"]:echo("hello")
-- Or use class methods: mdw.Widget.get("MyWidget"), mdw.TabbedWidget.get("MyWidget")
mdw.widgets = {}
mdw.elements = {}
mdw.handlers = {}

-- Row splitters: separate elements between side-by-side widgets
-- Key format: "{side}_{rowIndex}_{leftWidgetPosition}"
mdw.rowSplitters = {}

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
  originalSubRow = nil,
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

-- Update flag to prevent teardown during package update
mdw.isUpdating = false

-- Layout persistence
mdw.pendingLayouts = {}
mdw.layoutFile = getMudletHomeDir() .. "/mdw_layout.lua"

-- Debug mode flag
mdw.debugMode = false
