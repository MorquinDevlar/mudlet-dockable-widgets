# MDW - Mudlet Dockable Widgets

MDW gives your [Mudlet](https://www.mudlet.org/) profile a custom sidebar UI. Create widget panels for vitals, inventory, communication channels, the mapper, or anything else you want to track at a glance. Drag widgets between left and right sidebars, place them side-by-side, stack them vertically, or float them freely over the main display. Layouts persist across reloads.

<video src="https://github.com/MorquinDevlar/mudlet-dockable-widgets/raw/main/MDW.mp4" autoplay loop muted playsinline></video>

## Features

- **Dockable Sidebars**: Left and right sidebars that hold stacked or side-by-side widgets
- **Draggable Widgets**: Drag widgets by their title bar to reposition or re-dock them
- **Side-by-Side Docking**: Place multiple widgets in the same row with resizable splitters
- **Floating Mode**: Undock widgets to float freely with resize handles on all edges
- **Tabbed Widgets**: Widgets with multiple switchable tabs and an optional "all" channel
- **Embedded Mapper**: Embed the Mudlet mapper in any widget
- **Prompt Bar**: Display your MUD prompt with colors at the bottom of the screen
- **Header Menus**: Toggle sidebar and widget visibility from dropdown menus
- **Layout Persistence**: Widget positions, sizes, dock state, and visibility saved automatically
- **Overflow Modes**: Wrap, ellipsis (truncate with "..."), or hidden text clipping
- **Resizable**: Drag dock edges, widget borders, and between-widget splitters to resize

## Layout

```
+----------------+------------------------+------------------+
|           Header Bar (Layout | Widgets menus)              |
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

- **Header bar** spans the full window width with Layout and Widgets dropdown menus
- **Left and right docks** hold widgets stacked vertically or side-by-side; drag dock edges to resize
- **Main display** is the standard Mudlet output area
- **Prompt bar** sits between the docks at the bottom, showing your MUD prompt with colors

## Installation

1. Download the latest `MDW.mpackage` file from the releases
2. In Mudlet, go to **Packages**
3. Click **Install new package** or **Install from file** depending on your version and select the downloaded `MDW.mpackage` file

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
myWidget:cecho("<green>Success!\n")
```

```lua
-- Create a tabbed widget for communication channels
local comm = mdw.TabbedWidget:new({
  name = "Comm",
  title = "Communications",
  tabs = {"All", "Room", "Chat", "Tells"},
  allTab = "All",      -- "All" tab receives copies of all messages
  dock = "right",
})

-- Send a message to a specific tab (also appears in "All")
comm:cechoTo("Room", "<white>Someone says: Hello!\n")
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

## Documentation

For detailed API reference and guides, see the **[wiki](https://github.com/MorquinDevlar/mudlet-dockable-widgets/wiki)**:

| Page | Description |
|------|-------------|
| **[Widget Options](https://github.com/MorquinDevlar/mudlet-dockable-widgets/wiki/Widget-Options)** | Constructor options, overflow modes, and callbacks |
| **[Widget Methods](https://github.com/MorquinDevlar/mudlet-dockable-widgets/wiki/Widget-Methods)** | Display, docking, visibility, appearance, size/position, and class methods |
| **[Tabbed Widgets](https://github.com/MorquinDevlar/mudlet-dockable-widgets/wiki/Tabbed-Widgets)** | Creating tabbed widgets, tab management, and the "All" tab feature |
| **[Drag and Drop](https://github.com/MorquinDevlar/mudlet-dockable-widgets/wiki/Drag-and-Drop)** | Drop zones, side-by-side docking, floating widgets, and resizing |
| **[Prompt Bar](https://github.com/MorquinDevlar/mudlet-dockable-widgets/wiki/Prompt-Bar)** | Prompt bar API, custom triggers, and GMCP-based prompts |
| **[GMCP Integration](https://github.com/MorquinDevlar/mudlet-dockable-widgets/wiki/GMCP-Integration)** | Communication channels, character vitals, and integration tips |
| **[Configuration](https://github.com/MorquinDevlar/mudlet-dockable-widgets/wiki/Configuration)** | All configuration options and customization |
| **[Header Menus](https://github.com/MorquinDevlar/mudlet-dockable-widgets/wiki/Header-Menus)** | Layout and Widgets dropdown menus, programmatic toggle |
| **[Layout Persistence](https://github.com/MorquinDevlar/mudlet-dockable-widgets/wiki/Layout-Persistence)** | What's saved, when it saves, and the Layout API |
| **[Debugging](https://github.com/MorquinDevlar/mudlet-dockable-widgets/wiki/Debugging)** | Debug mode and diagnostic tools |

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

## Building from Source

Requires [Muddler](https://github.com/demonnic/muddler) to build:

```bash
muddle
```

The built package will be in `./build/`.

## Credits

- This project grew out of conversations with [MentalThinking](https://github.com/MentalThinking)
- Inspired by [Demonnic's MDK](https://github.com/demonnic/MDK) and [Edru's AdjustableTabWindow ](https://github.com/Edru2/AdjustableTabWindow)
- Built for [Mudlet](https://www.mudlet.org/)

## License

MIT License - feel free to use and modify for your own projects.
