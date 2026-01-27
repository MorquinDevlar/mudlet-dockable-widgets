--[[
  MDW_Widgets.lua
  Widget creation, drag/drop, dock management, and menus for MDW (Mudlet Dockable Widgets).

  Widgets are draggable containers that can be freely positioned or docked
  to left/right sidebars. Supports side-by-side docking, vertical stacking,
  and resize handles for both docked and floating widgets.

  Dependencies: MDW_Config.lua, MDW_Init.lua must be loaded first
]]

---------------------------------------------------------------------------
-- WIDGET CREATION
-- Factory functions for creating widget instances.
---------------------------------------------------------------------------

--- Create a widget with title bar and content area.
-- Why: Widgets are the primary UI component. Each widget has a draggable
-- title bar, content area, and optional resize borders for floating mode.
-- @param name string Unique identifier for the widget
-- @param title string Display title shown in the title bar
-- @param x number Initial X position
-- @param y number Initial Y position
-- @return table Widget instance
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
    width = cfg.leftDockWidth - totalMargin - cfg.splitterWidth,
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
  widget.titleBar:decho("<" .. cfg.headerTextColor .. ">" .. title)
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
  widget.bottomResizeHandle = mdw.trackElement(Geyser.Label:new({
    name = "MDW_" .. name .. "_BottomResize",
    x = 0,
    y = cfg.widgetHeight - cfg.widgetSplitterHeight,
    width = containerWidth,
    height = cfg.widgetSplitterHeight,
  }, widget.container))
  widget.bottomResizeHandle:setStyleSheet([[background-color: transparent;]])
  widget.bottomResizeHandle:setCursor(mudlet.cursor.ResizeVertical)
  widget.bottomResizeHandle:hide()  -- Hidden by default, shown when docked

  -- Create resize borders (hidden by default, shown when floating)
  mdw.createResizeBorders(widget)

  -- Set up docked resize handle callbacks
  mdw.setupDockedResizeHandle(widget)

  -- Set up drag callbacks
  mdw.setupWidgetDrag(widget)

  return widget
end

--- Create resize borders for a widget (used in floating mode).
-- Why: Floating widgets need resize handles so users can adjust dimensions.
-- Borders are absolute-positioned labels that track the widget's position.
-- @param widget table The widget to add resize borders to
function mdw.createResizeBorders(widget)
  local cfg = mdw.config
  local baseName = "MDW_" .. widget.name

  -- Left border
  widget.resizeLeft = mdw.trackElement(Geyser.Label:new({
    name = baseName .. "_ResizeLeft",
    x = 0, y = 0,
    width = cfg.resizeBorderWidth,
    height = 100,
  }))
  widget.resizeLeft:setStyleSheet(mdw.styles.splitter)
  widget.resizeLeft:setCursor(mudlet.cursor.ResizeHorizontal)
  widget.resizeLeft:hide()

  -- Right border
  widget.resizeRight = mdw.trackElement(Geyser.Label:new({
    name = baseName .. "_ResizeRight",
    x = 0, y = 0,
    width = cfg.resizeBorderWidth,
    height = 100,
  }))
  widget.resizeRight:setStyleSheet(mdw.styles.splitter)
  widget.resizeRight:setCursor(mudlet.cursor.ResizeHorizontal)
  widget.resizeRight:hide()

  -- Bottom border
  widget.resizeBottom = mdw.trackElement(Geyser.Label:new({
    name = baseName .. "_ResizeBottom",
    x = 0, y = 0,
    width = 100,
    height = cfg.resizeBorderWidth,
  }))
  widget.resizeBottom:setStyleSheet(mdw.styles.splitter)
  widget.resizeBottom:setCursor(mudlet.cursor.ResizeVertical)
  widget.resizeBottom:hide()

  -- Top border
  widget.resizeTop = mdw.trackElement(Geyser.Label:new({
    name = baseName .. "_ResizeTop",
    x = 0, y = 0,
    width = 100,
    height = cfg.resizeBorderWidth,
  }))
  widget.resizeTop:setStyleSheet(mdw.styles.splitter)
  widget.resizeTop:setCursor(mudlet.cursor.ResizeVertical)
  widget.resizeTop:hide()

  mdw.setupResizeBorders(widget)
end

--- Resize and reposition widget content after container changes.
-- Why: Ensures children match container dimensions after resize.
-- Uses relative positioning (children are parented to container).
-- @param widget table The widget to update
-- @param targetWidth number Optional explicit width (avoids Geyser timing issues)
-- @param targetHeight number Optional explicit height
function mdw.resizeWidgetContent(widget, targetWidth, targetHeight)
  local cfg = mdw.config

  -- Handle tabbed widgets
  if widget.isTabbed and widget._tabbedClass then
    mdw.resizeTabbedWidgetContent(widget._tabbedClass, targetWidth, targetHeight)
    return
  end

  -- Use provided dimensions or fall back to container dimensions
  local cw = targetWidth or widget.container:get_width()
  local ch = targetHeight or widget.container:get_height()

  -- Reserve space for bottom resize handle when docked
  local resizeHandleHeight = widget.docked and cfg.widgetSplitterHeight or 0
  local contentAreaHeight = ch - cfg.titleHeight - resizeHandleHeight
  local contentWidth = cw - cfg.contentPaddingLeft
  local contentHeight = contentAreaHeight - cfg.contentPaddingTop

  -- Use RELATIVE positions (children are parented to container)
  widget.titleBar:move(0, 0)
  widget.titleBar:resize(cw, cfg.titleHeight)

  -- Resize background label that fills the padding area
  if widget.contentBg then
    widget.contentBg:move(0, cfg.titleHeight)
    widget.contentBg:resize(cw, contentAreaHeight)
  end

  widget.content:move(cfg.contentPaddingLeft, cfg.titleHeight + cfg.contentPaddingTop)
  widget.content:resize(contentWidth, contentHeight)
  widget.content:setWrap(mdw.calculateWrap(contentWidth))

  if widget.mapper then
    widget.mapper:move(cfg.contentPaddingLeft, cfg.titleHeight + cfg.contentPaddingTop)
    widget.mapper:resize(contentWidth, contentHeight)
  end

  -- Position bottom resize handle at widget bottom
  if widget.bottomResizeHandle then
    widget.bottomResizeHandle:move(0, ch - cfg.widgetSplitterHeight)
    widget.bottomResizeHandle:resize(cw, cfg.widgetSplitterHeight)
  end
end


---------------------------------------------------------------------------
-- WIDGET DRAG HANDLING
-- Enables dragging widgets by their title bar.
---------------------------------------------------------------------------

