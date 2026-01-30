# MDW - Mudlet Dockable Widgets

A draggable, dockable widget system for [Mudlet](https://www.mudlet.org/). Create customizable UI panels that can be freely positioned or docked to sidebars.

## Features

- **Draggable Widgets**: Drag widgets by their title bar to reposition them
- **Dockable Sidebars**: Dock widgets to left or right sidebars
- **Side-by-Side Docking**: Place multiple widgets in the same row
- **Resizable**: Resize docks and widgets interactively
- **Floating Mode**: Undock widgets to float freely over the main display
- **Tabbed Widgets**: Create widgets with multiple switchable tabs
- **Embedded Mapper**: Embed the Mudlet mapper in any widget
- **Easy API**: Simple object-oriented API for creating and managing widgets

## Installation

1. Download the latest `MDW.mpackage` file from the releases
2. In Mudlet, go to **Packages**
3. Click **Install new package** or **Install from file** depending on your version and select the downloaded `MDW.mpackage` file

## Example Widgets

MDW comes with example widgets to demonstrate its features. These are created automatically when the package loads:

| Widget | Dock | Description |
|--------|------|-------------|
| **Items** | Left | Simple text widget showing echo methods |
| **Affects** | Left | Example status effects display |
| **Map** | Right | Widget with embedded Mudlet mapper |
| **Comm** | Right | Tabbed widget with All/Room/Tell/Chat tabs |

The examples also include:
- **Prompt Bar**: Displays your MUD's prompt (captured via trigger)
- **MDW_PromptCapture Trigger**: Automatically captures prompts and displays them in the prompt bar

### Disabling Examples

To disable the example widgets, add this before MDW loads:

```lua
mdw = mdw or {}
mdw.loadExamples = false
```

Or remove/deactivate `MDW_Examples` from the package scripts.

## Prompt Bar

The prompt bar at the bottom of the screen displays your MUD's prompt with colors preserved. MDW includes a trigger (`MDW_PromptCapture`) that automatically captures prompts.

### Prompt Bar API

```lua
-- Capture current line and display in prompt bar (call from a trigger)
mdw.capturePrompt()           -- Captures line, displays in bar, deletes from main window
mdw.capturePrompt(false)      -- Same, but keeps line in main window

-- Set prompt bar text directly
mdw.setPrompt("<255,200,100>HP: 100")    -- decho format (RGB)
mdw.setPromptCecho("<green>HP: <white>100")  -- cecho format (named colors)

-- Clear the prompt bar
mdw.clearPrompt()
```

### Custom Prompt Trigger

If the default trigger doesn't work with your MUD, create your own:

1. Disable the `MDW_PromptCapture` trigger
2. Create a new trigger matching your MUD's prompt pattern
3. In the trigger script, call `mdw.capturePrompt()`

### GMCP-Based Prompt

You can also build a custom prompt from GMCP data:

```lua
-- In a script handling gmcp.Char.Vitals event
local v = gmcp.Char.Vitals
mdw.setPromptCecho(string.format(
  "<green>HP:<white>%d/%d <blue>MP:<white>%d/%d",
  v.health, v.health_max, v.mana, v.mana_max
))
```

## Quick Start

```lua
-- Create a simple widget docked to the left sidebar
local myWidget = mdw.Widget:new({
  name = "MyWidget",
  title = "My Custom Widget",
  dock = "left",
})

-- Clear and display text (clear first for reload-safe scripts)
myWidget:clear()
myWidget:echo("Hello, World!\n")
myWidget:cecho("<green>Success!</green>\n")
```

## Creating Widgets

### Basic Widget

```lua
local widget = mdw.Widget:new({
  name = "Inventory",      -- Required: unique identifier
  title = "My Inventory",  -- Optional: display title (defaults to name)
  dock = "left",           -- Optional: "left", "right", or nil for floating
  height = 250,            -- Optional: height in pixels
})
```

**Note:** If a widget with the same name already exists, `Widget:new()` returns the existing widget instead of creating a duplicate. This allows scripts to be safely reloaded without errors.

### Persisting Widgets Across Package Reloads

When the MDW package reloads, custom widgets are destroyed. To automatically recreate your widgets, listen for the `mdwReady` event.

**Option 1: Using the Mudlet Script UI**

Create a Script in Mudlet and add `mdwReady` to the "Add User Defined Event Handler" list:

```lua
-- In a Mudlet Script, add "mdwReady" to the event handlers list
function myWidgetSetup()
  local myWidget = mdw.Widget:new({
    name = "MyWidget",
    title = "My Custom Widget",
    dock = "left",
  })
  myWidget:clear()
  myWidget:echo("Widget ready!\n")
end
```

**Option 2: Using registerAnonymousEventHandler**

Register an anonymous event handler directly in your script code. This is useful when you want to keep everything in code without using the UI:

```lua
function myWidgetSetup()
  local myWidget = mdw.Widget:new({
    name = "MyWidget",
    title = "My Custom Widget",
    dock = "left",
  })
  myWidget:clear()
  myWidget:echo("Widget ready!\n")
end

-- Register the event handler programmatically
registerAnonymousEventHandler("mdwReady", myWidgetSetup)
```

**Option 3: Register before MDW loads**

Register your widget creation function before MDW loads (must be called before MDW initializes):

```lua
mdw = mdw or {}
mdw.userWidgets = mdw.userWidgets or {}
mdw.userWidgets[#mdw.userWidgets + 1] = function()
  local myWidget = mdw.Widget:new({
    name = "MyWidget",
    title = "My Custom Widget",
    dock = "left",
  })
  myWidget:clear()
  myWidget:echo("Widget ready!\n")
end
```

### Constructor Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | string | *required* | Unique identifier for the widget |
| `title` | string | name | Display title shown in title bar |
| `dock` | string | nil | `"left"`, `"right"`, or `nil` for floating |
| `x` | number | 100 | Initial X position (floating only) |
| `y` | number | 100 | Initial Y position (floating only) |
| `height` | number | 200 | Widget height in pixels |
| `visible` | boolean | true | Whether widget starts visible |
| `row` | number | auto | Row index in dock (auto-assigned if nil) |
| `onClose` | function | nil | Callback when widget is hidden |
| `onClick` | function | nil | Callback when content area is clicked |
| `overflow` | string | `"wrap"` | Text overflow mode: `"wrap"`, `"ellipsis"`, or `"hidden"` |

### Overflow Modes

The `overflow` option controls how text behaves when it exceeds the widget width:

| Mode | Behavior | On Resize |
|------|----------|-----------|
| `"wrap"` | Lines wrap at the widget edge (default) | Text reflows to new width |
| `"ellipsis"` | Long lines are truncated with "..." | Text re-truncated to new width |
| `"hidden"` | Text clips at widget edge, no wrapping | No reflow |

```lua
-- Default: text wraps and reflows on resize
local inv = mdw.Widget:new({
  name = "Inventory",
  overflow = "wrap",
})

-- Long lines show "..." instead of wrapping
local status = mdw.Widget:new({
  name = "Status",
  overflow = "ellipsis",
})

-- Text clips at the edge, no buffer or reflow
local log = mdw.Widget:new({
  name = "Log",
  overflow = "hidden",
})
```

Ellipsis mode works with all echo methods (`echo`, `cecho`, `decho`, `hecho`), preserving color codes up to the truncation point.

### Callbacks

```lua
local widget = mdw.Widget:new({
  name = "Clickable",
  title = "Click Me",
  dock = "right",
  onClick = function(self, event)
    self:cecho("<yellow>Clicked at " .. event.x .. ", " .. event.y .. "\n")
  end,
  onClose = function(self)
    echo("Widget was closed\n")
  end,
})
```

## Widget Methods

### Display Methods

```lua
widget:echo("Plain text\n")                    -- Plain text
widget:cecho("<red>Colored</red> text\n")      -- Color names
widget:decho("<255,128,0>RGB text\n")          -- RGB values
widget:hecho("#FF8000Hex text\n")              -- Hex colors
widget:clear()                                  -- Clear content
```

### Docking Methods

```lua
widget:dock("left")          -- Dock to left sidebar
widget:dock("right")         -- Dock to right sidebar
widget:dock("left", 0)       -- Dock to specific row (0 = first)
widget:undock()              -- Make floating at current position
widget:undock(200, 300)      -- Make floating at specific position
widget:isDocked()            -- Returns "left", "right", or nil
```

### Visibility Methods

```lua
widget:show()        -- Show the widget
widget:hide()        -- Hide the widget
widget:toggle()      -- Toggle visibility
widget:isVisible()   -- Returns true/false
```

### Appearance Methods

```lua
widget:setTitle("New Title")                    -- Change title
widget:setFont("Consolas", 12)                  -- Set font and size
widget:setBackgroundColor(20, 20, 20)           -- Set content background (RGB)
widget:setTitleStyleSheet([[                    -- Custom title bar style
  background-color: rgb(60,60,60);
  color: white;
]])
widget:setContentStyleSheet([[                  -- Custom content area style
  background-color: rgb(20,20,30);
]])
```

### Size and Position Methods

```lua
widget:resize(300, 200)      -- Resize to width, height
widget:resize(nil, 250)      -- Resize height only
widget:move(100, 100)        -- Move (floating only)
widget:raise()               -- Bring to front

local x, y = widget:getPosition()
local w, h = widget:getSize()
```

### Special Content

```lua
-- Embed the Mudlet mapper
widget:embedMapper()

-- Remove mapper and restore normal content
widget:removeMapper()
```

### Destruction

```lua
widget:destroy()   -- Remove widget and clean up
```

## Tabbed Widgets

Tabbed widgets provide multiple switchable content areas within a single widget, ideal for communication channels, logs, or categorized information.

### Creating a Tabbed Widget

```lua
local comm = mdw.TabbedWidget:new({
  name = "Comm",
  title = "Communications",
  tabs = {"All", "Room", "Global", "Tells", "Party"},
  allTab = "All",        -- Optional: receives copies of all messages
  activeTab = "All",     -- Optional: initially active tab
  dock = "right",
  height = 300,
})
```

### Constructor Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | string | *required* | Unique identifier for the widget |
| `title` | string | name | Display title shown in title bar |
| `tabs` | table | *required* | Array of tab names |
| `allTab` | string | nil | Tab that receives copies of all messages |
| `activeTab` | string | first tab | Initially active tab |
| `dock` | string | nil | `"left"`, `"right"`, or `nil` for floating |
| `height` | number | 200 | Widget height in pixels |
| `onTabChange` | function | nil | Callback when tab is switched |
| `overflow` | string | `"wrap"` | Text overflow mode: `"wrap"`, `"ellipsis"`, or `"hidden"` (applies to all tabs) |

### Display Methods

```lua
-- Echo to the currently active tab
comm:echo("Plain text\n")
comm:cecho("<red>Colored text\n")
comm:decho("<255,128,0>RGB text\n")
comm:hecho("#FF8000Hex text\n")
comm:clear()

-- Echo to a specific tab (also copies to "all" tab if configured)
comm:echoTo("Room", "Someone says: Hello!\n")
comm:cechoTo("Global", "<cyan>[Global] Message\n")
comm:dechoTo("Tells", "<255,200,100>Tell from Bob\n")
comm:hechoTo("Party", "#00FF00Party chat\n")

-- Clear specific or all tabs
comm:clearTab("Room")
comm:clearAll()
```

### Tab Management

```lua
-- Switch tabs
comm:selectTab("Tells")

-- Get current tab info
local currentTab = comm:getActiveTab()     -- Returns tab name
local tabIndex = comm:getTabIndex("Room")  -- Returns numeric index

-- Get direct access to a tab's MiniConsole
local console = comm:getTab("Global")
console:echo("Direct console access\n")
```

### Other Methods

Tabbed widgets support all the same docking, visibility, appearance, and size methods as regular widgets:

```lua
comm:dock("left")
comm:undock()
comm:show()
comm:hide()
comm:setTitle("New Title")
comm:setFont("Consolas", 12)  -- Sets font for all tabs
comm:resize(nil, 400)
comm:destroy()
```

### Tabbed Widget Class Methods

```lua
-- Get a tabbed widget by name
local comm = mdw.TabbedWidget.get("Comm")

-- Get list of all tabbed widget names
local names = mdw.TabbedWidget.list()
```

### The "All" Tab Feature

When you specify an `allTab`, any message sent via `echoTo()`, `cechoTo()`, etc. is automatically duplicated to the "all" tab (unless you're already echoing to the all tab):

```lua
local comm = mdw.TabbedWidget:new({
  name = "Chat",
  tabs = {"All", "Say", "Tell", "OOC"},
  allTab = "All",
  dock = "right",
})

-- This message appears in both "Say" and "All" tabs
comm:cechoTo("Say", "<white>You say: Hello!\n")

-- This message only appears in "All" tab (no duplication)
comm:cechoTo("All", "<gray>--- Session started ---\n")
```

## Class Methods

```lua
-- Get a widget by name
local widget = mdw.Widget.get("Inventory")

-- Get list of all widget names
local names = mdw.Widget.list()

-- Show/hide all widgets
mdw.Widget.showAll()
mdw.Widget.hideAll()

-- Low-level: get sorted list of all widget names
local allNames = mdw.getWidgetNames()
```

## Accessing Widgets from Other Scripts

Widgets can be accessed by name from any script using the `get()` class methods. This allows you to create widgets in one place and push data to them from separate scripts (like GMCP handlers).

```lua
-- Get a regular widget
local stats = mdw.Widget.get("Stats")
if stats then
  stats:cecho("<green>Updated!\n")
end

-- Get a tabbed widget
local comm = mdw.TabbedWidget.get("Comm")
if comm then
  comm:cechoTo("Room", "<white>Hello!\n")
end
```

## GMCP Integration Examples

### Communication Channels

Route GMCP communication messages to appropriate tabs in a tabbed widget.

**Step 1: Create the widget** (in a Script with `mdwReady` event handler)

```lua
-- Script: CommWidgetSetup
-- Event: mdwReady

function setupCommWidget()
  mdw.TabbedWidget:new({
    name = "Comm",
    title = "Communications",
    tabs = {"All", "Room", "Chat", "Tells"},
    allTab = "All",
    dock = "right",
    height = 300,
  })
end
```

**Step 2: Handle GMCP messages** (in a separate Script with `gmcp.Comm.Channel` event handler)

```lua
-- Script: CommHandler
-- Event: gmcp.Comm.Channel

--[[
  gmcp.Comm.Channel structure:
  {
    channel = "chat",
    sender = "Bob",
    source = "player",
    text = "this is a test"
  }
]]

function onCommChannel()
  local comm = mdw.TabbedWidget.get("Comm")
  if not comm then return end

  local data = gmcp.Comm.Channel
  local channel = data.channel
  local sender = data.sender
  local text = data.text

  -- Map GMCP channel names to tab names
  local tabMap = {
    say = "Room",
    yell = "Room",
    chat = "Chat",
    newbie = "Chat",
    tell = "Tells",
    reply = "Tells",
  }

  local tabName = tabMap[channel] or "All"

  -- Format and display the message
  local color = (channel == "tell" or channel == "reply") and "yellow" or "white"
  comm:cechoTo(tabName, string.format(
    "<gray>[<" .. color .. ">%s<gray>] <<cyan>%s<gray>> %s\n",
    channel, sender, text
  ))
end
```

### Character Vitals

Display character stats in a widget, updating whenever GMCP vitals are received.

**Step 1: Create the widget** (in a Script with `mdwReady` event handler)

```lua
-- Script: VitalsWidgetSetup
-- Event: mdwReady

function setupVitalsWidget()
  mdw.Widget:new({
    name = "Vitals",
    title = "Character Stats",
    dock = "left",
    height = 150,
  })
end
```

**Step 2: Handle GMCP vitals** (in a separate Script with `gmcp.Char.Vitals` event handler)

```lua
-- Script: VitalsHandler
-- Event: gmcp.Char.Vitals

--[[
  gmcp.Char.Vitals structure:
  {
    health = 9,
    health_max = 9,
    mana = 7,
    mana_max = 7,
    stamina = 52,
    stamina_max = 52
  }
]]

function onCharVitals()
  local vitals = mdw.Widget.get("Vitals")
  if not vitals then return end

  local v = gmcp.Char.Vitals

  -- Calculate percentages
  local healthPct = (v.health / v.health_max) * 100
  local manaPct = (v.mana / v.mana_max) * 100
  local staminaPct = (v.stamina / v.stamina_max) * 100

  -- Choose colors based on percentage
  local function getColor(pct)
    if pct > 66 then return "green"
    elseif pct > 33 then return "yellow"
    else return "red"
    end
  end

  -- Clear and redraw
  vitals:clear()
  vitals:cecho(string.format(
    "  <white>Health:  <%s>%d<white>/<green>%d <gray>(%d%%)\n",
    getColor(healthPct), v.health, v.health_max, healthPct
  ))
  vitals:cecho(string.format(
    "  <white>Mana:    <%s>%d<white>/<green>%d <gray>(%d%%)\n",
    getColor(manaPct), v.mana, v.mana_max, manaPct
  ))
  vitals:cecho(string.format(
    "  <white>Stamina: <%s>%d<white>/<green>%d <gray>(%d%%)\n",
    getColor(staminaPct), v.stamina, v.stamina_max, staminaPct
  ))
end
```

### Tips for GMCP Integration

1. **Always check if the widget exists** before using it, in case MDW hasn't loaded yet or the widget was destroyed
2. **Use separate scripts** for widget creation and GMCP handlers to keep code organized
3. **Use the `mdwReady` event** for widget creation to ensure MDW is fully initialized
4. **Use `widget:clear()` before redrawing** for vitals/stats that replace their entire content
5. **Use `echoTo()` for communication** to take advantage of the "all tab" feature

## Layout Persistence

MDW automatically saves and restores widget layouts across profile reloads and package updates. The following state is preserved:

- Widget dock positions (left, right, or floating)
- Widget sizes and positions
- Row order and side-by-side arrangements
- Visibility state
- Active tab for tabbed widgets
- Dock widths

Layout is saved automatically when:
- The profile exits
- The package is updated

### Layout API

```lua
mdw.saveLayout()    -- Manually save current layout
mdw.loadLayout()    -- Manually load saved layout (usually automatic)
mdw.clearLayout()   -- Delete saved layout, reset to defaults
```

The layout file is stored at: `getMudletHomeDir() .. "/mdw_layout.lua"`

## Configuration

Customize the appearance by modifying `mdw.config` before widgets are created:

```lua
-- Dock dimensions
mdw.config.leftDockWidth = 300
mdw.config.rightDockWidth = 250
mdw.config.minDockWidth = 150
mdw.config.maxDockWidth = 1000

-- Widget dimensions
mdw.config.widgetHeight = 200
mdw.config.titleHeight = 25
mdw.config.minWidgetHeight = 50

-- Colors (CSS format)
mdw.config.sidebarBackground = "rgb(26,24,21)"
mdw.config.widgetBackground = "rgb(30,30,30)"
mdw.config.headerBackground = "rgb(38,38,38)"

-- Text colors (decho format: R,G,B)
mdw.config.headerTextColor = "140,120,80"

-- Typography
mdw.config.fontFamily = "JetBrains Mono NL"
mdw.config.fontSize = 11

-- Rebuild styles after changing colors
mdw.buildStyles()
```

### All Configuration Options

| Category | Option | Default | Description |
|----------|--------|---------|-------------|
| **Dock Dimensions** |
| | `leftDockWidth` | 250 | Initial width of left sidebar |
| | `rightDockWidth` | 250 | Initial width of right sidebar |
| | `minDockWidth` | 150 | Minimum dock width when resizing |
| | `maxDockWidth` | 1000 | Maximum dock width when resizing |
| **Widget Dimensions** |
| | `widgetHeight` | 200 | Default height for new widgets |
| | `titleHeight` | 25 | Height of widget title bars |
| | `minWidgetHeight` | 50 | Minimum widget height when resizing |
| | `minWidgetWidth` | 50 | Minimum width for side-by-side widgets |
| | `minFloatingWidth` | 100 | Minimum width for floating widgets |
| **Layout** |
| | `dockSplitterWidth` | 4 | Width of dock edge splitters (resize handles) |
| | `widgetSplitterHeight` | 2 | Height of between-widget splitters |
| | `widgetSplitterWidth` | 2 | Width of between-widget splitters (horizontal resize) |
| | `headerHeight` | 30 | Height of top header bar |
| | `promptBarHeight` | 30 | Height of bottom prompt bar |
| | `widgetMargin` | 2 | Margin around widgets in docks |
| **Drag Behavior** |
| | `dragThreshold` | 5 | Pixels before click becomes drag |
| | `dockDropBuffer` | 200 | Detection area beyond dock bounds |
| | `snapThreshold` | 15 | Distance for height snap |
| **Colors** |
| | `sidebarBackground` | rgb(26,24,21) | Sidebar background color |
| | `widgetBackground` | rgb(30,30,30) | Widget content background (CSS) |
| | `widgetBackgroundRGB` | {30,30,30} | Widget content background (RGB table) |
| | `headerBackground` | rgb(38,38,38) | Header/title bar background |
| | `splitterColor` | rgb(57,53,49) | Splitter/border color |
| | `splitterHoverColor` | rgb(106,91,58) | Splitter hover color |
| | `headerTextColor` | 140,120,80 | Title text color (R,G,B) |
| **Typography** |
| | `fontFamily` | JetBrains Mono NL | Default font family |
| | `fontSize` | 11 | Default font size |

## Layout Structure

```
+----------------+------------------------+------------------+
|           Header Bar (Layout | Widgets menus)             |
+----------------+------------------------+------------------+
|                |                        |                  |
|   Left Dock    |    Main Display        |   Right Dock     |
|   (widgets)    |    (Mudlet default)    |   (widgets)      |
|                |                        |                  |
| +-----------+  |                        | +--------------+ |
| |  Widget   |  |                        | |   Widget     | |
| +-----------+  |                        | +--------------+ |
| +-----------+  |                        | +--------------+ |
| |  Widget   |  |                        | |   Widget     | |
| +-----------+  |                        | +--------------+ |
|                |                        |                  |
|                +------------------------+                  |
|                |      Prompt Bar        |                  |
+----------------+------------------------+------------------+
```

## Drag and Drop

- **Drag** a widget by its title bar
- **Drop on sidebar** to dock the widget
- **Drop between widgets** to insert at that position
- **Drop on widget edge** to place side-by-side
- **Drop outside docks** to make the widget floating

## Building from Source

Requires [Muddler](https://github.com/demonnic/muddler) to build:

```bash
muddle
```

The built package will be in `./build/`.

## Credits

- This project grew out of conversations with [MentalThinking](https://github.com/MentalThinking)
- Inspired by [Demonnic's MDK](https://github.com/demonnic/MDK)
- Built for [Mudlet](https://www.mudlet.org/)

## License

MIT License - feel free to use and modify for your own projects.
