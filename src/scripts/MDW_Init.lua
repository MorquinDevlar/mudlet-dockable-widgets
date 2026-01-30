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

  -- Set Mudlet borders based on visibility (loaded from layout)
  local leftWidth = mdw.visibility.leftSidebar and cfg.leftDockWidth or 0
  local rightWidth = mdw.visibility.rightSidebar and cfg.rightDockWidth or 0
  local bottomHeight = mdw.visibility.promptBar and cfg.promptBarHeight or 0

  setBorderLeft(leftWidth)
  setBorderRight(rightWidth)
  setBorderTop(cfg.headerHeight)
  setBorderBottom(bottomHeight)

  -- Calculate sidebar height (window height minus header)
  local sidebarHeight = winH - cfg.headerHeight

  mdw.createHeader(winW)
  mdw.createPromptBar(winW)
  mdw.createDropIndicators(winW)
  mdw.createLeftDock(sidebarHeight)
  mdw.createRightDock(sidebarHeight)

  -- Hide docks/prompt if they were saved as hidden
  if not mdw.visibility.leftSidebar then
    mdw.leftDock:hide()
    mdw.leftSplitter:hide()
  end
  if not mdw.visibility.rightSidebar then
    mdw.rightDock:hide()
    mdw.rightSplitter:hide()
  end
  if not mdw.visibility.promptBar then
    if mdw.promptBarContainer then mdw.promptBarContainer:hide() end
    mdw.promptSeparator:hide()
  end
end

function mdw.createHeader(winW)
  local cfg = mdw.config

  mdw.headerPane = mdw.trackElement(Geyser.Label:new({
    name = "MDW_HeaderPane",
    x = 0,
    y = 0,
    width = "100%",
    height = cfg.headerHeight - cfg.separatorHeight,
  }))
  mdw.headerPane:setStyleSheet(mdw.styles.headerPane)
  setLabelClickCallback("MDW_HeaderPane", function()
    if mdw.closeAllMenus then mdw.closeAllMenus() end
  end)

  -- Separator line frames the main text area
  mdw.headerSeparator = mdw.trackElement(Geyser.Label:new({
    name = "MDW_HeaderSeparator",
    x = 0,
    y = cfg.headerHeight - cfg.separatorHeight,
    width = "100%",
    height = cfg.separatorHeight,
  }))
  mdw.headerSeparator:setStyleSheet(mdw.styles.separatorLine)
  setLabelClickCallback("MDW_HeaderSeparator", function()
    if mdw.closeAllMenus then mdw.closeAllMenus() end
  end)
end

function mdw.createPromptBar(winW)
  local cfg = mdw.config

  -- Calculate effective dock widths based on visibility
  local leftWidth = mdw.visibility.leftSidebar and cfg.leftDockWidth or 0
  local rightWidth = mdw.visibility.rightSidebar and cfg.rightDockWidth or 0

  local promptBarWidth = winW - leftWidth - rightWidth
  local promptBarContentHeight = cfg.promptBarHeight - cfg.separatorHeight
  local bgRGB = cfg.widgetBackgroundRGB
  local fgRGB = cfg.widgetForegroundRGB

  -- Separator above prompt bar
  mdw.promptSeparator = mdw.trackElement(Geyser.Label:new({
    name = "MDW_PromptSeparator",
    x = leftWidth,
    y = -cfg.promptBarHeight,
    width = promptBarWidth,
    height = cfg.separatorHeight,
  }))
  mdw.promptSeparator:setStyleSheet(mdw.styles.separatorLine)
  setLabelClickCallback("MDW_PromptSeparator", function()
    if mdw.closeAllMenus then mdw.closeAllMenus() end
  end)

  -- Prompt bar container (handles positioning and click events)
  local consoleWidth = promptBarWidth - cfg.contentPaddingLeft
  mdw.promptBarContainer = mdw.trackElement(Geyser.Container:new({
    name = "MDW_PromptBarContainer",
    x = leftWidth,
    y = -cfg.promptBarHeight + cfg.separatorHeight,
    width = promptBarWidth,
    height = promptBarContentHeight,
  }))

  -- Background label (for padding area and click handling)
  mdw.promptBarBg = mdw.trackElement(Geyser.Label:new({
    name = "MDW_PromptBarBg",
    x = 0,
    y = 0,
    width = "100%",
    height = "100%",
  }, mdw.promptBarContainer))
  mdw.promptBarBg:setStyleSheet(string.format(
    [[background-color: rgb(%d,%d,%d);]],
    bgRGB[1], bgRGB[2], bgRGB[3]
  ))
  setLabelClickCallback("MDW_PromptBarBg", function()
    if mdw.closeAllMenus then mdw.closeAllMenus() end
  end)

  -- Prompt bar MiniConsole (offset by padding, child of container)
  local topPadding = cfg.promptBarTopPadding
  mdw.promptBar = mdw.trackElement(Geyser.MiniConsole:new({
    name = "MDW_PromptBar",
    x = cfg.contentPaddingLeft,
    y = topPadding,
    width = consoleWidth,
    height = promptBarContentHeight - topPadding,
  }, mdw.promptBarContainer))
  mdw.promptBar:setColor(bgRGB[1], bgRGB[2], bgRGB[3], 255)
  mdw.promptBar:setFont(cfg.fontFamily)
  mdw.promptBar:setFontSize(cfg.fontSize)
  mdw.promptBar:setWrap(mdw.calculateWrap(consoleWidth))
  setBgColor("MDW_PromptBar", bgRGB[1], bgRGB[2], bgRGB[3])
  setFgColor("MDW_PromptBar", fgRGB[1], fgRGB[2], fgRGB[3])
  mdw.promptBar:raise()
