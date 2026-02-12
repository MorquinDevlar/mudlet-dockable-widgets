--[[
  MDW_Helpers.lua
  Runtime helper functions for MDW (Mudlet Dockable Widgets).

  Contains all utility functions, lifecycle helpers, widget class helpers,
  and style generation. Separated from MDW_Config.lua so that Config
  remains a static-only data declaration file.

  Dependencies: MDW_Config.lua must be loaded first (provides mdw table and config)
]]

---------------------------------------------------------------------------
-- STYLE GENERATION
-- Pre-built stylesheets for consistency across components.
-- Why: Centralizing styles prevents duplication and ensures visual consistency.
-- Changes to appearance only need to happen in one place.
---------------------------------------------------------------------------

--- Generate all stylesheets from current config.
-- Why: Called after config changes to regenerate styles with new values.
function mdw.buildStyles()
	local cfg = mdw.config

	mdw.styles.sidebar = string.format([[
    background-color: %s;
  ]], cfg.sidebarBackground)

	mdw.styles.splitter = string.format([[
    QLabel { background-color: %s; }
    QLabel:hover { background-color: %s; }
  ]], cfg.splitterColor, cfg.splitterHoverColor)

	-- Directional resize border styles: transparent with visible border on widget-facing side
	local bw = cfg.resizeBorderWidth
	local bc = cfg.splitterColor
	local bch = cfg.splitterHoverColor
	mdw.styles.resizeLeft = string.format([[
    QLabel { background-color: transparent; border-right: %dpx solid %s; }
    QLabel:hover { background-color: transparent; border-right: %dpx solid %s; }
  ]], bw, bc, bw, bch)
	mdw.styles.resizeRight = string.format([[
    QLabel { background-color: transparent; border-left: %dpx solid %s; }
    QLabel:hover { background-color: transparent; border-left: %dpx solid %s; }
  ]], bw, bc, bw, bch)
	mdw.styles.resizeTop = string.format([[
    QLabel { background-color: transparent; border-bottom: %dpx solid %s; }
    QLabel:hover { background-color: transparent; border-bottom: %dpx solid %s; }
  ]], bw, bc, bw, bch)
	mdw.styles.resizeBottom = string.format([[
    QLabel { background-color: transparent; border-top: %dpx solid %s; }
    QLabel:hover { background-color: transparent; border-top: %dpx solid %s; }
  ]], bw, bc, bw, bch)

	local titlePadLeft = cfg.titleButtonPadding + 2 * cfg.titleButtonSize + (cfg.titleButtonGap or 4)
	local titlePadRight = cfg.closeButtonPadding + cfg.titleButtonSize
	mdw.styles.titleBar = string.format([[
    background-color: %s;
    qproperty-alignment: 'AlignCenter';
    font-family: '%s';
    font-size: %dpx;
    padding-left: %dpx;
    padding-right: %dpx;
  ]], cfg.headerBackground, cfg.fontFamily, cfg.widgetHeaderFontSize,
		titlePadLeft, titlePadRight)

	mdw.styles.widgetContent = string.format([[
    background-color: %s;
    font-family: '%s';
    font-size: %dpx;
  ]], cfg.widgetBackground, cfg.fontFamily, cfg.fontSize)

	mdw.styles.headerPane = string.format([[
    background-color: %s;
    font-family: '%s';
    font-size: %dpx;
  ]], cfg.sidebarBackground, cfg.fontFamily, cfg.headerMenuFontSize)

	mdw.styles.promptBar = string.format([[
    background-color: %s;
    font-family: '%s';
    font-size: %dpx;
    padding-left: %dpx;
  ]], cfg.sidebarBackground, cfg.fontFamily, cfg.fontSize, cfg.contentPaddingLeft)

	mdw.styles.headerButton = string.format([[
    QLabel {
      background-color: transparent;
      font-family: '%s';
      font-size: %dpx;
      padding-left: %dpx;
      border: 2px solid transparent;
    }
    QLabel:hover {
      background-color: rgb(51,51,51);
      border: 2px solid rgb(85,85,85);
    }
  ]], cfg.fontFamily, cfg.headerMenuFontSize, cfg.menuPaddingLeft)

	-- Active state for header buttons when their menu is open
	mdw.styles.headerButtonActive = string.format([[
    QLabel {
      background-color: rgb(51,51,51);
      font-family: '%s';
      font-size: %dpx;
      padding-left: %dpx;
      border: 2px solid rgb(85,85,85);
    }
  ]], cfg.fontFamily, cfg.headerMenuFontSize, cfg.menuPaddingLeft)

	mdw.styles.menuItem = string.format([[
    QLabel {
      background-color: transparent;
      font-family: '%s';
      font-size: %dpx;
      padding-left: %dpx;
    }
  ]], cfg.fontFamily, cfg.headerMenuFontSize, cfg.menuPaddingLeft)

	mdw.styles.menuBackground = [[
    background-color: rgb(51,51,51);
    border: 2px solid rgb(85,85,85);
  ]]

	mdw.styles.dropIndicator = string.format([[
    background-color: %s;
  ]], cfg.dropIndicatorColor)

	mdw.styles.dockHighlight = string.format([[
    background-color: rgba(106,91,58,0.4);
    outline: 2px dashed %s;
  ]], cfg.dropIndicatorColor)

	mdw.styles.separatorLine = string.format([[
    background-color: %s;
  ]], cfg.splitterColor)

	mdw.styles.resizableSeparator = string.format([[
    QLabel { background-color: %s; }
    QLabel:hover { background-color: %s; }
  ]], cfg.splitterColor, cfg.splitterHoverColor)

	mdw.styles.tabBar = string.format([[
    background-color: %s;
  ]], cfg.headerBackground)

	mdw.styles.tabActive = string.format([[
    background-color: %s;
    qproperty-alignment: 'AlignCenter';
    font-family: '%s';
    font-size: %dpx;
    padding-left: %dpx;
    padding-right: %dpx;
  ]], cfg.tabActiveBackground, cfg.fontFamily, cfg.tabFontSize, cfg.tabPadding, cfg.tabPadding)

	mdw.styles.tabInactive = string.format([[
    background-color: %s;
    qproperty-alignment: 'AlignCenter';
    font-family: '%s';
    font-size: %dpx;
    padding-left: %dpx;
    padding-right: %dpx;
  ]], cfg.tabInactiveBackground, cfg.fontFamily, cfg.tabFontSize, cfg.tabPadding, cfg.tabPadding)

	mdw.styles.tabDragging = string.format([[
    background-color: %s;
    qproperty-alignment: 'AlignCenter';
    font-family: '%s';
    font-size: %dpx;
    padding-left: %dpx;
    padding-right: %dpx;
    opacity: 0.6;
  ]], cfg.tabActiveBackground, cfg.fontFamily, cfg.tabFontSize, cfg.tabPadding, cfg.tabPadding)

	mdw.styles.titleButtonClose = string.format([[
    QLabel {
      background-color: transparent;
      qproperty-alignment: 'AlignCenter';
      font-family: '%s';
      font-size: %dpx;
    }
    QLabel:hover { background-color: rgba(180,60,60,0.4); }
  ]], cfg.fontFamily, cfg.widgetHeaderFontSize)

