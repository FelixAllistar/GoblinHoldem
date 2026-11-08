-- No-limit Texas Hold'em rules engine. Pure and deterministic: every client runs an identical
-- copy and applies the same inputs, so stacks and pots never need to be trusted from anyone.
--
-- Inputs: Sit/Stand/SetStack between hands, StartHand(no, players), Act(seat, kind, amount),
--         DealBoard(cards), Showdown(holes). Engine:Emit(event, ...) reports what happened.
local _, ns = ...

local Engine = {}
Engine.__index = Engine
ns.Engine = Engine

local min, max, floor = math.min, math.max, math.floor
Engine.STREETS = { "preflop", "flop", "turn", "river" }

function Engine.New(cfg)
	local t = setmetatable({}, Engine)
	t.maxSeats = cfg.maxSeats or 9
	t.sb = cfg.sb
	t.bb = cfg.bb
	t.seats = {} -- [seat] = { name = , stack = , sittingOut = }
	t.button = 0
	t.hand = nil
	return t
end

function Engine:Emit(event, ...)
	if self.listener then self.listener(event, ...) end
end

function Engine:InHand()
	return self.hand ~= nil and self.hand.phase ~= "done"
end

---------------------------------------------------------------------------------------------
-- Seating (only between hands; the table layer enforces that)
---------------------------------------------------------------------------------------------
function Engine:Sit(seat, name, stack)
	if seat < 1 or seat > self.maxSeats then return false, "bad seat" end
	if self.seats[seat] then return false, "seat taken" end
	for _, s in pairs(self.seats) do
		if s.name == name then return false, "already seated" end
	end
	self.seats[seat] = { name = name, stack = stack, sittingOut = false }
	return true
end

function Engine:Stand(seat)
	self.seats[seat] = nil
end

function Engine:SeatOf(name)
	for i, s in pairs(self.seats) do
		if s.name == name then return i end
	end
end

function Engine:NextSeat(from, pred)
	for i = 1, self.maxSeats do
		local s = (from + i - 1) % self.maxSeats + 1
		if pred(s) then return s end
	end
end

