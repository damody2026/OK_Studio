-- pre-commit: when the commit touches the street rules (Tools/ok-rules) or the street data they read
-- (Content/IndependentResources/StreetSocialData: anchors, activities, catalog), run the ok-rules tests and refuse the
-- commit if they fail. Data-driven anchors are only checked there (anchors::every_activity_anchor_and_station_is_found),
-- so a data commit that skips them can break the game unseen (d1686360a, Docs/STREET_ERRORS.md 2026-11-18).
--
--   Tools\lua\lua.exe Tools\check_rules_tests.lua            (what the hook runs: staged files)
--   OK_SKIP_RULES_TESTS=1 git commit ...                     (only when the tests cannot run, say why in the message)

local function lines(cmd)
  local p = assert(io.popen(cmd, "r")); local t = {}
  for l in p:lines() do t[#t + 1] = l end
  p:close(); return t
end

if os.getenv("OK_SKIP_RULES_TESTS") == "1" then
  io.stderr:write("check_rules_tests: skipped (OK_SKIP_RULES_TESTS=1)\n"); os.exit(0)
end

local hit
for _, f in ipairs(lines("git diff --cached --name-only")) do
  if f:find("^Tools/ok%-rules/") or f:find("^Content/IndependentResources/StreetSocialData/") then hit = f; break end
end
if not hit then os.exit(0) end

io.stderr:write("check_rules_tests: ", hit, " is staged, running the ok-rules tests\n")
local ok = os.execute('cargo test --release --lib -j 8 --manifest-path Tools/ok-rules/Cargo.toml -q')
if not ok then
  io.stderr:write("check_rules_tests: ok-rules tests failed, commit refused\n"); os.exit(1)
end
os.exit(0)
