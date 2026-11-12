-- Mini HUD: your cards, the board, the pot and the three buttons you need, small enough to
-- leave on screen while questing. Off-turn the Fold / Call buttons queue an automatic action.
local _, ns = ...

local W = ns.W
local M = {}
ns.MiniUI = M

local function T() return ns.current end

function M:Create()
	if self.frame then return self.frame end
	local f = CreateFrame("Frame", "GoblinHoldemMini", UIParent, W.BACKDROP_TEMPLATE)
	self.frame = f
	f:SetSize(336, 140)
	f:SetPoint("CENTER", 0, -230)
	f:SetFrameStrata("MEDIUM")
	W.Backdrop(f, "plate")
	W.Movable(f, "mini")

	f.title = W.Text(f, 11)
	f.title:SetPoint("TOPLEFT", 9, -7)
	f.title:SetTextColor(1, 0.82, 0)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 3, 3)
	close:SetScale(0.8)
	local full = W.Button(f, "Table", 52, 18, function()
		if ns.db then ns.db.settings.mini = false end
		ns.TableUI:Show()
	end)
	full:SetPoint("TOPRIGHT", -26, -4)

	f.hole = {}
	for i = 1, 2 do
		local c = W.Card(f, 34, 48)
		c:SetPoint("TOPLEFT", 10 + (i - 1) * 36, -24)
		f.hole[i] = c
	end
	f.board = {}
	for i = 1, 5 do
		local c = W.Card(f, 30, 42)
		c:SetPoint("TOPLEFT", 92 + (i - 1) * 32, -27)
		f.board[i] = c
	end
	f.pot = W.Text(f, 11)
	f.pot:SetPoint("TOPLEFT", 256, -30)
	f.pot:SetWidth(74)
	f.pot:SetJustifyH("LEFT")
	f.pot:SetTextColor(1, 0.9, 0.6)

	f.status = W.Text(f, 12)
	f.status:SetPoint("TOPLEFT", 10, -77)
	f.status:SetWidth(316)
	f.status:SetJustifyH("LEFT")
	f.status:SetWordWrap(false)

	f.fold = W.Button(f, "Fold", 76, 24, function() ns.TableUI:Do("fold") end)
	f.fold:SetPoint("BOTTOMLEFT", 8, 12)
	f.call = W.Button(f, "Check", 112, 24, function() M:CallOrBack() end)
	f.call:SetPoint("LEFT", f.fold, "RIGHT", 4, 0)
	f.half = W.Button(f, "1/2 Pot", 62, 24, function() M:Raise(0.5) end)
	f.half:SetPoint("LEFT", f.call, "RIGHT", 4, 0)
	f.potBtn = W.Button(f, "Pot", 54, 24, function() M:Raise(1) end)
	f.potBtn:SetPoint("LEFT", f.half, "RIGHT", 4, 0)
	W.Tooltip(f.half, function(tt) tt:AddLine("Bet or raise half the pot. Open the full table for exact amounts or all-in.", 1, 1, 1, true) end)
	W.Tooltip(f.potBtn, function(tt) tt:AddLine("Bet or raise the size of the pot.", 1, 1, 1, true) end)

	f.timer = CreateFrame("StatusBar", nil, f)
	f.timer:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	f.timer:SetStatusBarColor(1, 0.75, 0.1)
	f.timer:SetPoint("BOTTOMLEFT", 6, 5)
	f.timer:SetPoint("BOTTOMRIGHT", -6, 5)
	f.timer:SetHeight(4)
	f.timer:SetMinMaxValues(0, 1)

	local acc = 0
	f:SetScript("OnUpdate", function(_, elapsed)
		if M.dirty then M.dirty = false M:Refresh() end
		acc = acc + elapsed
		if acc < 0.1 then return end
		acc = 0
		local t = T()
		local frac, seat = ns.TableUI:TurnFraction()
		if seat and t and seat == t:MySeat() then
			f.timer:Show()
			f.timer:SetValue(frac or 1)
			if frac and frac < 0.25 then f.timer:SetStatusBarColor(1, 0.2, 0.1) else f.timer:SetStatusBarColor(1, 0.75, 0.1) end
		else
			f.timer:Hide()
		end
	end)
	f:Hide()
	return f
