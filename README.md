# Goblin Hold'em

No-limit Texas Hold'em inside World of Warcraft, with friends anywhere on the realm, your
party/raid, or solo against goblin bots. Built for **WoW Forever** (interface `16001`). There's no
server and no outside program: the add-ons talk to each other over hidden addon messages.

The hard part of poker over chat is trust. Who shuffles, and how does anyone know the dealer
didn't stack the deck? Goblin Hold'em uses a **sealed deck** that the Blizzard server helps shuffle,
and every player's add-on checks every hand.

## Install

Copy (or `git clone`) this folder to `World of Warcraft\_forever_\Interface\AddOns\GoblinHoldem`
and reload. Every player at the table needs the add-on.

## Playing

**Try it alone first:** `/holdem practice` (or **Practice vs bots** in the lobby) opens a table with
four goblin bots and play chips. Nothing is sent to anyone.

**With friends, wherever they are (no party needed):**

1. Open `/holdem lobby`, then **Host a table** with players set to **Anywhere**. Pick the blinds,
   buy-in range, seats, turn timer, game type, and whether you play too.
2. Click **Invite** on the table and type a friend's name, or have them type
   `/holdem join <your name>`.
3. They click an open seat to buy in. Hands deal automatically once two players are seated.

The table runs on a private, password-protected chat channel that's hidden from your chat
windows. Players can be in different zones; they just need to be on the same realm and faction.

**In person:** host with players set to **In my party/raid**. The shuffle then uses real server
`/roll`s that the whole group sees. Public tables can be advertised on a hidden realm channel and to
your guild, and adverts include your zone (a tavern in Booty Bay, say).

At the table you get Fold / Check / Call / Bet / Raise, a raise slider, and ½-pot, ¾-pot, pot and
all-in buttons. **Ledger & Audit** shows who's up and down, who pays whom, and the audit of every
hand.

### Playing while you're busy

- **Minimap coin:** left-click opens or closes the game, right-click opens settings, drag moves it.
  It glows when it's your turn.
- **Mini HUD:** a small bar with your cards, the board, the pot and Fold / Call / ½ Pot / Pot.
  It pops up by itself when it's your turn, so you can keep the big table closed while questing.
- **Queued actions:** when it isn't your turn, Fold and Call turn into "Auto check/fold" and
  "Auto call". Click one and it plays for you when the turn arrives. A queued call is dropped if
  someone raises.
- **Key bindings:** Esc → Key Bindings → AddOns → Goblin Hold'em has open/close, fold and check/call.
- **Timing out sits you out.** If the clock runs out you check or fold, and you're sat out until you
  click **I'm back**, so you don't bleed blinds or stall the table every hand. The host sets the
  turn timer (default 45 seconds, `0` for no timer). The dealer can right-click a seat to skip a
  stalled turn; everyone is told it was a skip.
- **Safety nets:** going all-in for gold asks first, and Fold checks instead when checking is free.

### Debts and history

**Ledger & Audit** has two more tabs. **Debts** keeps a running total per person across finished
gold tables ("Thrall owes you 3g"), with a Settled button once the gold has changed hands.
**History** lists your past tables and what you won or lost. Every table is saved after each hand,
so a crash or disconnect doesn't lose the record.

### Game types

| Type | Chips are | Money moves |
|---|---|---|
| **Friends (IOU)** | gold | Never at the table. The ledger shows the fewest trades needed to settle up at the end. |
| **House bank** | gold | Players trade the dealer gold to buy in, and the dealer approves the chips. The dealer trades their stack back when they cash out. The dealer can't play at their own bank table. |
| **Play chips** | nothing | Just for fun. |

The add-on never moves gold itself. You pay through the trade window or the mail.

## How the shuffle stays fair

For each hand:

1. **Seal.** The dealer's add-on picks a random secret and posts `seal = SHA-256(secret)`. After
   this the secret can't change without everyone noticing.
2. **Everyone adds randomness.** At party/raid tables each seated player's add-on does
   `/roll 1-1000000`. The **Blizzard server** makes the roll and the whole group sees it, so nobody
   can fake or choose it. At anywhere tables each player's add-on sends a random seed over the
   table channel instead. The server stamps who sent each one, so the dealer can't fake them either.
3. **Shuffle.** `deck = FisherYates(SHA-256(table | hand | secret | every roll or seed))`. The
   dealer sealed before anyone's randomness existed, so it can't steer the deck. Players don't know
   the secret, so they can't predict it. The shuffle draws from a SHA-256 stream with rejection
   sampling, so there's no modulo bias.
