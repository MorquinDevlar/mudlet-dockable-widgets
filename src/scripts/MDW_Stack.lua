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
  pcall(function() deleteLabel(btnName) end)
  for i = #mdw.elements, 1, -1 do
    if mdw.elements[i] and mdw.elements[i].name == btnName then table.remove(mdw.elements, i) break end
  end
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
  local member = mdw.widgets[memberName]

  local idx
  for i, m in ipairs(stack.members) do
    if m == memberName then idx = i break end
  end
  if not idx then
    mdw.echo("removeFromStack: '" .. tostring(memberName) .. "' is not in '" .. tostring(stackName) .. "'")
    return
  end

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

  -- Fallback: any member whose stack record was missing -> dock it standalone
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
        if mdw.updateDockButtonVisibility then mdw.updateDockButtonVisibility(widget) end
      end
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
    }
  end)

  setLabelMoveCallback(btnName, function(event)
    local d = mdw.stackTabDrag
    if not d or d.memberName ~= memberName then return end
    local s = mdw.widgets[stackName]
    if not s then return end

    if d.mode == nil then
      local dx = event.globalX - d.startX
      local dy = event.globalY - d.startY
      if dy > mdw.config.tabBarHeight then
        d.mode = "tearout"
        mdw.beginTabTearout(s, tabObj, event)
      elseif math.abs(dx) > mdw.config.dragThreshold then
        d.mode = "reorder"
      end
    end

    if d.mode == "reorder" then
      mdw.handleStackTabReorder(s, tabObj, event)
    elseif d.mode == "tearout" then
      local member = mdw.widgets[memberName]
      if member and mdw.drag.active and mdw.drag.widget == member then
        mdw.handleDragMove(member, event)
        -- The torn tab button keeps the mouse grab, so it must stay visible and
        -- unclipped. Slide it within the stack toward the cursor so it reads as
        -- "being pulled out" instead of a stuck duplicate tab.
        local tw = mdw.stackTabWidth(tabObj.name)
        local relX = mdw.clamp(event.globalX - s.container:get_x() - tw / 2,
          0, math.max(0, s.container:get_width() - tw))
        local relY = mdw.clamp(event.globalY - s.container:get_y(),
          0, math.max(0, s.container:get_height() - mdw.config.tabBarHeight))
        tabObj.button:move(relX, relY)
        tabObj.button:raise()
      end
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
      local member = mdw.widgets[memberName]
      if member and mdw.drag.active and mdw.drag.widget == member then
        mdw.endDrag(member, event)
      end
      mdw.finalizeTabTearout(d)
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

--- Detach a member from its stack and hand it to the widget drag system so it
-- follows the cursor and can be dropped anywhere. The tab button MUST stay
-- visible: it owns the mouse grab, so hiding it would drop the grab and stop
-- the move/release events mid-drag. finalizeTabTearout deletes it on release.
function mdw.beginTabTearout(stack, tabObj, event)
  local memberName = tabObj.memberName
  local member = mdw.widgets[memberName]
  if not member then return end

  local idx
  for i, m in ipairs(stack.members) do
    if m == memberName then idx = i break end
  end
  if idx then
    table.remove(stack.members, idx)
    table.remove(stack.tabObjects, idx)
  end
  stack.tabsByName[memberName] = nil

  if memberName == stack.activeMember then
    stack.activeMember = stack.members[idx] or stack.members[#stack.members]
  end

  -- Detach into a free-floating widget
  member.stackId = nil
  member._preStackSlot = nil
  mdw.removeHeadless(member)
  member.docked = nil
  if member.container then member.container:show() end
  mdw.showResizeHandles(member)

  if #stack.members > 0 then
    mdw.layoutStack(stack)
  end

  -- Hand off to the normal widget drag (follows cursor; endDrag finalises)
  mdw.startDrag(member, event)
  mdw.commitDragStart(member)
end

--- After a tear-out drop: delete the orphaned tab button and clean the stack
-- (unless the member was dropped straight back into this same stack).
function mdw.finalizeTabTearout(d)
  local stack = mdw.widgets[d.stackName]
  local rejoined = stack and stack.isStack and stack.tabsByName[d.memberName]

  if not rejoined then
    local btnName = "MDW_" .. d.stackName .. "_Tab_" .. safeName(d.memberName)
    tempTimer(0, function()
      pcall(function() deleteLabel(btnName) end)
      for i = #mdw.elements, 1, -1 do
        local el = mdw.elements[i]
        if el and el.name == btnName then table.remove(mdw.elements, i) break end
      end
    end)
  end

  if stack and stack.isStack then
    if #stack.members == 0 then
      mdw.destroyStack(stack)
    else
      mdw.layoutStack(stack)
      mdw.saveLayout()
    end
  end
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
