# Recreating the Web-Client Widgets in Mudlet

This document describes how the Willowdale web client builds its widgets from GMCP,
when each widget refreshes, and which widgets send commands or requests back to the
server. Use it as the data contract for building equivalent Mudlet widgets on top of
your existing widget framework.

It is documentation only - no Mudlet code here. Where the web client and Mudlet differ
at the protocol level, that difference is called out explicitly.

---

## 1. The mental model

The relationship is push-driven:

1. The server sends GMCP messages whenever the underlying game state changes (and a
   batch of them at login).
2. The client keeps a single in-memory tree of the latest payloads (the web client
   calls this `GMCPStructs`; in Mudlet this is the `gmcp` table).
3. Each incoming message fires a small handler that reads the stored payload and
   repaints the affected widget.
4. The client pulls data on demand by sending GMCP *request* messages (e.g. when a
   widget is first opened, or to lazily fetch a detail view).

So a Mudlet widget is just: register a GMCP event handler -> read `gmcp.<Package>` ->
redraw. Interactive widgets additionally `send()` a normal game command or a GMCP
request when clicked.

The web client's central dispatch is in
`_datafiles/html/public/static/webclient/js/gmcp-ui.js` (`handleGMCP` ->
`GMCPUpdateHandlers`). The server side is in `modules/gmcp/`.

---

## 2. Transport: web client vs Mudlet (read this first)

The web client does **not** speak real telnet GMCP. It runs over a WebSocket and uses a
text-line convention. Mudlet speaks native telnet GMCP (IAC SB 201 ... IAC SE). The
*payloads are identical*; only the framing differs. Translation table:

| Concern | Web client (WebSocket) | Mudlet (telnet GMCP) |
|---|---|---|
| Receiving a package | Server sends `!!GMCP(Char.Vitals {json})` as a text line; client splits namespace from JSON | Standard GMCP sub-negotiation; Mudlet fires `gmcp.Char.Vitals` |
| Reading a package | `GMCPStructs.Char.Vitals` | `gmcp.Char.Vitals` |
| Requesting a package | Sends text line `GMCP:SendCharVitals` | Send a GMCP message (see Section 3) |
| Plain game command | `socket.send("look #5\n")` | `send("look #5")` |

Two consequences for Mudlet:

- **Prompt strings are now sent to Mudlet via GMCP.** `Char.Vitals.prompt` and
  `Char.Vitals.prompt2` are sent to both the web client and Mudlet, so a GMCP-driven
  prompt bar stays in sync with in-game prompt changes (custom prompt config, combat
  fprompt). The web client gets the raw `<ansi>` tagged string (it parses tags itself);
  **Mudlet gets the same prompt rendered to real ANSI escape codes** (`gmcp.Char.go`,
  the `Char.Vitals` build). Plain non-Mudlet telnet clients still get the prompt only in
  the text stream, so treat `prompt`/`prompt2` as possibly absent and fall back to the
  numeric fields (`health`, `health_max`, `aether`, `aether_max`). `combat_states` is
  always present when the player has active states.
