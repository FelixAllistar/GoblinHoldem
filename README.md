# Goblin Hold'em

No-limit Texas Hold'em inside World of Warcraft, played with your party or raid. Built for
**WoW Forever** (interface `16001`). There's no server and no outside program: the add-ons talk
to each other over hidden addon messages.

The hard part of poker over chat is trust. Who shuffles, and how does anyone know the dealer
didn't stack the deck? Goblin Hold'em uses a **sealed deck** that the Blizzard server helps shuffle,
and every player's add-on checks every hand.

## Install

Copy (or `git clone`) this folder to `World of Warcraft\_forever_\Interface\AddOns\GoblinHoldem`
and reload. Every player at the table needs the add-on.

## Playing

1. Form a party or raid. Tables run inside the group so everyone sees every `/roll`.
2. The host opens `/holdem lobby` → **Host a table**: name, blinds, buy-in range, seats, turn timer,
   game type, and whether the host plays too.
3. Group members type `/holdem` and click an open seat to buy in.
4. The dealer's add-on deals automatically. You get Fold / Check / Call / Bet / Raise, a raise slider,
   and ½-pot, ¾-pot, pot and all-in buttons.
5. **Ledger & Audit** shows who's up and down, who pays whom, and the audit of every hand.

Public tables can be advertised on a hidden realm channel and to your guild. Players browse them
in the lobby and ask for an invite. Adverts include the dealer's zone, so you can play in person
(a tavern in Booty Bay, say).

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
2. **Roll.** Every seated player's add-on does `/roll 1-1000000`. The **Blizzard server** makes
   the roll and shows it to the whole group, so nobody can fake it or choose it. Rolls in any other
   range don't count.
3. **Shuffle.** `deck = FisherYates(SHA-256(table | hand | secret | every roll))`. The dealer
   sealed before the rolls existed, so it can't steer the deck. Players don't know the secret, so
   they can't predict it. The shuffle draws from a SHA-256 stream with rejection sampling, so there's
   no modulo bias.
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
- `tests/sim.py`: five independent simulated clients play 60 hands only through routed addon
  messages and server rolls. Checks that every client agrees on every stack, chips are conserved,
  every hand passes audit, and AFK timeouts and leaving work. It also runs two cheating dealers
  (a fake roll and a swapped board card) and checks both get caught.
- `tests/ui_smoke.py`: loads every file in TOC order against a mocked frame API and plays a hand
  through the UI.

Textures are generated by `tools/make_textures.py` (Pillow).

## License

MIT
