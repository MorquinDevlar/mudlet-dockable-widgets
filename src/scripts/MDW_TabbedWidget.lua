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

  Dependencies: MDW_Config.lua, MDW_Init.lua, MDW_Widgets.lua, MDW_Widget.lua
]]

---------------------------------------------------------------------------
-- TABBED WIDGET CLASS
---------------------------------------------------------------------------

mdw.TabbedWidget = mdw.TabbedWidget or {}
mdw.TabbedWidget.__index = mdw.TabbedWidget

--- Default configuration for new tabbed widgets.
mdw.TabbedWidget.defaults = {
  height = nil,           -- Uses mdw.config.widgetHeight if not specified
  dock = nil,             -- nil = floating, "left" or "right" = docked
  x = nil,                -- Initial X position (uses config.floatingStartX if nil)
  y = nil,                -- Initial Y position (uses config.floatingStartY if nil)
  visible = true,         -- Whether widget starts visible
  row = nil,              -- Row in dock (auto-assigned if nil)
  rowPosition = 0,        -- Position within row for side-by-side
  tabs = {},              -- Array of tab names
  allTab = nil,           -- Name of "all" tab (receives copies of messages)
  activeTab = nil,        -- Initially active tab name (defaults to first)
}

--- Create a new TabbedWidget instance.
-- @tparam table cons Configuration table with the following options:
--   - name (string, required): Unique identifier for the widget
--   - title (string, optional): Display title, defaults to name
--   - tabs (table, required): Array of tab names
--   - allTab (string, optional): Name of tab that receives all messages
--   - activeTab (string, optional): Initially active tab (defaults to first)
--   - dock (string, optional): "left", "right", or nil for floating
--   - x (number, optional): Initial X position for floating widgets
--   - y (number, optional): Initial Y position for floating widgets
--   - height (number, optional): Widget height in pixels
--   - visible (boolean, optional): Start visible? Default true
--   - row (number, optional): Row index in dock (auto-assigned if nil)
--   - rowPosition (number, optional): Position within row
--   - onClose (function, optional): Callback when widget is hidden
--   - onTabChange (function, optional): Callback when tab is switched
-- @return TabbedWidget instance
function mdw.TabbedWidget:new(cons)
  cons = cons or {}

  -- Validate required fields
  assert(type(cons.name) == "string" and cons.name ~= "", "TabbedWidget name is required")
  assert(type(cons.tabs) == "table" and #cons.tabs > 0, "TabbedWidget requires at least one tab")

  -- Return existing widget if one with this name already exists (EMCO pattern)
  if mdw.widgets[cons.name] then
    local existing = mdw.widgets[cons.name]
    if existing._tabbedClass then
      return existing._tabbedClass
    end
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
  self.tabObjects = {}       -- Array of tab objects: {name, button, console}
  self.tabsByName = {}       -- Lookup table: tabName -> tab object
  self.activeTabIndex = 1    -- Index of currently active tab

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
      x = winW - cfg.rightDockWidth + cfg.splitterWidth + cfg.widgetMargin
    end
    y = cfg.headerHeight + cfg.widgetMargin
  end

  -- Create the underlying widget structure
  self._widget = mdw.createTabbedWidgetInternal(self, x, y)

  -- Copy widget properties
  self.container = self._widget.container
  self.titleBar = self._widget.titleBar
  self.tabBar = self._widget.tabBar
  self.resizeLeft = self._widget.resizeLeft
  self.resizeRight = self._widget.resizeRight
  self.resizeTop = self._widget.resizeTop
  self.resizeBottom = self._widget.resizeBottom
  self.bottomResizeHandle = self._widget.bottomResizeHandle

  -- Apply height
  if self.height ~= cfg.widgetHeight then
    self.container:resize(nil, self.height)
    mdw.resizeTabbedWidgetContent(self, self.container:get_width(), self.height)
  end

  -- Register in mdw.widgets
  mdw.widgets[self.name] = self._widget

  -- Copy class reference to internal widget for compatibility
  self._widget._tabbedClass = self

  -- Apply docking
  if cons.dock then
    self:dock(cons.dock, cons.row)
  else
    self._widget.docked = nil
    mdw.showResizeHandles(self._widget)
  end

  -- Apply visibility
  if not self.visible then
    self:hide()
  end

  -- Select initial tab
  local initialTab = cons.activeTab or self.tabs[1]
  self:selectTab(initialTab)

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
-- @param tabbedWidget TabbedWidget The parent tabbed widget instance
-- @param x number Initial X position
-- @param y number Initial Y position
-- @return table Internal widget structure
function mdw.createTabbedWidgetInternal(tabbedWidget, x, y)
  local cfg = mdw.config
  local name = tabbedWidget.name
  local title = tabbedWidget.title

  local widget = {
    name = name,
    title = title,
    docked = nil,
    visible = true,
    isTabbed = true,
  }

  -- Calculate dimensions
  local totalMargin = cfg.widgetMargin * 2
  local containerWidth = cfg.leftDockWidth - totalMargin - cfg.splitterWidth
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

    -- Tab button
    local tabButton = mdw.trackElement(Geyser.Label:new({
      name = "MDW_" .. name .. "_Tab_" .. tabName,
      x = tabX,
      y = cfg.titleHeight,
      width = tabWidth,
      height = cfg.tabBarHeight,
    }, widget.container))
    tabButton:setStyleSheet(mdw.styles.tabInactive)
    tabButton:decho("<" .. cfg.tabInactiveTextColor .. ">" .. tabName)
    tabButton:setCursor(mudlet.cursor.PointingHand)

    -- Tab console (MiniConsole for scrollable text)
    -- Offset by padding to create left and top padding
    local consoleName = "MDW_" .. name .. "_Console_" .. tabName
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
    tabConsole:hide()  -- All consoles start hidden

    -- Create tab object
    local tabObj = {
      name = tabName,
      button = tabButton,
      console = tabConsole,
      index = i,
    }

    tabbedWidget.tabObjects[i] = tabObj
    tabbedWidget.tabsByName[tabName] = tabObj

    -- Set up tab click callback
    local tabIndex = i
    setLabelClickCallback("MDW_" .. name .. "_Tab_" .. tabName, function()
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
  widget.bottomResizeHandle:setStyleSheet([[background-color: transparent;]])
  widget.bottomResizeHandle:setCursor(mudlet.cursor.ResizeVertical)
  widget.bottomResizeHandle:hide()  -- Hidden by default, shown when docked

  -- Create resize borders
  mdw.createResizeBorders(widget)

  -- Set up drag callbacks
  mdw.setupWidgetDrag(widget)

  -- Set up docked resize handle callbacks
  mdw.setupDockedResizeHandle(widget)

  return widget
end

--- Resize tabbed widget content after container changes.
-- @param tabbedWidget TabbedWidget The widget to resize
-- @param targetWidth number Optional explicit width (avoids Geyser timing issues)
-- @param targetHeight number Optional explicit height
function mdw.resizeTabbedWidgetContent(tabbedWidget, targetWidth, targetHeight)
  local cfg = mdw.config

  -- Use provided dimensions or fall back to container dimensions
  local cw = targetWidth or tabbedWidget.container:get_width()
  local ch = targetHeight or tabbedWidget.container:get_height()

  -- Reserve space for bottom resize handle when docked
  local widget = tabbedWidget._widget
  local resizeHandleHeight = (widget and widget.docked) and cfg.widgetSplitterHeight or 0
  local contentAreaHeight = ch - cfg.titleHeight - cfg.tabBarHeight - resizeHandleHeight
  local consoleWidth = cw - cfg.contentPaddingLeft
  local consoleHeight = contentAreaHeight - cfg.contentPaddingTop

  -- Resize title bar
  tabbedWidget.titleBar:move(0, 0)
  tabbedWidget.titleBar:resize(cw, cfg.titleHeight)

  -- Resize tab bar
  tabbedWidget.tabBar:move(0, cfg.titleHeight)
  tabbedWidget.tabBar:resize(cw, cfg.tabBarHeight)

  -- Resize background label that fills the padding area
  if widget and widget.contentBg then
    widget.contentBg:move(0, cfg.titleHeight + cfg.tabBarHeight)
    widget.contentBg:resize(cw, contentAreaHeight)
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
    tabObj.console:setWrap(mdw.calculateWrap(consoleWidth))
  end

  -- Position bottom resize handle at widget bottom
  if widget and widget.bottomResizeHandle then
    widget.bottomResizeHandle:move(0, ch - cfg.widgetSplitterHeight)
    widget.bottomResizeHandle:resize(cw, cfg.widgetSplitterHeight)
  end
end

---------------------------------------------------------------------------
-- TAB MANAGEMENT
---------------------------------------------------------------------------

--- Select a tab by name.
-- @tparam string tabName The name of the tab to select
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
    currentTab.button:decho("<" .. cfg.tabInactiveTextColor .. ">" .. currentTab.name)
  end

  -- Show new tab's console and update button style
  self.activeTabIndex = tabObj.index
  tabObj.console:show()
  tabObj.console:raise()
  tabObj.button:setStyleSheet(mdw.styles.tabActive)
  tabObj.button:decho("<" .. cfg.tabActiveTextColor .. ">" .. tabObj.name)

  -- Call onTabChange callback if set
  if self.onTabChange then
    self.onTabChange(self, tabName)
  end
end

--- Get the index of a tab by name.
-- @tparam string tabName The tab name
-- @return number|nil The tab index or nil if not found
function mdw.TabbedWidget:getTabIndex(tabName)
  local tabObj = self.tabsByName[tabName]
  return tabObj and tabObj.index or nil
end

--- Get the currently active tab name.
-- @return string The active tab name
function mdw.TabbedWidget:getActiveTab()
  local tabObj = self.tabObjects[self.activeTabIndex]
  return tabObj and tabObj.name or nil
end

--- Get a tab's MiniConsole directly.
-- @tparam string tabName The tab name
-- @return Geyser.MiniConsole|nil The console or nil if not found
function mdw.TabbedWidget:getTab(tabName)
  local tabObj = self.tabsByName[tabName]
  return tabObj and tabObj.console or nil
end

---------------------------------------------------------------------------
-- ECHO METHODS - Active Tab
-- Methods for displaying text in the currently active tab.
---------------------------------------------------------------------------

--- Internal helper to call a method on the active tab's console.
local function callOnActiveTab(self, method, ...)
  local tabObj = self.tabObjects[self.activeTabIndex]
  if tabObj then
    tabObj.console[method](tabObj.console, ...)
  end
end

--- Echo plain text to the active tab's console.
-- @tparam string text The text to display
function mdw.TabbedWidget:echo(text)
  callOnActiveTab(self, "echo", text)
end

--- Echo text with cecho color codes to the active tab.
-- @tparam string text The text with color codes
function mdw.TabbedWidget:cecho(text)
  callOnActiveTab(self, "cecho", text)
end

--- Echo text with decho color codes to the active tab.
-- @tparam string text The text with RGB codes
function mdw.TabbedWidget:decho(text)
  callOnActiveTab(self, "decho", text)
end

--- Echo text with hecho color codes to the active tab.
-- @tparam string text The text with hex codes
function mdw.TabbedWidget:hecho(text)
  callOnActiveTab(self, "hecho", text)
end

--- Clear the active tab's console.
function mdw.TabbedWidget:clear()
  callOnActiveTab(self, "clear")
end

---------------------------------------------------------------------------
-- ECHO METHODS - Specific Tab
-- Methods for displaying text in a specific tab (with "all" tab support).
---------------------------------------------------------------------------

--- Internal helper to echo to a tab with "all" tab support.
-- @param self TabbedWidget instance
-- @param method string The echo method name ("echo", "cecho", "decho", "hecho")
-- @param tabName string The target tab name
-- @param text string The text to display
local function echoToTab(self, method, tabName, text)
  local tabObj = self.tabsByName[tabName]
  if tabObj then
    tabObj.console[method](tabObj.console, text)
  end

  -- Echo to "all" tab if set and this isn't the all tab
  if self.allTab and tabName ~= self.allTab then
    local allTabObj = self.tabsByName[self.allTab]
    if allTabObj then
      allTabObj.console[method](allTabObj.console, text)
    end
  end
end

--- Echo plain text to a specific tab.
-- Also echoes to the "all" tab if set and the target is not the all tab.
-- @tparam string tabName The target tab name
-- @tparam string text The text to display
function mdw.TabbedWidget:echoTo(tabName, text)
  echoToTab(self, "echo", tabName, text)
end

--- Echo text with cecho color codes to a specific tab.
-- @tparam string tabName The target tab name
-- @tparam string text The text with color codes
function mdw.TabbedWidget:cechoTo(tabName, text)
  echoToTab(self, "cecho", tabName, text)
end

--- Echo text with decho color codes to a specific tab.
-- @tparam string tabName The target tab name
-- @tparam string text The text with RGB codes
function mdw.TabbedWidget:dechoTo(tabName, text)
  echoToTab(self, "decho", tabName, text)
end

--- Echo text with hecho color codes to a specific tab.
-- @tparam string tabName The target tab name
-- @tparam string text The text with hex codes
function mdw.TabbedWidget:hechoTo(tabName, text)
  echoToTab(self, "hecho", tabName, text)
end

--- Clear a specific tab's console.
-- @tparam string tabName The tab name to clear
function mdw.TabbedWidget:clearTab(tabName)
  local tabObj = self.tabsByName[tabName]
  if tabObj then
    tabObj.console:clear()
  end
end

--- Clear all tab consoles.
function mdw.TabbedWidget:clearAll()
  for _, tabObj in ipairs(self.tabObjects) do
    tabObj.console:clear()
  end
end

---------------------------------------------------------------------------
-- DOCKING METHODS
-- Methods for controlling widget docking state.
---------------------------------------------------------------------------

--- Dock the widget to a sidebar.
-- @tparam string side "left" or "right"
-- @tparam number row Optional row index (auto-assigned if nil)
function mdw.TabbedWidget:dock(side, row)
  assert(side == "left" or side == "right", "dock side must be 'left' or 'right'")

  self._widget.docked = side

  if row then
    self._widget.row = row
    self._widget.rowPosition = 0
  else
    local docked = mdw.getDockedWidgets(side, self._widget)
    local maxRow = -1
    for _, w in ipairs(docked) do
      maxRow = math.max(maxRow, w.row or 0)
    end
    self._widget.row = maxRow + 1
    self._widget.rowPosition = 0
  end

  mdw.hideResizeHandles(self._widget)
  mdw.reorganizeDock(side)
end

--- Undock the widget (make it floating).
-- @tparam number x Optional X position
-- @tparam number y Optional Y position
function mdw.TabbedWidget:undock(x, y)
  local previousDock = self._widget.docked

  self._widget.docked = nil
  self._widget.row = nil
  self._widget.rowPosition = nil

  if x and y then
    self.container:move(x, y)
  end

  mdw.showResizeHandles(self._widget)
  mdw.updateResizeBorders(self._widget)

  if previousDock then
    mdw.reorganizeDock(previousDock)
  end
end

--- Check if the widget is currently docked.
-- @return string|nil The dock side ("left" or "right") or nil if floating
function mdw.TabbedWidget:isDocked()
  return self._widget.docked
end

---------------------------------------------------------------------------
-- VISIBILITY METHODS
-- Methods for showing and hiding widgets.
---------------------------------------------------------------------------

--- Show the widget.
function mdw.TabbedWidget:show()
  self._widget.visible = true
  self.container:show()

  if self._widget.docked then
    mdw.hideResizeHandles(self._widget)
    mdw.reorganizeDock(self._widget.docked)
  else
    mdw.showResizeHandles(self._widget)
  end

  -- Show the active tab's console
  local activeTab = self.tabObjects[self.activeTabIndex]
  if activeTab then
    activeTab.console:show()
    activeTab.console:raise()
  end

  if mdw.updateWidgetsMenuState then
    mdw.updateWidgetsMenuState()
  end
end

--- Hide the widget.
function mdw.TabbedWidget:hide()
  self._widget.visible = false
  self.container:hide()
  mdw.hideResizeHandles(self._widget)

  -- Reorganize docks (will update vertical splitters for side-by-side widgets)
  if self._widget.docked then
    mdw.reorganizeDock(self._widget.docked)
  end

  if mdw.updateWidgetsMenuState then
    mdw.updateWidgetsMenuState()
  end

  if self.onClose then
    self.onClose(self)
  end
end

--- Toggle widget visibility.
function mdw.TabbedWidget:toggle()
  if self._widget.visible then
    self:hide()
  else
    self:show()
  end
end

--- Check if the widget is visible.
-- @return boolean
function mdw.TabbedWidget:isVisible()
  return self._widget.visible ~= false
end

---------------------------------------------------------------------------
-- APPEARANCE METHODS
-- Methods for customizing widget appearance.
---------------------------------------------------------------------------

--- Set the widget's title.
-- @tparam string title The new title
function mdw.TabbedWidget:setTitle(title)
  self.title = title
  self._widget.title = title
  self.titleBar:decho("<" .. mdw.config.headerTextColor .. ">" .. title)
end

--- Set a custom stylesheet for the title bar.
-- @tparam string css Qt stylesheet string
function mdw.TabbedWidget:setTitleStyleSheet(css)
  self.titleBar:setStyleSheet(css)
end

--- Set the font for all tab consoles.
-- @tparam string font Font name
-- @tparam number size Font size (optional)
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

--- Resize the widget.
-- @tparam number|nil width New width (nil to keep current)
-- @tparam number|nil height New height (nil to keep current)
function mdw.TabbedWidget:resize(width, height)
  self.container:resize(width, height)
  -- Get actual dimensions (may have been nil in the resize call)
  local actualWidth = width or self.container:get_width()
  local actualHeight = height or self.container:get_height()
  mdw.resizeTabbedWidgetContent(self, actualWidth, actualHeight)

  if self._widget.docked then
    mdw.reorganizeDock(self._widget.docked)
  else
    mdw.updateResizeBorders(self._widget)
  end
end

--- Move the widget (only works for floating widgets).
-- @tparam number x New X position
-- @tparam number y New Y position
function mdw.TabbedWidget:move(x, y)
  if self._widget.docked then
    mdw.debugEcho("Cannot move docked widget - undock it first")
    return
  end

  self.container:move(x, y)
  mdw.updateResizeBorders(self._widget)
end

--- Get the widget's current position.
-- @return number x, number y
function mdw.TabbedWidget:getPosition()
  return self.container:get_x(), self.container:get_y()
end

--- Get the widget's current size.
-- @return number width, number height
function mdw.TabbedWidget:getSize()
  return self.container:get_width(), self.container:get_height()
end

--- Raise the widget above others.
function mdw.TabbedWidget:raise()
  mdw.raiseWidget(self._widget)
end

---------------------------------------------------------------------------
-- DESTRUCTION
-- Methods for removing widgets.
---------------------------------------------------------------------------

--- Destroy the widget and clean up resources.
function mdw.TabbedWidget:destroy()
  self:hide()

  -- Remove from mdw.widgets
  mdw.widgets[self.name] = nil

  -- Hide resize borders
  if self.resizeLeft then self.resizeLeft:hide() end
  if self.resizeRight then self.resizeRight:hide() end
  if self.resizeTop then self.resizeTop:hide() end
  if self.resizeBottom then self.resizeBottom:hide() end

  -- Hide container
  self.container:hide()

  -- Rebuild menu
  if mdw.rebuildWidgetsMenu then
    mdw.rebuildWidgetsMenu()
  end
end

---------------------------------------------------------------------------
-- CLASS METHODS
-- Static methods for working with tabbed widgets.
---------------------------------------------------------------------------

--- Get a tabbed widget by name.
-- @tparam string name Widget name
-- @return TabbedWidget instance or nil
function mdw.TabbedWidget.get(name)
  local widget = mdw.widgets[name]
  if widget and widget._tabbedClass then
    return widget._tabbedClass
  end
  return nil
end

--- Get all tabbed widget names.
-- @return table Array of widget names
function mdw.TabbedWidget.list()
  local names = {}
  for name, widget in pairs(mdw.widgets) do
    if widget._tabbedClass then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end
