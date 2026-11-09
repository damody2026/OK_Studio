# OK 基礎庫共用資源盤點（2026-11-04）

盤點對象：`Content/IndependentResources/base_v1/` 目前 git 索引中追蹤的檔案（F 機，`duo2`）。
規則與流程見 [基礎庫共用資源與版控計畫](BASE_LIBRARY_SHARED_RESOURCES_PLAN.md)；共用 mod 清單是 [`Tools/base_library_shared_mods.txt`](../Tools/base_library_shared_mods.txt)。

盤點時的工作樹狀態（尚未 commit）：已從共用清單移除 mizuha clothes、cleavage shirt、mishiki_tight2 共 5 行，前兩者的 4 個 okmodel 已加入 `models/.gitignore` 並取消追蹤，不計入本表。

## 判斷規則

`ok-extract <遊戲> --oklib shared-ignore <基礎庫>` 依模型的來源標籤判斷，任一來源符合即為共用（進版控）：

1. 原作來源（不在 `mods/` 底下的路徑）。
2. 任何 zipmod 裡 `abdata/list/` 下的 bundle（每張卡建項目目錄都會讀）。
3. 列在共用 mod 清單：`資料夾/`、`zipmod`，或 `zipmod|abdata/...` 單一 bundle。

其他模型（只有第三方 mod 用到、或沒有記錄來源）寫進 `models/.gitignore`，只留本機。

## 一、模型（`models/`，622 個 okmodel，本機約 6.7 GB）

### A. 原作來源（約 470 個）

| 來源 | 模型數 | 內容 |
|---|---:|---|
| `abdata/chara/*` | 181 | 人物部件（細分見下） |
| `abdata/chara/thumb` | 151 | 選單縮圖 |
| `abdata/chara/sunshine` | 1 | Sunshine 追加服裝 |
| `abdata/list/characustom`、`abdata/list/shapecorrect` | 17 | 角色編輯清單、形狀修正 |
| `abdata/studio/map` | 75 | Studio 地圖 |
| `abdata/studio/info` | 18 | Studio 資源清單 |
| `abdata/studio/*.unity3d`（00、01、30～90） | 18 | Studio 物件包 |
| `abdata/studio/` 的 `mat`、`base`、`filter`、`sky` | 5 | 材質庫、基礎、濾鏡、天空 |
| `plugins/kks_plugins/kks_materialeditor` | 2 | ME 內建 `ec_shaders`、`kks_shaders` |

`abdata/chara` 181 個的組成：

- 衣服：`co_top` 12、`co_bot` 9、`co_shoes` 5、`co_bra` 4、`co_panst` 3、`co_gloves` 3、`co_socks` 2、`co_shorts` 2
- 服裝子部件：`cpo_sailor` 3、`cpo_jacket` 3
- 配件：`ao_head` 12、`ao_hand` 9、`ao_body` 8、`ao_neck` 7、`ao_hair` 7、`ao_face` 7、`ao_waist` 6、`ao_arm` 5、`ao_leg` 2、`ao_kokan` 2
- 頭髮與頭部：`bo_hair` 9、`bo_head` 1
- 材質貼圖：`mt_mask` 25、`mt_eye` 5、`mt_body` 3、`mt_pattern` 3、`mt_face` 2、`mt_eyeline` 2、`mt_emblem` 2，以及 `mt_underhair`、`mt_sunburn`、`mt_ramp`、`mt_nose`、`mt_nip`、`mt_mole`、`mt_lipline`、`mt_lip`、`mt_hairgloss`、`mt_eyeshadow`、`mt_eyebrow`、`mt_cheek` 各 1
- 其他：`oo_base`、`oo_hand`、`mm_base`、`face_preset`、`etc` 各 1
- **`mishiki_suit` 1**：虚子 `mishiki_tight2.zipmod` 的服裝。因為遊戲 `abdata/chara/` 裡也有同一個檔案，被判為原作來源；要移出版控需要在清單加排除規則（尚未實作）。

### B. 只因共用 mod 清單而進版控（約 134 個）

