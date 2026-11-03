# 一對一黑臉、廣場黑球：暫停時的進度（2026-10-26 23:00）

**2026-10-27 已完成**：
- 黑臉：根因是視錐剔除，修正見 064080221；黑球修正也在同一個 commit。
- 群聊提示前綴：4666326a0。

以下是暫停當時的紀錄。黑臉部分的假設（morph 資料、vertex factory）後來證實都不對。

E 組，使用者要求暫停時留下的交接。以下改動都在 E 工作樹，**未提交**。

## 1. 一對一（高模）張嘴時臉消失／變黑（優先）

**已重現**：Sandbox `OneOne`（雷電：戀人，好感 95）、晚上 20 點、「進入一對一場景」，她說話時：

- 臉皮（`cf_O_face`）整個消失，或只剩黑色剪影。黑色那層是描邊外殼的內面。
- 眼睛和口腔周圍那一圈（UV V<0.09）還在。
- 閉嘴、閉眼（眼睛 morph）時臉都正常。

截圖：`E:\OpenKoikatsu\Saved\StreetSocial\Play-20261026T223549\control_shots\`（shot.0004、0020 等）。

**已知事實**：

- 一對一的女主臉是 GPU skeletal mesh（log 有 `OK skelmesh gpu part=cf_O_face`，part 2，shader 7）。嘴型透過 UE morph target 套用：`KKPreviewActor.cpp` 的 `Slot.Comp->SetMorphTarget((Desired-Baseline)/100)`。
- morph target 由 `KKSkeletalBuilder.cpp` 的 `OKAddMorphs` 建立：原始 delta 做 `OkToUePos`，`SectionIndices` 只有 0。
- 一對一的環境是 `OK_GPU_SKIN=1` 加 `OK_HEAD_GPUSKIN=1`（`OKPrepareLiveGpuEnv`）。這條路徑的 `face_baseline_weights` 和 87625f6d0（舌頭修正）之前等價，所以不是那次改動造成的。
- 街區走 KKRuntimePose 自己的 delta 路徑，不受影響。

**在遊戲內排除掉的開關**（主控台切換後照樣出問題）：

- `ok.FaceFlatten 0`
- `ok.Face.PreparedPalette 0`
- `ok.Animation.LeaderPoseReuse 0`
- `r.AllowOcclusionQueries 0`
- `r.MorphTarget.ForceUpdate 1`
- `r.SkinCache.Mode 0`（執行中切換，可能要重建元件才生效）

`r.MorphTarget.Mode` 是唯讀，切不了。

**下一步**：

1. `KKPreviewActor.cpp` 新加了診斷指令 `ok.DumpFaceMorphs`（未提交、未編譯驗證）。它列出每個臉部元件每個 morph 的 delta 數、最大位移（cm）、最大頂點索引與 `NumBaseMeshVerts`、目前權重與基準。
2. 用新 tag 打包（例如 `--tag OneOneE2 --base-dir Saved/StreetSocial/Base1026c --skip-cook --skip-base`）。上一次打包在暫停時中斷了。
3. 跑 scratchpad 的 `oneone_dump.lua 2`，搭配 `SANDBOX=OneOne`，比對嘴巴 morph（`kuti_*`）和眼睛 morph 的資料差異。
4. 嫌疑方向：
   - 嘴巴 delta 的尺度或索引和 GPU 網格不一致，例如 mod 臉的 renderer scale。
   - morph 啟用後，臉部材質的頂點色或 UV2～4 沒有被綁上。臉是 4 組 UV 加頂點色（`bFaceOverlay`）。
5. 另一個對照實驗：環境變數 `OK_CPU_SKIN=1` 啟動，讓臉走 CPU 路徑，看臉是否正常。

## 2. 廣場黑球

黑球是話題拾取物：`OKStreetSocialScene.cpp` 約 827 行用引擎 Sphere，而且沒有材質。已改成：

- 網格：`/Game/Scenes/StreetSocial/Meshes/StreetSphere`
- 材質：`StreetMaterial09`（`EOKStreetMaterial::Lamp`）

這個改動已編進 `OneOneE1` stage，**還沒在廣場實際看過**。驗證後才提交。

## 3. 群聊提示前綴（未提交）

| 位置 | 改動 |
|---|---|
| `OKStreetSocialScene.cpp` 的 SendFreeTalk | `His?Text:OKMsg("ui.party.note_for_partner",...)` |
| `on_shift_tell_her` | 名字改用 `SpokenName(Character)` |
| 三語 `ui_text.toml` | 新增 `note_for_partner` |

待驗證：群聊時送出的提示裡要有「遊戲給」。

## 4. 待查：關閉遊戲時背景卡片載入崩潰（TTS session 回報）

- 現象：沙盒遊戲視窗被關掉的途中，ok-extract 還在背景載入 `keqing.png`，觸發斷言崩潰。
- 斷言：`ModuleManager.IsModuleLoaded` 失敗，訊息為「Tried to get module interface for unloaded module: 'ImageWrapper'」。
- log：`E:\OpenKoikatsu\Saved\StreetSocial\Play-20261026T224230\game.log`。
- 推測：背景的卡片載入沒有在引擎關閉前停下或等它結束。

## 注意

- 工作樹裡也有 TTS session（唱歌）未提交的改動：`OKStreetSocialSong*`、`ok-rules/src/song.rs` 等。提交時只拿自己的 hunk。
- 不要提交 `OKExtractBuildStamp.h`。
