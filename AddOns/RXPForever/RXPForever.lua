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

-- Quest-log snapshot for Claude (24 Sep): the Forever client only writes saved variables on /reload or logout and
-- RXP keeps no quest log on disk (questObjectivesCache is a lookup cache), so keep one here: every quest in the log
-- with objectives, plus the turned-in state of every quest the current guide mentions.
-- Read from WTF/.../<char>/SavedVariables/RXPGuides.lua -> RXPCData.rxpForever.questLog after any reload.
local function snapshotQuests()
	if not RXPCData or not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then return end
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
local function hookSetStep()
	if not RXP or not RXP.SetStep or RXP.SetStep == wrappedSetStep then return end
	local orig = RXP.SetStep
	-- RXP's element handlers (e.g. ".money") rewrite step.completed on every tick for the ACTIVE step, so a
	-- flagged step must never become active: when RXP asks to activate a flagged step, skip forward to the
	-- first unflagged one. Sticky steps are handled through RXP's own stepSkip list instead.
	wrappedSetStep = function(n, n2, loopback)
		local guide = RXP.currentGuide
		local idx = (type(n) == "table") and n2 or n
		if guide and guide.steps and type(idx) == "number" then
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
local function charKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end

rememberGuide = function(guide, step)
	if not loginSettled or not guide or guide.empty or guide.internal or not guide.name then return end
	local prev = DB().lastGuide
	-- the step's fingerprint too: RXP's own saved position (stepId = guide line number) and a bare step number both
	-- point at the wrong step once lines are inserted above it (23 Sep: a character sent back to Kharanos)
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

local restoreFrame = CreateFrame("Frame")
restoreFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
restoreFrame:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
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

-- ===== .continentskip for RXP guides =====
-- .continentskip <continentMapID>[,1] skips the step while you are on that continent (flag 1: while you are NOT).
-- Kalimdor = 1414, Eastern Kingdoms = 1415. Modelled on RXP's own .zoneskip (functions.lua) and re-checked on the
-- same zone-change events.
-- 23 Sep: the map-parent walk alone never produced a skip on Forever (a character in the Barrens still got "fly to
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
-- Dungeon drops start 95204 Crest of Lordaeron and 97288 Unending Torment (-> 97289 -> 97291 -> 97292, Faranell).
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
    >>Get a group and enter the |cRXP_WARN_Ruins of Lordaeron|r dungeon. The entrance is in the ruined courtyard above the Undercity, on your LEFT as you come in from outside
    >>Kill |cRXP_ENEMY_Witherfang|r and loot the |cRXP_LOOT_Highly Toxic Strain|r
    >>Collect 25 |cRXP_LOOT_Intact Limbs|r from the undead inside
    >>Kill |cRXP_ENEMY_Rath'mael|r
    >>Find out what happened to |cRXP_FRIENDLY_Edward Heartweaver|r
    >>Loot a |cRXP_LOOT_Crest of Lordaeron|r and an |cRXP_LOOT_Abominable Head|r if they drop - each starts a quest
    .complete 95216,1 --Highly Toxic Strain
    .complete 92421,1 --Intact Limbs (25)
    .complete 92422,1 --Rath'mael slain
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
    .target Unfinished Abomination
    .isOnQuest 97289
step
    .goto 1458,48.5,69.5
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Master Apothecary Faranell|r
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
-- Order: from Eastern Kingdoms -> Varimathras first; then Thunder Bluff -> Orgrimmar chain -> (Undercity if still
-- needed) -> RFC -> Orgrimmar hand-ins -> Undercity hand-in -> Thunder Bluff hand-ins (ends in Kalimdor).
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
    #completewith RFCRahauro
    .goto Orgrimmar,45.120,63.889
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Doras|r
    .fly Thunder Bluff >> Fly to Thunder Bluff
    .target Doras
    .zoneskip Orgrimmar,1
    .needanyquest 5722,5723
step
    #completewith RFCRahauro
    >>Fly to Thunder Bluff from the nearest flight master
    .fly Thunder Bluff >> Fly to Thunder Bluff
    .zoneskip Thunder Bluff+Orgrimmar
    .continentskip 1414,1
    .needanyquest 5722,5723
step
    #label RFCRahauro
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
    .fly Orgrimmar >> Fly to Orgrimmar
    .target Tal
    .zoneskip Thunder Bluff,1
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
    .goto 1411/1,-4769.10,1484.39,0
    >>Kill |cRXP_ENEMY_Burning Blade|r mobs in Skull Rock (just outside Orgrimmar's gate) until the |cRXP_LOOT_Lieutenant's Insignia|r drops
    .complete 5726,1 --Lieutenant's Insignia (1)
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
    #completewith next
    .goto Orgrimmar,45.120,63.889
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Doras|r
    .fly Thunder Bluff >> Fly to Thunder Bluff
    .target Doras
    .zoneskip Thunder Bluff
    .onanyquest 5723,5724
step
    .goto 1456/1,-218.13,-1055.97
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Rahauro|r
    .turnin -5724 >> Turn in Returning the Lost Satchel
    .turnin -5723 >> Turn in Testing an Enemy's Strength
    .target Rahauro
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
