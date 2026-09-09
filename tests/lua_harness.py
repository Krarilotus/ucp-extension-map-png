"""Loads the module's pure-Lua files into a Lua 5.4 runtime.

The framework runs Lua 5.4, so the tests do too. Files that touch the game or
the FFI are not loadable here; only the pure-logic modules under mappng/map/
are exercised.
"""

import pathlib

from lupa.lua54 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent


def runtime():
    """A Lua 5.4 runtime with `require` pointed at the repository root."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    root = ROOT.as_posix()
    lua.execute(
        'package.path = "{root}/?.lua;{root}/?/init.lua;" .. package.path'.format(root=root)
    )
    return lua


def load(lua, module):
    """require() a module by dotted path, e.g. "mappng.map.diamond".

    Lua 5.4's require returns (module, loaderdata); the extra parentheses
    truncate that to one value so `unpack_returned_tuples` does not hand back a
    Python tuple.
    """
    return lua.eval('(function() local m = require("%s") return m end)()' % module)
