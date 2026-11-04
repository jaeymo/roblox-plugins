--!strict
local Constants = {
	PLUGIN_NAME = "NodeManager",

	ROOT_NAME = "Nodes",
	ROOT_TAG = "NodeManagerRoot",
	NODE_TAG = "NodeManagerNode",
	COLLISION_GROUP = "NodeManagerNodes",
	LABEL_NAME = "NodeLabel",
	TYPES_NAME = "NodeTypes",

	ATTRIBUTES = {
		TYPE = "NodeType",
		DISPLAY_NAME = "NodeDisplayName",
		IMAGE = "NodeImage",
		HIDDEN = "NodeHidden",
		BOUNDS_MIN = "BoundsMin",
		BOUNDS_MAX = "BoundsMax",
	},

	TYPE_ATTRIBUTES = {
		COLOR = "Color",
		SHAPE = "Shape",
		SIZE = "Size",
		IMAGE = "Image",
		GROUNDED = "Grounded",
	},

	FIELD_ATTRIBUTES = {
		VALUE_TYPE = "ValueType",
		DEFAULT = "Default",
		FILL_DEFAULT = "FillDefault",
		REQUIRED = "Required",
	},

	DEFAULT_APPEARANCE = {
		Color = Color3.fromRGB(176, 176, 188),
		Shape = Enum.PartType.Block,
		Size = 1.5,
		Image = "",
	},

	SHAPES = { Enum.PartType.Block, Enum.PartType.Ball, Enum.PartType.Cylinder },

	SWATCHES = {
		Color3.fromRGB(226, 76, 76),
		Color3.fromRGB(240, 156, 52),
		Color3.fromRGB(240, 208, 60),
		Color3.fromRGB(96, 200, 110),
		Color3.fromRGB(70, 200, 200),
		Color3.fromRGB(86, 148, 240),
		Color3.fromRGB(160, 100, 230),
		Color3.fromRGB(230, 110, 190),
		Color3.fromRGB(176, 176, 188),
		Color3.fromRGB(245, 245, 245),
	},

	VISIBLE_TRANSPARENCY = 0.2,
	LABEL_MAX_DISTANCE = 150,
	MIN_NODE_SIZE = 0.2,
	MAX_NODE_SIZE = 50,

	SURFACE_GAP = 0.05,
	TERRAIN_RESOLUTION = 4,
}

export type Constants = typeof(Constants)

return Constants
