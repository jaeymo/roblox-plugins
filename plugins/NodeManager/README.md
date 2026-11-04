# NodeManager
A Studio plugin for creating, organizing, visualizing and validating development nodes (spawns, patrol points, and so on) in Workspace, with node types you define yourself. Nodes are ordinary Parts with attributes, so game code can use them without the plugin.

## Build and install

From the repository root:

```sh
lune run install                    # once, to fetch the shared Wally packages
lune run build NodeManager          # writes NodeManager.rbxm into %LOCALAPPDATA%\Roblox\Plugins
lune run build NodeManager --watch  # rebuild on change while developing
```

Restart Studio (or reload plugins) and click **NodeManager** in the Plugins toolbar to open the panel.

## Using it

### Nodes tab

- **Type ▾ / + Add Node**: pick one of your types, or `(none)` for a plain node, and create a node. The node is placed on top of the selected parts, models or attachments; next to the selected node; or where the camera is looking if nothing is selected. Grounded nodes drop onto the surface below.
- **Search**: filters by name, display name or type.
- **Group ▾ / + Group**: filter the list by group, or create a group. New nodes go into the filtered group.
- **List**: groups are collapsible headers. Click a node to select it, Ctrl+click to toggle it, Shift+click to select a range, and double-click to focus the camera on it. The ● / ○ button shows or hides a node or a whole group.
- **Right-click** a node for focus, duplicate, snap to ground, show/hide, move to group and delete. Right-click a group to select its nodes, show or hide them, add a node to it, rename it, or delete it. Deleting a group keeps its nodes by moving them to Ungrouped.
- **Editor** (below the list): edits every selected node at once. Fields that differ across the selection show `(mixed)` and are only changed when you type a new value. Changing **Type** applies that type's look and fields and removes fields that only the old type had (a field both types share, with the same value type, keeps its value). The **Fields** section edits the values of the node's type fields; `*` marks required ones.

You can also select and move nodes with Studio's own tools. Every change the plugin makes can be undone.

### Types tab

A type describes a kind of node: its look and the attributes (fields) every node of that type carries. For example, a `FlyingNode` type with a `FlightType` string field that defaults to `Levitate`.

- **+ New Type** creates a type; **Type ▾** switches between them.
- **Name, Color, Size, Shape, Image** set the look. **Must rest on the ground** controls whether validation reports the type's nodes as floating; turn it off for flying nodes.
- **+ Add Field** adds an attribute. Each field has:
  - a **value type** (`string`, `number` or `boolean`) and a **Default**;
  - **Fill default**: on, nodes start with the default value (and empty values are filled with it); off, nodes start empty (`""` for strings, no attribute for numbers and booleans);
  - **Required**: validation reports nodes of this type where the field is empty;
  - **Reset nodes**: overwrites the field on every node of the type with its starting value;
  - **Delete**: removes the field from the type and from its nodes.

Every change is baked onto all nodes of the type immediately: new fields are added, renamed fields carry their values across, deleted fields are removed, and changing a default updates nodes that still hold the old default (values you edited per node are kept). **Delete type** leaves its nodes untyped and removes the type's fields from them. All of it can be undone.

### Validate tab

**Scan Nodes** checks every node and lists the issues, errors first. Click an issue to select and focus the node (and, for duplicates, the node it overlaps).

| Check | How it is detected | Automatic fix |
| --- | --- | --- |
| Buried in terrain | Reads the terrain voxels at the node. When the surface passes through that voxel, a terrain-only raycast compares the surface height with the node's centre. | Raise to the open terrain surface above |
| Inside solid parts | `GetPartsInPart` with the node's own shape, counting only parts with `CanCollide` on | None |
| Floating | Downward raycast from the node, ignoring nodes and non-collidable parts, compared against the float tolerance. Skipped for nodes that are buried or inside parts, and for types with **Must rest on the ground** turned off. Untyped nodes are checked. | Snap to ground |
| No ground below | The same raycast finds nothing within the ground search distance | None |
| Outside world bounds | Only when bounds are set in the Settings tab | Move inside the bounds |
| Duplicate positions | A spatial hash finds nodes within the duplicate radius of each other | None |
| Missing metadata | A required field is empty, or `NodeType` names a type that doesn't exist | Clear the type, for unknown types |