- **The map is different.** `Map.Nearby` (the web client's interactive canvas map) is
  sent to web clients only. Mudlet uses its own built-in mapper, driven by the
  `Client.Map` protocol in `modules/gmcp/gmcp.Mudlet.go`. If you want a Mudlet map, use
  the native mapper, not a `Map.Nearby` reimplementation. Everything else in this guide
  applies to Mudlet unchanged.

---

## 3. Requesting data from the server (client -> server)

The server supports two request forms over telnet GMCP. Both are handled in
`modules/gmcp/gmcp.go` (`case 'GMCP'` around line 553, and the `default` branch around
line 624).

### Form A - standard GMCP node request (recommended for Mudlet)

Send a GMCP message whose **package name is the node you want**, with an optional JSON
body. An optional `.Get` suffix is accepted and stripped.

```
Char.Vitals          {}        -- request just vitals
Char                 {}        -- request the whole Char namespace
Room.Info            {}        -- request room basic+exits+contents
Game.Calendar        {}        -- request the calendar
Comm.History         {}        -- request recent channel history
Char.Quest.Detail    {"id":8}  -- parameterized request (one quest's detail)
```

Allowed top-level namespaces (`gmcp.go:760`): `Char`, `Room`, `Party`, `Game`, `Map`,
`Comm`, `Client.Map`. Requesting a bare namespace sends the whole namespace; requesting
a specific node sends just that node. Anything outside these namespaces is ignored.

### Form B - legacy `Send<Node>` convenience form

Send a GMCP message with package name `GMCP` and a string payload `Send<CamelCasePath>`.
The server converts CamelCase to dotted notation (`SendCharInventoryWorn` ->
`Char.Inventory.Worn`). An argument can follow a space. This is exactly what the web
client uses internally (`sendGMCP('SendCharVitals')` -> text line `GMCP:SendCharVitals`).

```
GMCP  "SendCharVitals"
GMCP  "SendCharQuestDetail 8"
GMCP  "SendFullPayload"          -- resend the entire login batch
```

Both forms end up in the same `routeGMCPNodeRequest` dispatcher, so either works. Form A
is cleaner for Mudlet; Form B's `SendFullPayload` is the easy "give me everything again"
call (handy after a UI reload).

### The login batch

At spawn the server pushes a full batch automatically. The web client also re-requests a
known set once its layout is ready (`requestWidgetData`, `gmcp-ui.js:163`):

```
SendCharInfo, SendCharAttributes, SendCharWorth,
SendGameInfo, SendGameWho, SendGameCalendar, SendGameClock,
SendCharAffects (if Affects widget open),
SendCharQuests (if Quests/Journal open),
SendCharInventoryWorn, SendCharInventoryBackpackItems,
SendCharInventoryBackpackSummary, SendCharInventoryKeyring,
SendCharInventoryIngredients (if any Items widget open),
SendMapNearby (web only), SendCommHistory (if Comm open)
```

For Mudlet, the simplest robust startup is: on login (and on `Engine.Copyover`), send
`GMCP "SendFullPayload"`, then request per-widget nodes you care about. The "request on
open" pattern (Section 4) keeps you from rendering into closed widgets.

---

## 4. Update cadence - when widgets refresh

Each package has its own trigger. Categories:

- **On-change (most Char.* and Room.*)** - sent whenever the value changes. e.g.
  `Char.Worth` on XP/gold change, `Char.Inventory.Worn` on equip/unequip,
  `Char.Affects` on buff apply/expire.
- **Per-beat while in combat** - `Char.Combat.Status`, `Char.Combat.Enemies`,
  `Char.Combat.Target`, and `Char.Balance` update very frequently during combat.
  `Char.Vitals` is rate-limited to at most one push per 100ms.
- **Periodic** - `Game.Clock` (~once per second), `Game.Calendar` (on day/night phase
  changes).
- **On-demand only** - `Char.Quest.Detail` (lazy, per quest), `Comm.History` (on
  request), `Room.Admin` (admin, on room change).
- **Event one-shots** - `Char.Combat.Started/Ended/DamageDealt/...`, `Room.Add.*`,
  `Room.Remove.*`, `Engine.Copyover`.

Web-client "request on widget open" pattern: when a widget is toggled open it calls its
matching GMCP handler immediately (with cached data) and, for data it may not have yet,
re-requests the node. The widget->handler map is in `dockview-widgets.js:642`
(`handleWidgetToggle`). Replicate this in Mudlet: when the user opens a widget, request
its node so it populates even if nothing has changed since login.

---

## 5. Per-widget reference

For each widget: the GMCP package(s) it reads, the fields it uses, what triggers a
refresh, and what it sends back to the server. Field names are the exact JSON wire names
(snake_case, from the Go `json:"..."` struct tags).

### 5.1 Vitals / prompt gauges (HP, AE, Balance, Enemy)

The web client renders these both in a always-on prompt bar and inside the Combat widget
(shared draw code, `gauge-` and `pb-gauge-` element prefixes). In Mudlet these are your
core status gauges.

| Gauge | Package | Fields used | Trigger |
|---|---|---|---|
| HP | `Char.Vitals` | `health`, `health_max` | vitals change (<=1/100ms) |
| AE | `Char.Vitals` | `aether`, `aether_max` | vitals change |
| Balance | `Char.Balance` | `balance`, `max_balance`, `seconds`, `is_balanced` | every balance change / per beat |
| Enemy | `Char.Combat.Target` | `name`, `hp_current`, `hp_max`, `id` (all ints; `hp` is `0` when no target) | target acquired / target HP change |

- HP gauge color thresholds in the web client: low <=33%, mid <=66%.
- Balance: when `is_balanced` is true, show full bar + "Balanced"; otherwise width =
  `balance / max_balance`, label = `seconds` + "s".
- Enemy gauge: if `name` is empty there is no target - dim the bar and show "No Enemy".
- `Char.Vitals.combat_states` is an array of `{name, category, remaining, stacks}` -
  the player's own active combat states (STAGGERED, POISONED, etc.). The web prompt bar
  does not draw these, but they are available for a "my states" indicator.
- Sends back: nothing.

### 5.2 Combat widget

The combat widget = the four gauges above plus an enemy list. Data:

| Element | Package | Fields used |
|---|---|---|
| Enemy list (names + per-enemy HP bars) | `Char.Combat.Enemies` (array) | `name`, `id`, `is_primary`, `health`, `health_max` |
| Target marker `(T)` | `Char.Combat.Target` | `id` (matched against the list) |
| Status text next to target | `Char.Combat.Status` | `in_combat`, `in_melee`, `combat_action` |
| Combat end / clear | `Char.Combat.Ended` | (no fields; clears the display) |

Trigger: all of these update per combat beat while engaged. When `Char.Combat.Status`
arrives with `in_combat:false`, or `Char.Combat.Ended` arrives, clear the widget.

Status text rule (from `Char.Combat.Status`): if `combat_action` is set show
`(<action>)` (action is one of attack/advancing/retreating/fleeing/shooting/casting);
else if `in_melee` show `(engaged)`; else `(advancing)`.

**Sends back:**
- Click an enemy name -> `target #<id>` (note: a plain game command, not GMCP).
- Auto-target: when the current target leaves `Char.Combat.Enemies` but other enemies
  remain, the client auto-sends `target #<firstEnemyId>`.

### 5.3 Character widget (score sheet)

Aggregates several packages into one panel (`updateCharacterPanel`).

| Field group | Package | Fields |
|---|---|---|
| Identity | `Char.Info` | `account`, `name`, `class`, `race`, `level`, `role`, `number_format` |
| Attributes / derived | `Char.Attributes` | `body`, `mind`, `spirit`, `armor_rating`, `evasion_chance`, `warding_rating`, `spirit_resilience`, `martial_power`, `aether_power`, `state_potency` |
| Wealth / progression | `Char.Worth` | `gold_carried`, `gold_bank`, `stat_points`, `training_points`, `xp_total`, `xp_current`, `xp_tnl` |
| Pools | `Char.Vitals` | `health`, `health_max`, `aether`, `aether_max` |

Trigger: re-render on any of `Char.Info`, `Char.Attributes`, `Char.Worth` (each on
change: train, equip, stat change, XP gain). Sends back: nothing.

`number_format` from `Char.Info` is a display preference (thousands formatting) the web
client applies to all numbers.

### 5.4 Equipment (worn) - part of the "Items" widget

Package: `Char.Inventory.Worn`. One object keyed by slot:

```
weapon, offhand, head, neck, body, back, belt, gloves,
ringmainhand, ringoffhand, legs, feet
```

Each slot is either empty or `{id, name, type, sub_type, uses, quantity, details,
command}`. `details` is a string array of badges like `cursed`, `enchanted`.

Trigger: on equip/unequip (and in the login batch). **Sends back** (right-click slot):
- `remove <slotName>` (slotName is the slot key, e.g. `remove weapon`)
- `look <id>`

### 5.5 Inventory (backpack) - part of the "Items" widget

Packages:
- `Char.Inventory.Backpack.Items` - array of `{id, name, type, sub_type, uses,
  quantity, details, command}`.
- `Char.Inventory.Backpack.Summary` - `{count, max}` (carry count footer; also feeds
  the prompt line-2 carry display).

Trigger: on any inventory change (pickup/drop/buy/use) and login batch. The server can
sort the list (name/time/value asc/desc); the client renders whatever order it receives.

**Sends back** (right-click item context menu):
- `<item.command> <id>` - each item carries its own primary `command` (e.g. `wield`,
  `wear`, `wield`); the menu offers that verb first.
- `look <id>`, `drop <id>`, `eat <id>` (eat shown for food types).

### 5.6 Keyring - part of the "Items" widget

Package: `Char.Inventory.Keyring` - array of `{type, location, roomid, where,
sequence}`. `type` is "Key" or "Lockpick"; `sequence` is only meaningful for lockpicks.
Trigger: when the keyring changes / login. Sends back: nothing.

### 5.7 Ingredients - part of the "Items" widget

Package: `Char.Inventory.Ingredients` - `{items:[...], count, max}` where each item has
the same shape as backpack items. Trigger: when the ingredient bag changes / login.
Sends back: nothing.

### 5.8 Affects (buffs/states) widget

Package: `Char.Affects`. An object keyed by affect name; each value is
`{name, description, duration_max, duration_current, type, affects}`:

- `duration_max` / `duration_current` in seconds (`-1` = permanent).
- `type` is `buff`, `state`, or a source name.
- `affects` is a map of stat-mod name -> value.

Trigger: on buff apply/expire/refresh and equipment change (gear-granted affects), plus
login. Sends back: nothing. Mudlet should drive countdowns locally from
`duration_current` rather than expecting a tick per second.

### 5.9 Quests widget

Package: `Char.Quests` - `{active:[...], completed:[...], rumors:[...]}`.

- Active quest: `id`, `name`, `category`, `completion`, `step_description`, `tracked`,
  `ready`, `receiver`, `zone`, `repeatable`, `objectives`.
- Completed quest: `id`, `name`, `category`, `description`, `count`.
- Rumor (intentionally masked): `text`, `source_text`, `zone` (no id/name).

Trigger: on any quest progress/accept/complete and login. On refresh the web client
also drops its lazily-fetched detail cache (objective progress can change).

Lazy detail: expanding a quest row fetches `Char.Quest.Detail` for that quest:
- Request: `GMCP "SendCharQuestDetail <id>"` or Form A `Char.Quest.Detail {"id":<id>}`.
- Response package `Char.Quest.Detail` carries the full view: `id`, `name`, `category`,
  `description`, `giver_name`, `giver_zone`, `hints[]`, `completion`, `step_num`,
  `step_count`, `step_description`, `step_hint`, `objectives[] {text,current,count,done}`,
  `quest_items[] {name,count}`, `reward_xp`, `reward_gold`, `reward_items[]`,
  `reward_title`, `reward_skill`, `reward_buff`, `has_reward`, `completed`,
  `times_done`, `active`, `tracked`.

**Sends back** (context menu / track toggle):
- `quest <id>` - show quest information.
- `quest track <id>` / `quest untrack <id>`.

### 5.10 Journal widget

Same package as Quests (`Char.Quests`); it is a fuller, filterable list over the same
payload (`renderQuestJournal`). It refreshes on the same `Char.Quests` pushes. Sends
back: the same quest commands as the Quests widget.

### 5.11 Communication (chat) widget

Packages:
- `Comm.Channel` - one live message: `{channel, sender, source, text, ansi, html,
  timestamp?}`. `channel` is say/shout/chat/broadcast/login/party/tell/otell. `source`
  is "player" or "mob". The web client renders the `html` field; for Mudlet use `ansi`
  (or `text` for a plain log).
- `Comm.History` - a batch of past `Comm.Channel` messages (up to ~60 across the public
  channels), each with `timestamp`. Requested on open.

Trigger: `Comm.Channel` pushes immediately per message; `Comm.History` only on request.

**Sends back:** nothing special - chat is sent with normal commands (`say`, `chat`,
`tell <name> ...`) through the regular input line.

### 5.12 Map

**Web client:** package `Map.Nearby` (web-only) drives a canvas map, and
`Map.HighlightPath` highlights a computed route. Sends back: `speedwalk <roomId>` on
double-click, `speedwalk stop`, and `mapunmark <roomId>`.

**Mudlet:** do not reimplement `Map.Nearby`. Use Mudlet's native mapper via the
`Client.Map` protocol (`gmcp.Mudlet.go`); request it with `Client.Map {}`. Room/zone
context also arrives through `Room.Info.Basic` (see 5.14) if you want a custom display.

### 5.13 Time bar (clock + calendar)

Packages:
- `Game.Clock` - `{time}` (HH:MM:SS), ~once per second.
- `Game.Calendar` - `{phase, day_name, day, week, mire, mire_num, turning, age}`, on
  day/night phase transitions.

Trigger: as above. Sends back: nothing.

### 5.14 Room context (and admin Room Inspector)

The web client has no plain "room" widget - room text goes to the terminal. But room
GMCP feeds the map/zone logic and an admin-only inspector:

- `Room.Info.Basic` - `{id, name, area, area_name, map_id, environment, biome_color,
  biome_symbol, coordinates, details}`. Pushed on room change. Drives zone tracking and
  map titles; useful for a Mudlet room/zone header widget.
- `Room.Info.Exits` - map of exit name -> `{room_id, delta_x, delta_y, delta_z,
  details}`; `details` describes doors (`type,name,state,hasKey,hasPicked`) or
  cross-map links. Good source for a clickable exits widget.
- `Room.Info.Contents.Players` / `.Npcs` / `.Items` / `.Containers` - arrays describing
  who/what is in the room (ids, names, quest flags, threat levels, lock state). Pushed
  on room change; incremental `Room.Add.*` / `Room.Remove.*` events fire as entities
  come and go.
- `Room.Admin` (admin only) - a large room-metadata snapshot for the Room Inspector;
  pushed when an admin enters a room or on refresh request.

Sends back: room widgets typically issue normal commands (movement directions, `look
<id>`, `get <id>`, `open <dir>`).

---

## 6. Outbound summary - what widgets send to the server

Two channels only:

1. **GMCP requests** (data pulls) - Section 3 forms. Used for: login refresh, "request
   on widget open", lazy quest detail, comm history.
2. **Plain game commands** (actions) - exactly what a player would type, sent verbatim.

Plain commands the web client widgets send:

| Widget | Action | Command sent |
|---|---|---|
| Combat | click enemy / auto-target | `target #<id>` |
| Equipment | remove / look | `remove <slot>`, `look <id>` |
| Inventory | use / look / drop / eat | `<item.command> <id>`, `look <id>`, `drop <id>`, `eat <id>` |
| Quests / Journal | info / track | `quest <id>`, `quest track <id>`, `quest untrack <id>` |
| Map (web only) | walk / unmark | `speedwalk <roomId>`, `speedwalk stop`, `mapunmark <roomId>` |

Note the design rule: widget buttons send *real commands*, and GMCP only carries data a
command could also reveal. Mirror that - every Mudlet widget affordance should map to a
command a player could type.

---

## 7. Web-only transport messages (ignore for Mudlet)

The web client also exchanges some non-GMCP control lines over its WebSocket that have no
Mudlet equivalent (handled natively by Mudlet or irrelevant): `TERMSIZE:`, `LAYOUTREADY`,
`CONNECT` / `RECONNECT:` / `WEBSESSION:` / `DISCONNECT`, `!!RECONNECT_TOKEN(...)`,
`!!SAVE_SETTINGS`, `!!CONFIG_UPDATED`, `!!RESET_LAYOUT`, `WSESSION:`, `TEXTMASK:`, and
MSP `!!MUSIC(...)` / `!!SOUND(...)`. One GMCP one worth handling in Mudlet:
`Engine.Copyover {status:"complete"}` is pushed after a server hot-reload - treat it as a
cue to re-request your widget data (e.g. `SendFullPayload`).

---

## 8. Gotchas and edge cases (the complete list)

The three headline differences (web-only prompt strings, web-only map, `target #id` is a
plain command) are in Sections 2 and 5. Below is the full set of non-obvious behaviours a
Mudlet reimplementation hits. Each is tagged:

- **[Mudlet]** - inherent; handle it in your widget code.
- **[Server-fixable]** - a quirk we could smooth at the source so Mudlet (and the web
  client) stop having to special-case it.

### Format / encoding

1. **[Mudlet] Use the `ansi` field for chat, not `html`.** `Comm.Channel` carries three
   renderings: `text` (plain), `ansi` (real ANSI escape codes), `html` (web). The named
   color aliases (`username`, `chat-body`, etc.) are already resolved into real ANSI in
   the `ansi` field server-side (`ansitags.Parse`), so Mudlet does **not** need the web
   client's color-alias map. Read `ansi` (or `text` for a plain log).
2. **[Fixed] Prompt strings are now sent to Mudlet.** `Char.Vitals.prompt` / `prompt2`
   are delivered to Mudlet as **real ANSI escape codes** (the web client still gets raw
   `<ansi>` tags), so a GMCP-driven prompt bar reflects in-game prompt changes. Non-Mudlet
   telnet clients still get the prompt only in the text stream, so keep the numeric-field
   fallback for those. Build gauges from `health`/`aether` regardless; use `prompt` for a
   text prompt line.

### Field-type inconsistencies (parse defensively)

3. **[Fixed] `Char.Combat.Target.hp_current` / `hp_max` are now ints** (`0` when there is
   no target), matching `Char.Combat.Enemies.health` / `health_max`. No string parsing
   needed any more.
4. **[Mudlet] `Char.Balance.seconds` is a STRING** (preformatted to one decimal);
   `balance` / `max_balance` are ints; `is_balanced` is a bool. When `is_balanced`, ignore
   the numbers and show "full / Balanced".
5. **[Mudlet] `Char.Affects` durations are ints in seconds; `-1` means permanent.** There
   is no per-second tick - drive the countdown locally from `duration_current`.
6. **[Mudlet] "No target" is a sentinel, not an absent package.** `Char.Combat.Target`
   arrives with empty `name` (and `0`/`0` HP) to mean "cleared". Treat empty `name` as
   clear-the-gauge - don't infer "no target" from the HP numbers.

### Identity / id schemes

7. **[Mudlet] Two different id formats.** Items are `!<itemId>:<uuid>`
   (`items.go:818`); mobs/NPCs are `#<instanceId>` (`mobs.go:631`). Players have their own
   shorthand. Room-contents packages hand you the full prefixed string (`#5`, `!20:uuid`);
   you pass it straight into commands (`look #5`, `get !20:uuid`).
8. **[Mudlet] Combat ids are bare ints; prepend `#` to target.** `Char.Combat.Enemies[].id`
   and `Char.Combat.Target.id` are the numeric instance id (e.g. `5`), while the room's
   version of the same mob is the string `#5`. The web client builds `target #<id>`. Don't
   try to target with the item-style shorthand.
9. **[Mudlet] Each inventory item carries its own primary `command` verb.** Use
   `item.command` (e.g. `wield`, `wear`, `eat`) rather than hardcoding the action; the
   item knows how it's used.

### Ordering / interdependencies

10. **[Mudlet] Room info arrives as several separate packages.** `Room.Info.Basic`,
    `Room.Info.Exits`, and `Room.Info.Contents.*` come as distinct messages. The web client
    waits until it has both the room id and coordinates before treating the room as
    "complete" (`gmcp-ui.js:224`). Buffer the sub-packages and render once, rather than
    repainting on each fragment.
11. **[Mudlet] The "Items" widget is four independent feeds.** Worn, Backpack
    (Items + Summary), Keyring, and Ingredients are separate packages. `Backpack.Summary`
    (`count`/`max`) is needed to render the carry footer and the prompt carry count -
    request and handle it alongside `Backpack.Items`.

### Lifecycle / refresh

12. **[Mudlet] A `Char.Quests` push invalidates cached quest detail.** Objective progress
    and step can change, so drop any cached `Char.Quest.Detail` whenever `Char.Quests`
    arrives and re-fetch on next expand (`gmcp-ui.js:656`).
13. **[Mudlet] `Char.Quest.Detail` is lazy, on-demand, and one-quest-at-a-time.** It is
    only sent when requested with an id; it is never part of the login batch.
14. **[Mudlet] Request-on-open.** Data only flows for nodes you have asked about. A widget
    opened after login stays empty until you request its node (the web client re-fires the
    matching handler / re-requests on toggle, `dockview-widgets.js:642`).
15. **[Mudlet] `Engine.Copyover {status:"complete"}` means the server hot-reloaded.** Re-
    request your data (`SendFullPayload`) - cached state may be stale.
16. **[Mudlet] A new `Char.Info.name` means a different character.** The web client tears
    down and rebuilds all widget state on a name change. Rare for Mudlet (one character per
    connection) but possible via admin possession - rebind rather than merge.

### Combat specifics

17. **[Mudlet] Combat can end two ways.** Either `Char.Combat.Ended` arrives, or
    `Char.Combat.Status` arrives with `in_combat:false`. Treat both as "clear the combat
    display".
18. **[Mudlet] Two signals say which enemy is the target.** `Char.Combat.Enemies[].is_primary`
    is the per-list hint; `Char.Combat.Target.id` is the live target. The web client paints
    the `(T)` marker from `Target.id` and uses `is_primary` as the initial state - prefer
    `Target.id` when they disagree.
19. **[Mudlet] Auto-target is a client behaviour, not the server's.** When the current
    target drops out of `Char.Combat.Enemies` but others remain, the web client auto-sends
    `target #<firstEnemy>`. Replicate it or omit it deliberately - the server won't do it
    for you.
20. **[Mudlet] `Char.Vitals.combat_states` already excludes "silent" states.** Buff-borrowed
    plumbing states are filtered server-side (`gmcp.Char.go:723`); you only receive
    player-meaningful states. No action needed, just don't expect to see internal ones.
21. **[Mudlet] Cadence is not fixed.** `Char.Vitals` is rate-limited to at most one push per
    100ms; combat packages and `Char.Balance` fire per beat; `Game.Clock` ~1/sec. Render on
    receipt; don't poll or assume a tick rate.

### Comm specifics

22. **[Fixed] The empty schema-template batch has been removed entirely.** `SendFullGMCPUpdate`
    (the `SendFullPayload` / login refresh) and the `Comm` node request used to emit a pile of
    blank "schema" packages to advertise field names - empty `Comm.Channel`, `Room.Add.*`,
    `Room.Remove.*`, `Char.Combat.Started/Ended/Damage*/Attack*/Fled`, plus zeroed
    `Char.Combat.Status/Target/Enemies` and `Char.Balance`. All of these are gone; the full
    update now sends only real current state (`Char`, `Room`, `Map`, `Party`, `Game`, and
    `Comm.History`). Clients build their GMCP tree lazily from real messages, so no templates
    are needed. Combat/balance widgets simply stay empty until combat actually starts, and the
    per-beat combat packages populate them with real data. Still good practice: skip a
    `Comm.Channel` that has no `text` and no `channel` (`gmcp-ui.js:315`).
23. **[Mudlet] `Comm.History` is a one-shot batch (up to ~60 lines) on request**, separate
    from the live `Comm.Channel` stream. Request it once when the chat widget opens.

### Misc

24. **[Mudlet] `Char.Info.number_format` is a display preference** (thousands formatting) -
    apply it to your number rendering for consistency with the web client.
25. **[Mudlet] Quest rumors are intentionally masked.** They carry only `text`,
    `source_text`, `zone` - no id or name - so they are display-only, not actionable.
26. **[Mudlet] `details` arrays are badge strings.** Items use them for `cursed` /
    `enchanted`; rooms use them for `bank` / `storage` / etc. Render as tags.
27. **[Mudlet] `Map.HighlightPath` is web-only too** (route highlighting for the canvas
    map). With the native Mudlet mapper you would drive route display through the mapper API
    instead.

### Server-side smoothing (done)

The server-side smoothing has been applied: the prompt is now sent to Mudlet as real ANSI
(#2), `Char.Combat.Target` HP is now ints (#3), and the entire empty schema-template batch -
not just the `Comm.Channel` ping - has been removed from `SendFullGMCPUpdate` (#22), so the
full update carries real current state only. The rest (#7-#21, #24-#27) are inherent to an
incremental, push-based GMCP design and are best handled in the widget layer - the web client
handles them exactly the same way.

---

## 9. Quick start checklist for Mudlet

1. On connect, send `Core.Hello {"client":"Mudlet","version":"..."}` so the server flags
   you as Mudlet (enables the native mapper and Discord RP). Mudlet does this for you if
   configured.
2. On login (and on `Engine.Copyover`), send `GMCP "SendFullPayload"`.
3. Register GMCP event handlers for the packages in Section 5 and repaint the matching
   widget from `gmcp.<Package>`.
4. When the user opens a widget, request its node (Section 3 Form A) so it populates
   immediately.
5. Wire widget clicks to either a GMCP request (detail pulls) or a plain `send()` command
   (actions) per Section 6.
6. Build HP/AE gauges from the numeric `Char.Vitals` fields (no `prompt` string in
   Mudlet); drive affect/quest countdowns locally from `duration_current` / objective
   counts.
