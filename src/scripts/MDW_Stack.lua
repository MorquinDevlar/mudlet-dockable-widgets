--[[
  MDW_Stack.lua
  Tab groups ("Stacks"): combine several widgets into one dock slot where each
  widget is a tab. A Stack is a duck-typed dock occupant (plain table) the layout
  engine treats like any widget: it has the slot fields (docked/row/...), a
  container, and isStack=true so resizeWidgetContent dispatches to resizeStackContent.

  Member widgets keep their own content/console/update logic untouched. While in a
  stack a member is "headless" (its own title bar hidden) and rendered by the stack:
  only the active member is shown, positioned below the stack's tab bar.

  Dependencies: MDW_Config, MDW_Helpers, MDW_WidgetCore, MDW_TabbedWidget loaded first.
]]

---------------------------------------------------------------------------
-- LOCAL HELPERS
---------------------------------------------------------------------------

local function safeName(s)
  return (tostring(s):gsub("[^%w]", "_"))
end

--- Pixel width of a stack tab button from its label (monospace estimate).
function mdw.stackTabWidth(title)
  local cfg = mdw.config
  local charWidth = math.ceil(cfg.tabFontSize * 0.65)
  return cfg.tabPadding * 2 + #tostring(title) * charWidth + 8
end

---------------------------------------------------------------------------
-- STACK CHROME + LAYOUT
---------------------------------------------------------------------------

--- Lay out the tab buttons (left-packed, content width) and style them by active.
function mdw.refreshStackTabBar(stack)
  local cfg = mdw.config
  local x = 0
  for _, tabObj in ipairs(stack.tabObjects) do
    local w = mdw.stackTabWidth(tabObj.name)
    tabObj.button:move(x, 0)
    tabObj.button:resize(w, cfg.tabBarHeight)
    if tabObj.memberName == stack.activeMember then
      mdw.applyTabActiveStyle(tabObj, "group")
    else
      mdw.applyTabInactiveStyle(tabObj, "group")
    end
    tabObj.button:setCursor(mudlet.cursor.PointingHand)
    x = x + w
  end
end

--- Lay out the stack: tab bar across the top, members filling the rest. Only the
-- active member is shown. Dispatched from resizeWidgetContent (isStack branch).
function mdw.resizeStackContent(stack, targetWidth, targetHeight)
  local cfg = mdw.config
  local cw = targetWidth or stack.container:get_width()
  local ch = targetHeight or stack.container:get_height()
  local resizeHandleHeight = stack.docked and cfg.widgetSplitterHeight or 0

  -- Tab bar (also the drag handle for the empty area beside the tabs)
  stack.tabBar:move(0, 0)
  stack.tabBar:resize(cw, cfg.tabBarHeight)
  mdw.refreshStackTabBar(stack)

  -- Member containers are siblings (top-level), positioned in absolute coords.
  -- reorganizeDock moves the stack container before calling this, so read it now.
  local contentX = stack.container:get_x()
  local contentY = stack.container:get_y() + cfg.tabBarHeight
  local contentW = cw
  local contentH = math.max(0, ch - cfg.tabBarHeight - resizeHandleHeight)

  for _, memberName in ipairs(stack.members) do
    local member = mdw.widgets[memberName]
    if member and member.container then
      member.container:move(contentX, contentY)
      member.container:resize(contentW, contentH)
      -- Only the active member is visible, so only it needs its content laid out;
      -- hidden members are re-laid when selected (selectStackTab -> resize again).
      if memberName == stack.activeMember then
        mdw.resizeWidgetContent(member, contentW, contentH)
        member.container:show()
        if mdw.showWidgetContent then mdw.showWidgetContent(member) end
      else
        member.container:hide()
      end
    end
  end

  if stack.bottomResizeHandle then
    stack.bottomResizeHandle:move(0, ch - cfg.widgetSplitterHeight)
    stack.bottomResizeHandle:resize(cw, cfg.widgetSplitterHeight)
  end
end

