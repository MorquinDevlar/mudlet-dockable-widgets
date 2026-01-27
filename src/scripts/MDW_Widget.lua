--[[
  MDW_Widget.lua
  Widget class for MDW (Mudlet Dockable Widgets).

  Provides an object-oriented API for creating and managing dockable widgets,
  inspired by the EMCO pattern from Demonnic's MDK.

  Usage:
    local myWidget = mdw.Widget:new({
      name = "Inventory",
      title = "My Inventory",
      dock = "left",        -- "left", "right", or nil for floating
      x = 100, y = 100,     -- initial position (for floating)
      height = 200,         -- optional, default from mdw.config
    })

    -- Echo to the widget's content area
    myWidget:echo("Hello!")
    myWidget:cecho("<red>Colored text")
    myWidget:decho("<255,0,0>RGB text")

    -- Control the widget
    myWidget:dock("right")
    myWidget:undock()
    myWidget:show()
    myWidget:hide()
    myWidget:setTitle("New Title")

  Dependencies: MDW_Config.lua, MDW_Init.lua, MDW_Widgets.lua must be loaded first
]]

---------------------------------------------------------------------------
-- WIDGET CLASS
---------------------------------------------------------------------------

mdw.Widget = mdw.Widget or {}
mdw.Widget.__index = mdw.Widget

--- Default configuration for new widgets.
-- These can be overridden in the constraints table passed to :new()
-- Note: x and y defaults are set dynamically from mdw.config in :new()
mdw.Widget.defaults = {
  height = nil,           -- Uses mdw.config.widgetHeight if not specified
  dock = nil,             -- nil = floating, "left" or "right" = docked
  x = nil,                -- Initial X position (uses config.floatingStartX if nil)
  y = nil,                -- Initial Y position (uses config.floatingStartY if nil)
  visible = true,         -- Whether widget starts visible
  row = nil,              -- Row in dock (auto-assigned if nil)
  rowPosition = 0,        -- Position within row for side-by-side
}

--- Create a new Widget instance.
-- @tparam table cons Configuration table with the following options:
--   - name (string, required): Unique identifier for the widget
--   - title (string, optional): Display title, defaults to name
--   - dock (string, optional): "left", "right", or nil for floating
--   - x (number, optional): Initial X position for floating widgets
--   - y (number, optional): Initial Y position for floating widgets
--   - height (number, optional): Widget height in pixels
--   - visible (boolean, optional): Start visible? Default true
--   - row (number, optional): Row index in dock (auto-assigned if nil)
--   - rowPosition (number, optional): Position within row
--   - onClose (function, optional): Callback when widget is hidden
--   - onClick (function, optional): Callback when content area is clicked
-- @return Widget instance
function mdw.Widget:new(cons)
  cons = cons or {}

  -- Validate required fields
  assert(type(cons.name) == "string" and cons.name ~= "", "Widget name is required")

  -- Return existing widget if one with this name already exists
  -- This allows scripts to be reloaded without errors (EMCO pattern)
  if mdw.widgets[cons.name] then
    local existing = mdw.widgets[cons.name]
    if existing._class then
      return existing._class
    end
  end

  -- Apply defaults
  local self = setmetatable({}, mdw.Widget)
  for k, v in pairs(mdw.Widget.defaults) do
    self[k] = cons[k] ~= nil and cons[k] or v
  end

  -- Required/computed fields
  self.name = cons.name
  self.title = cons.title or cons.name
  self.height = cons.height or mdw.config.widgetHeight
  self.onClose = cons.onClose
  self.onClick = cons.onClick

  -- Determine initial position (use config defaults if not specified)
  local cfg = mdw.config
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

  -- Create the underlying widget using existing infrastructure
  local widget = mdw.createWidget(self.name, self.title, x, y)

  -- Copy the internal widget properties
  self._widget = widget
  self.container = widget.container
  self.titleBar = widget.titleBar
  self.content = widget.content
  self.mapper = widget.mapper
  self.resizeLeft = widget.resizeLeft
  self.resizeRight = widget.resizeRight
  self.resizeTop = widget.resizeTop
  self.resizeBottom = widget.resizeBottom
  self.bottomResizeHandle = widget.bottomResizeHandle

  -- Apply height
  if self.height ~= mdw.config.widgetHeight then
    self.container:resize(nil, self.height)
    mdw.resizeWidgetContent(self._widget, self.container:get_width(), self.height)
  end

  -- Register in mdw.widgets
  mdw.widgets[self.name] = self._widget

  -- Copy class reference to internal widget for compatibility
  self._widget._class = self

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

  -- Set up click callback if provided
  if self.onClick then
    self.content:setClickCallback(function(event)
      if mdw.closeAllMenus then mdw.closeAllMenus() end
      self.onClick(self, event)
    end)
  end

  -- Update widgets menu to include new widget
  if mdw.rebuildWidgetsMenu then
    mdw.rebuildWidgetsMenu()
  end

  return self