| 類別 | 模型數 | 來源 mod／bundle |
|---|---:|---|
| KKS UncensorSelector | 23 | `kks_uncensorselector_base`（`oo_base`）；SAC uncensor selector pack v0.9.2（sacclit／sacclit2／sacgash／sacgash2／sacinnie／sacinnie2／sackupaa／sacmeaty／sacmeaty2／sacpuffy／sacroastie／sacroastie2／sacroastie3／sacslit）；EV MuscleBody（chad_clothes、mt_mask_chad、musclef、musclef2、musclem、musclesff）；DeathWeasel SoS uncensor v1.3、color matching balls v1.0 |
| KK UncensorSelector | 15 | moderchan uncensor；Nam Miyoo outlined pussy pack v0.2.3（long／mid／short slit）；DeathWeasel amputee body v1.0.3；kk_lo_pussy v0.5.4；anon profundis v0.5.2；Alexae bubblegum v1.0；lordmogsama cartoon v1.1；anon_n64 lizard dong v0.1.1；Hansh horse schlong v0.1.1；SAC dong v0.1；DAnon big color matching balls v1.0；origami frog male puffy nipples v1.0（mnip、mnip2） |
| BetterPenetration | 8 | profundis、SAC innie、bubblegum、cartoon、SoS、SAC dong、color match balls、DA color match balls |
| KKS_Fixes | 9 | DeathWeasel accessory hair vanilla fix v1.1（`ao_head_00`）、face fixes v2.0（`bo_head_00`）、texture fixes v2.0.2（`co_bra_00`、`co_shorts_00`、`mt_body_detail_00`、`mt_hairgloss_00`、`mt_mask_body_00`、`mt_sunburn_00`、`mt_underhair_00`） |
| Material Editor shader（`sideloader modpack - kk_materialeditor/`） | 45 | harvexarc matcap（9）、harvexarc shader pack（gem、resources、xray）、better matcap（2）、Nashi IBL v1.1（4）、nharuka KKUSS v1.10（4）、7s magnification（2）、fur（2）、goo（2）、space（2）、swirl（2）、triplanar（2）、portia dual scroll（2）、fx hologram v1.1、glitch、GF liquid、wireframe v1.0、CZ gem（wireframe）、DeathWeasel blur、DeathWeasel pixelate、DA shaders、rskoi snow and rain |
| shader（`exclusive kks`） | 16 | nharuka KKSUTS v2.2（kkuts、alpha、alpha2、alpha2tess、alphatess、clothes、clothestess、eye、eyew、hair、hairtess、item、item2、itemtess、tess，共 15）、xukmi vanilla plus v1.7.2 |
| 陰影 ramp | 7 | dak cgramp、dak revramp v1、augh minimalist shadows v1.0、koikoi shade mod v0.1、uppervolta more shadow types、yamadamod ramp、zmr shadow |
| 覆蓋原版 abdata 路徑 | 12 | augh body outline fixes v1.1.0、stinger722 unc_outline v1.1（皆為 `mm_base`）；aaabbb kimon_fixed（`mt_mask_body_00`、`mt_mask_bra_00`）；murara kimono_jacket_t（`mt_mask_body_00`、`mt_mask_bra_00`）；noble_kale body paint texture v1.0（`mt_face_paint_00`）；tansen eyes skin v2.0（`mt_eye_00`、`mt_eye_hi_up_00`、`mt_eyebrow_00`、`mt_eyeline_up_00`） |
| `abdata/list` 自動共用 | 2 | v-katsu 02（`00_vkat02`）、moderchan a-z 0-9（`nt_a_z_0_9`） |

`kks.backport.clothes` 的 `p_cf_bot_magac00` 同時有原作來源，計入 A 類。

kimon_fixed、murara 的 `mt_mask_*` 各含 60～66 張貼圖，是整包覆蓋原版；已移除的 mizuha、cleavage shirt 同路徑 bundle 只含 1～2 張自己衣服的遮罩，不是全域覆蓋。

### C. 本機查不到來源（18 個）

已進版控，但 F 機的 `converted.tsv` 沒有它們的來源標籤，推測是從其他機器（C／E）的基礎庫合併進來的；分類需在那台機器用 `OKLIB_SHARED_VERBOSE=1` 確認。

## 二、模型以外的共用資料（進版控）

| 路徑 | 檔案數 | 本機大小 | 內容 |
|---|---:|---:|---|
| `anims/` | 5,806 | 562 MB | Studio 動畫（`anims/studio/`）與 `studio_variants.okpack` |
| `studio/voice/` | 8,280 | 2.0 GB | Studio 語音 |
| `studio/bgm/` | 51 | 287 MB | Studio 背景音樂 |
| `studio/bg/` | 25 | 71 MB | Studio 背景圖 |
| `studio/sky/`、`studio/sky.json` | 10 | 20 MB | 天空 |
| `studio/reflections/` | 51 | 13 MB | 反射 |
| `studio/samples/` | 16 | 13 MB | 樣本場景 |
| `studio/frame/` | 8 | 1.1 MB | 外框 |
| `studio/map_environments.json`、`studio/map_reflections.json` | 2 | — | 地圖環境與反射設定 |
| `paired/` | 4 | 1.4 GB | 配對動作：`okpaired.json`、`manifest.json`、`editor-demos.json`、`cache/pack.bin` |
| `h/` | 14 | 1.1 MB | 配對音效：`se.json` 與 13 個 `h/se/*.ogg` |
| `studio_anims.json`、`studio_child_animations.json`、`studio_items.json`、`studio_voices.json` | 4 | 約 8 MB | Studio 目錄 |
| `sources.okidx` | 1 | 1015 MB | 來源索引，記著約 7300 個 zipmod（含非共用 mod） |
| `converted.tsv` | 1 | 7.2 MB | 轉換紀錄（來源標籤 → 模型 ID） |
| `missing.txt`、`shader_states.json`、`oklib.json`、`edits.stamp`、`shared_mods.txt` | 5 | 約 110 KB | 缺漏紀錄、shader 狀態、庫設定、編輯戳記、共用清單副本 |

只留本機、不進版控：`studio_mod_items.json`、`studio_mod_sources.txt`、`work/`，以及 `models/.gitignore` 列出的模型。

`Content/IndependentResources/` 下其他進版控的資料夾（`RuntimeMaterials`、`RuntimeAnimations`、`StreetSocialData` 等）是專案自己的內容，不屬於基礎庫共用資源，未列入本表。

## 注意事項

- 不要在單一機器直接執行 `--oklib shared-ignore` 覆寫已提交的 `models/.gitignore`：F 機的基礎庫比合併後的版本小，重新產生會刪掉約 3,900 行別台機器才有的模型。只增補需要的行。
- 取消追蹤只影響之後的 commit；已推送到 `origin` 的歷史仍含被移除的模型。
