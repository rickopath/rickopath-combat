--!strict

export type EffectId = string

export type PresentParams = {
	CFrame: CFrame?,
	Attachment: BasePart?, -- client side only, never serialized - the effect just follows this part locally
	Target: Model?,
	Scale: number?,
	Color: Color3?, -- client side only, never serialized - bytenet doesn't even have a public color3 dataType
	-- caller-side overrides for PresentationClient.UseDefaultPresentation's VFX handling - crosses
	-- the network, so a server-fired OnHit effect can tune these too, not just a locally-predicted
	-- Activate call. both are OPTIONAL: omit them and the VFX template's own Studio attributes (or
	-- the built-in fallbacks) apply exactly like before - this is priority, not a replacement
	EmitCount: number?, -- burst size override, beats any "EmitCount" attribute on the template
	AttachToPartName: string?, -- part name on Target to attach to, beats any "AttachToPart" attribute
}

return {}
