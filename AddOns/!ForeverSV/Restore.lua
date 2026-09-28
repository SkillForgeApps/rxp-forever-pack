-- !ForeverSV: the Forever beta client writes addon saved variables to disk but never reads them back
-- (proven 23 Sep 2026). rxp_state_sync.py mirrors the files WoW writes into Data.lua (ForeverSVData);
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

-- ===== Gamepad UI on/off icon (25 Sep, Gaz: "add the icon back, I understand it will reload the ui but its still
-- quicker than opening options unticking etc when im in a dungeon or stress situation") =====
-- Does exactly what Blizzard's Settings > Gameplay > Gamepad > "Enable Gamepad UI (Alpha)" tickbox does
-- (Blizzard_SettingsDefinitions_Shared/Gamepad.lua: GAMEPAD_INTERFACE_TOGGLE sets the CVar InputDeviceInterfaceStyle
-- to Enum.InputDeviceInterfaceType.Gamepad or .Mkb), then reloads the UI straight away, because the gamepad UI is
-- built at UI load. One click, or Ctrl+Shift+G (only bound if that key is free). Controller INPUT (GamePadEnable) is
-- never touched here - the first version flipped that and left the controller dead. Shift-drag to move.
do
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
	local function uiOn() return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() end
	local function refresh()
		local on = uiOn()
		icon:SetDesaturated(not on)
		icon:SetAlpha(on and 1 or 0.6)
	end
	b:SetScript("OnClick", function()
		local T = Enum and Enum.InputDeviceInterfaceType
		if not (T and T.Gamepad and T.Mkb) then
			print("|cff33ff99Gamepad UI:|r this client has no interface-style setting - use Settings > Gameplay > Gamepad.")
			return
		end
		local ok, err = pcall(C_CVar.SetCVar, "InputDeviceInterfaceStyle", uiOn() and T.Mkb or T.Gamepad)
		if not ok then
			print("|cff33ff99Gamepad UI:|r the game refused the switch (" .. tostring(err) .. ").")
			return
		end
		ReloadUI()
	end)
	b:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
	b:SetScript("OnDragStop", b.StopMovingOrSizing)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Gamepad UI: " .. (uiOn() and "|cff40ff40on|r" or "|cffff5555off|r"))
		GameTooltip:AddLine("Click (or Ctrl+Shift+G) to switch it " .. (uiOn() and "off" or "on") ..
			" and reload the UI straight away.", 1, 1, 1, true)
		GameTooltip:AddLine("Shift-drag to move.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_LOGIN")
	ev:SetScript("OnEvent", function()
		refresh()
		local action = GetBindingAction and GetBindingAction("CTRL-SHIFT-G")
		if (action == nil or action == "") and not InCombatLockdown() then
			SetOverrideBindingClick(b, true, "CTRL-SHIFT-G", "ForeverGamepadButton")
		end
	end)
end

-- ===== Mouse buttons back with the Gamepad UI on (25 Sep, Gaz: "keep it as is but add a train/interact ui button for
-- the mouse"; then "on opening my mailbox I'm back to the same issue, can you implement it on the mail box etc") =====
-- With "Enable Gamepad UI (Alpha)" on, Blizzard hides each window's mouse buttons (Train, Send, Reply, Close...) in the
-- window's InitializeGamepad and leaves only the footer prompts. Blizzard runs that init ONCE, when the window is
-- created (InputUtil.RegisterGamepadInit calls it straight away when the gamepad UI is on), and again only on a
-- gamepad-UI switch, which reloads the UI. So each button is shown once after its window exists. The gamepad UI and
-- footer stay as they are, and Blizzard's normal show/hide rules still apply afterwards (quest Decline, book page
-- arrows...). List taken from every InitializeGamepad in Blizzard's Forever UI source (Gethe/wow-ui-source,
-- branch forever). Left out: buttons Blizzard hides again on every update while the gamepad UI is on (vendor page
-- arrows, Report Spam), and glue / chat / raid-frame / buff bits. A path that doesn't exist on this client is skipped.
do
	local BUTTONS = {
		-- trainer
		"ClassTrainerTrainButton", "ClassTrainerFrame.CloseButton",
		-- mailbox: inbox, open letter, send
		"MailFrame.CloseButton", "InboxFrame.OpenAllMail", "InboxFrame.PrevPageButton", "InboxFrame.NextPageButton",
		"OpenMailFrame.CloseButton", "OpenMailFrame.ReplyButton", "OpenMailFrame.DeleteButton", "OpenMailFrame.CancelButton",
		"SendMailFrame.SendButton", "SendMailFrame.CancelButton",
		-- vendor
		"MerchantFrameCloseButton",
		-- quest giver and gossip
		"QuestFrameAcceptButton", "QuestFrameDeclineButton", "QuestFrameCompleteButton", "QuestFrameCompleteQuestButton",
		"QuestFrameGoodbyeButton", "QuestFrameGreetingGoodbyeButton", "QuestFrameCloseButton",
		"GossipFrame.GreetingPanel.GoodbyeButton", "GossipFrameCloseButton",
		-- books / letters, loot, master loot
		"ItemTextFrame.CloseButton", "ItemTextPrevPageButton", "ItemTextNextPageButton",
		"LootFrame.ClosePanelButton", "MasterLooterFrame.CloseButton",
		-- character, equipment sets, bags, inspect
		"CharacterFrameCloseButton", "PaperDollFrame.EquipmentManagerPane.EquipSet",
		"PaperDollFrame.EquipmentManagerPane.SaveSet", "ContainerFrameCombinedBags.CloseButton", "InspectFrame.CloseButton",
		-- professions, spellbook
		"ProfessionsFrame.CloseButton", "ProfessionsFrame.CraftingPage.LinkButton",
		"PlayerSpellsFrame.CloseButton", "PlayerSpellsFrame.TabSystem",
		"PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame.PagingControls.PrevPageButton",
		"PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame.PagingControls.NextPageButton",
		-- world map and quest log details
		"WorldMapFrame.CloseButton", "QuestMapFrame.QuestsFrame.DetailsFrame.BackFrame.BackButton",
		"QuestMapFrame.QuestsFrame.DetailsFrame.AbandonButton", "QuestMapFrame.QuestsFrame.DetailsFrame.ShareButton",
		"QuestMapFrame.QuestsFrame.DetailsFrame.TrackButton",
		-- split stack, colour picker
		"StackSplitFrame.OkayButton", "StackSplitFrame.CancelButton",
		"ColorPickerFrame.Footer.OkayButton", "ColorPickerFrame.Footer.CancelButton",
	}
	local done = {}
	local function resolve(path)
		local t = _G
		for part in path:gmatch("[^%.]+") do
			if type(t) ~= "table" then return nil end
			t = t[part]
		end
		return (type(t) == "table" and t.Show) and t or nil
	end
	local function pass()
		if not (InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()) then return end
		for _, path in ipairs(BUTTONS) do
			if not done[path] then
				local btn = resolve(path)
				if btn then
					done[path] = true
					pcall(btn.Show, btn)
				end
			end
		end
		-- the trainer's Train button sits where the gamepad footer is; keep it clickable above it
		if ClassTrainerTrainButton and ClassTrainerFrame and not done.trainLevel then
			done.trainLevel = true
			ClassTrainerTrainButton:SetFrameLevel(ClassTrainerFrame:GetFrameLevel() + 20)
		end
	end
	-- Gamepad UI on but controller input (GamePadEnable) off = a controller UI the controller can't drive. Happened
	-- 25 Sep: the first version of the removed gamepad icon flipped GamePadEnable and it was left at 0 in Config.wtf.
	-- Put input back on at login / reload.
	local function inputGuard()
		if not (InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()) then return end
		if not (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("GamePadEnable") == "0") then return end
		if pcall(C_CVar.SetCVar, "GamePadEnable", "1") then
			print("|cff33ff99Gamepad:|r controller input was switched off while the Gamepad UI is on - switched it back on.")
		end
	end
	pass()
	local f = CreateFrame("Frame")
	f:RegisterEvent("ADDON_LOADED")      -- load-on-demand windows (trainer, professions, inspect...) appear here
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function(_, event)
		pass()
		if event == "PLAYER_LOGIN" then inputGuard() end
	end)