end

function M:CallOrBack()
	local t = T()
	local seat = t and t:MySeat()
	if seat and t.engine.seats[seat].sittingOut then return t:SitOut(false) end
	ns.TableUI:Do("call")
end

function M:Raise(frac)
	local amount = ns.TableUI:PresetAmount(frac)
	if amount then ns.TableUI:Do("raise", amount) end
end

function M:Refresh()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local t = T()
	if not t then
		f.title:SetText("Goblin Hold'em")
		f.status:SetText("You're not at a table. Left-click the minimap coin for the lobby.")
		for _, c in ipairs(f.hole) do c:SetCard(nil) end
		for _, c in ipairs(f.board) do c:SetCard(nil) end
		f.pot:SetText("")
		for _, b in ipairs({ f.fold, f.call, f.half, f.potBtn }) do b:SetEnabled(false) end
		return
	end
	local c, e, h = t.cfg, t.engine, t.engine.hand
	local seat = t:MySeat()
	local cur = t.cur
	f.title:SetText(("%s  |cffbbbbbb%s/%s|r%s"):format(c.name, ns.Money(c.sb, c.mode, true), ns.Money(c.bb, c.mode, true),
		seat and ("  |cffffffff" .. ns.Money(e.seats[seat].stack, c.mode) .. "|r") or ""))

	local live = h and h.phase ~= "done"
	local mine = seat and cur and cur.myHole and h and cur.no == h.no and h.inHand[seat]
	for i = 1, 2 do
		if mine then
			f.hole[i]:SetCard(cur.myHole[i])
			f.hole[i]:SetDim(h.folded[seat])
		else
			f.hole[i]:SetCard(nil)
		end
	end
	for i = 1, 5 do f.board[i]:SetCard(h and h.board[i] or nil) end
	local pot = h and e:PotTotal() or 0
	f.pot:SetText(pot > 0 and ("Pot\n" .. ns.Money(pot, c.mode)) or "")

	local info, hand = ns.TableUI:InfoText()
	if not live and ns.TableUI.resultText then info = ns.TableUI.resultText:gsub("\n", "  ") end
	f.status:SetText(info .. (hand ~= "" and live and ("  |cff66ccff" .. hand .. "|r") or ""))

	local L = ns.TableUI:MyLegal()
	local sittingOut = seat and e.seats[seat].sittingOut
	if L then
		f.fold:SetText("Fold")
		f.call:SetText(L.check and "Check" or ("Call " .. ns.Money(L.toCall, c.mode, true)))
		f.fold:SetEnabled(true) f.call:SetEnabled(true)
		f.half:SetEnabled(L.canRaise) f.potBtn:SetEnabled(L.canRaise)
		f.fold:UnlockHighlight() f.call:UnlockHighlight()
	else
		local canQueue, owe = ns.TableUI:QueueInfo()
		local pre = t.preAction
		f.half:SetEnabled(false) f.potBtn:SetEnabled(false)
		f.fold:SetEnabled(canQueue)
		f.fold:SetText(canQueue and "Auto fold" or "Fold")
		if sittingOut and t.phase ~= "closed" then
			f.call:SetText("I'm back")
			f.call:SetEnabled(true)
		else
			f.call:SetText(canQueue and (owe > 0 and ("Auto call " .. ns.Money(owe, c.mode, true)) or "Auto check") or "Check / Call")
			f.call:SetEnabled(canQueue)
		end
		if pre and pre.kind == "checkfold" then f.fold:LockHighlight() else f.fold:UnlockHighlight() end
		if pre and pre.kind == "call" then f.call:LockHighlight() else f.call:UnlockHighlight() end
	end
end

function M:Show()
	self:Create()
	if ns.TableUI.frame then ns.TableUI.frame:Hide() end
	self.frame:Show()
	self:Refresh()
end

function M:Toggle()
	self:Create()
	if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

ns.Listen("TABLE_UPDATE", function() M.dirty = true end)
ns.Listen("TABLE_HAND_END", function() M.dirty = true end)
