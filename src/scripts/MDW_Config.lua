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
	leftDockWidth = 250, -- Initial width of left sidebar
	rightDockWidth = 250, -- Initial width of right sidebar
	minDockWidth = 150, -- Minimum width when resizing docks
	maxDockWidth = 1000, -- Maximum width when resizing docks

	-- Layout: Widget dimensions
	widgetHeight = 200,  -- Default height for new widgets
	titleHeight = 25,    -- Height of widget title bars
	minWidgetHeight = 50, -- Minimum height when resizing widgets
	minWidgetWidth = 50, -- Minimum width when resizing side-by-side widgets
	minFloatingWidth = 100, -- Minimum width for floating widgets

	-- Layout: Splitters and borders
	dockGap = 5,           -- Gap between sidebars/bottom bar and main window (px)
	dockSplitterWidth = 4, -- Width of vertical dock edge splitters (resize handles)
	separatorHeight = 2,   -- Height of horizontal separator lines (header/prompt)
	dropIndicatorHeight = 2, -- Height of drop target indicators
	widgetSplitterHeight = 2, -- Height of between-widget splitters (vertical resize)
	widgetSplitterWidth = 2, -- Width of between-widget splitters (horizontal resize)
	resizeBorderWidth = 2, -- Visual width of floating widget resize borders
	resizeHitWidth = 8,    -- Click target width for resize borders (extends outward)
	resizeCornerSize = 10, -- How far corner grab zones extend along each adjacent edge
	resizeHandleHitPad = 4, -- Extra hit area above bottom resize handle (px)

	-- Layout: Header and prompt bar
	headerHeight = 30,    -- Height of top header bar
	promptBarHeight = 30, -- Height of bottom prompt bar
	minPromptBarHeight = 25, -- Minimum prompt bar height when resizing

	-- Layout: Tabbed widgets
	tabBarHeight = 22, -- Height of tab button bar
	tabPadding = 5, -- Horizontal padding inside tab buttons

	-- Layout: Menus
	menuItemHeight = 28,     -- Height of dropdown menu items
	menuPadding = 8,         -- Vertical padding inside dropdown menus
	menuPaddingLeft = 10,    -- Left padding for menu items (px)
	headerButtonPadding = 12,  -- Right-side padding for header menu buttons
	menuWidth = 150,         -- Width of dropdown menus
	menuOverlap = 4,         -- Overlap between menu and header button border
	layoutMenuWidth = 250,   -- Width of the Font Size dropdown menu
	themeMenuWidth = 120,    -- Width of the Theme dropdown menu
	layoutMenuLabelWidth = 128, -- Width of row labels in Layout menu
	layoutMenuGap = 10,      -- Gap between label and controls in Layout menu
	layoutMenuBtnWidth = 30, -- Width of +/- buttons in Layout menu
	layoutMenuValueWidth = 36, -- Width of value display in Layout menu

	-- Layout: Margins
	widgetMargin = 2,     -- Margin around widgets in docks (px)
	contentPaddingLeft = 5, -- Left padding inside widget content area (px)
	contentPaddingTop = 5, -- Top padding inside widget content area (px)
	promptBarTopPadding = 5, -- Top padding inside prompt bar (px)
	floatingStartX = 100, -- Default X position for new floating widgets
	floatingStartY = 100, -- Default Y position for new floating widgets

	-- Drag behavior: Controls how drag operations feel
	dragThreshold = 5,  -- Pixels of movement before click becomes drag
	dockDropBuffer = 200, -- Extra detection area beyond dock bounds (px)
	snapThreshold = 15, -- Distance for height snap between widgets (px)
	sideBySideOffset = 20, -- Offset required to trigger side-by-side docking (px)

	-- Drop zone percentages (0.0-1.0): Control where drops trigger different behaviors
	verticalInsertZone = 0.1, -- Top/bottom 10% of row triggers vertical insert
	sideBySideZone = 0.2,  -- Top/bottom 20% disallows side-by-side placement

	-- Canonical color definitions (RGB tuples, theme-aware)
	-- Derived CSS/decho values are populated by buildStyles()
	colors = {
		-- Backgrounds
		sidebar           = { 26, 24, 21 },
		widgetBackground  = { 30, 30, 30 },
		widgetForeground  = { 200, 200, 200 },
		headerBackground  = { 38, 38, 38 },

		-- Menu/UI chrome
		menuBackground    = { 51, 51, 51 },
		menuBorder        = { 85, 85, 85 },

		-- Layout menu +/- buttons
		controlBackground = { 40, 38, 35 },
		controlBorder     = { 70, 65, 58 },
		controlHover      = { 60, 56, 50 },

		-- Splitters and resize handles
		splitter          = { 57, 53, 49 },
		splitterHover     = { 184, 134, 11 },

		-- Accent
		accent            = { 184, 134, 11 },
		accentDim         = { 218, 165, 32 },

		-- Tabs
		tabActive         = { 58, 52, 38 },
		tabInactive       = { 38, 38, 38 },

		-- Text
		headerText        = { 184, 134, 11 },
		menuText          = { 250, 235, 215 },
		menuHighlight     = { 189, 183, 107 },
		tabActiveText     = { 189, 183, 107 },
		tabInactiveText   = { 184, 134, 11 },

		-- Dock highlight (0.4 alpha applied in style generation)
		dockHighlight     = { 184, 134, 11 },
	},

	-- Active theme name (overrides specific colors from mdw.themes)
	theme = "gold",

	-- Legacy color keys populated by buildStyles() for backward compatibility
	widgetBackgroundRGB = { 30, 30, 30 },
	widgetForegroundRGB = { 200, 200, 200 },

	-- Typography
	fontFamily = "JetBrains Mono NL",
	contentFontSize = 11,      -- Base font size for widget content
	mainFontSize = 11,         -- Main Mudlet console font size
	promptFontAdjust = 0,      -- Prompt bar offset from contentFontSize
	headerMenuFontSize = 12,   -- Font size for header bar buttons and dropdown menus
	tabFontSize = 11,          -- Font size for tab buttons in tabbed widgets
	widgetHeaderFontSize = 12, -- Font size for widget title bars

	-- Title bar buttons (fill, lock, close)
	titleButtonSize = 12,     -- Width/height of square icon buttons (fill, lock)
	titleButtonPadding = 5,   -- Padding from left edge for fill/lock buttons
	titleButtonGap = 4,       -- Gap between fill and lock buttons
	closeButtonPadding = 4,   -- Padding from right edge for close button
	titleButtonTint = "#8C7850", -- Derived from accentDim by buildStyles()

	-- Buffering
	maxEchoBuffer = 50, -- Maximum echo buffer lines for widget reflow

	-- Sidebars Menu Items
	-- Define the items that appear in the Sidebars dropdown menu.
	-- Each item has: name (visibility key), label (display text)
	sidebarsMenuItems = {
		{ name = "leftSidebar",  label = "Left Sidebar" },
		{ name = "rightSidebar", label = "Right Sidebar" },
		{ name = "promptBar",    label = "Prompt Bar" },
	},
}

