--[[
  MDW_WidgetCore.lua
  Widget creation, drag/drop, dock management, and menus for MDW (Mudlet Dockable Widgets).

  Widgets are draggable containers that can be freely positioned or docked
  to left/right sidebars. Supports side-by-side docking, vertical stacking,
  and resize handles for both docked and floating widgets.

  Dependencies: MDW_Config.lua, MDW_Helpers.lua, MDW_Init.lua must be loaded first
]]

---------------------------------------------------------------------------
-- WIDGET CREATION
-- Factory functions for creating widget instances.
---------------------------------------------------------------------------

--- Create a widget with title bar and content area.
-- Why: Widgets are the primary UI component. Each widget has a draggable
-- title bar, content area, and optional resize borders for floating mode.
function mdw.createWidget(name, title, x, y)
	assert(type(name) == "string" and name ~= "", "name must be a non-empty string")
	assert(type(title) == "string", "title must be a string")
	assert(type(x) == "number", "x must be a number")
	assert(type(y) == "number", "y must be a number")

	local cfg = mdw.config

	local widget = {
		name = name,
		title = title,
		docked = nil,
		visible = true,
	}

	-- Main container
	local totalMargin = cfg.widgetMargin * 2
	widget.container = mdw.trackElement(Geyser.Container:new({
		name = "MDW_" .. name,
		x = x,
		y = y,
		width = cfg.leftDockWidth - totalMargin - cfg.dockSplitterWidth,
		height = cfg.widgetHeight,
	}))

	-- Get container's actual width for child elements
	local containerWidth = widget.container:get_width()
	local contentAreaHeight = cfg.widgetHeight - cfg.titleHeight
	local contentWidth = containerWidth - cfg.contentPaddingLeft
	local contentHeight = contentAreaHeight - cfg.contentPaddingTop
	local bgRGB = cfg.widgetBackgroundRGB

	-- Background label to fill the padding area
	widget.contentBg = mdw.trackElement(Geyser.Label:new({
		name = "MDW_" .. name .. "_ContentBg",
		x = 0,
		y = cfg.titleHeight,
		width = containerWidth,
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
		width = containerWidth,
		height = cfg.titleHeight,
	}, widget.container))
	widget.titleBar:setStyleSheet(mdw.styles.titleBar)
	widget.titleBar:setFontSize(cfg.widgetHeaderFontSize)
	widget.titleBar:setCursor(mudlet.cursor.OpenHand)

	-- Content area (MiniConsole for scrollable, appendable text)
	-- Offset by padding to create left and top padding
	local contentName = "MDW_" .. name .. "_Content"
	widget.content = mdw.trackElement(Geyser.MiniConsole:new({
		name = contentName,
		x = cfg.contentPaddingLeft,
		y = cfg.titleHeight + cfg.contentPaddingTop,
		width = contentWidth,
		height = contentHeight - cfg.widgetSplitterHeight,
	}, widget.container))
	local fgRGB = cfg.widgetForegroundRGB
	widget.content:setColor(bgRGB[1], bgRGB[2], bgRGB[3], 255)
	widget.content:setFont(cfg.fontFamily)
	widget.content:setFontSize(cfg.fontSize)
	widget.content:setWrap(mdw.calculateWrap(contentWidth))
	-- Set default text colors so echo() matches the background
	setBgColor(contentName, bgRGB[1], bgRGB[2], bgRGB[3])
	setFgColor(contentName, fgRGB[1], fgRGB[2], fgRGB[3])

	-- Bottom resize handle - part of widget so it moves with dragging
	local handleHeight = cfg.widgetSplitterHeight + cfg.resizeHandleHitPad
	widget.bottomResizeHandle = mdw.trackElement(Geyser.Label:new({
		name = "MDW_" .. name .. "_BottomResize",
		x = 0,
		y = cfg.widgetHeight - handleHeight,
		width = containerWidth,
		height = handleHeight,
	}, widget.container))
	widget.bottomResizeHandle:setStyleSheet(string.format([[
    QLabel { background-color: transparent; border-bottom: %dpx solid %s; }
    QLabel:hover { background-color: transparent; border-bottom: %dpx solid %s; }
  ]], cfg.widgetSplitterHeight, cfg.resizeBorderColor, cfg.widgetSplitterHeight, cfg.splitterHoverColor))
	widget.bottomResizeHandle:setCursor(mudlet.cursor.ResizeVertical)
	widget.bottomResizeHandle:hide() -- Hidden by default, shown when docked

	-- Create resize borders (hidden by default, shown when floating)
	mdw.createResizeBorders(widget)

	-- Create title bar buttons (FILL, LOCK, Close)
	mdw.createTitleBarButtons(widget)

	-- Render title (after buttons so truncation accounts for button space)
	mdw.renderWidgetTitle(widget)

	-- Set up docked resize handle callbacks
	mdw.setupDockedResizeHandle(widget)

	-- Set up drag callbacks
	mdw.setupWidgetDrag(widget)

	return widget
end

--- Get the package resource path for a title bar icon.
-- Uses SVG when setSvgTint is available (dev Mudlet), PNG otherwise.
function mdw.getIconPath(iconName)
	local ext = Geyser.Label.setSvgTint and ".svg" or ".png"
	return getMudletHomeDir() .. "/" .. mdw.packageName .. "/" .. iconName .. ext
end

function mdw.createTitleBarButtons(widget)
	local cfg = mdw.config
	local baseName = "MDW_" .. widget.name
	local cw = widget.container:get_width()
	local btnS = cfg.titleButtonSize
	local btnH = cfg.titleHeight
	local pad = cfg.titleButtonPadding
	local closePad = cfg.closeButtonPadding
	local btnY = math.floor((btnH - btnS) / 2)

	local gap = cfg.titleButtonGap or 4

	-- Fill toggle (far left, with padding from edge)
	widget.fillButton = mdw.trackElement(Geyser.Label:new({
		name = baseName .. "_FillBtn",
		x = pad, y = btnY, width = btnS, height = btnS,
	}, widget.container))
	widget.fillButton:setCursor(mudlet.cursor.PointingHand)
	widget.fillButton:setToolTip("Auto fill down")

	-- Lock toggle (second from left, with gap)
	widget.lockButton = mdw.trackElement(Geyser.Label:new({
		name = baseName .. "_LockBtn",
		x = pad + btnS + gap, y = btnY, width = btnS, height = btnS,
	}, widget.container))
	widget.lockButton:setCursor(mudlet.cursor.PointingHand)
	widget.lockButton:setToolTip("Locks widget width")

	-- Close button (far right, with padding from edge)
	widget.closeButton = mdw.trackElement(Geyser.Label:new({
		name = baseName .. "_CloseBtn",
		x = cw - btnS - closePad, y = btnY, width = btnS, height = btnS,
	}, widget.container))
	widget.closeButton:setStyleSheet(mdw.styles.titleButtonClose)
	widget.closeButton:setFontSize(cfg.widgetHeaderFontSize)
	widget.closeButton:setCursor(mudlet.cursor.PointingHand)
	widget.closeButton:decho("<" .. cfg.closeButtonColor .. ">X")

	mdw.setupTitleBarButtonCallbacks(widget)
	mdw.updateFillButtonText(widget)
	mdw.updateLockButtonText(widget)
end

--- Reposition title bar buttons after a container resize.
function mdw.repositionTitleBarButtons(widget, containerWidth)
	local cfg = mdw.config
	local btnS = cfg.titleButtonSize
	local pad = cfg.titleButtonPadding
	local gap = cfg.titleButtonGap or 4
	local closePad = cfg.closeButtonPadding
	local btnY = math.floor((cfg.titleHeight - btnS) / 2)
	if widget.fillButton then
		widget.fillButton:move(pad, btnY)
		widget.fillButton:resize(btnS, btnS)
	end
	if widget.lockButton then
		widget.lockButton:move(pad + btnS + gap, btnY)
		widget.lockButton:resize(btnS, btnS)
	end
	if widget.closeButton then
		widget.closeButton:move(containerWidth - btnS - closePad, btnY)
		widget.closeButton:resize(btnS, btnS)
	end
end

--- Set up click callbacks for title bar buttons.
function mdw.setupTitleBarButtonCallbacks(widget)
	local widgetName = widget.name

	setLabelClickCallback("MDW_" .. widgetName .. "_FillBtn", function()
		local w = mdw.widgets[widgetName]
		if not w then return end
		if mdw.closeAllMenus then mdw.closeAllMenus() end
		mdw.toggleFill(w)
	end)

	setLabelClickCallback("MDW_" .. widgetName .. "_LockBtn", function()
		local w = mdw.widgets[widgetName]
		if not w then return end
		if mdw.closeAllMenus then mdw.closeAllMenus() end
		mdw.toggleWidthLock(w)
	end)

	setLabelClickCallback("MDW_" .. widgetName .. "_CloseBtn", function()
		local w = mdw.widgets[widgetName]
		if not w then return end
		if mdw.closeAllMenus then mdw.closeAllMenus() end
		mdw.toggleWidget(widgetName)
	end)
end

--- Toggle fill mode for a docked widget.
function mdw.toggleFill(widget)
	if not widget.docked then return end
	-- Only allow fill on the bottom-most widget (_canFill set by reorganizeDock)
	if not widget.fill and not widget._canFill then return end
	if not widget.fill then
		-- Save current height before filling
		widget._preFillHeight = widget.container:get_height()
		widget.fill = true
	else
		-- Restore original height
		widget.fill = false
		if widget._preFillHeight then
			widget.container:resize(nil, widget._preFillHeight)
			mdw.resizeWidgetContent(widget, widget.container:get_width(), widget._preFillHeight)
			widget._preFillHeight = nil
		end
	end
	mdw.updateFillButtonText(widget)
	mdw.reorganizeDock(widget.docked)
	mdw.saveLayout()
end

--- Toggle width lock for a docked widget.
function mdw.toggleWidthLock(widget)
	if not widget.docked then return end
	if not widget.widthLocked and not widget._canLock then return end
	widget.widthLocked = not widget.widthLocked
	if widget.widthLocked then
		widget.lockedWidth = widget.container:get_width()
	else
		widget.lockedWidth = nil
	end
	mdw.updateLockButtonText(widget)
	mdw.saveLayout()
end

--- Update fill button icon based on state.
function mdw.updateFillButtonText(widget)
	if not widget.fillButton then return end
	local iconName = widget.fill and "fill-active" or "fill-inactive"
	local path = mdw.getIconPath(iconName)
	if Geyser.Label.setSvgTint then
		widget.fillButton:setBackgroundImage(path)
		widget.fillButton:setSvgTint(mdw.config.titleButtonTint)
	else
		widget.fillButton:setStyleSheet(string.format(
			[[QLabel { background-color: transparent; border: none; border-image: url(%s); }]],
			path))
	end
end

--- Update lock button icon based on state.
function mdw.updateLockButtonText(widget)
	if not widget.lockButton then return end
	local iconName = widget.widthLocked and "lock-active" or "lock-inactive"
	local path = mdw.getIconPath(iconName)
	if Geyser.Label.setSvgTint then
		widget.lockButton:setBackgroundImage(path)
		widget.lockButton:setSvgTint(mdw.config.titleButtonTint)
	else
		widget.lockButton:setStyleSheet(string.format(
			[[QLabel { background-color: transparent; border: none; border-image: url(%s); }]],
			path))
	end
end

