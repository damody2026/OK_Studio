-- Clicks OK Studio's character-page buttons through the control channel's "click" op (the button's own handler runs)
-- and reads the result back ("bones" op), one check per line. Needs a running studio.
-- Tools/lua/lua.exe Tools/check_ok_studio_buttons.lua [--port N] [--card Content/CharacterCards/CrowdAPNG/C000.png]
package.path = (arg[0]:match("^(.*)[/\\]") or ".") .. "/?.lua;" .. package.path
local json = require "ok.json"
local port, card = tostring(require("ok_instance").ports().studio_control), "Content/CharacterCards/CrowdAPNG/C000.png"
for i = 1, #arg, 2 do
  if arg[i] == "--port" then port = arg[i + 1] elseif arg[i] == "--card" then card = arg[i + 1] else error("unknown option " .. arg[i]) end
end
local tmp = os.getenv("TEMP") .. "\\ok_studio_buttons.json"

local function call(op, body)
  local f = assert(io.open(tmp, "wb")); f:write(json.encode(body or {})); f:close()
  local p = io.popen(('curl -s -m 120 -X POST http://127.0.0.1:%s/studio/%s --data-binary "@%s"'):format(port, op, tmp))
  local out = p:read("a"); p:close()
  local ok, value = pcall(json.decode, out)
  return ok and value or { ok = false, error = out }
end
local function wait(frames) local t = os.clock() + frames / 60 while os.clock() < t do end end

local passed, failed = 0, 0
local function check(cond, what)
  if cond then passed = passed + 1 else failed = failed + 1 end
  print((cond and "PASS " or "FAIL ") .. what)
end

local function character()
  for _, o in ipairs(call("state").objects or {}) do if o.kind == "character" then return o.id end end
end
local id = character()
if not id then
  call("cmd", { id = "add.character", arg = card })
  for _ = 1, 120 do id = character() if id then break end wait(30) end
end
assert(id, "no character in the scene")
wait(120)
call("select", { ids = { id } })
local function bones() return call("bones", { id = id }) end
local function click(text, index) local r = call("click", { text = text, index = index or 0 }); wait(20); return r end

-- U17: one-click clothes (state page).
call("cmd", { id = "page.state" }); wait(20)
local function all(states, v) if #states ~= 9 then return false end for _, s in ipairs(states) do if s ~= v then return false end end return true end
check(click("全裸").ok and all(bones().clothes_states, 3), "全裸 → every part off (3)")
check(click("半脫").ok and all(bones().clothes_states, 1), "半脫 → every part half (1)")
check(click("全穿").ok and all(bones().clothes_states, 0), "全穿 → every part on (0)")

-- U16: look modes and buttons (bones page, look tab).
call("cmd", { id = "page.bones" }); call("cmd", { id = "bones.page", arg = "2" }); wait(20)
check(click("正面").ok and bones().eyes_look == 4, "eyes 正面 → Front")
check(click("背離").ok and bones().eyes_look == 5, "eyes 背離 → Away")
-- Away from the camera first, so taking the camera position always moves it (also on a second run).
call("pose", { id = id, look = { point = { 0, 300, 140 } } }); wait(10)
local before = bones().look_point
check(click("取鏡頭位置").ok and bones().eyes_look == 2, "取鏡頭位置 → look point mode")
local after = bones().look_point
check(before and after and (before[1] ~= after[1] or before[2] ~= after[2] or before[3] ~= after[3]), "取鏡頭位置 moves the look point to the camera")
check(click("恢復看鏡頭").ok and bones().eyes_look == 1, "恢復看鏡頭 → camera")
-- Neck tab: follow strength through the pose op (a slider), and the neck's own front mode.
call("cmd", { id = "bones.page", arg = "3" }); wait(20)
check(click("正面").ok and bones().neck_look == 4, "neck 正面 → Front")
call("pose", { id = id, look = { neck_follow = 0.25 } }); wait(10)
check(math.abs((bones().neck_follow or 1) - 0.25) < 1e-3, "neck follow strength 0.25 kept")
call("pose", { id = id, look = { neck = "animation", neck_follow = 1 } })

-- U16: expression steppers and eye opening (expression tab): ▶ on the eyes row (the second ▶ of the page).
call("cmd", { id = "bones.page", arg = "4" }); wait(20)
local p0 = bones().face_eyes_pattern
-- From 照動畫 (-1) two steps reach pattern 1, which the animation's own pattern (often 0) is not.
check(click("▶", 1).ok and click("▶", 1).ok, "eyes ▶ clicked twice")
wait(30)
local p1 = bones().face_eyes_pattern
check(p1 == 1, ("eyes ▶▶ shows eye pattern 1 (%s → %s)"):format(tostring(p0), tostring(p1)))
check(click("◀", 1).ok and click("◀", 1).ok, "eyes ◀ clicked twice")
call("pose", { id = id, expression = { eyes_open = 0.3 } }); wait(30)
check(math.abs((bones().face_eyes_open or 0) - 0.3) < 0.02, "eyes_open 0.3 reaches the face")
call("pose", { id = id, expression = { eyes_open = -1 } }); wait(30)
check((bones().face_eyes_open or 0) > 0.5, "eyes_open -1 gives the character's own opening back")

-- U16: hands (hand tab): ▶ on the left hand, then 復位.
call("cmd", { id = "bones.page", arg = "5" }); wait(20)
check(click("▶", 0).ok and bones().hand_left == 0, "left hand ▶ from 照動畫 → pattern 0")
check(click("▶", 0).ok and bones().hand_left == 1, "left hand ▶ again → pattern 1")
check(click("復位").ok and bones().hand_left == -1 and bones().hand_right == -1, "hand 復位 → both -1")

-- U18: motion browser tabs and search (anim page): the count label changes with the tab.
call("cmd", { id = "page.anim" }); wait(20)
check(click("男").ok, "anim tab 男 clicked")
check(click("共用").ok, "anim tab 共用 clicked")
check(click("全部").ok, "anim tab 全部 clicked")

-- Pose page: save a pose file (the page's own button), back to the T-pose, then step to the file.
local poses = "UserData/Studio/pose"
local function pose_files() local t = {} local p = io.popen('dir /b "' .. poses:gsub("/", "\\") .. '\\*.dat" 2>nul') for l in p:lines() do t[l] = true end p:close() return t end
local had = pose_files()
call("pose", { id = id, fk = { { bone = "cf_j_neck", euler = { 20, 0, 0 } } } }); wait(20)
call("cmd", { id = "page.bones" }); call("cmd", { id = "bones.page", arg = "6" }); wait(20)
local function fk_set() for _, b in ipairs(bones().fk or {}) do if b.set then return true end end return false end
check(click("存成 KK 姿勢").ok, "存成 KK 姿勢 clicked")
check(click("復位 T-pose").ok and not fk_set(), "復位 T-pose clears FK")
wait(20)
local r = click("▶", 0)
wait(30)
check(r.ok and fk_set(), "pose ▶ loads the saved pose file (" .. tostring(r.error or r.clicked) .. ")")
check(click("復位 T-pose").ok and not fk_set(), "復位 T-pose clears it again")
for name in pairs(pose_files()) do if not had[name] then os.remove(poses .. "/" .. name) end end

-- U19: the tree's tools (群組／解散／鎖定／獨顯／錯開複製) on the character.
local function objects() local t = {} for _, o in ipairs(call("state").objects or {}) do t[o.id] = o end return t end
-- Opens a window by its command unless it is open already (the layout reopens what was open last time).
local function open_window(cmd, window)
  for _, w in ipairs((call("state").ui or {}).windows or {}) do if w == window then return end end
  call("cmd", { id = cmd }); wait(30)
end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
call("select", { ids = { id } }); wait(10)
local parent0 = objects()[id].parent
check(click("群組").ok, "群組 clicked")
local grouped = objects()
local folder = grouped[id] and grouped[grouped[id].parent]
check(folder and folder.kind == "folder", "群組 puts the character under a new folder")
check(click("解散").ok, "解散 clicked")
local ungrouped = objects()
check(ungrouped[id].parent == parent0 and not (folder and ungrouped[folder.id]), "解散 removes the folder, the character is back")
call("select", { ids = { id } }); wait(10)
check(click("鎖定").ok and objects()[id].locked == true, "鎖定 locks")
check(click("鎖定").ok and objects()[id].locked == false, "鎖定 again unlocks")
check(click("獨顯").ok, "獨顯 clicked")
local solo_ok = true
for oid, o in pairs(objects()) do if oid ~= id and o.kind ~= "light" and o.kind ~= "camera" and o.visible then solo_ok = false end end
check(solo_ok, "獨顯 hides everything but the selection (lights, cameras stay)")
check(click("獨顯").ok, "獨顯 again clicked")
local before_copy = objects()
check(click("錯開複製").ok, "錯開複製 clicked")
local after_copy, copy = objects(), nil
for oid, o in pairs(after_copy) do if not before_copy[oid] and o.kind == "character" then copy = o end end
local a, b = before_copy[id].location, copy and copy.location
check(copy and a and b and math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) + math.abs(a[3] - b[3]) > 5, "錯開複製 adds a character away from the original")
if copy then call("select", { ids = { copy.id } }); call("cmd", { id = "edit.delete" }); wait(20) end
check(count(objects()) == count(before_copy), "the copy is deleted again")
call("select", { ids = { id } }); wait(10)

-- U20: FK parts really switch FK (FK tab).
call("cmd", { id = "page.bones" }); call("cmd", { id = "bones.page", arg = "0" }); wait(20)
local function fk_world(bone) for _, b in ipairs(bones().fk or {}) do if b.bone == bone then return b.world end end end
local function dist(p, q) return p and q and math.sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2 + (p[3] - q[3]) ^ 2) or 0 end
local off0 = bones().fk_parts_off or 0
check(click("頭髮", 0).ok and bones().fk_parts_off == off0 ~ 4, "FK 頭髮 toggles the hair part")
click("頭髮", 0)
local head0 = fk_world("cf_j_head")
call("pose", { id = id, fk = { { bone = "cf_j_neck", euler = { 40, 0, 0 } } } }); wait(20)
local head1 = fk_world("cf_j_head")
check(dist(head0, head1) > 1 and (bones().fk_parts_off & 8) == 0, ("posing the neck switches its part on and moves the head (%.1f cm)"):format(dist(head0, head1)))
check(click("頸", 0).ok and (bones().fk_parts_off & 8) == 8, "FK 頸 switches the neck part off")
wait(20)
check(dist(fk_world("cf_j_head"), head0) < 0.5, "neck part off: the head follows the animation again")
click("頸", 0); wait(20)
check(dist(fk_world("cf_j_head"), head1) < 0.5, "neck part on: the kept FK value shows again")
local function neck_set() for _, b in ipairs(bones().fk or {}) do if b.bone == "cf_j_neck" then return b.set end end end
check(click("頸", 2).ok and not neck_set(), "復位 頸 drops the neck's FK")

