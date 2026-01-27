--[[
  MDW_Init.lua
  Lifecycle management and dock infrastructure for MDW (Mudlet Dockable Widgets).

  Handles package install/uninstall, profile load events, window resize,
  and creates the dock backgrounds, splitters, and drop indicators.

  Dependencies: MDW_Config.lua must be loaded first (provides mdw table, config, styles)
]]

---------------------------------------------------------------------------
-- DOCK CREATION
-- Creates the sidebar backgrounds, splitters, and drop indicators.
---------------------------------------------------------------------------

--- Create dock backgrounds, splitters, header, and prompt bar.
-- Why: The docks provide the visual container for widgets and the
-- splitters allow users to resize dock widths interactively.
function mdw.createDocks()
  local cfg = mdw.config
  local winW, winH = getMainWindowSize()

  -- Set Mudlet borders to reserve space for our UI
  setBorderLeft(cfg.leftDockWidth)
  setBorderRight(cfg.rightDockWidth)
  setBorderTop(cfg.headerHeight)
  setBorderBottom(cfg.promptBarHeight)

  -- Calculate sidebar height (window height minus header)
  local sidebarHeight = winH - cfg.headerHeight

  mdw.createHeader()
  mdw.createPromptBar(winW)
  mdw.createDropIndicators(winW)
  mdw.createLeftDock(sidebarHeight)
  mdw.createRightDock(sidebarHeight)
end

--- Create the header pane and separator.
function mdw.createHeader()
  local cfg = mdw.config

  mdw.headerPane = mdw.trackElement(Geyser.Label:new({
    name = "MDW_HeaderPane",
    x = 0,
    y = 0,
    width = "100%",
    height = cfg.headerHeight - cfg.splitterWidth,
  }))
  mdw.headerPane:setStyleSheet(mdw.styles.headerPane)
  setLabelClickCallback("MDW_HeaderPane", function()
    if mdw.closeAllMenus then mdw.closeAllMenus() end
  end)

  -- Separator line frames the main text area
  mdw.headerSeparator = mdw.trackElement(Geyser.Label:new({
    name = "MDW_HeaderSeparator",
    x = 0,
    y = cfg.headerHeight - cfg.splitterWidth,
    width = "100%",
    height = cfg.splitterWidth,
  }))
  mdw.headerSeparator:setStyleSheet(mdw.styles.separatorLine)
  setLabelClickCallback("MDW_HeaderSeparator", function()
    if mdw.closeAllMenus then mdw.closeAllMenus() end
  end)
end

--- Create the prompt bar at the bottom of the main display.
-- @param winW number Window width
function mdw.createPromptBar(winW)
  local cfg = mdw.config
  local promptBarWidth = winW - cfg.leftDockWidth - cfg.rightDockWidth

  -- Separator above prompt bar
  mdw.promptSeparator = mdw.trackElement(Geyser.Label:new({
    name = "MDW_PromptSeparator",
    x = cfg.leftDockWidth,
    y = -cfg.promptBarHeight,
    width = promptBarWidth,
    height = cfg.splitterWidth,
  }))
  mdw.promptSeparator:setStyleSheet(mdw.styles.separatorLine)
  setLabelClickCallback("MDW_PromptSeparator", function()
    if mdw.closeAllMenus then mdw.closeAllMenus() end
  end)

  -- Prompt bar itself
  mdw.promptBar = mdw.trackElement(Geyser.Label:new({
    name = "MDW_PromptBar",
    x = cfg.leftDockWidth,
    y = -cfg.promptBarHeight + cfg.splitterWidth,
    width = promptBarWidth,
    height = cfg.promptBarHeight - cfg.splitterWidth,
  }))
  mdw.promptBar:setStyleSheet(mdw.styles.headerPane)
  setLabelClickCallback("MDW_PromptBar", function()
    if mdw.closeAllMenus then mdw.closeAllMenus() end
  end)
end

