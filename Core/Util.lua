-- Shared helpers: internal message bus, names, money formatting, logging.
local _, ns = ...

local listeners = {}
function ns.Listen(msg, fn)
	listeners[msg] = listeners[msg] or {}
	table.insert(listeners[msg], fn)
end

function ns.Emit(msg, ...)
	local list = listeners[msg]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then ns.Debug("listener " .. msg .. ": " .. tostring(err)) end
	end
end

function ns.NormName(name)
	if not name then return nil end
	if Ambiguate then return Ambiguate(name, "none") end
	return (name:gsub("%-.*$", ""))
end

ns.debugLog = {}
function ns.Debug(text)
	local log = ns.debugLog
	log[#log + 1] = tostring(text)
	if #log > 300 then table.remove(log, 1) end
	if ns.debugEcho and DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cff888888GH debug:|r " .. tostring(text))
	end
end

function ns.Print(text)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Goblin Hold'em|r: " .. tostring(text))
	else
		print("Goblin Hold'em: " .. tostring(text))
	end
end

---------------------------------------------------------------------------------------------
-- Money. In gold modes chip amounts are copper; in "fun" mode they are plain chips.
---------------------------------------------------------------------------------------------
local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:1:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:1:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:1:0|t"

local function commas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end
ns.Commas = commas

--- Format a chip amount for display. plain = no texture icons (for chat lines).
function ns.Money(amount, mode, plain)
	amount = math.floor(amount or 0)
	if mode == "fun" then return commas(amount) end
	local neg = amount < 0
	if neg then amount = -amount end
	local g, s, c = math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100
	local parts = {}
	if plain then
		if g > 0 then parts[#parts + 1] = commas(g) .. "g" end
		if s > 0 then parts[#parts + 1] = s .. "s" end
		if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	else
		if g > 0 then parts[#parts + 1] = commas(g) .. GOLD end
		if s > 0 then parts[#parts + 1] = s .. SILVER end
		if c > 0 or #parts == 0 then parts[#parts + 1] = c .. COPPER end
	end
	return (neg and "-" or "") .. table.concat(parts, " ")
end

--- Parse user input into chip units. Gold modes accept "12.5", "12g 50s", "3s", "1g" etc.
function ns.ParseMoney(text, mode)
	text = tostring(text or ""):lower():gsub(",", "")
	if mode == "fun" then return tonumber(text) and math.floor(tonumber(text)) end
	local total, matched = 0, false
	for num, unit in text:gmatch("([%d%.]+)%s*([gsc])") do
		local n = tonumber(num)
		if not n then return nil end
		matched = true
		total = total + n * (unit == "g" and 10000 or unit == "s" and 100 or 1)
	end
	if not matched then
		local n = tonumber(text)
		if not n then return nil end
		total = n * 10000 -- bare numbers are gold
	end
	return math.floor(total + 0.5)
end
