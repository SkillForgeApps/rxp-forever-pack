-- RestedXP Forever Catch-up
--
-- RXP only evaluates the CURRENT step and advances one step at a time when every element in it completes.
-- Quest elements complete themselves from the quest log, but goto / vendor / buy / train / destroy elements
-- only complete on the physical action, so a character joining a guide part-way stalls on the first such step.
--
-- /rxpcatchup walks the whole current guide and flags every step that is already satisfied:
--   * a step whose quest elements are all met by live state (accept -> turned in or on log,
--     turnin -> turned in, complete -> turned in or objectives finished)
--   * a step whose quests are all GREY to the player (trivial XP)
--   * every step before the first outstanding quest step (travel, vendor, train ...)
-- Flags are stored per guide in RXPCData.rxpForever and re-applied whenever RXP activates a step, so RXP's own
-- engine hops over them - now and after a /reload. Manual skips are never removed.
-- If the whole guide is satisfied, RXP moves on to the guide's #next and the scan repeats there.
--
-- /rxpcatchup clear   forgets the flags for the current guide.

local RXP -- RestedXP's addon table, exposed as _G.RXP

-- Storage. The client was found NOT to load this addon's own per-character saved variable (RXPForeverDB)
-- on the Forever beta, while RestedXP's RXPCData loads reliably and is in memory before this file runs.
-- So all state lives in RXPCData.rxpForever; RXPForeverDB is kept only as a mirror.
local function DB()
	if RXPCData then
		RXPCData.rxpForever = RXPCData.rxpForever or {}
		return RXPCData.rxpForever
	end
	RXPForeverDB = RXPForeverDB or {}
	return RXPForeverDB
end

-- ===== State injection =====
-- The beta client does not read saved variables back (per-character or account), so every session starts
-- empty. The helper script rxp_state_sync.py mirrors WoW's last written saved files into State.lua, which
-- the client DOES read on every load. When RXPCData shows no sign of having been loaded, take the mirror.
local function injectState()
	local state = _G.RXPForeverState
	if type(state) ~= "table" or not RXPCData then return end
	local name = UnitName("player")
	if not name then return end
	local key = name:gsub(" ", "-")
	local rec = state[key]
	local fresh = RXPCData.rxpForever == nil and (RXPCData.guideProgress == nil or next(RXPCData.guideProgress) == nil)
	-- a brand-new character (level 1, no XP yet) must not take over an old saved record that has the same name (a deleted or
	-- re-rolled character), nor the account's "last guide" for that name: it starts with no guide and the player picks one
	if fresh and (UnitLevel("player") or 0) <= 1 and (UnitXP("player") or 0) == 0 then
		_G.RXPForeverNewChar = true
		fresh = false
		print("|cFF00ff96RXP catch-up:|r new level 1 character - not restoring any saved guide, pick a guide from the RXP window (right-click)")
	end
	local restored = {}
	if rec and rec.RXPCData and fresh then
		for _, k in ipairs({ "guideProgress", "stepSkip", "completedWaypoints", "currentGuideName", "currentGuideGroup",
			"currentStep", "currentStepId", "rxpForever", "flightPaths", "GA" }) do
			if rec.RXPCData[k] ~= nil then RXPCData[k] = rec.RXPCData[k] end
		end
		table.insert(restored, "character (saved " .. date("%H:%M", rec.savedAt or 0) .. ")")
	end
	local acct = state.account
	if acct and acct.RXPForeverAcct and (RXPForeverAcct == nil or next(RXPForeverAcct) == nil) then
		RXPForeverAcct = acct.RXPForeverAcct
		table.insert(restored, "account")
	end
	if #restored > 0 then
		print("|cFF00ff96RXP catch-up:|r state restored from the helper: " .. table.concat(restored, ", "))
	end
end
injectState()

local QUEST_TAGS = { accept = true, turnin = true, complete = true }

local function isTurnedIn(id)
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(id) end
	if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(id) end
	return false
end

local function isOnQuest(id)
	if C_QuestLog and C_QuestLog.IsOnQuest then return C_QuestLog.IsOnQuest(id) end
	return false
end

local function objectivesDone(id)
	if C_QuestLog and C_QuestLog.IsComplete then return C_QuestLog.IsComplete(id) end
	return false
end

-- quest level from the client; nil when the client has not cached that quest yet
local function questLevel(id)
	if C_QuestLog and C_QuestLog.GetQuestDifficultyLevel then
		local ok, level = pcall(C_QuestLog.GetQuestDifficultyLevel, id)
		if ok and level and level > 0 then return level end
	end
	if C_QuestLog and C_QuestLog.RequestLoadQuestByID then pcall(C_QuestLog.RequestLoadQuestByID, id) end
	return nil
end

local function isGrey(id)
	local level = questLevel(id)
	if not level or not GetQuestDifficultyColor or not QuestDifficultyColors or not QuestDifficultyColors.trivial then return false end
	local ok, c = pcall(GetQuestDifficultyColor, level)
	if not ok or not c then return false end
	local t = QuestDifficultyColors.trivial
	return math.abs(c.r - t.r) < 0.01 and math.abs(c.g - t.g) < 0.01 and math.abs(c.b - t.b) < 0.01
end

-- quests the player has retired by hand (e.g. not offered on Forever): every step for them counts as done
local function skippedQuests()
	local db = DB()
	db.skippedQuests = db.skippedQuests or {}
	return db.skippedQuests
end

-- "done", "grey" or "open" for one quest element
local function elementState(element)
	local id = element.questId
	if not id then return "done" end
	if skippedQuests()[id] then return "done" end
	if isTurnedIn(id) then return "done" end
	if element.tag == "accept" and isOnQuest(id) then return "done" end
	if element.tag == "complete" and isOnQuest(id) and objectivesDone(id) then return "done" end
	if isGrey(id) then return "grey" end
	return "open"
end

-- non-quest elements that can be verified from live state: items held and spells known.
-- returns nil when the element is not of a checkable kind
local function elementVerified(element)
	if element.tag == "collect" and element.id then
		local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(element.id, true)
			or GetItemCount and GetItemCount(element.id, true) or 0
		return count >= (element.qty or 1)
	end
	if element.tag == "train" and element.id then
		if C_Spell and C_Spell.IsSpellKnown then return C_Spell.IsSpellKnown(element.id) end
		if IsPlayerSpell then return IsPlayerSpell(element.id) end
		if IsSpellKnown then return IsSpellKnown(element.id) end
	end
	return nil
end

-- checkable, allVerified for a step's non-quest elements
local function verifiedState(step)
	local checkable, ok = 0, true
	for _, element in ipairs(step.elements or {}) do
		local v = elementVerified(element)
		if v ~= nil then
			checkable = checkable + 1
			if not v then ok = false end
		end
	end
	return checkable, ok
end

-- hasQuest, satisfied, greyCount for a step
local function stepState(step)
	local hasQuest, satisfied, grey = false, true, 0
	for _, element in ipairs(step.elements or {}) do
		if QUEST_TAGS[element.tag] and element.questId then
			hasQuest = true
			local s = elementState(element)
			if s == "grey" then grey = grey + 1
			elseif s == "open" then satisfied = false end
		end
	end
	return hasQuest, satisfied, grey
end

-- Build the key ourselves, the way RXP builds its progress key (group|subgroup|name). RXP hands out the same
-- guide with two different .key spellings (the list stub uses "group||name", the parsed guide includes the
-- subgroup), and flags saved under one were invisible under the other after the 4.11.9 update.
local function guideKey(guide)
	if not guide then return nil end
	local group, name = guide.group or "", guide.name or ""
	local sub = guide.subgroup
	if (sub == nil or sub == "") and type(guide.key) == "string" then
		sub = guide.key:match("^[^|]*|([^|]*)|") or ""
	end
	return group .. "|" .. (sub or "") .. "|" .. name
end

