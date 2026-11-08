-- "Sealed deck" fairness protocol.
--
--  1. Dealer picks a secret and broadcasts commit = SHA256("GH1|commit|" .. secret). Sealed.
--  2. Every seated player /rolls 1-1000000. The roll is made by the Blizzard server, so nobody
--     (dealer included) can choose it, and everyone in the group sees the same system message.
--  3. seed = SHA256(table | hand | secret | all rolls); deck = Fisher-Yates(seed).
--     The dealer committed before the rolls existed, so it cannot steer the deck; players
--     cannot predict it because they do not know the secret.
--  4. Hole cards travel encrypted with a per-player pad key only that player and the dealer know.
--  5. When the hand ends the dealer reveals the secret. Every add-on recomputes the deck and checks
--     the commit, the board, its own hole cards and every shown hand. Any mismatch is announced.
local _, ns = ...

local Fair = {}
ns.Fair = Fair

local SHA = function(s) return ns.SHA256(s) end

---------------------------------------------------------------------------------------------
-- Local entropy. Mixed from everything cheap and unpredictable we can read, plus a pool that
-- is carried forward in SavedVariables. Only needs to be unpredictable to other players.
---------------------------------------------------------------------------------------------
local pool = ""
function Fair.Stir(extra)
	local parts = { pool, tostring(extra or "") }
	local function add(f, ...)
		if type(f) == "function" then
			local ok, a, b = pcall(f, ...)
			if ok then parts[#parts + 1] = tostring(a) .. "," .. tostring(b) end
		end
	end
	add(math.random)
	add(math.random, 1, 2147483647)
	add(rawget(_G, "securerandom"))
	add(rawget(_G, "GetTimePreciseSec"))
	add(rawget(_G, "debugprofilestop"))
	add(rawget(_G, "GetTime"))
	add(rawget(_G, "GetCursorPosition"))
	add(rawget(_G, "GetFramerate"))
	add(os and os.time)
	add(os and os.clock)
	parts[#parts + 1] = tostring({}) .. tostring(function() end) -- heap addresses
	pool = SHA(table.concat(parts, "|"))
	return pool
end

function Fair.LoadPool(saved) if type(saved) == "string" then pool = saved end Fair.Stir("load") end
function Fair.SavePool() return SHA(pool .. "|save") end

function Fair.NewSecret()
	return SHA(Fair.Stir("secret") .. "|" .. Fair.Stir("secret2"))
end

function Fair.Commit(secret)
	return SHA("GH1|commit|" .. secret)
end

--- rolls: { [seat] = value } -> canonical "seat=value,seat=value" sorted by seat
function Fair.RollString(rolls)
	local seats = {}
	for seat in pairs(rolls) do seats[#seats + 1] = seat end
	table.sort(seats)
	local t = {}
	for i, seat in ipairs(seats) do t[i] = seat .. "=" .. rolls[seat] end
	return table.concat(t, ",")
end

function Fair.ParseRolls(str)
	local rolls = {}
	for seat, v in (str or ""):gmatch("(%d+)=(%d+)") do rolls[tonumber(seat)] = tonumber(v) end
	return rolls
end

function Fair.Seed(tableId, handNo, secret, rollString)
	return SHA("GH1|deck|" .. tableId .. "|" .. handNo .. "|" .. secret .. "|" .. rollString)
end

function Fair.Deck(tableId, handNo, secret, rollString)
	return ns.Cards.Shuffle(Fair.Seed(tableId, handNo, secret, rollString))
end

---------------------------------------------------------------------------------------------
-- Hole-card pads: card' = (card + pad) % 52, pad derived from the player's private key.
---------------------------------------------------------------------------------------------
local function pads(key, tableId, handNo)
	local h = SHA("GH1|pad|" .. key .. "|" .. tableId .. "|" .. handNo)
	return tonumber(h:sub(1, 8), 16) % 52, tonumber(h:sub(9, 16), 16) % 52
end

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function enc2(n) return B36:sub(math.floor(n / 36) + 1, math.floor(n / 36) + 1) .. B36:sub(n % 36 + 1, n % 36 + 1) end
local function dec2(s)
	local a, b = B36:find(s:sub(1, 1), 1, true), B36:find(s:sub(2, 2), 1, true)
	if not a or not b then return nil end
	return (a - 1) * 36 + (b - 1)
end

function Fair.SealHole(key, tableId, handNo, c1, c2)
	local p1, p2 = pads(key, tableId, handNo)
	return enc2((c1 + p1) % 52) .. enc2((c2 + p2) % 52)
end

function Fair.OpenHole(key, tableId, handNo, sealed)
	if type(sealed) ~= "string" or #sealed ~= 4 then return nil end
	local p1, p2 = pads(key, tableId, handNo)
	local e1, e2 = dec2(sealed:sub(1, 2)), dec2(sealed:sub(3, 4))
	if not e1 or not e2 then return nil end
	return (e1 - p1) % 52, (e2 - p2) % 52
end

---------------------------------------------------------------------------------------------
-- Audit: recompute everything from the revealed secret.
-- rec = { tableId, handNo, commit, rolls (string), dealOrder, board = {cards seen},
--         myHole = {c1,c2} or nil, mySeat }
---------------------------------------------------------------------------------------------
function Fair.Audit(rec, secret)
	local issues = {}
	if Fair.Commit(secret) ~= rec.commit then
		issues[#issues + 1] = "revealed secret does not match the sealed commit"
		return false, issues
	end
	local deck = Fair.Deck(rec.tableId, rec.handNo, secret, rec.rolls)
	local holes, board = ns.Cards.Layout(deck, rec.dealOrder)
	for i, c in ipairs(rec.board or {}) do
		if board[i] ~= c then
			issues[#issues + 1] = ("board card %d was %s, deck says %s"):format(i, ns.Cards.ToString(c), ns.Cards.ToString(board[i]))
		end
	end
	if rec.myHole and rec.mySeat then
		local h = holes[rec.mySeat]
		if not h or h[1] ~= rec.myHole[1] or h[2] ~= rec.myHole[2] then
			issues[#issues + 1] = "your hole cards do not match the deck"
		end
	end
	return #issues == 0, issues, holes, board, deck
end