--- Create drop indicators for drag-and-drop feedback.
-- @param winW number Window width
function mdw.createDropIndicators(winW)
  local cfg = mdw.config

  -- Horizontal drop indicator for left dock (vertical stacking)
  local totalMargin = cfg.widgetMargin * 2
  mdw.leftDropIndicator = mdw.trackElement(Geyser.Label:new({
    name = "MDW_LeftDropIndicator",
    x = cfg.widgetMargin,
    y = -100,
    width = cfg.leftDockWidth - totalMargin - cfg.splitterWidth,
    height = cfg.dropIndicatorHeight,
  }))
  mdw.leftDropIndicator:setStyleSheet(mdw.styles.dropIndicator)
  mdw.leftDropIndicator:hide()

  -- Horizontal drop indicator for right dock
  mdw.rightDropIndicator = mdw.trackElement(Geyser.Label:new({
    name = "MDW_RightDropIndicator",
    x = cfg.widgetMargin,
    y = -100,
    width = cfg.rightDockWidth - totalMargin - cfg.splitterWidth,
    height = cfg.dropIndicatorHeight,
  }))
  mdw.rightDropIndicator:setStyleSheet(mdw.styles.dropIndicator)
  mdw.rightDropIndicator:hide()

  -- Vertical drop indicator for side-by-side docking
  mdw.verticalDropIndicator = mdw.trackElement(Geyser.Label:new({
    name = "MDW_VerticalDropIndicator",
    x = -100,
    y = 0,
    width = cfg.dropIndicatorHeight,
    height = 100,
  }))
  mdw.verticalDropIndicator:setStyleSheet(mdw.styles.dropIndicator)
  mdw.verticalDropIndicator:hide()
end

--- Create the left dock background and splitter.
-- @param sidebarHeight number Height of the sidebar
function mdw.createLeftDock(sidebarHeight)
  local cfg = mdw.config

  mdw.leftDock = mdw.trackElement(Geyser.Label:new({
    name = "MDW_LeftDock",
    x = 0,
    y = cfg.headerHeight,
    width = cfg.leftDockWidth - cfg.splitterWidth,
    height = sidebarHeight,
  }))
  mdw.leftDock:setStyleSheet(mdw.styles.sidebar)
  setLabelClickCallback("MDW_LeftDock", function()
    if mdw.closeAllMenus then mdw.closeAllMenus() end
  end)

  -- Highlight overlay (hidden by default, shown during drag)
  mdw.leftDockHighlight = mdw.trackElement(Geyser.Label:new({
    name = "MDW_LeftDockHighlight",
    x = 0,
    y = cfg.headerHeight,
    width = cfg.leftDockWidth - cfg.splitterWidth,
    height = sidebarHeight,
  }))
  mdw.leftDockHighlight:setStyleSheet(mdw.styles.dockHighlight)
  mdw.leftDockHighlight:hide()

  -- Splitter for resizing
  mdw.leftSplitter = mdw.trackElement(Geyser.Label:new({
    name = "MDW_LeftSplitter",
    x = cfg.leftDockWidth - cfg.splitterWidth,
    y = cfg.headerHeight,
    width = cfg.splitterWidth,
    height = sidebarHeight,
  }))
  mdw.leftSplitter:setStyleSheet(mdw.styles.splitter)
  mdw.leftSplitter:setCursor(mudlet.cursor.ResizeHorizontal)
  mdw.setupDockSplitter("left")
end

--- Create the right dock background and splitter.
-- @param sidebarHeight number Height of the sidebar
function mdw.createRightDock(sidebarHeight)
  local cfg = mdw.config

  mdw.rightDock = mdw.trackElement(Geyser.Label:new({
    name = "MDW_RightDock",
    x = -cfg.rightDockWidth + cfg.splitterWidth,
    y = cfg.headerHeight,
    width = cfg.rightDockWidth - cfg.splitterWidth,
    height = sidebarHeight,
  }))
  mdw.rightDock:setStyleSheet(mdw.styles.sidebar)
  setLabelClickCallback("MDW_RightDock", function()
    if mdw.closeAllMenus then mdw.closeAllMenus() end
  end)

  -- Highlight overlay (hidden by default, shown during drag)
  mdw.rightDockHighlight = mdw.trackElement(Geyser.Label:new({
    name = "MDW_RightDockHighlight",
    x = -cfg.rightDockWidth + cfg.splitterWidth,
    y = cfg.headerHeight,
    width = cfg.rightDockWidth - cfg.splitterWidth,
    height = sidebarHeight,
  }))
  mdw.rightDockHighlight:setStyleSheet(mdw.styles.dockHighlight)
  mdw.rightDockHighlight:hide()

  -- Splitter for resizing
  mdw.rightSplitter = mdw.trackElement(Geyser.Label:new({
    name = "MDW_RightSplitter",
    x = -cfg.rightDockWidth,
    y = cfg.headerHeight,
    width = cfg.splitterWidth,
    height = sidebarHeight,
  }))
  mdw.rightSplitter:setStyleSheet(mdw.styles.splitter)
  mdw.rightSplitter:setCursor(mudlet.cursor.ResizeHorizontal)
  mdw.setupDockSplitter("right")
end

---------------------------------------------------------------------------
-- DOCK SPLITTER HANDLING
-- Enables dragging the dock splitters to resize dock widths.
---------------------------------------------------------------------------

