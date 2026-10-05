-- Gaz pack version, shown after RestedXP's own version in the guide window footer ("RXP Beta v4.11.9 0/23  Gaz V1.128").
-- The number is the repo commit count; tools/bump_gaz_version.py sets it - run it before every commit/push.
local GAZ_VERSION = "V1.128"

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	local R = _G.RXP
	local text = R and R.RXPFrame and R.RXPFrame.Footer and R.RXPFrame.Footer.text
	if not text then return end
	local busy = false
	local function tag()
		if busy then return end
		local cur = text:GetText()
		if not cur or cur:find("Gaz V", 1, true) then return end
		busy = true
		text:SetText(cur .. "  |cff00ff96Gaz " .. GAZ_VERSION .. "|r")
		busy = false
	end
	hooksecurefunc(text, "SetText", tag)
	tag()
end)
