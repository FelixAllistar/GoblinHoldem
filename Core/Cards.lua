-- Cards are integers 0..51: rank = floor(c / 4) (0 = deuce .. 12 = ace), suit = c % 4 (c, d, h, s).
local _, ns = ...

local Cards = {}
ns.Cards = Cards

local floor = math.floor
Cards.RANKS = "23456789TJQKA"
Cards.SUITS = "cdhs"
Cards.RANK_NAMES = { "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Jack", "Queen", "King", "Ace" }
Cards.RANK_PLURAL = { "Twos", "Threes", "Fours", "Fives", "Sixes", "Sevens", "Eights", "Nines", "Tens", "Jacks", "Queens", "Kings", "Aces" }
Cards.SUIT_NAMES = { "Clubs", "Diamonds", "Hearts", "Spades" }

function Cards.Rank(c) return floor(c / 4) end
function Cards.Suit(c) return c % 4 end
function Cards.IsRed(c) local s = c % 4 return s == 1 or s == 2 end

function Cards.ToString(c)
	local r, s = floor(c / 4), c % 4
	return Cards.RANKS:sub(r + 1, r + 1) .. Cards.SUITS:sub(s + 1, s + 1)
end

function Cards.FromString(str)
	if type(str) ~= "string" or #str ~= 2 then return nil end
	local r = Cards.RANKS:find(str:sub(1, 1), 1, true)
	local s = Cards.SUITS:find(str:sub(2, 2), 1, true)
	if not r or not s then return nil end
	return (r - 1) * 4 + (s - 1)
end

--- "AhKd" <-> {c1, c2}
function Cards.ListToString(list)
	local t = {}
	for i = 1, #list do t[i] = Cards.ToString(list[i]) end
	return table.concat(t)
end

function Cards.ListFromString(str)
	local out = {}
	for i = 1, #(str or ""), 2 do
		local c = Cards.FromString(str:sub(i, i + 1))
		if not c then return nil end
		out[#out + 1] = c
	end
	return out
end

---------------------------------------------------------------------------------------------
-- Deterministic CSPRNG stream: SHA-256(seed .. ":" .. counter), consumed 32 bits at a time.
---------------------------------------------------------------------------------------------
local Stream = {}
Stream.__index = Stream

function Cards.NewStream(seedHex)
	return setmetatable({ seed = seedHex, counter = 0, buf = "", pos = 1 }, Stream)
end

function Stream:Next32()
	if self.pos > #self.buf then
		self.counter = self.counter + 1
		self.buf = ns.SHA256(self.seed .. ":" .. self.counter)
		self.pos = 1
	end
	local hex = self.buf:sub(self.pos, self.pos + 7)
	self.pos = self.pos + 8
	return tonumber(hex, 16)
end

--- Uniform integer in [1, n] using rejection sampling (no modulo bias).
function Stream:Int(n)
	local limit = floor(4294967296 / n) * n
	while true do
		local r = self:Next32()
		if r < limit then return r % n + 1 end
	end
end

--- Fisher-Yates shuffle of a fresh 52-card deck, fully determined by seedHex.
function Cards.Shuffle(seedHex)
	local deck = {}
	for i = 1, 52 do deck[i] = i - 1 end
	local rng = Cards.NewStream(seedHex)
	for i = 52, 2, -1 do
		local j = rng:Int(i)
		deck[i], deck[j] = deck[j], deck[i]
	end
	return deck
end

---------------------------------------------------------------------------------------------
-- Deck layout used by every client. dealOrder = seats starting left of the button.
-- Hole cards are dealt one at a time around the table; one burn card before each street.
---------------------------------------------------------------------------------------------
function Cards.Layout(deck, dealOrder)
	local n = #dealOrder
	local holes = {}
	for i, seat in ipairs(dealOrder) do
		holes[seat] = { deck[i], deck[i + n] }
	end
	local p = 2 * n
	local board = { deck[p + 2], deck[p + 3], deck[p + 4], deck[p + 6], deck[p + 8] }
	return holes, board
end
