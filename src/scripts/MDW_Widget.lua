--[[
  MDW_Widget.lua
  Widget class for MDW (Mudlet Dockable Widgets).

  Provides an object-oriented API for creating and managing dockable widgets.

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

  Dependencies: MDW_Config.lua, MDW_Helpers.lua, MDW_Init.lua, MDW_WidgetCore.lua must be loaded first
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
  subRow = 0,             -- Sub-row within column for sub-column stacking
  overflow = "wrap",      -- "wrap", "ellipsis", or "hidden"
}

function mdw.Widget:new(cons)
  cons = cons or {}

  -- Validate required fields
  assert(type(cons.name) == "string" and cons.name ~= "", "Widget name is required")

  -- Return existing widget if one with this name already exists
  -- This allows scripts to be reloaded without creating duplicates
  if mdw.widgets[cons.name] then
    return mdw.widgets[cons.name]
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
      x = winW - cfg.rightDockWidth + cfg.dockSplitterWidth + cfg.widgetMargin
    end
    y = cfg.headerHeight + cfg.widgetMargin
  end

  -- Create the underlying widget using existing infrastructure
  local widget = mdw.createWidget(self.name, self.title, x, y)

  -- Copy the internal widget properties to the class
  -- Why: The class IS the widget now - mdw.widgets stores the class directly.
  -- Internal functions access .docked, .container, etc. on what they receive,
  -- so the class must expose all these properties.
  self.container = widget.container
  self.titleBar = widget.titleBar
  self.content = widget.content
  self.contentBg = widget.contentBg
  self.mapper = widget.mapper
  self.resizeLeft = widget.resizeLeft
  self.resizeRight = widget.resizeRight
  self.resizeTop = widget.resizeTop
  self.resizeBottom = widget.resizeBottom
  self.bottomResizeHandle = widget.bottomResizeHandle

  -- State properties (accessed by internal functions via mdw.widgets iteration)
  self.docked = nil            -- "left", "right", or nil for floating
  self.row = nil               -- Row index in dock
  self.rowPosition = 0         -- Position within row (for side-by-side)
  self.subRow = 0              -- Sub-row within column for sub-column stacking
  self.originalDock = nil      -- Saved dock when sidebar is hidden
  self.isTabbed = false        -- Distinguishes from TabbedWidget

  -- Overflow mode
  self.overflow = cons.overflow or "wrap"
  if self.overflow ~= "wrap" then
    self.content:setWrap(10000)
  end
  self._wrapWidth = mdw.calculateWrap(self.content:get_width())

  -- Apply height
  if self.height ~= mdw.config.widgetHeight then
    self.container:resize(nil, self.height)
    mdw.resizeWidgetContent(self, self.container:get_width(), self.height)
  end

  -- Register the CLASS instance directly in mdw.widgets
  -- This replaces the old pattern of storing _widget with a _class back-reference
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

  -- Set up click callback if provided
  if self.onClick then
    self.content:setClickCallback(function(event)
      if mdw.closeAllMenus then mdw.closeAllMenus() end
      self.onClick(self, event)
    end)
  end

  -- Apply saved layout if available (uses shared helper to avoid duplication)
  mdw.applyPendingLayout(self)

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

local MAX_BUFFER = 50

-- Skips buffering when overflow is "hidden" (no reflow needed).
function mdw.Widget:_bufferEcho(method, text)
  if self.overflow == "hidden" then return end
  if not self._buffer then self._buffer = {} end
  self._buffer[#self._buffer + 1] = {method, text}
  while #self._buffer > MAX_BUFFER do
    table.remove(self._buffer, 1)
  end
end

--- Replay buffered echo calls to reflow text at a new wrap width after resize.
-- For "ellipsis" mode, re-truncates each entry to current width.
-- For "hidden" mode, does nothing (no buffer).
function mdw.Widget:reflow()
  if self.overflow == "hidden" then return end
  if not self._buffer or #self._buffer == 0 then return end
  self.content:clear()
  for _, entry in ipairs(self._buffer) do
    local text = entry[2]
    if self.overflow == "ellipsis" and self._wrapWidth then
      text = mdw.truncateFormatted(text, entry[1], self._wrapWidth)
    end
    self.content[entry[1]](self.content, text)
  end
end

function mdw.Widget:echo(text)
  self:_bufferEcho("echo", text)
  if self.overflow == "ellipsis" and self._wrapWidth then
    text = mdw.truncateFormatted(text, "echo", self._wrapWidth)
  end
  self.content:echo(text)
end

function mdw.Widget:cecho(text)
  self:_bufferEcho("cecho", text)
  if self.overflow == "ellipsis" and self._wrapWidth then
    text = mdw.truncateFormatted(text, "cecho", self._wrapWidth)
  end
  self.content:cecho(text)
end

function mdw.Widget:decho(text)
  self:_bufferEcho("decho", text)
  if self.overflow == "ellipsis" and self._wrapWidth then
    text = mdw.truncateFormatted(text, "decho", self._wrapWidth)
  end
  self.content:decho(text)
end

function mdw.Widget:hecho(text)
  self:_bufferEcho("hecho", text)
  if self.overflow == "ellipsis" and self._wrapWidth then
    text = mdw.truncateFormatted(text, "hecho", self._wrapWidth)
  end
  self.content:hecho(text)
end

function mdw.Widget:clear()
  self._buffer = {}
  self.content:clear()
end

---------------------------------------------------------------------------
-- DOCKING METHODS
-- Methods for controlling widget docking state.
---------------------------------------------------------------------------

function mdw.Widget:dock(side, row)
  mdw.dockWidgetClass(self, side, row)
end

function mdw.Widget:undock(x, y)
  mdw.undockWidgetClass(self, x, y)
end

function mdw.Widget:isDocked()
  return self.docked
end

---------------------------------------------------------------------------
-- VISIBILITY METHODS
-- Methods for showing and hiding widgets.
---------------------------------------------------------------------------

function mdw.Widget:show()
  mdw.showWidgetClass(self)
end

function mdw.Widget:hide()
  mdw.hideWidgetClass(self)
end

function mdw.Widget:toggle()
  if self.visible then
    self:hide()
  else
    self:show()
  end
end

function mdw.Widget:isVisible()
  return self.visible ~= false
end

---------------------------------------------------------------------------
-- APPEARANCE METHODS
-- Methods for customizing widget appearance.
---------------------------------------------------------------------------

function mdw.Widget:setTitle(title)
  self.title = title
  self.titleBar:decho("<" .. mdw.config.headerTextColor .. ">" .. title)
end

function mdw.Widget:setTitleStyleSheet(css)
  self.titleBar:setStyleSheet(css)
end

-- Note: This affects the background label behind the MiniConsole, not the console itself.
-- For MiniConsole colors, use setBackgroundColor() instead.
function mdw.Widget:setContentStyleSheet(css)
  if self.contentBg then
    self.contentBg:setStyleSheet(css)
  end
end

function mdw.Widget:setBackgroundColor(r, g, b)
  self.content:setColor(r, g, b, 255)
end

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

function mdw.Widget:resize(width, height)
  mdw.resizeWidgetClass(self, width, height, mdw.resizeWidgetContent)
end

function mdw.Widget:move(x, y)
  mdw.moveWidgetClass(self, x, y)
end

function mdw.Widget:getPosition()
  return self.container:get_x(), self.container:get_y()
end

function mdw.Widget:getSize()
  return self.container:get_width(), self.container:get_height()
end

function mdw.Widget:raise()
  mdw.raiseWidget(self)
end

---------------------------------------------------------------------------
-- SPECIAL CONTENT METHODS
-- Methods for embedding special content like the mapper.
---------------------------------------------------------------------------

-- Note: Only one widget can have the mapper at a time.
function mdw.Widget:embedMapper()
  -- Hide the default content label
  self.content:hide()

  -- Create mapper if not exists
  if not self.mapper then
    self.mapper = Geyser.Mapper:new({
      name = "MDW_" .. self.name .. "_Mapper",
      x = 0,
      y = mdw.config.titleHeight,
      width = "100%",
      height = self.container:get_height() - mdw.config.titleHeight,
    }, self.container)

    -- If widget is hidden, hide the mapper too
    if self.visible == false then
      self.mapper:hide()
    end
  end
end

function mdw.Widget:removeMapper()
  if self.mapper then
    self.mapper:hide()
    self.mapper = nil
    self.content:show()
  end
end

---------------------------------------------------------------------------
-- DESTRUCTION
-- Methods for removing widgets.
---------------------------------------------------------------------------

function mdw.Widget:destroy()
  mdw.destroyWidgetClass(self)
end

---------------------------------------------------------------------------
-- CLASS METHODS
-- Static methods for working with all widgets.
---------------------------------------------------------------------------

function mdw.Widget.get(name)
  local widget = mdw.widgets[name]
  -- Only return if it's a Widget (not a TabbedWidget)
  if widget and not widget.isTabbed then
    return widget
  end
  return nil
end

function mdw.Widget.list()
  local names = {}
  for name, _ in pairs(mdw.widgets) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

function mdw.Widget.hideAll()
  for _, widget in pairs(mdw.widgets) do
    widget:hide()
  end
end

function mdw.Widget.showAll()
  for _, widget in pairs(mdw.widgets) do
    widget:show()
  end
end