-- U20: IK parts, 全部, weights, FK←IK (IK tab).
call("cmd", { id = "bones.page", arg = "1" }); wait(20)
if (bones().ik_parts_off or 0) ~= 0 then click("全部") end
check(click("全部").ok and bones().ik_parts_off == 31, "IK 全部 switches every part off")
check(click("全部").ok and bones().ik_parts_off == 0, "IK 全部 again switches every part on")
local hand0 = fk_world("cf_j_hand_L")
check(hand0 ~= nil, "the left hand bone is in the FK list")
local function ik_hand(weight)
  local target = { hand0[1] + 25, hand0[2], hand0[3] }
  local actor = nil
  for _, e in ipairs(bones().ik or {}) do if e.effector == 5 then actor = e end end
  -- The target in character space: the hand's own character-space position plus 25 cm on X.
  local local_pos = { actor.position[1] + 25, actor.position[2], actor.position[3] }
  call("pose", { id = id, ik = { { effector = 5, position = local_pos, weight = weight } } }); wait(30)
  return dist(fk_world("cf_j_hand_L"), hand0)
end
if hand0 then
  local full = ik_hand(1)
  local none = ik_hand(0)
  check(full > 10 and none < full * 0.5, ("IK weight 1 pulls the hand (%.1f cm), weight 0 leaves it (%.1f cm)"):format(full, none))
  ik_hand(1)
  check(click("左手").ok and dist(fk_world("cf_j_hand_L"), hand0) < full * 0.5, "IK 左手 part off: the hand goes back")
  click("左手"); wait(20)
  check(click("FK←IK").ok, "FK←IK clicked")
  wait(20)
  local any_ik = false for _, e in ipairs(bones().ik or {}) do if e.enabled then any_ik = true end end
  check(not any_ik and fk_set(), "FK←IK turns the IK pose into FK and clears IK")
  check(dist(fk_world("cf_j_hand_L"), hand0) > full * 0.5, "after FK←IK the hand stays where IK put it")