end

---------------------------------------------------------------------------
-- DEBUG
---------------------------------------------------------------------------

--- Output debug message if debug mode is enabled.
-- Why: Conditional debug output helps diagnose drag/drop issues without
-- cluttering normal operation. Set mdw.debugMode = true to enable.
-- Supports format strings: mdw.debugEcho("value=%s, count=%d", name, count)
function mdw.debugEcho(msg, ...)
	if mdw.debugMode then
		local formatted = select("#", ...) > 0 and string.format(msg, ...) or msg
		cecho("<dim_gray>[DEBUG] " .. formatted .. "\n")
	end
end

---------------------------------------------------------------------------
-- GENERAL UTILITIES
-- Shared utilities used across all UI modules.
---------------------------------------------------------------------------

function mdw.echo(msg)
	debugc("[MDW] " .. msg)
end

--- Clamp a value between min and max bounds.
-- Why: Prevents dimension values from exceeding valid ranges,
-- which would cause layout corruption or negative coordinates.
function mdw.clamp(value, min, max)
	return math.max(min, math.min(max, value))
end

--- Calculate wrap value for a MiniConsole based on pixel width.
-- Uses calcFontSize to get exact character width for the configured font.
function mdw.calculateWrap(pixelWidth)
	local cfg = mdw.config
	local charWidth, _ = calcFontSize(cfg.fontSize, cfg.fontFamily)
	if charWidth and charWidth > 0 then
		return math.floor(pixelWidth / charWidth)
	end
	-- Fallback: assume ~7px per character for typical monospace fonts
	return math.floor(pixelWidth / 7)
