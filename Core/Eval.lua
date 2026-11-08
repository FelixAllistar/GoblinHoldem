-- Best-five-of-seven hand evaluator. Eval(cards) -> score (higher wins), category, description.
local _, ns = ...

local Cards = ns.Cards
local Eval = {}
ns.Eval = Eval

local floor = math.floor

Eval.CATEGORY = {
	[0] = "High Card", "Pair", "Two Pair", "Three of a Kind", "Straight",
	"Flush", "Full House", "Four of a Kind", "Straight Flush",
}

local function score(cat, r1, r2, r3, r4, r5)
	return ((((cat * 16 + (r1 or 0)) * 16 + (r2 or 0)) * 16 + (r3 or 0)) * 16 + (r4 or 0)) * 16 + (r5 or 0)
end

-- highest straight in a rank set (ranks 0..12); returns the top rank (3 = five-high wheel) or nil
local function straightTop(has)
	for top = 12, 3, -1 do
		local ok = true
		for k = 0, 4 do
			local r = top - k
			if r < 0 then r = 12 end
			if not has[r] then ok = false break end
		end
		if ok then return top end
	end
end

local function name(r) return Cards.RANK_NAMES[r + 1] end
local function plural(r) return Cards.RANK_PLURAL[r + 1] end

function Eval.Eval(cards)
	local count, has, bySuit = {}, {}, { [0] = {}, {}, {}, {} }
	for r = 0, 12 do count[r] = 0 end
	for i = 1, #cards do
		local c = cards[i]
		local r, s = floor(c / 4), c % 4
		count[r] = count[r] + 1
		has[r] = true
		bySuit[s][r] = true
	end

	-- flush / straight flush
	for s = 0, 3 do
		local n = 0
		for _ in pairs(bySuit[s]) do n = n + 1 end
		if n >= 5 then
			local top = straightTop(bySuit[s])
			if top then
				local desc = top == 12 and "Royal Flush" or ("Straight Flush, " .. name(top) .. " high")
				return score(8, top), 8, desc
			end
			local ranks = {}
			for r = 12, 0, -1 do
				if bySuit[s][r] and #ranks < 5 then ranks[#ranks + 1] = r end
			end
			return score(5, ranks[1], ranks[2], ranks[3], ranks[4], ranks[5]), 5, "Flush, " .. name(ranks[1]) .. " high"
		end
	end

	local quads, trips, pairs_, singles = {}, {}, {}, {}
	for r = 12, 0, -1 do
		local c = count[r]
		if c == 4 then quads[#quads + 1] = r
		elseif c == 3 then trips[#trips + 1] = r
		elseif c == 2 then pairs_[#pairs_ + 1] = r
		elseif c == 1 then singles[#singles + 1] = r end
	end

	-- highest rank in `has` not in the excluded set
	local function kickers(n, ex1, ex2)
		local out = {}
		for r = 12, 0, -1 do
			if has[r] and r ~= ex1 and r ~= ex2 then
				out[#out + 1] = r
				if #out == n then break end
			end
		end
		return out
	end

	if quads[1] then
		local q = quads[1]
		local k = kickers(1, q)
		return score(7, q, k[1]), 7, "Four of a Kind, " .. plural(q)
	end

	if trips[1] and (trips[2] or pairs_[1]) then
		local t = trips[1]
		local p = trips[2] or -1
		if pairs_[1] and pairs_[1] > p then p = pairs_[1] end
		return score(6, t, p), 6, "Full House, " .. plural(t) .. " over " .. plural(p)
	end

	local top = straightTop(has)
	if top then
		return score(4, top), 4, "Straight, " .. name(top) .. " high"
	end

	if trips[1] then
		local t = trips[1]
		local k = kickers(2, t)
		return score(3, t, k[1], k[2]), 3, "Three of a Kind, " .. plural(t)
	end

	if pairs_[2] then
		local p1, p2 = pairs_[1], pairs_[2]
		local k = kickers(1, p1, p2)
		return score(2, p1, p2, k[1]), 2, "Two Pair, " .. plural(p1) .. " and " .. plural(p2)
	end

	if pairs_[1] then
		local p = pairs_[1]
		local k = kickers(3, p)
		return score(1, p, k[1], k[2], k[3]), 1, "Pair of " .. plural(p)
	end

	local k = kickers(5)
	return score(0, k[1], k[2], k[3], k[4], k[5]), 0, name(k[1]) .. " high"
end
