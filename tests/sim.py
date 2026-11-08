"""Multi-client network simulation: several independent Lua states (one per player) talk only
through addon messages and server /roll results routed here, like a real party would."""
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
PREFIX = "GHoldem"


class Client:
    def __init__(self, new_runtime, name, seed):
        self.name = name
        self.L, self.ns = new_runtime(name)
        with open(os.path.join(HERE, "sim_client.lua"), encoding="utf-8") as f:
            src = f.read()
        self.L.eval("function(src) return assert(loadstring(src, '@sim_client.lua')) end")(src)(self.ns, seed)
        self.g = self.L.globals()

    def run(self, code):
        return self.L.execute(code)


class World:
    def __init__(self, new_runtime, names, seed=1):
        self.rng = random.Random(seed)
        self.clients = {n: Client(new_runtime, n, seed * 100 + i) for i, n in enumerate(names)}
        self.time = 0.0

    def step(self, dt=0.25):
        self.time += dt
        for c in self.clients.values():
            c.g.GH_TIME = self.time
            c.g.GH_RunTimers()
        moved = True
        while moved:
            moved = False
            for c in self.clients.values():
                sent = c.g.GH_SENT
                n = len(sent)
                if n:
                    moved = True
                    msgs = [sent[i + 1] for i in range(n)]
                    c.run("GH_SENT = {}")
                    for m in msgs:
                        self.route(c.name, m)
                rolls = c.g.GH_ROLLS
                if len(rolls):
                    moved = True
                    reqs = [rolls[i + 1] for i in range(len(rolls))]
                    c.run("GH_ROLLS = {}")
                    for r in reqs:
                        v = self.rng.randint(int(r.lo), int(r.hi))
                        text = f"{c.name} rolls {v} ({int(r.lo)}-{int(r.hi)})"
                        for other in self.clients.values():
                            t = other.g.GH_T()
                            if t is not None:
                                t.OnSystem(t, text)

    def route(self, sender, m):
        if m.dist in ("PARTY", "RAID"):
            for c in self.clients.values():
                if c.name != sender:
                    c.ns.Comm.OnAddonMessage(m.prefix, m.text, m.dist, sender + "-Realm")
        elif m.dist == "WHISPER":
            c = self.clients.get(m.target)
            if c:
                c.ns.Comm.OnAddonMessage(m.prefix, m.text, "WHISPER", sender + "-Realm")

    def settle(self, seconds=3):
        for _ in range(int(seconds / 0.25)):
            self.step()

    def states(self):
        return {n: c.g.GH_State() for n, c in self.clients.items()}


def check(cond, msg, fails):
    if not cond:
        print("FAIL:", msg)
        fails.append(msg)


def play(world, hands, fails, styles=None, max_steps=200000):
    styles = styles or {}
    dealer = next(iter(world.clients.values()))
    start = dealer.g.GH_T().handNo
    steps = 0
    while dealer.g.GH_T().handNo < start + hands and steps < max_steps:
        world.step()
        for c in world.clients.values():
            c.g.GH_Bot(styles.get(c.name, "normal"))
        steps += 1
    world.settle(10)
    return steps