end

--- Check if a sidebar is currently visible.
-- Why: Centralizes the visibility check that appears in multiple places,
-- making the code more readable and the logic easier to update.
function mdw.isSidebarVisible(side)
	if side == "left" then return mdw.visibility.leftSidebar end
	if side == "right" then return mdw.visibility.rightSidebar end
	return true
end

--- Re-apply all Mudlet borders based on current visibility and dock sizes.
-- Why: Centralizes the border-setting logic that was duplicated in createDocks,
-- onConnection, toggleSidebar, and togglePromptBar.
function mdw.applyBorders()
	local cfg = mdw.config
	local leftWidth = mdw.visibility.leftSidebar and cfg.leftDockWidth or 0
	local rightWidth = mdw.visibility.rightSidebar and cfg.rightDockWidth or 0
	local bottomHeight = mdw.visibility.promptBar and cfg.promptBarHeight or 0

	setBorderLeft(leftWidth > 0 and leftWidth + cfg.dockGap or 0)
	setBorderRight(rightWidth > 0 and rightWidth + cfg.dockGap or 0)
	setBorderTop(cfg.headerHeight)
	setBorderBottom(bottomHeight > 0 and bottomHeight + cfg.dockGap or 0)
end

--- Render a widget's title with ellipsis truncation.
-- Measures available width between buttons and truncates with "..." if needed.
-- Call on creation, resize, and setTitle.
function mdw.renderWidgetTitle(widget)
	if not widget.titleBar or not widget.title then return end
	local cfg = mdw.config
	local cw = widget.container:get_width()
	local leftPad = cfg.titleButtonPadding + 2 * cfg.titleButtonSize + (cfg.titleButtonGap or 4)
	local rightPad = cfg.closeButtonPadding + cfg.titleButtonSize
	local availWidth = cw - leftPad - rightPad
	-- Estimate character width for monospace font (~60% of font size)
	local charWidth = cfg.widgetHeaderFontSize * 0.6
	local maxChars = math.floor(availWidth / charWidth)
	local title = widget.title
	if #title > maxChars and maxChars > 3 then
		title = title:sub(1, maxChars - 3) .. "..."
	end
	widget.titleBar:decho("<" .. cfg.headerTextColor .. ">" .. title)
end

--- Show appropriate content for a widget (mapper or default content).
-- Why: When a widget has an embedded mapper, the default content is hidden.
-- This helper ensures the correct element is shown/hidden when the widget becomes visible.
function mdw.showWidgetContent(widget)
	if widget.mapper then
		widget.mapper:show()
		if widget.content then widget.content:hide() end
	elseif widget.content then
		widget.content:show()
	end
end

---------------------------------------------------------------------------
-- Z-ORDER MANAGEMENT
-- Centralized z-order control. All raise() calls are consolidated here
-- to prevent whack-a-mole z-order bugs across scattered call sites.
---------------------------------------------------------------------------

