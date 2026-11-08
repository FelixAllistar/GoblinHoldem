"""Run the add-on's Lua tests outside the game with LuaJIT (pip install lupa).

    python tests/run.py
"""
import os
import sys

from lupa import luajit21 as lj

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = ["Util", "SHA256", "Cards", "Eval", "Engine", "Fair", "Comm", "Ledger", "Table", "Lobby"]


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def new_runtime(name="Tester"):
    """A fresh Lua state with the core modules loaded into a shared `ns`, like the game does."""
    L = lj.LuaRuntime(unpack_returned_tuples=True)
    L.execute(read("tests/wowstub.lua"))
    ns = L.eval("{}")
    L.globals().GH_PLAYER = name
    L.execute("unpack = unpack or table.unpack")
    for mod in CORE:
        chunk = L.eval("function(src, name) return assert(loadstring(src, '@' .. name)) end")(
            read(f"Core/{mod}.lua"), f"Core/{mod}.lua")
        chunk("GoblinHoldem", ns)
    L.eval("function(ns) GH_NS = ns; if ns.InitTest then ns.InitTest() end end")(ns)
    return L, ns


def run_lua_test(path, *args):
    L, ns = new_runtime()
    chunk = L.eval("function(src, name) return assert(loadstring(src, '@' .. name)) end")(read(path), path)
    return chunk(ns, *args)


def main():
    failures = 0
    failures += run_lua_test("tests/test_core.lua")
    from sim import run_simulation
    failures += run_simulation(new_runtime)
    import subprocess
    failures += subprocess.call([sys.executable, os.path.join(ROOT, "tests", "ui_smoke.py")], stdout=subprocess.DEVNULL)
    print("ALL PASSED" if failures == 0 else f"{failures} FAILURE(S)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    main()