--- Create resize borders for a widget (used in floating mode).
-- Why: Floating widgets need resize handles so users can adjust dimensions.
-- Borders are absolute-positioned labels that track the widget's position.
function mdw.createResizeBorders(widget)
	local cfg = mdw.config
	local baseName = "MDW_" .. widget.name
	local hw = cfg.resizeHitWidth

	-- Edge borders (hw-wide hit target, 2px visible border on widget-facing side)
	widget.resizeLeft = mdw.trackElement(Geyser.Label:new({
		name = baseName .. "_ResizeLeft",
		x = 0, y = 0, width = hw, height = 100,
	}))
	widget.resizeLeft:setStyleSheet(mdw.styles.resizeLeft)
	widget.resizeLeft:setCursor(mudlet.cursor.ResizeHorizontal)
	widget.resizeLeft:hide()

	widget.resizeRight = mdw.trackElement(Geyser.Label:new({
		name = baseName .. "_ResizeRight",
		x = 0, y = 0, width = hw, height = 100,
	}))
	widget.resizeRight:setStyleSheet(mdw.styles.resizeRight)
	widget.resizeRight:setCursor(mudlet.cursor.ResizeHorizontal)
	widget.resizeRight:hide()

	widget.resizeBottom = mdw.trackElement(Geyser.Label:new({
		name = baseName .. "_ResizeBottom",
		x = 0, y = 0, width = 100, height = hw,
	}))
	widget.resizeBottom:setStyleSheet(mdw.styles.resizeBottom)
	widget.resizeBottom:setCursor(mudlet.cursor.ResizeVertical)
	widget.resizeBottom:hide()

	widget.resizeTop = mdw.trackElement(Geyser.Label:new({
		name = baseName .. "_ResizeTop",
		x = 0, y = 0, width = 100, height = hw,
	}))
	widget.resizeTop:setStyleSheet(mdw.styles.resizeTop)
	widget.resizeTop:setCursor(mudlet.cursor.ResizeVertical)
	widget.resizeTop:hide()

	mdw.setupResizeBorder(widget, widget.resizeLeft, "left")
	mdw.setupResizeBorder(widget, widget.resizeRight, "right")
	mdw.setupResizeBorder(widget, widget.resizeBottom, "bottom")
	mdw.setupResizeBorder(widget, widget.resizeTop, "top")

	-- Corner resize handles
	local cs = cfg.resizeCornerSize
	local cornerStyle = [[QLabel { background-color: transparent; } QLabel:hover { background-color: transparent; }]]

	widget.resizeTopLeft = mdw.trackElement(Geyser.Label:new({
		name = baseName .. "_ResizeCornerTL",
		x = 0, y = 0, width = cs, height = cs,
	}))
	widget.resizeTopLeft:setStyleSheet(cornerStyle)
	pcall(function() widget.resizeTopLeft:setCursor(8) end)
	widget.resizeTopLeft:hide()
	mdw.setupResizeBorder(widget, widget.resizeTopLeft, "topLeft")

	widget.resizeTopRight = mdw.trackElement(Geyser.Label:new({
		name = baseName .. "_ResizeCornerTR",
		x = 0, y = 0, width = cs, height = cs,
	}))
	widget.resizeTopRight:setStyleSheet(cornerStyle)
	pcall(function() widget.resizeTopRight:setCursor(7) end)
	widget.resizeTopRight:hide()
	mdw.setupResizeBorder(widget, widget.resizeTopRight, "topRight")

	widget.resizeBottomLeft = mdw.trackElement(Geyser.Label:new({
		name = baseName .. "_ResizeCornerBL",
		x = 0, y = 0, width = cs, height = cs,
	}))
	widget.resizeBottomLeft:setStyleSheet(cornerStyle)
	pcall(function() widget.resizeBottomLeft:setCursor(7) end)
	widget.resizeBottomLeft:hide()
	mdw.setupResizeBorder(widget, widget.resizeBottomLeft, "bottomLeft")

	widget.resizeBottomRight = mdw.trackElement(Geyser.Label:new({
		name = baseName .. "_ResizeCornerBR",
		x = 0, y = 0, width = cs, height = cs,
	}))
	widget.resizeBottomRight:setStyleSheet(cornerStyle)
	pcall(function() widget.resizeBottomRight:setCursor(8) end)
	widget.resizeBottomRight:hide()
	mdw.setupResizeBorder(widget, widget.resizeBottomRight, "bottomRight")
end

--- Resize and reposition widget content after container changes.
-- Why: Ensures children match container dimensions after resize.
-- Uses relative positioning (children are parented to container).
function mdw.resizeWidgetContent(widget, targetWidth, targetHeight)
	local cfg = mdw.config

	-- Handle tabbed widgets (check function exists to avoid errors if TabbedWidget not loaded)
	if widget.isTabbed and mdw.resizeTabbedWidgetContent then
		mdw.resizeTabbedWidgetContent(widget, targetWidth, targetHeight)
		return
	end

	-- Use provided dimensions or fall back to container dimensions
	local cw = targetWidth or widget.container:get_width()
	local ch = targetHeight or widget.container:get_height()

	-- Reserve space for bottom resize handle when docked
	local resizeHandleHeight = widget.docked and cfg.widgetSplitterHeight or 0
	local contentAreaHeight = ch - cfg.titleHeight - resizeHandleHeight
	local contentAreaWidth = cw -- Full width - splitters are separate elements now
	local contentWidth = contentAreaWidth - cfg.contentPaddingLeft
	local contentHeight = contentAreaHeight - cfg.contentPaddingTop

	-- Use RELATIVE positions (children are parented to container)
	widget.titleBar:move(0, 0)
	widget.titleBar:resize(cw, cfg.titleHeight)

	mdw.repositionTitleBarButtons(widget, cw)
	mdw.renderWidgetTitle(widget)

	-- Resize background label that fills the padding area (not overlapping right splitter)
	if widget.contentBg then
		widget.contentBg:move(0, cfg.titleHeight)
		widget.contentBg:resize(contentAreaWidth, contentAreaHeight)
	end

	widget.content:move(cfg.contentPaddingLeft, cfg.titleHeight + cfg.contentPaddingTop)
	widget.content:resize(contentWidth, contentHeight)
	local wrapWidth = mdw.calculateWrap(contentWidth)
	local overflow = widget.overflow or "wrap"
	if overflow == "wrap" then
		widget.content:setWrap(wrapWidth)
	else
		widget.content:setWrap(10000)
	end
	widget._wrapWidth = wrapWidth
	if overflow ~= "hidden" and widget.reflow then widget:reflow() end

	if widget.mapper then
		widget.mapper:move(cfg.contentPaddingLeft, cfg.titleHeight + cfg.contentPaddingTop)
		widget.mapper:resize(contentWidth, contentHeight)
	end

	-- Position bottom resize handle at widget bottom (hit area extends above visible line)
	if widget.bottomResizeHandle then
		local handleHeight = cfg.widgetSplitterHeight + cfg.resizeHandleHitPad
		widget.bottomResizeHandle:move(0, ch - handleHeight)
		widget.bottomResizeHandle:resize(cw, handleHeight)
	end
end

---------------------------------------------------------------------------
-- WIDGET DRAG HANDLING
-- Enables dragging widgets by their title bar.
---------------------------------------------------------------------------

function mdw.setupWidgetDrag(internalWidget)
	local titleName = "MDW_" .. internalWidget.name .. "_Title"
	local widgetName = internalWidget.name

	-- Callbacks look up the class instance from mdw.widgets
	-- Why: The class instance has docked/row/visible state, not the internal structure
	setLabelClickCallback(titleName, function(event)
		local widget = mdw.widgets[widgetName]
		if widget then
			mdw.startDrag(widget, event)
		end
	end)

	setLabelMoveCallback(titleName, function(event)
		local widget = mdw.widgets[widgetName]
		if widget and mdw.drag.active and mdw.drag.widget == widget then
			mdw.handleDragMove(widget, event)
		end
	end)

	setLabelReleaseCallback(titleName, function(event)
		local widget = mdw.widgets[widgetName]
		if widget and mdw.drag.active and mdw.drag.widget == widget then
			mdw.endDrag(widget, event)
		end
	end)
end

--- Set up the docked bottom resize handle for vertical resizing.
-- Why: This handle is part of the widget itself (inside the container), so it
-- moves with the widget and doesn't need separate tracking/cleanup.
function mdw.setupDockedResizeHandle(internalWidget)
	local handleName = "MDW_" .. internalWidget.name .. "_BottomResize"
	local widgetName = internalWidget.name

	setLabelClickCallback(handleName, function(event)
		local widget = mdw.widgets[widgetName]
		if not widget then return end
		if widget.fill then return end
		mdw.widgetSplitterDrag.active = true
		mdw.widgetSplitterDrag.widget = widget
		mdw.widgetSplitterDrag.side = widget.docked
		mdw.widgetSplitterDrag.offsetY = event.globalY - widget.container:get_y() - widget.container:get_height()
	end)

	setLabelMoveCallback(handleName, function(event)
		local widget = mdw.widgets[widgetName]
		if not widget then return end
		if mdw.widgetSplitterDrag.active and mdw.widgetSplitterDrag.widget == widget then
			local side = widget.docked
			if side then
				local targetY = event.globalY - mdw.widgetSplitterDrag.offsetY
				mdw.resizeWidgetWithSnap(widget, side, targetY)
			end
		end
	end)

	setLabelReleaseCallback(handleName, function()
		local widget = mdw.widgets[widgetName]
		if not widget then return end
		if mdw.widgetSplitterDrag.active and mdw.widgetSplitterDrag.widget == widget then
			local side = widget.docked
			mdw.widgetSplitterDrag.active = false
			mdw.widgetSplitterDrag.widget = nil
			mdw.widgetSplitterDrag.side = nil
			if side then
				mdw.reorganizeDock(side)
			end
			mdw.saveLayout()
		end
	end)
end

--- Start dragging a widget.
-- Why: Records initial state but doesn't undock until actual movement occurs.
-- This prevents accidental undocking on simple clicks.
function mdw.startDrag(widget, event)
	mdw.closeAllMenus()

	mdw.drag.active = true
	mdw.drag.widget = widget
	mdw.drag.offsetX = event.globalX - widget.container:get_x()
	mdw.drag.offsetY = event.globalY - widget.container:get_y()
	mdw.drag.startMouseX = event.globalX
	mdw.drag.startMouseY = event.globalY
	mdw.drag.hasMoved = false

	-- Remember original dock info for cancel/restore
	mdw.drag.originalDock = widget.docked
	mdw.drag.originalRow = widget.row
	mdw.drag.originalRowPosition = widget.rowPosition
	mdw.drag.originalSubRow = widget.subRow

	widget.titleBar:setCursor(mudlet.cursor.ClosedHand)
	mdw.raiseWidgetElements(widget)
end

function mdw.handleDragMove(widget, event)
	if not widget or not widget.container then return end

	local cfg = mdw.config
	local movedX = math.abs(event.globalX - mdw.drag.startMouseX)
	local movedY = math.abs(event.globalY - mdw.drag.startMouseY)

	-- Commit drag start once movement threshold is exceeded
	if movedX > cfg.dragThreshold or movedY > cfg.dragThreshold then
		mdw.commitDragStart(widget)
	end

	-- Only move if drag has been committed
	if mdw.drag.hasMoved then
		local newX = math.max(0, event.globalX - mdw.drag.offsetX)
		local newY = math.max(cfg.headerHeight + cfg.separatorHeight, event.globalY - mdw.drag.offsetY)
		widget.container:move(newX, newY)

		if not widget.docked then
			mdw.updateResizeBorders(widget)
		end

		mdw.updateDropIndicator(widget)
		mdw.raiseWidgetElements(widget)
	end
end

--- Commit to a drag operation after movement threshold is exceeded.
-- Why: Separates click (no movement) from drag (movement detected).
-- Undocking and visual feedback only happen once we're sure it's a drag.
function mdw.commitDragStart(widget)
	if mdw.drag.hasMoved then return end
	mdw.drag.hasMoved = true

	-- Now undock the widget
	widget.docked = nil
	widget.row = nil
	widget.rowPosition = nil
	widget.subRow = nil

	-- Reset dock-only state and restore pre-fill height
	if widget.fill and widget._preFillHeight then
		widget.container:resize(nil, widget._preFillHeight)
		mdw.resizeWidgetContent(widget, widget.container:get_width(), widget._preFillHeight)
	end
	widget.fill = false
	widget._preFillHeight = nil
	widget.widthLocked = false
	widget.lockedWidth = nil
	mdw.updateDockButtonVisibility(widget)

	-- Reorganize the dock we left (this handles splitters automatically)
	if mdw.drag.originalDock then
		mdw.reorganizeDock(mdw.drag.originalDock)
	end

	mdw.raiseWidgetElements(widget)
end

function mdw.endDrag(widget, event)
	if not mdw.drag.active or mdw.drag.widget ~= widget then return end

	-- Capture state before clearing
	local insertSide = mdw.drag.insertSide
	local dropType = mdw.drag.dropType
	local rowIndex = mdw.drag.rowIndex
	local positionInRow = mdw.drag.positionInRow
	local targetWidget = mdw.drag.targetWidget
	local hasMoved = mdw.drag.hasMoved
	local originalDock = mdw.drag.originalDock
	local originalRow = mdw.drag.originalRow
	local originalRowPosition = mdw.drag.originalRowPosition
	local originalSubRow = mdw.drag.originalSubRow

	mdw.debugEcho("ENDDRAG: widget=%s, hasMoved=%s, insertSide=%s, dropType=%s",
		widget.name, tostring(hasMoved), tostring(insertSide), tostring(dropType))

	-- Clear drag state
	mdw.drag.active = false
	mdw.drag.widget = nil
	mdw.drag.originalDock = nil
	mdw.drag.originalRow = nil
	mdw.drag.originalRowPosition = nil
	mdw.drag.originalSubRow = nil
	mdw.drag.insertSide = nil
	mdw.drag.dropType = nil
	mdw.drag.rowIndex = nil
	mdw.drag.positionInRow = nil
	mdw.drag.targetWidget = nil
	mdw.drag.hasMoved = nil
	mdw.drag.startMouseX = nil
	mdw.drag.startMouseY = nil

	widget.titleBar:setCursor(mudlet.cursor.OpenHand)

	mdw.hideDropIndicator()
	mdw.updateDockHighlight(nil)

	-- Restore original position if no movement
	if not hasMoved then
		if originalDock then
			widget.docked = originalDock
			widget.row = originalRow
			widget.rowPosition = originalRowPosition
			widget.subRow = originalSubRow
		end
		-- Still need to reorganize docks to restore splitters that were hidden during drag
		mdw.reorganizeDock("left")
		mdw.reorganizeDock("right")
		return
	end

	-- Dock or float based on drop position
	if insertSide then
		mdw.dockWidgetWithPosition(widget, insertSide, dropType, rowIndex, positionInRow, targetWidget)
		mdw.hideResizeHandles(widget)
	else
		widget.docked = nil
		widget.row = nil
		widget.rowPosition = nil
		widget.subRow = nil
		mdw.showResizeHandles(widget)
	end

	-- Always reorganize both docks to ensure splitters are properly cleaned up
	-- This handles cases where widgets move between docks or are undocked
	mdw.reorganizeDock("left")
	mdw.reorganizeDock("right")

	mdw.saveLayout()
