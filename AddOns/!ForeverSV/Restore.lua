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
