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
	self.bottomResizeHandle = internalWidget.bottomResizeHandle

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
		self._wrapWidth = mdw.calculateWrap(self.tabObjects[1].console:get_width())
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

	-- Restore active tab from saved layout or use provided/default
	if applied and saved and saved.activeTab then
		self:selectTab(saved.activeTab)
	else
		local initialTab = cons.activeTab or self.tabs[1]
		self:selectTab(initialTab)
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
	widget.titleBar:decho("<" .. cfg.headerTextColor .. ">" .. title)
	widget.titleBar:setCursor(mudlet.cursor.OpenHand)

	-- Tab bar container
	widget.tabBar = mdw.trackElement(Geyser.Label:new({
		name = "MDW_" .. name .. "_TabBar",
		x = 0,
		y = cfg.titleHeight,
		width = actualWidth,
		height = cfg.tabBarHeight,
	}, widget.container))
	widget.tabBar:setStyleSheet(mdw.styles.tabBar)

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
		tabButton:setStyleSheet(mdw.styles.tabInactive)
		tabButton:setFontSize(cfg.tabFontSize)
		tabButton:decho("<" .. cfg.tabInactiveTextColor .. ">" .. tabName)
		tabButton:setCursor(mudlet.cursor.PointingHand)

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
		tabConsole:setFontSize(cfg.fontSize)
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

		-- Set up tab click callback
		setLabelClickCallback("MDW_" .. name .. "_Tab_" .. safeTabName, function()
			tabbedWidget:selectTab(tabName)
		end)
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

	-- Reserve space for bottom resize handle when docked
	local resizeHandleHeight = tabbedWidget.docked and cfg.widgetSplitterHeight or 0
	local contentAreaHeight = ch - cfg.titleHeight - cfg.tabBarHeight - resizeHandleHeight
	local contentAreaWidth = cw -- Full width - splitters are separate elements now
	local consoleWidth = contentAreaWidth - cfg.contentPaddingLeft
	local consoleHeight = contentAreaHeight - cfg.contentPaddingTop

	-- Resize title bar
	tabbedWidget.titleBar:move(0, 0)
	tabbedWidget.titleBar:resize(cw, cfg.titleHeight)

	-- Resize tab bar
	tabbedWidget.tabBar:move(0, cfg.titleHeight)
	tabbedWidget.tabBar:resize(cw, cfg.tabBarHeight)

	-- Resize background label that fills the padding area (not overlapping right splitter)
	if tabbedWidget.contentBg then
		tabbedWidget.contentBg:move(0, cfg.titleHeight + cfg.tabBarHeight)
		tabbedWidget.contentBg:resize(contentAreaWidth, contentAreaHeight)
	end

	-- Resize tabs
	local numTabs = #tabbedWidget.tabObjects
	local tabWidth = cw / numTabs

	for i, tabObj in ipairs(tabbedWidget.tabObjects) do
		local tabX = (i - 1) * tabWidth

		-- Resize tab button
		tabObj.button:move(tabX, cfg.titleHeight)
		tabObj.button:resize(tabWidth, cfg.tabBarHeight)

		-- Resize tab console
		tabObj.console:move(cfg.contentPaddingLeft, cfg.titleHeight + cfg.tabBarHeight + cfg.contentPaddingTop)
		tabObj.console:resize(consoleWidth, consoleHeight)
		local wrapWidth = mdw.calculateWrap(consoleWidth)
		local overflow = tabbedWidget.overflow or "wrap"
		if overflow == "wrap" then
			tabObj.console:setWrap(wrapWidth)
		else
			tabObj.console:setWrap(10000)
		end
	end

	-- Update wrap width for ellipsis truncation
	tabbedWidget._wrapWidth = mdw.calculateWrap(consoleWidth)

	-- Reflow text at new wrap width (skip for "hidden" mode)
	local overflow = tabbedWidget.overflow or "wrap"
	if overflow ~= "hidden" and tabbedWidget.reflow then tabbedWidget:reflow() end

	-- Position bottom resize handle at widget bottom
	if tabbedWidget.bottomResizeHandle then
		tabbedWidget.bottomResizeHandle:move(0, ch - cfg.widgetSplitterHeight)
		tabbedWidget.bottomResizeHandle:resize(cw, cfg.widgetSplitterHeight)
	end
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

	local cfg = mdw.config

	-- Hide current tab's console and update button style
	local currentTab = self.tabObjects[self.activeTabIndex]
	if currentTab then
		currentTab.console:hide()
		currentTab.button:setStyleSheet(mdw.styles.tabInactive)
		currentTab.button:setFontSize(cfg.tabFontSize)
		currentTab.button:decho("<" .. cfg.tabInactiveTextColor .. ">" .. currentTab.name)
	end

	-- Show new tab's console and update button style
	self.activeTabIndex = tabObj.index
	tabObj.console:show()
	tabObj.console:raise()
	tabObj.button:setStyleSheet(mdw.styles.tabActive)
	tabObj.button:setFontSize(cfg.tabFontSize)
	tabObj.button:decho("<" .. cfg.tabActiveTextColor .. ">" .. tabObj.name)

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

function mdw.TabbedWidget:dock(side, row)
	mdw.dockWidgetClass(self, side, row)
end

function mdw.TabbedWidget:undock(x, y)
	mdw.undockWidgetClass(self, x, y)
end

function mdw.TabbedWidget:isDocked()
	return self.docked
end

---------------------------------------------------------------------------
-- VISIBILITY METHODS
-- Methods for showing and hiding widgets.
---------------------------------------------------------------------------

function mdw.TabbedWidget:show()
	local selfRef = self
	mdw.showWidgetClass(self, function()
		-- Show the active tab's console
		local activeTab = selfRef.tabObjects[selfRef.activeTabIndex]
		if activeTab then
			activeTab.console:show()
			activeTab.console:raise()
		end
	end)
end

function mdw.TabbedWidget:hide()
	mdw.hideWidgetClass(self)
end

function mdw.TabbedWidget:toggle()
	if self.visible then
		self:hide()
	else
		self:show()
	end
end

function mdw.TabbedWidget:isVisible()
	return self.visible ~= false
end

---------------------------------------------------------------------------
-- APPEARANCE METHODS
-- Methods for customizing widget appearance.
---------------------------------------------------------------------------

function mdw.TabbedWidget:setTitle(title)
	self.title = title
	self.titleBar:decho("<" .. mdw.config.headerTextColor .. ">" .. title)
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

---------------------------------------------------------------------------
-- SIZE AND POSITION METHODS
-- Methods for controlling widget geometry.
---------------------------------------------------------------------------

function mdw.TabbedWidget:resize(width, height)
	mdw.resizeWidgetClass(self, width, height, mdw.resizeTabbedWidgetContent)
end

function mdw.TabbedWidget:move(x, y)
	mdw.moveWidgetClass(self, x, y)
end

function mdw.TabbedWidget:getPosition()
	return self.container:get_x(), self.container:get_y()
end

function mdw.TabbedWidget:getSize()
	return self.container:get_width(), self.container:get_height()
end

function mdw.TabbedWidget:raise()
	mdw.raiseWidget(self)
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
