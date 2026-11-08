-- Core tests: run with `python tests/run.py` (uses lupa's LuaJIT, which has the same `bit` API as WoW).
local ns = ...
local Cards, Eval, Engine, Fair = ns.Cards, ns.Eval, ns.Engine, ns.Fair
local failures, passed = 0, 0
local function check(cond, msg)
	if cond then passed = passed + 1 else failures = failures + 1 print("FAIL: " .. msg) end
end
local function eq(a, b, msg) check(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
local function C(s) return Cards.ListFromString(s) end

-- SHA-256 test vectors
eq(ns.SHA256(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha empty")
eq(ns.SHA256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha abc")
eq(ns.SHA256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
	"248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1", "sha 2-block")
eq(ns.SHA256(string.rep("a", 1000)), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3", "sha 1000a")

-- Shuffle is a permutation and deterministic
local d1, d2 = Cards.Shuffle("seed1"), Cards.Shuffle("seed1")
local seen = {}
for i = 1, 52 do seen[d1[i]] = true eq(d1[i], d2[i], "deterministic " .. i) end
local n = 0 for _ in pairs(seen) do n = n + 1 end
eq(n, 52, "permutation")
check(Cards.ListToString(Cards.Shuffle("seed2")) ~= Cards.ListToString(d1), "different seeds differ")

-- Rough uniformity: position of the ace of spades over many shuffles
local counts = {}
for i = 1, 2600 do
	local d = Cards.Shuffle("u" .. i)
	for p = 1, 52 do if d[p] == 51 then counts[p] = (counts[p] or 0) + 1 end end
end
local lo, hi = 1e9, 0
for p = 1, 52 do lo = math.min(lo, counts[p] or 0) hi = math.max(hi, counts[p] or 0) end
check(lo > 20 and hi < 90, "uniform-ish ace position (min " .. lo .. " max " .. hi .. ")")

-- Evaluator
local function ev(s) local sc, cat, desc = Eval.Eval(C(s)) return sc, cat, desc end
local _, cat, desc = ev("AsKsQsJsTs2d3c") eq(cat, 8, "royal cat") eq(desc, "Royal Flush", "royal desc")
_, cat = ev("As2s3s4s5s9d9c") eq(cat, 8, "steel wheel")
_, cat, desc = ev("9c9d9h9s2c3d4h") eq(cat, 7, "quads") eq(desc, "Four of a Kind, Nines", "quads desc")
_, cat, desc = ev("KcKdKh7s7c2d2h") eq(cat, 6, "boat") eq(desc, "Full House, Kings over Sevens", "boat desc")
_, cat, desc = ev("KcKdKh7s7c7d2h") eq(desc, "Full House, Kings over Sevens", "two trips boat")
_, cat = ev("2h7h9hJhKh3c4d") eq(cat, 5, "flush")
_, cat, desc = ev("Ac2d3h4s5c9dKh") eq(cat, 4, "wheel") eq(desc, "Straight, Five high", "wheel desc")
_, cat = ev("TcJdQhKsAc2d3h") eq(cat, 4, "broadway")
_, cat = ev("7c7d7h2s9cJdKh") eq(cat, 3, "trips")
_, cat, desc = ev("7c7d9h9s2cJdJh") eq(cat, 2, "two pair") eq(desc, "Two Pair, Jacks and Nines", "best two pair")
_, cat = ev("7c7d9h3s2cJdKh") eq(cat, 1, "pair")
_, cat = ev("7c4d9h3s2cJdKh") eq(cat, 0, "high")
check(ev("AcAd2h3s7c9dJh") > ev("KcKdAhQs7c9dJh"), "aces > kings")
check(ev("AcAdKh3s7c9d2h") > ev("AcAdQh3s7c9d2h"), "kicker")
check(ev("6c5d4h3s2c9dJh") > ev("Ac2d3h4s5c9dJh"), "six-high straight beats wheel")
eq(ev("AcAdKhQsJc2d3h"), ev("AhAsKcQdJs4c5h"), "split")

-- Engine helpers
local function newTable(stacks, sb, bb)
	local t = Engine.New({ maxSeats = 9, sb = sb or 5, bb = bb or 10 })
	for seat, st in pairs(stacks) do t:Sit(seat, "P" .. seat, st) end
	return t
end
local function act(t, seat, kind, amt)
	local ok, err = t:Act(seat, kind, amt)
	check(ok, ("act seat %d %s %s: %s"):format(seat, kind, tostring(amt), tostring(err)))
end

-- 3 handed: blinds, BB option, fold-out
do
	local t = newTable({ [1] = 1000, [2] = 1000, [3] = 1000 })
	assert(t:StartHand(1, { 1, 2, 3 }))
	local h = t.hand
	eq(h.button, 1, "button") eq(h.sbSeat, 2, "sb") eq(h.bbSeat, 3, "bb") eq(h.toAct, 1, "utg first")
	act(t, 1, "call") act(t, 2, "call")
	eq(h.toAct, 3, "bb option") act(t, 3, "check")
	eq(h.phase, "board", "flop needed")
	assert(t:DealBoard(C("2c3d4h")))
	eq(h.toAct, 2, "sb first postflop")
	act(t, 2, "raise", 20) act(t, 3, "fold") act(t, 1, "fold")
	eq(h.phase, "done", "fold out")
	eq(t.seats[2].stack, 1020, "winner stack")
	eq(t.seats[1].stack + t.seats[2].stack + t.seats[3].stack, 3000, "chips conserved")
end

-- Heads-up: button is SB and acts first preflop, last postflop
do
	local t = newTable({ [4] = 500, [7] = 500 })
	assert(t:StartHand(1, { 4, 7 }))
	local h = t.hand
	eq(h.button, 4, "hu button") eq(h.sbSeat, 4, "hu sb is button") eq(h.toAct, 4, "hu button acts first pre")
	act(t, 4, "call") act(t, 7, "check")
	assert(t:DealBoard(C("2c3d4h")))
	eq(h.toAct, 7, "hu bb first post")
	act(t, 7, "check") act(t, 4, "check")
	assert(t:DealBoard(C("5s"))) act(t, 7, "check") act(t, 4, "check")
	assert(t:DealBoard(C("9s"))) act(t, 7, "check") act(t, 4, "check")
	eq(h.phase, "showdown", "hu showdown")
	assert(t:Showdown({ [4] = C("AhAd"), [7] = C("KhKd") }))
	eq(t.seats[4].stack, 510, "hu aces win") eq(t.seats[7].stack, 490, "hu kings lose")
	-- button moves
	assert(t:StartHand(2, { 4, 7 }))
	eq(t.hand.button, 7, "button moves")
end

-- Min-raise rules and incomplete all-in raise not reopening action
do
	local t = newTable({ [1] = 1000, [2] = 1000, [3] = 65 })
	assert(t:StartHand(1, { 1, 2, 3 })) -- btn 1, sb 2, bb 3
	local L = t:Legal(1)
	eq(L.minTo, 20, "min raise to 2bb")
	local ok = t:Act(1, "raise", 15) check(not ok, "raise below min rejected")
	act(t, 1, "raise", 40)                  -- raise by 30
	eq(t:Legal(2).minTo, 70, "next min raise is +30")
	act(t, 2, "call")
	act(t, 3, "allin")                      -- 65 total: +25, less than a full raise
	eq(t.hand.currentBet, 65, "all-in sets bet")
	local L1 = t:Legal(1)
	check(L1 and not L1.canRaise, "incomplete raise does not reopen for original raiser")
	act(t, 1, "call")
	local L2 = t:Legal(2)
	check(L2 and not L2.canRaise, "nor for the caller")
	act(t, 2, "call")
	eq(t.hand.phase, "board", "street closed")
end

-- Side pots: short all-in, two bigger stacks
do
	local t = newTable({ [1] = 100, [2] = 300, [3] = 300 })
	assert(t:StartHand(1, { 1, 2, 3 }))
	act(t, 1, "allin")          -- 100
	act(t, 2, "raise", 300)     -- all in 300
	act(t, 3, "call")           -- all in 300
	eq(t.hand.phase, "board", "board after all-ins")
	assert(t:DealBoard(C("2c7d9h")))
	eq(t.hand.phase, "board", "no betting when all are all-in")
	assert(t:DealBoard(C("Js")))
	assert(t:DealBoard(C("3c")))
	eq(t.hand.phase, "showdown", "showdown reached")
	local pots = t:Pots()
	eq(#pots, 2, "two pots") eq(pots[1].amount, 300, "main pot") eq(pots[2].amount, 400, "side pot")
	-- seat 1 best (AA), seat 2 second (KK), seat 3 worst
	assert(t:Showdown({ [1] = C("AhAd"), [2] = C("KhKd"), [3] = C("QhQd") }))
	eq(t.seats[1].stack, 300, "short stack wins main") eq(t.seats[2].stack, 400, "KK wins side")
	eq(t.seats[3].stack, 0, "QQ busts")
end

-- Uncalled bet returned
do
	local t = newTable({ [1] = 1000, [2] = 200 })
	assert(t:StartHand(1, { 1, 2 }))
	act(t, 1, "raise", 1000) -- shove 1000 vs 200 stack
	act(t, 2, "call")        -- calls all-in for 200
	assert(t:DealBoard(C("2c7d9h"))) assert(t:DealBoard(C("Js"))) assert(t:DealBoard(C("3c")))
	assert(t:Showdown({ [1] = C("4h5d"), [2] = C("KhKd") }))
	eq(t.seats[1].stack, 800, "uncalled 800 returned") eq(t.seats[2].stack, 400, "doubled up")
end

-- Split pot with odd chip to first seat left of button
do
	local t = newTable({ [1] = 1000, [2] = 1000, [3] = 1000 }, 5, 10)
	assert(t:StartHand(1, { 1, 2, 3 })) -- btn 1, sb 2, bb 3
	act(t, 1, "call") act(t, 2, "fold") act(t, 3, "check") -- pot 25 (dead small blind)
	assert(t:DealBoard(C("AcKdQh"))) act(t, 3, "check") act(t, 1, "check")
	assert(t:DealBoard(C("Js"))) act(t, 3, "check") act(t, 1, "check")
	assert(t:DealBoard(C("Tc"))) act(t, 3, "check") act(t, 1, "check")
	assert(t:Showdown({ [1] = C("2h3h"), [3] = C("4d5d") })) -- both play the board
	eq(t.seats[3].stack, 1003, "odd chip to first winner left of button")
	eq(t.seats[1].stack, 1002, "other half")
end

print(("core: %d passed, %d failed"):format(passed, failures))
return failures