def run_simulation(new_runtime):
    fails = []
    names = ["Grizzle", "Thrall", "Jaina", "Vol", "Rexxar"]
    w = World(new_runtime, names, seed=7)
    host = w.clients["Grizzle"]
    host.run("""GH_Host({ name = "Booty Bay Back Room", mode = "iou", sb = 500, bb = 1000,
        minBuy = 20000, maxBuy = 200000, maxSeats = 9, dealerSeated = true, dealerBuyIn = 100000,
        actTimeout = 20, handPause = 2, boardDelay = 0.5 })""")
    w.settle(2)
    for i, n in enumerate(names[1:], start=2):
        check(w.clients[n].g.GH_T() is not None, f"{n} sees the table", fails)
        w.clients[n].g.GH_Sit(i, 100000)
    w.settle(5)
    st = w.states()
    print("seated:", st["Grizzle"])
    check(len(set(st.values())) == 1, f"all clients agree after seating: {st}", fails)

    steps = play(w, 60, fails)
    st = w.states()
    print(f"after 60 hands ({steps} steps):", st["Grizzle"])
    check(len(set(st.values())) == 1, "all clients agree on stacks:\n  " + "\n  ".join(f"{k}: {v}" for k, v in st.items()), fails)
    for n, c in w.clients.items():
        stacks, buy = c.g.GH_Total()
        check(stacks == buy, f"{n}: chips conserved ({stacks} vs {buy})", fails)
        ver, failed = c.g.GH_Verified()
        check(failed == 0 and ver >= 55, f"{n}: audits verified={ver} failed={failed}", fails)
        alerts = [c.g.GH_ALERTS[i + 1] for i in range(len(c.g.GH_ALERTS))]
        bad = [a for a in alerts if not a.startswith("info")]
        check(not bad, f"{n}: unexpected alerts {bad[:3]}", fails)
    ntr, netsum = host.g.GH_Settle()
    check(netsum == 0, f"ledger nets sum to zero ({netsum})", fails)

    # AFK player gets timed out and the game continues
    play(w, 3, fails, styles={"Vol": "afk"})
    st = w.states()
    check(len(set(st.values())) == 1, "agree after AFK timeouts", fails)

    # A player leaves; they are cashed out and the rest continue
    w.clients["Rexxar"].run("GH_T():Leave()")
    play(w, 3, fails)
    st = w.states()
    check("Rexxar" not in st["Grizzle"], "Rexxar removed after leaving", fails)
    check(len(set(v for k, v in st.items())) == 1, f"agree after leave: {st}", fails)
    _, netsum = host.g.GH_Settle()
    check(netsum == 0, "nets still zero after cash-out", fails)

    # Cheating dealer #1: lies about a server roll -> players flag it
    w2 = World(new_runtime, ["Crook", "Alice", "Bob"], seed=11)
    w2.clients["Crook"].run("""GH_Host({ name = "Shady", mode = "fun", sb = 5, bb = 10, minBuy = 100,
        maxBuy = 5000, maxSeats = 6, dealerSeated = false, actTimeout = 20, handPause = 2, boardDelay = 0.5 })""")
    w2.settle(2)
    w2.clients["Alice"].g.GH_Sit(1, 1000)
    w2.clients["Bob"].g.GH_Sit(2, 1000)
    w2.settle(3)
    w2.clients["Crook"].run("GH_CheatRolls()")
    play(w2, 1, fails)
    alerts = [w2.clients["Alice"].g.GH_ALERTS[i + 1] for i in range(len(w2.clients["Alice"].g.GH_ALERTS))]
    check(any("server rolled" in a for a in alerts), f"fake roll detected: {alerts}", fails)

    # Cheating dealer #2: deals a board card that isn't from the sealed deck -> audit fails
    w3 = World(new_runtime, ["Crook", "Alice", "Bob"], seed=12)
    w3.clients["Crook"].run("""GH_Host({ name = "Shady", mode = "fun", sb = 5, bb = 10, minBuy = 100,
        maxBuy = 5000, maxSeats = 6, dealerSeated = false, actTimeout = 20, handPause = 2, boardDelay = 0.5 })""")
    w3.settle(2)
    w3.clients["Alice"].g.GH_Sit(1, 1000)
    w3.clients["Bob"].g.GH_Sit(2, 1000)
    w3.settle(3)
    w3.clients["Crook"].run("GH_CheatBoard()")
    play(w3, 3, fails, styles={"Alice": "normal", "Bob": "normal"})
    ver, failed = w3.clients["Bob"].g.GH_Verified()
    alerts = [w3.clients["Bob"].g.GH_ALERTS[i + 1] for i in range(len(w3.clients["Bob"].g.GH_ALERTS))]
    check(failed >= 1 and any("board card" in a for a in alerts), f"swapped board detected (failed={failed}) {alerts[:2]}", fails)

    print(f"simulation: {len(fails)} failure(s)")
    return len(fails)
