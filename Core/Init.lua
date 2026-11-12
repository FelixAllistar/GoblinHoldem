-- Bootstrap: saved variables, WoW events, dealer reload recovery, slash commands.
local ADDON, ns = ...
GoblinHoldem = ns -- global handle for macros and /run debugging

ns.name = ADDON
local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.version = getMeta and getMeta(ADDON, "Version") or "dev"

local DEFAULTS = {
	settings = {
		autoRoll = true, hideRolls = true, sound = true, autoOpen = false,
		confirmAllIn = true, turnPopup = true, mini = false, minimap = true, scale = 1,
	},
	frames = {}, keys = {}, audit = {}, sessions = {}, debts = {}, minimapAngle = 215,
}

local function fill(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			fill(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

---------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}
frame:SetScript("OnEvent", function(_, event, ...)
	local fn = handlers[event]
	if fn then
		local ok, err = pcall(fn, ...)
		if not ok then ns.Debug(event .. ": " .. tostring(err)) end
	end
end)
local function on(event, fn)
	handlers[event] = fn
	frame:RegisterEvent(event)
end

on("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	GoblinHoldemDB = GoblinHoldemDB or {}
	fill(GoblinHoldemDB, DEFAULTS)
	ns.db = GoblinHoldemDB
	ns.Fair.LoadPool(ns.db.pool)
	-- forget card keys older than a week
	local now = time()
	for id, e in pairs(ns.db.keys) do
		if type(e) ~= "table" or now - (e.at or 0) > 7 * 86400 then ns.db.keys[id] = nil end
	end
	local reg = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
	if reg then reg(ns.Comm.PREFIX) end
end)

on("CHAT_MSG_ADDON", function(prefix, text, dist, sender)
	ns.Comm.OnAddonMessage(prefix, text, dist, sender)
end)

on("CHAT_MSG_SYSTEM", function(text)
	if ns.current then ns.current:OnSystem(text) end
	ns.Fair.Stir(text)
end)

local function inGroup(name)
	if name == ns.Comm.Me() then return true end
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
	for i = 1, n do
		local unit = prefix .. i
		local un = UnitName(unit)
		if un and ns.NormName(un) == name then return true end
	end
	return false
end
ns.InGroup = inGroup

local wasInGroup = false
local rosterPending = false
on("GROUP_ROSTER_UPDATE", function()
	if rosterPending then return end
	rosterPending = true
	-- the roster is briefly empty while loading or converting to raid; settle first
	C_Timer.After(2, function()
		rosterPending = false
		local grouped = ns.Comm.GroupDist() ~= nil
		if grouped and not wasInGroup then ns.Comm.Group("HELLO") end
		wasInGroup = grouped
		local t = ns.current
		if t then t:OnRoster(inGroup) end
		if t and t.isDealer and t.cfg.transport == "group" then t:Announce() end
	end)
end)

on("PLAYER_ENTERING_WORLD", function()
	C_Timer.After(4, function()
		wasInGroup = ns.Comm.GroupDist() ~= nil
		if ns.db.hosting then
			local saved = ns.db.hosting
			ns.db.hosting = nil
			local transport = saved.cfg and saved.cfg.transport or "group"
			if not ns.current and (wasInGroup or transport ~= "group") then ns.RestoreHosting(saved) end
		end
		if not ns.current and ns.db.joined then
			-- we were at someone's anywhere table before the reload: ask to be dealt back in
			ns.Comm.Whisper(ns.db.joined.dealer, "HELLO")
		elseif wasInGroup and not ns.current then
			ns.Comm.Group("HELLO")
		end
	end)
end)

-- someone left (or logged out of) our table's chat channel
on("CHAT_MSG_CHANNEL_LEAVE", function(_, playerName, _, channelName, _, _, _, _, baseName)
	local t = ns.current
	if not t or not t.cfg.channel or not playerName then return end
	local chan = (baseName and baseName ~= "" and baseName) or (channelName or ""):gsub("^%d+%.%s*", "")
	if chan:lower() == t.cfg.channel:lower() then t:OnChannelLeave(playerName) end
end)

on("PLAYER_LOGOUT", function()
	ns.db.pool = ns.Fair.SavePool()
	local t = ns.current
	if t then ns.SaveSession(t) end
	if t and t.isDealer and t.phase ~= "closed" then
		ns.db.hosting = ns.SaveHosting(t)
	else
		ns.db.hosting = nil
	end
end)

---------------------------------------------------------------------------------------------
-- Dealer reload recovery: rebuild the table from the last stable state and void the
-- hand that was running (everyone gets their chips back).
---------------------------------------------------------------------------------------------
function ns.SaveHosting(t)
	local entries = t:CurrentEntries()
	local h = t.engine.hand
	local midHand = (h and h.phase ~= "done") or t.phase == "rolling"
	if h and h.phase ~= "done" then
		for _, e in ipairs(entries) do
			if h.startStacks[e.seat] then e.stack = h.startStacks[e.seat] end
		end
	end
	return {
		id = t.id, cfg = t.cfg, handNo = t.handNo, entries = entries, ledger = t.ledger,
		keys = t.keys, myKey = t.myKey, secret = t.secret, midHand = midHand, button = t.engine.button, bots = t.bots,
		stats = t.stats, autoDeal = t.autoDeal, at = time(),
	}
end

function ns.RestoreHosting(s)
	if time() - (s.at or 0) > 15 * 60 then return end
	local t = ns.Table.Restore(s)
	ns.Emit("TABLE_OPENED", t)
	t:Log("Table restored after a reload.")
	t:Announce()
	if s.midHand then t:VoidCurrent("dealer reloaded") end
	C_Timer.After(1, function() t:PublishSeats() end)
	t:Changed()
end

---------------------------------------------------------------------------------------------
-- Hide the shuffle /rolls from chat (they're shown in the table log instead)
---------------------------------------------------------------------------------------------
if ChatFrame_AddMessageEventFilter then
	ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
		local t = ns.current
		if not t or not ns.db or not ns.db.settings.hideRolls then return false end
		local name, _, lo, hi = ns.Table.ParseRoll(msg)
		if name and lo == ns.Table.ROLL_MIN and hi == ns.Table.ROLL_MAX and t.engine:SeatOf(name) then
			return true
		end
		return false
	end)
end

-- players: notice a dealer who vanished mid-hand
C_Timer.NewTicker(5, function()
	if ns.current then ns.current:Watchdog() end
end)

BINDING_HEADER_GOBLINHOLDEM = "Goblin Hold'em"
BINDING_NAME_GOBLINHOLDEM_TOGGLE = "Open / close the table"
BINDING_NAME_GOBLINHOLDEM_FOLD = "Fold (or queue check/fold)"
BINDING_NAME_GOBLINHOLDEM_CALL = "Check / call (or queue it)"

--- Minimap button / keybind: the table if we're at one (mini or full), otherwise the lobby.
function ns.ToggleMain()
	if not ns.current then return ns.LobbyUI:Toggle() end
	if ns.db.settings.mini then ns.MiniUI:Toggle() else ns.TableUI:Toggle() end
end

-- public tables re-advertise once a minute
C_Timer.NewTicker(60, function()
	local t = ns.current
	if t and t.isDealer and t.cfg.public and t.phase ~= "closed" then ns.Lobby.Advertise(t) end
end)

---------------------------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------------------------
local function toggleSetting(key, label)
	ns.db.settings[key] = not ns.db.settings[key]
	ns.Print(("%s: %s"):format(label, ns.db.settings[key] and "on" or "off"))
end

SLASH_GOBLINHOLDEM1 = "/holdem"
SLASH_GOBLINHOLDEM2 = "/gh"
SlashCmdList.GOBLINHOLDEM = function(msg)
	local cmd = (msg or ""):lower():match("^%s*(%S*)")
	if cmd == "" then
		ns.ToggleMain()
	elseif cmd == "mini" then
		ns.db.settings.mini = true
		if ns.TableUI.frame then ns.TableUI.frame:Hide() end
		ns.MiniUI:Show()
	elseif cmd == "full" then
		ns.db.settings.mini = false
		if ns.MiniUI.frame then ns.MiniUI.frame:Hide() end
		ns.TableUI:Show()
	elseif cmd == "debts" or cmd == "history" then
		ns.LedgerUI:Show(cmd)
	elseif cmd == "settings" or cmd == "options" or cmd == "config" then
		ns.SettingsUI:Toggle()
	elseif cmd == "minimap" then
		toggleSetting("minimap", "Minimap button")
		ns.MinimapButton:Update()
	elseif cmd == "lobby" or cmd == "host" then
		ns.LobbyUI:Toggle()
	elseif cmd == "join" then
		local name = msg:match("^%s*%S+%s+(%S+)")
		if not name then return ns.Print("Usage: /holdem join <dealer's name>") end
		ns.Table.RequestJoin(name)
	elseif cmd == "invite" then
		local name = msg:match("^%s*%S+%s+(%S+)")
		local t = ns.current
		if not (t and t.isDealer) then return ns.Print("Only the dealer can invite. Host a table first.") end
		if not name then return ns.Print("Usage: /holdem invite <name>") end
		t:Invite(name)
	elseif cmd == "practice" then
		local t, err = ns.Table.HostPractice(4)
		if not t then ns.Print(err) end
	elseif cmd == "table" then
		if ns.current then ns.TableUI:Show() else ns.Print("You're not at a table. /holdem lobby to find or host one.") end
	elseif cmd == "ledger" then
		ns.LedgerUI:Show("ledger")
	elseif cmd == "audit" then
		ns.LedgerUI:Show("audit")
	elseif cmd == "fair" then
		ns.LedgerUI:Show("help")
	elseif cmd == "rolls" then
		toggleSetting("hideRolls", "Hide shuffle rolls from chat")
	elseif cmd == "sound" then
		toggleSetting("sound", "Sounds")
	elseif cmd == "autoopen" then
		toggleSetting("autoOpen", "Open the table window when a table starts in your group")
	elseif cmd == "autoroll" then
		toggleSetting("autoRoll", "Roll automatically for the shuffle")
	elseif cmd == "roll" then
		if ns.current then ns.current:Roll() end
	elseif cmd == "forget" then
		if ns.current then ns.SaveSession(ns.current) end
		if ns.current and ns.current.cfg.channel then ns.Comm.LeaveChannel(ns.current.cfg.channel) end
		ns.current = nil
		ns.Comm.SetRoute(nil)
		ns.db.joined = nil
		if ns.TableUI.frame then ns.TableUI.frame:Hide() end
		ns.Print("Forgot the current table.")
	elseif cmd == "debug" then
		ns.debugEcho = not ns.debugEcho
		ns.Print("debug " .. (ns.debugEcho and "on" or "off"))
		for i = math.max(1, #ns.debugLog - 10), #ns.debugLog do ns.Print(ns.debugLog[i]) end
	else
		ns.Print("/holdem - open the table (or the lobby)")
		ns.Print("/holdem lobby - find or host a table")
		ns.Print("/holdem join <name> - join a friend's table, wherever they are")
		ns.Print("/holdem invite <name> - (dealer) invite someone to your table")
		ns.Print("/holdem practice - solo table against goblin bots")
		ns.Print("/holdem mini | full - small HUD or the full table")
		ns.Print("/holdem ledger | debts | history | audit | fair")
		ns.Print("/holdem settings - options (also: right-click the minimap button)")
		ns.Print("/holdem forget - drop a stuck table on your side")
	end
end

StaticPopupDialogs["GOBLINHOLDEM_INVITED"] = {
	text = "%s",
	button1 = "Join", button2 = "No thanks", timeout = 60, whileDead = true, hideOnEscape = true,
	OnAccept = function(_, info)
		info.openUI = true
		ns.Table.Join(info)
	end,
}
ns.Listen("TABLE_INVITE", function(info)
	local c = info.cfg
	local stakes = ns.Money(c.sb, c.mode, true) .. "/" .. ns.Money(c.bb, c.mode, true) .. " " .. (ns.Table.MODES[c.mode] or "")
	local text = ("%s invites you to their Goblin Hold'em table |cffffd100%s|r (%s). Join?"):format(info.dealer, c.name, stakes)
	StaticPopup_Show("GOBLINHOLDEM_INVITED", text, nil, info)
end)

ns.Listen("TABLE_ROLL_NEEDED", function()
	ns.Print("Your roll for the shuffle: type |cffffffff/holdem roll|r (auto-roll is off).")
end)
