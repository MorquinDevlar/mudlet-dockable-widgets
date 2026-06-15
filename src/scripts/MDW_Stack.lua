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
      mdw.applyTabActiveStyle(tabObj)
    else
      mdw.applyTabInactiveStyle(tabObj)
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
      mdw.resizeWidgetContent(member, contentW, contentH)
      if memberName == stack.activeMember then
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
  else
    mdw.resizeStackContent(stack)
  end
  mdw.raiseWidgetElements(stack)
end

--- Make a member render without its own chrome (the stack provides it).
function mdw.applyHeadless(member)
  member._headless = true
  if member.titleBar then member.titleBar:hide() end
  if member.fillButton then member.fillButton:hide() end
  if member.lockButton then member.lockButton:hide() end
  if member.closeButton then member.closeButton:hide() end
  if member.bottomResizeHandle then member.bottomResizeHandle:hide() end
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
  mdw.setupStackDrag(stack)
  mdw.setupDockedResizeHandle(stack)

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

  -- Remember the standalone slot for a clean ungroup
  member._preStackSlot = {
    docked = member.docked, row = member.row, rowPosition = member.rowPosition,
    subRow = member.subRow, widthRatio = member.widthRatio, fill = member.fill,
    widthLocked = member.widthLocked, lockedWidth = member.lockedWidth,
  }
  member.stackId = stackName

  index = index or (#stack.members + 1)
  table.insert(stack.members, index, memberName)

  local btn = mdw.trackElement(Geyser.Label:new({
    name = "MDW_" .. stackName .. "_Tab_" .. safeName(memberName),
    x = 0, y = 0, width = 60, height = mdw.config.tabBarHeight,
  }, stack.container))
  btn:setCursor(mudlet.cursor.PointingHand)
  local tabObj = { memberName = memberName, name = member.title or memberName, button = btn }
  table.insert(stack.tabObjects, index, tabObj)
  stack.tabsByName[memberName] = tabObj

  setLabelClickCallback(btn.name, function()
    local s = mdw.widgets[stackName]
    if s then mdw.selectStackTab(s, memberName) end
  end)

  mdw.applyHeadless(member)
  if not stack.activeMember then stack.activeMember = memberName end

  mdw.layoutStack(stack)
  mdw.saveLayout()
  if mdw.rebuildWidgetsMenu then mdw.rebuildWidgetsMenu() end
end

--- Remove a member from a stack, restoring it as a standalone widget.
function mdw.removeFromStack(stackName, memberName)
  local stack = mdw.widgets[stackName]
  if not stack or not stack.isStack then return end
  local member = mdw.widgets[memberName]

  local idx
  for i, m in ipairs(stack.members) do
    if m == memberName then idx = i break end
  end
  if not idx then return end

  local tabObj = stack.tabObjects[idx]
  table.remove(stack.members, idx)
  table.remove(stack.tabObjects, idx)
  stack.tabsByName[memberName] = nil

  if tabObj and tabObj.button then
    pcall(function() tabObj.button:hide() end)
    pcall(function() if tabObj.button.name then deleteLabel(tabObj.button.name) end end)
    for i = #mdw.elements, 1, -1 do
      if mdw.elements[i] == tabObj.button then table.remove(mdw.elements, i) break end
    end
  end

  if member then
    member.stackId = nil
    mdw.removeHeadless(member)
    local saved = member._preStackSlot
    member._preStackSlot = nil
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

  if memberName == stack.activeMember then
    stack.activeMember = stack.members[idx] or stack.members[#stack.members]
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

--- Destroy an (empty) stack and free its elements.
function mdw.destroyStack(stack)
  local owned = { stack.tabBar, stack.bottomResizeHandle }
  for _, t in ipairs(stack.tabObjects or {}) do owned[#owned + 1] = t.button end
  owned[#owned + 1] = stack.container

  local toRemove = {}
  for _, el in ipairs(owned) do
    if el then
      toRemove[el] = true
      pcall(function() if el.hide then el:hide() end end)
      pcall(function() if el.name then deleteLabel(el.name) end end)
    end
  end
  for i = #mdw.elements, 1, -1 do
    if toRemove[mdw.elements[i]] then table.remove(mdw.elements, i) end
  end

  local side = stack.docked
  mdw.widgets[stack.name] = nil
  if side then mdw.reorganizeDock(side) end
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