---------------------------------------------------------------------------
-- THEME DEFINITIONS
-- Each theme overrides specific colors from mdw.config.colors.
-- The "gold" theme is the default and needs no overrides.
---------------------------------------------------------------------------

mdw.themes = {
	gold = {}, -- default, uses mdw.config.colors as-is
	fantasy = {
		splitterHover   = { 86, 130, 3 },
		accent          = { 86, 130, 3 },
		accentDim       = { 138, 154, 91 },
		headerText      = { 138, 154, 91 },
		menuHighlight   = { 170, 185, 130 },
		tabActiveText   = { 138, 154, 91 },
		tabInactiveText = { 129, 97, 62 },
		tabActive       = { 38, 48, 30 },
		controlBorder   = { 74, 93, 35 },
		controlHover    = { 60, 75, 32 },
		dockHighlight   = { 86, 130, 3 },
	},
	emerald = {
		splitterHover   = { 45, 135, 75 },
		accent          = { 45, 135, 75 },
		accentDim       = { 75, 170, 105 },
		headerText      = { 75, 170, 105 },
		menuHighlight   = { 115, 200, 145 },
		tabActiveText   = { 115, 200, 145 },
		tabInactiveText = { 75, 170, 105 },
		tabActive       = { 28, 52, 36 },
		controlBorder   = { 48, 68, 54 },
		controlHover    = { 40, 58, 46 },
		dockHighlight   = { 45, 135, 75 },
	},
	sapphire = {
		splitterHover   = { 60, 120, 190 },
		accent          = { 60, 120, 190 },
		accentDim       = { 90, 150, 215 },
		headerText      = { 90, 150, 215 },
		menuHighlight   = { 135, 185, 235 },
		tabActiveText   = { 135, 185, 235 },
		tabInactiveText = { 90, 150, 215 },
		tabActive       = { 30, 40, 58 },
		controlBorder   = { 48, 58, 75 },
		controlHover    = { 40, 50, 65 },
		dockHighlight   = { 60, 120, 190 },
	},
	ruby = {
		splitterHover   = { 170, 55, 55 },
		accent          = { 170, 55, 55 },
		accentDim       = { 200, 90, 90 },
		headerText      = { 200, 90, 90 },
		menuHighlight   = { 225, 135, 135 },
		tabActiveText   = { 225, 135, 135 },
		tabInactiveText = { 200, 90, 90 },
		tabActive       = { 58, 30, 32 },
		controlBorder   = { 75, 48, 48 },
		controlHover    = { 65, 40, 40 },
		dockHighlight   = { 170, 55, 55 },
	},
	slate = {
		sidebar         = { 24, 24, 24 },
		splitter        = { 55, 55, 55 },
		splitterHover   = { 140, 140, 140 },
		accent          = { 140, 140, 140 },
		accentDim       = { 170, 170, 170 },
		headerText      = { 170, 170, 170 },
		menuHighlight   = { 210, 210, 210 },
		tabActiveText   = { 210, 210, 210 },
		tabInactiveText = { 170, 170, 170 },
		tabActive       = { 55, 55, 55 },
		controlBorder   = { 70, 70, 70 },
		controlHover    = { 60, 60, 60 },
		dockHighlight   = { 140, 140, 140 },
	},
	violet = {
		splitterHover   = { 120, 75, 170 },
		accent          = { 120, 75, 170 },
		accentDim       = { 155, 110, 200 },
		headerText      = { 155, 110, 200 },
		menuHighlight   = { 190, 150, 225 },
		tabActiveText   = { 190, 150, 225 },
		tabInactiveText = { 155, 110, 200 },
		tabActive       = { 44, 32, 58 },
		controlBorder   = { 60, 50, 75 },
		controlHover    = { 50, 42, 65 },
		dockHighlight   = { 120, 75, 170 },
	},
	copper = {
		splitterHover   = { 190, 110, 45 },
		accent          = { 190, 110, 45 },
		accentDim       = { 215, 145, 75 },
		headerText      = { 215, 145, 75 },
		menuHighlight   = { 240, 180, 115 },
		tabActiveText   = { 240, 180, 115 },
		tabInactiveText = { 215, 145, 75 },
		tabActive       = { 58, 44, 30 },
		controlBorder   = { 72, 56, 44 },
		controlHover    = { 62, 48, 36 },
		dockHighlight   = { 190, 110, 45 },
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

-- Prompt bar splitter drag state for vertical resize
mdw.promptBarDrag = {
	active = false,
	offsetY = 0,
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

-- Tab drag state for reordering tabs within a TabbedWidget
mdw.tabDrag = {
	active = false,
	tabbedWidget = nil,
	tabObj = nil,
	originalIndex = nil,
	startMouseX = 0,
	startTabX = 0,
	hasMoved = false,
	dropIndex = nil,
}

-- Visibility toggles for layout components
mdw.visibility = {
	leftSidebar = true,
	rightSidebar = true,
	promptBar = true,
}

-- Menu state
mdw.menus = {
	sidebarsOpen = false,
	widgetsOpen = false,
	layoutOpen = false,
	themeOpen = false,
}

-- Update flag to prevent teardown during package update
mdw.isUpdating = false

-- Layout persistence
mdw.pendingLayouts = {}
mdw.layoutFile = getMudletHomeDir() .. "/mdw_layout.lua"

-- Debug mode flag
mdw.debugMode = false