Fixes only run when you click **Fix** on an issue or **Fix All**. Each click is a single undoable change. The scan yields between batches, so Studio stays responsive on maps with thousands of nodes.

### Settings tab

- **Validation tolerances** (float tolerance, ground search distance, surface search height, duplicate radius) are saved per user with `plugin:SetSetting`.
- **World bounds** are saved in the place as the `BoundsMin` and `BoundsMax` attributes on the `Nodes` folder. Type both corners, or select parts or models and click **Use selection**.

## Data model (for game code)

```
Workspace
└── Nodes                    Folder, tagged NodeManagerRoot
    ├── NodeTypes            Configuration holding the type definitions
    │   └── FlyingNode       Configuration: Color, Shape, Size, Image, Grounded attributes
    │       └── FlightType   Configuration: ValueType, Default, FillDefault, Required attributes
    ├── Air                  Folder = a node group
    │   └── FlyingNode_1     Part, tagged NodeManagerNode
    │       └── NodeLabel    BillboardGui (display name and optional image)
    └── Node_3               Part directly under Nodes = ungrouped
```

| Attribute | Meaning |
| --- | --- |
| `NodeType` | Name of the node's type; absent for untyped nodes |
| `NodeDisplayName` | Optional label text (the type is shown when empty) |
| `NodeImage` | Optional image asset shown in the label |
| `NodeHidden` | `true` when hidden in the editor |
| Your fields, e.g. `FlightType` | One attribute per field of the node's type |

Node parts are anchored, with `CanCollide`, `CanTouch` and `CastShadow` turned off. They use the `NodeManagerNodes` collision group, which doesn't collide with `Default`, so default raycasts and overlap queries in game code skip them. Nodes stay visible at runtime; to hide them in game, run something like:

```lua
for _, node in CollectionService:GetTagged("NodeManagerNode") do
	node.Transparency = 1
	local label = node:FindFirstChild("NodeLabel")
	if label then
		label.Enabled = false
	end
end
```

## Source layout

| Module | Responsibility |
| --- | --- |
| `init.server.luau` | Toolbar button and dock widget; starts the app the first time the panel opens |
| `App` | Tab layout, status bar, panel lifetimes |
| `NodeStore` | Workspace data: root folder, groups, nodes, bounds, undo recording, change notifications |
| `NodeAppearance` | Node physics properties, appearance, label, visibility |
| `NodeTypes` | Type definitions stored in the place, and baking them onto nodes |
| `Actions` | User commands: placement, selection and camera focus, edits, fixes, input validation messages |
| `Spatial` | Raycasts, terrain voxel reads and overlap queries |
| `Validator` | Validation checks, run as a cancellable Promise |
| `NodesPanel`, `EditorPanel`, `TypesPanel`, `ValidationPanel`, `SettingsPanel` | Interface panels |
| `Ui`, `VirtualList` | Theme-aware UI builders, overlays (menus and prompts) and a virtualized list |
| `Settings`, `Status`, `Format`, `Constants`, `Types` | Shared definitions and helpers |

## Known limitations
- Type changes overwrite the look of every node of that type, including colors or sizes changed on individual nodes.
- Nodes are uniformly sized (one size value) and assumed unrotated when computing the resting height; rotated non-ball nodes may sit slightly into or above the ground after snapping.
- "Inside solid parts" has no automatic fix, because there is no general safe direction to push a node out.
- The terrain check samples the node's centre, so a large node can be partly sunk into terrain without being reported.
- Floating detection uses one downward ray from the node's centre, so a node over a narrow gap can be reported even though it overhangs nearby ground.
- Studio's own click-to-select in the viewport isn't expected to depend on collision groups; if it does in your Studio version, select nodes from the list instead.
- If a place already uses all available collision groups, the `NodeManagerNodes` group can't be registered (a warning is printed). Nodes then stay in `Default` and game raycasts can hit them.