--- Set up drag handling for a dock splitter.
-- Why: Splitters need click/move/release callbacks to track drag state
-- and update dock width in real-time during the drag operation.
-- @param side string "left" or "right"
function mdw.setupDockSplitter(side)
  local splitterName = "MDW_" .. (side == "left" and "Left" or "Right") .. "Splitter"
  local splitter = (side == "left") and mdw.leftSplitter or mdw.rightSplitter

  setLabelClickCallback(splitterName, function(event)
    mdw.splitterDrag.active = true
    mdw.splitterDrag.side = side
    mdw.splitterDrag.offsetX = event.globalX - splitter:get_x()
  end)

  setLabelMoveCallback(splitterName, function(event)
    if mdw.splitterDrag.active and mdw.splitterDrag.side == side then
      local splitterX = event.globalX - mdw.splitterDrag.offsetX
      mdw.resizeDockBySplitter(side, splitterX)
    end
  end)

  setLabelReleaseCallback(splitterName, function()
    if mdw.splitterDrag.active and mdw.splitterDrag.side == side then
      mdw.splitterDrag.active = false
      mdw.splitterDrag.side = nil
      if mdw.reorganizeDock then
        mdw.reorganizeDock(side)
      end
    end
  end)
end

--- Resize a dock based on splitter position.
-- @param side string "left" or "right"
-- @param splitterX number The X position of the splitter
function mdw.resizeDockBySplitter(side, splitterX)
  local winW = getMainWindowSize()
  local cfg = mdw.config
  local newWidth

  if side == "left" then
    newWidth = splitterX + cfg.splitterWidth
  else
    newWidth = winW - splitterX
  end

  newWidth = mdw.clamp(newWidth, cfg.minDockWidth, cfg.maxDockWidth)
  mdw.applyDockWidth(side, newWidth)
end

--- Apply a new width to a dock, updating all related elements.
-- @param side string "left" or "right"
-- @param newWidth number The new dock width
function mdw.applyDockWidth(side, newWidth)
  local cfg = mdw.config

  if side == "left" then
    cfg.leftDockWidth = newWidth
    setBorderLeft(newWidth)
    mdw.leftDock:resize(newWidth - cfg.splitterWidth, nil)
    if mdw.leftDockHighlight then
      mdw.leftDockHighlight:resize(newWidth - cfg.splitterWidth, nil)
    end
    mdw.leftSplitter:move(newWidth - cfg.splitterWidth, nil)
  else
    cfg.rightDockWidth = newWidth
    setBorderRight(newWidth)
    mdw.rightDock:resize(newWidth - cfg.splitterWidth, nil)
    mdw.rightDock:move(-newWidth + cfg.splitterWidth, nil)
    if mdw.rightDockHighlight then
      mdw.rightDockHighlight:resize(newWidth - cfg.splitterWidth, nil)
      mdw.rightDockHighlight:move(-newWidth + cfg.splitterWidth, nil)
    end
    mdw.rightSplitter:move(-newWidth, nil)
  end

  -- Update prompt bar position and width
  if mdw.promptBar then
    local winW = getMainWindowSize()
    local promptBarWidth = winW - cfg.leftDockWidth - cfg.rightDockWidth
    mdw.promptBar:move(cfg.leftDockWidth, nil)
    mdw.promptBar:resize(promptBarWidth, nil)
    if mdw.promptSeparator then
      mdw.promptSeparator:move(cfg.leftDockWidth, nil)
      mdw.promptSeparator:resize(promptBarWidth, nil)
    end
  end

  -- Reorganize widgets in real-time during drag
  if mdw.reorganizeDock then
    mdw.reorganizeDock(side)
  end
end

---------------------------------------------------------------------------
-- LIFECYCLE MANAGEMENT
-- Handles setup, teardown, and Mudlet events.
---------------------------------------------------------------------------

--- Full UI setup - creates all components.
function mdw.setup()
  mdw.echo("Setting up UI...")
  mdw.createDocks()

  -- Call user-registered widget creation functions first
  -- This allows widgets to be created before menus are built
  if mdw.userWidgets then
    for _, func in ipairs(mdw.userWidgets) do
      local ok, err = pcall(func)
      if not ok then
        mdw.echo("<red>Error in user widget function: " .. tostring(err))
      end
    end
  end

  -- Create header menus and finalize widget layout
  if mdw.createWidgets then
    mdw.createWidgets()
  else
    mdw.echo("<red>Warning: mdw.createWidgets not defined")
  end

  -- Raise any mapper widgets to ensure visibility
  mdw.raiseMapperWidgets()

  -- Fire event so user scripts can create additional widgets
  raiseEvent("mdwReady")

  mdw.echo("UI ready!")
