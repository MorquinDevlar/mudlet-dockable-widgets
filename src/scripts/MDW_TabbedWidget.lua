--[[
  MDW_TabbedWidget.lua
  Tabbed widget class for MDW (Mudlet Dockable Widgets).

  Provides widgets with multiple switchable tabs, each with its own MiniConsole
  content area. Supports an optional "all" tab that receives copies of all
  messages sent to other tabs.

  Usage:
    local comm = mdw.TabbedWidget:new({
      name = "Comm",
      title = "Communications",
      tabs = {"All", "Room", "Global", "Tells"},
      allTab = "All",        -- Optional: this tab receives copies of all messages
      activeTab = "All",     -- Optional: initially active tab (defaults to first)
      dock = "right",
      height = 300,
    })

    -- Echo to active tab
    comm:echo("Hello!")
    comm:cecho("<red>Colored text")

    -- Echo to specific tab (also echoes to "all" tab if set)
    comm:echoTo("Room", "Room message\n")
    comm:cechoTo("Global", "<green>Global message\n")

    -- Switch tabs
    comm:selectTab("Tells")
    local current = comm:getActiveTab()

  Dependencies: MDW_Config.lua, MDW_Helpers.lua, MDW_Init.lua, MDW_WidgetCore.lua, MDW_Widget.lua
]]

---------------------------------------------------------------------------
-- TABBED WIDGET CLASS
---------------------------------------------------------------------------

mdw.TabbedWidget = mdw.TabbedWidget or {}
mdw.TabbedWidget.__index = mdw.TabbedWidget

--- Sanitize a tab name for use in Geyser element names.
-- Why: Tab names may contain spaces or special characters that could cause
-- issues in element naming. This ensures safe element IDs.
-- NOTE: Different tab names can produce the same sanitized name (e.g.
-- "My Tab" and "My_Tab" both become "My_Tab"). Callers should ensure
-- tab names are unique after sanitization.
local function sanitizeTabName(tabName)
	-- Replace spaces and special characters with underscores
	return tabName:gsub("[^%w]", "_")
end

--- Default configuration for new tabbed widgets.
mdw.TabbedWidget.defaults = {
	height = nil,    -- Uses mdw.config.widgetHeight if not specified
	dock = nil,      -- nil = floating, "left" or "right" = docked
	x = nil,         -- Initial X position (uses config.floatingStartX if nil)
	y = nil,         -- Initial Y position (uses config.floatingStartY if nil)
	visible = true,  -- Whether widget starts visible
	row = nil,       -- Row in dock (auto-assigned if nil)
	rowPosition = 0, -- Position within row for side-by-side
	subRow = 0,      -- Sub-row within column for sub-column stacking
	tabs = {},       -- Array of tab names
	allTab = nil,    -- Name of "all" tab (receives copies of messages)
	activeTab = nil, -- Initially active tab name (defaults to first)
	overflow = "wrap", -- "wrap", "ellipsis", or "hidden"
	fill = false,    -- Whether widget fills remaining dock column height
	widthLocked = false, -- Whether widget's column width is locked
	fontAdjust = 0,  -- Offset from contentFontSize for this widget
}