end
call("cmd", { id = "bones.page", arg = "0" }); wait(20)
click("清除 FK")

-- U21: one bone's own timeline track (FK page buttons), and 清空軌道 (timeline window).
call("keys", { id = id, action = "clear" })
local function keys() return call("keys", { id = id, action = "list" }).keys or {} end
local function neck_x() for _, b in ipairs(bones().fk or {}) do if b.bone == "cf_j_neck" then return b.euler[1] end end end
call("timeline", { time = 0 }); wait(5)
call("pose", { id = id, fk = { { bone = "cf_j_neck", euler = { 0, 0, 0 } } } }); wait(10)
check(call("click", { text = "cf_j_neck", contains = true }).ok, "the neck row picked in the FK tree")
wait(20)
check(click("骨骼打 key").ok and #keys() == 1 and keys()[1].fk_bones == 1, "骨骼打 key at 0 s: a key holding only the neck")
call("timeline", { time = 2 }); wait(5)
call("pose", { id = id, fk = { { bone = "cf_j_neck", euler = { 40, 0, 0 } } } }); wait(10)
check(click("骨骼打 key").ok and #keys() == 2, "骨骼打 key at 2 s: a second key")
call("timeline", { time = 1 }); wait(20)
local mid = neck_x() or 0
check(math.abs(mid - 20) < 2, ("at 1 s the neck is half way (%.1f°)"):format(mid))
call("timeline", { time = 2 }); wait(5)
check(click("骨骼刪 key").ok and (keys()[2] or {}).fk_bones == 0, "骨骼刪 key drops the neck from the 2 s key")
call("cmd", { id = "toggle.timeline" }); wait(30)
check(click("清空").ok and #keys() == 0, "清空 removes the track")
call("cmd", { id = "toggle.timeline" }); wait(10)
click("清除 FK")

-- U22: viewport helpers (camera page check boxes), an orthographic scene camera, the system menu's recent scenes.
call("cmd", { id = "page.camera" }); wait(20)
local function state() return call("state") end
check(click("視窗格線（地面 10 m）").ok and state().grid == true, "視窗格線 on")
check(click("視窗格線（地面 10 m）").ok and state().grid == false, "視窗格線 off")
check(click("隱藏全部輔助（把手、骨點、光源範圍）").ok and state().hide_helpers == true, "隱藏全部輔助 on")
check(click("隱藏全部輔助（把手、骨點、光源範圍）").ok and state().hide_helpers == false, "隱藏全部輔助 off")
local cams0 = objects()
call("cmd", { id = "add.camera" }); wait(20)
local cam = nil
for oid, o in pairs(objects()) do if not cams0[oid] and o.kind == "camera" then cam = o end end
check(cam ~= nil, "add.camera adds a camera")
if cam then
  -- The camera page is still open (page.* toggles), the selection rebuilds it.
  call("select", { ids = { cam.id } }); wait(20)
  check(click("正交").ok and objects()[cam.id].ortho == true, "camera 正交 on")
  check(click("正交").ok and objects()[cam.id].ortho == false, "camera 正交 off")
  call("cmd", { id = "edit.delete" }); wait(20)
end
-- The root buttons toggle: open the system menu unless an earlier session left it open.
if (call("state").ui or {}).root_menu ~= 3 then call("cmd", { id = "menu.system" }); wait(20) end
check(click("最近場景").ok, "system menu 最近場景 opens the window")
call("cmd", { id = "window.close", arg = "recent" }); call("cmd", { id = "menu.system" }); wait(10)
call("select", { ids = { id } })

-- U22: area light (添加光源 page), the screenshot window's 含前景框 / 本次目錄, the background list's 無.
local lights0 = objects()
call("cmd", { id = "page.lights" }); wait(20)
check(click("面光源").ok, "面光源 clicked")
local area = nil
for oid, o in pairs(objects()) do if not lights0[oid] and o.kind == "light" then area = o end end
check(area ~= nil and area.light_type == "area", "面光源 adds an area light")
if area then call("select", { ids = { area.id } }); wait(20); call("cmd", { id = "edit.delete" }); wait(20) end
open_window("app.screenshot", "shot")
local ui = function() return call("state").ui or {} end
local dir0 = ui().shot_directory or ""
check(click("含前景框").ok and ui().shot_frame == false, "含前景框 off")
check(click("含前景框").ok and ui().shot_frame == true, "含前景框 on")
local r = call("click", { text = "本次目錄", contains = true }); wait(20)
check(r.ok and (ui().shot_directory or ""):find("session_") ~= nil, "本次目錄 on: shots go into a session folder")
call("click", { text = "本次目錄", contains = true }); wait(20)
check(ui().shot_directory == dir0, "本次目錄 off: back to the shot folder")
call("cmd", { id = "window.close", arg = "shot" }); wait(10)
call("cmd", { id = "scene.tab", arg = "7" }); wait(30)
local function thumb(name) local r = call("click", { text = name, tag = true }); wait(20); return r end
check(thumb("bg_01.png").ok and call("state").background == "studio/bg/bg_01.png", "a background thumbnail puts that picture behind the scene")
check(thumb("koi_studio_frame_01.png").ok and call("state").frame_picture == "studio/frame/koi_studio_frame_01.png", "a frame thumbnail lays that frame over the view")
check(thumb("frame:none").ok and call("state").frame_picture == "", "frame 無 takes the frame off")
check(thumb("bg:none").ok and call("state").background == "", "background 無 leaves no picture")
call("cmd", { id = "page.scene" }); wait(10)
call("select", { ids = { id } })

-- U22: the ? help (hover shows, a click pins it in the 說明 window), the Material Editor window (renderer, material,
-- properties of the selected item), the animation controller window and the catalogues' 定位當前.
open_window("app.settings", "settings")
check(click("?").ok and (call("state").ui or {}).help ~= "", "a settings ? pins its help")
check(click("?").ok and (call("state").ui or {}).help == "", "the same ? again unpins it")
call("cmd", { id = "window.close", arg = "settings" }); wait(10)
local items0 = objects()
call("cmd", { id = "add.item", arg = "2/12/681" })
local item = nil
for _ = 1, 60 do
  for oid, o in pairs(objects()) do if not items0[oid] and o.kind == "item" then item = o end end
  if item then break end
  wait(30)
end
check(item ~= nil, "a catalogue item to edit")
if item then
  call("select", { ids = { item.id } }); wait(60)
  check(click("材質").ok, "the tree's 材質 button opens the Material Editor")
  local mui = {}
  for _ = 1, 40 do wait(30); mui = call("state").ui or {}; if (mui.material_properties or 0) > 0 then break end end
  check((mui.material_properties or 0) > 0 and (mui.material_name or "") ~= "", ("the editor lists the material %s and its %d properties"):format(tostring(mui.material_name), mui.material_properties or 0))
  check(click("此材質全部預設").ok, "此材質全部預設 clicked")
  call("cmd", { id = "window.close", arg = "material" }); wait(10)
  call("cmd", { id = "page.items" }); wait(30)
  local other = nil
  for _, g in ipairs(call("catalog", { kind = "item" }).groups or {}) do if g.id ~= 2 and (g.name or "") ~= "" then other = g break end end
  if other then click(other.name) end
  local ui = function() return call("state").ui or {} end
  check(other ~= nil and ui().item_browse ~= "2/12", ("the item list shows another group first (%s)"):format(tostring(ui().item_browse)))
  check(click("定位當前道具").ok and ui().item_browse == "2/12" and ui().item_located == "2/12/681",
    ("定位當前道具 goes to the selected item's group and category and scrolls to it (%s, %s)"):format(tostring(ui().item_browse), tostring(ui().item_located)))
  call("cmd", { id = "page.items" }); wait(10)
  call("cmd", { id = "edit.delete" }); wait(20)
end
call("select", { ids = { id } }); wait(20)
open_window("app.animcontrol", "animctl")
local function speed() local o = objects()[id] return o and o.speed end
check(click("播放").ok and speed() > 0, "動畫控制器 播放: the character plays")
check(click("暫停").ok and speed() == 0, "動畫控制器 暫停: speed 0")
check(click("播放").ok and speed() > 0, "動畫控制器 播放 again: the speed it had")
local function looping() local o = objects()[id] return o and o.force_loop end
check(click("強制循環").ok and looping() == true, "動畫控制器 強制循環 on")
check(click("強制循環").ok and looping() == false, "動畫控制器 強制循環 off again")
-- 定位當前 in the motion list: play a motion, look at the H motions, then come back to it.
local ag = (call("catalog", { kind = "anim" }).groups or {})[2]
local acat = ag and (call("catalog", { kind = "anim", group = ag.id }).categories or {})[1]
local entries = acat and call("catalog", { kind = "anim", group = ag.id, category = acat.id }).entries or {}
local motion = entries[#entries]
check(motion ~= nil and call("pose", { id = id, anim = motion.anim }).ok, "a Studio motion to locate (" .. tostring(motion and motion.name) .. ")")
call("cmd", { id = "page.anim" }); wait(30)
local aui = function() return call("state").ui or {} end
click("H 動作")
check((aui().anim_browse or ""):sub(1, 1) == "1", "the list shows the H motions (" .. tostring(aui().anim_browse) .. ")")
local r = call("click", { text = "定位當前", index = 0 }); wait(30)
local k = motion and motion.anim:match("^(%d+/%d+/%d+)/") or ""
check(r.ok and aui().anim_browse == k and aui().anim_selected == (motion and motion.name),
  ("動作 定位當前 goes back to the playing motion (%s %s)"):format(tostring(aui().anim_browse), tostring(aui().anim_selected)))
call("cmd", { id = "page.anim" }); wait(10)
-- U25: an H motion's Studio controls (輔助 1／2, 動作模式) reach its blended player and come back to the motion's own.
local blended
for _, g in ipairs(call("catalog", { kind = "anim", anim_kind = 1 }).groups or {}) do
  for _, c in ipairs(call("catalog", { kind = "anim", anim_kind = 1, group = g.id }).categories or {}) do
    for _, e in ipairs(call("catalog", { kind = "anim", anim_kind = 1, group = g.id, category = c.id }).entries or {}) do
      if e.controls and #e.controls > 0 then blended = e break end
    end
    if blended then break end
  end
  if blended then break end
end
check(blended ~= nil and call("pose", { id = id, anim = blended.anim }).ok, "an H motion with Studio controls (" .. tostring(blended and blended.name) .. ")")
if blended then
  wait(60)
  local control = blended.controls[1]
  local function controls() local o = objects()[id] return o and o.anim_controls or {} end
  local own = controls()[control]
  check(own ~= nil and own >= 0, ("the blended player has %s (%s)"):format(control, tostring(own)))
  call("pose", { id = id, anim_controls = { [control] = 0.8 } }); wait(20)
  check(math.abs((controls()[control] or -1) - 0.8) < 1e-4, ("%s set to 0.8 reaches the player (%s)"):format(control, tostring(controls()[control])))
  check(click("預設").ok and math.abs((controls()[control] or -1) - own) < 1e-4, ("動作參數 預設 gives %s back to the motion (%s)"):format(control, tostring(controls()[control])))
end
call("cmd", { id = "window.close", arg = "animctl" }); wait(10)

-- U24: mirror the pose (FK page): the left arm's rotation onto the right arm, reflected (x, -y, -z).
call("select", { ids = { id } }); wait(10)
if (call("state").ui or {}).page ~= "bones" then call("cmd", { id = "page.bones" }) end
call("cmd", { id = "bones.page", arg = "0" }); wait(20)
call("pose", { id = id, fk = { { bone = "cf_j_arm00_L", euler = { 10, 20, 30 } } } }); wait(10)
local function fk_euler(bone) for _, b in ipairs(bones().fk or {}) do if b.bone == bone then return b.euler end end end
check(click("左→右").ok, "左→右 clicked")
wait(20)
local r = fk_euler("cf_j_arm00_R") or {}
local function near(a, b) return a and math.abs(((a - b + 180) % 360) - 180) < 0.5 end
check(near(r[1], 10) and near(r[2], -20) and near(r[3], -30), ("左→右 puts the left arm's rotation on the right arm, mirrored (%s)"):format(table.concat(r, ",")))
click("清除 FK")

-- U262, U263: 放下, 坐下 (on a map's chair), 配到時間軸, 移除配樂. 開啟資料夾 opens Explorer and is left out.
local function idle() for _ = 1, 240 do if (call("state").busy or "") == "" then return end wait(30) end end
local function status() return ((call("state").ui or {}).status or "") end
call("scene", { map = 4 }); idle(); wait(60)
call("cmd", { id = "add.item" }); wait(30)
call("type", { field = "搜尋道具", text = "見開き", enter = true }); wait(30)
click("見開き本1"); idle(); wait(30)
local function item() for _, o in ipairs(call("state").objects or {}) do if o.kind == "item" then return o end end end
local book = item()
check(book ~= nil, "a book to put down")
call("camera", { focus = { 0, 0, 70 }, yaw = -110, pitch = -30, distance = 300 }); wait(20)
local z0 = book and book.location[3] or 0
check(click("放下").ok, "放下 clicked")
wait(30)
local down = item()
check(down and down.location[3] < z0 - 1, ("放下 brings the book down (%s to %s)"):format(tostring(z0), tostring(down and down.location[3])))

local chairs = {}
for _, b in ipairs(call("bounds", { map = true, ids = {} }).map or {}) do
  local w, l, h = b.max[1] - b.min[1], b.max[2] - b.min[2], b.max[3] - b.min[3]
  if math.min(w, l) >= 30 and math.max(w, l) <= 65 and h >= 55 and h <= 115 then chairs[#chairs + 1] = b end
end
check(#chairs > 0, ("the classroom has chairs (%d)"):format(#chairs))
if #chairs > 0 then
  local c = chairs[1]
  local cx, cy = (c.min[1] + c.max[1]) / 2, (c.min[2] + c.max[2]) / 2
  call("select", { ids = { id } }); wait(10)
  call("camera", { focus = { cx, cy, 40 }, yaw = 0, pitch = -50, distance = 250 }); wait(30)
  local shot = call("ui_shot", { name = "button_check_chair.png" })
  check(click("坐下").ok and status():find("椅子", 1, true) ~= nil, "坐下 asks for a chair")
  call("mouse", { x = (shot.width or 1600) / 2, y = (shot.height or 900) / 2 }); wait(120)
  local me = objects()[id]
  local at = me and me.location or { 1e9, 1e9, 0 }
  check(math.sqrt((at[1] - cx) ^ 2 + (at[2] - cy) ^ 2) < 40, ("坐下 puts the character at the chair (%.0f,%.0f by %.0f,%.0f)"):format(at[1], at[2], cx, cy))
end

-- U264: a sofa, read from its mesh: on the place clicked, the hips on the seat, with no map around.
call("scene", { map = -1 }); idle(); wait(30)
local known = objects()
call("cmd", { id = "add.item", arg = "2/13/79" }); idle(); wait(30)
local sofa = nil
for oid, o in pairs(objects()) do if not known[oid] and o.kind == "item" then sofa = o end end
check(sofa ~= nil, "a sofa to sit on")
if sofa then
  wait(120)
  check(math.abs(objects()[sofa.id].location[3]) < 1, ("a new sofa lands on the floor (%.1f)"):format(objects()[sofa.id].location[3]))
  call("transform", { id = sofa.id, location = { 300, 0, 0 }, rotation = { 0, 0, 0 } }); wait(30)
  call("select", { ids = { id } }); wait(10)
  call("camera", { focus = { 300, 0, 50 }, yaw = 90, pitch = -20, distance = 300 }); wait(30)
  local shot = call("ui_shot", { name = "button_check_sofa.png" })
  check(click("坐下").ok, "坐下 clicked for the sofa")
  call("mouse", { x = (shot.width or 1600) / 2, y = (shot.height or 900) / 2 + 50 }); wait(120)
  local me = objects()[id]
  local at = me and me.location or { 1e9, 1e9, 1e9 }
  check(math.abs(at[1] - 300) < 40 and math.abs(at[2]) < 30 and math.abs(at[3]) < 8, ("坐下 sits on the sofa (%.0f,%.0f,%.0f)"):format(at[1], at[2], at[3]))
end

-- U268: a new scene's 主光 is Studio's character light: on the map at 4 it washed out the ground.
do
  local light = nil
  for _, o in pairs(objects()) do if o.kind == "light" and (not light or o.id < light.id) then light = o end end
  local detail = light and (call("inspect", { id = light.id }).object or {}) or {}
  check(((detail.light or {}).bCharactersOnly) == true, "主光 lights the characters only")
end

-- U265: 看對方, both looking at the other's head.
local card = (((call("inspect", { id = id }).object or {}).character or {}).card) or ""
local known2 = objects()
call("spawn", { kind = "character", card = card }); idle(); wait(60)
local other = nil
for oid, o in pairs(objects()) do if not known2[oid] and o.kind == "character" then other = o end end
check(other ~= nil, "a second character to look at")
if other then
  local function neck(oid) return ((call("inspect", { id = oid }).object or {}).character or {}).neckLook end
  call("timeline", { time = 0 }); wait(5)
  local before = neck(id)
  call("timeline", { key = { ids = { id } } }); wait(5)
  call("timeline", { time = 2 }); wait(5)
  call("select", { ids = { id, other.id } }); wait(10)
  check(call("cmd", { id = "transform.look" }).ok, "看對方 runs")
  wait(30)
  check(neck(id) == "Point" and neck(other.id) == "Point", ("看對方 turns both to a look point (%s, %s)"):format(tostring(neck(id)), tostring(neck(other.id))))
  -- U266: a key holds the look: as it was at 0 s, on the other from 2 s.
  call("timeline", { key = { ids = { id } } }); wait(5)
  call("timeline", { time = 0 }); wait(20)
  local early = neck(id)
  call("timeline", { time = 2 }); wait(20)
  local late = neck(id)
  check(early == before and late == "Point", ("keys hold the look (%s at 0 s, %s at 2 s)"):format(tostring(early), tostring(late)))
  call("keys", { id = id, action = "clear" }); wait(5)
  call("timeline", { time = 0 }); wait(5)
  call("select", { ids = { other.id } }); wait(10); call("cmd", { id = "edit.delete" }); wait(20)
  call("select", { ids = { id } }); wait(10)
end

local wav = "UserData/audio/_button_check.wav"
local f = assert(io.open(wav, "wb"))
f:write("RIFF", string.pack("<I4", 36 + 8000), "WAVEfmt ", string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, 8000, 8000, 1, 8), "data", string.pack("<I4", 8000), string.rep("\128", 8000))
f:close()
call("cmd", { id = "window.open", arg = "outside" }); wait(30)
click("_button_check.wav")
check(click("配到時間軸").ok and status():find("已載入音樂", 1, true) ~= nil, "配到時間軸 puts the file on the timeline")
check(click("移除配樂").ok and status():find("已移除音樂", 1, true) ~= nil, "移除配樂 takes it off")
os.remove(wav)

print(("BUTTONS %d/%d"):format(passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