end

-- ===== Our icons on the minimap ring (26 Sep, Gaz: "getting quite the collection of mini icons, can you move them to
-- the outer ring of the minimap") =====
-- The guide book (RXPForever), reload, gamepad UI, to-do list and gear snapshot icons (ForeverGear) sit on the ring,
-- round the bottom from the potion icon towards the moon. Shift-drag slides an icon round the ring; where it's
-- dropped is kept in ForeverSVRing (account-wide). Each addon still places its own icon first (and the book re-places
-- itself on every loading screen), so this runs a frame after each loading screen and wins. An addon that isn't
-- installed is skipped.
do
	local ICONS = {   -- name, default angle in degrees (0 = right, 90 = top, counter-clockwise)
		{ "RXPForeverToggleButton", 250 }, { "ForeverReloadButton", 272 }, { "ForeverGamepadButton", 294 },
		{ "ForeverGearTodoButton", 316 }, { "ForeverGearSnapshotButton", 338 },
	}
	local function saved() ForeverSVRing = type(ForeverSVRing) == "table" and ForeverSVRing or {} return ForeverSVRing end
	local function put(b, deg)
		-- centre on the ring edge; offsets are in the icon's own units (it's parented to UIParent, the map may be scaled)
		local r = (Minimap:GetWidth() / 2 + 4) * Minimap:GetEffectiveScale() / b:GetEffectiveScale()
		local a = math.rad(deg)
		b:ClearAllPoints()
		b:SetPoint("CENTER", Minimap, "CENTER", r * math.cos(a), r * math.sin(a))
	end
	local function follow(self)   -- while shift-dragging: the angle from the minimap centre to the cursor
		local mx, my = Minimap:GetCenter()
		local s = Minimap:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		self.ringDeg = math.deg(math.atan2(cy / s - my, cx / s - mx)) % 360
		put(self, self.ringDeg)
	end
	local function ring()
		if not Minimap then return end
		for _, e in ipairs(ICONS) do
			local b = _G[e[1]]
			if b then
				if not b.foreverRing then
					b.foreverRing = true
					b:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:SetScript("OnUpdate", follow) end end)
					b:SetScript("OnDragStop", function(self)
						self:SetScript("OnUpdate", nil)
						if self.ringDeg then saved()[e[1]] = self.ringDeg end
					end)
				end
				put(b, saved()[e[1]] or e[2])
			end
		end
	end
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:SetScript("OnEvent", function() if C_Timer then C_Timer.After(0, ring) else ring() end end)
end

