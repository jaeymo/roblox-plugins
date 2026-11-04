--!strict
export type Appearance = {
	Color: Color3,
	Shape: Enum.PartType,
	Size: number,
	Image: string,
}

export type FieldValueType = "string" | "number" | "boolean"

export type FieldValue = string | number | boolean

export type Field = {
	Name: string,
	ValueType: FieldValueType,
	Default: FieldValue,
	FillDefault: boolean,
	Required: boolean,
	Instance: Configuration,
}

export type NodeType = {
	Name: string,
	Color: Color3,
	Shape: Enum.PartType,
	Size: number,
	Image: string,
	Grounded: boolean,
	Fields: { Field },
	Instance: Configuration,
}

export type Severity = "Error" | "Warning"

export type IssueKind = "Metadata" | "OutOfBounds" | "Buried" | "Embedded" | "Floating" | "NoGround" | "Duplicate"

export type Fix = {
	Label: string,
	Apply: (node: Part) -> (boolean, string?),
}

export type Issue = {
	Kind: IssueKind,
	Severity: Severity,
	Node: Part,
	Message: string,
	Related: { Part },
	Fix: Fix?,
}

export type Bounds = {
	Min: Vector3,
	Max: Vector3,
}

export type ScanOptions = {
	FloatTolerance: number,
	GroundSearchDistance: number,
	DuplicateTolerance: number,
	SurfaceSearchHeight: number,
}

export type GroupFilter = "All" | "Ungrouped" | Folder

return {}
