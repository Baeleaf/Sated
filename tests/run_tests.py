"""Sated verification harness.

Runs the addon's Lua files under a real Lua 5.1 runtime (lupa) against
tests/wow_stubs.lua, executing each test in tests/tests.lua in a fresh
environment. Also performs static checks on the TOC and deploy script.

Usage: python tests/run_tests.py
"""
import os
import sys

from lupa import lua51

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON_FILES = ["config.lua", "core.lua", "announce.lua"]


def read(path):
    with open(os.path.join(BASE, path), encoding="utf-8") as f:
        return f.read()


def new_env():
    """Fresh Lua runtime with stubs + addon loaded and ADDON_LOADED fired."""
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(read(os.path.join("tests", "wow_stubs.lua")))
    loader = lua.eval(
        "function(src, name)\n"
        "  local chunk = assert(loadstring(src, name))\n"
        "  chunk('Sated', SATED_SHARED)\n"
        "end"
    )
    for fname in ADDON_FILES:
        loader(read(fname), "@" + fname)
    lua.globals().FireEvent("ADDON_LOADED", "Sated")
    return lua


def static_checks():
    """Non-Lua sanity checks: TOC contents, file list, deploy script."""
    failures = []
    toc = read("Sated.toc")
    if "## Interface: 120100, 120005, 120007" not in toc:
        failures.append("TOC interface line does not match recon (BigWigs)")
    if "## SavedVariables: SatedDB" not in toc:
        failures.append("TOC missing SavedVariables: SatedDB")
    toc_files = [l.strip() for l in toc.splitlines()
                 if l.strip() and not l.startswith("##")]
    if toc_files != ADDON_FILES:
        failures.append(f"TOC load order {toc_files} != expected {ADDON_FILES}")
    for fname in ADDON_FILES:
        if not os.path.exists(os.path.join(BASE, fname)):
            failures.append(f"missing file listed in TOC: {fname}")
    deploy = read("deploy.cmd")
    for fname in ["Sated.toc"] + ADDON_FILES:
        if fname not in deploy:
            failures.append(f"deploy.cmd does not copy {fname}")
    return failures


def syntax_checks():
    """Every Lua file (addon + stubs) must parse under Lua 5.1."""
    failures = []
    lua = lua51.LuaRuntime()
    check = lua.eval(
        "function(src, name)\n"
        "  local chunk, err = loadstring(src, name)\n"
        "  if chunk then return true, nil else return false, err end\n"
        "end"
    )
    for fname in ADDON_FILES + [os.path.join("tests", "wow_stubs.lua"),
                                os.path.join("tests", "tests.lua")]:
        ok, err = check(read(fname), "@" + fname)
        if not ok:
            failures.append(f"Lua 5.1 syntax error: {err}")
    return failures


def run_lua_tests():
    tests_src = read(os.path.join("tests", "tests.lua"))
    # First pass: collect test names.
    lua = new_env()
    lua.execute(tests_src)
    count = lua.eval("#TESTS")
    names = [lua.eval(f"TESTS[{i}].name") for i in range(1, count + 1)]

    results = []
    for i, name in enumerate(names, start=1):
        lua = new_env()
        lua.execute(tests_src)
        ok, err = lua.eval(
            f"(function() local ok, err = pcall(TESTS[{i}].fn) "
            f"return ok, err end)()"
        )
        results.append((name, bool(ok), None if ok else str(err)))
    return results


def main():
    failures = 0

    print("== static checks ==")
    for msg in static_checks():
        print(f"  FAIL {msg}")
        failures += 1
    print("  ok" if failures == 0 else f"  ({failures} failed)")

    print("== syntax checks (Lua 5.1) ==")
    syn = syntax_checks()
    for msg in syn:
        print(f"  FAIL {msg}")
    failures += len(syn)
    if not syn:
        print("  ok")

    print("== behavioral tests ==")
    results = run_lua_tests()
    for name, ok, err in results:
        if ok:
            print(f"  PASS {name}")
        else:
            print(f"  FAIL {name}: {err}")
            failures += 1

    total = len(results)
    passed = sum(1 for _, ok, _ in results if ok)
    print(f"\n{passed}/{total} behavioral tests passed, "
          f"{failures} total failures")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
