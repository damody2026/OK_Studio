-- Installs this checkout's git hooks: pre-commit runs Tools/check_no_cards.lua (no character cards in commits) and
-- Tools/check_rules_tests.lua (ok-rules tests when the rules or street data are staged).
--
--   Tools\lua\lua.exe Tools\install_git_hooks.lua

local p = assert(io.popen("git rev-parse --git-path hooks", "r"))
local hooks = p:read("l"); p:close()
local f = assert(io.open(hooks .. "/pre-commit", "wb"))
f:write('#!/bin/sh\nL="$(git rev-parse --show-toplevel)/Tools/lua/lua.exe"\n"$L" Tools/check_no_cards.lua || exit 1\nexec "$L" Tools/check_rules_tests.lua\n')
f:close()
io.write("installed ", hooks, "/pre-commit\n")
