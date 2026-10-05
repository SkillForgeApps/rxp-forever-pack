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

-- ===== Auctionator on/off icon (28 Sep, Gaz: "the errors with auctionator are endless ... if you cant fix it we will
-- keep auctionator off ... change the gamepad ui button on the mini map to swap to an auctionator on off button") =====
-- Replaces the Gamepad UI icon (25 Sep). Auctionator taints the gamepad UI (Settings window, AH tabs, buff timers - see
-- CLAUDE.md 27-28 Sep) and no fix held, so it stays off and is switched on only for an AH session. Click = enable or
-- disable Auctionator for all characters (C_AddOns, as !BugGrabber does) and reload, because addons only load or
-- unload at a reload. Coloured = on, grey = off. Shift-drag slides it round the minimap ring. The Gamepad UI switch is
-- still Blizzard's own tickbox: Settings > Gameplay > Gamepad.
do
	local ADDON = "Auctionator"
	local b = CreateFrame("Button", "ForeverAuctionatorButton", UIParent)
	b:SetSize(24, 24)
	b:SetFrameStrata("HIGH")
	b:SetClampedToScreen(true)
	b:SetMovable(true)
	b:RegisterForDrag("LeftButton")
	b:SetPoint("TOP", ForeverReloadButton, "BOTTOM", 0, -4)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local function exists() return C_AddOns and C_AddOns.GetAddOnInfo and C_AddOns.GetAddOnInfo(ADDON) ~= nil end
	local function isOn()
		-- no character argument = all characters, the same scope Enable/DisableAddOn below act on (30 Sep: asking with
		-- UnitName("player") could read 0 while it was on, so a click always "enabled" and it never switched off)
		return C_AddOns and C_AddOns.GetAddOnEnableState and (C_AddOns.GetAddOnEnableState(ADDON) or 0) > 0
	end
	local function refresh()
		local on = isOn()
		icon:SetDesaturated(not on)
		icon:SetAlpha(on and 1 or 0.6)
	end
	b:SetScript("OnClick", function()
		if not exists() then
			print("|cff33ff99Auctionator:|r not installed.")
			return
		end
		local wasOn = isOn()
		if wasOn then C_AddOns.DisableAddOn(ADDON) else C_AddOns.EnableAddOn(ADDON) end
		if C_AddOns.SaveAddOns then C_AddOns.SaveAddOns() end
		print("|cff33ff99Auctionator:|r switching " .. (wasOn and "OFF" or "ON") .. " (now reads " ..
			tostring(C_AddOns.GetAddOnEnableState(ADDON)) .. ") - reloading the UI")
		ReloadUI()
	end)
	b:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
	b:SetScript("OnDragStop", b.StopMovingOrSizing)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Auctionator: " .. (isOn() and "|cff40ff40on|r" or "|cffff5555off|r"))
		GameTooltip:AddLine("Click to switch it " .. (isOn() and "off" or "on") .. " and reload the UI.", 1, 1, 1, true)
		GameTooltip:AddLine("Keep it off when you're not at the auction house - it breaks the controller UI.", 1, 0.82, 0, true)
		GameTooltip:AddLine("Shift-drag to move.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_LOGIN")
	ev:SetScript("OnEvent", refresh)
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

-- ===== Find Minerals / Find Herbs icon (29 Sep, Gaz: "is there some way to add find minerals to the minimap as an icon,
-- I keep forgetting to turn it on") =====
-- Click = switch the character's gathering tracking on or off (Find Minerals, else Find Herbs) with C_Minimap.SetTracking -
-- the call Blizzard's own tracking menu makes (Blizzard_Minimap/Mainline/Minimap.lua), not a protected cast. It is also
-- switched on by itself at login and after a resurrection, but only when nothing else is being tracked (a hunter's beast
-- tracking is never overridden). Coloured = on, grey = off; hidden on characters that know neither. Ring slot: 206 deg.
do
	local SPELLS = { 2580, 2383 }   -- Find Minerals, Find Herbs
	local b = CreateFrame("Button", "ForeverTrackingButton", UIParent)
	b:SetSize(24, 24)
	b:SetFrameStrata("HIGH")
	b:SetClampedToScreen(true)
	b:SetMovable(true)
	b:RegisterForDrag("LeftButton")
	b:SetPoint("TOP", ForeverReloadButton, "BOTTOM", 0, -32)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture("Interface\\Icons\\Spell_Nature_Earthquake")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local function find()
		if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo) then return end
		local byId = {}
		local otherActive = false
		for i = 1, C_Minimap.GetNumTrackingTypes() do
			local info = C_Minimap.GetTrackingInfo(i)
			if info then
				if info.spellID and (info.spellID == SPELLS[1] or info.spellID == SPELLS[2]) then
					byId[info.spellID] = { index = i, info = info }
				elseif info.active and info.type == "spell" then
					otherActive = true
				end
			end
		end
		return byId[SPELLS[1]] or byId[SPELLS[2]], otherActive
	end
	local function refresh()
		local t = find()
		b:SetShown(t ~= nil)
		if not t then return end
		if t.info.texture then icon:SetTexture(t.info.texture) end
		icon:SetDesaturated(not t.info.active)
		icon:SetAlpha(t.info.active and 1 or 0.6)
	end
	local function set(on)
		local t = find()
		if not t then return end
		pcall(C_Minimap.SetTracking, t.index, on)
		if C_Timer then C_Timer.After(0.5, refresh) end
	end
	local function autoOn()
		local t, otherActive = find()
		if t and not t.info.active and not otherActive and not UnitIsDeadOrGhost("player") then set(true) end
		refresh()
	end
	b:SetScript("OnClick", function()
		local t = find()
		if t then set(not t.info.active) end
	end)
	b:SetScript("OnEnter", function(self)
		local t = find()
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine((t and t.info.name or "Gathering tracking") .. ": " .. ((t and t.info.active) and "|cff40ff40on|r" or "|cffff5555off|r"))
		GameTooltip:AddLine("Click to switch it. It comes back on by itself at login and after you resurrect.", 1, 1, 1, true)
		GameTooltip:AddLine("Shift-drag to slide it round the minimap.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	ev:RegisterEvent("PLAYER_UNGHOST")
	ev:RegisterEvent("PLAYER_ALIVE")
	ev:RegisterEvent("MINIMAP_UPDATE_TRACKING")
	ev:SetScript("OnEvent", function(_, event)
		if event == "MINIMAP_UPDATE_TRACKING" then refresh()
		elseif C_Timer then C_Timer.After(2, autoOn) else autoOn() end
	end)
end

-- ===== Taint log on/off icon (30 Sep, Gaz: "you need to build an icon that turns it on and off - it takes too long to
-- type it after an error each time whilst trying to regain control of the interface") =====
-- One click = taintLog 11 (the level that names the addon line that taints; writes GBs while a window is open), the next
-- click = taintLog 0. It switches itself off after 45 seconds so it can't run away (a forgotten level 11 froze the game
-- on 30 Sep). Use it BEFORE the action that fails: click, do the thing (open the map, close it with B, accept a quest),
-- click again. Red = logging. Logs	aint.log is read by Claude afterwards. Ring slot 228 deg.
do
	local LEVEL, AUTO_OFF = "11", 45
	local b = CreateFrame("Button", "ForeverTaintLogButton", UIParent)
	b:SetSize(24, 24)
	b:SetFrameStrata("HIGH")
	b:SetClampedToScreen(true)
	b:SetMovable(true)
	b:RegisterForDrag("LeftButton")
	b:SetPoint("TOP", ForeverTrackingButton or ForeverReloadButton, "BOTTOM", 0, -4)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture("Interface\\Icons\\INV_Misc_Note_06")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local ring = b:CreateTexture(nil, "OVERLAY")
	ring:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	ring:SetBlendMode("ADD")
	ring:SetAllPoints()
	ring:SetVertexColor(1, 0.1, 0.1)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local token = 0
	local function get() return (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("taintLog")) or GetCVar("taintLog") end
	local function set(v)
		if not (pcall(C_CVar.SetCVar, "taintLog", v)) then pcall(ConsoleExec, "taintLog " .. v) end
	end
	local function isOn() local v = get() return v ~= nil and v ~= "0" end
	local function refresh()
		local on = isOn()
		ring:SetShown(on)
		icon:SetDesaturated(not on)
		icon:SetAlpha(on and 1 or 0.7)
	end
	local function say(msg) print("|cffff5555Taint log:|r " .. msg) end
	local function turn(on)
		token = token + 1
		set(on and LEVEL or "0")
		refresh()
		if isOn() ~= on then say("the game refused the change - type /console taintLog " .. (on and LEVEL or "0") .. " instead.") return end
		if on then
			say("ON (level " .. LEVEL .. "). Do the failing thing now, then click again. Switches itself off in " .. AUTO_OFF .. "s.")
			local mine = token
			if C_Timer then C_Timer.After(AUTO_OFF, function() if mine == token and isOn() then turn(false) say("auto-off after " .. AUTO_OFF .. "s.") end end) end
		else
			say("OFF. Tell Claude what you did.")
		end
	end
	b:SetScript("OnClick", function() turn(not isOn()) end)
	b:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
	b:SetScript("OnDragStop", b.StopMovingOrSizing)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Taint log: " .. (isOn() and "|cffff5555ON|r" or "off"))
		GameTooltip:AddLine("Click BEFORE the thing that breaks the controller UI, do it, click again. Auto-off after " .. AUTO_OFF .. "s.", 1, 1, 1, true)
		GameTooltip:AddLine("Shift-drag to move.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	SLASH_FOREVERTAINT1 = "/taint"
	SlashCmdList.FOREVERTAINT = function() turn(not isOn()) end
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_LOGIN")
	ev:SetScript("OnEvent", function()
		-- never start a session with the log left on (level 11 floods once a window is open)
		if isOn() then set("0") end
		refresh()
	end)
end

-- ===== Chat dump (1 Oct, Gaz: "add something that dumps the chat box or I have to keep screenshotting it") =====
-- /chatdump (or the ring icon) copies the last 300 lines of the main chat window - addon prints included - into the saved
-- variable ForeverSVRing.chatDump and reloads the UI, which is what makes the game write the file to disk
-- (WTF\\Account\\...\\SavedVariables\\!ForeverSV.lua). Claude reads it from there. Colour codes and links are stripped.
-- /chatdump 100 = last 100 lines only. The buffer is also saved automatically on every /reload and logout.
do
	local LIMIT = 300
	local b = CreateFrame("Button", "ForeverChatDumpButton", UIParent)
	b:SetSize(24, 24)
	b:SetFrameStrata("HIGH")
	b:SetClampedToScreen(true)
	b:SetMovable(true)
	b:RegisterForDrag("LeftButton")
	b:SetPoint("TOP", ForeverTaintLogButton or ForeverTrackingButton or ForeverReloadButton, "BOTTOM", 0, -4)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local function clean(t)
		if type(t) ~= "string" then return nil end
		if issecretvalue and issecretvalue(t) then return "<secret>" end
		t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H[^|]*|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
		return t
	end
	local function capture(n)
		local out = {}
		local cf = DEFAULT_CHAT_FRAME or ChatFrame1
		if not (cf and cf.GetNumMessages and cf.GetMessageInfo) then return out end
		local total = cf:GetNumMessages()
		for i = math.max(1, total - (n or LIMIT) + 1), total do
			local ok, text = pcall(cf.GetMessageInfo, cf, i)
			local line = ok and clean(text)
			if line and line ~= "" then out[#out + 1] = line end
		end
		return out
	end
	local function save(n)
		ForeverSVRing = type(ForeverSVRing) == "table" and ForeverSVRing or {}   -- already a saved variable: no restart needed
		ForeverSVRing.chatDump = { time = date("%Y-%m-%d %H:%M:%S"), lines = capture(n) }
		return #ForeverSVRing.chatDump.lines
	end
	local function dump(n)
		local count = save(n)
		print("|cff66ccffchat dump:|r " .. count .. " lines saved - reloading so the file is written")
		ReloadUI()   -- directly: from a C_Timer callback it is blocked (ADDON_ACTION_BLOCKED Reload), only a click/slash may call it
	end
	b:SetScript("OnClick", function() dump() end)
	b:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
	b:SetScript("OnDragStop", b.StopMovingOrSizing)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Dump chat for Claude")
		GameTooltip:AddLine("Saves the last " .. LIMIT .. " chat lines and reloads the UI so the file is written. Claude reads it - no screenshot needed.", 1, 1, 1, true)
		GameTooltip:AddLine("Shift-drag to move.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	SLASH_FOREVERCHATDUMP1 = "/chatdump"
	SlashCmdList.FOREVERCHATDUMP = function(msg) dump(tonumber((msg or ""):match("%d+"))) end
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_LOGOUT")
	ev:SetScript("OnEvent", function() pcall(save) end)   -- every reload / logout keeps the latest chat on disk too
end

-- ===== Real quest XP, straight from the game (1 Oct, Gaz: "dungeon quest XP is heavily increased in Forever") =====
-- Wowhead's Forever pages show raw 'xp' fields (Classic values) next to a calculated figure (about 2.9x for dungeon quests), so
-- neither is trusted. Whenever a quest window opens - accept (QUEST_DETAIL), progress, hand-in (QUEST_COMPLETE) - the game's own
-- GetRewardXP() is stored in ForeverSVRing.questXP[questID] = { xp, title, level (player), when } and written to disk on the
-- next reload / /chatdump. /questxp prints it for every quest in the log (C_QuestLog.GetQuestLogRewardXP).
do
	local function store(questID, xp, title)
		if not questID or questID == 0 or type(xp) ~= "number" then return end
		if issecretvalue and (issecretvalue(xp) or issecretvalue(questID)) then return end
		ForeverSVRing = type(ForeverSVRing) == "table" and ForeverSVRing or {}
		ForeverSVRing.questXP = type(ForeverSVRing.questXP) == "table" and ForeverSVRing.questXP or {}
		ForeverSVRing.questXP[questID] = { xp = xp, title = title, level = UnitLevel("player"), when = date("%Y-%m-%d %H:%M") }
	end
	local ev = CreateFrame("Frame")
	for _, e in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do ev:RegisterEvent(e) end
	ev:SetScript("OnEvent", function()
		pcall(function()
			local id = GetQuestID and GetQuestID()
			local xp = GetRewardXP and GetRewardXP()
			local title = GetTitleText and GetTitleText()
			if id and id ~= 0 then store(id, xp, title) end
		end)
	end)
	SLASH_FOREVERQUESTXP1 = "/questxp"
	SlashCmdList.FOREVERQUESTXP = function()
		local n = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
		local lines = 0
		for i = 1, n do
			local info = C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.questID then
				local ok, xp = pcall(C_QuestLog.GetQuestLogRewardXP, info.questID)
				if ok and type(xp) == "number" then
					store(info.questID, xp, info.title)
					print(string.format("|cff66ccffquestxp:|r %d  %s  = %d XP", info.questID, tostring(info.title), xp))
					lines = lines + 1
				end
			end
		end
		print("|cff66ccffquestxp:|r " .. lines .. " quests in your log. Click the chat dump icon and I can read them.")
	end
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
		{ "RXPForeverToggleButton", 250 }, { "ForeverReloadButton", 272 }, { "ForeverAuctionatorButton", 294 },
		{ "ForeverGearTodoButton", 316 }, { "ForeverGearSnapshotButton", 338 },
		{ "RXPForeverStepBackButton", 0 }, { "RXPForeverStepNextButton", 22 },   -- guide step back / forward (29 Sep)
		{ "ForeverTrackingButton", 206 },                                        -- Find Minerals / Herbs (29 Sep)
		{ "ForeverTaintLogButton", 228 },                                        -- taint log on/off (30 Sep)
		{ "ForeverChatDumpButton", 184 },                                        -- chat dump for Claude (1 Oct)
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
