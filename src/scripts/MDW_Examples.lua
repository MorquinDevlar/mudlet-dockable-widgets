--[[
  MDW_Examples.lua
  Example widgets demonstrating MDW features.

  This file creates sample widgets to showcase the different widget types
  and features available in MDW. Users can use these as templates for
  creating their own widgets.

  To disable these examples, either:
  1. Remove this file from the package
  2. Comment out the mdw.registerWidgets() call at the bottom
  3. Set mdw.loadExamples = false before the package loads

  Dependencies: MDW_Config.lua, MDW_Helpers.lua, MDW_Init.lua, MDW_WidgetCore.lua,
                MDW_Widget.lua, MDW_TabbedWidget.lua
]]

---------------------------------------------------------------------------
-- EXAMPLE WIDGETS
---------------------------------------------------------------------------

--- Create all example widgets.
-- Called during mdw.setup() via mdw.registerWidgets().
local function createExampleWidgets()
  ---------------------------------------------------------------------------
  -- BASIC WIDGETS (Left Dock)
  ---------------------------------------------------------------------------

  -- Simple text widget for displaying items/inventory
  local items = mdw.Widget:new({
    name = "Items",
    title = "Items",
    dock = "left",
    row = 0,
  })
  items:clear()
  items:cecho("<white>Example Items Widget\n")
  items:cecho("<gray>-------------------\n")
  items:echo("Use widget:echo() to display text\n")
  items:cecho("<green>Use widget:cecho() for colors\n")
  items:decho("<255,200,100>Use widget:decho() for RGB\n")

  -- Another simple widget for status effects
  local affects = mdw.Widget:new({
    name = "Affects",
    title = "Affects",
    dock = "left",
    row = 1,
  })
  affects:clear()
  affects:cecho("<white>Example Affects Widget\n")
  affects:cecho("<gray>---------------------\n")
  affects:cecho("<cyan>Sanctuary<reset> - 5 minutes\n")
  affects:cecho("<yellow>Haste<reset> - 3 minutes\n")
  affects:cecho("<magenta>Shield<reset> - 10 minutes\n")

  ---------------------------------------------------------------------------
  -- MAPPER WIDGET (Right Dock)
  ---------------------------------------------------------------------------

  -- Widget with embedded Mudlet mapper
  local map = mdw.Widget:new({
    name = "Map",
    title = "Map",
    dock = "right",
    row = 0,
  })
  map:embedMapper()

  ---------------------------------------------------------------------------
  -- TABBED WIDGET (Right Dock)
  ---------------------------------------------------------------------------

  -- Tabbed widget for communications
  -- The "All" tab receives copies of messages sent to other tabs
  local comm = mdw.TabbedWidget:new({
    name = "Comm",
    title = "Communications",
    tabs = {"All", "Room", "Tell", "Chat"},
    allTab = "All",
    activeTab = "All",
    dock = "right",
    row = 1,
  })

  -- Add some example content to demonstrate the tabbed widget
  comm:cechoTo("All", "<gray>--- Communications Widget ---\n")
  comm:cechoTo("All", "<dim_gray>Messages sent to other tabs appear here too.\n\n")

  comm:cechoTo("Room", "<white>Someone says: Welcome to MDW!\n")
  comm:cechoTo("Room", "<white>Someone says: This is the Room tab.\n")

  comm:cechoTo("Tell", "<magenta>Bob tells you: Hey there!\n")
  comm:cechoTo("Tell", "<magenta>You tell Bob: Hello!\n")

  comm:cechoTo("Chat", "<cyan>[Chat] Player1: Hello everyone! This is a longer message to demonstrate that word wrap is handled automatically when text exceeds the widget width.\n")
  comm:cechoTo("Chat", "<cyan>[Chat] Player2: Welcome to the game!\n")

  ---------------------------------------------------------------------------
  -- PROMPT BAR FALLBACK
  ---------------------------------------------------------------------------

  -- Show placeholder text if no prompt has been captured yet
  -- This will be replaced by the actual prompt when connected to a game
  if mdw.promptBar then
    mdw.setPromptCecho("<dim_gray>This is where your prompt will show")
  end
end

--[[
  ---------------------------------------------------------------------------
  PROMPT BAR USAGE GUIDE
  ---------------------------------------------------------------------------

  MDW includes a prompt trigger (MDW_PromptCapture) that automatically
  captures your MUD's prompt and displays it in the prompt bar.

  The trigger uses Mudlet's "prompt" detection, which works with most MUDs.
  If your prompt isn't being captured, you may need to:
  1. Disable the MDW_PromptCapture trigger
  2. Create your own trigger with a pattern matching your MUD's prompt
  3. Call mdw.capturePrompt() in your trigger script

  AVAILABLE FUNCTIONS:

  mdw.capturePrompt()
    - Captures current line with colors, displays in prompt bar, deletes from main
    - Call from a prompt trigger

  mdw.capturePrompt(false)
    - Same as above, but does NOT delete from main window

  mdw.setPrompt("<255,200,100>Custom text")
    - Set prompt bar text directly using decho format (RGB colors)

  mdw.setPromptCecho("<green>Custom <white>text")
    - Set prompt bar text directly using cecho format (named colors)

  mdw.clearPrompt()
    - Clear the prompt bar

  CUSTOM PROMPT EXAMPLE:

  -- Build a custom formatted prompt from GMCP data
  local hp = gmcp.Char.Vitals.hp or 100
  local maxHp = gmcp.Char.Vitals.maxHp or 100
  mdw.setPromptCecho(string.format("<green>HP: <white>%d/%d", hp, maxHp))
]]

---------------------------------------------------------------------------
-- REGISTRATION
---------------------------------------------------------------------------

-- Check if examples should be loaded (can be disabled by setting mdw.loadExamples = false)
mdw.loadExamples = mdw.loadExamples == nil and true or mdw.loadExamples

if mdw.loadExamples then
  mdw.registerWidgets(createExampleWidgets)
end
