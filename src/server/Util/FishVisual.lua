--!strict
--[[
	FishVisual — builds the 3D fish model.

	Owns: constructing a fish Model from species + variant (body, tail,
	fins, eyes). Used for tank displays, river swimmers, and carry visuals.

	Exposes:
	- Build(speciesId, variantId, scale, uid) -> Model

	Step 4 will fill this in (alongside the fish registry).
]]

local FishVisual = {}

function FishVisual.Build(
	_speciesId: string,
	_variantId: string,
	_scale: number,
	_uid: string?
): Model
	local model = Instance.new("Model")
	model.Name = "Fish"
	return model
end

return FishVisual