--- Safely raise a UI element, silently ignoring errors.
local function safeRaise(element)
	pcall(function() element:raise() end)
end

--- Raise all elements of a single widget in the correct order.
-- Why: Geyser doesn't raise children with their container. Each child
-- element must be raised individually, and the order matters for
-- clickability (resize handles above content, corners above edges, etc.).
function mdw.raiseWidgetElements(widget)
	if not widget or not widget.container then return end

	safeRaise(widget.container)
	if widget.contentBg then safeRaise(widget.contentBg) end
	if widget.titleBar then safeRaise(widget.titleBar) end
	if widget.fillButton then safeRaise(widget.fillButton) end
	if widget.lockButton then safeRaise(widget.lockButton) end
	if widget.closeButton then safeRaise(widget.closeButton) end

	if widget.isTabbed then
		if widget.tabBar then safeRaise(widget.tabBar) end
		for _, tabObj in ipairs(widget.tabObjects or {}) do
			if tabObj.button then safeRaise(tabObj.button) end
		end
		local activeTab = widget.tabObjects[widget.activeTabIndex]
		if activeTab and activeTab.console then
			safeRaise(activeTab.console)
		end
	else
		if widget.content then safeRaise(widget.content) end
		if widget.mapper then safeRaise(widget.mapper) end
	end

	-- Floating: raise external resize handles above container
	if not widget.docked then
		if widget.resizeLeft then safeRaise(widget.resizeLeft) end
		if widget.resizeRight then safeRaise(widget.resizeRight) end
		if widget.resizeTop then safeRaise(widget.resizeTop) end
		if widget.resizeBottom then safeRaise(widget.resizeBottom) end
		-- Corners above edges
		if widget.resizeTopLeft then safeRaise(widget.resizeTopLeft) end
		if widget.resizeTopRight then safeRaise(widget.resizeTopRight) end
		if widget.resizeBottomLeft then safeRaise(widget.resizeBottomLeft) end
		if widget.resizeBottomRight then safeRaise(widget.resizeBottomRight) end
	end

	-- Docked: bottom resize handle above content
	if widget.docked and widget.bottomResizeHandle then
		safeRaise(widget.bottomResizeHandle)
	end
end

--- Reset the entire UI z-order by raising all elements in layer order.
-- Why: Replaces ~37 scattered raise() calls with a single source of truth.
-- Called after state changes (dock/undock, drag end, reorganize, menu open/close,
-- sidebar toggle). NOT called on every mouse move during drag — use
-- raiseWidgetElements() for that.
-- Note: Iterates all widgets twice (docked + floating). Avoid calling in
-- tight loops or per-frame handlers.
function mdw.applyZOrder()
	-- Layer 1: Background elements (dock bgs, header, separators, dock edge splitters)
	-- These are at bottom from creation order — skip explicit raising

	-- Layer 2: Dock highlights
	if mdw.leftDockHighlight then safeRaise(mdw.leftDockHighlight) end
	if mdw.rightDockHighlight then safeRaise(mdw.rightDockHighlight) end

	-- Layer 3: Drop indicators
	if mdw.leftDropIndicator then safeRaise(mdw.leftDropIndicator) end
	if mdw.rightDropIndicator then safeRaise(mdw.rightDropIndicator) end
	if mdw.verticalDropIndicator then safeRaise(mdw.verticalDropIndicator) end

	-- Layer 4: Row splitters
	for _, splitter in pairs(mdw.rowSplitters) do
		safeRaise(splitter)
	end

	-- Layer 5: Docked widgets
	for _, widget in pairs(mdw.widgets) do
		if widget.docked and not (mdw.drag.active and mdw.drag.widget == widget) then
			mdw.raiseWidgetElements(widget)
		end
	end

	-- Layer 6: Floating widgets (skip drag widget)
	for _, widget in pairs(mdw.widgets) do
		if not widget.docked and not (mdw.drag.active and mdw.drag.widget == widget) then
			mdw.raiseWidgetElements(widget)
		end
	end

	-- Layer 7: Dragged widget
	if mdw.drag.active and mdw.drag.widget then
		mdw.raiseWidgetElements(mdw.drag.widget)
	end

	-- Layer 8: Menus
	if mdw.menuOverlay then safeRaise(mdw.menuOverlay) end
	if mdw.menus.layoutOpen then
		if mdw.layoutMenuBg then safeRaise(mdw.layoutMenuBg) end
		for _, label in ipairs(mdw.layoutMenuLabels or {}) do
			safeRaise(label)
		end
	end
	if mdw.menus.widgetsOpen then
		if mdw.widgetsMenuBg then safeRaise(mdw.widgetsMenuBg) end
		for _, label in ipairs(mdw.widgetsMenuLabels or {}) do
			safeRaise(label)
		end
	end

	-- Layer 9: Prompt bar
	if mdw.promptBarContainer then safeRaise(mdw.promptBarContainer) end
	if mdw.promptBarBg then safeRaise(mdw.promptBarBg) end
	if mdw.promptBar then safeRaise(mdw.promptBar) end