end

---------------------------------------------------------------------------
-- ECHO METHODS
-- Methods for displaying text in the widget's content area.
---------------------------------------------------------------------------

--- Echo plain text to the widget's content area.
-- @tparam string text The text to display
function mdw.Widget:echo(text)
  self.content:echo(text)
end

--- Echo text with cecho color codes.
-- @tparam string text The text with color codes (e.g., "<red>Hello")
function mdw.Widget:cecho(text)
  self.content:cecho(text)
end

--- Echo text with decho color codes.
-- @tparam string text The text with RGB codes (e.g., "<255,0,0>Hello")
function mdw.Widget:decho(text)
  self.content:decho(text)
end

--- Echo text with hecho color codes.
-- @tparam string text The text with hex codes (e.g., "#FF0000Hello")
function mdw.Widget:hecho(text)
  self.content:hecho(text)
end

--- Clear the widget's content area.
function mdw.Widget:clear()
  self.content:clear()
end

---------------------------------------------------------------------------
-- DOCKING METHODS
-- Methods for controlling widget docking state.
---------------------------------------------------------------------------

--- Dock the widget to a sidebar.
-- @tparam string side "left" or "right"
-- @tparam number row Optional row index (auto-assigned if nil)
function mdw.Widget:dock(side, row)
  assert(side == "left" or side == "right", "dock side must be 'left' or 'right'")

  self._widget.docked = side

  if row then
    self._widget.row = row
    self._widget.rowPosition = 0
  else
    -- Auto-assign to next row
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
function mdw.Widget:undock(x, y)
  local previousDock = self._widget.docked

  self._widget.docked = nil
  self._widget.row = nil
  self._widget.rowPosition = nil

  if x and y then
    self.container:move(x, y)
  end

  mdw.showResizeHandles(self._widget)
  mdw.updateResizeBorders(self._widget)

  -- Reorganize the dock we left
  if previousDock then
    mdw.reorganizeDock(previousDock)
  end
end

--- Check if the widget is currently docked.
-- @return string|nil The dock side ("left" or "right") or nil if floating
function mdw.Widget:isDocked()
  return self._widget.docked
end

---------------------------------------------------------------------------
-- VISIBILITY METHODS
-- Methods for showing and hiding widgets.
---------------------------------------------------------------------------

--- Show the widget.
function mdw.Widget:show()
  self._widget.visible = true
  self.container:show()

  if self._widget.docked then
    mdw.hideResizeHandles(self._widget)
    mdw.reorganizeDock(self._widget.docked)
  else
    mdw.showResizeHandles(self._widget)
  end

  -- Update menu state if it exists
  if mdw.updateWidgetsMenuState then
    mdw.updateWidgetsMenuState()
  end
end

--- Hide the widget.
function mdw.Widget:hide()
  self._widget.visible = false
  self.container:hide()
  mdw.hideResizeHandles(self._widget)

  -- Reorganize docks (will update vertical splitters for side-by-side widgets)
  if self._widget.docked then
    mdw.reorganizeDock(self._widget.docked)
  end

  -- Update menu state
  if mdw.updateWidgetsMenuState then
    mdw.updateWidgetsMenuState()
  end

  -- Call onClose callback
  if self.onClose then
    self.onClose(self)
  end
end

--- Toggle widget visibility.
function mdw.Widget:toggle()
  if self._widget.visible then
    self:hide()
  else
    self:show()
  end
end

--- Check if the widget is visible.
-- @return boolean
function mdw.Widget:isVisible()
  return self._widget.visible ~= false
end

---------------------------------------------------------------------------
-- APPEARANCE METHODS
-- Methods for customizing widget appearance.
---------------------------------------------------------------------------

--- Set the widget's title.
-- @tparam string title The new title
function mdw.Widget:setTitle(title)
  self.title = title
  self._widget.title = title
  self.titleBar:decho("<" .. mdw.config.headerTextColor .. ">" .. title)
end

--- Set a custom stylesheet for the title bar.
-- @tparam string css Qt stylesheet string
function mdw.Widget:setTitleStyleSheet(css)
  self.titleBar:setStyleSheet(css)
end

--- Set the background color for the content area.
-- @tparam number r Red value (0-255)
-- @tparam number g Green value (0-255)
-- @tparam number b Blue value (0-255)
function mdw.Widget:setBackgroundColor(r, g, b)
  self.content:setColor(r, g, b, 255)