--- Seats that may be dealt into the next hand (the table layer further filters by who rolled).
function Engine:Eligible()
	local out = {}
	for i = 1, self.maxSeats do
		local s = self.seats[i]
		if s and not s.sittingOut and s.stack > 0 then out[#out + 1] = i end
	end
	return out
end

---------------------------------------------------------------------------------------------
-- Hand flow
---------------------------------------------------------------------------------------------
--- Who would be button/blinds and in what order cards go out, without changing anything.
function Engine:PlanHand(players)
	local inHand, count = {}, 0
	for _, seat in ipairs(players) do
		local s = self.seats[seat]
		if not s or s.stack <= 0 then return nil, "seat " .. seat .. " cannot play" end
		if not inHand[seat] then count = count + 1 end
		inHand[seat] = true
	end
	if count < 2 then return nil, "need two players" end

	local isIn = function(s) return inHand[s] end
	local button = self:NextSeat(self.button, isIn)
	local sbSeat, bbSeat
	if count == 2 then
		sbSeat = button -- heads-up: the button posts the small blind and acts first preflop
		bbSeat = self:NextSeat(button, isIn)
	else
		sbSeat = self:NextSeat(button, isIn)
		bbSeat = self:NextSeat(sbSeat, isIn)
	end

	local order, s = {}, button
	for _ = 1, count do
		s = self:NextSeat(s, isIn)
		order[#order + 1] = s
	end
	return { inHand = inHand, count = count, button = button, sbSeat = sbSeat, bbSeat = bbSeat, order = order }
end

function Engine:StartHand(no, players)
	if self:InHand() then return false, "hand in progress" end
	local plan, err = self:PlanHand(players)
	if not plan then return false, err end
	local inHand, count, button, sbSeat, bbSeat, order =
		plan.inHand, plan.count, plan.button, plan.sbSeat, plan.bbSeat, plan.order
	self.button = button

	local h = {
		no = no, inHand = inHand, order = order, count = count,
		button = button, sbSeat = sbSeat, bbSeat = bbSeat,
		bet = {}, total = {}, folded = {}, allin = {}, actedAt = {},
		street = 1, board = {}, seq = 0, phase = "betting",
		startStacks = {},
	}
	for seat in pairs(inHand) do
		h.bet[seat], h.total[seat] = 0, 0
		h.startStacks[seat] = self.seats[seat].stack
	end
	self.hand = h

	self:Pay(sbSeat, self.sb)
	self:Pay(bbSeat, self.bb)
	h.currentBet = self.bb
	h.fullBet = self.bb
	h.minRaise = self.bb
	self:Emit("handStart", h)
	self:Advance(bbSeat)
	return true
end

function Engine:Pay(seat, amount)
	local h, st = self.hand, self.seats[seat]
	local a = min(amount, st.stack)
	st.stack = st.stack - a
	h.bet[seat] = h.bet[seat] + a
	h.total[seat] = h.total[seat] + a
	if st.stack == 0 then h.allin[seat] = true end
	return a
end

function Engine:Live(seat) -- still holding cards
	local h = self.hand
	return h.inHand[seat] and not h.folded[seat]
end

function Engine:CanAct(seat) -- holding cards with chips behind
	local h = self.hand
	return h.inHand[seat] and not h.folded[seat] and not h.allin[seat]
end

function Engine:NeedsAction(seat)
	local h = self.hand
	if not self:CanAct(seat) then return false end
	if h.actedAt[seat] == nil or h.bet[seat] < h.currentBet then
		-- nobody left to bet against: a lone active player who has matched the bet is done
		local others = 0
		for s in pairs(h.inHand) do
			if s ~= seat and self:CanAct(s) then others = others + 1 end
		end
		if others == 0 and h.bet[seat] >= h.currentBet then return false end
		return true
	end
	return false
end

function Engine:LiveCount()
	local n, last = 0, nil
	for s in pairs(self.hand.inHand) do
		if self:Live(s) then n, last = n + 1, s end
	end
	return n, last
end

--- Move the turn to the next seat after `from` that needs to act, or close the street.
function Engine:Advance(from)
	local h = self.hand
	local n, last = self:LiveCount()
	if n == 1 then return self:FinishUncontested(last) end
	local nextSeat = self:NextSeat(from, function(s) return self:NeedsAction(s) end)
	if nextSeat then
		h.toAct = nextSeat
		h.phase = "betting"
		self:Emit("turn", nextSeat)
	else
		self:EndStreet()
	end
end

function Engine:EndStreet()
	local h = self.hand
	h.toAct = nil
	for s in pairs(h.inHand) do
		h.bet[s] = 0
		h.actedAt[s] = nil
	end
	h.currentBet, h.fullBet, h.minRaise = 0, 0, self.bb
	if h.street >= 4 then
		h.phase = "showdown"
		self:Emit("needShowdown")
	else
		h.phase = "board"
		self:Emit("needBoard", Engine.STREETS[h.street + 1])
	end
end

function Engine:DealBoard(cards)
	local h = self.hand
	if not h or h.phase ~= "board" then return false, "not waiting for board" end
	local need = h.street == 1 and 3 or 1
	if #cards ~= need then return false, "wrong card count" end
	for _, c in ipairs(cards) do h.board[#h.board + 1] = c end
	h.street = h.street + 1
	self:Emit("board", Engine.STREETS[h.street], cards)
	self:Advance(h.button)
	return true
end

---------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------
function Engine:Legal(seat)
	local h = self.hand
	if not h or h.phase ~= "betting" or h.toAct ~= seat then return nil end
	local st = self.seats[seat]
	local toCall = min(st.stack, h.currentBet - h.bet[seat])
	local maxTo = h.bet[seat] + st.stack
	local canRaise = (h.actedAt[seat] == nil or h.actedAt[seat] < h.fullBet) and maxTo > h.currentBet
	if canRaise then
		local others = false
		for s in pairs(h.inHand) do
			if s ~= seat and self:CanAct(s) then others = true break end
		end
		canRaise = others
	end
	return {
		check = h.bet[seat] >= h.currentBet,
		toCall = toCall,
		canRaise = canRaise,
		minTo = min(maxTo, h.currentBet + h.minRaise),
		maxTo = maxTo,
		isBet = h.currentBet == 0,
	}
end

--- kind: "fold" | "check" | "call" | "raise" (amount = total bet for this street) | "allin"
function Engine:Act(seat, kind, amount)
	local h = self.hand
	local legal = self:Legal(seat)
	if not legal then return false, "not your turn" end
	local st = self.seats[seat]

	if kind == "allin" then
		if legal.canRaise then kind, amount = "raise", legal.maxTo
		elseif legal.check then kind = "check"
		else kind = "call" end
	end

	local paid = 0
	if kind == "fold" then
		h.folded[seat] = true
	elseif kind == "check" then
		if not legal.check then return false, "cannot check" end
	elseif kind == "call" then
		if legal.check then return false, "nothing to call" end
		paid = self:Pay(seat, h.currentBet - h.bet[seat])
	elseif kind == "raise" then
		amount = floor(tonumber(amount) or 0)
		if not legal.canRaise then return false, "cannot raise" end
		if amount > legal.maxTo then return false, "not enough chips" end
		if amount < legal.minTo then return false, "raise too small" end
		paid = self:Pay(seat, amount - h.bet[seat])
		if amount - h.currentBet >= h.minRaise then -- full raise reopens the betting
			h.minRaise = amount - h.currentBet
			h.fullBet = amount
		end
		h.currentBet = amount
	else
		return false, "unknown action"
	end

	h.actedAt[seat] = h.fullBet
	h.seq = h.seq + 1
	self:Emit("action", seat, kind, h.bet[seat], paid)
	self:Advance(seat)
	return true
end

--- Player left or timed out without being on the clock: fold them where they sit.
function Engine:ForceFold(seat)
	local h = self.hand
	if not h or h.phase == "done" or not self:Live(seat) then return false end
	if h.toAct == seat and h.phase == "betting" then return self:Act(seat, "fold") end
	h.folded[seat] = true
	h.seq = h.seq + 1
	self:Emit("action", seat, "fold", h.bet[seat], 0)
	local n, last = self:LiveCount()
	if n == 1 then self:FinishUncontested(last) end
	return true
end

--- Cancel the hand in progress: everyone gets back exactly what they started it with.
function Engine:Void()
	local h = self.hand
	if not h or h.phase == "done" then return false end
	for seat, stack in pairs(h.startStacks) do
		if self.seats[seat] then self.seats[seat].stack = stack end
	end
	h.phase = "done"
	h.toAct = nil
	h.voided = true
	h.result = { voided = true, awards = {} }
	self:Emit("handEnd", h.result)
	return true
end

---------------------------------------------------------------------------------------------
-- Settlement
---------------------------------------------------------------------------------------------
function Engine:ReturnUncalled()
	local h = self.hand
	local top, topSeat, second = -1, nil, 0
	for s in pairs(h.inHand) do
		local v = h.total[s]
		if v > top then second, top, topSeat = max(second, top), v, s
		elseif v > second then second = v end
	end
	if topSeat and top > second then
		local back = top - second
		h.total[topSeat] = second
		self.seats[topSeat].stack = self.seats[topSeat].stack + back
		h.returned = { seat = topSeat, amount = back }
	end
end

function Engine:PotTotal()
	local h, n = self.hand, 0
	if not h then return 0 end
	for s in pairs(h.inHand) do n = n + h.total[s] end
	return n
end

function Engine:FinishUncontested(winner)
	local h = self.hand
	self:ReturnUncalled()
	local pot = self:PotTotal()
	self.seats[winner].stack = self.seats[winner].stack + pot
	h.phase = "done"
	h.toAct = nil
	h.result = { showdown = false, awards = { { seat = winner, amount = pot } } }
	self:Emit("handEnd", h.result)
end

--- Side pots from total contributions. Returns { {amount=, eligible={seat=true}} ... }
function Engine:Pots()
	local h = self.hand
	local levels, seen = {}, {}
	for s in pairs(h.inHand) do
		if not h.folded[s] and not seen[h.total[s]] and h.total[s] > 0 then
			seen[h.total[s]] = true
			levels[#levels + 1] = h.total[s]
		end
	end
	table.sort(levels)
	local pots, prev = {}, 0
	for i, L in ipairs(levels) do
		local amount = 0
		for s in pairs(h.inHand) do
			local c = h.total[s]
			amount = amount + min(c, L) - min(c, prev)
		end
		if i == #levels then -- dead money above the last live level (rare) goes to the last pot
			for s in pairs(h.inHand) do
				if h.total[s] > L then amount = amount + h.total[s] - L end
			end
		end
		local eligible = {}
		for s in pairs(h.inHand) do
			if not h.folded[s] and h.total[s] >= L then eligible[s] = true end
		end
		if amount > 0 then pots[#pots + 1] = { amount = amount, eligible = eligible } end
		prev = L
	end
	return pots
end

--- holes[seat] = {c1, c2} for every live seat. Awards all pots and ends the hand.
function Engine:Showdown(holes)
	local h = self.hand
	if not h or h.phase ~= "showdown" then return false, "not at showdown" end
	self:ReturnUncalled()
	local scores, names = {}, {}
	for s in pairs(h.inHand) do
		if not h.folded[s] then
			local hole = holes[s]
			if not hole then return false, "missing hole cards for seat " .. s end
			local seven = { hole[1], hole[2] }
			for _, c in ipairs(h.board) do seven[#seven + 1] = c end
			local sc, _, desc = ns.Eval.Eval(seven)
			scores[s], names[s] = sc, desc
		end
	end

	local awards, bySeat = {}, {}
	for potIndex, pot in ipairs(self:Pots()) do
		local best, winners = -1, {}
		-- iterate clockwise from the button so odd chips go to the first winner left of it
		local s = h.button
		for _ = 1, self.maxSeats do
			s = s % self.maxSeats + 1
			if pot.eligible[s] then
				if scores[s] > best then best, winners = scores[s], { s }
				elseif scores[s] == best then winners[#winners + 1] = s end
			end
		end
		local share = floor(pot.amount / #winners)
		local odd = pot.amount - share * #winners
		for i, w in ipairs(winners) do
			local amt = share + (i <= odd and 1 or 0)
			self.seats[w].stack = self.seats[w].stack + amt
			bySeat[w] = (bySeat[w] or 0) + amt
			awards[#awards + 1] = { seat = w, amount = amt, pot = potIndex, hand = names[w] }
		end
	end
	h.phase = "done"
	h.result = { showdown = true, awards = awards, won = bySeat, handNames = names, holes = holes }
	self:Emit("handEnd", h.result)
	return true
end