--- Re-lay-out a stack (docked -> via reorganizeDock, floating -> direct) and fix z-order.
function mdw.layoutStack(stack)
  if stack.docked then
    mdw.reorganizeDock(stack.docked)
    if mdw.hideResizeHandles then mdw.hideResizeHandles(stack) end
  else
    mdw.resizeStackContent(stack)
    -- A floating group shows the edge/corner resize borders, like a floating widget.
    if mdw.showResizeHandles then mdw.showResizeHandles(stack) end
    if mdw.updateResizeBorders then mdw.updateResizeBorders(stack) end
  end
  mdw.raiseWidgetElements(stack)
end

--- Hide a whole group. Members are top-level siblings (not children of the stack
-- container), so they must be hidden explicitly alongside the stack chrome.
function mdw.hideStack(stack)
  if not stack then return end
  stack.visible = false
  if stack.container then stack.container:hide() end
  for _, m in ipairs(stack.members or {}) do
    local mw = mdw.widgets[m]
    if mw and mw.container then mw.container:hide() end
  end
  if stack.docked then mdw.reorganizeDock(stack.docked) end
  if mdw.updateWidgetsMenuState then mdw.updateWidgetsMenuState() end
end

--- Show a group (optionally selecting a member's tab) and lay it out.
function mdw.showStack(stack, memberName)
  if not stack then return end
  stack.visible = true
  if stack.container then stack.container:show() end
  if memberName and stack.tabsByName[memberName] then
    mdw.selectStackTab(stack, memberName)
  else
    mdw.layoutStack(stack)
  end
  if stack.docked then mdw.reorganizeDock(stack.docked) end
  mdw.raiseWidgetElements(stack)
  if mdw.updateWidgetsMenuState then mdw.updateWidgetsMenuState() end
end

--- Make a member render without its own chrome (the stack provides it).
function mdw.applyHeadless(member)
  member._headless = true
  if member.titleBar then member.titleBar:hide() end
  if member.fillButton then member.fillButton:hide() end
  if member.lockButton then member.lockButton:hide() end
  if member.closeButton then member.closeButton:hide() end
  if member.bottomResizeHandle then member.bottomResizeHandle:hide() end
  -- A floating member would still show its own resize border; the stack owns
  -- sizing now, so hide them.
  if mdw.hideResizeHandles then mdw.hideResizeHandles(member) end
end

--- Restore a member's own chrome after leaving a stack.
function mdw.removeHeadless(member)
  member._headless = nil
  if member.titleBar then member.titleBar:show() end
  if mdw.updateDockButtonVisibility then mdw.updateDockButtonVisibility(member) end
end

---------------------------------------------------------------------------
-- DRAG (the tab bar moves the whole stack; reuses the generic drag system)
---------------------------------------------------------------------------

function mdw.setupStackDrag(stack)
  local barName = "MDW_" .. stack.name .. "_TabBar"
  local stackName = stack.name
  setLabelClickCallback(barName, function(event)
    local s = mdw.widgets[stackName]
    if s then mdw.startDrag(s, event) end
  end)
  setLabelMoveCallback(barName, function(event)
    local s = mdw.widgets[stackName]
    if s and mdw.drag.active and mdw.drag.widget == s then mdw.handleDragMove(s, event) end
  end)
  setLabelReleaseCallback(barName, function(event)
    local s = mdw.widgets[stackName]
    if s and mdw.drag.active and mdw.drag.widget == s then mdw.endDrag(s, event) end
  end)
end

---------------------------------------------------------------------------
-- CONSTRUCTION / MEMBERSHIP
---------------------------------------------------------------------------

--- Create a new (empty) stack occupant.
-- @param name string unique stack name
-- @param opts table { dock="left"|"right", row, members={names}, activeMember, x, y }
function mdw.createStack(name, opts)
  opts = opts or {}
  local cfg = mdw.config
  if mdw.widgets[name] then
    mdw.echo("Stack/widget name already in use: " .. tostring(name))
    return mdw.widgets[name]
  end

  local stack = {
    name = name,
    isStack = true,
    members = {},
    tabObjects = {},
    tabsByName = {},
    activeMember = nil,
    -- slot fields the layout engine reads
    docked = nil, row = nil, rowPosition = 0, subRow = 0,
    widthRatio = nil, fill = false, widthLocked = false, lockedWidth = nil,
    visible = true, fontAdjust = 0,
  }

  local totalMargin = cfg.widgetMargin * 2
  local w = cfg.leftDockWidth - totalMargin - cfg.dockSplitterWidth
  local h = cfg.widgetHeight

  stack.container = mdw.trackElement(Geyser.Container:new({
    name = "MDW_" .. name,
    x = opts.x or cfg.floatingStartX,
    y = opts.y or cfg.floatingStartY,
    width = w, height = h,
  }))

  -- Tab bar (top; no title bar). Doubles as the drag handle.
  stack.tabBar = mdw.trackElement(Geyser.Label:new({
    name = "MDW_" .. name .. "_TabBar",
    x = 0, y = 0, width = w, height = cfg.tabBarHeight,
  }, stack.container))
  stack.tabBar:setStyleSheet(mdw.styles.tabBar)
  stack.tabBar:setCursor(mudlet.cursor.OpenHand)
  -- The tab bar is the drag handle; alias it as titleBar so the generic drag
  -- code (which sets the title-bar cursor) works on a stack unchanged.
  stack.titleBar = stack.tabBar

  -- Bottom resize handle (named so setupDockedResizeHandle wires it up unchanged)
  stack.bottomResizeHandle = mdw.trackElement(Geyser.Label:new({
    name = "MDW_" .. name .. "_BottomResize",
    x = 0, y = h - cfg.widgetSplitterHeight, width = w, height = cfg.widgetSplitterHeight,
  }, stack.container))
  stack.bottomResizeHandle:setStyleSheet(string.format([[
    QLabel { background-color: %s; }
    QLabel:hover { background-color: %s; }
  ]], cfg.resizeBorderColor, cfg.splitterHoverColor))
  stack.bottomResizeHandle:setCursor(mudlet.cursor.ResizeVertical)
  stack.bottomResizeHandle:hide()

  mdw.widgets[name] = stack
  -- The tab bar is NOT a whole-group drag handle: only the tabs are draggable.
  mdw.setupDockedResizeHandle(stack)
  -- Floating groups get the same edge/corner resize borders that widgets have.
  if mdw.createResizeBorders then mdw.createResizeBorders(stack) end

  if opts.dock then
    mdw.dockWidgetClass(stack, opts.dock, opts.row)
  end

  if opts.members then
    for _, m in ipairs(opts.members) do mdw.addToStack(name, m) end
  end
  if opts.activeMember then mdw.selectStackTab(stack, opts.activeMember) end

  if mdw.rebuildWidgetsMenu then mdw.rebuildWidgetsMenu() end
  return stack
end

--- Add an existing widget to a stack as a tab.
function mdw.addToStack(stackName, memberName, index)
  local stack = mdw.widgets[stackName]
  local member = mdw.widgets[memberName]
  if not stack or not stack.isStack then return end
  if not member then return end
  if member.isStack then return end      -- no nesting (Phase 1)
  if member.stackId then return end      -- already grouped

  -- Remember the standalone slot for a clean ungroup (unless restore already
  -- set it from the saved layout).
  if not member._preStackSlot then
    member._preStackSlot = {
      docked = member.docked, row = member.row, rowPosition = member.rowPosition,
      subRow = member.subRow, widthRatio = member.widthRatio, fill = member.fill,
      widthLocked = member.widthLocked, lockedWidth = member.lockedWidth,
    }
  end
  member.stackId = stackName

  index = index or (#stack.members + 1)
  table.insert(stack.members, index, memberName)

  local btnName = "MDW_" .. stackName .. "_Tab_" .. safeName(memberName)
  -- Clear any stale button of the same name (e.g. a torn-out tab dropped back in)
  mdw.deleteElementByName(btnName)
  local btn = mdw.trackElement(Geyser.Label:new({
    name = btnName,
    x = 0, y = 0, width = 60, height = mdw.config.tabBarHeight,
  }, stack.container))
  btn:setCursor(mudlet.cursor.PointingHand)
  local tabObj = { memberName = memberName, name = member.title or memberName, button = btn }
  table.insert(stack.tabObjects, index, tabObj)
  stack.tabsByName[memberName] = tabObj

  mdw.setupStackTabDrag(stack, tabObj)

  mdw.applyHeadless(member)
  if not stack.activeMember then stack.activeMember = memberName end

  mdw.layoutStack(stack)
  mdw.saveLayout()
  if mdw.rebuildWidgetsMenu then mdw.rebuildWidgetsMenu() end
end

--- Remove a member from a stack, restoring it as a standalone widget.
function mdw.removeFromStack(stackName, memberName)
  local stack = mdw.widgets[stackName]
  if not stack or not stack.isStack then
    mdw.echo("removeFromStack: no stack '" .. tostring(stackName) .. "' (see mdw.Stack.list())")
    return
  end
  if not stack.tabsByName[memberName] then
    mdw.echo("removeFromStack: '" .. tostring(memberName) .. "' is not in '" .. tostring(stackName) .. "'")
    return
  end

  -- Read the saved standalone slot before detachMember clears _preStackSlot.
  local member = mdw.widgets[memberName]
  local saved = member and member._preStackSlot
  mdw.detachMember(stack, memberName)

  if member then
    -- Restore the saved standalone slot, or dock below the stack if unknown.
    if saved and saved.docked then
      member.docked = saved.docked
      member.row = saved.row
      member.rowPosition = saved.rowPosition
      member.subRow = saved.subRow
      member.widthRatio = saved.widthRatio
      member.fill = saved.fill
      member.widthLocked = saved.widthLocked
      member.lockedWidth = saved.lockedWidth
      if mdw.updateDockButtonVisibility then mdw.updateDockButtonVisibility(member) end
    elseif stack.docked then
      mdw.dockWidgetClass(member, stack.docked)
    end
    if member.container then member.container:show() end
  end

  if #stack.members == 0 then
    mdw.destroyStack(stack)
  else
    mdw.layoutStack(stack)
  end
  if member and member.docked then mdw.reorganizeDock(member.docked) end
  mdw.saveLayout()
  if mdw.rebuildWidgetsMenu then mdw.rebuildWidgetsMenu() end
end

--- Switch the active tab of a stack.
function mdw.selectStackTab(stack, memberName)
  if not stack or not stack.tabsByName[memberName] then return end
  stack.activeMember = memberName
  mdw.layoutStack(stack)
end

--- Destroy an (empty) stack and free its elements (container last, as parent).
function mdw.destroyStack(stack)
  for _, t in ipairs(stack.tabObjects or {}) do mdw.deleteElement(t.button) end
  for _, f in ipairs({
    "resizeLeft", "resizeRight", "resizeTop", "resizeBottom",
    "resizeTopLeft", "resizeTopRight", "resizeBottomLeft", "resizeBottomRight",
  }) do
    mdw.deleteElement(stack[f])
  end
  mdw.deleteElement(stack.tabBar)
  mdw.deleteElement(stack.bottomResizeHandle)
  mdw.deleteElement(stack.container)

  local side = stack.docked
  mdw.widgets[stack.name] = nil
  if side then mdw.reorganizeDock(side) end
end

--- Rebuild stacks from the saved layout, after all member widgets exist.
-- Stacks are not created by user widget functions, so their pendingLayouts
-- records survive (no widget consumed them). Members were early-returned by
-- applyPendingLayout (hidden, _pendingStackId set); here we create each stack
-- and absorb its members, then dock any orphaned member standalone.
function mdw.rebuildStacksFromLayout()
  if not mdw.pendingLayouts then return end
  mdw._restoringLayout = true

  for name, saved in pairs(mdw.pendingLayouts) do
    if saved.isStack and not mdw.widgets[name] then
      local stack = mdw.createStack(name, { dock = saved.dock, row = saved.row })
      if stack then
        stack.rowPosition = saved.rowPosition or 0
        stack.subRow = saved.subRow or 0
        stack.widthRatio = saved.widthRatio
        stack.fill = saved.fill or false
        stack.widthLocked = saved.widthLocked or false
        stack.lockedWidth = saved.lockedWidth
        for _, memberName in ipairs(saved.members or {}) do
          local member = mdw.widgets[memberName]
          if member and member._pendingStackId == name then
            member._pendingStackId = nil
            mdw.addToStack(name, memberName)
          end
        end
        if saved.activeMember and stack.tabsByName[saved.activeMember] then
          mdw.selectStackTab(stack, saved.activeMember)
        end
      end
    end
  end

  -- Fallback: any member whose stack record was missing -> restore its slot and
  -- re-wrap it in a fresh single-tab home group (never leave a widget bare).
  for _, widget in pairs(mdw.widgets) do
    if widget._pendingStackId then
      widget._pendingStackId = nil
      local s = widget._preStackSlot
      widget._preStackSlot = nil
      if widget.container then widget.container:show() end
      if s and s.docked then
        widget.docked = s.docked
        widget.row = s.row
        widget.rowPosition = s.rowPosition
        widget.subRow = s.subRow
        widget.widthRatio = s.widthRatio
        widget.fill = s.fill
        widget.widthLocked = s.widthLocked
        widget.lockedWidth = s.lockedWidth
      end
      mdw.wrapInHomeStack(widget)
    end
  end

  mdw._restoringLayout = false
  mdw.reorganizeDock("left")
  mdw.reorganizeDock("right")
  mdw.saveLayout()
end

--- Convenience: group several existing widgets into a new stack at the first's slot.
function mdw.groupWidgetsIntoStack(memberNames, opts)
  opts = opts or {}
  if not memberNames or #memberNames < 1 then return end
  local first = mdw.widgets[memberNames[1]]
  local dock = opts.dock or (first and (first.docked or first.originalDock)) or "left"
  mdw._stackCounter = (mdw._stackCounter or 0) + 1
  local name = opts.name or ("Group" .. mdw._stackCounter)
  local stack = mdw.createStack(name, { dock = dock, row = first and first.row })
  for _, m in ipairs(memberNames) do mdw.addToStack(name, m) end
  return stack
end

--- Wrap a widget in its own single-tab "home" group, the universal dock/float
-- occupant. Called at widget creation and whenever a widget would otherwise end
-- up standalone. No-op if it is already grouped or being restored into a group.
-- The new stack inherits the widget's resolved slot so the layout is preserved.
function mdw.wrapInHomeStack(widget)
  if not widget or widget.isStack then return end
  if widget.stackId or widget._pendingStackId then return end
  -- Wrapping must NEVER fail - a failure would leave the widget rendering bare
  -- (the old centered-title style we no longer allow). Clear a stale empty group
  -- hogging the name, then fall back to a suffixed name if one is still taken.
  local base = "grp_" .. widget.name
  local existing = mdw.widgets[base]
  if existing and existing.isStack and #(existing.members or {}) == 0 then
    mdw.destroyStack(existing)
  end
  local stackName = base
  local n = 1
  while mdw.widgets[stackName] do
    n = n + 1
    stackName = base .. "_" .. n
  end

  -- Capture the widget's resolved slot, then vacate it so the new group becomes
  -- the sole occupant of that spot (no transient double-occupancy).
  local dock = widget.docked or widget.originalDock
  local slot = {
    docked = dock, row = widget.row, rowPosition = widget.rowPosition,
    subRow = widget.subRow, widthRatio = widget.widthRatio, fill = widget.fill,
    widthLocked = widget.widthLocked, lockedWidth = widget.lockedWidth,
  }
  local fx = widget.container and widget.container:get_x()
  local fy = widget.container and widget.container:get_y()
  widget.docked = nil
  widget.row = nil

  local opts = dock and { dock = dock, row = slot.row } or { x = fx, y = fy }
  local stack = mdw.createStack(stackName, opts)
  if not stack then
    widget.docked = slot.docked
    widget.row = slot.row
    return
  end
  -- Carry the widget's full slot onto the group (rowPosition / fill / width ...).
  stack.rowPosition = slot.rowPosition or 0
  stack.subRow = slot.subRow or 0
  stack.widthRatio = slot.widthRatio
  stack.fill = slot.fill or false
  stack.widthLocked = slot.widthLocked or false
  stack.lockedWidth = slot.lockedWidth
  -- Preset the pre-group slot so addToStack records the real standalone spot
  -- (it only captures when _preStackSlot is unset).
  widget._preStackSlot = slot
  mdw.addToStack(stackName, widget.name)
  return stack
end

---------------------------------------------------------------------------
-- TAB DRAG: select / reorder within the bar / tear out to anywhere
---------------------------------------------------------------------------

--- Wire a stack tab button: click selects, horizontal drag reorders within the
-- bar, dragging down/out of the bar tears the member out as a normal widget drag
-- (so it can be floated, re-docked, or dropped into another group).
function mdw.setupStackTabDrag(stack, tabObj)
  local btnName = tabObj.button.name
  local stackName = stack.name
  local memberName = tabObj.memberName

  setLabelClickCallback(btnName, function(event)
    mdw.stackTabDrag = {
      stackName = stackName, memberName = memberName,
      startX = event.globalX, startY = event.globalY, mode = nil,
      -- Where on the tab the press landed (label-local), so the drop-detection
      -- point can track the real cursor instead of the ghost's centre.
      clickLocalX = event.x, clickLocalY = event.y,
    }
  end)

  setLabelMoveCallback(btnName, function(event)
    local d = mdw.stackTabDrag
    if not d or d.memberName ~= memberName then return end
    local s = mdw.widgets[stackName]
    if not s then return end

    -- Decide / update the drag mode. A vertical pull (up OR down, same distance
    -- either way) tears the tab out; a shallow, horizontal-dominant slide
    -- reorders. Every drag direction stays live - no need to aim a straight
    -- vertical line. Tearing out is eager before a reorder begins; once we're
    -- reordering we tolerate more vertical wobble so a sideways slide does not
    -- pop out by accident (and if it does pop, we snap the tabs back first).
    local dx = event.globalX - d.startX
    local dy = event.globalY - d.startY
    local barH = mdw.config.tabBarHeight
    local margin = mdw.config.dragThreshold
    local vPull = (d.mode == "reorder") and barH or barH / 2
    if d.mode ~= "tearout" and math.abs(dy) > vPull then
      if d.mode == "reorder" then mdw.refreshStackTabBar(s) end
      d.mode = "tearout"
      mdw.beginTabGhost(s, tabObj)
    elseif d.mode == nil and math.abs(dx) > margin and math.abs(dx) > math.abs(dy) then
      d.mode = "reorder"
    end

    if d.mode == "reorder" then
      mdw.handleStackTabReorder(s, tabObj, event)
    elseif d.mode == "tearout" then
      mdw.updateTabGhost(s, tabObj, event)
    end
  end)

  setLabelReleaseCallback(btnName, function(event)
    local d = mdw.stackTabDrag
    mdw.stackTabDrag = nil
    if not d or d.memberName ~= memberName then return end
    local s = mdw.widgets[stackName]

    if d.mode == nil then
      if s then mdw.selectStackTab(s, memberName) end
    elseif d.mode == "reorder" then
      if s then mdw.commitStackTabReorder(s, tabObj, event) end
    elseif d.mode == "tearout" then
      -- Defer the detach + placement out of this button's own release callback
      -- (placement deletes this very tab button).
      tempTimer(0, function() mdw.dropTabGhost(d) end)
    end
  end)
end

--- Slide the dragged tab to follow the cursor x (committed on release).
function mdw.handleStackTabReorder(stack, tabObj, event)
  local w = mdw.stackTabWidth(tabObj.name)
  local relX = event.globalX - stack.container:get_x() - w / 2
  local barW = stack.tabBar:get_width()
  relX = mdw.clamp(relX, 0, math.max(0, barW - w))
  tabObj.button:move(relX, 0)
  tabObj.button:raise()
end

--- Commit a tab reorder from the cursor's x relative to the other tabs.
function mdw.commitStackTabReorder(stack, tabObj, event)
  local fromIdx
  for i, t in ipairs(stack.tabObjects) do
    if t == tabObj then fromIdx = i break end
  end
  if not fromIdx then mdw.refreshStackTabBar(stack); return end

  local cursorX = event.globalX
  local x = stack.container:get_x()
  local toIdx = 1
  for i, t in ipairs(stack.tabObjects) do
    if i ~= fromIdx then
      local tw = mdw.stackTabWidth(t.name)
      if cursorX > x + tw / 2 then toIdx = toIdx + 1 end
      x = x + tw
    end
  end

  if toIdx ~= fromIdx then
    local m = table.remove(stack.members, fromIdx)
    table.insert(stack.members, toIdx, m)
    local t = table.remove(stack.tabObjects, fromIdx)
    table.insert(stack.tabObjects, toIdx, t)
    mdw.saveLayout()
  end
  mdw.refreshStackTabBar(stack)
end

--- Tear-out uses a small "ghost" that follows the cursor (like DockView); the
-- member stays in the stack untouched, so there is no mouse-grab handoff. The
-- member is only detached + placed on release.

--- Begin a tear-out: spawn the ghost and dim the original tab. The widget does
-- not move; only the ghost does.
function mdw.beginTabGhost(stack, tabObj)
  local d = mdw.stackTabDrag
  if not d then return end
  d.ghost = mdw.createDragGhost(tabObj.name)
  -- Anchor the ghost to the tab's current screen position (the container's
  -- move-frame x/y plus the tab's left-packed offset), then move it by the
  -- cursor delta (like the widget drag) - avoids any event-vs-move frame offset.
  local tabRelX = 0
  for _, t in ipairs(stack.tabObjects) do
    if t == tabObj then break end
    tabRelX = tabRelX + mdw.stackTabWidth(t.name)
  end
  d.ghostAnchorX = stack.container:get_x() + tabRelX
  d.ghostAnchorY = stack.container:get_y()
  if mdw.styles.tabDragging then
    tabObj.button:setStyleSheet(mdw.styles.tabDragging)
    tabObj.button:setFontSize(mdw.config.tabFontSize)
    tabObj.button:decho("<" .. mdw.config.tabInactiveTextColor .. ">" .. tabObj.name)
  end
end

--- Move the ghost and update the drop indicator. Everything works in the
-- move-frame (anchor + cursor delta), NOT raw event coords, because widget
-- positions are in the move-frame and the two frames can differ by a constant.
function mdw.updateTabGhost(stack, tabObj, event)
  local d = mdw.stackTabDrag
  if not d then return end
  local gx = (d.ghostAnchorX or 0) + (event.globalX - d.startX)
  local gy = (d.ghostAnchorY or 0) + (event.globalY - d.startY)
  -- Detection point = the actual cursor in the move-frame (ghost top-left + where
  -- on the tab it was grabbed), so the thin tab-bar merge zone is reliably hit.
  local cx = gx + (d.clickLocalX or mdw.stackTabWidth(tabObj.name) / 2)
  local cy = gy + (d.clickLocalY or mdw.config.tabBarHeight / 2)
  d.lastX = cx
  d.lastY = cy
  local member = mdw.widgets[d.memberName]
  if member then
    mdw.updateDropIndicator(member, cx, cy)
  end
  if d.ghost then
    d.ghost:move(gx, gy)
    d.ghost:raise()
  end
end

--- Detach a member from a stack: remove its tab + restore its own chrome. Pure
-- model/chrome removal - the CALLER repositions the member and relayouts the
-- stack, so the member is never laid out at a stale slot mid-detach. Clears
-- _preStackSlot (callers that need it, like removeFromStack, read it first).
function mdw.detachMember(stack, memberName)
  local idx
  for i, m in ipairs(stack.members) do
    if m == memberName then idx = i break end
  end
  if not idx then return end
  local tabObj = stack.tabObjects[idx]
  table.remove(stack.members, idx)
  table.remove(stack.tabObjects, idx)
  stack.tabsByName[memberName] = nil
  if tabObj then mdw.deleteElement(tabObj.button) end
  local member = mdw.widgets[memberName]
  if member then
    member.stackId = nil
    member._preStackSlot = nil
    mdw.removeHeadless(member)
  end
  if memberName == stack.activeMember then
    stack.activeMember = stack.members[idx] or stack.members[#stack.members]
  end
end

--- Run (deferred) on tear-out release: delete the ghost, then detach the member
-- and place it where the cursor was (float / dock / merge into another group).
function mdw.dropTabGhost(d)
  if d.ghost then
    mdw.deleteElement(d.ghost)
    d.ghost = nil
  end

  -- The last updateDropIndicator stored the drop intent here.
  local side = mdw.drag.insertSide
  local dropType = mdw.drag.dropType
  local target = mdw.drag.targetWidget
  local rowIndex = mdw.drag.rowIndex
  local positionInRow = mdw.drag.positionInRow
  mdw.hideDropIndicator()
  mdw.updateDockHighlight(nil)
  mdw.drag.insertSide = nil
  mdw.drag.dropType = nil
  mdw.drag.targetWidget = nil
  mdw.drag.rowIndex = nil
  mdw.drag.positionInRow = nil

  local stack = mdw.widgets[d.stackName]
  local member = mdw.widgets[d.memberName]
  if not stack or not member then return end

  -- Dropped back onto its own stack: cancel, restore the tab.
  if dropType == "tab" and target == stack then
    mdw.refreshStackTabBar(stack)
    mdw.layoutStack(stack)
    return
  end

  mdw.detachMember(stack, d.memberName)

  -- If the source group is now empty, destroy it first so its name/slot is free
  -- before we re-home the torn-out member (it may re-use the same "grp_" name).
  local s2 = mdw.widgets[d.stackName]
  if s2 and s2.isStack and #s2.members == 0 then
    mdw.destroyStack(s2)
    s2 = nil
  end

  if not side then
    -- Float: re-home the member in a fresh single-tab group at the release point.
    member.docked = nil
    member.row = nil
    member.rowPosition = nil
    member.subRow = nil
    if member.container then
      member.container:move(math.max(0, (d.lastX or 100) - 30), math.max(0, (d.lastY or 100) - 10))
    end
    local hs = mdw.wrapInHomeStack(member)
    if hs then
      if hs.container then hs.container:show() end
      mdw.raiseWidgetElements(hs)
    end
  elseif dropType == "tab" and target and target ~= stack then
    -- Drop into another group as a tab.
    if target.isStack then
      mdw.addToStack(target.name, d.memberName)
    else
      mdw.groupWidgetsIntoStack({ target.name, d.memberName }, { dock = target.docked or side })
    end
  else
    -- Dock: re-home the member in a fresh group, docked at the drop position.
    member.docked = nil
    member.row = nil
    member.rowPosition = nil
    member.subRow = nil
    local hs = mdw.wrapInHomeStack(member)
    if hs then
      mdw.dockWidgetWithPosition(hs, side, dropType, rowIndex, positionInRow, target)
    end
  end

  -- Relay a surviving floating source group (docked ones via reorganizeDock).
  if s2 and s2.isStack and not s2.docked then
    mdw.layoutStack(s2)
  end
  mdw.reorganizeDock("left")
  mdw.reorganizeDock("right")
  mdw.saveLayout()
  if mdw.rebuildWidgetsMenu then mdw.rebuildWidgetsMenu() end
end

---------------------------------------------------------------------------
-- PUBLIC CLASS-STYLE API
---------------------------------------------------------------------------

mdw.Stack = mdw.Stack or {}

function mdw.Stack.get(name)
  local s = mdw.widgets[name]
  return (s and s.isStack) and s or nil
end

function mdw.Stack.list()
  local names = {}
  for name, w in pairs(mdw.widgets) do
    if w.isStack then names[#names + 1] = name end
  end
  table.sort(names)
  return names
end

function mdw.Stack.select(name, memberName)
  local s = mdw.Stack.get(name)
  if s then mdw.selectStackTab(s, memberName) end
end
