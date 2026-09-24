-- !ForeverSV: the Forever beta client writes addon saved variables to disk but never reads them back
-- (proven 23 Sep 2026). the sync helper (ForeverSync.ps1 / rxp_state_sync.py) mirrors the files WoW writes into Data.lua (ForeverSVData);
-- this addon loads first (the "!" sorts before every other addon) and puts each saved global back
-- whenever the client has left it empty. If the client ever loads saved variables properly again,
-- nothing here overrides real data.

-- ===== Emergency reload: button by the minimap + Ctrl+Shift+R =====
-- When the gamepad input stack breaks (tainted by an addon) chat can stop taking input, so /reload is
-- impossible. This needs no chat: click the button, or press Ctrl+Shift+R (only bound if that key is free).
do
	local b = CreateFrame("Button", "ForeverReloadButton", UIParent)
	b:SetSize(24, 24)
	b:SetFrameStrata("HIGH")
	if Minimap then b:SetPoint("TOPRIGHT", Minimap, "BOTTOMLEFT", 8, 8) else b:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -190, -170) end
	b:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:SetMovable(true)
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
	b:SetScript("OnDragStop", b.StopMovingOrSizing)
	b:SetScript("OnClick", function() ReloadUI() end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Reload UI")
		GameTooltip:AddLine("Click (or Ctrl+Shift+R) when the controller or chat stops responding.", 1, 1, 1, true)
		GameTooltip:AddLine("Shift-drag to move.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local kf = CreateFrame("Frame")
	kf:RegisterEvent("PLAYER_LOGIN")
	kf:SetScript("OnEvent", function()
		local action = GetBindingAction and GetBindingAction("CTRL-SHIFT-R")
		if (action == nil or action == "") and not InCombatLockdown() then
			SetOverrideBindingClick(b, true, "CTRL-SHIFT-R", "ForeverReloadButton")
		end
	end)
end

local data = ForeverSVData
if type(data) ~= "table" then return end

local function isEmpty(name, v)
	if v == nil then return true end
	if type(v) ~= "table" then return false end
	for k in pairs(v) do
		if k ~= "__dbversion" then return false end -- Auctionator stamps a version into an otherwise empty DB
	end
	return true
end

local restored = {}   -- addon -> savedAt

local function apply(addon)
	local entry = data[addon]
	if type(entry) ~= "table" or type(entry.vars) ~= "table" then return end
	for name, value in pairs(entry.vars) do
		if isEmpty(name, _G[name]) then
			_G[name] = value
			restored[addon] = entry.savedAt or 0
		end
	end
end

-- 1) At load, before any other addon's files run.
for addon in pairs(data) do apply(addon) end

-- 2) Again as each addon finishes loading, in case the client resets its globals then. Our frame registered
--    first, so this runs before the addon's own ADDON_LOADED / PLAYER_LOGIN handlers.
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		if data[name] then apply(name) end
	else
		for addon in pairs(data) do apply(addon) end
		local list = {}
		for addon, at in pairs(restored) do
			list[#list + 1] = string.format("%s (saved %s)", addon, at > 0 and date("%d %b %H:%M", at) or "?")
		end
		if #list > 0 then
			table.sort(list)
			print("|cff33ff99Saved data restored by the helper:|r " .. table.concat(list, ", "))
		end
	end
end)
