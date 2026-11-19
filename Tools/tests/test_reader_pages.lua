-- Tools\lua\lua.exe Tools\tests\test_reader_pages.lua   (from the project root)
local ok = require "ok"
package.path = "Tools/?.lua;" .. package.path
local pages = require "reader_pages"

local T = ok.test.suite("reader pages")

local function read(file) local f = assert(io.open(file, "rb")); local s = f:read("a"); f:close(); return s end
local groups = pages.shape_groups(read("Plugins/KKCard/Source/KKCard/Private/KKShapeRows.cpp"))
local keys = pages.static_keys("", read("Source/OpenKoikatsu/OKBoneControls.h"))
local checked_in = ok.json.decode((read("Config/ReaderEditor/pages.json"):gsub("^\239\187\191", "")))

local function doc(sub) return { version = 1, categories = { { name = "臉", subs = { sub } } } } end

T:case("shape_groups_follow_the_separators", function(t)
  t:eq(#groups.face, 8)
  t:eq(#groups.body, 6)
  t:eq(groups.face[1], { "shape.face.0", "shape.face.1", "shape.face.2", "shape.face.3", "shape.face.4", "shape.face.5" })
  -- 軀幹 starts with the neck rows (card indices 2 and 3), shown after the bust group.
  t:eq(groups.body[3][1], "shape.body.2")
end)

T:case("the_checked_in_file_has_every_key_and_matches_itself", function(t)
  local lines, unknown = pages.compare(checked_in, checked_in, groups, keys)
  t:eq(#lines, 0); t:eq(#unknown, 0)
end)

T:case("a_shape_group_swapped_for_its_keys_shows_the_same_rows", function(t)
  local before = doc({ name = "臉型", sources = { { shape = "face", group = 0 } }, bone_category = "原遊戲參數" })
  local items = {}
  for i = 0, 5 do items[#items + 1] = { key = "shape.face." .. i } end
  local after = doc({ name = "臉型", items = items, bone_category = "原遊戲參數" })
  local lines, unknown = pages.compare(before, after, groups, keys)
  t:eq(lines, {}); t:eq(unknown, {})
end)

T:case("a_missing_or_reordered_key_is_a_change", function(t)
  local before = doc({ name = "臉型", sources = { { shape = "face", group = 0 } } })
  local after = doc({ name = "臉型", items = { { key = "shape.face.1" }, { key = "shape.face.0" } } })
  local lines = pages.compare(before, after, groups, keys)
  t:eq(#lines, 1); t:contains(lines[1], "changed  臉›臉型")
end)

-- 胸部: its shape keys, then the two bust physics rows, in one ordered list.
local function bust_items(physics_first)
  local items = {}
  for _, k in ipairs(groups.body[2]) do items[#items + 1] = { key = k } end
  local physics = { { key = "physics.bustSoftness" }, { key = "physics.bustWeight" } }
  if physics_first then items = { physics[1], physics[2], table.unpack(items) }
  else items[#items + 1] = physics[1]; items[#items + 1] = physics[2] end
  return items
end
local bust_before = doc({ name = "胸部", sources = { { shape = "body", group = 1 }, { rows = "bust" } } })

T:case("the_bust_page_as_ordered_keys_shows_the_same_rows", function(t)
  local lines, unknown = pages.compare(bust_before, doc({ name = "胸部", items = bust_items(false) }), groups, keys)
  t:eq(lines, {}); t:eq(unknown, {})
end)

T:case("the_list_order_is_the_page_order_nothing_goes_first", function(t)
  local lines = pages.compare(bust_before, doc({ name = "胸部", items = bust_items(true) }), groups, keys)
  t:eq(#lines, 1); t:contains(lines[1], "changed  臉›胸部")
end)

T:case("an_item_can_be_a_source_and_mixes_with_keys", function(t)
  local before = doc({ name = "眼部縮放2", sources = { { widget = "bone_axes" }, { rows = "bones" } } })
  local after = doc({ name = "眼部縮放2", items = { { widget = "bone_axes" }, { rows = "bones" } } })
  local lines, unknown = pages.compare(before, after, groups, keys)
  t:eq(lines, {}); t:eq(unknown, {})
  local mixed = doc({ name = "眼部縮放2", items = { { key = "shape.face.0" }, { widget = "bone_axes" } } })
  local _, err = pages.page_rows(mixed.categories[1].subs[1], groups)
  t:eq(err, nil)
end)

T:case("a_page_with_both_sources_and_items_is_refused", function(t)
  local after = doc({ name = "臉型", sources = { { shape = "face", group = 0 } }, items = { { key = "shape.face.0" } } })
  local lines = pages.compare(after, after, groups, keys)
  t:truthy(#lines >= 1); t:contains(lines[1], "invalid  臉›臉型")
end)

T:case("a_typo_in_a_key_is_found_before_the_build", function(t)
  local after = doc({ name = "臉型", items = { { key = "shape.face.0" }, { key = "shape.fase.1" } } })
  local _, unknown = pages.compare(after, after, groups, keys)
  t:eq(#unknown, 1); t:contains(unknown[1], "shape.fase.1")
end)

T:case("bone_keys_come_from_the_bone_table", function(t)
  t:truthy(keys["bone.cf_J_Eye_tz.scale.uniform"])
  t:truthy(keys["bone.cf_J_FaceBase.length"])
  t:falsy(keys["bone.cf_J_Eye_tz.scale.w"])
end)

T:case("run_time_keys_are_left_to_the_in_game_audit", function(t)
  local after = doc({ name = "懷孕", items = { { key = "pregnancy.inflation" } } })
  local _, unknown, runtime = pages.compare(after, after, groups, keys)
  t:eq(#unknown, 0); t:eq(#runtime, 1)
end)

T:case("kkex_column_says_missing_support_when_the_producer_has_no_field_never_0", function(t)
  local c = pages.audit_cells({ card = true, ui = 3, data = 0, range = 2, kkex = "absent" })
  t:contains(c.kkex, "缺支援")
  t:falsy(c.kkex:match("^0"), "a missing producer field is not 'none unknown'")
  t:eq(pages.audit_cells({ card = true, ui = 0, data = 0, range = 0, kkex = {} }).kkex, "0")
  t:eq(pages.audit_cells({ card = true, ui = 0, data = 0, range = 0, kkex = { "KSOX", "com.x" } }).kkex, "2：KSOX、com.x")
  t:contains(pages.audit_cells({ card = true, ui = 0, data = 0, range = 0, kkex = "unread" }).kkex, "未讀")
  t:eq(pages.audit_cells({ card = true, ui = 0, data = 0, range = 0, kkex = "busy" }).kkex, "讀取中")
end)

-- The producer (F tree plugins.rs) keeps ABMX, the sideloader resolve list and our provenance block out of
-- PLUGIN_SECTIONS on purpose: they come back in unknown_plugin_sections on every card and are not a support gap.
T:case("sections_left_out_on_purpose_are_not_counted_as_unknown", function(t)
  local c = pages.audit_cells({ card = true, ui = 0, data = 0, range = 0,
    kkex = { "KKABMX.Core", "com.bepis.sideloader.universalautoresolver", "KSOXv2", "OpenKoikatsu.AppearanceSource" } })
  t:eq(c.kkex, "1：KSOXv2；刻意不收 3（KKABMX.Core、com.bepis.sideloader.universalautoresolver、OpenKoikatsu.AppearanceSource）")
  local only = pages.audit_cells({ card = true, ui = 0, data = 0, range = 0, kkex = { "kkabmplugin.ABMData" } })
  t:eq(only.kkex, "0；刻意不收 1（kkabmplugin.ABMData）")
end)

-- The audit and reader_call state read the same members (bad2861df), so each status maps to one cell.
T:case("each_mcp_status_gives_one_cell", function(t)
  local function cell(k) return pages.audit_cells({ card = true, ui = 0, data = 0, range = 0, kkex = k }).kkex end
  t:eq(cell("no_card"), "沒有卡")
  t:contains(cell("not_read"), "未讀")
  t:contains(cell("unsupported"), "缺支援")
  t:eq(cell({}), "0")
end)

T:case("without_a_card_every_column_says_so", function(t)
  local c = pages.audit_cells({ card = false, ui = 4, data = 0, unjudged = 1, range = 2, kkex = { "KSOX" } })
  t:eq(c.kkex, "沒有卡")	-- whatever a previous card left behind
  t:contains(c.ui, "沒有卡"); t:contains(c.data, "沒有卡"); t:contains(c.range, "沒有卡")
  t:contains(c.data, "1 個未判")
  -- With a card the numbers stand alone, so the two are never compared as if alike.
  t:eq(pages.audit_cells({ card = true, ui = 4, data = 0, range = 2, kkex = {} }).ui, "4")
end)

-- The user's rule (2026-11-19): the new reader UI is the only one that appears. A page file that does not read
-- builds the hand-written pages with the reason in red; nothing on that path opens the old UMG reader, which
-- shows only when -LegacyReader is given (OKGalleryWidget.cpp). Checked in the source, as the game is not run here.
T:case("a_bad_page_file_never_brings_back_the_old_ui", function(t)
  local screen = read("Source/OpenKoikatsu/OKReaderScreen.cpp")
  local gallery = read("Source/OpenKoikatsu/OKGalleryWidget.cpp")
  local loader = screen:match("void UOKReaderScreen::BuildCategories%(%)(.-)\nvoid UOKReaderScreen::")
  t:truthy(loader, "BuildCategories found")
  t:contains(loader, "NEVER fall back to the old UMG reader")
  loader = loader:gsub("//[^\n]*", "")	-- the code, not what its comments say about it
  t:contains(loader, "暫用內建頁面")
  t:falsy(loader:find("LegacyReader", 1, true), "the page loader must not decide on the old UI")
  t:falsy(loader:find("return nullptr", 1, true), "the page loader must not give up the screen")
  -- The old reader is reached by -LegacyReader alone (or a failed screen open, which is not about the page file).
  t:contains(gallery, 'if(!FParse::Param(FCommandLine::Get(),TEXT("LegacyReader")))if((ReaderScreen=UOKReaderScreen::Open(this))!=nullptr)')
end)

T:run()