end

---------------------------------------------------------------------------
-- TEXT TRUNCATION
-- Utilities for truncating formatted text while preserving color codes.
-- Used by overflow="ellipsis" mode to truncate long lines with "...".
---------------------------------------------------------------------------

--- Count visible characters in formatted text (excluding color codes).
function mdw.visibleLength(text, method)
	if method == "echo" then return #text end
	if method == "cecho" or method == "decho" then
		return #(text:gsub("<[^>]*>", ""))
	end
	if method == "hecho" then
		return #(text:gsub("#%x%x%x%x%x%x", ""):gsub("#r", ""))
	end
	return #text
end

--- Truncate a single line of formatted text to maxVisible visible chars.
-- Walks through text tracking format codes vs visible chars, cuts at
-- (maxVisible - 3) and appends "...".
function mdw.truncateLine(text, method, maxVisible)
	if maxVisible < 4 then return text end
	local visLen = mdw.visibleLength(text, method)
	if visLen <= maxVisible then return text end

	local cutAt = maxVisible - 3

	if method == "echo" then
		return text:sub(1, cutAt) .. "..."
	end

	if method == "cecho" or method == "decho" then
		local result = {}
		local n = 0
		local visCount = 0
		local i = 1
		local len = #text
		while i <= len and visCount < cutAt do
			if text:sub(i, i) == "<" then
				local j = text:find(">", i + 1, true)
				if j then
					n = n + 1
					result[n] = text:sub(i, j)
					i = j + 1
				else
					n = n + 1
					result[n] = text:sub(i, i)
					visCount = visCount + 1
					i = i + 1
				end
			else
				n = n + 1
				result[n] = text:sub(i, i)
				visCount = visCount + 1
				i = i + 1
			end
		end
		n = n + 1
		result[n] = "..."
		return table.concat(result)
	end

	if method == "hecho" then
		local result = {}
		local n = 0
		local visCount = 0
		local i = 1
		local len = #text
		while i <= len and visCount < cutAt do
			if text:sub(i, i) == "#" then
				if i + 6 <= len and text:sub(i + 1, i + 6):match("^%x%x%x%x%x%x$") then
					n = n + 1
					result[n] = text:sub(i, i + 6)
					i = i + 7
				elseif i + 1 <= len and text:sub(i + 1, i + 1) == "r" then
					n = n + 1
					result[n] = "#r"
					i = i + 2
				else
					n = n + 1
					result[n] = "#"
					visCount = visCount + 1
					i = i + 1
				end
			else
				n = n + 1
				result[n] = text:sub(i, i)
				visCount = visCount + 1
				i = i + 1
			end
		end
		n = n + 1
		result[n] = "..."
		return table.concat(result)
	end

	return text:sub(1, cutAt) .. "..."
end