end

--- Raise a widget above all others.
-- Delegates to mdw.raiseWidgetElements() which is the centralized implementation.
function mdw.raiseWidget(widget)
	mdw.raiseWidgetElements(widget)
end

--- Reflow a widget's content to repaint text at the current wrap width.
-- Replays buffered echo calls so text reflows correctly after resize.
function mdw.refreshWidgetContent(widget)
	if not widget then return end
	if widget.reflow then
		widget:reflow()
	end
end

---------------------------------------------------------------------------
-- DROP DETECTION
-- Determines where a dragged widget should be inserted in a dock.
---------------------------------------------------------------------------

function mdw.getDockZoneAtPoint(x, y)
	local cfg = mdw.config
	local dropBuffer = cfg.dockDropBuffer

	if mdw.visibility.leftSidebar then
		local leftX = mdw.leftDock:get_x()
		local leftY = mdw.leftDock:get_y()
		local leftW = mdw.leftDock:get_width()
		local leftH = mdw.leftDock:get_height()

		if x >= leftX and x <= leftX + leftW + cfg.dockSplitterWidth and
			y >= leftY - dropBuffer and y <= leftY + leftH + dropBuffer then
			return "left"
		end
	end

	if mdw.visibility.rightSidebar then
		local rightX = mdw.rightDock:get_x()
		local rightY = mdw.rightDock:get_y()
		local rightW = mdw.rightDock:get_width()
		local rightH = mdw.rightDock:get_height()

		if x >= rightX - cfg.dockSplitterWidth and x <= rightX + rightW and
			y >= rightY - dropBuffer and y <= rightY + rightH + dropBuffer then
			return "right"
		end
	end

	return nil
end

