-- Writes mcp.json beside this checkout or package (WriteMcpConfig.cmd): the two MCP servers an AI client (Claude Code,
-- Claude Desktop, Cursor...) uses to drive the running game, with this folder's absolute paths in them (a client starts
-- the servers from its own working folder, so relative paths do not work).
--   ok-game:               Tools/ok-game-mcp/target/release/ok-game-mcp.exe (OK_ROOT = this folder): the card reader
--                          (reader_call: load a card, parameters, set, screenshot, views, measure), OK Studio
--                          (studio_*), any screen (ui_*).
--   openkoikatsu-character: Tools/character_mcp/bin/ok-character-mcp.exe (--mailbox Saved/CharacterMCP): the character
--                          editor's 31 tools, among them reference images and body fitting to a 2D picture
--                          (Docs/CHARACTER_EDITOR_MCP_USAGE.md).
-- Both talk to a game started from this folder (CardReaderDevelopment.cmd or OKStudio.cmd); neither opens a network port.
--   Tools\lua\lua.exe Tools\write_mcp_config.lua [--out FILE]
local ok = require "ok"
local json, path = ok.json, ok.path

local function main()
  local p = ok.args.parser("Write mcp.json for this folder's MCP servers")
  p:opt("--out", { default = "" })
  local a = p:parse(arg)
  local root = path.abs(ok.root)
  local game = path.join(root, "Tools/ok-game-mcp/target/release/ok-game-mcp.exe")
  local character = path.join(root, "Tools/character_mcp/bin/ok-character-mcp.exe")
  for _, exe in ipairs({ game, character }) do
    if not path.is_file(exe) then error("Missing " .. exe, 0) end
  end
  local out = a.out ~= "" and path.abs(a.out) or path.join(root, "mcp.json")
  local config = json.object({ { "mcpServers", json.object({
    { "ok-game", json.object({ { "command", game }, { "args", json.array({}) }, { "env", json.object({ { "OK_ROOT", root } }) } }) },
    { "openkoikatsu-character", json.object({ { "command", character },
      { "args", json.array({ "--mailbox", path.join(root, "Saved/CharacterMCP"), "--timeout", "1800" }) } }) },
  }) } })
  path.write_text(out, json.encode(config, { indent = 2 }) .. "\n")
  io.write("Wrote ", out, "\n",
    "Copy its mcpServers into your AI client's MCP settings (Claude Code: put mcp.json's content in .mcp.json of your\n",
    "project, or run `claude mcp add-json`), start CardReaderDevelopment.cmd and load a card, then ask the AI to match a\n",
    "picture: Docs/CHARACTER_EDITOR_MCP_USAGE.md.\n")
end

ok.main(main)