-- ===== Addon pages in the Settings window must not taint it (27 Sep, Gaz: ticking "Auto Sell Junk" in RXP's options
-- then closing the window -> "fatality" + dead controller; taint.log level 11, 22:48) =====
-- Blizzard calls every addon page's OnRefresh when the Settings window opens (CallRefreshOnCanvases,
-- Blizzard_SettingsPanel.lua:607) and its OnCommit when it closes (CommitCanvases, :592), directly. RXP's options page
-- (AceGUI BlizOptionsGroup: OnCommit/OnDefault/OnRefresh) and Auctionator's pages (PanelConfig.lua:16-18) set both, so
-- the rest of the open - including the gamepad scan of the window's buttons (SmartNavigation FindButtons) - and the
-- close ran as addon code; closing then hit SetPreferredGamepadInteractTarget "blocked" with Auctionator blamed.
-- Each addon page registered after this file loads (we load first) gets its OnRefresh moved to the page's OnShow and
-- its OnCommit to the page's OnHide: script handlers don't pass their taint back to Blizzard's code, and both addons
-- still get the call at the same moment. OnDefault is left alone (only runs when "Defaults" is pressed).
-- Second half (22:58, the move alone didn't stop it - 22:55:11 same error with it loaded): Auctionator creates its pages
-- as SHOWN children of the Settings window at load (Source/Config/InitializeFrames.lua:3, Configuration.lua:7), so they
-- sit in the window whether or not their page is open. Ticking an RXP option rebuilds RXP's page, the gamepad
-- navigation rescans the window's buttons (SmartNavigation FindButtons: "tainted by Auctionator while reading field
-- 151") and from then on runs as Auctionator's code. So every addon page is hidden at login; Blizzard shows a page
-- itself when it is selected. (Auctionator's top page overrides Show with an empty function, so that one landing page
-- may stay blank - its sub-pages hold the options.)
do
	local MOVE = { OnRefresh = "OnShow", OnCommit = "OnHide" }
	local pages = {}
	local function guard(frame)
		if type(frame) ~= "table" or not frame.HookScript then return end
		local addonPage = false
		for field, script in pairs(MOVE) do
			local fn = rawget(frame, field)
			if type(fn) == "function" and not issecurevariable(frame, field) then
				addonPage = true   -- an addon set this page's callbacks; Blizzard's own pages never get here
				frame[field] = nil
				frame:HookScript(script, function(self) pcall(fn, self) end)
			end
		end
		if addonPage then table.insert(pages, frame) end
	end
	if Settings and Settings.RegisterCanvasLayoutCategory then
		hooksecurefunc(Settings, "RegisterCanvasLayoutCategory", function(frame) guard(frame) end)
		hooksecurefunc(Settings, "RegisterCanvasLayoutSubcategory", function(_, frame) guard(frame) end)
	end
	local function hideAll()
		if SettingsPanel and SettingsPanel:IsShown() then return end   -- never while the window is open
		for _, frame in ipairs(pages) do
			if frame.IsShown and frame:IsShown() then pcall(frame.Hide, frame) end
		end
	end
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function()
		hideAll()
		if C_Timer then C_Timer.After(2, hideAll) end   -- pages added a little after login
	end)