--- Set up drag callbacks for a widget's title bar.
-- @param widget table The widget to set up drag for
function mdw.setupWidgetDrag(widget)
  local titleName = "MDW_" .. widget.name .. "_Title"

  setLabelClickCallback(titleName, function(event)
    mdw.startDrag(widget, event)
  end)

  setLabelMoveCallback(titleName, function(event)
    if mdw.drag.active and mdw.drag.widget == widget then
      mdw.handleDragMove(widget, event)
    end
  end)

  setLabelReleaseCallback(titleName, function(event)
    if mdw.drag.active and mdw.drag.widget == widget then
      mdw.endDrag(widget, event)
    end
  end)
end

--- Set up the docked bottom resize handle for vertical resizing.
-- Why: This handle is part of the widget itself (inside the container), so it
-- moves with the widget and doesn't need separate tracking/cleanup.
-- @param widget table The widget to set up
function mdw.setupDockedResizeHandle(widget)
  local handleName = "MDW_" .. widget.name .. "_BottomResize"

  setLabelClickCallback(handleName, function(event)
    mdw.widgetSplitterDrag.active = true
    mdw.widgetSplitterDrag.widget = widget
    mdw.widgetSplitterDrag.side = widget.docked
    mdw.widgetSplitterDrag.offsetY = event.globalY - widget.container:get_y() - widget.container:get_height()
  end)

  setLabelMoveCallback(handleName, function(event)
    if mdw.widgetSplitterDrag.active and mdw.widgetSplitterDrag.widget == widget then
      local side = widget.docked
      if side then
        local targetY = event.globalY - mdw.widgetSplitterDrag.offsetY
        mdw.resizeWidgetWithSnap(widget, side, targetY)
      end
    end
  end)

  setLabelReleaseCallback(handleName, function()
    if mdw.widgetSplitterDrag.active and mdw.widgetSplitterDrag.widget == widget then
      local side = widget.docked
      mdw.widgetSplitterDrag.active = false
      mdw.widgetSplitterDrag.widget = nil
      mdw.widgetSplitterDrag.side = nil
      if side then
        mdw.reorganizeDock(side)
      end
    end
  end)
end

--- Start dragging a widget.
-- Why: Records initial state but doesn't undock until actual movement occurs.
-- This prevents accidental undocking on simple clicks.
-- @param widget table The widget being dragged
-- @param event table Mouse event data
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

  widget.titleBar:setCursor(mudlet.cursor.ClosedHand)
  mdw.raiseWidget(widget)
end

--- Handle mouse movement during drag.
-- @param widget table The widget being dragged
-- @param event table Mouse event data
function mdw.handleDragMove(widget, event)
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
    local newY = math.max(0, event.globalY - mdw.drag.offsetY)
    widget.container:move(newX, newY)

    if not widget.docked then
      mdw.updateResizeBorders(widget)
    end

    mdw.updateDropIndicator(widget)
    mdw.raiseWidget(widget)
  end
end

--- Commit to a drag operation after movement threshold is exceeded.
-- Why: Separates click (no movement) from drag (movement detected).
-- Undocking and visual feedback only happen once we're sure it's a drag.
-- @param widget table The widget being dragged
function mdw.commitDragStart(widget)
  if mdw.drag.hasMoved then return end
  mdw.drag.hasMoved = true

  -- Now undock the widget
  widget.docked = nil
  widget.row = nil
  widget.rowPosition = nil

  -- Reorganize the dock we left (this handles splitters automatically)
  if mdw.drag.originalDock then
    mdw.reorganizeDock(mdw.drag.originalDock)
  end

  -- Apply dragging visual feedback (titleBar only, MiniConsole doesn't support setStyleSheet)
  widget.titleBar:setStyleSheet(mdw.styles.titleBarDragging)

  mdw.raiseWidget(widget)
end

--- End dragging a widget.
-- @param widget table The widget being dragged
-- @param event table Mouse event data
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

  mdw.debugEcho(string.format("ENDDRAG: widget=%s, hasMoved=%s, insertSide=%s, dropType=%s",
    widget.name, tostring(hasMoved), tostring(insertSide), tostring(dropType)))

  -- Clear drag state
  mdw.drag.active = false
  mdw.drag.widget = nil
  mdw.drag.originalDock = nil
  mdw.drag.originalRow = nil
  mdw.drag.originalRowPosition = nil
  mdw.drag.insertSide = nil
  mdw.drag.dropType = nil
  mdw.drag.rowIndex = nil
  mdw.drag.positionInRow = nil
  mdw.drag.targetWidget = nil
  mdw.drag.hasMoved = nil
  mdw.drag.startMouseX = nil
  mdw.drag.startMouseY = nil

  widget.titleBar:setCursor(mudlet.cursor.OpenHand)

  -- Restore normal styling
  if hasMoved then
    widget.titleBar:setStyleSheet(mdw.styles.titleBar)
  end

  mdw.hideDropIndicator()
  mdw.updateDockHighlight(nil)

  -- Restore original position if no movement
  if not hasMoved then
    if originalDock then
      widget.docked = originalDock
      widget.row = originalRow
      widget.rowPosition = originalRowPosition
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
    mdw.showResizeHandles(widget)
  end

  -- Always reorganize both docks to ensure splitters are properly cleaned up
  -- This handles cases where widgets move between docks or are undocked
  mdw.reorganizeDock("left")
  mdw.reorganizeDock("right")
end

--- Raise a widget above all others.
-- Why: Geyser doesn't automatically raise children with their container.
-- We must explicitly raise container AND all its children.
-- @param widget table The widget to raise
function mdw.raiseWidget(widget)
  -- Just raise the target widget and its children - don't lower others
  -- as that can push them below dock backgrounds
  widget.container:raise()
  widget.titleBar:raise()

  -- Handle tabbed widgets
  if widget.isTabbed and widget._tabbedClass then
    local tabbedWidget = widget._tabbedClass
    tabbedWidget.tabBar:raise()
    for _, tabObj in ipairs(tabbedWidget.tabObjects) do
      tabObj.button:raise()
    end
    -- Raise only the active tab's console
    local activeTab = tabbedWidget.tabObjects[tabbedWidget.activeTabIndex]
    if activeTab then
      activeTab.console:raise()
    end
  else
    widget.content:raise()
    if widget.mapper then
      widget.mapper:raise()
    end
  end
end

---------------------------------------------------------------------------
-- DROP DETECTION
-- Determines where a dragged widget should be inserted in a dock.
---------------------------------------------------------------------------

--- Get which dock zone a point is over.
-- @param x number X coordinate
-- @param y number Y coordinate
-- @return string|nil "left", "right", or nil if not over a dock
function mdw.getDockZoneAtPoint(x, y)
  local cfg = mdw.config
  local dropBuffer = cfg.dockDropBuffer

  if mdw.visibility.leftSidebar then
    local leftX = mdw.leftDock:get_x()
    local leftY = mdw.leftDock:get_y()
    local leftW = mdw.leftDock:get_width()
    local leftH = mdw.leftDock:get_height()

    if x >= leftX and x <= leftX + leftW + cfg.splitterWidth and
       y >= leftY - dropBuffer and y <= leftY + leftH + dropBuffer then
      return "left"
    end
  end

  if mdw.visibility.rightSidebar then
    local rightX = mdw.rightDock:get_x()
    local rightY = mdw.rightDock:get_y()
    local rightW = mdw.rightDock:get_width()
    local rightH = mdw.rightDock:get_height()

    if x >= rightX - cfg.splitterWidth and x <= rightX + rightW and
       y >= rightY - dropBuffer and y <= rightY + rightH + dropBuffer then
      return "right"
    end
  end

  return nil
end

--- Get sorted list of docked widgets for a side (excludes hidden widgets).
-- @param side string "left" or "right"
-- @param excludeWidget table|nil Widget to exclude from results
-- @return table Array of widgets sorted by row and position
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
    return (a.rowPosition or 0) < (b.rowPosition or 0)
  end)

  return docked