--- Create a new TabbedWidget instance.
function mdw.TabbedWidget:new(cons)
	cons = cons or {}

	-- Validate required fields
	assert(type(cons.name) == "string" and cons.name ~= "", "TabbedWidget name is required")
	assert(type(cons.tabs) == "table" and #cons.tabs > 0, "TabbedWidget requires at least one tab")

	-- Return existing widget if one with this name already exists
	-- This allows scripts to be reloaded without creating duplicates
	if mdw.widgets[cons.name] then
		return mdw.widgets[cons.name]
	end

	-- Apply defaults
	local self = setmetatable({}, mdw.TabbedWidget)
	for k, v in pairs(mdw.TabbedWidget.defaults) do
		self[k] = cons[k] ~= nil and cons[k] or v
	end

	-- Required/computed fields
	self.name = cons.name
	self.title = cons.title or cons.name
	self.height = cons.height or mdw.config.widgetHeight
	self.tabs = cons.tabs
	self.allTab = cons.allTab
	self.onClose = cons.onClose
	self.onTabChange = cons.onTabChange
	self.fill = cons.fill or false
	self.widthLocked = cons.widthLocked or false
	self.lockedWidth = nil
	self.fontAdjust = cons.fontAdjust or 0

	-- Tab state
	self.tabObjects = {}  -- Array of tab objects: {name, button, console}
	self.tabsByName = {}  -- Lookup table: tabName -> tab object
	self.activeTabIndex = 1 -- Index of currently active tab

	local cfg = mdw.config

	-- Determine initial position
	local x = cons.x or self.x or cfg.floatingStartX
	local y = cons.y or self.y or cfg.floatingStartY

	-- If docking, calculate dock position
	if cons.dock then
		local winW = getMainWindowSize()
		if cons.dock == "left" then
			x = cfg.widgetMargin
		elseif cons.dock == "right" then
			x = winW - cfg.rightDockWidth + cfg.dockSplitterWidth + cfg.widgetMargin
		end
		y = cfg.headerHeight + cfg.widgetMargin
	end

	-- Create the underlying widget structure
	local internalWidget = mdw.createTabbedWidgetInternal(self, x, y)

	-- Copy widget properties to the class
	-- Why: The class IS the widget now - mdw.widgets stores the class directly.
	self.container = internalWidget.container
	self.titleBar = internalWidget.titleBar
	self.tabBar = internalWidget.tabBar
	self.contentBg = internalWidget.contentBg
	self.resizeLeft = internalWidget.resizeLeft
	self.resizeRight = internalWidget.resizeRight
	self.resizeTop = internalWidget.resizeTop
	self.resizeBottom = internalWidget.resizeBottom
	self.resizeTopLeft = internalWidget.resizeTopLeft
	self.resizeTopRight = internalWidget.resizeTopRight
	self.resizeBottomLeft = internalWidget.resizeBottomLeft
	self.resizeBottomRight = internalWidget.resizeBottomRight
	self.bottomResizeHandle = internalWidget.bottomResizeHandle
	self.fillButton = internalWidget.fillButton
	self.lockButton = internalWidget.lockButton
	self.closeButton = internalWidget.closeButton

	-- State properties (accessed by internal functions via mdw.widgets iteration)
	self.docked = nil     -- "left", "right", or nil for floating
	self.row = nil        -- Row index in dock
	self.rowPosition = 0  -- Position within row (for side-by-side)
	self.subRow = 0       -- Sub-row within column for sub-column stacking
	self.originalDock = nil -- Saved dock when sidebar is hidden
	self.isTabbed = true  -- Distinguishes from Widget

	-- Overflow mode
	self.overflow = cons.overflow or "wrap"
	if self.overflow ~= "wrap" then
		for _, tabObj in ipairs(self.tabObjects) do
			tabObj.console:setWrap(10000)
		end
	end
	if #self.tabObjects > 0 then
		-- Apply the effective font size (honours fontAdjust) and wrap at creation
		mdw.applyWidgetFontSize(self)
	end

	-- Apply height
	if self.height ~= cfg.widgetHeight then
		self.container:resize(nil, self.height)
		mdw.resizeTabbedWidgetContent(self, self.container:get_width(), self.height)
	end

	-- Register the CLASS instance directly in mdw.widgets
	mdw.widgets[self.name] = self

	-- Apply docking
	if cons.dock then
		self:dock(cons.dock, cons.row)
	else
		self.docked = nil
		mdw.showResizeHandles(self)
	end

	-- Apply visibility
	if not self.visible then
		self:hide()
	end

	-- Apply saved layout if available (uses shared helper to avoid duplication)
	local applied, saved = mdw.applyPendingLayout(self)

	-- Restore saved tab order before selecting the active tab
	if applied and saved and saved.tabOrder then
		mdw.applyTabOrder(self, saved.tabOrder)
	end

	-- Restore active tab from saved layout or use provided/default. Guard the
	-- saved name against the current tab set: a stale name would otherwise leave
	-- selectTab with nothing shown (all consoles start hidden) - a blank widget.
	if applied and saved and saved.activeTab and self.tabsByName[saved.activeTab] then
		self:selectTab(saved.activeTab)
	else
		local initialTab = cons.activeTab or self.tabs[1]
		self:selectTab(initialTab)
	end

	-- Default every widget into its own single-tab home group (the universal
	-- occupant). No-op when restoring into a saved group. Done after tab restore
	-- so the active tab is set before the widget renders headless.
	if mdw.wrapInHomeStack then
		mdw.wrapInHomeStack(self)
	end

	-- Update widgets menu to include new widget
	if mdw.rebuildWidgetsMenu then
		mdw.rebuildWidgetsMenu()
	end

	return self
end

---------------------------------------------------------------------------
-- INTERNAL WIDGET CREATION
---------------------------------------------------------------------------

--- Create the internal widget structure for a tabbed widget.
function mdw.createTabbedWidgetInternal(tabbedWidget, x, y)
	local cfg = mdw.config
	local name = tabbedWidget.name
	local title = tabbedWidget.title

	local widget = {
		name = name,
		title = title,
	}

	-- Calculate dimensions
	local totalMargin = cfg.widgetMargin * 2
	local containerWidth = cfg.leftDockWidth - totalMargin - cfg.dockSplitterWidth
	local contentAreaHeight = cfg.widgetHeight - cfg.titleHeight - cfg.tabBarHeight
	local contentHeight = contentAreaHeight - cfg.contentPaddingTop

	-- Main container
	widget.container = mdw.trackElement(Geyser.Container:new({
		name = "MDW_" .. name,
		x = x,
		y = y,
		width = containerWidth,
		height = cfg.widgetHeight,
	}))

	local actualWidth = widget.container:get_width()
	local consoleWidth = actualWidth - cfg.contentPaddingLeft
	local bgRGB = cfg.widgetBackgroundRGB

	-- Background label to fill the padding area
	widget.contentBg = mdw.trackElement(Geyser.Label:new({
		name = "MDW_" .. name .. "_ContentBg",
		x = 0,
		y = cfg.titleHeight + cfg.tabBarHeight,
		width = actualWidth,
		height = contentAreaHeight,
	}, widget.container))
	widget.contentBg:setStyleSheet(string.format(
		[[background-color: rgb(%d,%d,%d);]],
		bgRGB[1], bgRGB[2], bgRGB[3]
	))

	-- Title bar (drag handle)
	widget.titleBar = mdw.trackElement(Geyser.Label:new({
		name = "MDW_" .. name .. "_Title",
		x = 0,
		y = 0,
		width = actualWidth,
		height = cfg.titleHeight,
	}, widget.container))
	widget.titleBar:setStyleSheet(mdw.styles.titleBar)
	widget.titleBar:setFontSize(cfg.widgetHeaderFontSize)
	widget.titleBar:setCursor(mudlet.cursor.OpenHand)

	-- Tab bar container
	widget.tabBar = mdw.trackElement(Geyser.Label:new({
		name = "MDW_" .. name .. "_TabBar",
		x = 0,
		y = cfg.titleHeight,
		width = actualWidth,
		height = cfg.tabBarHeight,
	}, widget.container))
	widget.tabBar:setStyleSheet(mdw.styles.channelTabBar)

	-- Create tabs
	local numTabs = #tabbedWidget.tabs
	local tabWidth = actualWidth / numTabs

	for i, tabName in ipairs(tabbedWidget.tabs) do
		local tabX = (i - 1) * tabWidth
		local safeTabName = sanitizeTabName(tabName)

		-- Tab button
		local tabButton = mdw.trackElement(Geyser.Label:new({
			name = "MDW_" .. name .. "_Tab_" .. safeTabName,
			x = tabX,
			y = cfg.titleHeight,
			width = tabWidth,
			height = cfg.tabBarHeight,
		}, widget.container))
		tabButton:setCursor(mudlet.cursor.PointingHand)
		tabButton:setToolTip("Drag to reorder")

		-- Tab console (MiniConsole for scrollable text)
		-- Offset by padding to create left and top padding
		local consoleName = "MDW_" .. name .. "_Console_" .. safeTabName
		local tabConsole = mdw.trackElement(Geyser.MiniConsole:new({
			name = consoleName,
			x = cfg.contentPaddingLeft,
			y = cfg.titleHeight + cfg.tabBarHeight + cfg.contentPaddingTop,
			width = consoleWidth,
			height = contentHeight,
		}, widget.container))
		local fgRGB = cfg.widgetForegroundRGB
		tabConsole:setColor(bgRGB[1], bgRGB[2], bgRGB[3], 255)
		tabConsole:setFont(cfg.fontFamily)
		tabConsole:setFontSize(cfg.contentFontSize)
		tabConsole:setWrap(mdw.calculateWrap(consoleWidth))
		setBgColor(consoleName, bgRGB[1], bgRGB[2], bgRGB[3])
		setFgColor(consoleName, fgRGB[1], fgRGB[2], fgRGB[3])
		tabConsole:hide() -- All consoles start hidden

		-- Create tab object
		local tabObj = {
			name = tabName,
			safeName = safeTabName,
			button = tabButton,
			console = tabConsole,
			index = i,
		}

		tabbedWidget.tabObjects[i] = tabObj
		tabbedWidget.tabsByName[tabName] = tabObj

		mdw.applyTabInactiveStyle(tabObj)

		-- Set up tab drag (handles both click-to-select and drag-to-reorder)
		mdw.setupTabDrag(tabbedWidget, tabObj)
	end

	-- Bottom resize handle - part of widget so it moves with dragging
	widget.bottomResizeHandle = mdw.trackElement(Geyser.Label:new({
		name = "MDW_" .. name .. "_BottomResize",
		x = 0,
		y = cfg.widgetHeight - cfg.widgetSplitterHeight,
		width = actualWidth,
		height = cfg.widgetSplitterHeight,
	}, widget.container))
	widget.bottomResizeHandle:setStyleSheet(string.format([[
    QLabel { background-color: %s; }
    QLabel:hover { background-color: %s; }
  ]], cfg.resizeBorderColor, cfg.splitterHoverColor))
	widget.bottomResizeHandle:setCursor(mudlet.cursor.ResizeVertical)
	widget.bottomResizeHandle:hide() -- Hidden by default, shown when docked

	-- Create title bar buttons (FILL, LOCK, Close)
	mdw.createTitleBarButtons(widget)

	-- Render title (after buttons so truncation accounts for button space)
	mdw.renderWidgetTitle(widget)

	-- Create resize borders
	mdw.createResizeBorders(widget)

	-- Set up drag callbacks
	mdw.setupWidgetDrag(widget)

	-- Set up docked resize handle callbacks
	mdw.setupDockedResizeHandle(widget)

	return widget
end

--- Resize tabbed widget content after container changes.
function mdw.resizeTabbedWidgetContent(tabbedWidget, targetWidth, targetHeight)
	local cfg = mdw.config

	-- Use provided dimensions or fall back to container dimensions
	local cw = targetWidth or tabbedWidget.container:get_width()
	local ch = targetHeight or tabbedWidget.container:get_height()

	-- Headless members (inside a stack) skip their own title bar; the tab bar
	-- moves to the top and the stack provides the resize handle.
	local titleH = tabbedWidget._headless and 0 or cfg.titleHeight
	local resizeHandleHeight = (tabbedWidget.docked and not tabbedWidget._headless) and cfg.widgetSplitterHeight or 0
	local contentAreaHeight = ch - titleH - cfg.tabBarHeight - resizeHandleHeight
	local contentAreaWidth = cw -- Full width - splitters are separate elements now
	local consoleWidth = contentAreaWidth - cfg.contentPaddingLeft
	local consoleHeight = contentAreaHeight - cfg.contentPaddingTop

	-- Resize title bar (skipped when headless)
	if tabbedWidget._headless then
		tabbedWidget.titleBar:hide()
	else
		tabbedWidget.titleBar:move(0, 0)
		tabbedWidget.titleBar:resize(cw, cfg.titleHeight)
		mdw.repositionTitleBarButtons(tabbedWidget, cw)
		mdw.renderWidgetTitle(tabbedWidget)
	end

	-- Resize tab bar
	tabbedWidget.tabBar:move(0, titleH)
	tabbedWidget.tabBar:resize(cw, cfg.tabBarHeight)

	-- Resize background label that fills the padding area (not overlapping right splitter)
	if tabbedWidget.contentBg then
		tabbedWidget.contentBg:move(0, titleH + cfg.tabBarHeight)
		tabbedWidget.contentBg:resize(contentAreaWidth, contentAreaHeight)
	end

	-- Resize tabs
	local numTabs = #tabbedWidget.tabObjects
	local tabWidth = cw / numTabs

	for i, tabObj in ipairs(tabbedWidget.tabObjects) do
		local tabX = (i - 1) * tabWidth

		-- Resize tab button
		tabObj.button:move(tabX, titleH)
		tabObj.button:resize(tabWidth, cfg.tabBarHeight)

		-- Resize tab console
		tabObj.console:move(cfg.contentPaddingLeft, titleH + cfg.tabBarHeight + cfg.contentPaddingTop)
		tabObj.console:resize(consoleWidth, consoleHeight)
		local effectiveFontSize = mdw.getEffectiveFontSize(tabbedWidget.fontAdjust)
		local wrapWidth = mdw.calculateWrap(consoleWidth, effectiveFontSize)
		local overflow = tabbedWidget.overflow or "wrap"
		if overflow == "wrap" then
			tabObj.console:setWrap(wrapWidth)
		else
			tabObj.console:setWrap(10000)
		end
	end

	-- Update wrap width for ellipsis truncation
	tabbedWidget._wrapWidth = mdw.calculateWrap(consoleWidth, mdw.getEffectiveFontSize(tabbedWidget.fontAdjust))

	-- Reflow text at new wrap width (skip for "hidden" mode)
	local overflow = tabbedWidget.overflow or "wrap"
	if overflow ~= "hidden" and tabbedWidget.reflow then tabbedWidget:reflow() end

	-- Position bottom resize handle at widget bottom (hidden when headless)
	if tabbedWidget.bottomResizeHandle then
		if tabbedWidget._headless then
			tabbedWidget.bottomResizeHandle:hide()
		else
			tabbedWidget.bottomResizeHandle:move(0, ch - cfg.widgetSplitterHeight)
			tabbedWidget.bottomResizeHandle:resize(cw, cfg.widgetSplitterHeight)
		end
	end
end

---------------------------------------------------------------------------
-- TAB STYLE HELPERS
-- Centralized tab button styling to avoid duplication across
-- selectTab, refreshTabBar, and creation.
---------------------------------------------------------------------------

-- kind: "group" (widget/stack tabs) or "channel" (tabbed-widget tabs, the default).
function mdw.applyTabActiveStyle(tabObj, kind)
	local cfg = mdw.config
	local style = (kind == "group") and mdw.styles.groupTabActive or mdw.styles.channelTabActive
	tabObj.button:setStyleSheet(style)
	tabObj.button:setFontSize(cfg.tabFontSize)
	tabObj.button:decho("<" .. cfg.tabActiveTextColor .. ">" .. tabObj.name)
end

function mdw.applyTabInactiveStyle(tabObj, kind)
	local cfg = mdw.config
	local style = (kind == "group") and mdw.styles.groupTabInactive or mdw.styles.channelTabInactive
	tabObj.button:setStyleSheet(style)
	tabObj.button:setFontSize(cfg.tabFontSize)
	tabObj.button:decho("<" .. cfg.tabInactiveTextColor .. ">" .. tabObj.name)
end

---------------------------------------------------------------------------
-- TAB DRAG HANDLING
-- Enables dragging tabs horizontally to reorder them.
-- Follows the same threshold-based click/drag pattern as widget dragging.
---------------------------------------------------------------------------

-- Build the shared-reorder context for a TabbedWidget's (equal-width) channel bar.
local function channelTabBarCtx(tw)
	local cfg = mdw.config
	return {
		tabs = tw.tabObjects,
		y = tw._headless and 0 or cfg.titleHeight,
		originX = function() return tw.container:get_x() end,
		barWidth = function() return tw.tabBar:get_width() end,
		widthOf = function() return tw.tabBar:get_width() / math.max(1, #tw.tabObjects) end,
		onReorder = function(fromIdx, toIdx) mdw.reorderTab(tw, fromIdx, toIdx) end,
		refresh = function() mdw.refreshTabBar(tw) end,
	}
end

--- Register click/move/release callbacks on a channel tab button. Click selects;
-- a horizontal drag reorders via the shared tab-bar reorder (no tear-out).
function mdw.setupTabDrag(tabbedWidget, tabObj)
	local labelName = tabObj.button.name
	local widgetName = tabbedWidget.name
	local tabName = tabObj.name

	setLabelClickCallback(labelName, function(event)
		local tw = mdw.widgets[widgetName]
		if not (tw and tw.tabsByName[tabName]) then return end
		mdw.tabDrag = {
			tabbedWidget = tw,
			tabObj = tw.tabsByName[tabName],
			startMouseX = event.globalX,
			hasMoved = false,
			ctx = channelTabBarCtx(tw),
		}
	end)

	setLabelMoveCallback(labelName, function(event)
		local d = mdw.tabDrag
		if not d or not d.tabObj or d.tabObj.name ~= tabName then return end
		if d.tabbedWidget ~= mdw.widgets[widgetName] then return end
		if #d.tabbedWidget.tabObjects < 2 then return end
		if not d.hasMoved then
			if math.abs(event.globalX - d.startMouseX) <= mdw.config.dragThreshold then return end
			d.hasMoved = true
			d.tabObj.button:setCursor(mudlet.cursor.ClosedHand)
		end
		mdw.barTabSlide(d.ctx, d.tabObj, event)
	end)

	setLabelReleaseCallback(labelName, function(event)
		local d = mdw.tabDrag
		mdw.tabDrag = nil
		if not d or not d.tabObj or d.tabObj.name ~= tabName then return end
		if not d.hasMoved then
			d.tabbedWidget:selectTab(d.tabObj.name)
			return
		end
		d.tabObj.button:setCursor(mudlet.cursor.PointingHand)
		mdw.barTabCommit(d.ctx, d.tabObj, event)
	end)
end

--- Reorder a tab within a TabbedWidget's arrays.
function mdw.reorderTab(tw, fromIndex, toIndex)
	local activeTabName = tw.tabObjects[tw.activeTabIndex].name

	local tabObj = table.remove(tw.tabObjects, fromIndex)
	table.insert(tw.tabObjects, toIndex, tabObj)

	local tabName = table.remove(tw.tabs, fromIndex)
	table.insert(tw.tabs, toIndex, tabName)

	-- Update indices and find where the active tab landed
	for i, tab in ipairs(tw.tabObjects) do
		tab.index = i
		if tab.name == activeTabName then
			tw.activeTabIndex = i
		end
	end
end

--- Reposition all tab buttons to canonical positions and restore styles.
function mdw.refreshTabBar(tw)
	local cfg = mdw.config
	local numTabs = #tw.tabObjects
	local tabBarWidth = tw.tabBar:get_width()
	local tabWidth = tabBarWidth / numTabs

	for i, tabObj in ipairs(tw.tabObjects) do
		tabObj.button:move((i - 1) * tabWidth, cfg.titleHeight)
		tabObj.button:resize(tabWidth, cfg.tabBarHeight)

		if i == tw.activeTabIndex then
			mdw.applyTabActiveStyle(tabObj)
		else
			mdw.applyTabInactiveStyle(tabObj)
		end

		tabObj.button:setCursor(mudlet.cursor.PointingHand)
	end
end

--- Apply a saved tab order to a TabbedWidget.
-- Handles missing/new tabs gracefully: saved tabs that still exist come first
-- in saved order, new tabs append at the end.
function mdw.applyTabOrder(tw, savedOrder)
	if not savedOrder or #savedOrder == 0 then return end

	-- Build set of existing tab names for quick lookup
	local existing = {}
	for _, tabObj in ipairs(tw.tabObjects) do
		existing[tabObj.name] = true
	end

	-- Build new order: saved tabs first (if they still exist), then any new tabs
	local ordered = {}
	local seen = {}
	for _, name in ipairs(savedOrder) do
		if existing[name] and not seen[name] then
			ordered[#ordered + 1] = name
			seen[name] = true
		end
	end
	for _, tabObj in ipairs(tw.tabObjects) do
		if not seen[tabObj.name] then
			ordered[#ordered + 1] = tabObj.name
		end
	end

	-- Skip if order hasn't changed
	local changed = false
	for i, name in ipairs(ordered) do
		if tw.tabObjects[i].name ~= name then
			changed = true
			break
		end
	end
	if not changed then return end

	local activeTabName = tw.tabObjects[tw.activeTabIndex].name

	-- Rebuild tabObjects and tabs arrays in new order
	local newTabObjects = {}
	local newTabs = {}
	for i, name in ipairs(ordered) do
		local tabObj = tw.tabsByName[name]
		tabObj.index = i
		newTabObjects[i] = tabObj
		newTabs[i] = name
	end
	tw.tabObjects = newTabObjects
	tw.tabs = newTabs

	-- Recalculate activeTabIndex
	for i, tab in ipairs(tw.tabObjects) do
		if tab.name == activeTabName then
			tw.activeTabIndex = i
			break
		end
	end

	mdw.refreshTabBar(tw)
end

---------------------------------------------------------------------------
-- TAB MANAGEMENT
---------------------------------------------------------------------------

function mdw.TabbedWidget:selectTab(tabName)
	local tabObj = self.tabsByName[tabName]
	if not tabObj then
		mdw.debugEcho("Tab not found: " .. tostring(tabName))
		return
	end

	-- Hide current tab's console and update button style
	local currentTab = self.tabObjects[self.activeTabIndex]
	if currentTab then
		currentTab.console:hide()
		mdw.applyTabInactiveStyle(currentTab)
	end

	-- Show new tab's console and update button style
	self.activeTabIndex = tabObj.index
	tabObj.console:show()
	tabObj.console:raise()
	mdw.applyTabActiveStyle(tabObj)

	-- Call onTabChange callback if set
	if self.onTabChange then
		self.onTabChange(self, tabName)
	end
end

function mdw.TabbedWidget:getTabIndex(tabName)
	local tabObj = self.tabsByName[tabName]
	return tabObj and tabObj.index or nil
end

function mdw.TabbedWidget:getActiveTab()
	local tabObj = self.tabObjects[self.activeTabIndex]
	return tabObj and tabObj.name or nil
end

function mdw.TabbedWidget:getTab(tabName)
	local tabObj = self.tabsByName[tabName]
	return tabObj and tabObj.console or nil
end

--- Programmatically reorder a tab from one position to another.
function mdw.TabbedWidget:reorderTab(fromIndex, toIndex)
	assert(type(fromIndex) == "number", "fromIndex must be a number")
	assert(type(toIndex) == "number", "toIndex must be a number")
	local numTabs = #self.tabObjects
	if fromIndex < 1 or fromIndex > numTabs then return end
	if toIndex < 1 or toIndex > numTabs then return end
	if fromIndex == toIndex then return end

	mdw.reorderTab(self, fromIndex, toIndex)
	mdw.refreshTabBar(self)
	mdw.saveLayout()
end

--- Return an array of tab names in their current display order.
function mdw.TabbedWidget:getTabOrder()
	local order = {}
	for i, tabObj in ipairs(self.tabObjects) do
		order[i] = tabObj.name
	end
	return order
end

---------------------------------------------------------------------------
-- ECHO METHODS - Active Tab
-- Methods for displaying text in the currently active tab.
---------------------------------------------------------------------------

--- Buffer an echo call on a tab object for later replay on reflow.
-- Skips buffering when overflow is "hidden" (no reflow needed).
local function bufferTabEcho(tabObj, method, text, overflow)
	if overflow == "hidden" then return end
	if not tabObj._buffer then tabObj._buffer = {} end
	tabObj._buffer[#tabObj._buffer + 1] = { method, text }
	local maxBuffer = mdw.config.maxEchoBuffer
	while #tabObj._buffer > maxBuffer do
		table.remove(tabObj._buffer, 1)
	end
end

--- Internal helper to call a method on the active tab's console.
local function callOnActiveTab(self, method, text)
	local tabObj = self.tabObjects[self.activeTabIndex]
	if tabObj then
		bufferTabEcho(tabObj, method, text, self.overflow)
		local displayText = text
		if self.overflow == "ellipsis" and self._wrapWidth then
			displayText = mdw.truncateFormatted(text, method, self._wrapWidth)
		end
		tabObj.console[method](tabObj.console, displayText)
	end
end

function mdw.TabbedWidget:echo(text)
	callOnActiveTab(self, "echo", text)
end

function mdw.TabbedWidget:cecho(text)
	callOnActiveTab(self, "cecho", text)
end

function mdw.TabbedWidget:decho(text)
	callOnActiveTab(self, "decho", text)
end

function mdw.TabbedWidget:hecho(text)
	callOnActiveTab(self, "hecho", text)
end

function mdw.TabbedWidget:clear()
	local tabObj = self.tabObjects[self.activeTabIndex]
	if tabObj then
		tabObj._buffer = {}
		tabObj.console:clear()
	end
end

---------------------------------------------------------------------------
-- ECHO METHODS - Specific Tab
-- Methods for displaying text in a specific tab (with "all" tab support).
---------------------------------------------------------------------------

--- Internal helper to echo to a tab with "all" tab support.
local function echoToTab(self, method, tabName, text)
	local tabObj = self.tabsByName[tabName]
	if tabObj then
		bufferTabEcho(tabObj, method, text, self.overflow)
		local displayText = text
		if self.overflow == "ellipsis" and self._wrapWidth then
			displayText = mdw.truncateFormatted(text, method, self._wrapWidth)
		end
		tabObj.console[method](tabObj.console, displayText)
	else
		mdw.debugEcho("TabbedWidget '%s': tab '%s' not found", self.name, tostring(tabName))
		return
	end

	-- Echo to "all" tab if set and this isn't the all tab
	if self.allTab and tabName ~= self.allTab then
		local allTabObj = self.tabsByName[self.allTab]
		if allTabObj then
			bufferTabEcho(allTabObj, method, text, self.overflow)
			local displayText = text
			if self.overflow == "ellipsis" and self._wrapWidth then
				displayText = mdw.truncateFormatted(text, method, self._wrapWidth)
			end
			allTabObj.console[method](allTabObj.console, displayText)
		end
	end
end

-- Also echoes to the "all" tab if set and the target is not the all tab.
function mdw.TabbedWidget:echoTo(tabName, text)
	echoToTab(self, "echo", tabName, text)
end

function mdw.TabbedWidget:cechoTo(tabName, text)
	echoToTab(self, "cecho", tabName, text)
end

function mdw.TabbedWidget:dechoTo(tabName, text)
	echoToTab(self, "decho", tabName, text)
end

function mdw.TabbedWidget:hechoTo(tabName, text)
	echoToTab(self, "hecho", tabName, text)
end

function mdw.TabbedWidget:clearTab(tabName)
	local tabObj = self.tabsByName[tabName]
	if tabObj then
		tabObj._buffer = {}
		tabObj.console:clear()
	end
end

function mdw.TabbedWidget:clearAll()
	for _, tabObj in ipairs(self.tabObjects) do
		tabObj._buffer = {}
		tabObj.console:clear()
	end
end

--- Replay buffered echo calls on all tabs after clearing content.
-- Used to reflow text at a new wrap width after resize.
-- For "ellipsis" mode, re-truncates each entry to current width.
-- For "hidden" mode, does nothing (no buffer).
function mdw.TabbedWidget:reflow()
	if self.overflow == "hidden" then return end
	for _, tabObj in ipairs(self.tabObjects) do
		if tabObj._buffer and #tabObj._buffer > 0 then
			tabObj.console:clear()
			for _, entry in ipairs(tabObj._buffer) do
				local text = entry[2]
				if self.overflow == "ellipsis" and self._wrapWidth then
					text = mdw.truncateFormatted(text, entry[1], self._wrapWidth)
				end
				tabObj.console[entry[1]](tabObj.console, text)
			end
		end
	end
end

---------------------------------------------------------------------------
-- DOCKING METHODS
-- Methods for controlling widget docking state.
---------------------------------------------------------------------------

-- The widget's home group (Stack) when grouped, else nil. Position / dock /
-- visibility operate on the group, since the group is the real dock occupant.
function mdw.TabbedWidget:_group()
	return self.stackId and mdw.widgets[self.stackId] or nil
end

function mdw.TabbedWidget:dock(side, row)
	mdw.dockWidgetClass(self:_group() or self, side, row)
end

function mdw.TabbedWidget:undock(x, y)
	mdw.undockWidgetClass(self:_group() or self, x, y)
end

function mdw.TabbedWidget:isDocked()
	return (self:_group() or self).docked
end

function mdw.TabbedWidget:setFill(enabled)
	mdw.setFillClass(self:_group() or self, enabled)
end

function mdw.TabbedWidget:isFill()
	return (self:_group() or self).fill == true
end

function mdw.TabbedWidget:setWidthLocked(enabled)
	mdw.setWidthLockedClass(self:_group() or self, enabled)
end

function mdw.TabbedWidget:isWidthLocked()
	return (self:_group() or self).widthLocked == true
end

---------------------------------------------------------------------------
-- VISIBILITY METHODS
-- Methods for showing and hiding widgets.
---------------------------------------------------------------------------

function mdw.TabbedWidget:show()
	local g = self:_group()
	-- A widget must never render bare: wrap it in its home group first.
	if not g and mdw.wrapInHomeStack then
		mdw.wrapInHomeStack(self)
		g = self:_group()
	end
	if g then
		mdw.showStack(g, self.name)
		return
	end
	local selfRef = self
	mdw.showWidgetClass(self, function()
		-- Show the active tab's console
		local activeTab = selfRef.tabObjects[selfRef.activeTabIndex]
		if activeTab then
			activeTab.console:show()
		end
	end)
end

function mdw.TabbedWidget:hide()
	local g = self:_group()
	if g then
		mdw.hideStack(g)
	else
		mdw.hideWidgetClass(self)
	end
end

function mdw.TabbedWidget:toggle()
	if self:isVisible() then
		self:hide()
	else
		self:show()
	end
end

function mdw.TabbedWidget:isVisible()
	local g = self:_group()
	if g then
		return g.visible ~= false and g.activeMember == self.name
	end
	return self.visible ~= false
end

---------------------------------------------------------------------------
-- APPEARANCE METHODS
-- Methods for customizing widget appearance.
---------------------------------------------------------------------------

function mdw.TabbedWidget:setTitle(title)
	self.title = title
	mdw.renderWidgetTitle(self)
	local g = self:_group()
	if g and g.tabsByName and g.tabsByName[self.name] then
		g.tabsByName[self.name].name = title
		if mdw.refreshStackTabBar then mdw.refreshStackTabBar(g) end
	end
end

function mdw.TabbedWidget:setTitleStyleSheet(css)
	self.titleBar:setStyleSheet(css)
end

--- Set a custom stylesheet for the content background area.
-- Note: This affects the background label behind the tab consoles.
function mdw.TabbedWidget:setContentStyleSheet(css)
	if self.contentBg then
		self.contentBg:setStyleSheet(css)
	end
end

function mdw.TabbedWidget:setFont(font, size)
	for _, tabObj in ipairs(self.tabObjects) do
		if font then
			tabObj.console:setFont(font)
		end
		if size then
			tabObj.console:setFontSize(size)
		end
	end
end

function mdw.TabbedWidget:setFontAdjust(adjust)
	self.fontAdjust = adjust or 0
	mdw.applyWidgetFontSize(self)
	mdw.saveLayout()
end

---------------------------------------------------------------------------
-- SIZE AND POSITION METHODS
-- Methods for controlling widget geometry.
---------------------------------------------------------------------------

function mdw.TabbedWidget:resize(width, height)
	local g = self:_group()
	if g then
		mdw.resizeWidgetClass(g, width, height, mdw.resizeWidgetContent)
	else
		mdw.resizeWidgetClass(self, width, height, mdw.resizeTabbedWidgetContent)
	end
end

function mdw.TabbedWidget:move(x, y)
	local g = self:_group()
	if g then
		if g.docked then return end
		g.container:move(x, y)
		if mdw.resizeStackContent then mdw.resizeStackContent(g) end
		mdw.raiseWidgetElements(g)
	else
		mdw.moveWidgetClass(self, x, y)
	end
end

function mdw.TabbedWidget:getPosition()
	local t = self:_group() or self
	return t.container:get_x(), t.container:get_y()
end

function mdw.TabbedWidget:getSize()
	local t = self:_group() or self
	return t.container:get_width(), t.container:get_height()
end

function mdw.TabbedWidget:raise()
	mdw.raiseWidgetElements(self:_group() or self)
	mdw.applyZOrder()
end

---------------------------------------------------------------------------
-- DESTRUCTION
-- Methods for removing widgets.
---------------------------------------------------------------------------

function mdw.TabbedWidget:destroy()
	mdw.destroyWidgetClass(self)
end

---------------------------------------------------------------------------
-- CLASS METHODS
-- Static methods for working with tabbed widgets.
---------------------------------------------------------------------------

function mdw.TabbedWidget.get(name)
	local widget = mdw.widgets[name]
	-- Only return if it's a TabbedWidget
	if widget and widget.isTabbed then
		return widget
	end
	return nil
end

function mdw.TabbedWidget.list()
	local names = {}
	for name, widget in pairs(mdw.widgets) do
		if widget.isTabbed then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names
end