end

--- Set the font for the content area.
-- @tparam string font Font name
-- @tparam number size Font size (optional)
function mdw.Widget:setFont(font, size)
  if font then
    self.content:setFont(font)
  end
  if size then
    self.content:setFontSize(size)
  end
end

---------------------------------------------------------------------------
-- SIZE AND POSITION METHODS
-- Methods for controlling widget geometry.
---------------------------------------------------------------------------

--- Resize the widget.
-- @tparam number|nil width New width (nil to keep current)
-- @tparam number|nil height New height (nil to keep current)
function mdw.Widget:resize(width, height)
  self.container:resize(width, height)
  -- Get actual dimensions (may have been nil in the resize call)
  local actualWidth = width or self.container:get_width()
  local actualHeight = height or self.container:get_height()
  mdw.resizeWidgetContent(self._widget, actualWidth, actualHeight)

  if self._widget.docked then
    mdw.reorganizeDock(self._widget.docked)
  else
    mdw.updateResizeBorders(self._widget)
  end
end

--- Move the widget (only works for floating widgets).
-- @tparam number x New X position
-- @tparam number y New Y position
function mdw.Widget:move(x, y)
  if self._widget.docked then
    mdw.debugEcho("Cannot move docked widget - undock it first")
    return
  end

  self.container:move(x, y)
  mdw.updateResizeBorders(self._widget)
end

--- Get the widget's current position.
-- @return number x, number y
function mdw.Widget:getPosition()
  return self.container:get_x(), self.container:get_y()
end

--- Get the widget's current size.
-- @return number width, number height
function mdw.Widget:getSize()
  return self.container:get_width(), self.container:get_height()
end

--- Raise the widget above others.
function mdw.Widget:raise()
  mdw.raiseWidget(self._widget)
end

---------------------------------------------------------------------------
-- SPECIAL CONTENT METHODS
-- Methods for embedding special content like the mapper.
---------------------------------------------------------------------------

--- Embed the Mudlet mapper in this widget.
-- Note: Only one widget can have the mapper at a time.
function mdw.Widget:embedMapper()
  -- Hide the default content label
  self.content:hide()

  -- Create mapper if not exists
  if not self._widget.mapper then
    self._widget.mapper = Geyser.Mapper:new({
      name = "MDW_" .. self.name .. "_Mapper",
      x = 0,
      y = mdw.config.titleHeight,
      width = "100%",
      height = self.container:get_height() - mdw.config.titleHeight,
    }, self.container)
    self.mapper = self._widget.mapper
  end
end

--- Remove the embedded mapper and restore normal content.
function mdw.Widget:removeMapper()
  if self._widget.mapper then
    self._widget.mapper:hide()
    self._widget.mapper = nil
    self.mapper = nil
    self.content:show()
  end
end

---------------------------------------------------------------------------
-- DESTRUCTION
-- Methods for removing widgets.
---------------------------------------------------------------------------

--- Destroy the widget and clean up resources.
function mdw.Widget:destroy()
  -- Hide everything
  self:hide()

  -- Remove from mdw.widgets
  mdw.widgets[self.name] = nil

  -- Hide and cleanup resize borders
  if self.resizeLeft then self.resizeLeft:hide() end
  if self.resizeRight then self.resizeRight:hide() end
  if self.resizeTop then self.resizeTop:hide() end
  if self.resizeBottom then self.resizeBottom:hide() end

  -- Hide mapper if exists
  if self.mapper then
    self.mapper:hide()
  end

  -- Hide container
  self.container:hide()

  -- Rebuild menu to remove destroyed widget
  if mdw.rebuildWidgetsMenu then
    mdw.rebuildWidgetsMenu()
  end
end

---------------------------------------------------------------------------
-- CLASS METHODS
-- Static methods for working with all widgets.
---------------------------------------------------------------------------

--- Get a widget by name.
-- @tparam string name Widget name
-- @return Widget instance or nil
function mdw.Widget.get(name)
  local widget = mdw.widgets[name]
  if widget and widget._class then
    return widget._class
  end
  return nil
end

--- Get all widget names.
-- @return table Array of widget names
function mdw.Widget.list()
  local names = {}
  for name, _ in pairs(mdw.widgets) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

--- Hide all widgets.
function mdw.Widget.hideAll()
  for _, widget in pairs(mdw.widgets) do
    if widget._class then
      widget._class:hide()
    else
      widget.visible = false
      widget.container:hide()
    end
  end
end

--- Show all widgets.
function mdw.Widget.showAll()
  for _, widget in pairs(mdw.widgets) do
    if widget._class then
      widget._class:show()
    else
      widget.visible = true
      widget.container:show()
    end
  end
end