end

--- Group widgets by row number.
-- @param docked table Array of docked widgets
-- @return table Array of rows, each row is an array of widgets
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
      return (a.rowPosition or 0) < (b.rowPosition or 0)
    end)
    sortedRows[#sortedRows + 1] = rows[rowNum]
  end

  return sortedRows
end

--- Detect drop position within a dock.
-- Why: Uses spatial zones to determine insertion type:
-- - Top/bottom zone (configured by verticalInsertZone) triggers vertical insert
-- - Middle zone with horizontal offset triggers side-by-side placement
-- This dual-zone approach prevents accidental side-by-side when users intend vertical stacking.
-- @param side string "left" or "right"
-- @param headerX number Widget center X coordinate
-- @param headerY number Widget header Y coordinate
-- @param excludeWidget table Widget being dragged (excluded from calculations)
-- @param widgetLeftX number Widget's left edge X
-- @param widgetRightX number Widget's right edge X
-- @return string dropType, number rowIndex, number positionInRow, table|nil targetWidget
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
    local rowHeight = 0
    for _, w in ipairs(row) do
      rowHeight = math.max(rowHeight, w.container:get_height())
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

      -- Middle zone - check for side-by-side
      local sideBySideTopZone = rowTop + rowHeight * sideBySideZone
      local sideBySideBottomZone = rowTop + rowHeight * (1 - sideBySideZone)
      local inSideBySideZone = headerY >= sideBySideTopZone and headerY <= sideBySideBottomZone
      local numInRow = #row

      for i, w in ipairs(row) do
        local wX = w.container:get_x()
        local wW = w.container:get_width()
        local wMidX = wX + wW / 2
        local isFirst = (i == 1)
        local isLast = (i == numInRow)

        -- Left of first widget
        if isFirst and headerX < wMidX and inSideBySideZone then
          local leftEdge = widgetLeftX or headerX
          if leftEdge - wX < -sideBySideOffset then
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

        -- Between widgets
        if not isLast and inSideBySideZone then
          local nextW = row[i + 1]
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

    if headerY < rowMidY then
      return "above", rowIndex, 0, nil
    end

    yPos = rowBottom
  end

  return "below", #rows, 0, nil
end

--- Update drop indicator during drag.
-- @param widget table The widget being dragged
function mdw.updateDropIndicator(widget)
  local cfg = mdw.config

  -- Delete all widget splitters during drag to avoid visual artifacts
  -- We delete them entirely rather than just hiding, to prevent orphan issues
  mdw.deleteAllWidgetSplitters()

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
    local rowHeight = 0
    for _, w in ipairs(row) do
      rowHeight = math.max(rowHeight, w.container:get_height())
    end

    -- Show horizontal indicator above this row
    if dropType == "above" and ri == rowIndex then
      local indicator = dockCfg.dropIndicator
      indicator:move(dockXPos, yPos)
      indicator:resize(fullWidgetWidth, cfg.dropIndicatorHeight)
      indicator:raise()
      indicator:show()
      yPos = yPos + indicatorSpace
    end

    -- Position widgets and show vertical indicators
    local numInRow = #row
    local availableWidth = fullWidgetWidth - (numInRow - 1) * cfg.splitterWidth
    local totalRatio = 0
    local hasCustomRatios = false

    for _, w in ipairs(row) do
      if w.widthRatio then
        hasCustomRatios = true
        totalRatio = totalRatio + w.widthRatio
      else
        totalRatio = totalRatio + 1
      end
    end

    local xPos = dockXPos
    for wi, w in ipairs(row) do
      local widgetWidth
      if hasCustomRatios then
        widgetWidth = availableWidth * ((w.widthRatio or 1) / totalRatio)
      else
        widgetWidth = availableWidth / numInRow
      end

      -- Show vertical indicator for side-by-side
      if (dropType == "left" or dropType == "right" or dropType == "between") and ri == rowIndex then
        if dropType == "left" and wi == 1 then
          mdw.verticalDropIndicator:move(xPos - cfg.dropIndicatorHeight / 2, yPos)
          mdw.verticalDropIndicator:resize(cfg.dropIndicatorHeight, rowHeight)
          mdw.verticalDropIndicator:raise()
          mdw.verticalDropIndicator:show()
        elseif dropType == "right" and wi == positionInRow then
          mdw.verticalDropIndicator:move(xPos + widgetWidth - cfg.dropIndicatorHeight / 2, yPos)
          mdw.verticalDropIndicator:resize(cfg.dropIndicatorHeight, rowHeight)
          mdw.verticalDropIndicator:raise()
          mdw.verticalDropIndicator:show()
        elseif dropType == "between" and wi == positionInRow then
          mdw.verticalDropIndicator:move(xPos + widgetWidth + cfg.splitterWidth / 2 - cfg.dropIndicatorHeight / 2, yPos)
          mdw.verticalDropIndicator:resize(cfg.dropIndicatorHeight, rowHeight)
          mdw.verticalDropIndicator:raise()
          mdw.verticalDropIndicator:show()
        end
      end

      w.container:move(xPos, yPos)
      w.container:resize(widgetWidth, rowHeight)
      mdw.resizeWidgetContent(w, widgetWidth, rowHeight)
      xPos = xPos + widgetWidth + cfg.splitterWidth
    end

    -- Show horizontal indicator below this row
    if dropType == "below" and ri == rowIndex then
      yPos = yPos + rowHeight
      dockCfg.dropIndicator:move(dockXPos, yPos - cfg.dropIndicatorHeight / 2)
      dockCfg.dropIndicator:resize(fullWidgetWidth, cfg.dropIndicatorHeight)
      dockCfg.dropIndicator:raise()
      dockCfg.dropIndicator:show()
    else
      yPos = yPos + rowHeight
    end
  end

  -- Empty dock indicator
  if dropType == "above" and #rows == 0 then
    dockCfg.dropIndicator:move(dockXPos, cfg.headerHeight + cfg.widgetMargin)
    dockCfg.dropIndicator:resize(fullWidgetWidth, cfg.dropIndicatorHeight)
    dockCfg.dropIndicator:raise()
    dockCfg.dropIndicator:show()
  end

  -- Store drop position for endDrag
  mdw.drag.insertSide = side
  mdw.drag.dropType = dropType
  mdw.drag.rowIndex = rowIndex
  mdw.drag.positionInRow = positionInRow
  mdw.drag.targetWidget = targetWidget

  if mdw.drag.widget then
    mdw.drag.widget.container:raise()
  end
end

--- Update dock highlight during drag.
-- @param side string|nil "left", "right", or nil to clear
function mdw.updateDockHighlight(side)
  -- Use separate overlay elements instead of changing dock stylesheet
  -- This avoids rendering artifacts that occur when dock style changes
  if not mdw.leftDockHighlight or not mdw.rightDockHighlight then return end

  if side == "left" then
    mdw.leftDockHighlight:show()
    mdw.leftDockHighlight:raise()
    mdw.rightDockHighlight:hide()
  elseif side == "right" then
    mdw.rightDockHighlight:show()
    mdw.rightDockHighlight:raise()
    mdw.leftDockHighlight:hide()
  else
    mdw.leftDockHighlight:hide()
    mdw.rightDockHighlight:hide()
  end
end

--- Hide drop indicators.
function mdw.hideDropIndicator()
  mdw.leftDropIndicator:hide()
  mdw.rightDropIndicator:hide()
  mdw.verticalDropIndicator:hide()
end

--- Hide all drop indicators and restore widget positions.
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

--- Dock a widget with specific position information.
-- Why: Handles the complex logic of inserting a widget into the dock
-- at the correct row and position, shifting other widgets as needed.
-- @param widget table The widget to dock
-- @param side string "left" or "right"
-- @param dropType string "above", "below", "left", "right", or "between"
-- @param rowIndex number Visual row index (1-based)
-- @param positionInRow number Position within row
-- @param targetWidget table|nil Reference widget for side-by-side insertion
function mdw.dockWidgetWithPosition(widget, side, dropType, rowIndex, positionInRow, targetWidget)
  local cfg = mdw.config
  local dockCfg = mdw.getDockConfig(side)

  mdw.debugEcho(string.format("DOCK: widget=%s, side=%s, dropType=%s, rowIndex=%s",
    widget.name, side, dropType, tostring(rowIndex)))

  -- Don't dock if sidebar is hidden
  if not mdw.visibility[dockCfg.visibilityKey] then
    widget.docked = nil
    mdw.showResizeHandles(widget)
    return
  end

  widget.docked = side
  widget.widthRatio = nil

  local docked = mdw.getDockedWidgets(side, widget)
  local rows = mdw.groupWidgetsByRow(docked)

  if dropType == "left" or dropType == "right" or dropType == "between" then
    -- Side-by-side insertion
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
        for _, w in ipairs(docked) do
          if w.row == widget.row and (w.rowPosition or 0) >= widget.rowPosition then
            w.rowPosition = (w.rowPosition or 0) + 1
          end
        end
      elseif dropType == "between" then
        widget.rowPosition = (targetWidget.rowPosition or 0) + 1
        for _, w in ipairs(docked) do
          if w.row == widget.row and (w.rowPosition or 0) >= widget.rowPosition then
            w.rowPosition = (w.rowPosition or 0) + 1
          end
        end
      else -- right
        widget.rowPosition = (targetWidget.rowPosition or 0) + 1
        for _, w in ipairs(docked) do
          if w.row == widget.row and (w.rowPosition or 0) >= widget.rowPosition then
            w.rowPosition = (w.rowPosition or 0) + 1
          end
        end
      end
    else
      widget.row = rowIndex - 1
      widget.rowPosition = positionInRow
    end
  else
    -- Vertical insertion (above or below)
    local targetVisualRow = rows[rowIndex]
    local actualRowNum = 0
    if targetVisualRow and #targetVisualRow > 0 then
      actualRowNum = targetVisualRow[1].row or 0
    end

    local newRow
    if dropType == "above" then
      newRow = actualRowNum
      for _, w in ipairs(docked) do
        if (w.row or 0) >= newRow then
          w.row = (w.row or 0) + 1
        end
      end
    else -- below
      newRow = actualRowNum + 1
      for _, w in ipairs(docked) do
        if (w.row or 0) >= newRow then
          w.row = (w.row or 0) + 1
        end
      end
    end
    widget.row = newRow
    widget.rowPosition = 0
  end

  mdw.reorganizeDock(side)
end

--- Dock a widget to a side (adds to end as new row).
-- @param widget table The widget to dock
-- @param side string "left" or "right"
function mdw.dockWidget(widget, side)
  widget.docked = side

  local docked = mdw.getDockedWidgets(side, widget)
  local maxRow = -1
  for _, w in ipairs(docked) do
    maxRow = math.max(maxRow, w.row or 0)
  end
  widget.row = maxRow + 1
  widget.rowPosition = 0

  mdw.hideResizeHandles(widget)
  mdw.reorganizeDock(side)
end

--- Reorganize all widgets in a dock.
-- Why: Called after any change to dock contents to ensure proper
-- positioning and sizing of all widgets.
-- @param side string "left" or "right"
function mdw.reorganizeDock(side)
  local cfg = mdw.config
  local dockCfg = mdw.getDockConfig(side)
  local docked = mdw.getDockedWidgets(side, nil)

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

  local yPos = cfg.headerHeight + cfg.widgetMargin
  local dockIndex = 1

  -- Track widget positions for splitter placement
  local widgetPositions = {}

  for _, row in ipairs(rows) do
    local maxRowHeight = 0
    for _, w in ipairs(row) do
      maxRowHeight = math.max(maxRowHeight, w.container:get_height())
    end

    local numInRow = #row
    local availableWidth = fullWidgetWidth - (numInRow - 1) * cfg.splitterWidth

    local hasCustomRatios = false
    local totalRatio = 0
    for _, w in ipairs(row) do
      if w.widthRatio then
        hasCustomRatios = true
        totalRatio = totalRatio + w.widthRatio
      else
        totalRatio = totalRatio + 1
      end
    end

    local xPos = dockXPos
    for _, w in ipairs(row) do
      local widgetWidth
      if hasCustomRatios then
        widgetWidth = availableWidth * ((w.widthRatio or 1) / totalRatio)
      else
        widgetWidth = availableWidth / numInRow
      end

      local widgetHeight = w.container:get_height()
      w.container:move(xPos, yPos)
      if numInRow > 1 then
        w.container:resize(widgetWidth, nil)
      else
        w.widthRatio = nil
        w.container:resize(widgetWidth, widgetHeight)
      end
      w.dockIndex = dockIndex

      -- Store calculated position for splitter placement
      widgetPositions[w] = {x = xPos, y = yPos, w = widgetWidth, h = widgetHeight}

      -- Pass explicit dimensions to avoid Geyser timing issues
      mdw.resizeWidgetContent(w, widgetWidth, widgetHeight)
      dockIndex = dockIndex + 1
      xPos = xPos + widgetWidth + cfg.splitterWidth
    end

    yPos = yPos + maxRowHeight
  end

  -- Pass calculated positions to avoid Geyser timing issues
  mdw.updateDockSplitters(side, docked, dockXPos, fullWidgetWidth, widgetPositions)

  -- Raise all widgets above dock background and highlight overlays
  for _, w in ipairs(docked) do
    mdw.raiseWidget(w)
  end
end

---------------------------------------------------------------------------
-- DOCK SPLITTER MANAGEMENT
-- Creates and manages splitters between docked widgets.
---------------------------------------------------------------------------

--- Delete a Geyser label safely by name.
-- @param name string The label name to delete
local function deleteLabelByName(name)
  if Geyser.Label.all and Geyser.Label.all[name] then
    pcall(function()
      Geyser.Label.all[name]:hide()
    end)
    pcall(deleteLabel, name)
  end
end

--- Delete all vertical widget splitters from both docks.
-- Used during drag preview to ensure no orphaned splitters are visible.
-- Note: Horizontal splitters no longer exist - each widget has its own bottomResizeHandle.
function mdw.deleteAllWidgetSplitters()
  for _, side in ipairs({"left", "right"}) do
    -- Delete tracked vertical splitters
    for _, splitter in ipairs(mdw.verticalWidgetSplitters[side]) do
      if splitter and splitter.name then
        deleteLabelByName(splitter.name)
      end
    end
    mdw.verticalWidgetSplitters[side] = {}

    -- Delete any orphans by name pattern
    for i = 1, 20 do
      deleteLabelByName("MDW_VertWidgetSplitter_" .. side .. "_" .. i)
      -- Also clean up old horizontal splitters that might exist from previous versions
      deleteLabelByName("MDW_WidgetSplitter_" .. side .. "_" .. i)
    end

    -- Clear the old horizontal splitter array (no longer used)
    mdw.widgetSplitters[side] = {}
  end
end

--- Update splitters for a dock.
-- This function now only creates VERTICAL splitters for side-by-side widgets.
-- Horizontal (vertical resize) splitters are no longer needed because each widget
-- has its own bottomResizeHandle element that handles vertical resizing.
-- @param side string "left" or "right"
-- @param docked table Array of docked widgets
-- @param dockXPos number X position of dock content area
-- @param fullWidgetWidth number Full width available for widgets
-- @param widgetPositions table Optional pre-calculated widget positions {widget = {x, y, w, h}}
function mdw.updateDockSplitters(side, docked, dockXPos, fullWidgetWidth, widgetPositions)
  local cfg = mdw.config

  -- DESTROY all existing vertical splitters for this side
  for _, splitter in ipairs(mdw.verticalWidgetSplitters[side]) do
    if splitter and splitter.name then
      deleteLabelByName(splitter.name)
    end
  end
  mdw.verticalWidgetSplitters[side] = {}

  -- Delete any orphan vertical splitters by name pattern
  for i = 1, 20 do
    deleteLabelByName("MDW_VertWidgetSplitter_" .. side .. "_" .. i)
  end

  -- Also clean up any old horizontal splitters that might exist from before
  -- (these are no longer created, but may exist from previous versions)
  for i = 1, 20 do
    deleteLabelByName("MDW_WidgetSplitter_" .. side .. "_" .. i)
  end
  mdw.widgetSplitters[side] = {}

  local rows = mdw.groupWidgetsByRow(docked)
  local vertSplitterIndex = 0

  -- Calculate positions the same way reorganizeDock does
  local yPos = cfg.headerHeight + cfg.widgetMargin

  for ri, row in ipairs(rows) do
    local numInRow = #row
    local availableWidth = fullWidgetWidth - (numInRow - 1) * cfg.splitterWidth

    -- Calculate max row height
    local maxRowHeight = 0
    for _, w in ipairs(row) do
      local wh = (widgetPositions and widgetPositions[w] and widgetPositions[w].h)
                 or w.container:get_height()
      maxRowHeight = math.max(maxRowHeight, wh)
    end

    local hasCustomRatios = false
    local totalRatio = 0
    for _, w in ipairs(row) do
      if w.widthRatio then
        hasCustomRatios = true
        totalRatio = totalRatio + w.widthRatio
      else
        totalRatio = totalRatio + 1
      end
    end

    local xPos = dockXPos
    for wi, w in ipairs(row) do
      local widgetWidth
      if hasCustomRatios then
        widgetWidth = availableWidth * ((w.widthRatio or 1) / totalRatio)
      else
        widgetWidth = availableWidth / numInRow
      end

      -- Create vertical splitter between side-by-side widgets
      if wi < numInRow then
        vertSplitterIndex = vertSplitterIndex + 1
        local vertSplitterName = "MDW_VertWidgetSplitter_" .. side .. "_" .. vertSplitterIndex

        local vSplitterX = xPos + widgetWidth
        local vSplitterY = yPos

        local vertSplitter = Geyser.Label:new({
          name = vertSplitterName,
          x = vSplitterX,
          y = vSplitterY,
          width = cfg.splitterWidth,
          height = maxRowHeight,
        })
        vertSplitter:setStyleSheet(mdw.styles.splitter)
        vertSplitter:setCursor(mudlet.cursor.ResizeHorizontal)
        vertSplitter:raise()
        vertSplitter.leftWidget = w
        vertSplitter.rightWidget = row[wi + 1]
        vertSplitter.side = side
        vertSplitter.rowIndex = ri
        mdw.verticalWidgetSplitters[side][vertSplitterIndex] = vertSplitter
        mdw.setupVerticalWidgetSplitter(vertSplitter, w, row[wi + 1], side)
      end

      xPos = xPos + widgetWidth + cfg.splitterWidth
    end

    yPos = yPos + maxRowHeight
  end
end

---------------------------------------------------------------------------
-- WIDGET RESIZE HANDLING
-- Handles resizing of docked and floating widgets.
---------------------------------------------------------------------------

--- Set up drag handling for a vertical widget splitter (horizontal resize).
-- @param splitter Geyser.Label The splitter element
-- @param leftWidget table Widget on the left
-- @param rightWidget table Widget on the right
-- @param side string "left" or "right"
function mdw.setupVerticalWidgetSplitter(splitter, leftWidget, rightWidget, side)
  setLabelClickCallback(splitter.name, function(event)
    mdw.verticalWidgetSplitterDrag.active = true
    mdw.verticalWidgetSplitterDrag.splitter = splitter
    mdw.verticalWidgetSplitterDrag.leftWidget = leftWidget
    mdw.verticalWidgetSplitterDrag.rightWidget = rightWidget
    mdw.verticalWidgetSplitterDrag.side = side
    mdw.verticalWidgetSplitterDrag.offsetX = event.globalX - splitter:get_x()
    mdw.verticalWidgetSplitterDrag.leftStartWidth = leftWidget.container:get_width()
    mdw.verticalWidgetSplitterDrag.rightStartWidth = rightWidget.container:get_width()
    mdw.verticalWidgetSplitterDrag.startMouseX = event.globalX
  end)

  setLabelMoveCallback(splitter.name, function(event)
    if mdw.verticalWidgetSplitterDrag.active and
       mdw.verticalWidgetSplitterDrag.leftWidget == leftWidget and
       mdw.verticalWidgetSplitterDrag.rightWidget == rightWidget then
      mdw.resizeWidgetsHorizontally(event.globalX)
    end
  end)

  setLabelReleaseCallback(splitter.name, function()
    if mdw.verticalWidgetSplitterDrag.active and
       mdw.verticalWidgetSplitterDrag.leftWidget == leftWidget and
       mdw.verticalWidgetSplitterDrag.rightWidget == rightWidget then
      mdw.verticalWidgetSplitterDrag.active = false
      mdw.verticalWidgetSplitterDrag.splitter = nil
      mdw.verticalWidgetSplitterDrag.leftWidget = nil
      mdw.verticalWidgetSplitterDrag.rightWidget = nil
      mdw.verticalWidgetSplitterDrag.side = nil
    end
  end)
end

--- Resize a widget vertically with snap to adjacent widgets.
-- @param widget table The widget to resize
-- @param side string "left" or "right"
-- @param targetBottomY number Target Y position for widget bottom
function mdw.resizeWidgetWithSnap(widget, side, targetBottomY)
  local cfg = mdw.config
  local widgetTop = widget.container:get_y()
  local newHeight = targetBottomY - widgetTop

  newHeight = math.max(cfg.minWidgetHeight, newHeight)

  local _, winH = getMainWindowSize()
  local maxHeight = winH - widgetTop - cfg.sideBySideOffset
  newHeight = math.min(newHeight, maxHeight)

  -- Check for snap to other widgets in same row
  local docked = mdw.getDockedWidgets(side, nil)
  local rows = mdw.groupWidgetsByRow(docked)

  local widgetRowIndex = nil
  for rowIdx, row in ipairs(rows) do
    for _, w in ipairs(row) do
      if w == widget then
        widgetRowIndex = rowIdx
        for _, w2 in ipairs(row) do
          if w2 ~= widget then
            local otherHeight = w2.container:get_height()
            if math.abs(newHeight - otherHeight) < cfg.snapThreshold then
              newHeight = otherHeight
              break
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

  -- Move subsequent rows
  if widgetRowIndex then
    local currentRowMaxHeight = newHeight
    for _, w in ipairs(rows[widgetRowIndex]) do
      if w ~= widget then
        currentRowMaxHeight = math.max(currentRowMaxHeight, w.container:get_height())
      end
    end

    local nextRowY = widgetTop + currentRowMaxHeight

    for rowIdx = widgetRowIndex + 1, #rows do
      local row = rows[rowIdx]
      local rowMaxHeight = 0
      for _, w in ipairs(row) do
        rowMaxHeight = math.max(rowMaxHeight, w.container:get_height())
      end

      for _, w in ipairs(row) do
        w.container:move(nil, nextRowY)
        mdw.resizeWidgetContent(w, w.container:get_width(), w.container:get_height())
      end

      nextRowY = nextRowY + rowMaxHeight
    end
  end
end

--- Resize two side-by-side widgets horizontally.
-- @param mouseX number Current mouse X position
function mdw.resizeWidgetsHorizontally(mouseX)
  local drag = mdw.verticalWidgetSplitterDrag
  if not drag.active then return end

  local cfg = mdw.config
  local leftWidget = drag.leftWidget
  local rightWidget = drag.rightWidget
  local splitter = drag.splitter
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

  leftWidget.container:resize(newLeftWidth, nil)
  rightWidget.container:resize(newRightWidth, nil)

  -- Update ratios for all widgets in row
  local docked = mdw.getDockedWidgets(side, nil)
  local rowWidgets = {}
  local rowTotalWidth = 0
  for _, w in ipairs(docked) do
    if w.row == leftWidget.row then
      rowWidgets[#rowWidgets + 1] = w
      rowTotalWidth = rowTotalWidth + w.container:get_width()
    end
  end
  for _, w in ipairs(rowWidgets) do
    w.widthRatio = w.container:get_width() / rowTotalWidth
  end

  local newRightX = leftWidget.container:get_x() + newLeftWidth + cfg.splitterWidth
  rightWidget.container:move(newRightX, nil)
  splitter:move(leftWidget.container:get_x() + newLeftWidth, nil)

  -- Update widget content (including bottom resize handles)
  mdw.resizeWidgetContent(leftWidget, newLeftWidth, leftWidget.container:get_height())
  mdw.resizeWidgetContent(rightWidget, newRightWidth, rightWidget.container:get_height())
end

---------------------------------------------------------------------------
-- FLOATING WIDGET RESIZE
-- Handles resize borders for floating (undocked) widgets.
---------------------------------------------------------------------------

--- Set up resize borders for a floating widget.
-- @param widget table The widget to set up resize for
function mdw.setupResizeBorders(widget)
  mdw.setupResizeBorder(widget, widget.resizeLeft, "left")
  mdw.setupResizeBorder(widget, widget.resizeRight, "right")
  mdw.setupResizeBorder(widget, widget.resizeBottom, "bottom")
  mdw.setupResizeBorder(widget, widget.resizeTop, "top")
end

--- Set up a single resize border.
-- @param widget table The widget
-- @param border Geyser.Label The border element
-- @param edge string "left", "right", "top", or "bottom"
function mdw.setupResizeBorder(widget, border, edge)
  local cfg = mdw.config
  local borderName = border.name

  setLabelClickCallback(borderName, function(event)
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
      end

      mdw.updateResizeBorders(widget)
    end
  end)

  setLabelReleaseCallback(borderName, function()
    if mdw.resizeDrag.active and mdw.resizeDrag.widget == widget and mdw.resizeDrag.edge == edge then
      mdw.resizeDrag.active = false
      mdw.resizeDrag.widget = nil
      mdw.resizeDrag.edge = nil
    end
  end)
end

--- Update resize border positions after widget move/resize.
-- @param widget table The widget
function mdw.updateResizeBorders(widget)
  local cfg = mdw.config
  local x = widget.container:get_x()
  local y = widget.container:get_y()
  local w = widget.container:get_width()
  local h = widget.container:get_height()
  local bw = cfg.resizeBorderWidth

  widget.resizeLeft:move(x - bw, y - bw)
  widget.resizeLeft:resize(bw, h + bw * 2)

  widget.resizeRight:move(x + w, y - bw)
  widget.resizeRight:resize(bw, h + bw * 2)

  widget.resizeBottom:move(x - bw, y + h)
  widget.resizeBottom:resize(w + bw * 2, bw)

  widget.resizeTop:move(x - bw, y - bw)
  widget.resizeTop:resize(w + bw * 2, bw)
end

--- Show resize handles for a floating widget.
-- @param widget table The widget
function mdw.showResizeHandles(widget)
  widget.resizeLeft:show()
  widget.resizeLeft:raise()
  widget.resizeRight:show()
  widget.resizeRight:raise()
  widget.resizeBottom:show()
  widget.resizeBottom:raise()
  widget.resizeTop:show()
  widget.resizeTop:raise()
  mdw.updateResizeBorders(widget)

  -- Hide docked resize handle when floating (use the border resize handles instead)
  if widget.bottomResizeHandle then
    widget.bottomResizeHandle:hide()
  end
end

--- Hide resize handles (for docked widgets).
-- @param widget table The widget
function mdw.hideResizeHandles(widget)
  widget.resizeLeft:hide()
  widget.resizeRight:hide()
  widget.resizeBottom:hide()
  widget.resizeTop:hide()

  -- Show docked resize handle when docked
  if widget.bottomResizeHandle and widget.docked then
    widget.bottomResizeHandle:show()
    widget.bottomResizeHandle:raise()
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
    x = 0, y = 0,
    width = cfg.headerButtonWidth,
    height = cfg.headerHeight - cfg.splitterWidth,
  }, mdw.headerPane))
  mdw.layoutButton:setStyleSheet(mdw.styles.headerButton)
  mdw.layoutButton:decho("<" .. cfg.headerTextColor .. ">Layout")
  mdw.layoutButton:setCursor(mudlet.cursor.PointingHand)
  setLabelClickCallback("MDW_LayoutButton", function()
    mdw.toggleLayoutMenu()
  end)

  -- Widgets menu button
  mdw.widgetsButton = mdw.trackElement(Geyser.Label:new({
    name = "MDW_WidgetsButton",
    x = cfg.headerButtonWidth, y = 0,
    width = cfg.headerButtonWidth,
    height = cfg.headerHeight - cfg.splitterWidth,
  }, mdw.headerPane))
  mdw.widgetsButton:setStyleSheet(mdw.styles.headerButton)
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
  local menuY = cfg.headerHeight - cfg.menuOverlap  -- Overlap top border with header button's bottom border
  local items = {
    {name = "leftSidebar", label = "Left Sidebar", visible = mdw.visibility.leftSidebar},
    {name = "rightSidebar", label = "Right Sidebar", visible = mdw.visibility.rightSidebar},
    {name = "promptBar", label = "Prompt Bar", visible = mdw.visibility.promptBar},
  }
  local menuHeight = #items * cfg.menuItemHeight + cfg.menuPadding * 2

  mdw.layoutMenuBg = mdw.trackElement(Geyser.Label:new({
    name = "MDW_LayoutMenuBg",
    x = menuX, y = menuY,
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
      x = menuX, y = yPos,
      width = menuWidth,
      height = cfg.menuItemHeight,
    }))
    menuItem:setStyleSheet(mdw.styles.menuItem)
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

    mdw.layoutMenuItems[item.name] = {label = menuItem, text = item.label}
    mdw.layoutMenuLabels[#mdw.layoutMenuLabels + 1] = menuItem
  end
end

--- Get sorted list of widget names.
-- @return table Array of widget names sorted alphabetically
local function getWidgetNames()
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
  local menuX = cfg.menuPaddingLeft + cfg.headerButtonWidth  -- After Layout button
  local menuY = cfg.headerHeight - cfg.menuOverlap  -- Overlap top border with header button's bottom border
  local items = getWidgetNames()
  local menuHeight = math.max(#items, 1) * cfg.menuItemHeight + cfg.menuPadding * 2

  mdw.widgetsMenuBg = mdw.trackElement(Geyser.Label:new({
    name = "MDW_WidgetsMenuBg",
    x = menuX, y = menuY,
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
-- @param widgetName string The widget name
-- @param index number|nil The position index (auto-calculated if nil)
function mdw.addWidgetMenuItem(widgetName, index)
  local cfg = mdw.config
  local menuWidth = cfg.menuWidth
  local menuX = cfg.menuPaddingLeft + cfg.headerButtonWidth
  local menuY = cfg.headerHeight - cfg.menuOverlap

  -- Calculate position
  local i = index or (#mdw.widgetsMenuLabels + 1)
  local yPos = menuY + cfg.menuPadding + (i - 1) * cfg.menuItemHeight

  local menuItem = mdw.trackElement(Geyser.Label:new({
    name = "MDW_WidgetsMenu_" .. widgetName,
    x = menuX, y = yPos,
    width = menuWidth,
    height = cfg.menuItemHeight,
  }))
  menuItem:setStyleSheet(mdw.styles.menuItem)

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

  mdw.widgetsMenuItems[widgetName] = {label = menuItem, text = widgetName}
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
  local menuX = cfg.menuPaddingLeft + cfg.headerButtonWidth
  local menuY = cfg.headerHeight - cfg.menuOverlap
  local items = getWidgetNames()
  local menuHeight = math.max(#items, 1) * cfg.menuItemHeight + cfg.menuPadding * 2

  mdw.widgetsMenuBg = mdw.trackElement(Geyser.Label:new({
    name = "MDW_WidgetsMenuBg",
    x = menuX, y = menuY,
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
-- @param menuItem Geyser.Label The menu item
-- @param text string The label text
-- @param checked boolean Whether the item is checked
-- @param highlighted boolean|nil Whether the item is highlighted (hovered)
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
-- @param menuBg Geyser.Label The menu background label
-- @param menuLabels table Array of menu item labels
-- @param button Geyser.Label The header button that opens this menu
local function showMenu(menuBg, menuLabels, button)
  mdw.createMenuOverlay()
  button:setStyleSheet(mdw.styles.headerButtonActive)
  menuBg:show()
  menuBg:raise()
  for _, label in ipairs(menuLabels) do
    label:show()
    label:raise()
  end
end

--- Hide a dropdown menu.
-- Why: Consolidates the repetitive pattern of hiding background, items,
-- and restoring button styling.
-- @param menuBg Geyser.Label The menu background label
-- @param menuLabels table Array of menu item labels
-- @param button Geyser.Label The header button that opens this menu
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

--- Create menu overlay on demand.
function mdw.createMenuOverlay()
  if mdw.menuOverlay then return end

  mdw.menuOverlay = Geyser.Label:new({
    name = "MDW_MenuOverlay",
    x = 0, y = mdw.config.headerHeight,
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

--- Destroy menu overlay.
function mdw.destroyMenuOverlay()
  if mdw.menuOverlay then
    mdw.menuOverlay:hide()
    mdw.menuOverlay = nil
    deleteLabel("MDW_MenuOverlay")
  end
end

--- Show layout menu.
function mdw.showLayoutMenu()
  showMenu(mdw.layoutMenuBg, mdw.layoutMenuLabels, mdw.layoutButton)
  mdw.menus.layoutOpen = true
end

--- Hide layout menu.
function mdw.hideLayoutMenu()
  hideMenu(mdw.layoutMenuBg, mdw.layoutMenuLabels, mdw.layoutButton)
  mdw.menus.layoutOpen = false
  if not mdw.menus.widgetsOpen then
    mdw.destroyMenuOverlay()
  end
end

--- Show widgets menu.
function mdw.showWidgetsMenu()
  showMenu(mdw.widgetsMenuBg, mdw.widgetsMenuLabels, mdw.widgetsButton)
  mdw.menus.widgetsOpen = true
end

--- Hide widgets menu.
function mdw.hideWidgetsMenu()
  hideMenu(mdw.widgetsMenuBg, mdw.widgetsMenuLabels, mdw.widgetsButton)
  mdw.menus.widgetsOpen = false
  if not mdw.menus.layoutOpen then
    mdw.destroyMenuOverlay()
  end
end

--- Toggle layout menu.
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

--- Toggle widgets menu.
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

--- Close all menus.
function mdw.closeAllMenus()
  if mdw.layoutMenuLabels and mdw.menus.layoutOpen then
    mdw.hideLayoutMenu()
  end
  if mdw.widgetsMenuLabels and mdw.menus.widgetsOpen then
    mdw.hideWidgetsMenu()
  end
  mdw.destroyMenuOverlay()
end

---------------------------------------------------------------------------
-- SIDEBAR VISIBILITY TOGGLES
---------------------------------------------------------------------------

--- Toggle a layout item visibility.
-- @param itemName string "leftSidebar", "rightSidebar", or "promptBar"
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
-- @param side string "left" or "right"
local function toggleSidebar(side)
  local dockCfg = mdw.getDockConfig(side)
  local isVisible = mdw.visibility[dockCfg.visibilityKey]

  if isVisible then
    dockCfg.setBorder(dockCfg.width)
    dockCfg.dock:show()
    dockCfg.splitter:show()

    for _, w in pairs(mdw.widgets) do
      if w.originalDock == side then
        w.docked = side
        w.originalDock = nil
        if w.visible ~= false then
          w.container:show()
        end
        mdw.hideResizeHandles(w)
      end
    end
    mdw.reorganizeDock(side)
  else
    dockCfg.setBorder(0)
    dockCfg.dock:hide()
    dockCfg.splitter:hide()

    -- Hide vertical splitters (for side-by-side widgets)
    for _, splitter in ipairs(dockCfg.verticalSplitters) do
      splitter:hide()
    end

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
end

--- Toggle left sidebar visibility.
function mdw.toggleLeftSidebar()
  toggleSidebar("left")
end

--- Toggle right sidebar visibility.
function mdw.toggleRightSidebar()
  toggleSidebar("right")
end

--- Toggle prompt bar visibility.
function mdw.togglePromptBar()
  local cfg = mdw.config

  if mdw.visibility.promptBar then
    setBorderBottom(cfg.promptBarHeight)
    mdw.promptBar:show()
    mdw.promptSeparator:show()
  else
    setBorderBottom(0)
    mdw.promptBar:hide()
    mdw.promptSeparator:hide()
  end
end

--- Update prompt bar position based on sidebar visibility.
function mdw.updatePromptBar()
  local cfg = mdw.config
  local winW = getMainWindowSize()
  local leftOffset = mdw.visibility.leftSidebar and cfg.leftDockWidth or 0
  local rightOffset = mdw.visibility.rightSidebar and cfg.rightDockWidth or 0
  local promptBarWidth = winW - leftOffset - rightOffset

  mdw.promptBar:move(leftOffset, nil)
  mdw.promptBar:resize(promptBarWidth, nil)
  mdw.promptSeparator:move(leftOffset, nil)
  mdw.promptSeparator:resize(promptBarWidth, nil)
end

---------------------------------------------------------------------------
-- WIDGET VISIBILITY
---------------------------------------------------------------------------

--- Check if a widget is currently shown on screen.
-- @param widget table The widget to check
-- @return boolean True if widget is visible
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

--- Toggle a widget's visibility.
-- @param widgetName string Name of the widget to toggle
function mdw.toggleWidget(widgetName)
  local widget = mdw.widgets[widgetName]
  if not widget then return end

  local isCurrentlyShown = mdw.isWidgetShown(widget)

  if isCurrentlyShown then
    widget.container:hide()
    mdw.hideResizeHandles(widget)
    widget.visible = false

    -- Hide vertical splitters associated with this widget
    for _, splitter in ipairs(mdw.verticalWidgetSplitters.left) do
      if splitter.leftWidget == widget or splitter.rightWidget == widget then splitter:hide() end
    end
    for _, splitter in ipairs(mdw.verticalWidgetSplitters.right) do
      if splitter.leftWidget == widget or splitter.rightWidget == widget then splitter:hide() end
    end
  else
    widget.visible = true
    local dockSide = widget.docked or widget.originalDock

    if dockSide then
      local sidebarVisible = (dockSide == "left" and mdw.visibility.leftSidebar) or
                             (dockSide == "right" and mdw.visibility.rightSidebar)
      if sidebarVisible then
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
  end

  local item = mdw.widgetsMenuItems[widgetName]
  if item then
    mdw.updateMenuItemText(item.label, item.text, not isCurrentlyShown)
  end

  if mdw.visibility.leftSidebar then mdw.reorganizeDock("left") end
  if mdw.visibility.rightSidebar then mdw.reorganizeDock("right") end
end

--- Float a widget centered in the main window.
-- @param widget table The widget to float
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
  widget.container:raise()
  mdw.showResizeHandles(widget)
end

--- Update all widgets menu checkboxes.
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
