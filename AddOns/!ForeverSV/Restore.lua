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

-- ===== Gamepad UI on/off button (25 Sep, Gaz: "an add on that turns off the gamepad ui without reloading the ui, a
-- small icon I can click") =====
-- Flips the client's gamepad master switch (the setting the Settings > Gamepad option writes), live, no reload.
-- The switch is found at login from the client's own list of settings: GamePadEnable if it exists, otherwise the
-- first gamepad setting whose name says Enable/Enabled/Active. Every gamepad setting found (name = value) is kept in
-- RXPCData.rxpForever.gamepadCVars so it can be read from the saved file. Not in combat. If the game refuses the
-- change (protected setting), chat says so and nothing else happens. Shift-drag to move.
do
	local cvarName
	local function findSwitch()
		local found, names = {}, {}
		if C_Console and C_Console.GetAllCommands then
			local ok, cmds = pcall(C_Console.GetAllCommands)
			if ok and type(cmds) == "table" then
				for _, c in ipairs(cmds) do
					local n = c.command
					if type(n) == "string" and n:lower():find("gamepad", 1, true) then
						names[#names + 1] = n
						local v = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(n)
						if v ~= nil then found[n] = v end
					end
				end
			end
		end
		if RXPCData then
			RXPCData.rxpForever = RXPCData.rxpForever or {}
			RXPCData.rxpForever.gamepadCVars = found
		end
		if C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("GamePadEnable") ~= nil then return "GamePadEnable" end
		table.sort(names)
		for _, n in ipairs(names) do
			if found[n] ~= nil and (n:find("Enable") or n:find("Active")) then return n end
		end
	end
	local function isOn() return cvarName and C_CVar.GetCVarBool(cvarName) end

	local b = CreateFrame("Button", "ForeverGamepadButton", UIParent)
	b:SetSize(24, 24)
	b:SetFrameStrata("HIGH")
	b:SetClampedToScreen(true)
	b:SetMovable(true)
	b:RegisterForDrag("LeftButton")
	b:SetPoint("TOP", ForeverReloadButton, "BOTTOM", 0, -4)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture("Interface\\Icons\\INV_Gizmo_01")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local function refresh()
		local on = isOn()
		icon:SetDesaturated(not on)
		icon:SetAlpha(on and 1 or 0.6)
	end
	local function say(msg) print("|cff33ff99Gamepad UI:|r " .. msg) end
	b:SetScript("OnClick", function()
		if not cvarName then say("this client has no gamepad on/off setting I can find.") return end
		if InCombatLockdown() then say("can't switch in combat - try again when combat ends.") return end
		local want = isOn() and "0" or "1"
		local ok, err = pcall(C_CVar.SetCVar, cvarName, want)
		if not ok then say("the game refused the change (" .. tostring(err) .. ").") end
		if C_Timer then C_Timer.After(0.2, refresh) else refresh() end
	end)
	b:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
	b:SetScript("OnDragStop", b.StopMovingOrSizing)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Gamepad UI: " .. (cvarName and (isOn() and "|cff40ff40on|r" or "|cffff5555off|r") or "|cff888888not found|r"))
		GameTooltip:AddLine("Click to switch the controller interface on / off (no reload, not in combat).", 1, 1, 1, true)
		if cvarName then GameTooltip:AddLine("Setting: " .. cvarName, 0.7, 0.7, 0.7) end
		GameTooltip:AddLine("Shift-drag to move.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_LOGIN")
	ev:RegisterEvent("CVAR_UPDATE")
	ev:RegisterEvent("ADDON_ACTION_FORBIDDEN")
	ev:RegisterEvent("ADDON_ACTION_BLOCKED")
	ev:SetScript("OnEvent", function(_, event, a1, a2)
		if event == "PLAYER_LOGIN" then
			cvarName = findSwitch()
			refresh()
		elseif event == "CVAR_UPDATE" then
			refresh()
		elseif (event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED") and a1 == "!ForeverSV" then
			say("the game blocked " .. tostring(a2) .. " - the gamepad switch can't be flipped by an addon on this client.")
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