4. **Private cards.** Hole cards travel encrypted with a key that only that player and the dealer's
   add-on know. Board cards are public.
5. **Unseal.** When the hand ends the dealer reveals the secret. Every add-on rebuilds the deck
   and checks the seal, every roll it saw, every board card, and its own hole cards. Showdown
   hands come straight from that rebuilt deck.

If anything doesn't match, everyone gets a red alert and the hand is **voided** (all stacks go back
to where they were). A player whose own hole cards don't match can publish their key, so the
whole table can check the claim.

All betting is checked the same way. Each player sends their own action (the server stamps who
sent it), and every add-on runs the same rules engine. Nobody can bet chips they don't have, act
out of turn, or change a stack. Stacks and side pots are worked out on every add-on, so nobody
has to trust anyone's numbers.

### Why do party tables use /roll and anywhere tables use seeds?

The server only shows a `/roll` to your group or to people standing nearby, so friends in other
zones can't see each other's rolls. Seeds give the same guarantee once the deck is sealed: the
dealer can't change the deck after the fact, and no player can predict it. The one extra thing a
roll protects against is a dealer and a player colluding to pick a seed, but a dealer who
cheats with a partner can already see the hole cards (see below). Party tables keep rolls because
being able to watch everyone roll feels right at an in-person table.

### Why not roll for each card?

Rolls are public, so anything rolled for directly is seen by everyone, hole cards included. You'd
also need dozens of rolls a hand, plus re-rolls for duplicates. One roll per player as *entropy*
for a sealed shuffle keeps the cards secret, needs a handful of rolls, and can't be biased.

### What's still on trust

- **The dealer's add-on knows the hole cards while a hand is running.** Only real "mental poker"
  cryptography fixes this, and that's too heavy for addon chat. For games with strangers, use a
  dealer who doesn't play: a friend, an alt, or the house-bank mode. The table warns everyone when
  the dealer is seated.
- **Collusion.** Two players sharing cards on Discord can't be detected by any add-on.
- **Paying up.** In IOU games the ledger tells you who owes what. Paying is between you.

## Commands

```
/holdem            open the table (or the lobby if you're not at one)
/holdem lobby      find or host a table
/holdem practice   solo table against goblin bots
/holdem join Name  join a friend's table, wherever they are
/holdem invite Name  (dealer) invite someone to your table
/holdem mini       small HUD (/holdem full for the big table)
/holdem settings   options (same as right-clicking the minimap coin)
/holdem debts      who owes whom across sessions
/holdem history    past tables
/holdem ledger     session ledger and settle-up
/holdem audit      per-hand audit trail and alerts
/holdem fair       how the shuffle works
/holdem rolls      show/hide the shuffle rolls in chat (hidden by default; shown in the table log)
/holdem sound      toggle sounds
/holdem autoopen   open the table window when someone starts a table in your group
/holdem forget     drop a stuck table on your side
```

## Rules implemented

No-limit hold'em with heads-up blind rules (the button posts the small blind), proper minimum
raises, short all-ins that don't reopen the betting, side pots, returned uncalled bets, split pots
with the odd chip to the first winner left of the button, a turn timer (check if you can, otherwise
fold), sitting out, adding chips between hands, and leaving mid-session.

## Development

Logic tests run outside the game with LuaJIT through [lupa](https://pypi.org/project/lupa/):

```
pip install lupa
python tests/run.py
```

- `tests/test_core.lua`: SHA-256 test vectors, shuffle determinism and uniformity, hand rankings,
  blinds and heads-up order, min-raise rules and incomplete all-ins, side pots, uncalled bets, odd
  chips.
- `tests/sim.py`: independent simulated clients play only through routed addon messages, chat
  channels and server rolls. It covers a 5-player party table (60 hands), a 4-player anywhere table
  where nobody is grouped (25 hands), and 30 solo practice hands against bots. It checks that every
  client agrees on every stack, chips are conserved, every hand passes audit, and AFK timeouts and
  leaving work. It also runs three cheating dealers (a fake roll, a fake seed, a swapped board
  card) and checks all are caught, and checks that an uninvited stranger can't get a private
  table's channel password.
- `tests/ui_smoke.py`: loads every file in TOC order against a mocked frame API and plays a hand
  through the UI.

Textures are generated by `tools/make_textures.py` (Pillow).

## License

MIT