end

-- ===== Auctionator's pages out of the Settings window (27 Sep 23:05) =====
-- Proven by Gaz: with Auctionator switched off, ticking an RXP option and closing Settings no longer kills the
-- controller; with it on, it still did even with the block above. Auctionator parents all its option pages to
-- SettingsPanel (top page Config/Frame.xml OnLoad -> Configuration.lua:7; sub-pages Config/InitializeFrames.lua:3), so
-- they are inside the window's frame tree and the gamepad navigation's button scan runs into them. Move every
-- AuctionatorConfig* page into a hidden frame of ours: Blizzard's own pages and RXP's stay as they are. Auctionator's
-- options are still in its Auction House tab; its Settings pages show empty. Runs after Auctionator's ADDON_LOADED and
-- at login, so it works whichever of us handles the event first.
do
	local holder = CreateFrame("Frame")
	holder:Hide()
	local function evict()
		if not SettingsPanel or SettingsPanel:IsShown() then return end
		for _, c in ipairs({ SettingsPanel:GetChildren() }) do
			local name = c.GetName and c:GetName()
			if name and (name:find("^AuctionatorConfig") or name == "AuctionatorConfigurationFrameTemplate") then
				pcall(c.SetParent, c, holder)
			end
		end
	end
	local f = CreateFrame("Frame")
	f:RegisterEvent("ADDON_LOADED")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function(_, event, name)
		if event == "PLAYER_LOGIN" or name == "Auctionator" then
			if C_Timer then C_Timer.After(0, evict) else evict() end
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