end

--- Register a function to create user widgets on package load.
-- This function will be called during mdw.setup() after default widgets are created.
-- Use this to ensure your custom widgets are recreated when the package reloads.
-- @param func function The widget creation function
function mdw.registerWidgets(func)
  mdw.userWidgets = mdw.userWidgets or {}
  mdw.userWidgets[#mdw.userWidgets + 1] = func
end

--- Raise all widgets containing embedded mappers.
-- Why: Mappers can be obscured by other UI elements created after them.
-- This ensures mapper widgets are visible after all UI initialization completes.
function mdw.raiseMapperWidgets()
  for _, widget in pairs(mdw.widgets) do
    if widget.mapper then
      widget.container:raise()
      widget.mapper:raise()
      mdw.debugEcho("Raised mapper widget: " .. (widget.name or "unknown"))
    end
  end
end

--- Full UI teardown - cleans up all components.
function mdw.teardown()
  mdw.echo("Cleaning up UI...")

  mdw.destroyAllElements()

  setBorderLeft(0)
  setBorderRight(0)
  setBorderTop(0)
  setBorderBottom(0)

  mdw.echo("Cleanup complete")
end

--- Handle package installation.
-- Why: Called by Mudlet when package is installed or updated.
-- Sets up the UI after successful installation.
function mdw.onInstall(_, package)
  if package ~= mdw.packageName then return end

  if mdw.isUpdating then
    mdw.isUpdating = false
    mdw.echo("Update complete!")
  else
    mdw.echo("Package installed!")
  end

  mdw.setup()
end

--- Handle package uninstall.
-- Why: Ensures clean removal of all UI elements and handlers.
-- Skips teardown during updates to preserve state.
function mdw.onUninstall(_, package)
  if package ~= mdw.packageName then return end

  if not mdw.isUpdating then
    mdw.teardown()
    mdw.killAllHandlers()
  end
end

--- Handle profile load (Mudlet startup with existing profile).
-- Why: Re-creates the UI when loading a profile that has the package installed.
function mdw.onProfileLoad()
  if not mdw.leftDock then
    mdw.setup()
  end
end

--- Handle window resize events.
-- Why: Updates dock and widget positions to match new window dimensions.
function mdw.onWindowResize()
  local winW, winH = getMainWindowSize()
  local cfg = mdw.config
  local sidebarHeight = winH - cfg.headerHeight

  -- Update left dock
  if mdw.leftDock then
    mdw.leftDock:move(nil, cfg.headerHeight)
    mdw.leftDock:resize(nil, sidebarHeight)
    if mdw.leftDockHighlight then
      mdw.leftDockHighlight:move(nil, cfg.headerHeight)
      mdw.leftDockHighlight:resize(nil, sidebarHeight)
    end
    mdw.leftSplitter:move(nil, cfg.headerHeight)
    mdw.leftSplitter:resize(nil, sidebarHeight)
  end

  -- Update right dock
  if mdw.rightDock then
    mdw.rightDock:move(-cfg.rightDockWidth + cfg.splitterWidth, cfg.headerHeight)
    mdw.rightDock:resize(nil, sidebarHeight)
    if mdw.rightDockHighlight then
      mdw.rightDockHighlight:move(-cfg.rightDockWidth + cfg.splitterWidth, cfg.headerHeight)
      mdw.rightDockHighlight:resize(nil, sidebarHeight)
    end
    mdw.rightSplitter:move(-cfg.rightDockWidth, cfg.headerHeight)
    mdw.rightSplitter:resize(nil, sidebarHeight)
  end

  -- Update prompt bar width
  if mdw.promptBar then
    local promptBarWidth = winW - cfg.leftDockWidth - cfg.rightDockWidth
    mdw.promptBar:resize(promptBarWidth, nil)
    if mdw.promptSeparator then
      mdw.promptSeparator:resize(promptBarWidth, nil)
    end
  end

  -- Reorganize widgets
  if mdw.reorganizeDock then
    mdw.reorganizeDock("left")
    mdw.reorganizeDock("right")
  end

  -- Ensure mapper widgets stay visible after resize
  mdw.raiseMapperWidgets()
end

---------------------------------------------------------------------------
-- EVENT HANDLER REGISTRATION
---------------------------------------------------------------------------

mdw.registerHandler("sysInstallPackage", "install", "mdw.onInstall")
mdw.registerHandler("sysUninstallPackage", "uninstall", "mdw.onUninstall")
mdw.registerHandler("sysLoadEvent", "profileLoad", "mdw.onProfileLoad")
mdw.registerHandler("sysWindowResizeEvent", "windowResize", "mdw.onWindowResize")