--- Get all docked widgets on a side, optionally excluding one.
function mdw.getDockedWidgets(side, excludeWidget)
	local docked = {}
	for _, w in pairs(mdw.widgets) do
		if w.docked == side and w ~= excludeWidget and w.visible ~= false then
			docked[#docked + 1] = w
		end
	end

	table.sort(docked, function(a, b)
		local rowA = a.row or 0
		local rowB = b.row or 0
		if rowA ~= rowB then
			return rowA < rowB
		end
		local posA = a.rowPosition or 0
		local posB = b.rowPosition or 0
		if posA ~= posB then
			return posA < posB
		end
		return (a.subRow or 0) < (b.subRow or 0)
	end)

	return docked
end

--- Group docked widgets by row number.
function mdw.groupWidgetsByRow(docked)
	local rows = {}
	for _, w in ipairs(docked) do
		local rowNum = w.row or 0
		if not rows[rowNum] then
			rows[rowNum] = {}
		end
		rows[rowNum][#rows[rowNum] + 1] = w
	end

	-- Convert to sorted array
	local sortedRows = {}
	local rowNums = {}
	for rowNum in pairs(rows) do
		rowNums[#rowNums + 1] = rowNum
	end
	table.sort(rowNums)

	for _, rowNum in ipairs(rowNums) do
		table.sort(rows[rowNum], function(a, b)
			local posA = a.rowPosition or 0
			local posB = b.rowPosition or 0
			if posA ~= posB then return posA < posB end
			return (a.subRow or 0) < (b.subRow or 0)
		end)
		sortedRows[#sortedRows + 1] = rows[rowNum]
	end

	return sortedRows
end

--- Group a row's widgets into columns by rowPosition.
function mdw.groupWidgetsByColumn(row)
	local columnMap = {}
	for _, w in ipairs(row) do
		local pos = w.rowPosition or 0
		if not columnMap[pos] then
			columnMap[pos] = {}
		end
		columnMap[pos][#columnMap[pos] + 1] = w
	end

	-- Sort column keys
	local positions = {}
	for pos in pairs(columnMap) do
		positions[#positions + 1] = pos
	end
	table.sort(positions)

	-- Build sorted columns array, sort each column by subRow
	local columns = {}
	for _, pos in ipairs(positions) do
		local col = columnMap[pos]
		table.sort(col, function(a, b)
			return (a.subRow or 0) < (b.subRow or 0)
		end)
		columns[#columns + 1] = col
	end

	return columns
end

--- Get total height of a column of widgets.
function mdw.getColumnHeight(column)
	local total = 0
	for _, w in ipairs(column) do
		total = total + w.container:get_height()
	end
	return total
end

--- Detect where a widget would be dropped in a dock.
-- Why: Uses spatial zones to determine insertion type:
-- - Top/bottom zone (configured by verticalInsertZone) triggers vertical insert
-- - Middle zone with horizontal offset triggers side-by-side placement
-- This dual-zone approach prevents accidental side-by-side when users intend vertical stacking.
function mdw.detectDropPosition(side, headerX, headerY, excludeWidget, widgetLeftX, widgetRightX)
	local cfg = mdw.config
	local docked = mdw.getDockedWidgets(side, excludeWidget)
	local rows = mdw.groupWidgetsByRow(docked)

	if #rows == 0 then
		return "above", 1, 0, nil
	end

	local vertZone = cfg.verticalInsertZone
	local sideBySideZone = cfg.sideBySideZone
	local sideBySideOffset = cfg.sideBySideOffset

	local yPos = cfg.headerHeight + cfg.widgetMargin
	for rowIndex, row in ipairs(rows) do
		local columns = mdw.groupWidgetsByColumn(row)
		local rowHeight = 0
		for _, col in ipairs(columns) do
			rowHeight = math.max(rowHeight, mdw.getColumnHeight(col))
		end

		local rowTop = yPos
		local rowBottom = yPos + rowHeight
		local rowMidY = yPos + rowHeight / 2

		if headerY >= rowTop - sideBySideOffset and headerY <= rowBottom + sideBySideOffset then
			local topZone = rowTop + rowHeight * vertZone
			local bottomZone = rowTop + rowHeight * (1 - vertZone)

			-- Top zone - insert above
			if headerY < topZone then
				return "above", rowIndex, 0, nil
				-- Bottom zone - insert below
			elseif headerY > bottomZone then
				return "below", rowIndex, 0, nil
			end

			-- Sub-column gap detection (checked before side-by-side)
			if #columns > 1 then
				-- Calculate column positions and widths
				local numColumns = #columns
				local dockCfg = mdw.getDockConfig(side)
				local fullWidgetWidth = dockCfg.fullWidgetWidth
				local dockXPos = dockCfg.xPos

				local colAvailableWidth = fullWidgetWidth - (numColumns - 1) * cfg.widgetSplitterWidth
				local hasCustomRatios = false
				local colTotalRatio = 0
				for _, col in ipairs(columns) do
					if col[1].widthRatio then
						hasCustomRatios = true
						colTotalRatio = colTotalRatio + col[1].widthRatio
					else
						colTotalRatio = colTotalRatio + 1
					end
				end

				local colXPos = dockXPos
				for ci, col in ipairs(columns) do
					local colWidth
					if hasCustomRatios then
						colWidth = colAvailableWidth * ((col[1].widthRatio or 1) / colTotalRatio)
					else
						colWidth = colAvailableWidth / numColumns
					end

					local columnHeight = mdw.getColumnHeight(col)
					local gapHeight = rowHeight - columnHeight

					if gapHeight >= cfg.minWidgetHeight then
						-- Check if cursor is within this column's horizontal bounds and gap area
						local gapTop = rowTop + columnHeight
						local gapBottom = rowTop + rowHeight
						if headerX >= colXPos and headerX <= colXPos + colWidth
							and headerY >= gapTop and headerY <= gapBottom then
							return "subcolumn", rowIndex, col[1].rowPosition or 0, col[#col]
						end
					end

					colXPos = colXPos + colWidth + cfg.widgetSplitterWidth
				end
			end

			-- Middle zone - check for side-by-side
			local sideBySideTopZone = rowTop + rowHeight * sideBySideZone
			local sideBySideBottomZone = rowTop + rowHeight * (1 - sideBySideZone)
			local inSideBySideZone = headerY >= sideBySideTopZone and headerY <= sideBySideBottomZone
			local numInRow = #columns -- Use columns count for side-by-side detection

			-- Build flat list of first widgets per column for side-by-side detection
			local colFirstWidgets = {}
			for _, col in ipairs(columns) do
				colFirstWidgets[#colFirstWidgets + 1] = col[1]
			end

			for i, w in ipairs(colFirstWidgets) do
				local wX = w.container:get_x()
				local wW = w.container:get_width()
				local wMidX = wX + wW / 2
				local isFirst = (i == 1)
				local isLast = (i == numInRow)

				-- Left of first widget
				if isFirst and headerX < wMidX and inSideBySideZone then
					local leftEdge = widgetLeftX or headerX
					if leftEdge <= wX then
						return "left", rowIndex, 0, w
					end
				end

				-- Right of last widget
				if isLast and headerX > wMidX and inSideBySideZone then
					local rightEdge = widgetRightX or headerX
					if (wX + wW) - rightEdge < -sideBySideOffset then
						return "right", rowIndex, i, w
					end
				end

				-- Between columns
				if not isLast and inSideBySideZone then
					local nextW = colFirstWidgets[i + 1]
					local nextX = nextW.container:get_x()
					local gapMid = (wX + wW + nextX) / 2

					if headerX >= wMidX and headerX <= nextX + nextW.container:get_width() / 2 then
						if headerX < gapMid then
							return "between", rowIndex, i, w
						else
							return "between", rowIndex, i, nextW
						end
					end
				end
			end

			-- Default to above/below based on position
			if headerY < rowMidY then
				return "above", rowIndex, 0, nil
			else
				return "below", rowIndex, 0, nil
			end
		end

		-- Cursor is in the gap between rows: snap to the closer edge
		if headerY < rowMidY then
			return "above", rowIndex, 0, nil
		end

		yPos = rowBottom
	end

	return "below", #rows, 0, nil
end

--- Update the drop indicator position during drag.
function mdw.updateDropIndicator(widget)
	local cfg = mdw.config

	local widgetX = widget.container:get_x()
	local widgetY = widget.container:get_y()
	local widgetW = widget.container:get_width()
	local centerX = widgetX + widgetW / 2
	local headerY = widgetY + cfg.titleHeight / 2

	-- Detect dock zone
	local side = mdw.getDockZoneAtPoint(centerX, headerY)
	if not side then
		side = mdw.getDockZoneAtPoint(widgetX, headerY)
	end
	if not side then
		side = mdw.getDockZoneAtPoint(widgetX + widgetW, headerY)
	end

	mdw.updateDockHighlight(side)

	if not side then
		mdw.hideDropIndicator()
		mdw.drag.insertSide = nil
		mdw.drag.dropType = nil
		mdw.drag.rowIndex = nil
		mdw.drag.positionInRow = nil
		mdw.drag.targetWidget = nil
		return
	end

	local dockCfg = mdw.getDockConfig(side)
	local fullWidgetWidth = dockCfg.fullWidgetWidth
	local dockXPos = dockCfg.xPos

	local dropType, rowIndex, positionInRow, targetWidget = mdw.detectDropPosition(
		side, centerX, headerY, widget, widgetX, widgetX + widgetW)

	local docked = mdw.getDockedWidgets(side, widget)
	local rows = mdw.groupWidgetsByRow(docked)

	-- Hide all indicators
	mdw.leftDropIndicator:hide()
	mdw.rightDropIndicator:hide()
	mdw.verticalDropIndicator:hide()

	-- Calculate positions and show appropriate indicator
	local yPos = cfg.headerHeight + cfg.widgetMargin
	local indicatorSpace = cfg.dropIndicatorHeight + 4

	for ri, row in ipairs(rows) do
		local columns = mdw.groupWidgetsByColumn(row)
		local numColumns = #columns

		-- Calculate row height = max column height
		local rowHeight = 0
		for _, col in ipairs(columns) do
			rowHeight = math.max(rowHeight, mdw.getColumnHeight(col))
		end

		-- Show horizontal indicator above this row
		if dropType == "above" and ri == rowIndex then
			local indicator = dockCfg.dropIndicator
			indicator:move(dockXPos, yPos)
			indicator:resize(fullWidgetWidth, cfg.dropIndicatorHeight)
			indicator:show()
			yPos = yPos + indicatorSpace
		end

		-- Calculate column widths
		local availableWidth = fullWidgetWidth - (numColumns - 1) * cfg.widgetSplitterWidth
		local totalRatio = 0
		local hasCustomRatios = false

		for _, col in ipairs(columns) do
			if col[1].widthRatio then
				hasCustomRatios = true
				totalRatio = totalRatio + col[1].widthRatio
			else
				totalRatio = totalRatio + 1
			end
		end

		local xPos = dockXPos
		for ci, col in ipairs(columns) do
			local columnWidth
			if hasCustomRatios then
				columnWidth = availableWidth * ((col[1].widthRatio or 1) / totalRatio)
			else
				columnWidth = availableWidth / numColumns
			end

			-- Show vertical indicator for side-by-side
			if (dropType == "left" or dropType == "right" or dropType == "between") and ri == rowIndex then
				if dropType == "left" and ci == 1 then
					mdw.verticalDropIndicator:move(xPos - cfg.dropIndicatorHeight / 2, yPos)
					mdw.verticalDropIndicator:resize(cfg.dropIndicatorHeight, rowHeight)
					mdw.verticalDropIndicator:show()
				elseif dropType == "right" and ci == positionInRow then
					mdw.verticalDropIndicator:move(xPos + columnWidth - cfg.dropIndicatorHeight / 2, yPos)
					mdw.verticalDropIndicator:resize(cfg.dropIndicatorHeight, rowHeight)
					mdw.verticalDropIndicator:show()
				elseif dropType == "between" and ci == positionInRow then
					mdw.verticalDropIndicator:move(
					xPos + columnWidth + cfg.widgetSplitterWidth / 2 - cfg.dropIndicatorHeight / 2, yPos)
					mdw.verticalDropIndicator:resize(cfg.dropIndicatorHeight, rowHeight)
					mdw.verticalDropIndicator:show()
				end
			end

			-- Show sub-column drop indicator at the bottom of the target column
			if dropType == "subcolumn" and ri == rowIndex and (col[1].rowPosition or 0) == positionInRow then
				local columnHeight = mdw.getColumnHeight(col)
				local indicator = dockCfg.dropIndicator
				indicator:move(xPos, yPos + columnHeight - cfg.dropIndicatorHeight / 2)
				indicator:resize(columnWidth, cfg.dropIndicatorHeight)
				indicator:show()
			end

			-- Position each widget in the column at its own height (NOT forced to rowHeight)
			local colYPos = yPos
			for _, w in ipairs(col) do
				local widgetHeight = w.container:get_height()
				w.container:move(xPos, colYPos)
				w.container:resize(columnWidth, widgetHeight)
				mdw.resizeWidgetContent(w, columnWidth, widgetHeight)
				colYPos = colYPos + widgetHeight
			end

			xPos = xPos + columnWidth + cfg.widgetSplitterWidth
		end

		-- Show horizontal indicator below this row
		if dropType == "below" and ri == rowIndex then
			yPos = yPos + rowHeight
			dockCfg.dropIndicator:move(dockXPos, yPos - cfg.dropIndicatorHeight / 2)
			dockCfg.dropIndicator:resize(fullWidgetWidth, cfg.dropIndicatorHeight)
			dockCfg.dropIndicator:show()
		else
			yPos = yPos + rowHeight
		end
	end

	-- Empty dock indicator
	if dropType == "above" and #rows == 0 then
		dockCfg.dropIndicator:move(dockXPos, cfg.headerHeight + cfg.widgetMargin)
		dockCfg.dropIndicator:resize(fullWidgetWidth, cfg.dropIndicatorHeight)
		dockCfg.dropIndicator:show()
	end

	-- Store drop position for endDrag
	mdw.drag.insertSide = side
	mdw.drag.dropType = dropType
	mdw.drag.rowIndex = rowIndex
	mdw.drag.positionInRow = positionInRow
	mdw.drag.targetWidget = targetWidget
end

function mdw.updateDockHighlight(side)
	-- Use separate overlay elements instead of changing dock stylesheet
	-- This avoids rendering artifacts that occur when dock style changes
	if not mdw.leftDockHighlight or not mdw.rightDockHighlight then return end

	if side == "left" then
		mdw.leftDockHighlight:show()
		mdw.rightDockHighlight:hide()
	elseif side == "right" then
		mdw.rightDockHighlight:show()
		mdw.leftDockHighlight:hide()
	else
		mdw.leftDockHighlight:hide()
		mdw.rightDockHighlight:hide()
	end
end

function mdw.hideDropIndicator()
	mdw.leftDropIndicator:hide()
	mdw.rightDropIndicator:hide()
	mdw.verticalDropIndicator:hide()
end

function mdw.hideDropIndicators()
	mdw.hideDropIndicator()
	mdw.updateDockHighlight(nil)
	mdw.drag.insertSide = nil
	mdw.drag.dropType = nil
	mdw.drag.rowIndex = nil
	mdw.drag.positionInRow = nil
	mdw.drag.targetWidget = nil
	mdw.reorganizeDock("left")
	mdw.reorganizeDock("right")
end

---------------------------------------------------------------------------
-- DOCK MANAGEMENT
-- Functions for docking widgets and organizing dock layouts.
---------------------------------------------------------------------------

--- Dock a widget at a specific detected position.
-- Why: Handles the complex logic of inserting a widget into the dock
-- at the correct row and position, shifting other widgets as needed.
function mdw.dockWidgetWithPosition(widget, side, dropType, rowIndex, positionInRow, targetWidget)
	local cfg = mdw.config
	local dockCfg = mdw.getDockConfig(side)

	mdw.debugEcho("DOCK: widget=%s, side=%s, dropType=%s, rowIndex=%s",
		widget.name, side, dropType, tostring(rowIndex))

	-- Don't dock if sidebar is hidden
	if not mdw.visibility[dockCfg.visibilityKey] then
		widget.docked = nil
		widget.row = nil
		widget.rowPosition = nil
		widget.subRow = nil
		mdw.showResizeHandles(widget)
		return
	end

	widget.docked = side
	widget.widthRatio = nil
	mdw.updateDockButtonVisibility(widget)

	local docked = mdw.getDockedWidgets(side, widget)
	local rows = mdw.groupWidgetsByRow(docked)

	if dropType == "left" or dropType == "right" or dropType == "between" then
		-- Side-by-side insertion
		widget.subRow = 0
		if targetWidget then
			widget.row = targetWidget.row or 0
			local targetHeight = targetWidget.container:get_height()
			widget.container:resize(nil, targetHeight)
			mdw.resizeWidgetContent(widget, widget.container:get_width(), targetHeight)

			-- Clear width ratios for row (ratios invalid with new widget count)
			for _, w in ipairs(docked) do
				if w.row == widget.row then
					w.widthRatio = nil
				end
			end

			if dropType == "left" then
				widget.rowPosition = targetWidget.rowPosition or 0
			else -- "between" or "right"
				widget.rowPosition = (targetWidget.rowPosition or 0) + 1
			end
			for _, w in ipairs(docked) do
				if w.row == widget.row and (w.rowPosition or 0) >= widget.rowPosition then
					w.rowPosition = (w.rowPosition or 0) + 1
				end
			end
		else
			widget.row = rowIndex - 1
			widget.rowPosition = positionInRow
		end
	elseif dropType == "subcolumn" then
		-- Sub-column insertion: dock into empty space below shorter column
		widget.row = targetWidget.row
		widget.rowPosition = targetWidget.rowPosition
		widget.subRow = (targetWidget.subRow or 0) + 1

		-- Shift existing widgets in this column at or after new subRow
		for _, w in ipairs(docked) do
			if w.row == widget.row
				and w.rowPosition == widget.rowPosition
				and (w.subRow or 0) >= widget.subRow then
				w.subRow = (w.subRow or 0) + 1
			end
		end

		-- Auto-fill gap: compute remaining space in the column
		-- Only use existing docked widgets (not the new one) to find max column height,
		-- because the new widget's stale height would inflate the target column total
		local allRowWidgets = {}
		for _, w in ipairs(docked) do
			if w.row == widget.row then
				allRowWidgets[#allRowWidgets + 1] = w
			end
		end

		local allColumns = mdw.groupWidgetsByColumn(allRowWidgets)
		local maxColHeight = 0
		for _, col in ipairs(allColumns) do
			maxColHeight = math.max(maxColHeight, mdw.getColumnHeight(col))
		end

		-- Find the target column's current total height
		local targetColumnHeight = 0
		for _, col in ipairs(allColumns) do
			if col[1].rowPosition == widget.rowPosition then
				for _, w in ipairs(col) do
					targetColumnHeight = targetColumnHeight + w.container:get_height()
				end
				break
			end
		end

		local gapHeight = maxColHeight - targetColumnHeight
		gapHeight = math.max(gapHeight, cfg.minWidgetHeight)

		widget.container:resize(nil, gapHeight)
		mdw.resizeWidgetContent(widget, widget.container:get_width(), gapHeight)
		widget.widthRatio = targetWidget.widthRatio
	else
		-- Vertical insertion (above or below)
		widget.subRow = 0
		local targetVisualRow = rows[rowIndex]
		local actualRowNum = 0
		if targetVisualRow and #targetVisualRow > 0 then
			actualRowNum = targetVisualRow[1].row or 0
		end

		local newRow
		if dropType == "above" then
			newRow = actualRowNum
		else -- below
			newRow = actualRowNum + 1
		end
		for _, w in ipairs(docked) do
			if (w.row or 0) >= newRow then
				w.row = (w.row or 0) + 1
			end
		end
		widget.row = newRow
		widget.rowPosition = 0
	end

	mdw.reorganizeDock(side)
end

function mdw.dockWidget(widget, side, row)
	widget.docked = side

	if row then
		-- Shift existing widgets down if inserting at specific row
		local docked = mdw.getDockedWidgets(side, widget)
		for _, w in ipairs(docked) do
			if (w.row or 0) >= row then
				w.row = (w.row or 0) + 1
			end
		end
		widget.row = row
		widget.rowPosition = 0
		widget.subRow = 0
	else
		-- Auto-assign to next row
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

--- Reorganize all widgets in a dock side.
-- Why: Called after any change to dock contents to ensure proper
-- positioning and sizing of all widgets.
function mdw.reorganizeDock(side)
	local cfg = mdw.config
	local dockCfg = mdw.getDockConfig(side)
	local docked = mdw.getDockedWidgets(side, nil)

	-- FIRST: Destroy all existing splitters for this side (prevents orphans)
	mdw.destroyRowSplittersForSide(side)

	-- Assign default rows to widgets without row info
	local maxRow = -1
	for _, w in ipairs(docked) do
		if w.row then
			maxRow = math.max(maxRow, w.row)
		end
	end
	for _, w in ipairs(docked) do
		if not w.row then
			maxRow = maxRow + 1
			w.row = maxRow
			w.rowPosition = 0
		end
	end

	local rows = mdw.groupWidgetsByRow(docked)
	local fullWidgetWidth = dockCfg.fullWidgetWidth
	local dockXPos = dockCfg.xPos
	local _, winH = getMainWindowSize()
	local lastRowIdx = #rows

	-- Reset fill/lock eligibility for all docked widgets
	for _, w in ipairs(docked) do
		w._canFill = false
		w._canLock = false
	end

	local yPos = cfg.headerHeight + cfg.widgetMargin
	local dockIndex = 1

	-- Pre-calculate fill row heights: sum non-fill row heights first,
	-- then distribute remaining space to fill rows so they don't push
	-- other rows off screen.
	local fillRowIndices = {}
	local nonFillRowHeight = 0
	for ri, row in ipairs(rows) do
		local rowColumns = mdw.groupWidgetsByColumn(row)
		local hasFill = false
		for _, col in ipairs(rowColumns) do
			for _, w in ipairs(col) do
				if w.fill then hasFill = true; break end
			end
			if hasFill then break end
		end
		if hasFill then
			fillRowIndices[ri] = true
		else
			local rh = 0
			for _, col in ipairs(rowColumns) do
				rh = math.max(rh, mdw.getColumnHeight(col))
			end
			nonFillRowHeight = nonFillRowHeight + rh
		end
	end
	local numFillRows = 0
	for _ in pairs(fillRowIndices) do numFillRows = numFillRows + 1 end
	-- Space left for fill rows after non-fill rows claim their height
	local fillRowBudget = math.max(0, winH - yPos - nonFillRowHeight)

	for rowIdx, row in ipairs(rows) do
		local columns = mdw.groupWidgetsByColumn(row)
		local numColumns = #columns

		-- Normalize subRow values to be contiguous (0, 1, 2...)
		for _, col in ipairs(columns) do
			for i, w in ipairs(col) do
				w.subRow = i - 1
			end
		end

		-- Normalize rowPosition after column grouping to prevent gaps
		for ci, col in ipairs(columns) do
			for _, w in ipairs(col) do
				w.rowPosition = ci - 1
			end
		end

		-- Calculate column widths using widthRatio from first widget in each column
		local availableWidth = fullWidgetWidth - (numColumns - 1) * cfg.widgetSplitterWidth
		local hasCustomRatios = false
		local totalRatio = 0
		for _, col in ipairs(columns) do
			local firstWidget = col[1]
			if firstWidget.widthRatio then
				hasCustomRatios = true
				totalRatio = totalRatio + firstWidget.widthRatio
			else
				totalRatio = totalRatio + 1
			end
		end

		-- Calculate lock-aware column widths
		local lockedTotal = 0
		local unlockedCols = {}
		local hasLocked = false
		local hasUnlocked = false
		for _, col in ipairs(columns) do
			local first = col[1]
			if first.widthLocked and first.lockedWidth then
				hasLocked = true
				lockedTotal = lockedTotal + first.lockedWidth
			else
				hasUnlocked = true
				unlockedCols[#unlockedCols + 1] = col
			end
		end
		-- Only apply lock logic when mixed (some locked, some not)
		local useLockLayout = hasLocked and hasUnlocked and lockedTotal < availableWidth

		-- Calculate row height = max column height across all columns
		-- Fill rows get an equal share of the remaining vertical budget
		local rowHeight = 0
		if fillRowIndices[rowIdx] then
			local fillHeight = numFillRows > 0 and (fillRowBudget / numFillRows) or 0
			for _, col in ipairs(columns) do
				local colHasFill = false
				for _, w in ipairs(col) do
					if w.fill then colHasFill = true; break end
				end
				if colHasFill then
					rowHeight = math.max(rowHeight, fillHeight)
				else
					rowHeight = math.max(rowHeight, mdw.getColumnHeight(col))
				end
			end
		else
			for _, col in ipairs(columns) do
				rowHeight = math.max(rowHeight, mdw.getColumnHeight(col))
			end
		end

		local xPos = dockXPos
		for ci, col in ipairs(columns) do
			local first = col[1]
			local columnWidth

			if useLockLayout then
				if first.widthLocked and first.lockedWidth then
					columnWidth = first.lockedWidth
				else
					-- Distribute remaining space among unlocked columns by ratio
					local remaining = availableWidth - lockedTotal
					local unlockedRatio = 0
					for _, uc in ipairs(unlockedCols) do
						unlockedRatio = unlockedRatio + (uc[1].widthRatio or 1)
					end
					columnWidth = remaining * ((first.widthRatio or 1) / unlockedRatio)
				end
			else
				if hasCustomRatios then
					columnWidth = availableWidth * ((first.widthRatio or 1) / totalRatio)
				else
					columnWidth = availableWidth / numColumns
				end
			end

			-- Enforce minimum width
			columnWidth = math.max(cfg.minWidgetWidth, columnWidth)

			-- Check if any widget in this column has fill enabled
			local fillWidgets = {}
			local nonFillHeight = 0
			for _, w in ipairs(col) do
				if w.fill then
					fillWidgets[#fillWidgets + 1] = w
				else
					nonFillHeight = nonFillHeight + w.container:get_height()
				end
			end

			-- Lay out widgets vertically within the column
			local colYPos = yPos
			if #fillWidgets > 0 then
				local fillSpace = math.max(0, rowHeight - nonFillHeight)
				local fillPerWidget = math.max(cfg.minWidgetHeight, fillSpace / #fillWidgets)

				for _, w in ipairs(col) do
					local widgetHeight = w.fill and fillPerWidget or w.container:get_height()
					local maxHeight = winH - colYPos
					if widgetHeight > maxHeight then
						widgetHeight = math.max(cfg.minWidgetHeight, maxHeight)
					end

					w.container:move(xPos, colYPos)
					w.container:resize(columnWidth, widgetHeight)
					if numColumns == 1 then
						w.widthRatio = nil
					end
					w.dockIndex = dockIndex

					mdw.resizeWidgetContent(w, columnWidth, widgetHeight)

					-- Hide bottom resize handle for fill widgets (height is computed)
					if w.fill and w.bottomResizeHandle then
						w.bottomResizeHandle:hide()
					elseif w.docked and w.bottomResizeHandle then
						w.bottomResizeHandle:show()
					end

					dockIndex = dockIndex + 1
					colYPos = colYPos + widgetHeight
				end
			else
				-- Original non-fill layout
				for _, w in ipairs(col) do
					local widgetHeight = w.container:get_height()

					-- Clamp height so widget doesn't extend below window bottom
					local maxHeight = winH - colYPos
					if widgetHeight > maxHeight then
						widgetHeight = math.max(cfg.minWidgetHeight, maxHeight)
					end

					w.container:move(xPos, colYPos)
					w.container:resize(columnWidth, widgetHeight)
					if numColumns == 1 then
						w.widthRatio = nil
					end
					w.dockIndex = dockIndex

					mdw.resizeWidgetContent(w, columnWidth, widgetHeight)

					-- Restore bottom resize handle for docked non-fill widgets
					if w.docked and w.bottomResizeHandle then
						w.bottomResizeHandle:show()
					end

					dockIndex = dockIndex + 1
					colYPos = colYPos + widgetHeight
				end
			end

			-- Mark last widget in each column of the last row as fill-eligible
			local lastInCol = col[#col]
			if rowIdx == lastRowIdx then
				lastInCol._canFill = true
			end

			-- Lock is only useful in side-by-side (multi-column) rows
			if numColumns > 1 then
				for _, w in ipairs(col) do
					w._canLock = true
				end
			end

			-- Update fill/lock button visibility for all widgets in this column
			for _, w in ipairs(col) do
				if w.fillButton then
					if w._canFill then
						w.fillButton:show()
						mdw.updateFillButtonText(w)
					else
						-- Auto-disable fill if widget lost eligibility
						if w.fill then
							w.fill = false
							if w._preFillHeight then
								w.container:resize(nil, w._preFillHeight)
								mdw.resizeWidgetContent(w, w.container:get_width(), w._preFillHeight)
								w._preFillHeight = nil
							end
						end
						w.fillButton:hide()
					end
				end
				if w.lockButton then
					if w._canLock then
						w.lockButton:show()
						mdw.updateLockButtonText(w)
					else
						-- Auto-disable lock if no longer side-by-side
						if w.widthLocked then
							w.widthLocked = false
							w.lockedWidth = nil
						end
						w.lockButton:hide()
					end
				end
			end

			-- CREATE SPLITTER between this column and next (if exists)
			-- Splitter height = rowHeight (max column height)
			if ci < numColumns then
				local nextCol = columns[ci + 1]
				mdw.createRowSplitter(side, rowIdx, ci, col[1], nextCol[1], xPos + columnWidth, yPos, rowHeight)
			end

			xPos = xPos + columnWidth + cfg.widgetSplitterWidth
		end

		yPos = yPos + rowHeight
	end

	mdw.applyZOrder()
end

---------------------------------------------------------------------------
-- ROW SPLITTER MANAGEMENT
-- Manages separate splitter elements between side-by-side widgets.
---------------------------------------------------------------------------

function mdw.getSplitterKey(side, rowIndex, leftPosition)
	return string.format("%s_%d_%d", side, rowIndex, leftPosition)
end

--- Create row splitters between side-by-side widgets.
function mdw.createRowSplitter(side, rowIndex, leftPosition, leftWidget, rightWidget, x, y, height)
	local cfg = mdw.config
	local key = mdw.getSplitterKey(side, rowIndex, leftPosition)

	-- Destroy existing splitter with this key if it exists
	if mdw.rowSplitters[key] then
		mdw.destroyRowSplitter(key)
	end

	-- Create the splitter label
	local splitterName = "MDW_RowSplitter_" .. key
	local splitter = Geyser.Label:new({
		name = splitterName,
		x = x,
		y = y,
		width = cfg.widgetSplitterWidth,
		height = height,
	})
	splitter:setStyleSheet(string.format([[
    QLabel { background-color: %s; }
    QLabel:hover { background-color: %s; }
  ]], cfg.resizeBorderColor, cfg.splitterHoverColor))
	splitter:setCursor(mudlet.cursor.ResizeHorizontal)

	-- Store splitter with metadata
	mdw.rowSplitters[key] = splitter
	splitter._mdwKey = key
	splitter._mdwSide = side
	splitter._mdwLeftWidget = leftWidget
	splitter._mdwRightWidget = rightWidget

	-- Set up drag callbacks
	mdw.setupRowSplitterCallbacks(splitter, key)
end

function mdw.setupRowSplitterCallbacks(splitter, key)
	local splitterName = splitter.name

	setLabelClickCallback(splitterName, function(event)
		local s = mdw.rowSplitters[key]
		if not s then return end

		local leftWidget = s._mdwLeftWidget
		local rightWidget = s._mdwRightWidget
		local side = s._mdwSide

		if not leftWidget or not rightWidget then return end

		mdw.verticalWidgetSplitterDrag.active = true
		mdw.verticalWidgetSplitterDrag.splitter = s
		mdw.verticalWidgetSplitterDrag.leftWidget = leftWidget
		mdw.verticalWidgetSplitterDrag.rightWidget = rightWidget
		mdw.verticalWidgetSplitterDrag.side = side
		mdw.verticalWidgetSplitterDrag.offsetX = event.globalX - s:get_x()
		mdw.verticalWidgetSplitterDrag.leftStartWidth = leftWidget.container:get_width()
		mdw.verticalWidgetSplitterDrag.rightStartWidth = rightWidget.container:get_width()
		mdw.verticalWidgetSplitterDrag.startMouseX = event.globalX
	end)

	setLabelMoveCallback(splitterName, function(event)
		local s = mdw.rowSplitters[key]
		if not s then return end
		if mdw.verticalWidgetSplitterDrag.active and mdw.verticalWidgetSplitterDrag.splitter == s then
			mdw.resizeWidgetsHorizontallyWithSplitter(event.globalX, s)
		end
	end)

	setLabelReleaseCallback(splitterName, function()
		local s = mdw.rowSplitters[key]
		if not s then return end
		if mdw.verticalWidgetSplitterDrag.active and mdw.verticalWidgetSplitterDrag.splitter == s then
			local leftWidget = mdw.verticalWidgetSplitterDrag.leftWidget
			local rightWidget = mdw.verticalWidgetSplitterDrag.rightWidget
			mdw.verticalWidgetSplitterDrag.active = false
			mdw.verticalWidgetSplitterDrag.splitter = nil
			mdw.verticalWidgetSplitterDrag.leftWidget = nil
			mdw.verticalWidgetSplitterDrag.rightWidget = nil
			mdw.verticalWidgetSplitterDrag.side = nil
			-- Update locked widths after manual splitter drag
			if leftWidget and leftWidget.widthLocked then
				leftWidget.lockedWidth = leftWidget.container:get_width()
			end
			if rightWidget and rightWidget.widthLocked then
				rightWidget.lockedWidth = rightWidget.container:get_width()
			end
			mdw.saveLayout()
		end
	end)
end

function mdw.destroyRowSplitter(key)
	local splitter = mdw.rowSplitters[key]
	if splitter then
		splitter:hide()
		if splitter.name then
			pcall(deleteLabel, splitter.name)
		end
		mdw.rowSplitters[key] = nil
	end
end

function mdw.destroyRowSplittersForSide(side)
	local keysToDelete = {}
	for key in pairs(mdw.rowSplitters) do
		if key:sub(1, #side) == side then
			keysToDelete[#keysToDelete + 1] = key
		end
	end
	for _, key in ipairs(keysToDelete) do
		mdw.destroyRowSplitter(key)
	end
end

function mdw.destroyAllRowSplitters()
	local keysToDelete = {}
	for key in pairs(mdw.rowSplitters) do
		keysToDelete[#keysToDelete + 1] = key
	end
	for _, key in ipairs(keysToDelete) do
		mdw.destroyRowSplitter(key)
	end
end

--- Update row splitter positions and heights for a dock side.
-- Called during vertical resize to keep splitters in sync with widgets.
function mdw.updateRowSplitterPositions(side, rows)
	local cfg = mdw.config

	for rowIdx, row in ipairs(rows) do
		local rowY = row[1].container:get_y()

		-- Group into columns and update splitters between columns
		local columns = mdw.groupWidgetsByColumn(row)
		local rowHeight = 0
		for _, col in ipairs(columns) do
			rowHeight = math.max(rowHeight, mdw.getColumnHeight(col))
		end

		for ci = 1, #columns - 1 do
			local key = mdw.getSplitterKey(side, rowIdx, ci)
			local splitter = mdw.rowSplitters[key]
			if splitter then
				local leftCol = columns[ci]
				local leftWidget = leftCol[1]
				local xPos = leftWidget.container:get_x() + leftWidget.container:get_width()
				splitter:move(xPos, rowY)
				splitter:resize(cfg.widgetSplitterWidth, rowHeight)
			end
		end
	end
end

--- Resize two side-by-side widgets horizontally using a row splitter.
function mdw.resizeWidgetsHorizontallyWithSplitter(mouseX, splitter)
	local drag = mdw.verticalWidgetSplitterDrag
	if not drag.active then return end

	local cfg = mdw.config
	local leftWidget = drag.leftWidget
	local rightWidget = drag.rightWidget
	local side = drag.side

	local deltaX = mouseX - drag.startMouseX
	local minWidth = cfg.minWidgetWidth
	local newLeftWidth = drag.leftStartWidth + deltaX
	local newRightWidth = drag.rightStartWidth - deltaX
	local totalWidth = drag.leftStartWidth + drag.rightStartWidth

	if newLeftWidth < minWidth then
		newLeftWidth = minWidth
		newRightWidth = totalWidth - minWidth
	end
	if newRightWidth < minWidth then
		newRightWidth = minWidth
		newLeftWidth = totalWidth - minWidth
	end

	-- Collect all row widgets and group into columns once
	local docked = mdw.getDockedWidgets(side, nil)
	local rowWidgets = {}
	for _, w in ipairs(docked) do
		if w.row == leftWidget.row then
			rowWidgets[#rowWidgets + 1] = w
		end
	end
	local columns = mdw.groupWidgetsByColumn(rowWidgets)

	-- Resize all widgets in both columns, update ratios and positions
	local leftRowPos = leftWidget.rowPosition
	local rightRowPos = rightWidget.rowPosition
	local newRightX = leftWidget.container:get_x() + newLeftWidth + cfg.widgetSplitterWidth
	local rowTotalWidth = 0

	for _, col in ipairs(columns) do
		local pos = col[1].rowPosition
		local newWidth
		if pos == leftRowPos then
			newWidth = newLeftWidth
		elseif pos == rightRowPos then
			newWidth = newRightWidth
		end

		if newWidth then
			for _, w in ipairs(col) do
				w.container:resize(newWidth, nil)
				mdw.resizeWidgetContent(w, newWidth, w.container:get_height())
				if pos == rightRowPos then
					w.container:move(newRightX, nil)
				end
			end
		end

		-- All columns contribute to total width (not just the two being resized)
		rowTotalWidth = rowTotalWidth + col[1].container:get_width()
	end

	-- Set width ratios on all widgets per column
	for _, col in ipairs(columns) do
		local ratio = col[1].container:get_width() / rowTotalWidth
		for _, w in ipairs(col) do
			w.widthRatio = ratio
		end
	end

	-- Move the splitter
	splitter:move(leftWidget.container:get_x() + newLeftWidth, nil)
end

---------------------------------------------------------------------------
-- WIDGET RESIZE HANDLING
-- Handles resizing of docked and floating widgets.
---------------------------------------------------------------------------

--- Reposition sub-column siblings below a resized widget.
-- Why: When a widget in a sub-column is resized, widgets below it in the
-- same column must move to stay contiguous.
function mdw.repositionColumnSiblings(widget, rows, rowIndex, newHeight)
	local currentRow = rows[rowIndex]
	local columns = mdw.groupWidgetsByColumn(currentRow)

	for _, col in ipairs(columns) do
		local found = false
		local colYPos = 0
		for _, w in ipairs(col) do
			if w == widget then
				found = true
				colYPos = w.container:get_y() + newHeight
			elseif found then
				w.container:move(nil, colYPos)
				mdw.resizeWidgetContent(w, w.container:get_width(), w.container:get_height())
				colYPos = colYPos + w.container:get_height()
			end
		end
	end
end

--- Reposition all rows below the given row index.
-- Why: After a widget resize changes a row's total height, all subsequent
-- rows must shift to maintain contiguous vertical layout.
function mdw.repositionSubsequentRows(widget, rows, rowIndex, newHeight)
	local currentRow = rows[rowIndex]
	local columns = mdw.groupWidgetsByColumn(currentRow)

	-- Find row top from the first widget in the first column
	local rowTop = currentRow[1].container:get_y()

	-- Calculate current row height using the new height for the resized widget
	local currentRowMaxHeight = 0
	for _, col in ipairs(columns) do
		local colHeight = 0
		for _, w in ipairs(col) do
			if w == widget then
				colHeight = colHeight + newHeight
			else
				colHeight = colHeight + w.container:get_height()
			end
		end
		currentRowMaxHeight = math.max(currentRowMaxHeight, colHeight)
	end

	local nextRowY = rowTop + currentRowMaxHeight

	for rowIdx = rowIndex + 1, #rows do
		local row = rows[rowIdx]
		local rowColumns = mdw.groupWidgetsByColumn(row)
		local rowMaxHeight = 0
		for _, col in ipairs(rowColumns) do
			rowMaxHeight = math.max(rowMaxHeight, mdw.getColumnHeight(col))
		end

		-- Position each column's widgets vertically
		for _, col in ipairs(rowColumns) do
			local colYPos = nextRowY
			for _, w in ipairs(col) do
				w.container:move(nil, colYPos)
				mdw.resizeWidgetContent(w, w.container:get_width(), w.container:get_height())
				colYPos = colYPos + w.container:get_height()
			end
		end

		nextRowY = nextRowY + rowMaxHeight
	end
end

--- Resize a widget vertically with snap to adjacent widgets.
function mdw.resizeWidgetWithSnap(widget, side, targetBottomY)
	local cfg = mdw.config
	local widgetTop = widget.container:get_y()
	local newHeight = targetBottomY - widgetTop

	newHeight = math.max(cfg.minWidgetHeight, newHeight)

	local _, winH = getMainWindowSize()
	local maxHeight = winH - widgetTop - cfg.sideBySideOffset
	newHeight = math.min(newHeight, maxHeight)

	-- Check for snap to other columns' total heights in same row
	local docked = mdw.getDockedWidgets(side, nil)
	local rows = mdw.groupWidgetsByRow(docked)

	local widgetRowIndex = nil
	for rowIdx, row in ipairs(rows) do
		for _, w in ipairs(row) do
			if w == widget then
				widgetRowIndex = rowIdx

				-- Group into columns and snap to other columns' total heights
				local columns = mdw.groupWidgetsByColumn(row)
				local widgetColIdx = nil
				for ci, col in ipairs(columns) do
					for _, cw in ipairs(col) do
						if cw == widget then
							widgetColIdx = ci
							break
						end
					end
					if widgetColIdx then break end
				end

				if widgetColIdx and #columns > 1 then
					local snapped = false

					-- Calculate this column's total height with the new height
					local myCol = columns[widgetColIdx]
					local myColHeight = 0
					for _, cw in ipairs(myCol) do
						if cw == widget then
							myColHeight = myColHeight + newHeight
						else
							myColHeight = myColHeight + cw.container:get_height()
						end
					end

					-- Snap to other columns' total heights
					for ci, col in ipairs(columns) do
						if ci ~= widgetColIdx then
							local otherColHeight = mdw.getColumnHeight(col)
							if math.abs(myColHeight - otherColHeight) < cfg.snapThreshold then
								-- Adjust newHeight so the column total matches
								local otherWidgetsHeight = myColHeight - newHeight
								newHeight = otherColHeight - otherWidgetsHeight
								newHeight = math.max(cfg.minWidgetHeight, newHeight)
								snapped = true
								break
							end
						end
					end

					-- Snap this widget's bottom edge to other widgets' bottom edges
					if not snapped then
						local myBottom = widgetTop + newHeight
						for ci, col in ipairs(columns) do
							if ci ~= widgetColIdx then
								local bottomY = col[1].container:get_y()
								for _, cw in ipairs(col) do
									bottomY = bottomY + cw.container:get_height()
									if math.abs(myBottom - bottomY) < cfg.snapThreshold then
										newHeight = bottomY - widgetTop
										newHeight = math.max(cfg.minWidgetHeight, newHeight)
										snapped = true
										break
									end
								end
								if snapped then break end
							end
						end
					end
				else
					-- Single-column row: snap to other widgets' heights in the row
					for _, w2 in ipairs(row) do
						if w2 ~= widget then
							local otherHeight = w2.container:get_height()
							if math.abs(newHeight - otherHeight) < cfg.snapThreshold then
								newHeight = otherHeight
								break
							end
						end
					end
				end
				break
			end
		end
		if widgetRowIndex then break end
	end

	local currentWidth = widget.container:get_width()
	widget.container:resize(nil, newHeight)
	-- Pass explicit dimensions to avoid Geyser timing issues
	mdw.resizeWidgetContent(widget, currentWidth, newHeight)

	-- Reposition sub-column siblings and subsequent rows
	if widgetRowIndex then
		mdw.repositionColumnSiblings(widget, rows, widgetRowIndex, newHeight)
		mdw.repositionSubsequentRows(widget, rows, widgetRowIndex, newHeight)
	end

	-- Update row splitter positions and heights during resize
	mdw.updateRowSplitterPositions(side, rows)
end

---------------------------------------------------------------------------
-- FLOATING WIDGET RESIZE
-- Handles resize borders for floating (undocked) widgets.
---------------------------------------------------------------------------

--- Set up resize borders for a floating widget.
--- Set up a single resize border.
function mdw.setupResizeBorder(internalWidget, border, edge)
	local cfg = mdw.config
	local borderName = border.name
	local widgetName = internalWidget.name

	setLabelClickCallback(borderName, function(event)
		local widget = mdw.widgets[widgetName]
		if not widget then return end
		mdw.resizeDrag.active = true
		mdw.resizeDrag.widget = widget
		mdw.resizeDrag.edge = edge
		mdw.resizeDrag.startX = widget.container:get_x()
		mdw.resizeDrag.startY = widget.container:get_y()
		mdw.resizeDrag.startWidth = widget.container:get_width()
		mdw.resizeDrag.startHeight = widget.container:get_height()
		mdw.resizeDrag.startMouseX = event.globalX
		mdw.resizeDrag.startMouseY = event.globalY
	end)

	setLabelMoveCallback(borderName, function(event)
		local widget = mdw.widgets[widgetName]
		if not widget then return end
		if mdw.resizeDrag.active and mdw.resizeDrag.widget == widget and mdw.resizeDrag.edge == edge then
			local deltaX = event.globalX - mdw.resizeDrag.startMouseX
			local deltaY = event.globalY - mdw.resizeDrag.startMouseY

			if edge == "left" then
				local newWidth = math.max(cfg.minFloatingWidth, mdw.resizeDrag.startWidth - deltaX)
				local newX = math.max(0, mdw.resizeDrag.startX + (mdw.resizeDrag.startWidth - newWidth))
				widget.container:move(newX, nil)
				widget.container:resize(newWidth, nil)
				mdw.resizeWidgetContent(widget, newWidth, widget.container:get_height())
			elseif edge == "right" then
				local newWidth = math.max(cfg.minFloatingWidth, mdw.resizeDrag.startWidth + deltaX)
				widget.container:resize(newWidth, nil)
				mdw.resizeWidgetContent(widget, newWidth, widget.container:get_height())
			elseif edge == "bottom" then
				local newHeight = math.max(cfg.minWidgetHeight, mdw.resizeDrag.startHeight + deltaY)
				widget.container:resize(nil, newHeight)
				mdw.resizeWidgetContent(widget, widget.container:get_width(), newHeight)
			elseif edge == "top" then
				local newHeight = math.max(cfg.minWidgetHeight, mdw.resizeDrag.startHeight - deltaY)
				local newY = math.max(0, mdw.resizeDrag.startY + (mdw.resizeDrag.startHeight - newHeight))
				widget.container:move(nil, newY)
				widget.container:resize(nil, newHeight)
				mdw.resizeWidgetContent(widget, widget.container:get_width(), newHeight)
			elseif edge == "topLeft" then
				local newWidth = math.max(cfg.minFloatingWidth, mdw.resizeDrag.startWidth - deltaX)
				local newX = math.max(0, mdw.resizeDrag.startX + (mdw.resizeDrag.startWidth - newWidth))
				local newHeight = math.max(cfg.minWidgetHeight, mdw.resizeDrag.startHeight - deltaY)
				local newY = math.max(0, mdw.resizeDrag.startY + (mdw.resizeDrag.startHeight - newHeight))
				widget.container:move(newX, newY)
				widget.container:resize(newWidth, newHeight)
				mdw.resizeWidgetContent(widget, newWidth, newHeight)
			elseif edge == "topRight" then
				local newWidth = math.max(cfg.minFloatingWidth, mdw.resizeDrag.startWidth + deltaX)
				local newHeight = math.max(cfg.minWidgetHeight, mdw.resizeDrag.startHeight - deltaY)
				local newY = math.max(0, mdw.resizeDrag.startY + (mdw.resizeDrag.startHeight - newHeight))
				widget.container:move(nil, newY)
				widget.container:resize(newWidth, newHeight)
				mdw.resizeWidgetContent(widget, newWidth, newHeight)
			elseif edge == "bottomLeft" then
				local newWidth = math.max(cfg.minFloatingWidth, mdw.resizeDrag.startWidth - deltaX)
				local newX = math.max(0, mdw.resizeDrag.startX + (mdw.resizeDrag.startWidth - newWidth))
				local newHeight = math.max(cfg.minWidgetHeight, mdw.resizeDrag.startHeight + deltaY)
				widget.container:move(newX, nil)
				widget.container:resize(newWidth, newHeight)
				mdw.resizeWidgetContent(widget, newWidth, newHeight)
			elseif edge == "bottomRight" then
				local newWidth = math.max(cfg.minFloatingWidth, mdw.resizeDrag.startWidth + deltaX)
				local newHeight = math.max(cfg.minWidgetHeight, mdw.resizeDrag.startHeight + deltaY)
				widget.container:resize(newWidth, newHeight)
				mdw.resizeWidgetContent(widget, newWidth, newHeight)
			end

			mdw.updateResizeBorders(widget)
		end
	end)

	setLabelReleaseCallback(borderName, function()
		local widget = mdw.widgets[widgetName]
		if not widget then return end
		if mdw.resizeDrag.active and mdw.resizeDrag.widget == widget and mdw.resizeDrag.edge == edge then
			mdw.resizeDrag.active = false
			mdw.resizeDrag.widget = nil
			mdw.resizeDrag.edge = nil
			mdw.saveLayout()
			mdw.refreshWidgetContent(widget)
		end
	end)
end

function mdw.updateResizeBorders(widget)
	if not widget or not widget.container then return end
	if not widget.resizeLeft then return end -- Borders may not exist yet

	local cfg = mdw.config
	local x = widget.container:get_x()
	local y = widget.container:get_y()
	local w = widget.container:get_width()
	local h = widget.container:get_height()
	local bw = cfg.resizeBorderWidth
	local hw = cfg.resizeHitWidth
	local cs = cfg.resizeCornerSize

	-- Edges: hw-wide hit target, visible 2px border on widget-facing side
	widget.resizeLeft:move(x - hw, y - bw)
	widget.resizeLeft:resize(hw, h + bw * 2)

	widget.resizeRight:move(x + w, y - bw)
	widget.resizeRight:resize(hw, h + bw * 2)

	widget.resizeBottom:move(x - bw, y + h)
	widget.resizeBottom:resize(w + bw * 2, hw)

	widget.resizeTop:move(x - bw, y - hw)
	widget.resizeTop:resize(w + bw * 2, hw)

	-- Corners: cs x cs squares overlapping the ends of adjacent edges
	if widget.resizeTopLeft then
		widget.resizeTopLeft:move(x - hw, y - hw)
		widget.resizeTopLeft:resize(hw + cs, hw + cs)
	end
	if widget.resizeTopRight then
		widget.resizeTopRight:move(x + w - cs, y - hw)
		widget.resizeTopRight:resize(hw + cs, hw + cs)
	end
	if widget.resizeBottomLeft then
		widget.resizeBottomLeft:move(x - hw, y + h - cs)
		widget.resizeBottomLeft:resize(hw + cs, hw + cs)
	end
	if widget.resizeBottomRight then
		widget.resizeBottomRight:move(x + w - cs, y + h - cs)
		widget.resizeBottomRight:resize(hw + cs, hw + cs)
	end
end

function mdw.showResizeHandles(widget)
	if not widget then return end
	local cfg = mdw.config

	if widget.resizeLeft then widget.resizeLeft:show() end
	if widget.resizeRight then widget.resizeRight:show() end
	if widget.resizeBottom then widget.resizeBottom:show() end
	if widget.resizeTop then widget.resizeTop:show() end
	if widget.resizeTopLeft then widget.resizeTopLeft:show() end
	if widget.resizeTopRight then widget.resizeTopRight:show() end
	if widget.resizeBottomLeft then widget.resizeBottomLeft:show() end
	if widget.resizeBottomRight then widget.resizeBottomRight:show() end
	mdw.updateResizeBorders(widget)

	-- Hide docked bottom resize handle when floating (use the border resize handles instead)
	if widget.bottomResizeHandle then
		widget.bottomResizeHandle:hide()
		-- Shrink container once to remove the gap left by the hidden handle.
		-- Guard: only adjust if not already adjusted (prevents double-shrink).
		if not widget._floatingHeightAdjusted then
			widget._floatingHeightAdjusted = true
			local cw = widget.container:get_width()
			local ch = widget.container:get_height()
			local newH = ch - cfg.widgetSplitterHeight
			widget.container:resize(nil, newH)
			mdw.resizeWidgetContent(widget, cw, newH)
			mdw.updateResizeBorders(widget)
		end
	end

	mdw.applyZOrder()
end

function mdw.hideResizeHandles(widget)
	if not widget then return end

	if widget.resizeLeft then widget.resizeLeft:hide() end
	if widget.resizeRight then widget.resizeRight:hide() end
	if widget.resizeBottom then widget.resizeBottom:hide() end
	if widget.resizeTop then widget.resizeTop:hide() end
	if widget.resizeTopLeft then widget.resizeTopLeft:hide() end
	if widget.resizeTopRight then widget.resizeTopRight:hide() end
	if widget.resizeBottomLeft then widget.resizeBottomLeft:hide() end
	if widget.resizeBottomRight then widget.resizeBottomRight:hide() end

	-- Show docked bottom resize handle when docked
	if widget.bottomResizeHandle and widget.docked then
		-- Grow container back once to accommodate the docked resize handle
		if widget._floatingHeightAdjusted then
			widget._floatingHeightAdjusted = false
			local cfg = mdw.config
			local cw = widget.container:get_width()
			local ch = widget.container:get_height()
			local newH = ch + cfg.widgetSplitterHeight
			widget.container:resize(nil, newH)
			mdw.resizeWidgetContent(widget, cw, newH)
		end
		widget.bottomResizeHandle:show()
	end
end

---------------------------------------------------------------------------
-- UI INITIALIZATION
-- Creates header menus and finalizes widget layout.
---------------------------------------------------------------------------

--- Initialize UI components after widgets are created.
-- Called by mdw.setup() to create header menus and organize docks.
-- Widgets are created separately via mdw.registerWidgets() or mdwReady event.
function mdw.createWidgets()
	-- Create header menus
	mdw.createHeaderMenus()

	-- Position any widgets that were created
	mdw.reorganizeDock("left")
	mdw.reorganizeDock("right")

	mdw.echo("Created " .. #mdw.elements .. " UI elements")
end

---------------------------------------------------------------------------
-- HEADER MENUS
-- Dropdown menus in the header bar.
---------------------------------------------------------------------------

--- Create header menu buttons.
function mdw.createHeaderMenus()
	local cfg = mdw.config

	-- Layout menu button
	mdw.layoutButton = mdw.trackElement(Geyser.Label:new({
		name = "MDW_LayoutButton",
		x = cfg.menuPaddingLeft,
		y = 0,
		width = cfg.headerButtonWidth,
		height = cfg.headerHeight - cfg.separatorHeight,
	}, mdw.headerPane))
	mdw.layoutButton:setStyleSheet(mdw.styles.headerButton)
	mdw.layoutButton:setFontSize(cfg.headerMenuFontSize)
	mdw.layoutButton:decho("<" .. cfg.headerTextColor .. ">Layout")
	mdw.layoutButton:setCursor(mudlet.cursor.PointingHand)
	setLabelClickCallback("MDW_LayoutButton", function()
		mdw.toggleLayoutMenu()
	end)

	-- Widgets menu button
	mdw.widgetsButton = mdw.trackElement(Geyser.Label:new({
		name = "MDW_WidgetsButton",
		x = cfg.menuPaddingLeft + cfg.headerButtonWidth,
		y = 0,
		width = cfg.headerButtonWidth,
		height = cfg.headerHeight - cfg.separatorHeight,
	}, mdw.headerPane))
	mdw.widgetsButton:setStyleSheet(mdw.styles.headerButton)
	mdw.widgetsButton:setFontSize(cfg.headerMenuFontSize)
	mdw.widgetsButton:decho("<" .. cfg.headerTextColor .. ">Widgets")
	mdw.widgetsButton:setCursor(mudlet.cursor.PointingHand)
	setLabelClickCallback("MDW_WidgetsButton", function()
		mdw.toggleWidgetsMenu()
	end)

	mdw.createLayoutDropdown()
	mdw.createWidgetsDropdown()
end

--- Create the Layout dropdown menu.
function mdw.createLayoutDropdown()
	local cfg = mdw.config
	local menuWidth = cfg.menuWidth
	local menuX = cfg.menuPaddingLeft
	local menuY = cfg.headerHeight - cfg.menuOverlap -- Overlap top border with header button's bottom border

	-- Build items from configuration with current visibility state
	local items = {}
	for _, itemDef in ipairs(cfg.layoutMenuItems) do
		items[#items + 1] = {
			name = itemDef.name,
			label = itemDef.label,
			visible = mdw.visibility[itemDef.name],
		}
	end
	local menuHeight = #items * cfg.menuItemHeight + cfg.menuPadding * 2

	mdw.layoutMenuBg = mdw.trackElement(Geyser.Label:new({
		name = "MDW_LayoutMenuBg",
		x = menuX,
		y = menuY,
		width = menuWidth,
		height = menuHeight,
	}))
	mdw.layoutMenuBg:setStyleSheet(mdw.styles.menuBackground)
	mdw.layoutMenuBg:hide()

	mdw.layoutMenuItems = {}
	mdw.layoutMenuLabels = {}

	for i, item in ipairs(items) do
		local yPos = menuY + cfg.menuPadding + (i - 1) * cfg.menuItemHeight
		local menuItem = mdw.trackElement(Geyser.Label:new({
			name = "MDW_LayoutMenu_" .. item.name,
			x = menuX,
			y = yPos,
			width = menuWidth,
			height = cfg.menuItemHeight,
		}))
		menuItem:setStyleSheet(mdw.styles.menuItem)
		menuItem:setFontSize(cfg.headerMenuFontSize)
		mdw.updateMenuItemText(menuItem, item.label, item.visible)
		menuItem:setCursor(mudlet.cursor.PointingHand)
		menuItem:hide()

		local itemName = item.name
		setLabelClickCallback("MDW_LayoutMenu_" .. itemName, function()
			mdw.toggleLayoutItem(itemName)
		end)
		setLabelOnEnter("MDW_LayoutMenu_" .. itemName, function()
			mdw.updateMenuItemText(menuItem, item.label, mdw.visibility[itemName], true)
		end)
		setLabelOnLeave("MDW_LayoutMenu_" .. itemName, function()
			mdw.updateMenuItemText(menuItem, item.label, mdw.visibility[itemName], false)
		end)

		mdw.layoutMenuItems[item.name] = { label = menuItem, text = item.label }
		mdw.layoutMenuLabels[#mdw.layoutMenuLabels + 1] = menuItem
	end
end

function mdw.getWidgetNames()
	local names = {}
	for name in pairs(mdw.widgets) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

--- Create the Widgets dropdown menu.
function mdw.createWidgetsDropdown()
	local cfg = mdw.config
	local menuWidth = cfg.menuWidth
	local menuX = cfg.menuPaddingLeft + cfg.headerButtonWidth -- After Layout button
	local menuY = cfg.headerHeight - cfg.menuOverlap        -- Overlap top border with header button's bottom border
	local items = mdw.getWidgetNames()
	local menuHeight = math.max(#items, 1) * cfg.menuItemHeight + cfg.menuPadding * 2

	mdw.widgetsMenuBg = mdw.trackElement(Geyser.Label:new({
		name = "MDW_WidgetsMenuBg",
		x = menuX,
		y = menuY,
		width = menuWidth,
		height = menuHeight,
	}))
	mdw.widgetsMenuBg:setStyleSheet(mdw.styles.menuBackground)
	mdw.widgetsMenuBg:hide()

	mdw.widgetsMenuItems = {}
	mdw.widgetsMenuLabels = {}

	for i, widgetName in ipairs(items) do
		mdw.addWidgetMenuItem(widgetName, i)
	end
end

--- Add a single widget menu item.
function mdw.addWidgetMenuItem(widgetName, index)
	local cfg = mdw.config
	local menuWidth = cfg.menuWidth
	local menuX = cfg.menuPaddingLeft + cfg.headerButtonWidth -- After Layout button
	local menuY = cfg.headerHeight - cfg.menuOverlap

	-- Calculate position
	local i = index or (#mdw.widgetsMenuLabels + 1)
	local yPos = menuY + cfg.menuPadding + (i - 1) * cfg.menuItemHeight

	local menuItem = mdw.trackElement(Geyser.Label:new({
		name = "MDW_WidgetsMenu_" .. widgetName,
		x = menuX,
		y = yPos,
		width = menuWidth,
		height = cfg.menuItemHeight,
	}))
	menuItem:setStyleSheet(mdw.styles.menuItem)
	menuItem:setFontSize(cfg.headerMenuFontSize)

	local widget = mdw.widgets[widgetName]
	local isShown = widget and mdw.isWidgetShown(widget)
	mdw.updateMenuItemText(menuItem, widgetName, isShown)
	menuItem:setCursor(mudlet.cursor.PointingHand)
	menuItem:hide()

	local wName = widgetName
	setLabelClickCallback("MDW_WidgetsMenu_" .. widgetName, function()
		mdw.toggleWidget(wName)
	end)
	setLabelOnEnter("MDW_WidgetsMenu_" .. widgetName, function()
		local w = mdw.widgets[wName]
		local shown = w and mdw.isWidgetShown(w)
		mdw.updateMenuItemText(menuItem, wName, shown, true)
	end)
	setLabelOnLeave("MDW_WidgetsMenu_" .. widgetName, function()
		local w = mdw.widgets[wName]
		local shown = w and mdw.isWidgetShown(w)
		mdw.updateMenuItemText(menuItem, wName, shown, false)
	end)

	mdw.widgetsMenuItems[widgetName] = { label = menuItem, text = widgetName }
	mdw.widgetsMenuLabels[#mdw.widgetsMenuLabels + 1] = menuItem
end

--- Rebuild the widgets menu to reflect current widgets.
-- Call this after adding or removing widgets.
function mdw.rebuildWidgetsMenu()
	if not mdw.widgetsMenuBg then return end

	-- Close menu if open
	if mdw.menus.widgetsOpen then
		mdw.hideWidgetsMenu()
	end

	-- Remove old menu items
	for _, item in pairs(mdw.widgetsMenuItems) do
		if item.label then
			item.label:hide()
			if item.label.name then
				deleteLabel(item.label.name)
			end
		end
	end

	-- Remove old background
	if mdw.widgetsMenuBg then
		mdw.widgetsMenuBg:hide()
		deleteLabel("MDW_WidgetsMenuBg")
	end

	-- Recreate the menu
	local cfg = mdw.config
	local menuWidth = cfg.menuWidth
	local menuX = cfg.menuPaddingLeft + cfg.headerButtonWidth -- After Layout button
	local menuY = cfg.headerHeight - cfg.menuOverlap
	local items = mdw.getWidgetNames()
	local menuHeight = math.max(#items, 1) * cfg.menuItemHeight + cfg.menuPadding * 2

	mdw.widgetsMenuBg = mdw.trackElement(Geyser.Label:new({
		name = "MDW_WidgetsMenuBg",
		x = menuX,
		y = menuY,
		width = menuWidth,
		height = menuHeight,
	}))
	mdw.widgetsMenuBg:setStyleSheet(mdw.styles.menuBackground)
	mdw.widgetsMenuBg:hide()

	mdw.widgetsMenuItems = {}
	mdw.widgetsMenuLabels = {}

	for i, widgetName in ipairs(items) do
		mdw.addWidgetMenuItem(widgetName, i)
	end
end

--- Update menu item text with checkbox.
function mdw.updateMenuItemText(menuItem, text, checked, highlighted)
	local cfg = mdw.config
	local checkmark = checked and "[x] " or "[ ] "
	local textColor = highlighted and cfg.menuHighlightColor or cfg.menuTextColor
	local checkColor = highlighted and cfg.menuHighlightColor or cfg.headerTextColor
	menuItem:decho("<" .. checkColor .. ">" .. checkmark .. "<" .. textColor .. ">" .. text)
end

---------------------------------------------------------------------------
-- MENU HELPERS
-- Shared utilities for dropdown menu management.
---------------------------------------------------------------------------

--- Show a dropdown menu with its items.
-- Why: Consolidates the repetitive pattern of showing overlay, styling button,
-- showing background, and raising all menu items.
local function showMenu(menuBg, menuLabels, button)
	mdw.createMenuOverlay()
	button:setStyleSheet(mdw.styles.headerButtonActive)
	menuBg:show()
	for _, label in ipairs(menuLabels) do
		label:show()
	end
	mdw.applyZOrder()
end

--- Hide a dropdown menu.
-- Why: Consolidates the repetitive pattern of hiding background, items,
-- and restoring button styling.
local function hideMenu(menuBg, menuLabels, button)
	button:setStyleSheet(mdw.styles.headerButton)
	menuBg:hide()
	for _, label in ipairs(menuLabels) do
		label:hide()
	end
end

---------------------------------------------------------------------------
-- MENU OVERLAY
-- Transparent overlay for click-away-to-close behavior.
---------------------------------------------------------------------------

function mdw.createMenuOverlay()
	if mdw.menuOverlay then return end

	mdw.menuOverlay = Geyser.Label:new({
		name = "MDW_MenuOverlay",
		x = 0,
		y = mdw.config.headerHeight,
		width = "100%",
		height = "100%",
	})
	mdw.menuOverlay:setStyleSheet([[background-color: transparent;]])

	setLabelClickCallback("MDW_MenuOverlay", function(event)
		local clickX, clickY = event.globalX, event.globalY

		-- Check if click is within layout menu
		if mdw.menus.layoutOpen and mdw.layoutMenuBg then
			local mx, my = mdw.layoutMenuBg:get_x(), mdw.layoutMenuBg:get_y()
			local mw, mh = mdw.layoutMenuBg:get_width(), mdw.layoutMenuBg:get_height()
			if clickX >= mx and clickX <= mx + mw and clickY >= my and clickY <= my + mh then
				return
			end
		end

		-- Check if click is within widgets menu
		if mdw.menus.widgetsOpen and mdw.widgetsMenuBg then
			local mx, my = mdw.widgetsMenuBg:get_x(), mdw.widgetsMenuBg:get_y()
			local mw, mh = mdw.widgetsMenuBg:get_width(), mdw.widgetsMenuBg:get_height()
			if clickX >= mx and clickX <= mx + mw and clickY >= my and clickY <= my + mh then
				return
			end
		end

		mdw.closeAllMenus()
	end)
end

function mdw.destroyMenuOverlay()
	if mdw.menuOverlay then
		mdw.menuOverlay:hide()
		mdw.menuOverlay = nil
		deleteLabel("MDW_MenuOverlay")
	end
end

function mdw.showLayoutMenu()
	mdw.menus.layoutOpen = true
	showMenu(mdw.layoutMenuBg, mdw.layoutMenuLabels, mdw.layoutButton)
end

function mdw.hideLayoutMenu()
	hideMenu(mdw.layoutMenuBg, mdw.layoutMenuLabels, mdw.layoutButton)
	mdw.menus.layoutOpen = false
	if not mdw.menus.widgetsOpen then
		mdw.destroyMenuOverlay()
	end
end

function mdw.showWidgetsMenu()
	mdw.menus.widgetsOpen = true
	showMenu(mdw.widgetsMenuBg, mdw.widgetsMenuLabels, mdw.widgetsButton)
end

function mdw.hideWidgetsMenu()
	hideMenu(mdw.widgetsMenuBg, mdw.widgetsMenuLabels, mdw.widgetsButton)
	mdw.menus.widgetsOpen = false
	if not mdw.menus.layoutOpen then
		mdw.destroyMenuOverlay()
	end
end

function mdw.toggleLayoutMenu()
	if mdw.menus.layoutOpen then
		mdw.hideLayoutMenu()
	else
		mdw.showLayoutMenu()
		if mdw.menus.widgetsOpen then
			mdw.hideWidgetsMenu()
		end
	end
end

function mdw.toggleWidgetsMenu()
	if mdw.menus.widgetsOpen then
		mdw.hideWidgetsMenu()
	else
		mdw.showWidgetsMenu()
		if mdw.menus.layoutOpen then
			mdw.hideLayoutMenu()
		end
	end
end

function mdw.closeAllMenus()
	if mdw.layoutMenuLabels and mdw.menus.layoutOpen then
		mdw.hideLayoutMenu()
	end
	if mdw.widgetsMenuLabels and mdw.menus.widgetsOpen then
		mdw.hideWidgetsMenu()
	end
	mdw.destroyMenuOverlay()
end

--- Re-raise open menus above other elements.
-- Delegates to applyZOrder() which handles all z-order concerns.
function mdw.raiseOpenMenus()
	mdw.applyZOrder()
end

---------------------------------------------------------------------------
-- SIDEBAR VISIBILITY TOGGLES
---------------------------------------------------------------------------

function mdw.toggleLayoutItem(itemName)
	mdw.visibility[itemName] = not mdw.visibility[itemName]
	local item = mdw.layoutMenuItems[itemName]
	if item then
		mdw.updateMenuItemText(item.label, item.text, mdw.visibility[itemName])
	end

	if itemName == "leftSidebar" then
		mdw.toggleLeftSidebar()
	elseif itemName == "rightSidebar" then
		mdw.toggleRightSidebar()
	elseif itemName == "promptBar" then
		mdw.togglePromptBar()
	end
end

--- Toggle sidebar visibility (internal helper).
-- Why: Consolidated logic that was duplicated between left and right toggles.
local function toggleSidebar(side)
	local dockCfg = mdw.getDockConfig(side)
	local isVisible = mdw.visibility[dockCfg.visibilityKey]

	mdw.applyBorders()

	if isVisible then
		dockCfg.dock:show()
		dockCfg.splitter:show()

		for _, w in pairs(mdw.widgets) do
			if w.originalDock == side then
				w.docked = side
				w.originalDock = nil
				if w.visible ~= false then
					w.container:show()
					mdw.showWidgetContent(w)
				end
				mdw.hideResizeHandles(w)
			end
		end
		mdw.reorganizeDock(side)
	else
		dockCfg.dock:hide()
		dockCfg.splitter:hide()
		if dockCfg.dockHighlight then dockCfg.dockHighlight:hide() end
		if dockCfg.dropIndicator then dockCfg.dropIndicator:hide() end
		if mdw.verticalDropIndicator then mdw.verticalDropIndicator:hide() end

		-- Destroy row splitters for this side
		mdw.destroyRowSplittersForSide(side)

		for _, w in pairs(mdw.widgets) do
			if w.docked == side then
				w.originalDock = side
				w.docked = nil
				w.container:hide()
				mdw.hideResizeHandles(w)
			end
		end
	end

	mdw.updateWidgetsMenuState()
	mdw.updatePromptBar()
	mdw.saveLayout()
end

function mdw.toggleLeftSidebar()
	toggleSidebar("left")
end

function mdw.toggleRightSidebar()
	toggleSidebar("right")
end

function mdw.togglePromptBar()
	mdw.applyBorders()

	if mdw.visibility.promptBar then
		if mdw.promptBarContainer then mdw.promptBarContainer:show() end
		mdw.promptSeparator:show()
	else
		if mdw.promptBarContainer then mdw.promptBarContainer:hide() end
		mdw.promptSeparator:hide()
	end
	mdw.raiseOpenMenus()
	mdw.saveLayout()
end

function mdw.updatePromptBar()
	local cfg = mdw.config
	local winW = getMainWindowSize()
	local leftOffset = mdw.visibility.leftSidebar and cfg.leftDockWidth or 0
	local rightOffset = mdw.visibility.rightSidebar and cfg.rightDockWidth or 0
	local promptBarWidth = winW - leftOffset - rightOffset
	local consoleWidth = promptBarWidth - cfg.contentPaddingLeft

	if mdw.promptBarContainer then
		mdw.promptBarContainer:move(leftOffset, nil)
		mdw.promptBarContainer:resize(promptBarWidth, nil)
	end
	if mdw.promptBar then
		mdw.promptBar:resize(consoleWidth, nil)
		if mdw.promptBar.setWrap then
			mdw.promptBar:setWrap(mdw.calculateWrap(consoleWidth))
		end
	end
	if mdw.promptSeparator then
		mdw.promptSeparator:move(leftOffset, nil)
		mdw.promptSeparator:resize(promptBarWidth, nil)
	end
end

---------------------------------------------------------------------------
-- WIDGET VISIBILITY
---------------------------------------------------------------------------

--- Check if a widget is currently shown on screen.
function mdw.isWidgetShown(widget)
	if widget.visible == false then return false end

	local dockSide = widget.docked or widget.originalDock
	if not dockSide then
		return true
	end

	if dockSide == "left" then
		return mdw.visibility.leftSidebar
	elseif dockSide == "right" then
		return mdw.visibility.rightSidebar
	end

	return true
end

function mdw.toggleWidget(widgetName)
	local widget = mdw.widgets[widgetName]
	if not widget then return end

	local isCurrentlyShown = mdw.isWidgetShown(widget)

	if isCurrentlyShown then
		widget.container:hide()
		mdw.hideResizeHandles(widget)
		widget.visible = false
	else
		widget.visible = true
		local dockSide = widget.docked or widget.originalDock

		if dockSide then
			if mdw.isSidebarVisible(dockSide) then
				widget.docked = dockSide
				widget.originalDock = nil
				widget.container:show()
				mdw.hideResizeHandles(widget)
				mdw.reorganizeDock(dockSide)
			else
				widget.container:show()
				mdw.floatWidgetCentered(widget)
			end
		else
			widget.container:show()
			mdw.showResizeHandles(widget)
		end

		mdw.showWidgetContent(widget)
	end

	local item = mdw.widgetsMenuItems[widgetName]
	if item then
		mdw.updateMenuItemText(item.label, item.text, not isCurrentlyShown)
	end

	if mdw.visibility.leftSidebar then mdw.reorganizeDock("left") end
	if mdw.visibility.rightSidebar then mdw.reorganizeDock("right") end

	mdw.saveLayout()
end

function mdw.floatWidgetCentered(widget)
	local cfg = mdw.config
	local winW, winH = getMainWindowSize()
	local leftOffset = mdw.visibility.leftSidebar and cfg.leftDockWidth or 0
	local rightOffset = mdw.visibility.rightSidebar and cfg.rightDockWidth or 0

	local mainWidth = winW - leftOffset - rightOffset
	local mainHeight = winH - cfg.headerHeight - (mdw.visibility.promptBar and cfg.promptBarHeight or 0)

	local widgetW = widget.container:get_width()
	local widgetH = widget.container:get_height()

	local centerX = leftOffset + (mainWidth - widgetW) / 2
	local centerY = cfg.headerHeight + (mainHeight - widgetH) / 2

	widget.originalDock = widget.docked
	widget.docked = nil
	widget.container:move(centerX, centerY)
	widget.container:show()
	mdw.showWidgetContent(widget)
	mdw.showResizeHandles(widget)
end

function mdw.updateWidgetsMenuState()
	if not mdw.widgetsMenuItems then return end

	for widgetName, item in pairs(mdw.widgetsMenuItems) do
		local widget = mdw.widgets[widgetName]
		if widget then
			local isShown = mdw.isWidgetShown(widget)
			mdw.updateMenuItemText(item.label, item.text, isShown)
		end
	end
end