--- Truncate formatted text line-by-line.
-- Splits on newlines, truncates each line independently, rejoins.
function mdw.truncateFormatted(text, method, maxChars)
	if not text or maxChars < 1 then return text end
	if not text:find("\n", 1, true) then
		return mdw.truncateLine(text, method, maxChars)
	end

	local result = {}
	local n = 0
	local start = 1
	while true do
		local nlPos = text:find("\n", start, true)
		if nlPos then
			n = n + 1
			result[n] = mdw.truncateLine(text:sub(start, nlPos - 1), method, maxChars)
			start = nlPos + 1
		else
			n = n + 1
			result[n] = mdw.truncateLine(text:sub(start), method, maxChars)
			break
		end
	end
	return table.concat(result, "\n")
end

---------------------------------------------------------------------------
-- ELEMENT/HANDLER LIFECYCLE
-- Tracking and cleanup for UI elements and event handlers.
---------------------------------------------------------------------------

--- Register a UI element for cleanup on package uninstall.
-- Why: Mudlet doesn't automatically clean up Geyser elements when
-- packages are removed, leading to orphaned UI and memory leaks.
function mdw.trackElement(element)
	mdw.elements[#mdw.elements + 1] = element
	return element
end

--- Register a named event handler for cleanup.
-- Why: Named handlers can accumulate if not properly cleaned up on
-- package reinstall, causing duplicate event processing.
function mdw.registerHandler(event, name, func)
	local handlerName = mdw.packageName .. "_" .. name
	registerNamedEventHandler(mdw.packageName, handlerName, event, func)
	mdw.handlers[handlerName] = true
end

-- Why: Essential for clean package uninstall to prevent orphaned handlers.
function mdw.killAllHandlers()
	for handlerName in pairs(mdw.handlers) do
		deleteNamedEventHandler(mdw.packageName, handlerName)
	end
	mdw.handlers = {}
end

--- Destroy all tracked UI elements.
-- Why: Ensures complete cleanup on uninstall, preventing visual artifacts
-- and memory leaks from orphaned Geyser elements.
function mdw.destroyAllElements()
	-- Destroy all row splitters first
	if mdw.destroyAllRowSplitters then
		mdw.destroyAllRowSplitters()
	end

	-- Delete all tracked elements
	for _, element in ipairs(mdw.elements) do
		if element then
			pcall(function()
				if element.hide then element:hide() end
			end)
			pcall(function()
				if element.name then
					deleteLabel(element.name)
				end
			end)
		end
	end

	mdw.elements = {}
	mdw.widgets = {}
end

---------------------------------------------------------------------------
-- WIDGET CLASS HELPERS
-- Shared behavior for Widget and TabbedWidget classes.
-- Why: Both classes have nearly identical dock/visibility/position methods.
-- These helpers centralize the logic to avoid duplication.
---------------------------------------------------------------------------

--- Dock a widget class instance to a sidebar.
function mdw.dockWidgetClass(widget, side, row)
	assert(side == "left" or side == "right", "dock side must be 'left' or 'right'")

	widget.docked = side

	if row then
		widget.row = row
		widget.rowPosition = 0
		widget.subRow = 0
	else
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
	mdw.updateDockButtonVisibility(widget)
	mdw.reorganizeDock(side)
end

--- Undock a widget class instance (make it floating).
function mdw.undockWidgetClass(widget, x, y)
	local previousDock = widget.docked

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

	if x and y then
		widget.container:move(x, y)
	end

	mdw.showResizeHandles(widget)
	mdw.updateResizeBorders(widget)

	if previousDock then
		mdw.reorganizeDock(previousDock)
	end

	mdw.saveLayout()
end

--- Show a widget class instance.
function mdw.showWidgetClass(widget, showContentFunc)
	widget.visible = true
	widget.container:show()

	if showContentFunc then
		showContentFunc()
	else
		mdw.showWidgetContent(widget)
	end

	if widget.docked then
		mdw.hideResizeHandles(widget)
		mdw.reorganizeDock(widget.docked)
	else
		mdw.showResizeHandles(widget)
	end

	mdw.updateDockButtonVisibility(widget)

	if mdw.updateWidgetsMenuState then
		mdw.updateWidgetsMenuState()
	end
end

--- Hide a widget class instance.
function mdw.hideWidgetClass(widget)
	widget.visible = false
	widget.container:hide()
	mdw.hideResizeHandles(widget)

	if widget.docked then
		mdw.reorganizeDock(widget.docked)
	end

	if mdw.updateWidgetsMenuState then
		mdw.updateWidgetsMenuState()
	end

	if widget.onClose then
		widget.onClose(widget)
	end
end

--- Resize a widget class instance.
function mdw.resizeWidgetClass(widget, width, height, resizeContentFunc)
	widget.container:resize(width, height)
	local actualWidth = width or widget.container:get_width()
	local actualHeight = height or widget.container:get_height()
	resizeContentFunc(widget, actualWidth, actualHeight)

	if widget.docked then
		mdw.reorganizeDock(widget.docked)
	else
		mdw.updateResizeBorders(widget)
	end
end

--- Move a widget class instance (floating only).
function mdw.moveWidgetClass(widget, x, y)
	if widget.docked then
		mdw.debugEcho("Cannot move docked widget - undock it first")
		return
	end

	widget.container:move(x, y)
	mdw.updateResizeBorders(widget)
end

--- Destroy a widget class instance.
function mdw.destroyWidgetClass(widget)
	widget:hide()

	mdw.widgets[widget.name] = nil

	if widget.fillButton then widget.fillButton:hide() end
	if widget.lockButton then widget.lockButton:hide() end
	if widget.closeButton then widget.closeButton:hide() end
	if widget.resizeLeft then widget.resizeLeft:hide() end
	if widget.resizeRight then widget.resizeRight:hide() end
	if widget.resizeTop then widget.resizeTop:hide() end
	if widget.resizeBottom then widget.resizeBottom:hide() end
	if widget.resizeTopLeft then widget.resizeTopLeft:hide() end
	if widget.resizeTopRight then widget.resizeTopRight:hide() end
	if widget.resizeBottomLeft then widget.resizeBottomLeft:hide() end
	if widget.resizeBottomRight then widget.resizeBottomRight:hide() end
	if widget.mapper then widget.mapper:hide() end

	widget.container:hide()

	if mdw.rebuildWidgetsMenu then
		mdw.rebuildWidgetsMenu()
	end
end

--- Show/hide dock-only buttons (FILL, LOCK) based on dock state.
function mdw.updateDockButtonVisibility(widget)
	if widget.docked then
		if widget.fillButton then
			widget.fillButton:show()
			mdw.updateFillButtonText(widget)
		end
		if widget.lockButton then
			widget.lockButton:show()
			mdw.updateLockButtonText(widget)
		end
	else
		if widget.fillButton then widget.fillButton:hide() end
		if widget.lockButton then widget.lockButton:hide() end
	end
end

--- Set fill state for a widget (shared by Widget and TabbedWidget).
function mdw.setFillClass(widget, enabled)
	if enabled and not widget.fill then
		widget._preFillHeight = widget.container:get_height()
	elseif not enabled and widget.fill and widget._preFillHeight then
		widget.container:resize(nil, widget._preFillHeight)
		mdw.resizeWidgetContent(widget, widget.container:get_width(), widget._preFillHeight)
		widget._preFillHeight = nil
	end
	widget.fill = enabled
	mdw.updateFillButtonText(widget)
	if widget.docked then
		mdw.reorganizeDock(widget.docked)
		mdw.saveLayout()
	end
end

--- Set width lock state for a widget (shared by Widget and TabbedWidget).
function mdw.setWidthLockedClass(widget, enabled)
	widget.widthLocked = enabled
	if enabled then
		widget.lockedWidth = widget.container:get_width()
	else
		widget.lockedWidth = nil
	end
	mdw.updateLockButtonText(widget)
	mdw.saveLayout()
end

--- Apply pending layout to a widget during creation.
-- Why: Widget and TabbedWidget both need identical layout restoration logic.
-- Extracting to a shared helper prevents duplication and ensures consistency.
function mdw.applyPendingLayout(widget)
	if not mdw.pendingLayouts or not mdw.pendingLayouts[widget.name] then
		return false, nil
	end

	local saved = mdw.pendingLayouts[widget.name]

	-- Apply size first
	if saved.width and saved.height then
		widget:resize(saved.width, saved.height)
	end

	-- Apply dock state - but check if sidebar is visible
	if saved.dock then
		local sidebarVisible = mdw.isSidebarVisible(saved.dock)

		if sidebarVisible then
			-- Sidebar is visible, dock normally
			widget.row = saved.row
			widget.rowPosition = saved.rowPosition
			widget.subRow = saved.subRow or 0
			widget.widthRatio = saved.widthRatio
			widget.fill = saved.fill or false
			if widget.fill then
				widget._preFillHeight = saved.height
			end
			widget.widthLocked = saved.widthLocked or false
			widget.lockedWidth = saved.lockedWidth
			widget.docked = saved.dock
			mdw.hideResizeHandles(widget)
			mdw.updateDockButtonVisibility(widget)
			mdw.reorganizeDock(saved.dock)
		else
			-- Sidebar is hidden, remember the dock and hide the widget
			widget.originalDock = saved.dock
			widget.row = saved.row
			widget.rowPosition = saved.rowPosition
			widget.subRow = saved.subRow or 0
			widget.widthRatio = saved.widthRatio
			widget.fill = saved.fill or false
			if widget.fill then
				widget._preFillHeight = saved.height
			end
			widget.widthLocked = saved.widthLocked or false
			widget.lockedWidth = saved.lockedWidth
			widget.docked = nil
			widget:hide()
		end
	elseif saved.x and saved.y then
		widget:undock(saved.x, saved.y)
	end

	-- Apply visibility (only if not already hidden due to hidden sidebar)
	if saved.visible == false and widget.visible ~= false then
		widget:hide()
	end

	mdw.pendingLayouts[widget.name] = nil
	return true, saved
end

---------------------------------------------------------------------------
-- DOCK CONFIGURATION
---------------------------------------------------------------------------

--- Get configuration values for a specific dock side.
-- Why: Reduces repetitive if/else blocks throughout the codebase when
-- operations differ only by which dock side they target.
-- NOTE: Returns a new table each call. Not suitable for hot paths;
-- cache the result if calling repeatedly within the same operation.
function mdw.getDockConfig(side)
	local cfg = mdw.config
	local winW = getMainWindowSize()

	local totalMargin = cfg.widgetMargin * 2 -- margin on both sides

	if side == "left" then
		return {
			dock = mdw.leftDock,
			dockHighlight = mdw.leftDockHighlight,
			splitter = mdw.leftSplitter,
			dropIndicator = mdw.leftDropIndicator,
			width = cfg.leftDockWidth,
			fullWidgetWidth = cfg.leftDockWidth - totalMargin - cfg.dockSplitterWidth,
			xPos = cfg.widgetMargin,
			visibilityKey = "leftSidebar",
		}
	else
		return {
			dock = mdw.rightDock,
			dockHighlight = mdw.rightDockHighlight,
			splitter = mdw.rightSplitter,
			dropIndicator = mdw.rightDropIndicator,
			width = cfg.rightDockWidth,
			fullWidgetWidth = cfg.rightDockWidth - totalMargin - cfg.dockSplitterWidth,
			xPos = winW - cfg.rightDockWidth + cfg.dockSplitterWidth + cfg.widgetMargin,
			visibilityKey = "rightSidebar",
		}
	end
end

---------------------------------------------------------------------------
-- Build styles on load
---------------------------------------------------------------------------

mdw.buildStyles()
