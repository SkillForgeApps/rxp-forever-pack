-- Class macro sets (4 Oct 2026, Gaz: "add a tab in macros that says warrior and put all the macros there").
-- The macro window only has two tabs: General (account) and one named after the character - a custom tab name is not possible.
-- So these go into the CHARACTER tab. A set is created on login for that class if a macro of that name is missing (an existing
-- macro is never touched by the automatic pass, so edits made in the macro window stay). Commands:
--   /fmacros          create any missing macro of this class's set now
--   /fmacros update   overwrite the set's macros with the versions below (after we change them)
local SETS = {
	WARRIOR = {
		-- Charge from Battle Stance (out of combat), Defensive Stance once in combat, Revenge when it procs, otherwise the cycle
		{ name = "Tank Cycle", body = [[#showtooltip
/cast [nocombat,nostance:1] Battle Stance
/cast [nocombat,stance:1] Charge
/cast [combat,nostance:2] Defensive Stance
/cast Revenge
/castsequence [combat] reset=combat/15 Rend, Demoralizing Shout, Sunder Armor, Thunder Clap, Heroic Strike]] },
	},
}

local ICON = 134400   -- question mark; #showtooltip draws the real spell icon

local function say(msg) print("|cff33ff99Class macros:|r " .. msg) end

local function install(update)
	local _, class = UnitClass("player")
	local set = SETS[class]
	if not set then return 0, 0 end
	if InCombatLockdown() then say("in combat - try again after the fight") return 0, 0 end
	local made, changed = 0, 0
	for _, m in ipairs(set) do
		if #m.body > 255 then
			say(m.name .. " is longer than 255 characters - not installed")
		else
			local idx = GetMacroIndexByName(m.name)
			if idx and idx > 0 then
				if update then EditMacro(idx, m.name, nil, m.body) changed = changed + 1 end
			else
				local _, perChar = GetNumMacros()
				if perChar and perChar >= 18 then
					say("your character macro tab is full (18) - delete one, then /fmacros")
				else
					local ok, err = pcall(CreateMacro, m.name, ICON, m.body, true)
					if ok then made = made + 1 else say("could not create " .. m.name .. ": " .. tostring(err)) end
				end
			end
		end
	end
	return made, changed
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	C_Timer.After(5, function()
		local ok, made = pcall(install, false)
		if ok and made and made > 0 then
			say(made .. " new macro" .. (made == 1 and "" or "s") .. " added to your character's macro tab (open the macro window, tab named after this character)")
		end
	end)
end)

SLASH_FOREVERMACROS1 = "/fmacros"
SlashCmdList["FOREVERMACROS"] = function(msg)
	local update = (msg or ""):lower():find("update", 1, true) ~= nil
	local made, changed = install(update)
	local _, class = UnitClass("player")
	if not SETS[class] then say("no macro set for " .. tostring(class)) return end
	say(string.format("%d created, %d updated. They are in the macro window's character tab.", made, changed))
end