end

---------------------------------------------------------------------------
-- PROMPT BAR API
-- Functions for displaying content in the prompt bar.
---------------------------------------------------------------------------

function mdw.setPrompt(text)
  if mdw.promptBar then
    mdw.promptBar:clear()
    mdw.promptBar:decho(text)
  end
end

function mdw.setPromptCecho(text)
  if mdw.promptBar then
    mdw.promptBar:clear()
    mdw.promptBar:cecho(text)
  end
end

function mdw.clearPrompt()
  if mdw.promptBar then
    mdw.promptBar:clear()
  end
end

--- Capture the current line from the main window with colors and display in prompt bar.
-- Call this from a prompt trigger to capture and display the MUD prompt.
function mdw.capturePrompt(deleteFromMain)
  if not mdw.promptBar then return end
  if deleteFromMain == nil then deleteFromMain = true end

  selectCurrentLine()

  -- Get text with decho formatting, strip background colors so console bg shows through
  local text = copy2decho():gsub("<(%d+,%d+,%d+):%d+,%d+,%d+>", "<%1>")

  mdw.promptBar:clear()
  mdw.promptBar:decho(text)

  if deleteFromMain then
    deleteLine()
  end

  deselect()
end

function mdw.createDropIndicators(winW)
  local cfg = mdw.config

  -- Horizontal drop indicator for left dock (vertical stacking)
  local totalMargin = cfg.widgetMargin * 2
  mdw.leftDropIndicator = mdw.trackElement(Geyser.Label:new({
    name = "MDW_LeftDropIndicator",
    x = cfg.widgetMargin,
    y = -100,
    width = cfg.leftDockWidth - totalMargin - cfg.dockSplitterWidth,
    height = cfg.dropIndicatorHeight,
  }))
  mdw.leftDropIndicator:setStyleSheet(mdw.styles.dropIndicator)
  mdw.leftDropIndicator:hide()

  -- Horizontal drop indicator for right dock
  mdw.rightDropIndicator = mdw.trackElement(Geyser.Label:new({
    name = "MDW_RightDropIndicator",
    x = cfg.widgetMargin,
    y = -100,
    width = cfg.rightDockWidth - totalMargin - cfg.dockSplitterWidth,
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

function mdw.createLeftDock(sidebarHeight)
  local cfg = mdw.config

  mdw.leftDock = mdw.trackElement(Geyser.Label:new({
    name = "MDW_LeftDock",
    x = 0,
    y = cfg.headerHeight,
    width = cfg.leftDockWidth - cfg.dockSplitterWidth,
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
    width = cfg.leftDockWidth - cfg.dockSplitterWidth,
    height = sidebarHeight,
  }))
  mdw.leftDockHighlight:setStyleSheet(mdw.styles.dockHighlight)
  mdw.leftDockHighlight:hide()

  -- Splitter for resizing
  mdw.leftSplitter = mdw.trackElement(Geyser.Label:new({
    name = "MDW_LeftSplitter",
    x = cfg.leftDockWidth - cfg.dockSplitterWidth,
    y = cfg.headerHeight,
    width = cfg.dockSplitterWidth,
    height = sidebarHeight,
  }))
  mdw.leftSplitter:setStyleSheet(mdw.styles.splitter)
  mdw.leftSplitter:setCursor(mudlet.cursor.ResizeHorizontal)
  mdw.setupDockSplitter("left")
end

function mdw.createRightDock(sidebarHeight)
  local cfg = mdw.config

  mdw.rightDock = mdw.trackElement(Geyser.Label:new({
    name = "MDW_RightDock",
    x = -cfg.rightDockWidth + cfg.dockSplitterWidth,
    y = cfg.headerHeight,
    width = cfg.rightDockWidth - cfg.dockSplitterWidth,
    height = sidebarHeight,
  }))
  mdw.rightDock:setStyleSheet(mdw.styles.sidebar)
  setLabelClickCallback("MDW_RightDock", function()
    if mdw.closeAllMenus then mdw.closeAllMenus() end
  end)

  -- Highlight overlay (hidden by default, shown during drag)
  mdw.rightDockHighlight = mdw.trackElement(Geyser.Label:new({
    name = "MDW_RightDockHighlight",
    x = -cfg.rightDockWidth + cfg.dockSplitterWidth,
    y = cfg.headerHeight,
    width = cfg.rightDockWidth - cfg.dockSplitterWidth,
    height = sidebarHeight,
  }))
  mdw.rightDockHighlight:setStyleSheet(mdw.styles.dockHighlight)
  mdw.rightDockHighlight:hide()

  -- Splitter for resizing
  mdw.rightSplitter = mdw.trackElement(Geyser.Label:new({
    name = "MDW_RightSplitter",
    x = -cfg.rightDockWidth,
    y = cfg.headerHeight,
    width = cfg.dockSplitterWidth,
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
      mdw.saveLayout()
      -- Force repaint on all docked widgets after resize
      for _, widget in pairs(mdw.widgets) do
        if widget.docked == side then
          mdw.refreshWidgetContent(widget)
        end
      end
    end
  end)
end

function mdw.resizeDockBySplitter(side, splitterX)
  local winW = getMainWindowSize()
  local cfg = mdw.config
  local newWidth

  if side == "left" then
    newWidth = splitterX + cfg.dockSplitterWidth
  else
    newWidth = winW - splitterX
  end

  newWidth = mdw.clamp(newWidth, cfg.minDockWidth, cfg.maxDockWidth)
  mdw.applyDockWidth(side, newWidth)
end

function mdw.applyDockWidth(side, newWidth)
  local cfg = mdw.config

  if side == "left" then
    cfg.leftDockWidth = newWidth
    setBorderLeft(newWidth)
    mdw.leftDock:resize(newWidth - cfg.dockSplitterWidth, nil)
    if mdw.leftDockHighlight then
      mdw.leftDockHighlight:resize(newWidth - cfg.dockSplitterWidth, nil)
    end
    mdw.leftSplitter:move(newWidth - cfg.dockSplitterWidth, nil)
  else
    cfg.rightDockWidth = newWidth
    setBorderRight(newWidth)
    mdw.rightDock:resize(newWidth - cfg.dockSplitterWidth, nil)
    mdw.rightDock:move(-newWidth + cfg.dockSplitterWidth, nil)
    if mdw.rightDockHighlight then
      mdw.rightDockHighlight:resize(newWidth - cfg.dockSplitterWidth, nil)
      mdw.rightDockHighlight:move(-newWidth + cfg.dockSplitterWidth, nil)
    end
    mdw.rightSplitter:move(-newWidth, nil)
  end

  -- Header spans full width, no repositioning needed

  -- Update prompt bar position and width
  local winW = getMainWindowSize()
  if mdw.promptBarContainer then
    local promptBarWidth = winW - cfg.leftDockWidth - cfg.rightDockWidth
    local consoleWidth = promptBarWidth - cfg.contentPaddingLeft
    mdw.promptBarContainer:move(cfg.leftDockWidth, nil)
    mdw.promptBarContainer:resize(promptBarWidth, nil)
    if mdw.promptBar and mdw.promptBar.setWrap then
      mdw.promptBar:resize(consoleWidth, nil)
      mdw.promptBar:setWrap(mdw.calculateWrap(consoleWidth))
    end
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
-- LAYOUT PERSISTENCE
-- Save and restore widget layouts across profile reloads.
---------------------------------------------------------------------------

--- Save the current layout to file.
-- Captures dock widths, visibility, and all widget positions/sizes.
function mdw.saveLayout()
  local layout = {
    version = 1,
    docks = {
      leftWidth = mdw.config.leftDockWidth,
      rightWidth = mdw.config.rightDockWidth,
      leftVisible = mdw.visibility.leftSidebar,
      rightVisible = mdw.visibility.rightSidebar,
      promptBarVisible = mdw.visibility.promptBar,
    },
    widgets = {},
  }

  for name, widget in pairs(mdw.widgets) do
    -- Use originalDock if widget was docked to a hidden sidebar
    local dockSide = widget.docked or widget.originalDock

    layout.widgets[name] = {
      dock = dockSide,
      row = widget.row,
      rowPosition = widget.rowPosition,
      subRow = widget.subRow or 0,
      widthRatio = widget.widthRatio,
      x = widget.container:get_x(),
      y = widget.container:get_y(),
      width = widget.container:get_width(),
      height = widget.container:get_height(),
      visible = widget.visible ~= false,
    }
    -- Save active tab for tabbed widgets
    if widget.isTabbed then
      layout.widgets[name].activeTab = widget:getActiveTab()
    end
  end

  table.save(mdw.layoutFile, layout)
  mdw.debugEcho("Layout saved to " .. mdw.layoutFile)
end

function mdw.loadLayout()
  if not io.exists(mdw.layoutFile) then
    mdw.debugEcho("No saved layout found")
    return false
  end

  local layout = {}
  table.load(mdw.layoutFile, layout)

  if not layout.version then
    mdw.debugEcho("Invalid layout file")
    return false
  end

  -- Apply dock settings
  if layout.docks then
    mdw.config.leftDockWidth = layout.docks.leftWidth or mdw.config.leftDockWidth
    mdw.config.rightDockWidth = layout.docks.rightWidth or mdw.config.rightDockWidth
    -- Store visibility for application after UI is created
    if layout.docks.leftVisible ~= nil then
      mdw.visibility.leftSidebar = layout.docks.leftVisible
    end
    if layout.docks.rightVisible ~= nil then
      mdw.visibility.rightSidebar = layout.docks.rightVisible
    end
    if layout.docks.promptBarVisible ~= nil then
      mdw.visibility.promptBar = layout.docks.promptBarVisible
    end
  end

  -- Store widget layouts for application during widget creation
  mdw.pendingLayouts = layout.widgets or {}

  mdw.debugEcho("Layout loaded from " .. mdw.layoutFile)
  return true
end

-- Call this and then reload the profile to get fresh default layouts.
function mdw.clearLayout()
  if io.exists(mdw.layoutFile) then
    os.remove(mdw.layoutFile)
    mdw.echo("Layout file deleted: " .. mdw.layoutFile)
    mdw.echo("Reload profile to apply default layout")
  else
    mdw.echo("No layout file to delete")
  end
  mdw.pendingLayouts = {}
end

function mdw.showLayout()
  if not io.exists(mdw.layoutFile) then
    mdw.echo("No saved layout file exists")
    return
  end

  local layout = {}
  table.load(mdw.layoutFile, layout)

  mdw.echo("=== Saved Layout ===")
  mdw.echo("File: " .. mdw.layoutFile)
  mdw.echo("Version: " .. tostring(layout.version))

  if layout.docks then
    mdw.echo("Docks:")
    mdw.echo("  Left width: " .. tostring(layout.docks.leftWidth))
    mdw.echo("  Right width: " .. tostring(layout.docks.rightWidth))
    mdw.echo("  Left visible: " .. tostring(layout.docks.leftVisible))
    mdw.echo("  Right visible: " .. tostring(layout.docks.rightVisible))
    mdw.echo("  Prompt bar visible: " .. tostring(layout.docks.promptBarVisible))
  end

  if layout.widgets then
    mdw.echo("Saved Widgets:")
    for name, w in pairs(layout.widgets) do
      local dockStr = w.dock or "floating"
      local visStr = w.visible and "visible" or "hidden"
      mdw.echo(string.format("  %s: dock=%s, row=%s, visible=%s",
        name, dockStr, tostring(w.row), visStr))
    end
  end
end

function mdw.showWidgets()
  mdw.echo("=== Current Widgets ===")
  mdw.echo("Visibility: left=" .. tostring(mdw.visibility.leftSidebar) ..
           ", right=" .. tostring(mdw.visibility.rightSidebar))

  local count = 0
  for name, w in pairs(mdw.widgets) do
    count = count + 1
    local dockStr = w.docked or "floating"
    local visStr = (w.visible ~= false) and "visible" or "hidden"
    mdw.echo(string.format("  %s: dock=%s, row=%s, rowPos=%s, subRow=%s, visible=%s",
      name, dockStr, tostring(w.row), tostring(w.rowPosition), tostring(w.subRow or 0), visStr))
  end

  if count == 0 then
    mdw.echo("  (no widgets registered)")
  end
end

---------------------------------------------------------------------------
-- LIFECYCLE MANAGEMENT
-- Handles setup, teardown, and Mudlet events.
---------------------------------------------------------------------------

function mdw.setup()
  mdw.echo("Setting up UI...")

  -- Load saved layout first (sets dock widths and pendingLayouts)
  mdw.loadLayout()

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

function mdw.teardown()
  mdw.echo("Cleaning up UI...")

  mdw.destroyAllElements()

  -- Clear userWidgets so they re-register fresh on reload
  mdw.userWidgets = {}

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

  -- Always save layout before uninstall (for updates and full uninstall)
  mdw.saveLayout()

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
    mdw.rightDock:move(-cfg.rightDockWidth + cfg.dockSplitterWidth, cfg.headerHeight)
    mdw.rightDock:resize(nil, sidebarHeight)
    if mdw.rightDockHighlight then
      mdw.rightDockHighlight:move(-cfg.rightDockWidth + cfg.dockSplitterWidth, cfg.headerHeight)
      mdw.rightDockHighlight:resize(nil, sidebarHeight)
    end
    mdw.rightSplitter:move(-cfg.rightDockWidth, cfg.headerHeight)
    mdw.rightSplitter:resize(nil, sidebarHeight)
  end

  -- Header spans full width, no resize needed

  -- Update prompt bar width
  if mdw.promptBarContainer then
    local promptBarWidth = winW - cfg.leftDockWidth - cfg.rightDockWidth
    local consoleWidth = promptBarWidth - cfg.contentPaddingLeft
    mdw.promptBarContainer:resize(promptBarWidth, nil)
    if mdw.promptBar and mdw.promptBar.setWrap then
      mdw.promptBar:resize(consoleWidth, nil)
      mdw.promptBar:setWrap(mdw.calculateWrap(consoleWidth))
    end
    if mdw.promptSeparator then
      mdw.promptSeparator:resize(promptBarWidth, nil)
    end
  end

  -- Reorganize widgets
  if mdw.reorganizeDock then
    mdw.reorganizeDock("left")
    mdw.reorganizeDock("right")
  end

end

---------------------------------------------------------------------------
-- EVENT HANDLER REGISTRATION
---------------------------------------------------------------------------

mdw.registerHandler("sysInstallPackage", "install", "mdw.onInstall")
mdw.registerHandler("sysUninstallPackage", "uninstall", "mdw.onUninstall")
mdw.registerHandler("sysLoadEvent", "profileLoad", "mdw.onProfileLoad")
mdw.registerHandler("sysWindowResizeEvent", "windowResize", "mdw.onWindowResize")
mdw.registerHandler("sysExitEvent", "saveLayout", "mdw.saveLayout")
