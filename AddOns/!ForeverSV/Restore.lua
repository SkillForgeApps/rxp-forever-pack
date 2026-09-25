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
-- Flips Settings > Gameplay > Gamepad (Alpha) > "Enable Gamepad UI (Alpha)" live, no reload. NOT GamePadEnable: that
-- one is controller INPUT (Gaz: turning it off "unplugs the controller" and the gamepad UI stays up).
-- The option is found in Blizzard's own settings panel by its label ("Gamepad UI") and flipped through the same
-- setting object the tickbox uses (setting:SetValue), so it behaves exactly like clicking the box. Fallback: a few
-- likely CVar names. What was found (label, variable, categories searched) is kept in
-- RXPCData.rxpForever.gamepadUIDiag so it can be read from the saved file. Not in combat. Shift-drag to move.
do
	local target, diag = nil, {}
	local function walk(cat, out)
		if not cat then return end
		out[#out + 1] = cat
		if cat.GetSubcategories then
			local ok, subs = pcall(cat.GetSubcategories, cat)
			if ok and type(subs) == "table" then for _, s in ipairs(subs) do walk(s, out) end end
		end
	end
	local function findByLabel()
		if not (SettingsPanel and SettingsPanel.GetAllCategories and SettingsPanel.GetLayout) then diag.panel = "no SettingsPanel API"; return end
		local cats = {}
		local ok, all = pcall(SettingsPanel.GetAllCategories, SettingsPanel)
		for _, c in ipairs(ok and all or {}) do walk(c, cats) end
		diag.categories = #cats
		for _, cat in ipairs(cats) do
			local ok2, layout = pcall(SettingsPanel.GetLayout, SettingsPanel, cat)
			if ok2 and layout and layout.GetInitializers then
				for _, init in ipairs(layout:GetInitializers() or {}) do
					local setting = (init.GetSetting and init:GetSetting()) or (init.data and init.data.setting)
					local name = setting and setting.GetName and setting:GetName()
					if type(name) == "string" and name:lower():find("gamepad ui", 1, true) then
						diag.label = name
						diag.variable = setting.GetVariable and tostring(setting:GetVariable()) or "?"
						return setting
					end
				end
			end
		end
	end
	local CANDIDATES = { "GamePadUIEnabled", "GamepadUIEnabled", "GamePadEnableUI", "GamePadUI", "gamePadUI",
		"enableGamepadUI", "useGamepadUI", "GamePadUseUI" }
	local function find()
		if target then return target end
		local s = findByLabel()
		if s then
			target = { setting = s, name = diag.label, var = diag.variable }
		elseif C_CVar and C_CVar.GetCVar then
			for _, n in ipairs(CANDIDATES) do
				if C_CVar.GetCVar(n) ~= nil then target = { cvar = n, name = n, var = n }; diag.cvar = n; break end
			end
		end
		if RXPCData then
			RXPCData.rxpForever = RXPCData.rxpForever or {}
			diag.found = target and target.name or "nothing"
			RXPCData.rxpForever.gamepadUIDiag = diag
		end
		return target
	end
	local function isOn()
		if not target then return false end
		if target.setting then
			local ok, v = pcall(target.setting.GetValue, target.setting)
			return ok and (v == true or v == 1 or v == "1")
		end
		return C_CVar.GetCVarBool(target.cvar)
	end
	local function setOn(v)
		if target.setting then return pcall(target.setting.SetValue, target.setting, v) end
		return pcall(C_CVar.SetCVar, target.cvar, v and "1" or "0")
	end

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
		if not find() then say("couldn't find the \"Enable Gamepad UI\" option - /reload and tell Claude.") return end
		if InCombatLockdown() then say("can't switch in combat - try again when combat ends.") return end
		local ok, err = setOn(not isOn())
		if not ok then say("the game refused the change (" .. tostring(err) .. ").") end
		if C_Timer then C_Timer.After(0.2, refresh) else refresh() end
	end)
	b:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
	b:SetScript("OnDragStop", b.StopMovingOrSizing)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		find()
		GameTooltip:AddLine("Gamepad UI: " .. (target and (isOn() and "|cff40ff40on|r" or "|cffff5555off|r") or "|cff888888not found|r"))
		GameTooltip:AddLine("Click to switch the controller interface on / off (no reload, not in combat). Controller input stays on.", 1, 1, 1, true)
		if target then GameTooltip:AddLine("Setting: " .. tostring(target.name) .. " (" .. tostring(target.var) .. ")", 0.7, 0.7, 0.7) end
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
			-- the settings panel registers its categories as the UI loads; look a moment after login
			if C_Timer then C_Timer.After(3, function() find(); refresh() end) else find(); refresh() end
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