-- Flags are stored by STEP FINGERPRINT, not step number (23 Sep: guide edits shifted step numbers under saved
-- index flags and the guide jumped ahead). A fingerprint is each element's tag + quest/item id + text, plus the
-- occurrence count of that same fingerprint so repeated steps ("Hearth to Kharanos") stay distinct.
-- flagsFor() still returns something indexed by step number, so callers are unchanged.
local sigCache = setmetatable({}, { __mode = "k" })
local function stepSigs(guide)
	local c = sigCache[guide]
	if c and c.n == #guide.steps then return c end
	c = { n = #guide.steps, byIndex = {} }
	local seen = {}
	for i, step in ipairs(guide.steps) do
		local parts = {}
		for _, e in ipairs(step.elements or {}) do
			local id = e.questId or e.id
			parts[#parts + 1] = tostring(e.tag or "?") .. (id and (":" .. tostring(id)) or "")
				.. (type(e.text) == "string" and ("=" .. e.text:sub(1, 32)) or "")
		end
		local base = table.concat(parts, "|")
		seen[base] = (seen[base] or 0) + 1
		c.byIndex[i] = base .. "#" .. seen[base]
	end
	sigCache[guide] = c
	return c
end

local function flagsFor(guide, create)
	local db = DB()
	db.flagsBySig = db.flagsBySig or {}
	local key = guideKey(guide)
	if not key or not guide.steps then return nil end
	local stored = db.flagsBySig[key]
	if not stored then
		if not create then return nil end
		stored = {}
		db.flagsBySig[key] = stored
	end
	local sigs = stepSigs(guide).byIndex
	return setmetatable({}, {
		__index = function(_, i) local s = sigs[i]; return s and stored[s] or nil end,
		__newindex = function(_, i, v) local s = sigs[i]; if s then stored[s] = v end end,
	})
end

local function applyFlag(guide, n)
	local step = guide.steps[n]
	if not step or step.tip then return end
	if step.sticky then
		RXPCData.stepSkip = RXPCData.stepSkip or {}
		RXPCData.stepSkip[n] = true
	else
		step.completed = true
	end
end

local function say(msg) print("|cFF00ff96RXP catch-up:|r " .. msg) end

local function catchup(depth)
	depth = depth or 0
	local guide = RXP and RXP.currentGuide
	if not guide or not guide.steps or #guide.steps == 0 then say("no guide loaded") return end
	local flags = flagsFor(guide, true)

	local firstOpen
	local questDone, greyQuests, states = 0, 0, {}
	for i, step in ipairs(guide.steps) do
		local hasQuest, satisfied, grey = stepState(step)
		local checkable, verified = verifiedState(step)
		states[i] = { hasQuest = hasQuest, satisfied = satisfied, itemsDone = (not hasQuest and checkable > 0 and verified) }
		if hasQuest then
			if satisfied then
				questDone = questDone + 1
				greyQuests = greyQuests + grey
			elseif not firstOpen then
				firstOpen = i
			end
		end
	end

	local marked = 0
	for i, step in ipairs(guide.steps) do
		local mark = false
		if firstOpen == nil or i < firstOpen then
			mark = true
		elseif states[i].hasQuest and states[i].satisfied then
			mark = true
		elseif states[i].itemsDone then
			-- e.g. "buy 20 mushrooms" when 20 are already in the bags, or "train X" when X is known
			mark = true
		end
		if mark and not step.tip then
			if not flags[i] then marked = marked + 1 end
			flags[i] = true
			applyFlag(guide, i)
		end
	end

	if firstOpen == nil then
		say(string.format("every quest in '%s' is already done or grey (%d quest steps done, %d grey) - moving to the next guide", tostring(guide.name), questDone, greyQuests))
		if depth < 6 and RXP.functions and RXP.functions.next then
			RXP.functions.next(nil, guide)
			C_Timer.After(0.5, function() catchup(depth + 1) end)
		end
		return
	end

	local current = (RXP.GetGuideProgress and RXP.GetGuideProgress()) or 1
	RXP.SetStep(current)
	local now = (RXP.GetGuideProgress and RXP.GetGuideProgress()) or firstOpen
	say(string.format("%d steps flagged (%d quest steps already done, %d grey quests skipped). Now on step %d of %d.",
		marked, questDone, greyQuests, now, #guide.steps))
end

local function clear()
	local guide = RXP and RXP.currentGuide
	local key = guideKey(guide)
	if key and DB() then
		if DB().flags then DB().flags[key] = nil end            -- old step-number flags
		if DB().flagsBySig then DB().flagsBySig[key] = nil end  -- fingerprint flags
	end
	say("flags cleared for the current guide - /reload to see every step again")
end

-- keep the legacy variable pointing at the live store so an old copy is never stale
local mirrorFrame = CreateFrame("Frame")
mirrorFrame:RegisterEvent("PLAYER_LOGOUT")
mirrorFrame:SetScript("OnEvent", function() if RXPCData then RXPForeverDB = RXPCData.rxpForever end end)

-- re-apply saved flags whenever RXP activates a step, so it keeps hopping after a /reload
-- declared here so the SetStep wrapper below can see them; defined further down
local loginSettled = false
local rememberGuide

-- RXP only auto-accepts a quest it has registered in RXP.questAccept, and its accept handler registers one
-- only after it has resolved the quest NAME. Forever quests are not in its database, the name comes from the
-- server a moment too late, and a follow-up offered straight after a hand-in is missed. The popup is matched
-- by quest ID, so register the accept elements of the active step (and the next, which RXP also honours)
-- by ID as soon as the step activates. RXP wipes questAccept inside SetStep, so this runs after it.
local function armAutoAccept(idx)
	local guide = RXP and RXP.currentGuide
	if not guide or not guide.steps or type(idx) ~= "number" or not RXP.questAccept then return end
	for _, si in ipairs({ idx, idx + 1 }) do
		local step = guide.steps[si]
		for _, el in ipairs(step and step.elements or {}) do
			if el.tag == "accept" and el.questId
				and (not el.flags or bit.band(el.flags, 1) == 0)
				and not (RXP.disabledQuests and RXP.disabledQuests[el.questId]) then
				RXP.questAccept[el.questId] = el
			end
		end
	end
end

-- RXP only auto-hands-in quests whose .turnin sits on the active step, so a quest finished while the guide is on
-- another step has to be clicked by hand at the NPC (23 Sep: Rime's Wrath part 2 on a test character - Avala died, the guide
-- moved to the rifle step, the hand-in was two steps later). Arm every COMPLETE quest that this guide turns in
-- anywhere, by ID and by name, without overriding anything RXP set itself (false = RXP says don't).
local turninCache = setmetatable({}, { __mode = "k" })
local function guideTurnins(guide)
	local c = turninCache[guide]
	if c and c.n == #guide.steps then return c end
	c = { n = #guide.steps }
	for _, step in ipairs(guide.steps) do
		for _, el in ipairs(step.elements or {}) do
			if el.tag == "turnin" and type(el.questId) == "number" and (not el.flags or bit.band(el.flags, 1) == 0) then
				c[#c + 1] = el
			end
		end
	end
	turninCache[guide] = c
	return c
end

local function armTurnIns()
	local guide = RXP and RXP.currentGuide
	if not guide or not guide.steps or type(RXP.questTurnIn) ~= "table" then return end
	for _, el in ipairs(guideTurnins(guide)) do
		local id = el.questId
		if RXP.questTurnIn[id] == nil and not (RXP.disabledQuests and RXP.disabledQuests[id])
			and isOnQuest(id) and objectivesDone(id) then
			local proxy = { tag = "turnin", questId = id, step = el.step, reward = (type(el.reward) == "number" and el.reward) or 0 }
			RXP.questTurnIn[id] = proxy
			local name = RXP.GetQuestName and RXP.GetQuestName(id)
			if name and RXP.questTurnIn[name] == nil then RXP.questTurnIn[name] = proxy end
		end
	end
end

local armFrame = CreateFrame("Frame")
armFrame:RegisterEvent("QUEST_LOG_UPDATE")
armFrame:RegisterEvent("GOSSIP_SHOW")
armFrame:RegisterEvent("QUEST_GREETING")
local lastArm = 0
armFrame:SetScript("OnEvent", function(_, event)
	local now = GetTime and GetTime() or 0
	if event == "QUEST_LOG_UPDATE" and now - lastArm < 1 then return end
	lastArm = now
	pcall(armTurnIns)
end)

-- ===== Take guide quests early (25 Sep, Gaz: the guide wasn't "picking up quests or handing quests
-- in near me yet sending me on"; asked whether it breaks the routing - no - then "ok do it") =====
-- RXP only auto-accepts a quest whose step is the current one (RXPGuides.lua QuestAutoAccept: step.active or the
-- step before). Its gossip / greeting / quest-detail automation all ask RXP.QuestAutoAccept, so wrapping that one
-- function lets them take ANY quest the current guide accepts somewhere (by id or title) when you talk to the NPC.
-- Not taken: RXP's disabled quests, quests retired with /rxpcatchup skip, accepts the guide flags as "no auto
-- accept" (flag 0x1), and quests the guide doesn't accept at all (e.g. ones RXP commented out on purpose). Later
-- accept/turn-in steps then complete themselves (the quest is in the log / turned in), so the route is unchanged.
-- Hand-ins were already covered by armTurnIns above. (A "Nearby: ..." note under the arrow was tried and removed -
-- Gaz didn't want it.)
do
	local cacheGuide, acceptIds, acceptTitles
	local function build(guide)
		acceptIds, acceptTitles = {}, {}
		for _, step in ipairs(guide.steps or {}) do
			for _, e in ipairs(step.elements or {}) do
				local id = e.tag == "accept" and type(e.questId) == "number" and e.questId > 0 and e.questId
				local noAuto = e.flags and bit and bit.band(e.flags, 0x1) == 0x1
				if id and not noAuto then acceptIds[id] = true end
			end
		end
		cacheGuide = guide
	end
	local function titleToId(title)
		if acceptTitles[title] then return acceptTitles[title] end
		for id in pairs(acceptIds) do   -- quest names load lazily: fill in as they become known
			local t = RXP.GetQuestName and RXP.GetQuestName(id)
			if t then acceptTitles[t] = id end
		end
		return acceptTitles[title]
	end
	local function guideAccepts(x)
		local g = RXP and RXP.currentGuide
		if not (g and g.steps) then return false end
		if g ~= cacheGuide then build(g) end
		local id = type(x) == "number" and x or (type(x) == "string" and titleToId(x))
		if not (id and acceptIds[id]) then return false end
		if RXP.disabledQuests and RXP.disabledQuests[id] then return false end
		if skippedQuests()[id] then return false end
		return true
	end
	local wrapped
	local function hookAutoAccept()
		if not (RXP and RXP.QuestAutoAccept) or RXP.QuestAutoAccept == wrapped then return end
		local orig = RXP.QuestAutoAccept
		wrapped = function(x)
			if orig(x) then return true end
			local ok, yes = pcall(guideAccepts, x)
			return ok and yes or nil
		end
		RXP.QuestAutoAccept = wrapped
	end

	local nf, acc = CreateFrame("Frame"), 0
	nf:SetScript("OnUpdate", function(_, dt)
		acc = acc + (dt or 0)
		if acc < 1 then return end
		acc = 0
		RXP = RXP or _G.RXP
		if RXP then hookAutoAccept() end
	end)
end

-- Quest-log snapshot for Claude (24 Sep): the Forever client only writes saved variables on /reload or logout and
-- RXP keeps no quest log on disk (questObjectivesCache is a lookup cache), so keep one here: every quest in the log
-- with objectives, plus the turned-in state of every quest the current guide mentions.
-- Read from WTF/.../<char>/SavedVariables/RXPGuides.lua -> RXPCData.rxpForever.questLog after any reload.
local function snapshotQuests()
	if not RXPCData or not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then return end
	-- on a real logout the client has already wiped the character by PLAYER_LOGOUT (quest levels 0, every quest
	-- "not turned in" - seen 25 Sep, an Undead Paladin): keep the last good snapshot instead
	if UnitHealthMax and UnitHealthMax("player") == 0 then return end
	local log = {}
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID then
			local objs = {}
			for _, o in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
				objs[#objs + 1] = tostring(o.text) .. (o.finished and " [done]" or "")
			end
			log[info.questID] = { title = info.title, level = info.level,
				complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID) or false, objectives = objs }
		end
	end
	local done = {}
	local guide = RXP and RXP.currentGuide
	for _, step in ipairs(guide and guide.steps or {}) do
		for _, el in ipairs(step.elements or {}) do
			local id = type(el.questId) == "number" and el.questId
			if id and done[id] == nil then done[id] = isTurnedIn(id) and true or false end
		end
	end
	RXPCData.rxpForever = RXPCData.rxpForever or {}
	RXPCData.rxpForever.questLog = { time = date("%Y-%m-%d %H:%M:%S"), guide = guide and guide.name,
		step = RXP and RXP.GetGuideProgress and RXP.GetGuideProgress() or nil, quests = log, guideQuestsTurnedIn = done }
end
local snapFrame = CreateFrame("Frame")
snapFrame:RegisterEvent("QUEST_LOG_UPDATE")
snapFrame:RegisterEvent("PLAYER_LOGOUT")
local lastSnap = 0
snapFrame:SetScript("OnEvent", function(_, event)
	local now = GetTime and GetTime() or 0
	if event ~= "PLAYER_LOGOUT" and now - lastSnap < 2 then return end
	lastSnap = now
	pcall(snapshotQuests)
end)

-- ===== Track dungeon guide quests (25 Sep, Gaz: "make it auto track ... keep it for dungeon pre quests for now") =====
-- Blizzard only auto-tracks a new quest that shows a counter (QuestMapFrame: GetNumQuestLeaderBoards > 0), so
-- "A Frightened Request" (investigate, no counter) never showed on the tracker, and the quest log files it under
-- Undercity rather than Ruins of Lordaeron. While a guide from a "Dungeon" group is active, every quest of that guide
-- that is in the log gets ticked for tracking. Each quest is ticked once per session, so untracking one by hand sticks.
local trackedOnce = {}
local function trackDungeonQuests()
	local guide = RXP and RXP.currentGuide
	if not (guide and guide.steps and type(guide.group) == "string" and guide.group:lower():find("dungeon", 1, true)) then return end
	if not (C_QuestLog and C_QuestLog.AddQuestWatch and C_QuestLog.GetNumQuestWatches) then return end
	local max = (Constants and Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES) or 25
	for _, step in ipairs(guide.steps) do
		for _, el in ipairs(step.elements or {}) do
			local id = type(el.questId) == "number" and el.questId
			if id and not trackedOnce[id] and isOnQuest(id) then
				trackedOnce[id] = true
				local watched = QuestUtils_IsQuestWatched and QuestUtils_IsQuestWatched(id)
				if not watched and C_QuestLog.GetNumQuestWatches() < max then C_QuestLog.AddQuestWatch(id) end
			end
		end
	end
end
local trackFrame = CreateFrame("Frame")
trackFrame:RegisterEvent("QUEST_ACCEPTED")
trackFrame:RegisterEvent("QUEST_LOG_UPDATE")
trackFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
local lastTrack = 0
trackFrame:SetScript("OnEvent", function(_, event)
	local now = GetTime and GetTime() or 0
	if event == "QUEST_LOG_UPDATE" and now - lastTrack < 2 then return end
	lastTrack = now
	pcall(trackDungeonQuests)
end)

-- ===== Generic travel skip (24 Sep, Gaz: "applied across the whole add on regardless of guide") =====
-- RXP skips accept / complete / turn-in steps the game says are done, but a pure travel step (fly, hearth, go to,
-- take the zeppelin, enter a zone) has nothing to complete, so it runs even when the quest step it leads to is
-- already done ("fly to Undercity" for a quest already in the log). When RXP activates a pure travel step, look
-- ahead past any further travel steps to the first step that is NOT pure travel: if that is a quest step the game
-- already reports done, the travel is not needed and is skipped. A following train / buy / flight-path / hearth-set
-- step keeps the travel (hasQuest is false there), so nothing outside quests is ever skipped.
local TRAVEL_TAGS = { ["goto"] = true, fly = true, hs = true, zone = true, deathskip = true, waypoint = true,
	zoneskip = true, subzoneskip = true, continentskip = true, needanyquest = true, onanyquest = true,
	use = true, cooldown = true, bindlocation = true, target = true, mob = true, subzone = true, text = true,
	isQuestAvailable = true, isNotOnQuest = true, isOnQuest = true, isQuestTurnedIn = true, isQuestComplete = true }
local MOVE_TAGS = { ["goto"] = true, fly = true, hs = true, zone = true, deathskip = true, waypoint = true }
local function isTravelStep(step)
	if not step or step.sticky or step.tip then return false end
	local moves = false
	for _, e in ipairs(step.elements or {}) do
		local t = e.tag
		if t ~= nil and not TRAVEL_TAGS[t] then return false end
		if MOVE_TAGS[t] then moves = true end
	end
	return moves
end
local function questStepDone(step)
	local hasQuest, satisfied = false, true
	for _, e in ipairs(step.elements or {}) do
		if QUEST_TAGS[e.tag] and e.questId then
			hasQuest = true
			local id = e.questId
			local done = isTurnedIn(id) or skippedQuests()[id]
				or (e.tag == "accept" and isOnQuest(id))
				or (e.tag == "complete" and isOnQuest(id) and objectivesDone(id))
				or (e.skipIfMissing and not isOnQuest(id))
			if not done then satisfied = false end
		end
	end
	return hasQuest and satisfied
end
local function travelNotNeeded(guide, idx)
	if not guide or not guide.steps or not isTravelStep(guide.steps[idx]) then return false end
	for j = idx + 1, math.min(#guide.steps, idx + 15) do
		local nxt = guide.steps[j]
		if not isTravelStep(nxt) then return questStepDone(nxt) end
	end
	return false
end

local travelFrame = CreateFrame("Frame")
travelFrame:RegisterEvent("QUEST_ACCEPTED")
travelFrame:RegisterEvent("QUEST_TURNED_IN")
travelFrame:RegisterEvent("QUEST_REMOVED")
travelFrame:SetScript("OnEvent", function()
	if C_Timer then C_Timer.After(0.5, function()
		pcall(function()
			local guide = RXP and RXP.currentGuide
			local cur = RXP and RXP.GetGuideProgress and RXP.GetGuideProgress()
			if guide and type(cur) == "number" and travelNotNeeded(guide, cur) then RXP.SetStep(cur) end
		end)
	end) end
end)

local wrappedSetStep
local navBypass = false   -- set by the step-back button for one SetStep call: no flagged / travel auto-skip
local function hookSetStep()
	if not RXP or not RXP.SetStep or RXP.SetStep == wrappedSetStep then return end
	local orig = RXP.SetStep
	-- RXP's element handlers (e.g. ".money") rewrite step.completed on every tick for the ACTIVE step, so a
	-- flagged step must never become active: when RXP asks to activate a flagged step, skip forward to the
	-- first unflagged one. Sticky steps are handled through RXP's own stepSkip list instead.
	wrappedSetStep = function(n, n2, loopback)
		local guide = RXP.currentGuide
		local idx = (type(n) == "table") and n2 or n
		if guide and guide.steps and type(idx) == "number" and not navBypass then
			local flags = flagsFor(guide, false)
			local total = #guide.steps
			while idx < total and guide.steps[idx] do
				if flags and flags[idx] and not guide.steps[idx].sticky then
					applyFlag(guide, idx)
				elseif travelNotNeeded(guide, idx) then
					guide.steps[idx].completed = true      -- not flagged: re-evaluated if the quest state changes
				else
					break
				end
				idx = idx + 1
			end
			if flags and flags[idx] then applyFlag(guide, idx) end
		end
		local r
		if type(n) == "table" then r = orig(n, idx, loopback) else r = orig(idx, n2, loopback) end
		if loginSettled and type(idx) == "number" then rememberGuide(RXP.currentGuide, idx) end
		armAutoAccept(idx)
		pcall(armTurnIns)
		return r
	end
	RXP.SetStep = wrappedSetStep
end

-- Guide restore on login.
-- On this client RXP loses its current guide on every /reload: its startup lookup misses and it loads the
-- zone's default (or empty) guide, overwriting its own saved name before this file even loads. So this addon
-- keeps its OWN record: every guide the player loads after login is remembered in the store's lastGuide,
-- and a few seconds after entering the world it is put back if RXP ended up somewhere else.

-- the per-character file was once found empty at login, so the last guide is also mirrored in an
-- account-wide variable keyed by character; whichever copy survives is used
-- keyed by GUID: the name+realm key was shared by every character with the same first name, so one character's guide overwrote the others'
local function charKey() return UnitGUID("player") or ((UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")) end

rememberGuide = function(guide, step)
	if not loginSettled or not guide or guide.empty or guide.internal or not guide.name then return end
	local prev = DB().lastGuide
	-- the step's fingerprint too: RXP's own saved position (stepId = guide line number) and a bare step number both
	-- point at the wrong step once lines are inserted above it (23 Sep: a test character sent back to Kharanos)
	local sig
	if not step and prev and prev.name == guide.name and prev.group == guide.group then
		step, sig = prev.step, prev.sig      -- guide re-loaded without a step: keep the saved position as it was
	else
		sig = step and guide.steps and stepSigs(guide).byIndex[step]
	end
	local rec = { group = guide.group, name = guide.name, step = step, sig = sig }
	DB().lastGuide = rec
	RXPForeverAcct = RXPForeverAcct or {}
	RXPForeverAcct.lastGuide = RXPForeverAcct.lastGuide or {}
	RXPForeverAcct.lastGuide[charKey()] = rec
end

local function lastGuideRecord()
	local perChar = DB() and DB().lastGuide
	if perChar then return perChar, "character" end
	local acct = RXPForeverAcct and RXPForeverAcct.lastGuide and RXPForeverAcct.lastGuide[charKey()]
	if acct then return acct, "account" end
	return nil
end

local wrappedLoadGuide
local function hookLoadGuide()
	if not RXP or not RXP.LoadGuide or RXP.LoadGuide == wrappedLoadGuide then return end
	local orig = RXP.LoadGuide
	wrappedLoadGuide = function(self, guide, onLoad)
		local r = orig(self, guide, onLoad)
		rememberGuide(RXP.currentGuide)
		return r
	end
	RXP.LoadGuide = wrappedLoadGuide
end

-- where to put the player back: the step whose fingerprint matches the saved one (nearest to the saved number if
-- the fingerprint repeats), else the saved number if no fingerprint was stored or the step itself was edited
local function targetStep(guide, last)
	if not guide or not guide.steps then return nil end
	if last.sig then
		local best
		for i, s in ipairs(stepSigs(guide).byIndex) do
			if s == last.sig and (not best or math.abs(i - (last.step or i)) < math.abs(best - (last.step or i))) then best = i end
		end
		if best then return best end
	end
	if last.step and guide.steps[last.step] then return last.step end
	return nil
end

local restoreAttempts = 0
local function restoreGuide()
	RXP = _G.RXP
	if _G.RXPForeverNewChar then return true end
	local last, source = lastGuideRecord()
	local current = RXP and RXP.currentGuide and RXP.currentGuide.name
	local found = last and RXP and RXP.GetGuideTable and RXP.GetGuideTable(last.group, last.name)
	restoreAttempts = restoreAttempts + 1
	DB().restoreDebug = { lastGroup = last and last.group, lastName = last and last.name,
		currentAtLogin = tostring(current), rxpSavedName = tostring(RXPCData and RXPCData.currentGuideName),
		lookupFound = found ~= nil, attempts = restoreAttempts, source = source or "none",
		store = RXPCData and "RXPCData" or "own", flagsLoaded = DB().flags ~= nil, rxpLoaded = tostring(RXP and RXP.addonLoaded),
		guidesKnown = RXP and RXP.guides and #RXP.guides or -1, time = date("%H:%M:%S") }
	if not last then return true end
	if found then
		if current == last.name and last.sig and RXP.currentGuide and RXP.currentGuide.group == last.group then
			-- RXP reloaded the right guide, but from its line-number stepId, which drifts after guide edits
			local target = targetStep(RXP.currentGuide, last)
			local rxpStep = RXP.GetGuideProgress and RXP.GetGuideProgress() or nil
			DB().restoreDebug.sameGuide = true
			DB().restoreDebug.ourStep, DB().restoreDebug.rxpStepAfterLoad = target, rxpStep
			if target and rxpStep ~= target then
				RXP.SetStep(target)
				say(string.format("guide position corrected: step %s -> %d (guide was edited since you last played)", tostring(rxpStep), target))
			end
		elseif current ~= last.name then
			RXP:LoadGuide(found, true)
			local rxpStep = RXP.GetGuideProgress and RXP.GetGuideProgress() or nil
			DB().restoreDebug.rxpStepAfterLoad = rxpStep
			DB().restoreDebug.ourStep = last.step
			local g = RXP.currentGuide
			DB().restoreDebug.loadedKey = tostring(g and guideKey(g))
			DB().restoreDebug.flagsForLoadedKey = (g and flagsFor(g, false)) and "yes" or "no"
			DB().restoreDebug.rxpProgressForKey = tostring(g and g.key and RXPCData.guideProgress and RXPCData.guideProgress[g.key] and RXPCData.guideProgress[g.key].step)
			local target = RXP.currentGuide and targetStep(RXP.currentGuide, last)
			if target and rxpStep ~= target then
				RXP.SetStep(target)
			end
			say(string.format("restored guide '%s' at step %s (RXP had loaded '%s', step %s)",
				last.name, tostring(target or rxpStep), tostring(current), tostring(rxpStep)))
		end
		return true
	end
	-- RXP has not registered that guide yet (it loads its guide list over several seconds); try again
	return false
end

-- RXP update safety (3 Oct 2026): RXPCData.stepSkip (steps ticked off by hand) and completedWaypoints are indexed by step NUMBER,
-- and a new RestedXP release renumbers the steps (Barrens 12-17 went 410 -> 395). The first login after the RXPGuides version
-- changes clears both once, so no wrong step stays hidden. The guide position itself is restored by fingerprint, as before.
local function checkRxpVersion()
	if not RXPCData then return end
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
	local v = get and get("RXPGuides", "Version")
	if not v or v == "" then return end
	local st = DB()
	-- a character that never recorded a version last ran on v4.11.9 (the release before this check existed), so it needs no login first
	local last = st.rxpVersion or "v4.11.9"
	if last ~= v then
		RXPCData.stepSkip = {}
		RXPCData.completedWaypoints = {}
		print("|cFF00ff96RXP catch-up:|r RestedXP updated " .. tostring(last) .. " -> " .. v ..
			": cleared the skipped-steps list (step numbers changed). Your guide position is restored as usual.")
	end
	st.rxpVersion = v
end

local restoreFrame = CreateFrame("Frame")
restoreFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
restoreFrame:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	pcall(checkRxpVersion)
	local function attempt()
		local ok, done = pcall(restoreGuide)
		if not ok then say("restore error: " .. tostring(done)) done = true end
		if not done and restoreAttempts < 15 then
			C_Timer.After(2, attempt)
			return
		end
		if not done then say("could not find the saved guide after 30 s - pick it by hand") end
		loginSettled = true
		hookLoadGuide()
		rememberGuide(RXP and RXP.currentGuide)
	end
	C_Timer.After(3, attempt)
end)

-- ===== Step summary under the waypoint arrow (24 Sep, Gaz: "add to the waypoint text what the step is, e.g.
-- Travel to Tundra MacGrann, a summary from the current step in small text") =====
-- RXP's arrow (RXPG_ARROW, map.lua) shows "Step N (123yd)". A smaller second line underneath shows the first
-- unfinished line of the step the arrow belongs to, with RXP's colour / icon codes stripped. Warnings are only
-- used when the step has nothing else. Built here, not in RXP's map.lua, so RXP updates don't remove it.
local function plainText(t)
	t = t:gsub("|T.-|t", ""):gsub("|cRXP_%u+_", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	t = t:gsub("%s+", " "):gsub("^[%s>]+", ""):gsub("%s+$", "")
	if #t > 72 then t = t:sub(1, 69) .. "..." end
	return t
end
local function stepSummary(step)
	if not step then return "" end
	local warn
	for _, e in ipairs(step.elements or {}) do
		if type(e.text) == "string" and e.text ~= "" and not e.completed then
			local t = plainText(e.text)
			if t ~= "" then
				if e.text:find("^|cRXP_WARN_") then warn = warn or t else return t end
			end
		end
	end
	return warn or ""
end
_G.RXPForeverStepSummary = stepSummary   -- exposed for testing
local sumFrame = CreateFrame("Frame")
local sumAcc, sumLast = 0, nil
sumFrame:SetScript("OnUpdate", function(_, dt)
	sumAcc = sumAcc + (dt or 0)
	if sumAcc < 0.3 then return end
	sumAcc = 0
	local af = _G.RXPG_ARROW
	if not (af and af.text and af.CreateFontString) then return end
	local font, size, flags = af.text:GetFont()
	if not af.rxpfSummary then
		local fs = af:CreateFontString(nil, "OVERLAY")
		fs:SetPoint("TOP", af.text, "BOTTOM", 0, -2)
		fs:SetWidth(260)
		fs:SetJustifyH("CENTER")
		fs:SetTextColor(0.85, 0.85, 0.85)
		af.rxpfSummary = fs
	end
	local fs = af.rxpfSummary
	if font and fs.rxpfSize ~= size then
		pcall(fs.SetFont, fs, font, math.max(7, (size or 9) - 1), flags or "OUTLINE")
		fs.rxpfSize = size
	end
	local text = stepSummary(af.element and af.element.step)
	if text ~= sumLast then
		fs:SetText(text)
		sumLast = text
	end
end)

-- ===== Guide window toggle button (25 Sep, Gaz: "add a minimise button to the rxp add on visually so I can flick it
-- on and off as required") =====
-- Left-click: hide / show the guide window, exactly like RXP's own "Hide Window" option (the arrow and its step
-- summary keep working). Right-click: hide / show everything RXP draws, like /rxp toggle. Shift-drag to move; the
-- position is remembered per character. The icon is greyed while the window is hidden. Uses RXP's settings, so the
-- state survives reloads.
do
	local btn = CreateFrame("Button", "RXPForeverToggleButton", UIParent)
	btn:SetSize(26, 26)
	btn:SetFrameStrata("HIGH")
	btn:SetClampedToScreen(true)
	btn:SetMovable(true)
	btn:RegisterForDrag("LeftButton")
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetPoint("TOPLEFT", -2, 2)
	border:SetPoint("BOTTOMRIGHT", 2, -2)
	border:SetColorTexture(0, 0, 0, 0)

	local function profile()
		local rxp = _G.RXP
		return rxp and rxp.settings and rxp.settings.profile, rxp
	end
	local function refresh()
		local prof = profile()
		local hidden = prof and (prof.hideGuideWindow or prof.showEnabled == false)
		icon:SetDesaturated(hidden and true or false)
		icon:SetAlpha(hidden and 0.6 or 1)
	end
	local function place()
		btn:ClearAllPoints()
		local pos = RXPCData and RXPCData.rxpForever and RXPCData.rxpForever.toggleBtnPos
		if pos then
			btn:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
		elseif _G.ForeverReloadButton then
			btn:SetPoint("RIGHT", _G.ForeverReloadButton, "LEFT", -4, 0)
		elseif Minimap then
			btn:SetPoint("TOPRIGHT", Minimap, "BOTTOMLEFT", -24, 8)
		else
			btn:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -170)
		end
	end

	btn:SetScript("OnClick", function(_, button)
		local prof, rxp = profile()
		if not prof then return end
		if button == "RightButton" then
			if rxp.settings.ToggleActive then rxp.settings.ToggleActive() end
		else
			if prof.showEnabled == false and rxp.settings.ToggleActive then
				rxp.settings.ToggleActive()          -- everything was off: bring RXP back first
				prof.hideGuideWindow = false
			else
				prof.hideGuideWindow = not prof.hideGuideWindow
			end
			if rxp.RXPFrame then rxp.RXPFrame:SetShown(not prof.hideGuideWindow and prof.showEnabled ~= false) end
			if rxp.v2 and rxp.v2.events then
				pcall(rxp.v2.events.Trigger, rxp.v2.events, "GuideWindowRefresh", "visibility",
					not prof.hideGuideWindow and prof.showEnabled ~= false)
			end
		end
		refresh()
	end)
	btn:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
	btn:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p1, _, p2, x, y = self:GetPoint(1)
		if RXPCData then
			RXPCData.rxpForever = RXPCData.rxpForever or {}
			RXPCData.rxpForever.toggleBtnPos = { p1, p2, x, y }
		end
	end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("RestedXP guide")
		GameTooltip:AddLine("Left-click: hide / show the guide window (arrow keeps working)", 1, 1, 1, true)
		GameTooltip:AddLine("Right-click: hide / show everything, arrow included", 1, 1, 1, true)
		GameTooltip:AddLine("Shift-drag to move.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	ev:SetScript("OnEvent", function()
		place()
		if C_Timer then C_Timer.After(3, refresh) else refresh() end   -- RXP applies its settings a moment after login
	end)
end

-- ===== Step back / step forward icons (29 Sep, Gaz: "a button ... on the mini map ring to go back or forward a step") =====
-- Replaces pasting /run RXP.SetStep(...) lines. Forward = the next step (our normal auto-skips apply, like RXP's own
-- skip). Back = the nearest earlier step that would actually stay active: RXP re-completes a step whose quests are
-- already done and passes over steps whose quest conditions don't match the log (.isOnQuest etc.), so those are
-- skipped here too; our flagged / travel auto-skip is bypassed for that one call. !ForeverSV puts both on the ring.
do
	local CHECK = {
		isOnQuest = function(id) return isOnQuest(id) end,
		isNotOnQuest = function(id) return not isOnQuest(id) end,
		isQuestTurnedIn = function(id) return isTurnedIn(id) end,
		isQuestAvailable = function(id) return not isTurnedIn(id) end,
		isQuestComplete = function(id) return isOnQuest(id) and objectivesDone(id) end,
	}
	local function conditionsMet(step)
		for _, e in ipairs(step.elements or {}) do
			local f = CHECK[e.tag]
			local id = e.questId or (e.questIds and e.questIds[1])
			if f and type(id) == "number" and not f(id) then return false end
		end
		return true
	end
	local function wouldStay(step)
		if not step or step.sticky or step.tip then return false end
		return conditionsMet(step) and not questStepDone(step)
	end
	local function current()
		local rxp = _G.RXP
		local cur = rxp and rxp.GetGuideProgress and rxp.GetGuideProgress()
		return rxp, rxp and rxp.currentGuide, type(cur) == "number" and cur or nil
	end
	local function stepBack()
		local rxp, guide, cur = current()
		if not (guide and guide.steps and cur) then return end
		for i = cur - 1, math.max(1, cur - 40), -1 do
			if wouldStay(guide.steps[i]) then
				navBypass = true
				local ok, err = pcall(rxp.SetStep, i)
				navBypass = false
				if not ok then print("|cFF00ff96RXP step back:|r " .. tostring(err)) end
				return
			end
		end
		print("|cFF00ff96RXP step back:|r nothing still open in the 40 steps before this one.")
	end
	local function stepForward()
		local rxp, guide, cur = current()
		if not (guide and guide.steps and cur) or cur >= #guide.steps then return end
		pcall(rxp.SetStep, cur + 1)
	end
	local function make(name, tex, line1, line2, onClick)
		local b = CreateFrame("Button", name, UIParent)
		b:SetSize(24, 24)
		b:SetFrameStrata("HIGH")
		b:SetClampedToScreen(true)
		b:SetMovable(true)
		b:RegisterForDrag("LeftButton")
		b:SetNormalTexture(tex)
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		if Minimap then b:SetPoint("TOPRIGHT", Minimap, "BOTTOMLEFT", -8, -8) else b:SetPoint("CENTER") end
		b:SetScript("OnClick", onClick)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:AddLine(line1)
			GameTooltip:AddLine(line2, 1, 1, 1, true)
			GameTooltip:AddLine("Shift-drag to slide it round the minimap.", 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return b
	end
	make("RXPForeverStepBackButton", "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
		"Guide: step back", "Back to the nearest earlier step that isn't done yet.", stepBack)
	make("RXPForeverStepNextButton", "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
		"Guide: step forward", "Skip to the next step.", stepForward)
end

-- ===== Quest-log safety net (3 Oct 2026, Gaz: "can't we build some redundancy in this? can't it check the quest log") =====
-- RXP moves on when steps are completed OR skipped, and never checks that the quests of a chain were really done: on 3 Oct
-- the shaman stood at Cairne with Rite of Vision still open (Ambercorns 0/2), Rite of Wisdom and Journey into Thunder Bluff
-- never picked up, and the arrow still led on. This looks at the quest log against the current guide and says so.
--   * stranded : the quest is in your log, but every step of this guide that completes / hands it in is BEHIND the current step
--   * missed   : the quest is not in your log and not handed in, its accept step is behind you, and a step at or after the
--                current one still needs it (e.g. the Cairne hand-in for a quest you never took)
-- It only talks (one green chat line when the list changes). /rxpback jumps to the earliest step of the chain and un-skips
-- the chain's steps; nothing is moved automatically. /rxpback off | on silences / restores the chat line.
do
	local function qtitle(id)
		local t = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
		if t and t ~= "" then return t end
		t = RXP and RXP.GetQuestName and RXP.GetQuestName(id)
		return t or ("quest " .. tostring(id))
	end

	-- per guide: byQuest[id] = { accept = {step idx...}, complete = {...}, turnin = {...} } (ascending)
	local idxCache = setmetatable({}, { __mode = "k" })
	local function questIndex(guide)
		local c = idxCache[guide]
		if c and c.n == #guide.steps then return c.byQuest end
		local byQuest = {}
		for i, step in ipairs(guide.steps) do
			for _, e in ipairs(step.elements or {}) do
				local id = e.questId
				if QUEST_TAGS[e.tag] and type(id) == "number" and id > 0 then
					local q = byQuest[id]
					if not q then q = { accept = {}, complete = {}, turnin = {} }; byQuest[id] = q end
					local list = q[e.tag]
					if list[#list] ~= i then list[#list + 1] = i end
				end
			end
		end
		idxCache[guide] = { n = #guide.steps, byQuest = byQuest }
		return byQuest
	end

	local function retired(id)
		return skippedQuests()[id] or (RXP and RXP.disabledQuests and RXP.disabledQuests[id])
	end

	local function nearestBehind(list, cur)
		local a
		for _, i in ipairs(list) do if i < cur then a = i end end
		return a
	end

	-- earliest step of the chain behind `id`'s accept step at `a`: the quests that step hands in must be done first
	local function chainOrigin(guide, idx, id, a, cur, depth, involved)
		involved[id] = true
		local best = a
		for _, e in ipairs(guide.steps[a].elements or {}) do
			local pid = e.tag == "turnin" and e.questId
			if type(pid) == "number" and pid ~= id and depth < 8 and not isTurnedIn(pid) and not retired(pid) and idx[pid] and not involved[pid] then
				if isOnQuest(pid) then
					involved[pid] = true
					local list = objectivesDone(pid) and idx[pid].turnin or idx[pid].complete
					if list[1] and list[1] < best then best = list[1] end
				else
					local pa = nearestBehind(idx[pid].accept, a)
					if pa then best = math.min(best, chainOrigin(guide, idx, pid, pa, cur, depth + 1, involved)) end
				end
			end
		end
		return best
	end

	-- returns issues (list), earliest step, set of involved quest ids
	local function scan()
		local guide = RXP and RXP.currentGuide
		local cur = RXP and RXP.GetGuideProgress and RXP.GetGuideProgress()
		if not (guide and guide.steps and #guide.steps > 0 and type(cur) == "number") then return nil end
		local idx = questIndex(guide)
		local function ahead(list) for _, i in ipairs(list) do if i >= cur then return true end end end
		local issues, involved, earliest = {}, {}, nil
		for id, q in pairs(idx) do
			if not retired(id) and not isTurnedIn(id) then
				local later = ahead(q.complete) or ahead(q.turnin)
				if isOnQuest(id) then
					if not later then
						local done = objectivesDone(id)
						local list = done and q.turnin or q.complete
						if list[1] and list[1] < cur then
							issues[#issues + 1] = { id = id, kind = done and "ready" or "open", step = list[1] }
							involved[id] = true
							earliest = math.min(earliest or list[1], list[1])
						end
					end
				elseif later then
					local a = nearestBehind(q.accept, cur)
					if a then
						local origin = chainOrigin(guide, idx, id, a, cur, 0, involved)
						issues[#issues + 1] = { id = id, kind = "missed", step = a }
						earliest = math.min(earliest or origin, origin)
					end
				end
			end
		end
		table.sort(issues, function(x, y) return x.step < y.step end)
		return issues, earliest, involved, guide, cur
	end

	local KIND = { open = "still open in your log", ready = "finished, not handed in", missed = "never picked up" }
	local lastSig, lastSay = nil, 0
	local function report(force)
		if not loginSettled or (DB().safetyOff and not force) then return end
		local issues, earliest, _, guide, cur = scan()
		if not issues then return end
		local parts, sig = {}, {}
		for n, it in ipairs(issues) do
			sig[#sig + 1] = it.id .. it.kind
			if n <= 4 then parts[#parts + 1] = string.format("%s (%s, step %d)", qtitle(it.id), KIND[it.kind], it.step) end
		end
		local s = table.concat(sig, ",") .. "@" .. tostring(guide.name)
		if #issues == 0 then
			lastSig = s
			if force then print("|cFF00ff96RXP safety net:|r nothing left behind - every quest of this guide before step " .. cur .. " is done or handed in.") end
			return
		end
		local now = GetTime and GetTime() or 0
		if not force and s == lastSig and now - lastSay < 600 then return end
		lastSig, lastSay = s, now
		local sum = _G.RXPForeverStepSummary and _G.RXPForeverStepSummary(guide.steps[earliest])
		print("|cFF00ff96RXP safety net:|r you left something behind: " .. table.concat(parts, "; ")
			.. (#issues > 4 and (" (+" .. (#issues - 4) .. " more)") or "")
			.. ". Type |cFFffff00/rxpback|r to go back to step " .. earliest .. (sum and sum ~= "" and (" (" .. sum .. ")") or "") .. ".")
	end

	local function back()
		local issues, earliest, involved, guide, cur = scan()
		if not issues then say("no guide loaded") return end
		if #issues == 0 or not earliest then say("nothing left behind - nothing to go back to") return end
		local flags = flagsFor(guide, true)
		RXPCData.stepSkip = RXPCData.stepSkip or {}
		local cleared = 0
		for i = earliest, cur - 1 do
			local step = guide.steps[i]
			for _, e in ipairs(step and step.elements or {}) do
				if QUEST_TAGS[e.tag] and involved[e.questId] then
					RXPCData.stepSkip[i] = nil
					if flags then flags[i] = nil end
					step.completed = false
					cleared = cleared + 1
					break
				end
			end
		end
		navBypass = true
		local ok, err = pcall(RXP.SetStep, earliest)
		navBypass = false
		if ok then say(string.format("back to step %d; %d chain steps un-skipped. The guide walks the chain forward from here.", earliest, cleared))
		else say("could not move: " .. tostring(err)) end
		lastSig = nil
	end

	SLASH_RXPBACK1 = "/rxpback"
	SlashCmdList["RXPBACK"] = function(msg)
		msg = (msg or ""):lower():match("^%s*(%S*)") or ""
		if msg == "off" then DB().safetyOff = true; say("safety-net chat line off (/rxpback still works, /rxpback on turns it back on)")
		elseif msg == "on" then DB().safetyOff = nil; say("safety-net chat line on"); pcall(report, true)
		elseif msg == "check" or msg == "list" then pcall(report, true)
		else back() end
	end

	-- when to look: login (after the guide is restored), quest changes, and whenever the guide step changes
	local f, acc, lastCur, lastGuide, dirty = CreateFrame("Frame"), 0, nil, nil, false
	f:RegisterEvent("QUEST_LOG_UPDATE")
	f:RegisterEvent("QUEST_TURNED_IN")
	f:RegisterEvent("QUEST_ACCEPTED")
	f:RegisterEvent("QUEST_REMOVED")
	f:SetScript("OnEvent", function() dirty = true end)
	f:SetScript("OnUpdate", function(_, dt)
		acc = acc + (dt or 0)
		if acc < 4 then return end
		acc = 0
		if not loginSettled then return end
		local g = RXP and RXP.currentGuide
		local cur = RXP and RXP.GetGuideProgress and RXP.GetGuideProgress()
		if dirty or cur ~= lastCur or g ~= lastGuide then
			dirty, lastCur, lastGuide = false, cur, g
			pcall(report, false)
		end
	end)
end

-- ===== Map lines after the map is first opened (26 Sep) =====
-- rxp-forever/patches/patch_rxp_no_map_flash.py stops RXP flashing WorldMapFrame open and shut from addon code (that
-- tainted the gamepad UI: "AddOn 'RXPGuides' tried to call the protected function SetPreferredGamepadInteractTarget").
-- RXP only did it to give the map canvas a size before drawing route lines, so the lines are now skipped until the
-- map has been opened once. This redraws them the first time the map is open with a real size - in a fresh
-- execution (C_Timer), never from inside the map's own show.
do
	local w, acc = CreateFrame("Frame"), 0
	w:SetScript("OnUpdate", function(self, dt)
		acc = acc + (dt or 0)
		if acc < 0.5 then return end
		acc = 0
		local map = _G.WorldMapFrame
		local rxp = _G.RXP
		if not (map and map:IsShown() and rxp and rxp.UpdateMap and rxp.currentGuide) then return end
		local canvas = map.GetCanvas and map:GetCanvas()
		if not canvas or canvas:GetWidth() == 0 then return end
		self:SetScript("OnUpdate", nil)
		C_Timer.After(0, function() pcall(rxp.UpdateMap, true) end)
	end)
end

SLASH_RXPCATCHUP1 = "/rxpcatchup"
SLASH_RXPCATCHUP2 = "/catchup"
-- /rxpcatchup skip [questId]  -> retire a quest: every step that accepts, completes or turns it in is flagged.
-- With no id, retires the quests of the current step. Undo with  /rxpcatchup unskip <questId>
local function skipQuest(arg, undo)
	local guide = RXP and RXP.currentGuide
	if not guide or not guide.steps then say("no guide loaded") return end
	local ids = {}
	local id = tonumber(arg)
	if id then
		ids[id] = true
	else
		local cur = guide.steps[(RXP.GetGuideProgress and RXP.GetGuideProgress()) or 1]
		for _, element in ipairs(cur and cur.elements or {}) do
			if QUEST_TAGS[element.tag] and element.questId then ids[element.questId] = true end
		end
	end
	if next(ids) == nil then say("no quest on the current step - give a quest id: /rxpcatchup skip 425") return end
	local list = skippedQuests()
	local names = {}
	for qid in pairs(ids) do
		list[qid] = (not undo) and true or nil
		table.insert(names, tostring(qid) .. (RXP.GetQuestName and RXP.GetQuestName(qid) and (" " .. RXP.GetQuestName(qid)) or ""))
	end
	say((undo and "un-retired: " or "retired: ") .. table.concat(names, ", ") .. " - re-running catch-up")
	local ok, err = pcall(catchup)
	if not ok then say("error: " .. tostring(err)) end
end

SlashCmdList["RXPCATCHUP"] = function(msg)
	RXP = _G.RXP
	if not RXP then say("RestedXP is not loaded") return end
	hookSetStep()
	hookLoadGuide()
	msg = (msg or ""):lower()
	if msg:match("^%s*clear") then return clear() end
	if msg:match("^%s*unskip") then return skipQuest(msg:match("unskip%s*(%d*)"), true) end
	if msg:match("^%s*skip") then return skipQuest(msg:match("skip%s*(%d*)"), false) end
	local ok, err = pcall(catchup)
	if not ok then say("error: " .. tostring(err)) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	RXP = _G.RXP
	if RXP then hookSetStep() end
end)

-- ===== Fold the step list, keep the current-step box (25 Sep, Gaz: "minimise or turn off the quest window steps
-- ... but keep the top window which lists what needs to be done in the dungeon") =====
-- A -/+ button on the guide-name bar. RXP already has this layout: a guide with `#hidewindow` gets a 28px window
-- (current-step box + name bar) and no step list (GuideWindow.lua, end of BottomFrame.UpdateFrame), and it saves /
-- restores the full height itself (settings.profile.frameHeight). The button sets or clears that flag on the current
-- guide and asks RXP to redraw (updateBottomFrame), so RXP's own code does the folding. Remembered per guide
-- (RXPCData.rxpForever.folded[guide name]) and re-applied when a folded guide is loaded. Classic window only (RXP's
-- beta V2 window has its own layout).
do
	local function folded()
		RXPCData.rxpForever = RXPCData.rxpForever or {}
		RXPCData.rxpForever.folded = RXPCData.rxpForever.folded or {}
		return RXPCData.rxpForever.folded
	end
	local fb, lastGuide
	local function apply(guide, on)
		local R = _G.RXP
		if not (R and guide and RXPCData) then return end
		if R.v2 and R.v2.IsGuideWindowEnabled and R.v2:IsGuideWindowEnabled() then return end
		if guide.rxpfOwnHide == nil then guide.rxpfOwnHide = guide.hidewindow and true or false end
		if guide.rxpfOwnHide then return end   -- the guide folds itself (#hidewindow) - leave it alone
		guide.hidewindow = on or nil
		-- un-fold: RXP keeps the list hidden while its area is under 30px (first branch of its check), so give the
		-- window its saved height back first; RXP then shows the list itself
		local win = R.RXPFrame
		if not on and win and win:GetHeight() < 50 then
			local h = R.settings and R.settings.profile and R.settings.profile.frameHeight
			win:SetHeight(math.max(tonumber(h) or 200, 50))
		end
		R.updateBottomFrame = true
		if fb then
			fb:SetNormalTexture(on and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
			fb:SetPushedTexture(on and "Interface\\Buttons\\UI-PlusButton-Down" or "Interface\\Buttons\\UI-MinusButton-Down")
		end
	end
	local function setup()
		local R = _G.RXP
		local bar = R and R.RXPFrame and R.RXPFrame.GuideName
		if fb or not bar then return end
		fb = CreateFrame("Button", "RXPForeverFoldButton", bar)
		fb:SetSize(14, 14)
		fb:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
		fb:SetFrameLevel(bar:GetFrameLevel() + 5)
		fb:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
		fb:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
		fb:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
		fb:SetScript("OnClick", function()
			local g = _G.RXP and _G.RXP.currentGuide
			if not (g and g.name) then return end
			local on = not folded()[g.name]
			folded()[g.name] = on or nil
			apply(g, on)
		end)
		fb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			local g = _G.RXP and _G.RXP.currentGuide
			local on = g and g.name and folded()[g.name]
			GameTooltip:AddLine(on and "Show the step list" or "Fold the step list")
			GameTooltip:AddLine("Keeps the current step box. Remembered for this guide.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		fb:SetScript("OnLeave", function() GameTooltip:Hide() end)

		-- drag strip along the top of the current-step box (Gaz: "step 19 window not moveable, make it moveable from
		-- the top"). The step's text lines cover the box and take the mouse, so RXP's own drag on the box rarely
		-- gets the click. This strip sits above them and calls RXP's own handlers (respects Lock Frames, saves the
		-- position like dragging RXP's window).
		local box = R.RXPFrame.CurrentStepFrame
		if box and R.RXPFrame.OnMouseDown then
			local grip = CreateFrame("Frame", "RXPForeverStepGrip", box)
			grip:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 10)
			grip:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 10)
			grip:SetHeight(20)
			grip:SetFrameLevel(box:GetFrameLevel() + 20)
			grip:EnableMouse(true)
			local hl = grip:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 1, 1, 0.08)
			grip:SetScript("OnMouseDown", function(self, button)
				if button == "LeftButton" then R.RXPFrame.OnMouseDown(self, button) end
			end)
			grip:SetScript("OnMouseUp", function(self, button) R.RXPFrame.OnMouseUp(self, button) end)
			grip:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:AddLine("Drag to move the guide window")
				GameTooltip:Show()
			end)
			grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end
	end
	-- set up once RXP's window exists, and re-apply the saved fold whenever the loaded guide changes
	local w, acc = CreateFrame("Frame"), 0
	w:SetScript("OnUpdate", function(_, dt)
		acc = acc + (dt or 0)
		if acc < 1 then return end
		acc = 0
		if not RXPCData then return end
		setup()
		local g = _G.RXP and _G.RXP.currentGuide
		if g and g ~= lastGuide then
			lastGuide = g
			apply(g, g.name and folded()[g.name] or false)
		end
	end)
end

-- ===== Trainer automation on by default (25 Sep, Gaz: "I want it to auto train judgement and blessing ... next time") =====
-- RXP can buy the guide's .train spells (and its list of useful generic spells) when a trainer window opens
-- (RXPGuides.lua OnTrainer, setting "Trainer automation" = profile.enableTrainerAutomation), but the setting has no
-- default, so it is off on every new profile - and Forever's first-name-only UnitName makes a new profile per name.
-- Switch it on once per profile where it has never been set; a deliberate "off" in RXP's options is left alone.
do
	local ta = CreateFrame("Frame")
	ta:RegisterEvent("PLAYER_LOGIN")
	ta:SetScript("OnEvent", function()
		if not C_Timer then return end
		C_Timer.After(2, function()
			local R = _G.RXP
			local p = R and R.settings and R.settings.profile
			if p and p.enableTrainerAutomation == nil then
				p.enableTrainerAutomation = true
				print("|cff33ff99RXPForever:|r trainer automation switched on - RXP now buys the guide's spells when you open a trainer.")
			end
		end)
	end)
end

-- ===== .continentskip for RXP guides =====
-- .continentskip <continentMapID>[,1] skips the step while you are on that continent (flag 1: while you are NOT).
-- Kalimdor = 1414, Eastern Kingdoms = 1415. Modelled on RXP's own .zoneskip (functions.lua) and re-checked on the
-- same zone-change events.
-- 23 Sep: the map-parent walk alone never produced a skip on Forever (a test character in the Barrens still got "fly to
-- Undercity" and "zeppelin to Durotar"), so the world instance from UnitPosition comes first: 0 = Eastern Kingdoms,
-- 1 = Kalimdor - the same /0 and /1 the guides' world coordinates use. What was seen is kept in continentDebug.
local INSTANCE_CONTINENT = { [0] = 1415, [1] = 1414 }
local function currentContinent()
	local _, _, _, inst = UnitPosition("player")
	local dbg = { inst = inst, time = date("%H:%M:%S") }
	if RXPCData then RXPCData.rxpForever = RXPCData.rxpForever or {}; RXPCData.rxpForever.continentDebug = dbg end
	if inst and INSTANCE_CONTINENT[inst] then dbg.result = INSTANCE_CONTINENT[inst] return dbg.result end
	local m = C_Map.GetBestMapForUnit("player")
	dbg.map = m
	for _ = 1, 10 do
		if not m then return nil end
		local info = C_Map.GetMapInfo(m)
		if not info then return nil end
		dbg[#dbg + 1] = tostring(m) .. ":" .. tostring(info.mapType)
		if info.mapType == 2 then dbg.result = m return m end -- Enum.UIMapType.Continent
		m = info.parentMapID
	end
end
-- NB: the file-level `local RXP` is still nil while this file loads (it is filled at login), so this block must use
-- the global - before 23 Sep it tested the nil local and .continentskip was never registered at all.
local RXPG = _G.RXP
if RXPG and RXPG.functions and not RXPG.functions.continentskip then
	RXPG.functions.continentskip = function(self, text, continent, flags)
		if type(self) == "string" then -- on parse
			local element = { continent = tonumber(continent), reverse = ((tonumber(flags) or 0) % 2) == 1, textOnly = true }
			if text and text ~= "" then element.text = text end
			return element
		end
		local element = self.element
		local step = element.step
		if not step.active or RXPG.isHidden then return end
		local c = currentContinent()
		if not c then return end
		if (c == element.continent) == not element.reverse then
			step.completed = true
			RXPG.updateSteps = true
		end
	end
	if RXPG.functions.events then RXPG.functions.events.continentskip = RXPG.functions.events.zoneskip end
end

-- ===== .needanyquest / .onanyquest (24 Sep) =====
-- Travel legs in the dungeon guides must know WHY they exist ("only send me where I still need to go"):
--   .needanyquest 5722,5723  -> skip the step unless at least one listed quest is still to get (not in log, not done)
--   .onanyquest 5723,5724    -> skip the step unless at least one listed quest is in the log (e.g. a hand-in trip)
-- RXP ANDs its conditions (each one skips the step on its own), so "any of" needs its own command.
if RXPG and RXPG.functions and not RXPG.functions.needanyquest then
	local function makeAny(test)
		return function(self, text, ...)
			if type(self) == "string" then -- on parse
				local ids = {}
				for _, v in ipairs({ ... }) do local id = tonumber(v) if id then ids[#ids + 1] = id end end
				return { ids = ids, textOnly = true, text = (text ~= "" and text) or nil }
			end
			local element = self.element
			local step = element.step
			if not step.active or RXPG.isHidden then return end
			for _, id in ipairs(element.ids) do
				if test(id) then return end   -- one quest still qualifies: keep the step
			end
			step.completed = true
			RXPG.updateSteps = true
		end
	end
	RXPG.functions.needanyquest = makeAny(function(id) return not isOnQuest(id) and not isTurnedIn(id) end)
	RXPG.functions.onanyquest = makeAny(function(id) return isOnQuest(id) end)
	if RXPG.functions.events then
		local ev = { "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" }
		RXPG.functions.events.needanyquest = ev
		RXPG.functions.events.onanyquest = ev
	end
end

-- ===== .fpknown <taxi node id>[,1] (29 Sep) =====
-- RXP can't tell whether a flight path is known, so an Undead fresh off the zeppelin was told to fly to Thunder Bluff.
--   .fpknown 22    -> skip the step unless the Thunder Bluff flight path is known (fly legs)
--   .fpknown 22,1  -> skip the step if it is known (walk legs)
-- Known = RXPCData.flightPaths, which RXP fills whenever a flight master's map opens (Timers.lua), so the guide sends
-- the player to their nearest flight master first; the TAXIMAP events re-check once the map has been read.
if RXPG and RXPG.functions and not RXPG.functions.fpknown then
	RXPG.functions.fpknown = function(self, text, node, flags)
		if type(self) == "string" then -- on parse
			local element = { node = tonumber(node), reverse = ((tonumber(flags) or 0) % 2) == 1, textOnly = true }
			if text and text ~= "" then element.text = text end
			return element
		end
		local element = self.element
		local step = element.step
		if not step.active or RXPG.isHidden then return end
		local known = RXPCData and RXPCData.flightPaths and RXPCData.flightPaths[element.node] and true or false
		if known == element.reverse then
			step.completed = true
			RXPG.updateSteps = true
		end
	end
	if RXPG.functions.events then RXPG.functions.events.fpknown = { "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "UI_INFO_MESSAGE" } end
end

-- ===== /rxpfp - flight paths RXP does not know about (1 Oct, Gaz: "shouldn't it check if I have the FP already and skip?") =====
-- RXP's .fp step and our .fpknown only trust RXPCData.flightPaths, which RXP fills when a flight master's map is opened or
-- when .fp completes while the guide runs - so a path learned earlier (the paladin's Crossroads) looks unknown and the step
-- shows again. The world map knows which taxi nodes are discovered (C_TaxiMap.GetTaxiNodesForMap, the same data the map's
-- flight-point pins use). /rxpfp prints what it reports for Kalimdor and Eastern Kingdoms next to what RXP has recorded;
-- /rxpfp apply merges the discovered ones into RXPCData.flightPaths. Nothing is changed without "apply".
do
	local function nodes()
		local out = {}
		if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return out, "C_TaxiMap.GetTaxiNodesForMap is not available" end
		local unreachable = Enum and Enum.FlightPathState and Enum.FlightPathState.Unreachable
		for _, mapID in ipairs({ 1414, 1415 }) do   -- Kalimdor, Eastern Kingdoms
			local ok, list = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
			if ok and type(list) == "table" then
				for _, v in pairs(list) do
					if type(v) == "table" and v.nodeID then
						out[#out + 1] = { id = v.nodeID, name = v.name or "?", state = v.state, known = (v.state ~= nil and v.state ~= unreachable) }
					end
				end
			end
		end
		table.sort(out, function(a, b) return a.id < b.id end)
		return out
	end
	SLASH_RXPFP1 = "/rxpfp"
	SlashCmdList.RXPFP = function(msg)
		local R = _G.RXPCData
		if not R then print("|cff33ff99rxpfp:|r RXP is not loaded") return end
		R.flightPaths = R.flightPaths or {}
		local list, err = nodes()
		if err then print("|cff33ff99rxpfp:|r " .. err) return end
		if (msg or ""):lower():find("debug") then
			local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
			print("|cff33ff99rxpfp debug:|r you are on map " .. tostring(here) .. "; RXP has recorded:")
			local rec = {}
			for id, nm in pairs(R.flightPaths) do rec[#rec + 1] = id .. "=" .. tostring(nm) end
			table.sort(rec)
			print("  " .. (#rec > 0 and table.concat(rec, ", ") or "(nothing)"))
			for _, mapID in ipairs({ 1414, 1415, 1413, 1456, 1454, here }) do
				for _, fn in ipairs({ "GetTaxiNodesForMap", "GetAllTaxiNodes" }) do
					local f = C_TaxiMap and C_TaxiMap[fn]
					if f then
						local ok, res = pcall(f, mapID)
						local n = (ok and type(res) == "table") and #res or -1
						local first = ""
						if n > 0 then
							local v = res[1]
							first = " first: " .. tostring(v.nodeID) .. " " .. tostring(v.name) .. " state=" .. tostring(v.state)
						end
						print("  map " .. mapID .. " " .. fn .. ": " .. (ok and (n .. " nodes" .. first) or ("error " .. tostring(res))))
					else
						print("  C_TaxiMap." .. fn .. " does not exist")
					end
				end
			end
			return
		end
		if (msg or ""):lower():find("apply") then
			local added = 0
			for _, n in ipairs(list) do
				if n.known and not R.flightPaths[n.id] then R.flightPaths[n.id] = n.name added = added + 1 end
			end
			print("|cff33ff99rxpfp:|r added " .. added .. " flight paths RXP did not know. Guides re-check them on the next step update.")
			if _G.RXP and _G.RXP.updateSteps ~= nil then _G.RXP.updateSteps = true end
			return
		end
		local known, unk = {}, {}
		for _, n in ipairs(list) do
			local mark = (R.flightPaths[n.id] and "RXP knows") or "RXP does NOT know"
			local line = n.id .. " " .. n.name .. " (map state " .. tostring(n.state) .. ", " .. mark .. ")"
			if n.known then known[#known + 1] = line else unk[#unk + 1] = line end
		end
		print("|cff33ff99rxpfp:|r the game map reports " .. #known .. " discovered / " .. #unk .. " other flight nodes.")
		for _, l in ipairs(known) do print("  discovered: " .. l) end
		print("Type /rxpfp apply to tell RXP about the discovered ones. (If this list is wrong - paths you have not learned - do NOT apply.)")
	end
end

-- ===== auto-accept look-ahead in our dungeon guides (1 Oct, Gaz: "quests aren't being auto accepted like talk to Tonga") =====
-- RXP auto-accepts a quest only while the step holding its .accept is the ACTIVE step or the one right after it
-- (RXPGuides.lua QuestAutoAccept). Our dungeon guides put optional travel steps (flight/walk legs, flight paths RXP does not
-- know) in front of the NPC step, so by the time you stand at Tonga the .accept step is several steps ahead and nothing is
-- accepted. Here, in guides whose name ends "dungeon quests" only, a quest is also auto-accepted when an .accept for it
-- sits in the next 14 steps and that step is not done. Hold Ctrl to talk without accepting (RXP's own rule).
-- /rxpaccept [questId] explains what RXP decides.
do
	local R = _G.RXP
	if R and R.QuestAutoAccept and not R.QuestAutoAcceptForever then
		local orig = R.QuestAutoAccept
		R.QuestAutoAcceptForever = true
		local function ahead(id)
			local g = R.currentGuide
			if not (g and g.steps and type(g.name) == "string" and g.name:find("dungeon quests", 1, true)) then return end
			local cur = (R.GetGuideProgress and R.GetGuideProgress()) or 1
			for i = cur, math.min(#g.steps, cur + 14) do
				local st = g.steps[i]
				if st and not st.completed then
					for _, el in ipairs(st.elements or {}) do
						if el.tag == "accept" and el.questId == id and ((el.flags or 0) % 2) ~= 1 then return i end
					end
				end
			end
		end
		R.QuestAutoAccept = function(titleOrId)
			local r = orig(titleOrId)
			if r then return r end
			local id = tonumber(titleOrId)
			if id and not (R.disabledQuests and R.disabledQuests[id]) and ahead(id) then return true end
		end
		SLASH_RXPACCEPT1 = "/rxpaccept"
		SlashCmdList.RXPACCEPT = function(msg)
			if (msg or ""):lower():find("watch") then
				if not R.acceptWatch then
					R.acceptWatch = CreateFrame("Frame")
					for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM", "QUEST_ACCEPTED", "QUEST_PROGRESS", "QUEST_COMPLETE", "TAXIMAP_OPENED", "TAXIMAP_CLOSED" }) do
						R.acceptWatch:RegisterEvent(e)
					end
					R.acceptWatch:SetScript("OnEvent", function(_, event, ...)
						if not R.acceptWatchOn then return end
						local line = "|cff33ff99watch:|r " .. event
						if event == "GOSSIP_SHOW" and C_GossipInfo then
							local av = C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests() or {}
							for _, q in ipairs(av) do
								line = line .. " | available " .. tostring(q.questID) .. " '" .. tostring(q.title) .. "' RXP " .. (R.QuestAutoAccept(q.questID) and "ACCEPTS" or "ignores")
							end
							if #av == 0 then line = line .. " | no available quests listed" end
							local ok, opts = pcall(C_GossipInfo.GetOptions)
							if ok and type(opts) == "table" then
								line = line .. " | gossip options: " .. #opts
								for i, o in ipairs(opts) do
									line = line .. " [" .. i .. " " .. tostring(o.name) .. " type=" .. tostring(o.type) .. " icon=" .. tostring(o.icon) .. "]"
								end
							end
							line = line .. " | step " .. tostring(R.GetGuideProgress and R.GetGuideProgress())
						elseif event == "QUEST_DETAIL" then
							local id = GetQuestID and GetQuestID()
							line = line .. " | quest " .. tostring(id) .. " RXP " .. (id and R.QuestAutoAccept(id) and "ACCEPTS" or "ignores")
						elseif event == "QUEST_ACCEPTED" then
							line = line .. " | " .. tostring((...))
						end
						print(line)
					end)
					if C_GossipInfo and C_GossipInfo.SelectAvailableQuest then
						hooksecurefunc(C_GossipInfo, "SelectAvailableQuest", function(q)
							if R.acceptWatchOn then print("|cff33ff99watch:|r SelectAvailableQuest(" .. tostring(q) .. ") was called") end
						end)
					end
					if C_GossipInfo and C_GossipInfo.SelectOption then
						hooksecurefunc(C_GossipInfo, "SelectOption", function(id)
							if R.acceptWatchOn then print("|cff33ff99watch:|r SelectOption(" .. tostring(id) .. ") was called") end
						end)
					end
					hooksecurefunc("AcceptQuest", function()
						if R.acceptWatchOn then print("|cff33ff99watch:|r AcceptQuest() was called") end
					end)
				end
				R.acceptWatchOn = not R.acceptWatchOn
				print("|cff33ff99rxpaccept:|r watch " .. (R.acceptWatchOn and "ON - now talk to the NPC. Type /rxpaccept watch again to stop." or "off"))
				return
			end
			local id = tonumber((msg or ""):match("%d+"))
			local prof = R.settings and R.settings.profile
			local g = R.currentGuide
			print("|cff33ff99rxpaccept:|r quest automation setting: " .. tostring(prof and prof.enableQuestAutomation) ..
				"; Ctrl held: " .. tostring(IsControlKeyDown()) .. "; RXP hidden: " .. tostring(R.isHidden))
			print("  guide: " .. tostring(g and g.name) .. ", step " .. tostring(R.GetGuideProgress and R.GetGuideProgress()))
			if id then
				print("  quest " .. id .. ": RXP's own rule " .. tostring(orig(id) and "ACCEPTS" or "does not accept") ..
					"; look-ahead finds the .accept at step " .. tostring(ahead(id)) ..
					"; disabled: " .. tostring(R.disabledQuests and R.disabledQuests[id]))
			else
				print("  give a quest id, e.g. /rxpaccept 1489")
			end
		end
	end
end

-- ===== Ruins of Lordaeron dungeon quests (Horde) =====
-- Forever-only 5-man (zone 16611, added 1.60.1). Quest data from Wowhead Forever, 23 Sep 2026.
-- Starts from ANYWHERE: gets you to Undercity (hearth if bound there / zeppelin from Kalimdor / flight in Eastern
-- Kingdoms / walk in from Tirisfal), picks up Theodore + Morbin, detours to the Sepulcher for Tabitha only if you
-- don't already have her quest, then Kristof on the way to the dungeon. After the run: every hand-in, ending at
-- Tabitha (hearth if bound to the Sepulcher, else fly).
-- Undercity routes reuse RXP's own tested waypoint chains (Apothecarium chain from forever/Horde-01-14_Undead.lua,
-- Royal Quarter chain from RestedXP Horde 1-20 BloodElf.lua, enter/exit + flight master from
-- forever/Horde-01-14_Undead.lua, zeppelin tower from forever/Horde-01-12_Durotar.lua).
-- Pickups: 95216 The New Plague (Theodore Griffs, req 16), 92421 Light's Justice (Morbin Lightbane),
-- 92401 A Frightened Request (Tabitha Heartweaver, Sepulcher), 92422 The Wrath of Rath'mael (Deathguard Kristof).
-- Dungeon drops start 95204 Crest of Lordaeron and 97288 Unending Torment (-> 97289 -> 97290 (Abomination, reward choice) -> 97291 -> 97292, Faranell).
if RXPGuides and RXPGuides.RegisterGuide then
	RXPGuides.RegisterGuide([[
<< Horde
#forever
#version 2
#group Forever Dungeons (H)
#name Ruins of Lordaeron dungeon quests
step
    .hs >> Hearth to the Undercity
    .use 6948
    .cooldown item,6948,>2,1
    .zoneskip Undercity
    .bindlocation 1497,1
    .needanyquest 95216,92421,92422,92401
step
    .goto 1421,44.5,42.9
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tYou're in Silverpine: talk to |cRXP_FRIENDLY_Tabitha Heartweaver|r at The Sepulcher before flying out
    .accept 92401 >>Accept A Frightened Request
    .target Tabitha Heartweaver
    .zoneskip Silverpine Forest,1
step
    .goto 1421/0,1533.96,474.43
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Karos|r at The Sepulcher
    .fly Undercity >> Fly to the Undercity
    .target Karos Razok
    .zoneskip Silverpine Forest,1
    .needanyquest 95216,92421,92422
step
    .goto 1411/1,-4648.55,1321.88,40 >>Go up the Zeppelin Tower outside Orgrimmar (fly to Orgrimmar first if you're far away)
    .zone Tirisfal Glades >>Take the Zeppelin to Tirisfal Glades
    .continentskip 1414,1
    .needanyquest 95216,92421,92422,92401
step
    >>Fly to the Undercity from the nearest flight master
    .fly Undercity >> Fly to the Undercity
    .continentskip 1415,1
    .zoneskip Undercity+Tirisfal Glades+Silverpine Forest
    .needanyquest 95216,92421,92422,92401
step
    #completewith next
    .goto 1420/0,240.75,1877.57,20 >> Enter Undercity
    .zoneskip Undercity
    .zoneskip Tirisfal Glades,1
    .needanyquest 95216,92421
step
    #completewith next
    .goto 1458,65.50,56.75,20,0
    .goto 1458,64.42,64.62,20,0
    .goto 1458,54.383,73.014,20,0
    .goto 1458,52.837,77.725,20,0
    .goto 1458,52.275,79.254,15,0
    .goto 1458,51.279,79.923,15,0
    .goto 1458,49.693,78.903,15,0
    .goto 1458,47.951,76.171,15,0
    .goto 1458,46.4,71.6,12 >>Travel to The Apothecarium on the LOWER level. Do not go up into the Royal Quarter
    .needanyquest 95216,92421
step
    .goto 1458,46.4,71.6
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Theodore Griffs|r in The Apothecarium (needs level 16)
    .accept 95216 >>Accept The New Plague
    .target Theodore Griffs
step
    #completewith next
    .goto 1458,47.951,76.171,15,0
    .goto 1458,49.693,78.903,15,0
    .goto 1458,51.279,79.923,15,0
    .goto 1458,52.275,79.254,15,0
    .goto 1458,52.837,77.725,20,0
    .goto 1458,54.383,73.014,20,0
    .goto 1458,51.88,64.84,20,0
    .goto 1458,46.28,73.10,15,0
    .goto 1458,45.31,78.24,15,0
    .goto 1458,46.18,83.63,15,0
    .goto 1458,48.80,87.63,15,0
    .goto 1458,52.45,89.49,15,0
    .goto 1458,57.6,89.5,12 >>Travel to the Royal Quarter
    .needanyquest 92421
step
    .goto 1458,57.6,89.5
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Morbin Lightbane|r in the Royal Quarter
    .accept 92421 >>Accept Light's Justice
    .target Morbin Lightbane
step
    .goto 1458,52.45,89.49,15,0
    .goto 1458,48.80,87.63,15,0
    .goto 1458,46.18,83.63,15,0
    .goto 1458,45.31,78.24,15,0
    .goto 1458,46.28,73.10,15,0
    .goto 1458,51.88,64.84,20,0
    .goto 1458,64.42,64.62,20,0
    .goto 1458,65.50,56.75,20 >>Head back up to the Trade Quarter
    .needanyquest 92401
step
    .goto 1458/0,266.20,1567.17
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Michael|r
    .fly Sepulcher >> Fly to The Sepulcher
    .target Michael Garrett
    .isQuestAvailable 92401
    .isNotOnQuest 92401
step
    .goto 1421,44.5,42.9
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tabitha Heartweaver|r at The Sepulcher
    .accept 92401 >>Accept A Frightened Request
    .target Tabitha Heartweaver
step
    .hs >> Hearth to the Undercity
    .use 6948
    .cooldown item,6948,>2,1
    .zoneskip Silverpine Forest,1
    .bindlocation 1497,1
    .needanyquest 95216,92421,92422
step
    .goto 1421/0,1533.96,474.43
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Karos|r
    .fly Undercity >> Fly back to the Undercity
    .target Karos Razok
    .zoneskip Silverpine Forest,1
    .needanyquest 95216,92421,92422
step
    #completewith next
    .goto 1420/0,235.32,1883.89
    .zone Tirisfal Glades >> Exit Undercity by the elevators
    .zoneskip Undercity,1
step
    .goto 1420,65.2,60.2
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Deathguard Kristof|r
    .accept 92422 >>Accept The Wrath of Rath'mael
    .target Deathguard Kristof
step
    #completewith RoLEnter
    .goto 1420/0,240.75,1877.57,20 >> Enter Undercity
    .zoneskip Undercity
step
    #label RoLEnter
    .goto 1458/0,238.400,1872.200,20,0
    .goto 1458/0,170.700,1804.700
    .subzone 16611 >> Travel to the |cRXP_WARN_Ruins of Lordaeron|r entrance in Undercity and zone in with your group
    >>|cRXP_WARN_Waypoints from RXP's own Dungeon Guide (v4.11.12). It is the ruined courtyard above the Undercity, on your LEFT as you come in from outside|r
step
    #completewith RoLDone
    >>Collect 25 |cRXP_LOOT_Intact Limbs|r from the undead as you go
    .complete 92421,1 --Intact Limbs (25)
step
    #completewith RoLDone
    +Loot a |cRXP_LOOT_Crest of Lordaeron|r and an |cRXP_LOOT_Abominable Head|r if they drop - each starts a quest
step
    >>|cRXP_WARN_The dungeon is not linear - do the bosses in any order. Journal order (/fj rol): Witherfang, The Baron, Viktor the Vile, The Abandoned, Bjork, Rath'mael|r
    >>Kill |cRXP_ENEMY_Witherfang|r in the long hallway east of the entrance (King's Alley). Loot the |cRXP_LOOT_Highly Toxic Strain|r
    .complete 95216,1 --Highly Toxic Strain
    .mob Witherfang
step
    +Kill |cRXP_ENEMY_The Baron|r in the indoor courtyard after the hallway
    .mob The Baron
step
    +Follow the U-shaped path to |cRXP_ENEMY_Viktor the Vile|r, then trigger the statue event for |cRXP_ENEMY_The Abandoned|r
    .mob Viktor the Vile
    .mob The Abandoned
step
    +Kill |cRXP_ENEMY_Bjork|r in the foggy area below Market Street
    .mob Bjork
step
    #label RoLDone
    >>Kill |cRXP_ENEMY_Rath'mael|r on the purple rune in the south-west
    .complete 92422,1 --Rath'mael slain
    .mob Rath'mael
step
    >>Find out what happened to |cRXP_FRIENDLY_Edward Heartweaver|r
    >>|cRXP_WARN_His body is in Rath'mael's area, behind the gate - so kill Rath'mael first. Walk over the body next to the|r |cRXP_PICK_Crumpled Paper|r
    .complete 92401,1 --Edward Heartweaver investigated
step
    #optional
    .use 275521 >>Use the |cRXP_LOOT_Crest of Lordaeron|r to start its quest
    .accept 95204 >>Accept Crest of Lordaeron
    .itemcount 275521,>=1
step
    #optional
    .use 280438 >>Use the |cRXP_LOOT_Abominable Head|r to start its quest
    .accept 97288 >>Accept Unending Torment
    .itemcount 280438,>=1
step
    .goto 1420,65.2,60.2
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Deathguard Kristof|r
    .turnin -92422 >>Turn in The Wrath of Rath'mael
    .target Deathguard Kristof
step
    #completewith next
    .goto 1420/0,240.75,1877.57,20 >> Enter Undercity
    .zoneskip Undercity
step
    .goto 1458,73.5,32.5
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Oran Snakewrithe|r
    .turnin 95204 >>Turn in Crest of Lordaeron
    .target Oran Snakewrithe
    .isOnQuest 95204
step
    #completewith next
    .goto 1458,65.50,56.75,20,0
    .goto 1458,64.42,64.62,20,0
    .goto 1458,54.383,73.014,20,0
    .goto 1458,52.837,77.725,20,0
    .goto 1458,52.275,79.254,15,0
    .goto 1458,51.279,79.923,15,0
    .goto 1458,49.693,78.903,15,0
    .goto 1458,47.951,76.171,15,0
    .goto 1458,46.4,71.6,12 >>Travel to The Apothecarium on the LOWER level
step
    .goto 1458,46.4,71.6
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Theodore Griffs|r
    .turnin -95216 >>Turn in The New Plague
    .target Theodore Griffs
step
    .goto 1458,48.5,69.5
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Master Apothecary Faranell|r
    .turnin 97288 >>Turn in Unending Torment
    .accept 97289 >>Accept Unending Torment (he gives you the Head of the Baron)
    .target Master Apothecary Faranell
    .isOnQuest 97288
step
    .goto 1458,46.1,62.6
    >>Take the |cRXP_LOOT_Head of the Baron|r to the |cRXP_FRIENDLY_Unfinished Abomination|r (Othmar's body)
    .turnin 97289 >>Turn in Unending Torment
    .accept 97290 >>Accept Unending Torment (Report your findings to Faranell)
    .target Unfinished Abomination
    .isOnQuest 97289
step
    .goto 1458,48.5,69.5
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Master Apothecary Faranell|r
    >>|cRXP_WARN_Pick a reward: |r|cRXP_LOOT_Slain Baron's Signet|r|cRXP_WARN_, |r|cRXP_LOOT_Grave Shroud|r|cRXP_WARN_ or |r|cRXP_LOOT_Monstrous Cleaver|r
    .turnin 97290 >>Turn in Unending Torment
    .accept 97291 >>Accept Unending Torment
    .target Master Apothecary Faranell
    .isQuestTurnedIn 97289
step
    #completewith next
    .goto 1458,47.951,76.171,15,0
    .goto 1458,49.693,78.903,15,0
    .goto 1458,51.279,79.923,15,0
    .goto 1458,52.275,79.254,15,0
    .goto 1458,52.837,77.725,20,0
    .goto 1458,54.383,73.014,20,0
    .goto 1458,54.4,49.9,12 >>Leave The Apothecarium and head to the Herbalism trainer
    .isOnQuest 97291
step
    .goto 1458,54.4,49.9
    >>Pick the |cRXP_LOOT_Blisterweed|r near |cRXP_FRIENDLY_Martha Alliestar|r, the Herbalism trainer
    .collect 281300,1,97291 --Blisterweed
    .isOnQuest 97291
step
    .goto 1458,65.0,44.0
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tBuy a |cRXP_LOOT_Toxic Skullcap|r (1s 50c) from |cRXP_FRIENDLY_Tawny Grisette|r. She walks the ring around the Trade Quarter bank
    .collect 281246,1,97291 --Toxic Skullcap
    .target Tawny Grisette
    .isOnQuest 97291
step
    .goto 1458,75.5,51.5
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tBuy an |cRXP_LOOT_Essence of Agony|r (2s) from |cRXP_FRIENDLY_Ezekiel Graves|r, the poison vendor
    .collect 8923,1,97291 --Essence of Agony
    .target Ezekiel Graves
    .isOnQuest 97291
step
    #completewith next
    .goto 1458,64.42,64.62,20,0
    .goto 1458,54.383,73.014,20,0
    .goto 1458,52.837,77.725,20,0
    .goto 1458,52.275,79.254,15,0
    .goto 1458,51.279,79.923,15,0
    .goto 1458,49.693,78.903,15,0
    .goto 1458,47.951,76.171,15,0
    .goto 1458,48.5,69.5,12 >>Back to The Apothecarium on the LOWER level
    .isOnQuest 97291
step
    .goto 1458,48.5,69.5
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Master Apothecary Faranell|r
    .turnin 97291 >>Turn in Unending Torment
    .accept 97292 >>Accept Unending Torment
    .target Master Apothecary Faranell
    .isOnQuest 97291
step
    .goto 1458,46.1,62.6
    >>Use the |cRXP_LOOT_Hissing Serum|r on the system above |cRXP_FRIENDLY_Othmar's body|r
    .use 281327
    .complete 97292,1
    .isOnQuest 97292
step
    .goto 1458,48.5,69.5
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Master Apothecary Faranell|r
    .turnin 97292 >>Turn in Unending Torment
    .target Master Apothecary Faranell
    .isOnQuest 97292
step
    #completewith next
    .goto 1458,47.951,76.171,15,0
    .goto 1458,49.693,78.903,15,0
    .goto 1458,51.279,79.923,15,0
    .goto 1458,52.275,79.254,15,0
    .goto 1458,52.837,77.725,20,0
    .goto 1458,54.383,73.014,20,0
    .goto 1458,51.88,64.84,20,0
    .goto 1458,46.28,73.10,15,0
    .goto 1458,45.31,78.24,15,0
    .goto 1458,46.18,83.63,15,0
    .goto 1458,48.80,87.63,15,0
    .goto 1458,52.45,89.49,15,0
    .goto 1458,57.6,89.5,12 >>Travel to the Royal Quarter
step
    .goto 1458,57.6,89.5
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Morbin Lightbane|r
    .turnin -92421 >>Turn in Light's Justice
    .target Morbin Lightbane
step
    .hs >> Hearth to The Sepulcher
    .use 6948
    .cooldown item,6948,>2,1
    .subzoneskip 228
    .bindlocation 228,1
step
    #completewith next
    .goto 1458,52.45,89.49,15,0
    .goto 1458,48.80,87.63,15,0
    .goto 1458,46.18,83.63,15,0
    .goto 1458,45.31,78.24,15,0
    .goto 1458,46.28,73.10,15,0
    .goto 1458,51.88,64.84,20,0
    .goto 1458,64.42,64.62,20,0
    .goto 1458,65.50,56.75,20,0
    .goto 1458/0,266.20,1567.17,12 >>Travel to the flight master
    .zoneskip Undercity,1
step
    .goto 1458/0,266.20,1567.17
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Michael|r
    .fly Sepulcher >> Fly to The Sepulcher
    .target Michael Garrett
    .zoneskip Undercity,1
step
    .goto 1421,44.5,42.9
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tabitha Heartweaver|r
    .turnin -92401 >>Turn in A Frightened Request
    .target Tabitha Heartweaver
]])
end

-- ===== Ragefire Chasm dungeon quests (Horde) =====
-- All 5 RFC quests (Wowhead Forever zone 2437, 23 Sep 2026 - no Forever-only additions): 5722/5724 Searching for /
-- Returning the Lost Satchel + 5723 Testing an Enemy's Strength (Rahauro, Thunder Bluff), 5725 The Power to Destroy...
-- (Varimathras, Undercity Royal Quarter), 5761 Slaying the Beast (Neeru Fireblade, Cleft of Shadow), 5726-5730 Hidden
-- Enemies (Thrall; Lieutenant's Insignia from Burning Blade at Skull Rock). Coordinates and step shapes are RXP's own
-- (forever/Horde-12-22_Barrens.lua RFC block, Mulgore guide for Tal/Rahauro, Undead guide for the Tirisfal zeppelin);
-- RXP itself never routes 5725's pickup and assumes 5722/5723 get shared, so this guide goes to both.
-- Order: from Eastern Kingdoms -> Varimathras first; starting in Thunder Bluff/Mulgore -> Rahauro first (Tauren, 24 Sep);
-- everyone else -> Orgrimmar (Thrall's chain) FIRST, then Thunder Bluff for Rahauro - flown if the TB flight path is
-- known (.fpknown 22), else on foot via the Crossroads and Camp Taurajo picking up both flight paths (29 Sep, Gaz: an
-- Undead off the zeppelin was told to fly to TB). -> (Undercity if still needed) -> RFC -> Orgrimmar hand-ins ->
-- Undercity hand-in -> Thunder Bluff hand-ins (ends in Kalimdor).
if RXPGuides and RXPGuides.RegisterGuide then
	RXPGuides.RegisterGuide([[
<< Horde
#forever
#version 1
#group Forever Dungeons (H)
#name Ragefire Chasm dungeon quests
step
    >>|cRXP_WARN_Ragefire Chasm is for levels 13-18; all five quests need level 9. The dungeon is inside Orgrimmar's Cleft of Shadow|r
    .hs >> Hearth to Orgrimmar
    .use 6948
    .cooldown item,6948,>2,1
    .zoneskip Orgrimmar
    .bindlocation 1637,1
step
    >>|cRXP_WARN_You're in the Eastern Kingdoms: grab Varimathras' quest in Undercity before crossing to Kalimdor|r
    .hs >> Hearth to the Undercity
    .use 6948
    .cooldown item,6948,>2,1
    .zoneskip Undercity
    .bindlocation 1497,1
    .continentskip 1415,1
    .isQuestAvailable 5725
    .isNotOnQuest 5725
step
    >>Fly to the Undercity from the nearest flight master
    .fly Undercity >> Fly to the Undercity
    .zoneskip Undercity+Tirisfal Glades
    .continentskip 1415,1
    .isQuestAvailable 5725
    .isNotOnQuest 5725
step
    #completewith next
    .goto 1420/0,240.75,1877.57,20 >> Enter Undercity
    .zoneskip Undercity
    .zoneskip Tirisfal Glades,1
    .isQuestAvailable 5725
    .isNotOnQuest 5725
step
    #completewith next
    .goto 1458,65.50,56.75,20,0
    .goto 1458,64.42,64.62,20,0
    .goto 1458,51.88,64.84,20,0
    .goto 1458,46.28,73.10,15,0
    .goto 1458,45.31,78.24,15,0
    .goto 1458,46.18,83.63,15,0
    .goto 1458,48.80,87.63,15,0
    .goto 1458,52.45,89.49,15,0
    .goto 1458,56.4,92.4,12 >>Travel to the Royal Quarter
    .zoneskip Undercity,1
    .isQuestAvailable 5725
    .isNotOnQuest 5725
step
    .goto 1458,56.4,92.4
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Varimathras|r beside Sylvanas
    .accept 5725 >> Accept The Power to Destroy...
    .target Varimathras
    .zoneskip Undercity,1
step
    #completewith next
    .goto 1458,52.45,89.49,15,0
    .goto 1458,48.80,87.63,15,0
    .goto 1458,46.18,83.63,15,0
    .goto 1458,45.31,78.24,15,0
    .goto 1458,46.28,73.10,15,0
    .goto 1458,51.88,64.84,20,0
    .goto 1458,64.42,64.62,20,0
    .goto 1458,65.50,56.75,20,0
    .goto 1420/0,235.32,1883.89
    .zone Tirisfal Glades >> Exit Undercity by the elevators
    .zoneskip Undercity,1
step
    .goto 1420/0,278.70,2071.27,12,0
    .goto 1420/0,253.85,2059.82,10,0
    .goto 1420/0,264.70,2053.50,8,0
    .goto 1420/0,271.02,2064.94,8,0
    .goto 1420/0,259.72,2068.86,8,0
    .goto 1420/0,261.53,2055.00,8,0
    .goto 1420/0,299.04,2069.46,-1
    .goto 1420/0,279.61,2441.21,-1
    .zone Durotar >> Go up the Zeppelin Tower west of Brill's road and take the Zeppelin to Durotar
    .zoneskip Durotar
    .continentskip 1415,1
step
    #label RFCRahauro
    >>|cRXP_WARN_You're in Thunder Bluff / Mulgore: Rahauro first, then Orgrimmar|r
    .goto 1456/1,-218.13,-1055.97
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Rahauro|r on the Elder Rise
    .accept 5723 >> Accept Testing an Enemy's Strength
    .target Rahauro
    .zoneskip Thunder Bluff+Mulgore,1
step
    .goto 1456/1,-218.13,-1055.97
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Rahauro|r AGAIN - he has a second quest
    .accept 5722 >> Accept Searching for the Lost Satchel
    .target Rahauro
    .zoneskip Thunder Bluff+Mulgore,1
step
    .goto 1456/1,26.1,-1196.66
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tal|r
    .fly Orgrimmar >> Fly to Orgrimmar
    .target Tal
    .zoneskip Thunder Bluff,1
step
    #completewith next
    >>Fly to Orgrimmar from the nearest flight master
    .fly Orgrimmar >> Fly to Orgrimmar
    .zoneskip Orgrimmar+Durotar
    .continentskip 1414,1
step
    .goto 1454/1,-4125.79,1920.10
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Thrall|r in Grommash Hold
    .accept 5726 >> Accept Hidden Enemies
    .target Thrall
step
    .goto 1454/1,-4376.29,1802.43
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Neeru Fireblade|r in the Cleft of Shadow - his RFC quest is available now
    .accept 5761 >> Accept Slaying the Beast
    .target Neeru Fireblade
step
    .goto 1411/1,-4855.82,1498.84,15,0
    .goto 1411/1,-4833.08,1494.96,15,0
    .goto 1411/1,-4805.59,1495.67,15,0
    .goto 1411/1,-4784.44,1535.85,15,0
    .goto 1411/1,-4750.60,1531.62,15,0
    .goto 1411/1,-4734.21,1505.54,15,0
    .goto 1411/1,-4693.49,1519.64,15,0
    .goto 1411/1,-4679.75,1501.31,15,0
    .goto 1411/1,-4684.50,1466.06,15,0
    >>Kill |cRXP_ENEMY_Burning Blade|r mobs in Skull Rock (just outside Orgrimmar's gate) until the |cRXP_LOOT_Lieutenant's Insignia|r drops
    .complete 5726,1 --Lieutenant's Insignia (1)
    .mob Burning Blade Fanatic
    .mob Burning Blade Apprentice
step
    .goto 1454/1,-4125.79,1920.10
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Thrall|r
    .turnin 5726 >> Turn in Hidden Enemies
    .accept 5727 >> Accept Hidden Enemies
    .target Thrall
step
    .goto 1454/1,-4376.29,1802.43
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Neeru Fireblade|r in the Cleft of Shadow. Accept his quest, then pick the dialogue option about the Burning Blade
    .accept 5761 >> Accept Slaying the Beast
    .complete 5727,1 --Gauge Neeru Fireblade's reaction to you being a member of the Burning Blade
    .skipgossip
    .target Neeru Fireblade
step
    .goto 1454/1,-4125.79,1920.10
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Thrall|r
    .turnin 5727 >> Turn in Hidden Enemies
    .accept 5728 >> Accept Hidden Enemies
    .target Thrall
step
    .goto Orgrimmar,45.120,63.889
    >>|cRXP_WARN_Rahauro's two RFC quests are in Thunder Bluff. A group member can share them instead - if they do, this trip skips itself|r
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Doras|r and open his flight map (gets the Orgrimmar flight path and shows what you know)
    .fp Orgrimmar >> Get the Orgrimmar flight path
    .target Doras
    .zoneskip Orgrimmar,1
    .needanyquest 5722,5723
step
    #completewith RFCRahauro2
    .goto Orgrimmar,45.120,63.889
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Doras|r
    .fly Thunder Bluff >> Fly to Thunder Bluff
    .target Doras
    .zoneskip Orgrimmar,1
    .fpknown 22
    .needanyquest 5722,5723
step
    #completewith next
    .goto Durotar,45.6,12.4,30,0
    .goto Durotar,34.4,42.4,30,0
    .goto 1413/1,-2595.75,-437.35,30 >> No Thunder Bluff flight path: run out of Orgrimmar's front gate, south to the bridge over the Southfury, then west to The Crossroads
    .fpknown 22,1
    .zoneskip Thunder Bluff
    .needanyquest 5722,5723
step
    .goto 1413/1,-2595.75,-437.35
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Devrak|r
    .fp The Crossroads >> Get the The Crossroads flight path
    .target Devrak
    .fpknown 22,1
    .zoneskip Thunder Bluff
    .needanyquest 5722,5723
step
    #completewith next
    .goto 1413/1,-1881.35,-2384.50,30 >> Run south down the road to Camp Taurajo
    .fpknown 22,1
    .zoneskip Thunder Bluff
    .needanyquest 5722,5723
step
    .goto 1413/1,-1881.35,-2384.50
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Omusa|r
    .fp Camp Taurajo >> Get the Camp Taurajo flight path
    .target Omusa Thunderhorn
    .fpknown 22,1
    .zoneskip Thunder Bluff
    .needanyquest 5722,5723
step
    #completewith RFCRahauro2
    .goto 1412/1,-1527.78,-2341.62,60,0
    .goto 1412/1,-341.02,-2173.79,80,0
    .goto 1456/1,182.67,-1314.05,40,0
    .zone Thunder Bluff >> Head west into Mulgore, past Bloodhoof Village, north to Thunder Bluff and ride a lift up
    .fpknown 22,1
    .zoneskip Thunder Bluff
    .needanyquest 5722,5723
step
    .goto 1456/1,26.1,-1196.66
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tal|r at the top of the tower
    .fp Thunder Bluff >> Get the Thunder Bluff flight path
    .target Tal
    .zoneskip Thunder Bluff,1
    .needanyquest 5722,5723
step
    #label RFCRahauro2
    .goto 1456/1,-218.13,-1055.97
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Rahauro|r on the Elder Rise
    .accept 5723 >> Accept Testing an Enemy's Strength
    .target Rahauro
step
    .goto 1456/1,-218.13,-1055.97
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Rahauro|r AGAIN - he has a second quest
    .accept 5722 >> Accept Searching for the Lost Satchel
    .target Rahauro
step
    .goto 1456/1,26.1,-1196.66
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tal|r
    .fly Orgrimmar >> Fly back to Orgrimmar
    .target Tal
    .zoneskip Thunder Bluff,1
step
    #completewith next
    .goto 1411/1,-4648.55,1321.88,40 >> Still need Varimathras' quest: go up the Zeppelin Tower outside Orgrimmar
    .zone Tirisfal Glades >> Take the Zeppelin to Tirisfal Glades
    .isQuestAvailable 5725
    .isNotOnQuest 5725
step
    #completewith next
    .goto 1420/0,240.75,1877.57,20 >> Enter Undercity
    .zoneskip Undercity
    .zoneskip Tirisfal Glades,1
    .isQuestAvailable 5725
    .isNotOnQuest 5725
step
    #completewith next
    .goto 1458,65.50,56.75,20,0
    .goto 1458,64.42,64.62,20,0
    .goto 1458,51.88,64.84,20,0
    .goto 1458,46.28,73.10,15,0
    .goto 1458,45.31,78.24,15,0
    .goto 1458,46.18,83.63,15,0
    .goto 1458,48.80,87.63,15,0
    .goto 1458,52.45,89.49,15,0
    .goto 1458,56.4,92.4,12 >>Travel to the Royal Quarter
    .zoneskip Undercity,1
    .isNotOnQuest 5725
step
    .goto 1458,56.4,92.4
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Varimathras|r beside Sylvanas
    .accept 5725 >> Accept The Power to Destroy...
    .target Varimathras
    .zoneskip Undercity,1
step
    #completewith next
    .goto 1458,52.45,89.49,15,0
    .goto 1458,48.80,87.63,15,0
    .goto 1458,46.18,83.63,15,0
    .goto 1458,45.31,78.24,15,0
    .goto 1458,46.28,73.10,15,0
    .goto 1458,51.88,64.84,20,0
    .goto 1458,64.42,64.62,20,0
    .goto 1458,65.50,56.75,20,0
    .goto 1420/0,235.32,1883.89
    .zone Tirisfal Glades >> Exit Undercity by the elevators
    .zoneskip Undercity,1
step
    .goto 1420/0,278.70,2071.27,12,0
    .goto 1420/0,253.85,2059.82,10,0
    .goto 1420/0,264.70,2053.50,8,0
    .goto 1420/0,271.02,2064.94,8,0
    .goto 1420/0,259.72,2068.86,8,0
    .goto 1420/0,261.53,2055.00,8,0
    .goto 1420/0,299.04,2069.46,-1
    .goto 1420/0,279.61,2441.21,-1
    .zone Durotar >> Take the Zeppelin back to Durotar
    .zoneskip Durotar
    .continentskip 1415,1
step
    #completewith RFCMaur
    .goto 1454/1,-4420.76,1815.80
    .subzone 2437 >> Get a group and enter Ragefire Chasm - the portal is in the Cleft of Shadow, Orgrimmar
step
    #label RFCMaur
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tInside, find the body of |cRXP_FRIENDLY_Maur Grimtotem|r
    .turnin 5722 >> Turn in Searching for the Lost Satchel
    .accept 5724 >> Accept Returning the Lost Satchel
    .target Maur Grimtotem
    .isOnQuest 5722
step
    >>Clear the dungeon:
    >>Kill 8 |cRXP_ENEMY_Ragefire Troggs|r and 8 |cRXP_ENEMY_Ragefire Shamans|r
    >>Loot |cRXP_LOOT_Spells of Shadow|r and |cRXP_LOOT_Incantations from the Nether|r from |cRXP_ENEMY_Searing Blade Cultists|r and |cRXP_ENEMY_Warlocks|r
    >>Kill |cRXP_ENEMY_Taragaman the Hungerer|r for his |cRXP_LOOT_Heart|r, and |cRXP_ENEMY_Bazzalan|r and |cRXP_ENEMY_Jergosh the Invoker|r
    .complete 5723,1 --Ragefire Trogg (8)
    .complete 5723,2 --Ragefire Shaman (8)
    .complete 5725,1 --Spells of Shadow (1)
    .complete 5725,2 --Incantations from the Nether (1)
    .complete 5761,1 --Taragaman the Hungerer's Heart
    .complete 5728,1 --Bazzalan (1)
    .complete 5728,2 --Jergosh the Invoker (1)
step
    .goto 1454/1,-4376.29,1802.43
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Neeru Fireblade|r
    .turnin 5761 >> Turn in Slaying the Beast
    .target Neeru Fireblade
    .isQuestComplete 5761
step
    .goto 1454/1,-4125.79,1920.10
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Thrall|r
    .turnin 5728 >> Turn in Hidden Enemies
    .accept 5729 >> Accept Hidden Enemies
    .target Thrall
    .isQuestComplete 5728
step
    .goto 1454/1,-4376.29,1802.43
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Neeru Fireblade|r
    .turnin 5729 >> Turn in Hidden Enemies
    .accept 5730 >> Accept Hidden Enemies
    .target Neeru Fireblade
    .isQuestTurnedIn 5728
step
    .goto 1454/1,-4125.79,1920.10
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Thrall|r
    .turnin 5730 >> Turn in Hidden Enemies
    .target Thrall
    .isQuestTurnedIn 5728
step
    #completewith next
    .goto Orgrimmar,45.120,63.889
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Doras|r
    .fly Thunder Bluff >> Fly to Thunder Bluff
    .target Doras
    .zoneskip Thunder Bluff
    .onanyquest 5723,5724
step
    .goto 1456/1,-218.13,-1055.97
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Rahauro|r on the Elder Rise
    .turnin -5724 >> Turn in Returning the Lost Satchel
    .turnin -5723 >> Turn in Testing an Enemy's Strength
    .target Rahauro
step
    >>|cRXP_WARN_Varimathras is last: back to Orgrimmar for the zeppelin to Undercity|r
    .hs >> Hearth to Orgrimmar
    .use 6948
    .cooldown item,6948,>2,1
    .bindlocation 1637,1
    .zoneskip Thunder Bluff,1
    .isQuestComplete 5725
step
    .goto 1456/1,26.1,-1196.66
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tal|r
    .fly Orgrimmar >> Fly to Orgrimmar
    .target Tal
    .zoneskip Thunder Bluff,1
    .isQuestComplete 5725
step
    #completewith next
    .goto 1411/1,-4648.55,1321.88,40 >> Go up the Zeppelin Tower outside Orgrimmar
    .zone Tirisfal Glades >> Take the Zeppelin to Tirisfal Glades for Varimathras
    .isQuestComplete 5725
step
    #completewith next
    .goto 1420/0,240.75,1877.57,20 >> Enter Undercity
    .zoneskip Undercity
    .zoneskip Tirisfal Glades,1
    .isQuestComplete 5725
step
    #completewith next
    .goto 1458,65.50,56.75,20,0
    .goto 1458,64.42,64.62,20,0
    .goto 1458,51.88,64.84,20,0
    .goto 1458,46.28,73.10,15,0
    .goto 1458,45.31,78.24,15,0
    .goto 1458,46.18,83.63,15,0
    .goto 1458,48.80,87.63,15,0
    .goto 1458,52.45,89.49,15,0
    .goto 1458,56.4,92.4,12 >>Travel to the Royal Quarter
    .zoneskip Undercity,1
    .isQuestComplete 5725
step
    .goto 1458,56.4,92.4
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Varimathras|r
    .turnin 5725 >> Turn in The Power to Destroy...
    .target Varimathras
    .isQuestComplete 5725
]])
end

-- ===== Wailing Caverns dungeon quests (Horde) - pre-dungeon pickups (1 Oct 2026, Gaz: "add a Wailing Caverns pre dungeon quest
-- pick up guide to the RXP app") =====
-- Quests (Wowhead Forever zone 718; level needed in brackets): Deviate Hides 1486 (Nalpak, 13) and Deviate Eradication 1487
-- (Ebru, 15) - both above the cave entrance; Smart Drinks 1491 (Mebok Mizzyrix, Ratchet, 13); Trouble at the Docks 959
-- (Crane Operator Bigglefuzz, Ratchet, 14); Serpentbloom 962 (Apothecary Zamah, Thunder Bluff, 14); Leaders of the Fang 914
-- (Nara Wildmane, Thunder Bluff, 10) after Hamuul Runetotem 1489 (Tonga, Crossroads) -> 1490 (Hamuul, Thunder Bluff) -> 914.
-- Coordinates are RXP's own (forever/Horde-12-22_Barrens.lua WC block and its Ratchet / Thunder Bluff steps).
-- Route: (Orgrimmar ->) Crossroads (Tonga) -> Ratchet (Bigglefuzz, Mebok) -> Crossroads -> Thunder Bluff (Zamah, Hamuul,
-- Nara) -> Crossroads -> the cave. Every stop skips itself when its quests are done / in the log (.needanyquest,
-- .isQuestAvailable). Fly-vs-walk uses .fpknown (node ids: Orgrimmar 23, Crossroads 25, Thunder Bluff 22, Ratchet 80).
-- v3 (1 Oct, Gaz: 'add them all, all chains, in the right order'): Tonga chain 870 -> 877 -> 880 -> Hamuul 1489 (Barrens, no TB needed
-- until 1489/1490/914), Mebok 865 -> Smart Drinks 1491, outside + inside objectives, Glowing Shard 6981 -> In Nightmares 3369.
-- NOTE: Smart Drinks 1491 needs Raptor Horns 865 handed in first (Questie classic DB preQuestSingle {865}); Trouble at the Docks,
-- Serpentbloom, Deviate Hides and Deviate Eradication have no prerequisite.
-- NOTE: Leaders of the Fang needs the Barrens chain Altered Beings 880 -> Hamuul Runetotem 1489 -> Nara 1490; a character that
-- skipped it is not offered 1489 by Tonga, so those steps stay hidden (.isQuestTurnedIn / .isQuestComplete). .isQuestAvailable only
-- means 'not handed in yet' - it does NOT check prerequisites. UNVERIFIED in game.
if RXPGuides and RXPGuides.RegisterGuide then
	RXPGuides.RegisterGuide([[
<< Horde
#forever
#version 1
#group Forever Dungeons (H)
#name Wailing Caverns dungeon quests
step
    #completewith WCXroadsFP
    .goto Orgrimmar,45.120,63.889
    >>|cRXP_WARN_Wailing Caverns (Barrens, level 15-25): quests need level 10-15. This loop collects them: Crossroads, Ratchet, Thunder Bluff, then the cave. A stop you have already done skips itself|r
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Doras|r
    .fly Crossroads >> Fly to The Crossroads
    .target Doras
    .zoneskip Orgrimmar,1
    .fpknown 25
step
    #completewith WCXroadsFP
    .goto 1413/1,-2680.87,-365.05,150,0
    .subzone 380 >> Travel to The Crossroads
    .zoneskip Orgrimmar,1
    .fpknown 25,1
step
    #label WCXroadsFP
    .goto 1413/1,-2595.75,-437.35
    >>|cRXP_WARN_Wailing Caverns quest loop: Crossroads, Ratchet, Thunder Bluff, then the cave|r
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Devrak|r
    .fp Crossroads >> Get the Crossroads flight path
    .target Devrak
    .zoneskip The Barrens,1
step
    .goto 1413/1,-2672.76,-544.77
    >>|cRXP_WARN_Tonga's Barrens chain unlocks Hamuul Runetotem, then Nara and Leaders of the Fang (a dungeon quest worth about 6,400 XP): The Forgotten Pools, The Stagnant Oasis, Altered Beings|r
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tonga|r
    .accept 870 >> Accept The Forgotten Pools
    .target Tonga Runetotem
    .isQuestAvailable 870
    .xp <10,1
    .zoneskip The Barrens,1
step
    #completewith WCPools
    .goto 1413/1,-1943.16,89.64,60 >> Travel to the Forgotten Pools
    .isOnQuest 870
step
    #label WCPools
    .goto 1413/1,-1943.16,89.64
    >>Dive underwater to the |cRXP_PICK_Bubbling Fissure|r
    .complete 870,1 --Explore the waters of the Forgotten Pools
    .isOnQuest 870
step
    #label WCTonga1
    .goto 1413/1,-2672.76,-544.77
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tonga|r
    .turnin 870 >> Turn in The Forgotten Pools
    .accept 877 >> Accept The Stagnant Oasis
    .target Tonga Runetotem
    .isQuestComplete 870
step
    .goto 1413/1,-2672.76,-544.77
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tonga|r
    .accept 877 >> Accept The Stagnant Oasis
    .target Tonga Runetotem
    .isQuestTurnedIn 870
    .isQuestAvailable 877
step
    #completewith WCOasis
    .goto 1413/1,-3012.23,-1275.80,60 >> Travel to the Stagnant Oasis
    .isOnQuest 877
step
    #label WCOasis
    .goto 1413/1,-3012.23,-1275.80
    >>Click the |cRXP_PICK_Bubbling Fissure|r underwater
    .complete 877,1 --Test the Dried Seeds (1)
    .isOnQuest 877
step
    #label WCTonga2
    .goto 1413/1,-2672.76,-544.77
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tonga|r
    .turnin 877 >> Turn in The Stagnant Oasis
    .accept 880 >> Accept Altered Beings
    .target Tonga Runetotem
    .isQuestComplete 877
step
    .goto 1413/1,-2672.76,-544.77
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tonga|r
    .accept 880 >> Accept Altered Beings
    .target Tonga Runetotem
    .isQuestTurnedIn 877
    .isQuestAvailable 880
step
    #completewith WCShells
    .goto 1413/1,-3010.20,-1319.04,60 >> Travel back to the Stagnant Oasis lake
    .isOnQuest 880
step
    #label WCShells
    #loop
    .goto 1413/1,-3010.20,-1319.04,0
    .goto 1413/1,-3010.20,-1319.04,40,0
    .goto 1413/1,-2959.54,-1292.69,40,0
    .goto 1413/1,-2953.46,-1239.31,40,0
    .goto 1413/1,-2998.04,-1192.02,40,0
    .goto 1413/1,-3050.74,-1225.13,40,0
    .goto 1413/1,-3066.95,-1260.93,40,0
    .goto 1413/1,-3052.76,-1319.710,40,0
    >>Kill |cRXP_ENEMY_Oasis Snapjaws|r in and around the lake. Loot them for their |cRXP_LOOT_Shells|r
    .complete 880,1 --Altered Snapjaw Shell (8)
    .mob Oasis Snapjaw
    .isOnQuest 880
step
    #label WCTonga3
    .goto 1413/1,-2672.76,-544.77
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tonga|r
    .turnin 880 >> Turn in Altered Beings
    .accept 1489 >> Accept Hamuul Runetotem
    .accept 3301 >> Accept Mura Runetotem
    .target Tonga Runetotem
    .isQuestComplete 880
step
    .goto 1413/1,-2672.76,-544.77
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tonga|r
    .accept 1489 >> Accept Hamuul Runetotem
    .accept 3301 >> Accept Mura Runetotem
    .target Tonga Runetotem
    .isQuestTurnedIn 880
    .isQuestAvailable 1489
step
    #completewith WCRatchet
    .goto 1413/1,-2595.75,-437.35
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Devrak|r
    .fly Ratchet >> Fly to Ratchet
    .target Devrak
    .fpknown 80
    .needanyquest 959,865,1491
    .xp <13,1
step
    #completewith WCRatchet
    .goto 1413/1,-3770.20,-898.12,30 >> No Ratchet flight path yet: run east along the road to Ratchet (Bragok will give you the flight path)
    .fpknown 80,1
    .needanyquest 959,865,1491
    .xp <13,1
step
    .goto 1413/1,-3770.20,-898.12
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Bragok|r
    .fp Ratchet >> Get the Ratchet flight path
    .target Bragok
    .needanyquest 959,865,1491
    .xp <13,1
step
    #label WCRatchet
    .goto 1413/1,-3770.20,-928.53
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Bigglefuzz|r
    .accept 959 >> Accept Trouble at the Docks
    .target Crane Operator Bigglefuzz
    .isQuestAvailable 959
    .xp <14,1
step
    .goto 1413/1,-3697.24,-929.20
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Mebok|r
    .accept 865 >> Accept Raptor Horns
    .target Mebok Mizzyrix
    .isQuestAvailable 865
    .xp <13,1
step
    #completewith WCHorns
    .goto 1413/1,-3183.48,-2015.61,90 >> Travel south to the Sunscale Scytheclaws
    .isOnQuest 865
step
    #label WCHorns
    #loop
    .goto 1413/1,-3183.48,-2015.61,0
    .goto 1413/1,-2646.42,-1529.16,0
    .goto 1413/1,-3183.48,-2015.61,90,0
    .goto 1413/1,-2646.42,-1529.16,90,0
    >>Kill |cRXP_ENEMY_Sunscale Scytheclaws|r. Loot them for their |cRXP_LOOT_Horns|r
    >>|cRXP_WARN_Be careful as they cast|r |T132152:0|t[Thrash] |cRXP_WARN_(Charges 2 extra attacks every 10 seconds)|r
    .complete 865,1 --Intact Raptor Horn (5)
    .mob Sunscale Scytheclaw
    .isOnQuest 865
step
    #completewith WCMebok2
    .goto 1413/1,-3697.24,-929.20,40 >> Return to Mebok in Ratchet
    .isQuestComplete 865
step
    #label WCMebok2
    .goto 1413/1,-3697.24,-929.20
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Mebok|r
    .turnin 865 >> Turn in Raptor Horns
    .accept 1491 >> Accept Smart Drinks
    .target Mebok Mizzyrix
    .isQuestComplete 865
    .xp <13,1
step
    .goto 1413/1,-3697.24,-929.20
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Mebok|r
    .accept 1491 >> Accept Smart Drinks
    .target Mebok Mizzyrix
    .isQuestTurnedIn 865
    .isQuestAvailable 1491
    .xp <13,1
step
    #completewith WCBackXroads
    .goto 1413/1,-3770.20,-898.12
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Bragok|r
    .fly Crossroads >> Fly to The Crossroads
    .target Bragok
    .subzoneskip 392,1
step
    #label WCBackXroads
    .subzone 380 >> Be at The Crossroads
    .zoneskip The Barrens,1
    .subzoneskip 380
    .needanyquest 914,962
step
    #completewith WCThunderBluff
    .goto 1413/1,-2595.75,-437.35
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Devrak|r
    .fly Thunder Bluff >> Fly to Thunder Bluff
    .target Devrak
    .fpknown 22
    .needanyquest 914,962
    .zoneskip Thunder Bluff
step
    #completewith WCThunderBluff
    .goto 1413/1,-1881.35,-2384.50,30 >> No Thunder Bluff flight path yet: run south down the road to Camp Taurajo
    .fpknown 22,1
    .needanyquest 914,962
    .zoneskip Thunder Bluff
step
    #completewith WCThunderBluff
    .goto 1413/1,-1881.35,-2384.50
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Omusa|r
    .fp Camp Taurajo >> Get the Camp Taurajo flight path
    .target Omusa Thunderhorn
    .fpknown 22,1
    .needanyquest 914,962
    .zoneskip Thunder Bluff
step
    #completewith WCThunderBluff
    .goto 1412/1,-1527.78,-2341.62,60,0
    .goto 1412/1,-341.02,-2173.79,80,0
    .goto 1456/1,182.67,-1314.05,40,0
    .zone Thunder Bluff >> Head west into Mulgore, past Bloodhoof Village, north to Thunder Bluff and ride a lift up
    .fpknown 22,1
    .needanyquest 914,962
    .zoneskip Thunder Bluff
step
    .goto 1456/1,26.1,-1196.66
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tal|r at the top of the tower
    .fp Thunder Bluff >> Get the Thunder Bluff flight path
    .target Tal
    .zoneskip Thunder Bluff,1
step
    #label WCThunderBluff
    .goto 1456/1,278.48,-995.29
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Zamah|r on the Spirit Rise
    .accept 962 >> Accept Serpentbloom
    .target Apothecary Zamah
    .xp <14,1
    .zoneskip Thunder Bluff,1
step
    #completewith next
    .goto 1456/1,-212.71,-1065.010,80 >> Travel to the Elder Rise
    .needanyquest 914
    .zoneskip Thunder Bluff,1
step
    .goto 1456/1,-303.83,-1048.66
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Hamuul|r
    .turnin 1489 >> Turn in Hamuul Runetotem
    .accept 1490 >> Accept Nara Wildmane
    .target Arch Druid Hamuul Runetotem
    .isOnQuest 1489
    .zoneskip Thunder Bluff,1
step
    .goto 1456/1,-303.83,-1048.66
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Hamuul|r
    .accept 1490 >> Accept Nara Wildmane
    .target Arch Druid Hamuul Runetotem
    .isQuestTurnedIn 1489
    .isQuestAvailable 1490
    .zoneskip Thunder Bluff,1
step
    .goto 1456/1,-272.93,-1069.67
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Nara|r
    .turnin 1490 >> Turn in Nara Wildmane
    .accept 914 >> Accept Leaders of the Fang
    .target Nara Wildmane
    .isOnQuest 1490
    .zoneskip Thunder Bluff,1
step
    .goto 1456/1,-272.93,-1069.67
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Nara|r
    .accept 914 >> Accept Leaders of the Fang
    .target Nara Wildmane
    .isQuestTurnedIn 1490
    .isQuestAvailable 914
    .zoneskip Thunder Bluff,1
step
    #completewith WCCave
    .goto 1456/1,26.1,-1196.66
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tal|r
    .fly Crossroads >> Fly back to The Crossroads
    .target Tal
    .zoneskip Thunder Bluff,1
step
    #completewith WCCave
    .goto 1413/1,-2053.62,-882.58,100 >> Travel to Wailing Caverns
    .xp <13,1
step
    #completewith WCCave
    .goto 1413/1,-2134.68,-764.35,0
    .goto 1413/1,-2134.68,-764.35,30,0
    .goto 1413/1,-2122.52,-734.62,20,0
    .goto 1414/1,-2061.94,-781.68,20,0
    .goto 1414/1,-2028.82,-828.29,10,0
    .goto 1414/1,-2021.46,-816.030,10 >>Run up the mountain at the Wailing Caverns meeting stone
    >>|cRXP_WARN_Follow the arrow closely to reach the hidden cave|r
    .xp <13,1
step
    #label WCCave
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Nalpak|r and |cRXP_FRIENDLY_Ebru|r
    >>|cRXP_WARN_They are located above the Wailing Caverns cave entrance|r
    .accept 1486 >> Accept Deviate Hides
    .target +Nalpak
    .goto 1414/1,-2036.18,-796.40
    .accept 1487 >> Accept Deviate Eradication
    .target +Ebru
    .goto 1414/1,-2039.86,-801.31
    .xp <13,1
step
    #completewith WCEnter
    >>Loot the |cRXP_PICK_Serpentbloom|r on the ground around the cave entrance
    >>|cRXP_WARN_Cast|r |T133939:0|t[Find Herbs] |cRXP_WARN_to see them on your minimap if you have it. Group members share these - take only what you need|r
    .complete 962,1 --Serpentbloom (10)
    .isOnQuest 962
step
    #completewith WCEnter
    >>Kill |cRXP_ENEMY_Deviate Beasts|r outside and inside. Loot them for their |cRXP_LOOT_Hides|r
    .complete 1486,1 --Deviate Hide (20)
    .isOnQuest 1486
step
    #loop
    .goto 1414/1,-2058.26,-749.79,0
    .goto 1414/1,-2003.06,-659.01,0
    .goto 1414/1,-2072.98,-698.27,0
    .goto 1414/1,-2124.50,-730.16,0
    .goto 1414/1,-2058.26,-749.79,30,0
    .goto 1414/1,-2003.06,-659.01,30,0
    .goto 1414/1,-2072.98,-698.27,30,0
    .goto 1414/1,-2124.50,-730.16,30,0
    >>Kill |cRXP_ENEMY_Mad Magglish|r. Loot him for the |cRXP_LOOT_99-Year-Old Port|r
    >>|cRXP_WARN_He has a long respawn timer. Skip this step if you cannot find him|r
    .complete 959,1 --99-Year-Old Port (1)
    .mob Mad Magglish
    .isOnQuest 959
step
    #label WCEnter
    .goto 1414/1,-2028.82,-636.93,20,0
    .goto 1414/1,-2050.90,-585.41,20,0
    .goto 1414/1,-2168.66,-607.49,30,0
    .goto 1414/1,-2216.5,-742.43,30 >> Enter the Wailing Caverns portal. Zone in with your group
step
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to the |cRXP_FRIENDLY_Disciple of Naralex|r just inside the entrance
    >>|cRXP_WARN_He starts the escort quest. You cannot start the escort itself until the four Fanglords are dead|r
    .accept 999 >> Accept When Dreams Turn to Nightmares
    .target Disciple of Naralex
step
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to the |cRXP_FRIENDLY_Disciple of Naralex|r
    .accept 1500 >> Accept Waking Naralex
    .target Disciple of Naralex
step
    #completewith WCShard
    >>Kill |cRXP_ENEMY_Ectoplasms|r. Loot them for their |cRXP_LOOT_Essence|r
    .complete 1491,1 --Wailing Essence (6)
    .isOnQuest 1491
step
    #completewith WCShard
    >>Kill |cRXP_ENEMY_Deviate Ravagers|r, |cRXP_ENEMY_Vipers|r, |cRXP_ENEMY_Shamblers|r and |cRXP_ENEMY_Dreadfangs|r. The Deviate Beasts also drop the hides
    .complete 1487,1 --Deviate Ravager (7)
    .mob +Deviate Ravager
    .complete 1487,2 --Deviate Viper (7)
    .mob +Deviate Viper
    .complete 1487,3 --Deviate Shambler (7)
    .mob +Deviate Shambler
    .complete 1487,4 --Deviate Dreadfang (7)
    .mob +Deviate Dreadfang
    .complete 1486,1 --Deviate Hide (20)
    .isOnQuest 1487
step
    #completewith WCShard
    >>Kill |cRXP_ENEMY_Lord Cobrahn|r, |cRXP_ENEMY_Lady Anacondra|r, |cRXP_ENEMY_Lord Pythas|r and |cRXP_ENEMY_Lord Serpentis|r. Loot them for their |cRXP_LOOT_Gems|r
    .complete 914,1 --Gem of Cobrahn (1)
    .mob +Lord Cobrahn
    .complete 914,2 --Gem of Anacondra (1)
    .mob +Lady Anacondra
    .complete 914,3 --Gem of Pythas (1)
    .mob +Lord Pythas
    .complete 914,4 --Gem of Serpentis (1)
    .mob +Lord Serpentis
    .isOnQuest 914
step
    +|Tinterface/worldmap/chatbubble_64grey.blp:20|tOnce Cobrahn, Anacondra, Pythas and Serpentis (and Verdan the Everliving, if you take him) are dead, go back to the entrance and talk to the |cRXP_FRIENDLY_Disciple of Naralex|r to begin the escort: he stops three times and you are ambushed on the way, then two waves at Naralex before Mutanus
    .target Disciple of Naralex
    .skipgossip
step
    #label WCShard
    >>Once you reach |cRXP_FRIENDLY_Naralex|r you are attacked by waves of enemies and finally |cRXP_ENEMY_Mutanus the Devourer|r. Kill him and loot the |T135229:0|t[|cRXP_LOOT_Glowing Shard|r]
    .collect 10441,1 --Collect Glowing Shard (x1)
    .mob Mutanus the Devourer
step
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to the |cRXP_FRIENDLY_Disciple of Naralex|r
    .turnin 999 >> Turn in When Dreams Turn to Nightmares
    .target Disciple of Naralex
    .isQuestComplete 999
step
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to the |cRXP_FRIENDLY_Disciple of Naralex|r
    .turnin 1500 >> Turn in Waking Naralex
    .target Disciple of Naralex
    .isQuestComplete 1500
step
    .goto 1414/1,-2036.18,-796.40
    +|cRXP_WARN_Ready: you now have the Wailing Caverns quests. That is every Wailing Caverns quest from the chains onwards. Dungeon first, then the hand-ins below|r
step
    .goto 1414/1,-2036.18,-796.40
    +|cRXP_WARN_Hand-ins start here, after the dungeon: the cave top, then Ratchet, then Thunder Bluff. A stop you cannot hand in yet is hidden|r
step
    >>|cRXP_WARN_Use the Glowing Shard (Mutanus the Devourer drops it) to start the quest|r
    .accept 6981 >> Accept The Glowing Shard
    .use 10441
    .itemcount 10441,1
step
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Nalpak|r and |cRXP_FRIENDLY_Ebru|r
    >>|cRXP_WARN_They are located above the Wailing Caverns cave entrance|r
    .turnin 1486 >> Turn in Deviate Hides
    .target +Nalpak
    .goto 1414/1,-2036.18,-796.40
    .turnin 1487 >> Turn in Deviate Eradication
    .target +Ebru
    .goto 1414/1,-2039.86,-801.31
    .isQuestComplete 1487
    .isQuestComplete 1486
step
    .goto 1414/1,-2039.86,-801.31
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Ebru|r
    >>|cRXP_WARN_He is located above the Wailing Caverns cave entrance|r
    .turnin 1487 >> Turn in Deviate Eradication
    .target Ebru
    .isQuestComplete 1487
step
    .goto 1414/1,-2036.18,-796.40
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Nalpak|r
    >>|cRXP_WARN_He is located above the Wailing Caverns cave entrance|r
    .turnin 1486 >> Turn in Deviate Hides
    .target Nalpak
    .isQuestComplete 1486
step
    #completewith WCHandRatchet
    .hs >> Hearth to Ratchet
    .use 6948
    .cooldown item,6948,>2,1
    .subzoneskip 392
    .bindlocation 392,1
    .onanyquest 959,1491,6981
step
    #completewith WCHandRatchet
    .goto 1413/1,-2595.75,-437.35,60 >> Travel to The Crossroads (or use your hearthstone if it is ready)
    .onanyquest 959,1491,6981
    .subzoneskip 380
    .subzoneskip 392
step
    #completewith WCHandRatchet
    .goto 1413/1,-2595.75,-437.35
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Devrak|r
    .fly Ratchet >> Fly to Ratchet
    .target Devrak
    .fpknown 80
    .onanyquest 959,1491,6981
    .subzoneskip 392
step
    #completewith WCHandRatchet
    .goto 1413/1,-3770.20,-898.12,30 >> No Ratchet flight path: run east along the road to Ratchet
    .fpknown 80,1
    .onanyquest 959,1491,6981
    .subzoneskip 392
step
    #label WCHandRatchet
    .goto 1413/1,-3697.24,-929.20
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Mebok|r
    .turnin 1491 >> Turn in Smart Drinks
    .target Mebok Mizzyrix
    .isQuestComplete 1491
step
    .goto 1413/1,-3770.20,-928.53
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Bigglefuzz|r
    .turnin 959 >> Turn in Trouble at the Docks
    .target Crane Operator Bigglefuzz
    .isQuestComplete 959
step
    .goto 1413/1,-3760.07,-902.18
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Sputtervalve|r
    .complete 6981,1 --Speak with someone in Ratchet about the Glowing Shard
    .skipgossip
    .target Sputtervalve
    .isOnQuest 6981
step
    #completewith WCHandFalla
    .goto 1413/1,-3770.20,-898.12
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Bragok|r
    .fly Crossroads >> Fly to The Crossroads
    .target Bragok
    .subzoneskip 392,1
    .onanyquest 914,962,3369,6981
step
    #completewith WCHandFalla
    .goto 1413/1,-2493.40,-708.95,20,0
    .goto 1413/1,-2404.23,-721.11,20,0
    .goto 1413/1,-2356.60,-685.98,20,0
    .goto 1413/1,-2259.32,-602.20,50 >> Travel up the mountain
    .isOnQuest 6981
step
    #label WCHandFalla
    .goto 1413/1,-2259.32,-602.20
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Falla|r
    .turnin 6981 >> Turn in The Glowing Shard
    .accept 3369 >> Accept In Nightmares
    .target Falla Sagewind
    .isOnQuest 6981
step
    .goto 1413/1,-2259.32,-602.20
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Falla|r
    .accept 3369 >> Accept In Nightmares
    .target Falla Sagewind
    .isQuestTurnedIn 6981
step
    #completewith WCHandTB
    .goto 1413/1,-2595.75,-437.35
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Devrak|r
    .fly Thunder Bluff >> Fly to Thunder Bluff
    .target Devrak
    .fpknown 22
    .onanyquest 914,962,3369
    .zoneskip Thunder Bluff
step
    #completewith WCHandTB
    .goto 1413/1,-1881.35,-2384.50,30 >> No Thunder Bluff flight path: run south down the road to Camp Taurajo
    .fpknown 22,1
    .onanyquest 914,962,3369
    .zoneskip Thunder Bluff
step
    #completewith WCHandTB
    .goto 1413/1,-1881.35,-2384.50
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Omusa|r
    .fp Camp Taurajo >> Get the Camp Taurajo flight path
    .target Omusa Thunderhorn
    .fpknown 22,1
    .onanyquest 914,962,3369
    .zoneskip Thunder Bluff
step
    #completewith WCHandTB
    .goto 1412/1,-1527.78,-2341.62,60,0
    .goto 1412/1,-341.02,-2173.79,80,0
    .goto 1456/1,182.67,-1314.05,40,0
    .zone Thunder Bluff >> Head west into Mulgore, past Bloodhoof Village, north to Thunder Bluff and ride a lift up
    .fpknown 22,1
    .onanyquest 914,962,3369
    .zoneskip Thunder Bluff
step
    #label WCHandTB
    .goto 1456/1,-272.93,-1069.67
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Nara|r
    .turnin 914 >> Turn in Leaders of the Fang
    .target Nara Wildmane
    .isQuestComplete 914
step
    .goto 1456/1,-303.83,-1048.66
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Hamuul|r
    .turnin 3369 >> Turn in In Nightmares
    .target Arch Druid Hamuul Runetotem
    .isOnQuest 3369
step
    #completewith next
    .goto 1456/1,219.09,-1051.44,10 >> Travel to the Spirit Rise and enter the pools of vision
    .isQuestComplete 962
step
    .goto 1456/1,276.6,-996.12
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Apothecary Zamah|r
    .turnin 962 >> Turn in Serpentbloom
    .target Apothecary Zamah
    .isQuestComplete 962
step
    #completewith WCMura
    .hs >> Hearth to the Undercity
    .use 6948
    .cooldown item,6948,>2,1
    .zoneskip Undercity
    .bindlocation 1497,1
    .isOnQuest 3301
step
    #completewith WCMura
    .goto 1458/0,266.20,1567.17,12 >> Travel to the Undercity flight master
    .zoneskip Undercity,1
    .isOnQuest 3301
step
    #completewith WCMura
    .goto 1458/0,266.20,1567.17
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Michael Garrett|r
    .fly Sepulcher >> Fly to The Sepulcher
    .target Michael Garrett
    .zoneskip Undercity,1
    .isOnQuest 3301
step
    #label WCMura
    .goto 1421,42.91,41.99
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Mura Runetotem|r in the Sepulcher
    .turnin 3301 >> Turn in Mura Runetotem
    .target Mura Runetotem
    .isOnQuest 3301
]])
end

-- ===== Shadowfang Keep dungeon quests (Horde) =====
-- Wowhead Forever zone 209 lists exactly three quests, all Horde and all from Classic (4 Oct 2026; Questie's classic DB agrees,
-- no prerequisites): 1013 The Book of Ur (Keeper Bel'dugur, Undercity, req 16 - loot the book in the dungeon, hand in at
-- Bel'dugur), 1098 Deathstalkers in Shadowfang (High Executor Hadrec, The Sepulcher, req 18 - find Deathstalker Adamant and
-- Deathstalker Vincent INSIDE, hand in to Vincent), 1014 Arugal Must Die (Dalar Dawnweaver, The Sepulcher, req 18 - kill
-- Archmage Arugal, hand in to Dalar). Dungeon is level 22-30 on Forever, entrance Silverpine Forest ~44.8,67.8.
-- Raw XP (Wowhead page data) 2100 / 2000 / 3300; Forever multiplies dungeon-quest XP (a paladin saw 5600 for the Book at 18).
-- Coordinates: Hadrec's crypt route and Dalar from RXP's own Undead guide (forever/Horde-01-14_Undead.lua), Undercity transit
-- chain from RXP's Undercity routes used in the Ruins of Lordaeron guide above; Bel'dugur's spot 53.7,54.5 is from Questie's classic
-- DB / Wowhead (the path inside the Apothecarium is not mapped, the arrow points straight at him). Nothing in the dungeon has a
-- recorded position - the objectives are text steps. Order: Undercity (Book) -> Sepulcher (Hadrec + Dalar) -> dungeon ->
-- hand-ins: Vincent inside, then Dalar at the Sepulcher and Bel'dugur in Undercity (whichever you can hearth to first).
if RXPGuides and RXPGuides.RegisterGuide then
	RXPGuides.RegisterGuide([[
<< Horde
#forever
#version 1
#group Forever Dungeons (H)
#name Shadowfang Keep dungeon quests
step
    >>|cRXP_WARN_Shadowfang Keep is a level 22-30 dungeon on Forever, but its three quests only need level 16-18. You can pick them all up now|r
    .hs >> Hearth to the Undercity (for The Book of Ur)
    .use 6948
    .cooldown item,6948,>2,1
    .zoneskip Undercity
    .bindlocation 1497,1
    .isQuestAvailable 1013
    .isNotOnQuest 1013
step
    >>Fly to the Undercity from the nearest flight master (The Book of Ur is picked up there)
    .fly Undercity >> Fly to the Undercity
    .zoneskip Undercity+Tirisfal Glades+Silverpine Forest
    .continentskip 1415,1
    .isQuestAvailable 1013
    .isNotOnQuest 1013
step
    .goto 1411/1,-4648.55,1321.88,40 >>Go up the Zeppelin Tower outside Orgrimmar (fly to Orgrimmar first if you're far away)
    .zone Tirisfal Glades >>Take the Zeppelin to Tirisfal Glades
    .continentskip 1414,1
    .isQuestAvailable 1013
    .isNotOnQuest 1013
step
    #completewith next
    .goto 1420/0,240.75,1877.57,20 >> Enter Undercity
    .zoneskip Undercity
    .zoneskip Tirisfal Glades,1
    .isQuestAvailable 1013
    .isNotOnQuest 1013
step
    #completewith next
    .goto 1458,65.50,56.75,20,0
    .goto 1458,64.42,64.62,20,0
    .goto 1458,53.74,54.46,12 >>Travel to the Apothecarium. Keeper Bel'dugur stands in its north end
    .zoneskip Undercity,1
    .isQuestAvailable 1013
    .isNotOnQuest 1013
step
    .goto 1458,53.74,54.46
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Keeper Bel'dugur|r in the Apothecarium
    >>|cRXP_WARN_Position from the classic database; he may be a few yards away. Needs level 16|r
    .accept 1013 >>Accept The Book of Ur
    .target Keeper Bel'dugur
    .zoneskip Undercity,1
step
    .goto 1458/0,266.20,1567.17
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Michael|r
    .fly Sepulcher >> Fly to The Sepulcher
    .target Michael Garrett
    .zoneskip Undercity,1
    .needanyquest 1098,1014
step
    #completewith next
    .goto 1421/0,1640.22,509.43,8,0
    .goto 1421/0,1654.50,510.270,8,0
    .goto 1421/0,1654.08,521.470,8,0
    .goto 1421/0,1625.94,522.31,2 >> Enter the crypt below The Sepulcher
    .zoneskip Silverpine Forest,1
    .needanyquest 1098
step
    .goto 1421/0,1625.94,522.31
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Hadrec|r in the crypt
    >>|cRXP_WARN_Needs level 18|r
    .accept 1098 >>Accept Deathstalkers in Shadowfang
    .target High Executor Hadrec
    .zoneskip Silverpine Forest,1
step
    .goto 1421/0,1593.6,554.23
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Dalar|r
    >>|cRXP_WARN_Needs level 18|r
    .accept 1014 >>Accept Arugal Must Die
    .target Dalar Dawnweaver
    .zoneskip Silverpine Forest,1
step
    #label SFKEnter
    .goto 1421,44.8,67.8,12
    >>|cRXP_WARN_Walk south from The Sepulcher to the Shadowfang Keep entrance, west of Pyrewood Village (entrance at about 44.8, 67.8; Wowhead says 44,67). Zone in with your group|r
    .zone Shadowfang Keep >> Enter Shadowfang Keep
    .zoneskip Shadowfang Keep
step
    #completewith SFKDone
    >>Loot |cRXP_PICK_The Book of Ur|r from the bookshelf in the circular library room
    >>|cRXP_WARN_Wowhead comment, not verified: treating the big wolf in the middle of the room as 12 o'clock, it is on the shelf at 8 o'clock, bottom right corner. It respawns quickly|r
    .complete 1013,1 --The Book of Ur (1)
step
    #completewith SFKDone
    >>Find |cRXP_FRIENDLY_Deathstalker Adamant|r and |cRXP_FRIENDLY_Deathstalker Vincent|r inside Shadowfang Keep (both are friendly NPCs in the dungeon)
    .isOnQuest 1098
step
    #completewith SFKDone
    >>|cRXP_WARN_The dungeon is not linear. Do the bosses in any order|r
step
    #label SFKDone
    >>Kill |cRXP_ENEMY_Archmage Arugal|r in the top of the keep. Loot his |cRXP_LOOT_Head of Arugal|r
    .complete 1014,1 --Head of Arugal (1)
    .mob Archmage Arugal
step
    >>Talk to |cRXP_FRIENDLY_Deathstalker Vincent|r
    >>|cRXP_WARN_He stands inside Shadowfang Keep. If you have already left, go back in or skip this step: the quest just waits for you|r
    .turnin 1098 >>Turn in Deathstalkers in Shadowfang
    .target Deathstalker Vincent
    .isQuestComplete 1098
step
    #completewith next
    .hs >> Hearth to the Undercity (hand in The Book of Ur first, then fly to The Sepulcher)
    .use 6948
    .cooldown item,6948,>2,1
    .zoneskip Undercity
    .bindlocation 1497,1
    .isQuestComplete 1013
step
    .goto 1458,53.74,54.46
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Keeper Bel'dugur|r
    .turnin 1013 >>Turn in The Book of Ur
    .target Keeper Bel'dugur
    .zoneskip Undercity,1
    .isQuestComplete 1013
step
    .goto 1458/0,266.20,1567.17
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Michael|r
    .fly Sepulcher >> Fly to The Sepulcher for Arugal Must Die
    .target Michael Garrett
    .zoneskip Undercity,1
    .isQuestComplete 1014
step
    #completewith next
    .hs >> Hearth to The Sepulcher
    .use 6948
    .cooldown item,6948,>2,1
    .zoneskip Undercity
    .subzoneskip 228
    .bindlocation 228,1
    .isQuestComplete 1014
step
    .goto 1421/0,1593.6,554.23
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Dalar|r
    >>|cRXP_WARN_Not at The Sepulcher yet? Run north up the road from the dungeon entrance|r
    .turnin 1014 >>Turn in Arugal Must Die
    .target Dalar Dawnweaver
    .isQuestComplete 1014
step
    .goto 1421/0,1533.96,474.43
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Karos|r
    .fly Undercity >> Fly to the Undercity for The Book of Ur
    .target Karos Razok
    .zoneskip Silverpine Forest,1
    .isQuestComplete 1013
step
    #completewith next
    .goto 1420/0,240.75,1877.57,20 >> Enter Undercity
    .zoneskip Undercity
    .zoneskip Tirisfal Glades,1
    .isQuestComplete 1013
step
    .goto 1458,53.74,54.46
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Keeper Bel'dugur|r in the Apothecarium
    .turnin 1013 >>Turn in The Book of Ur
    .target Keeper Bel'dugur
    .zoneskip Undercity,1
    .isQuestComplete 1013
]])
end

-- ===== Father Gavin chain (Dun Morogh, Alliance) - standalone copy of the steps patched into 06-11 Dun Morogh =====
-- Load it from the RXP guide list when the main guide misbehaves; switch back to 06-11 Dun Morogh afterwards
-- (RXP keeps that guide's own progress).
if RXPGuides and RXPGuides.RegisterGuide then
	RXPGuides.RegisterGuide([[
<< Alliance
#forever
#version 1
#group Forever Side Quests (A)
#name Father Gavin chain (Dun Morogh)
step
    .goto Dun Morogh,47.2,52.2
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Maxan Anvol|r, the priest trainer in the Kharanos inn
    .accept 99158 >> Accept Dawn in the Mountains
    .target Maxan Anvol
step
    .goto Dun Morogh,57.4,44.8
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Father Gavin|r in the old building in the hills north-east of Kharanos
    .turnin 99158 >> Turn in Dawn in the Mountains
    .target Father Gavin
    .isOnQuest 99158
step
    #label GavinWarmth
    .goto Dun Morogh,57.4,44.8
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Father Gavin|r
    .accept 99159 >> Accept Finding Warmth
    .target Father Gavin
    .isQuestTurnedIn 99158
step
    #label GavinFirewood
    #loop
    .goto Dun Morogh,55.4,44.6,0
    .goto Dun Morogh,53.4,43.8,0
    .goto Dun Morogh,51.8,46.8,0
    .goto Dun Morogh,51.0,52.3,0
    .goto Dun Morogh,53.6,50.4,0
    .goto Dun Morogh,56.4,47.6,0
    .goto Dun Morogh,55.4,44.6,35,0
    .goto Dun Morogh,53.4,43.8,35,0
    .goto Dun Morogh,51.8,46.8,35,0
    .goto Dun Morogh,51.0,52.3,35,0
    .goto Dun Morogh,53.6,50.4,35,0
    .goto Dun Morogh,56.4,47.6,35,0
    .goto Dun Morogh,55.4,44.6,35,0
    >>Pick up |cRXP_LOOT_Mostly Dry Firewood|r around Father Gavin - the white trunks on the ground next to trees (some give 2)
    .complete -99159,1 --Mostly Dry Firewood (14)
step
    .goto Dun Morogh,57.4,44.8
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Father Gavin|r
    .turnin -99159 >> Turn in Finding Warmth
    .accept 99160 >> Accept Rime's Wrath
    .accept 99162 >> Accept Treacherous Cold
    .target Father Gavin
    .isQuestTurnedIn 99158
step
    #label GavinElementals
    #loop
    .goto Dun Morogh,55.4,44.6,0
    .goto Dun Morogh,53.4,43.8,0
    .goto Dun Morogh,56.4,46.8,0
    .goto Dun Morogh,55.4,44.6,40,0
    .goto Dun Morogh,53.4,43.8,40,0
    .goto Dun Morogh,56.4,46.8,40,0
    >>Kill |cRXP_ENEMY_Minor Ice Elementals|r around Father Gavin
    .complete -99160,1 --Minor Ice Elemental slain (10)
    .mob Minor Ice Elemental
step
    .goto Dun Morogh,57.4,44.8
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Father Gavin|r
    .turnin -99160 >> Turn in Rime's Wrath (part 1)
    .target Father Gavin
step
    .goto Dun Morogh,57.4,44.8
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Father Gavin|r again
    >>|cRXP_WARN_If he doesn't offer Rime's Wrath part 2, click this step to move on|r
    .accept 99161 >> Accept Rime's Wrath (part 2)
    .target Father Gavin
    .isQuestTurnedIn 99160
step
    #label GavinAvala
    .goto Dun Morogh,58.2,42.6
    >>Kill |cRXP_ENEMY_Avala|r, the large ice elemental just north-east of Father Gavin. Loot its |cRXP_LOOT_Core|r
    .complete -99161,1 --Avala's Core (1)
    .mob Avala
step
    .goto Dun Morogh,57.4,44.8
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tBack to |cRXP_FRIENDLY_Father Gavin|r, right next to Avala
    .turnin -99161 >> Turn in Rime's Wrath (part 2)
    .target Father Gavin
step
    #label GavinRifles
    .goto Dun Morogh,52.0,44.0
    >>Pick up |cRXP_LOOT_Coalbeard's Rifle|r - follow the frozen river west of Father Gavin, the body is under the tree fallen across it
    >>|cRXP_WARN_The rifle is a separate pickup next to the body - if it isn't there someone just took it, wait a moment for it to respawn|r
    .complete -99162,3 --Coalbeard's Rifle (1)
step
    .goto Dun Morogh,53.0,59.0
    >>Pick up |cRXP_LOOT_Stoneanvil's Rifle|r - in the valley to the south, the body is next to a cart
    >>|cRXP_WARN_The rifle is a separate pickup next to the body - if it isn't there someone just took it, wait a moment for it to respawn|r
    .complete -99162,1 --Stoneanvil's Rifle (1)
step
    .goto Dun Morogh,60.0,50.0
    >>Pick up |cRXP_LOOT_Sunhammer's Rifle|r - the body is next to a cart on the small path up to Vagash's cave
    >>|cRXP_WARN_The rifle is a separate pickup next to the body - if it isn't there someone just took it, wait a moment for it to respawn|r
    .complete -99162,2 --Sunhammer's Rifle (1)
step
    .goto Dun Morogh,57.4,44.8
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Father Gavin|r
    .turnin -99162 >> Turn in Treacherous Cold
    .target Father Gavin
]])
end
