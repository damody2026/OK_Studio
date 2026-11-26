# 配種：兩張角色卡生出孩子（2026-11-22）

讀卡器 › 人物卡 › 人物卡總欄 › **配種**。選兩張卡當母親與父親，按「配種」就生出一個孩子：一張新的角色卡，生出來直接打開顯示，並拍一張她自己的照片當卡片圖。同一對父母每按一次都是不同的孩子。

## 使用

1. 在配種頁下方的卡片牆點一張卡，按「設為母親」；再點另一張，按「設為父親」（「對調」交換兩人）。卡片牆上方的搜尋框可以用萬用字元找卡。
2. 按「配種」。OK 卡要重新封裝，約半分鐘；狀態列顯示進度。
3. 孩子存在 `UserData/okbreed/<母親檔名>×<父親檔名>_<種子>.png`，自動選中並載入 3D，顯示後拍正面照片換掉卡片圖，卡片牆跟著更新。
4. 孩子本身也是角色卡，可以再拿去當父母（第幾代記在卡裡）。

MCP（`reader_call`）：`{"action":"action","command":"breed_parent","role":"mother"|"father","path":"<可省略，省略用目前選的卡>"}`、`{"action":"action","command":"breed","seed":<可省略>}`，結果寫在 log（`MCP breed ok: <孩子的卡>`、`OK breed seed ...`）。畫面上的按鈕：`ok.ReaderScreen press 設為母親`／`設為父親`／`配種`。

命令列：`ok-extract.exe <遊戲或 X:/NoGame> --oklib breed <母親卡> <父親卡> <種子> <輸出卡>`（OK 卡要設 `OK_BASE_LIBRARY`），和讀卡器同一段程式（`breed::file::breed_into`）。

## 遺傳規則（`Tools/ok-extract/src/breed.rs`）

孩子以其中一位父母的卡為底（隨機），沿用那位的服裝（上衣、下衣、內衣另外混搭，見下表）、飾品、卡片資料與外掛資料；身體、臉、頭髮（卡片的 `Custom` 區塊：face、body、hair 三段）逐項混合：

| 基因 | 遺傳 |
|---|---|
| 臉 52 項、身體 44 項滑桿（`shapeValueFace`／`shapeValueBody`） | 每一項各自在兩人之間取一個點（10%～90%）；6% 機率突變，可以略超出兩人（最多超出 0.2，限制在 -1～2） |
| 其他數值（光澤、胸部柔軟度等） | 兩人之間 25%～75% |
| 顏色（四個浮點數：膚色、髮色、瞳色等） | 整個顏色一起混合；5% 機率小幅偏色。頭髮的顏色用 HSV 混（色相走較短的那一邊，一方接近灰色時用另一方的色相；飽和度、亮度直接內插）：RGB 取中間會變灰變暗，一代代混下去愈來愈黑（使用者 2026-11-22） |
| 模型編號（頭、眼睛、眉毛、鼻、嘴、膚質…） | 來自其中一人；頭與臉部膚質一起，左右眼一起 |
| 髮型 | 四個部位（後、前、側、附加）一起來自其中一人，髮色仍然混合 |
| 衣服（2026-11-22 起） | 每套服裝以當底那位的為主；**上衣**（含水手服／外套子部件）、**下衣**、**內衣**（胸罩＋內褲一起）各自抽一次，抽到另一位就在每一套都換成另一位那套的那件（顏色、花樣跟著件走）。另一位那套沒穿那件就不換（不會換成光著）。混完下身沒穿（使用者：「下體沒穿幫我補上裙子」）：那套有上衣沒下衣，就補上衣那位在那套穿的下衣，她沒穿就補另一位那套的（多半是裙子；Sideloader 對照與 Material Editor 列跟著件走，`okDn` 的 `bottom_added` 記哪幾套，`cover_bare_outfits`）。兩人那套都沒穿下衣才照原樣（雷電的兔女郎上衣前面是開的，原本「她自己就這樣穿」的例外讓孩子只穿內褲）。不用遊戲本身的裙子：兩人都沒穿過的衣服，封裝時的嚴格開卡要問兩人資料裡都沒有的問題（プリーツスカートA 的 `skel:bone_implants`），那套就退回當底那位的整套，裙子等於沒補。手套、褲襪、襪子、鞋子、飾品、妝仍是當底那位的。那件衣服的 Sideloader 對照（`outfitN.ChaFileClothes.ClothesTop…`）與 Material Editor 列（服裝、第幾套、第幾件）跟著件走 |
| 頭髮（2026-11-22 起，讀卡器配種） | HairDeck 從父母兩人的正臉照混合生成：父親佔 40%～60%（依種子），見下方「頭髮：父母混合生成」。生成失敗（找不到 `ok-hairdeck.exe`、權重、臉照）時照舊：跟著髮型，髮型來自的那位有 HairDeck 頭髮（`okHk`）就帶上，每片頭髮的顏色依孩子混出來的髮色平移 |
| 名字 | 姓來自當底的那位；名是一人名字的前半加另一人的後半（刻晴＋雷電 → 刻電） |
| 其他角色參數（個性、聲音高低…） | 數值混合，選項來自其中一人 |

- 用到 mod 部件時，孩子的臉／身體／頭髮 Sideloader 對照（一筆只在數值等於它的 `Slot` 時生效）只留「她的值來自那位、且值等於 `Slot`」的那筆；兩人值相同時用當底那位的。原本兩人的對照全帶上，一位父母沒在用的 mod 對照剛好等於另一位的原作編號時，孩子就戴上沒人戴過的 mod 部件（第二代的眼睛高光 cat 410 1919，封裝時開不了卡）。頭髮的 Material Editor 設定跟著頭髮那一方。
- ABMX 骨骼、膚色貼圖疊加（KSOX）、UncensorSelector 等仍是當底那位的。
- 混搭的那套服裝封裝時開不了（上衣、下衣來自不同父母，要一張兩人的卡都沒問過的身體遮罩：`texture_payload … bodymask`），那一套改回當底那位的整套再封（`okDn` 的 `clothes_not_mixed` 記哪幾套）；和缺目錄項目的基因同一個重試迴圈，最多 7 次。
- 衣服混搭的抽籤排在所有基因之後：同一對父母、同一個種子，臉、身體、頭髮和加入混搭前一樣。KoiClothesOverlay（KCOX）的衣服疊圖還沒跟著件走：仍是當底那位的，換來的那件原本的疊圖會不見，當底那位的疊圖可能疊到換來的那件上。
- 卡片多一個 `okDn` chunk（JSON）：父母的身分、名字、檔名、第幾代、種子、當底的是誰、每組基因來自誰。孩子有自己的 `okId`（由父母身分與種子算出），KKS 卡的 `About.dataID` 也換成她自己的。
- 同一對父母、同一個種子永遠生出同一個孩子。

### 頭髮：父母混合生成（2026-11-22）

使用者：「第一代都不是 HairDeck，兩邊的頭髮 40～60% 混合一下用 HairDeck 生成」。讀卡器配種（`OKGalleryBreed.cpp`）：

1. 父母的正臉照：`Saved/OKBreed/faces/<卡片路徑的 MD5>.png`，比卡片新就直接用（使用者：「已經拍過的角色復用就好，不要重複一直拍照」）；沒有或卡片改過才打開她拍一張（`OKCardPreviewCapture::BeginHairReference`：正面、以臉部網格為中心、寬 1.5 個臉部網格寬，768×1024）。孩子生出、拍完卡片圖後也拍她的臉，她當父母時就不用再拍。
2. 臉照裡不是頭髮的飾品不拍（兔耳、帽子、髮夾）：使用者「不應該把兔耳飾品當頭髮」，HairDeck 會把頭上的東西都當頭髮生成。用頭髮 shader（`main_hair`）、網格／renderer 名稱有 hair、kami，或類別 121 的飾品槽算頭髮，整槽留著（雷電的長髮同一網格還有一層 main_item）；其他飾品藏起來（`portable::hairdeck::non_hair_accessory_parts`，`ok_session_non_hair_accessories`）。不看掛點：雷電的兔耳掛在頭髮掛點、長髮掛在頭上。
3. 配出孩子後，`ok-hairdeck generate --image <母親臉> --mix <父親臉> --mix-weight <父親比例> --box 0,143,768,911 --mix-box 0,143,768,911 --seed <種子>`：兩張圖各過 DINOv3，頭髮模型與顏色模型的條件逐 token 線性混合後取樣一次（結果在 `Saved/OKBreed/hair/<孩子檔名>/`）。父親比例 = 0.4 + 0.2 ×（種子雜湊），同種子同結果。
4. 生成的頭髮存進孩子卡（`okHk`，`FOkSession::CardHairDeck`），選項記 `mix`（母親、父親檔名、`father_share`）。基準髮色存生成頭髮的平均色（不是卡片髮色），開卡時每片頭髮整體平移到卡片的髮色（HSV 混出來的），頭髮顏色跟著遺傳走。log：`OK breed seed … HairDeck hair mixed from both (father 48%)`。

所以第一代父母用原卡（沒有 HairDeck 頭髮），孩子起每一代都是 HairDeck 頭髮。

## OK 卡

父母任一方是 OK 卡，孩子就做成 OK 卡（不是的那位先從遊戲的 zipmod 做成 OK 卡）：兩人的卡內資源包（`okLc`）與開卡問答（`okLt`）合併，封裝後重做 digest，和服裝卡穿到 OK 卡上是同一套流程（[OK_CLOTHES_CARD.md](OK_CLOTHES_CARD.md)）。孩子的組合會問到父母都沒問過的問題（例如另一方的眼睛高光），封裝時從共用資源補錄答案，父母的答案優先（`oklib::seal_card_adding_answers`）。

### 子卡依賴父母（預設）

孩子的卡只放父母卡沒有的資源；開卡時才讀父母的卡，把她自己的、父母的（父母若也依賴，再往上一代）資源包與問答依序合併後開（`breed::with_parents`，`card::card_file_bytes` 讀卡時處理，所以讀卡器、街區、命令列都一樣）。

- 生出來時照常做出完整的卡，再減掉父母已有的部分（`oklib::pack_delta`、`tree_answers::delta`），只寫回差額。`okDn` 記父母的 `path`（絕對路徑）、`relative`（相對於孩子的資料夾）與 `depends`（依賴哪幾位：原本就是 OK 卡檔案的那位；從原作卡臨時做成 OK 卡的那位，她給的資源留在孩子卡裡）。
- 找父母：先照相對路徑，再照絕對路徑，最後在孩子旁邊找同檔名且 `okId` 相同的卡。找不到就開不了卡，錯誤訊息寫出找過哪些路徑；父母卡換過內容（`okId` 不同）仍會用，log 會提醒。
- 合併結果在同一個程序裡留最近兩張，父母或孩子的檔案沒變就不重算（刻晴 × 雷電的孩子合併約 0.4 秒）。
- 大小：刻晴 × 雷電的孩子 90 MB → 24 MB（剩下的是卡片本身的資料，雷電的 Material Editor 貼圖跟著衣服那一方），惠惠 × 胡桃的孩子 35 MB → 3.9 MB。
- 父母卡要留著（搬家時連父母一起搬，資料夾相對位置不變就好）。

### 匯出完整卡

要給別人或單獨帶走時才做完整卡：讀卡器配種頁選她按「匯出完整卡」，存到 `UserData/okbreed/export/<同檔名>.png`；命令列 `ok-extract.exe X:/NoGame --oklib breed-export <子卡> <輸出>`；MCP `{"action":"action","command":"breed_export","path":"<可省略>"}`。合併所有祖先的資源包與問答，`okDn` 的 `depends` 清掉（記 `exported_from`），再逐套服裝嚴格開一次並重做 digest（`remake_ok_card`），不需要父母卡就能開。

命令列配種時第五個參數給 `whole` 則直接生完整卡（舊行為）。

卡片圖：生出時先用當底那位的圖，顯示後拍正面照換掉（`ok_breed_file` op 1，只換 PNG 影像，`ok*` chunk 與卡片資料不動）。

## 驗證（2026-11-22，F）

- Rust 單元測試 `breed::tests`：同種子同結果、滑桿在兩人之間、顏色整體混合、名字混合。
- 命令列：刻晴 × 雷電（都是 OK 卡），種子 42，約 29 秒；孩子 Raiden Sho晴，衣服來自父親、頭髮來自母親，封裝 `added zips=52`，嚴格重開成功，資源包 66 MB。
- 讀卡器（照玩家操作：點卡、設為母親、點卡、設為父親、配種）：
  - 刻晴 × 惠惠 → re 刻min：衣服與頭髮都來自刻晴，臉部滑桿混合（例如臉上部前後 59，刻晴是 9）。刻晴的雙馬尾與貓耳是飾品做的，跟著衣服那一方，所以外觀接近刻晴。
  - 雷電 × 惠惠 → Raiden Shomin：雷電的兔女郎服裝加上惠惠的髮型，混合明顯。
  - 兩次都約 30～40 秒生出並顯示；拍照後卡片牆換成她自己的照片，從磁碟重開只用 OK 資料（不讀 zipmod）。
- 第二代：上面兩個孩子再配種（種子 7）→ Raiden 刻mmin，generation 2，約 43 秒，嚴格重開成功；卡片 105 MB（資源包 81 MB），資源包會一代代變大。

## 家族樹圖

`Tools\lua\lua.exe Tools\breed_family_tree.lua --out <圖.png> [--list <清單檔>] <卡或資料夾>...`：讀孩子卡的 `okDn`，從父母的路徑一路找到原卡，依世代排版（下一代排在父母中間），每對父母一種顏色的連線，每張卡標名字、檔案大小、依賴父母或完整卡；ffmpeg（`Tools/ffmpeg`）合成。檔名有「×」這類字時用 `--list`（UTF-8 清單檔，一行一張）：Windows 給 lua.exe 的參數是系統碼頁，中文檔名過不來；讀檔用 `okfs`（UTF-8 檔名）。

### 大家族 demo（2026-11-22，F）

讀卡器配了 13 次（照玩家操作：設為母親／父親、配種，生出來載入、拍照當卡片圖）：

| 代 | 父母 → 孩子 |
|---|---|
| 原卡 | 貞德、三月七、刻晴、雷電、惠惠、胡桃（OK 卡，18～75 MB） |
| 第 1 代 | 刻晴×雷電 兩個、惠惠×胡桃 兩個、貞德×三月七 兩個（4～40 MB） |
| 第 2 代 | 第 1 代互配四個：兩個是同一對父母的姊妹（4～16 MB） |
| 第 3 代 | 第 2 代互配兩個（4～8 MB） |
| 第 4 代 | 第 3 代的兩人 → 1 個，7.9 MB；匯出完整卡 145.6 MB |

每次 51～107 秒（封裝含逐套服裝嚴格開卡）。依賴卡在讀卡器裡開卡顯示「OK card from OK data only (card pack mounted…)」，不讀 zipmod。圖：`Saved/OKBreed/family_tree.png`（清單 `Saved/OKBreed/family_cards.txt`，用上面的指令重產）。

### HairDeck 頭髮＋衣服混搭的大家族（2026-11-22，F）

同樣的家族結構重配一次：刻晴、雷電、惠惠、貞德先換上 HairDeck 頭髮（四張參考圖 `output/characters-2026-09-30-anime/references/0[1-4]-*.png` 生成，`ok-hair-pack card` 存成 `UserData/okbreed/hairdeck_family/*_hd.png`，讀卡器 MCP `breed_picture` 拍新頭髮的照片），胡桃、三月七保留原本頭髮。13 個孩子在讀卡器配出（每次 40～106 秒），其中 12 個帶著 HairDeck 頭髮：只有髮型來自三月七的那個沒有。上衣、下衣、內衣各自來自不同父母。命令列試配（刻晴 × 雷電，種子 102）時有兩套服裝因身體遮罩缺資料改回不混搭，封裝成功。

- 圖：`Saved/OKBreed/family_tree_hairdeck.png`（清單 `Saved/OKBreed/family_cards_hairdeck.txt`，第一行 `#title`、第二行 `#subtitle`）。家族樹工具在卡片帶 `okHk` 的照片左上角標「HairDeck 頭髮」。
- 讀卡器拍照時兩次出現 GPU page fault（D3D12 裝置遺失），都在換卡後幾秒內拍照時。是讀卡器已知的 DreamGUI PageFault（同一顆著色器 `E6753E1E…`、`fragment_02 @ 0x45f90`，見 [CARD_READER_DREAMGUI.md](CARD_READER_DREAMGUI.md)）：F 的引擎 `F:\UE5.8` 原本少了根因補丁 `ClearRecycledOnlineDescriptors.patch`，已補上；補上後用 RDG 並行執行連開仍會在第 11 張當，另開 session 追查中。

### 大圖：每張卡正面、側面、斜側面（2026-11-22，F）

使用者要「最終合出來的圖要大、人臉清楚、正面／側面／站姿斜側面」。每張卡在讀卡器拍三張（視窗 3200×2000，`鏡頭›全身`、`鏡頭›正面`，動作選單第 3 項 `custom_pose Stand_00_00` 站姿；正面、鏡頭 yaw −90 的側面、yaw +35 的斜側面，MCP `screenshot target=preview`，每張 1579×1876），合成時每張卡三格並排。

`breed_family_tree.lua --views <檔>`：一行「卡片路徑<TAB>正面<TAB>側面<TAB>斜側面」，截圖裁掉左右空白與右下角名牌（`CROP` 1180×1730），`--panel-height`（預設 1000）是每格在圖上的高度，字、線、間距照比例放大。圖約 13000 像素寬。圖：`Saved/OKBreed/family_tree_views.png`（清單 `Saved/OKBreed/family_views.txt`，截圖在 `Saved/OKBreed/views/`）。

## 打包版（2026-11-25，F）

使用者：「打包出來的 `CardReaderDevelopment.cmd` 要能正確配種成功」。在 `E:\OKPackage\Studio-20261124-release-e` 實際開讀卡器配了一次，抓到兩條只在打包版（或只在新庫）才出事的毛病。

### 1. 子卡光頭：接上去的原生材質頭髮被壓成 `opaque`，cooked build 整片不畫

**現象**：包裡配 `heroine_keqing × heroine_megumin`（兩張 OK 卡）成功生出孩子，log 寫著 `HairDeck hair mixed from both (father 59%)`、`HairDeck hair kept in the card (139705 bytes)`，但她一顯示就是光頭。log：

```
Part 18 (Tripo_Golden_Hair_25356) left out: Unsupported shared material family:
  part Tripo_Golden_Hair_25356 (hair_back, shader Shader Forge/main_hair_front)
```

**原因**：`portable_hair.rs` 的「沿用捐贈部件的原生髮材質」那一段複製了捐贈部件（`shader_kind` 1，`Shader Forge/main_hair*`）之後，把 `blend` 壓成 `opaque`。而 cooked build 只畫找得到共用母材質的部件：`OKRuntimeSharedMaterialRecipe`（[`KKRuntimeSharedMaterial.cpp`](../Plugins/KKRuntimePose/Source/KKRuntimePose/Private/KKRuntimeSharedMaterial.cpp)）認 `shader_kind == 1` 的條件是 **blend `masked` 且 unlit**，`opaque` 對不上任何家族 → 沒有母材質 → `ApplyPartMaterial` 在 `!WITH_EDITOR` 直接 `SetRenderInMainPass(false)`，整片頭髮不畫。編輯器（開發樹的讀卡器）走的是另一條：沒有母材質就臨時建一張材質圖，所以同一張卡在開發樹看起來是對的。**「開發樹能跑、打包版光頭」就是這個差。**

**修正**：那一段不再動 `blend`（`*p = d.clone()` 本來就帶著捐贈部件的 `masked`／unlit）。HairDeck 的色彩圖集每個取樣到的像素 alpha 都是 255，masked 的裁切不改變任何像素。同一段結尾加了一道攔截：`shader_kind == 1` 而 blend 不是 `masked`／不是 unlit 就直接報錯，不讓它再悄悄變成光頭。

舊卡不用重做：頭髮是開卡時才接上去的，程式修好，既有的子卡再開就有頭髮。

### 2. 原作卡配 OK 卡封不了卡：庫有了 mods 索引之後，新做的 OK 卡沒錄 `guids` 答案

**現象**：`Jeanne V1.11.png`（原作卡）× `heroine_megumin.png`（OK 卡）→ 封卡失敗，每一套服裝都是

```
the OK card has 1 unanswered question(s) its open needs: okLt guids (7): Jeanne_Cetol,com.DeathWeasel...
```

**原因**：OK 卡的嚴格開卡不准問庫的 mods 索引（`tree_answers::unanswered` 排在索引前面），答案一定要在卡裡。而 `mods.rs` 的 `find_guids_inner` 只在「掃整棵 mods 樹」那條路上 `record` 答案；自 2026-11-24 基礎庫帶了 `mods_index.db`（`modsindex::serves`）之後，錄答案那一次開卡從索引拿到答案就 `return` 了，**什麼都沒寫進卡**。於是那之後做的每一張 OK 卡都沒有 `guids` 那一列（`--oklib pack-keys` 看得到：一列都沒有），拿它去封卡（配種把原作卡臨時轉成的 OK 卡就是這種）就失敗。

**修正**：索引那條路也 `record`（兩條路共用 `record_guids`）。另外 `tree_answers::unanswered` 的缺口訊息現在會寫出**七個 guid 裡哪幾個從來沒被問過**（`never asked: ...`）——原本七個全印出來，看不出少的是哪一個。

修正後 `Jeanne V1.11 × heroine_megumin` 種子 77 一次封卡成功（`added zips=10 model records=2`）。

### 3. 髮型來自「頭髮是飾品做的」那一位：孩子一根頭髮也沒有，HairDeck 也接不上去

**現象**：包裡 `Jeanne V1.11`（原作卡）× `heroine_hu_tao`（OK 卡）→ 封卡、生出、載入都成功，`HairDeck hair kept in the card (111418 bytes)`，顯示出來還是光頭。log：

```
OK card HairDeck hair not applied: base has no hair material donor
  (parts: body:o_body_a:5:Koikano/main_skin, head:cf_... )
```

**原因**：胡桃的頭髮是**飾品**做的（`hair-check` 列出 `Hair (accessory, kind 1)`、`hair_0 (accessory, kind 1)`）。飾品跟著衣服那一方（這裡是母親貞德），髮型基因跟著「頭髮」那一組；孩子拿了胡桃的髮型編號、卻沒有胡桃的飾品，貞德自己的髮型又被蓋掉，於是孩子一個頭髮部件都沒有。接 HairDeck 頭髮要有一個「捐贈部件」當模板，沒有就整段放棄 → 連生成好的頭髮也沒戴上。

**修正**：沒有任何頭髮可當模板時，拿她的**頭**當模板複製一份新部件（頭本身不動），用 item shader 畫（`shader_kind` 8，cooked build 認得）。先前那張光頭的子卡不用重配，重開就有頭髮（`OKHAIRCHECK ok ... Tripo_Golden_Hair_19022 (hair_back, kind 8, opaque, unlit)`）。

髮型基因本身仍然照舊（「用飾品做的頭髮跟著衣服那一方」還在「未做」裡）：這一條只保證她不會光頭。

### 打包自檢裡的配種檢查

`Tools/package_studio_release.lua` 的自檢多一段（完整包與 `--program-only` 都跑）：用**包自己的** `ok-extract.exe` 與包的基礎庫，拿包裡最小的兩張 OK 卡配一個孩子 → 把前一步 HairDeck 自檢生出的頭髮裝進她（`--oklib hair-put ... {"native":true}`）→ `--oklib hair-check` 開孩子與兩位父母，要求每人都有一片畫得出來的頭髮。上面兩條都會讓它失敗：第 2 條在配種那一步，第 1 條在 `hair-check`（接頭髮時就報錯）。

新的兩個命令（讀卡器與自檢共用同一段程式）：

```powershell
.\Tools\ok-extract\target\release\ok-extract.exe X:/NoGame --oklib hair-put <卡> <cards_seed*.json|-> <輸出卡> [OPTS]
.\Tools\ok-extract\target\release\ok-extract.exe X:/NoGame --oklib hair-check <卡>...
```

`hair-check` 印 `OKHAIRCHECK ok|fail <卡> <說明>`，fail 的回傳碼非 0。

2026-11-25 晚改成**配三對**（挑四張自己有頭髮的卡，(1,2)、(3,4)、(1,4)），因為孩子會不會光頭看的是這一對：
髮型基因只帶遊戲的頭髮槽，頭髮是飾品做的那一位髮型欄位是空的。HairDeck 頭髮只裝進第一個孩子（那一步測的是
頭髮的材質，和配對無關）。`card_vf` 只在頭尾封口另有單元測試
（`portable_hairdeck.rs` `a_strand_is_capped_at_its_ends_only`），魚鱗面回來的話它會先失敗。

### 打包版的驗收（2026-11-25，F）

程式包 `Tools\lua\lua.exe Tools\package_studio_release.lua --tag BreedFix1125g --program-only --resources-from E:\OKPackage\Studio-20261124-release-e --out E:\OKPackage\Studio-20261125-program-f-breed2`（自檢全過，含新的配種那段：`breeding kks_KK_402071.png x crowd_C011.png` → 孩子 `OKHAIRCHECK ok`），疊到 `Studio-20261124-release-e` 上，用包的 `CardReaderDevelopment.cmd` 照玩家的操作（設為母親／父親、配種）配了五次，每次都生出、載入、拍照成功，log 裡 `left out` / `Unsupported shared material family` / `no hair material donor` 都是 0，**五個孩子都有頭髮**（讀卡器截圖看過）：

| 父母 | 種子 | 孩子 | 結果 |
|---|---|---|---|
| heroine_keqing × heroine_megumin（OK × OK） | 42 | Komazoku 刻min | 修正前同一張是光頭，修正後有頭髮 |
| Jeanne V1.11（原作卡）× heroine_hu_tao（OK） | 77 | 胡nne | 修正前封不了卡／接著光頭，修正後都好 |
| heroine_jeanne × heroine_raiden_shogun（OK × OK） | 303 | Jeagun | 好 |
| heroine_klara × heroine_alice（OK × OK） | 909 | Alice | 好 |
| heroine_keqing × heroine_megumin（OK × OK） | 55 | re 刻min | 好 |

建置：`cargo check --release`（預設與 `--no-default-features`）、`cargo build --release`、打包的第 3 步 `OpenKoikatsuEditor Win64 Development` 與第 4 步遊戲 `OpenKoikatsu` Development 都過。`cargo test --release --lib` 的既有失敗見 [ERROR_LOG](ERROR_LOG.md) 2026-11-24 那條。

包的基礎庫 `mods_index.db` 原本是 schema 1（11-24 那版程式寫的），新程式要 schema 2，驗收前用 `ok-extract <遊戲> --oklib mods-index <base_v1>` 重建過（舊檔留在 `mods_index.db.schema1.bak`）。下一個完整包會自己帶新的。

## 頭髮：光頭、大小與鱗片（2026-11-25 晚，F）

使用者在打包版配出來的孩子身上看到的，是三件各自獨立的事。十八張街頭女主角卡兩兩配九對，修之前有一對光頭，修之後九對全過
（`Tools\lua\lua.exe Tools\breed_hair_sweep.lua -Pairs 9 -Game <遊戲>`）。

### 1. 髮型基因只帶遊戲的頭髮槽，孩子就光頭

`lan × luo_tianyi_2024`：孩子開出來一根頭髮也沒有，`skip dummy hair id=500 cat=101 nohairB`。lan 的頭髮是飾品做的，
所以她的「髮型」欄位是空的（nohairB）；飾品跟著**基礎那一方的服裝**走，不跟髮型基因走。孩子抽到 lan 的髮型（空），
飾品又來自另一位（她的頭髮在槽裡，不在飾品裡）——兩邊都沒有。

修法：封完卡**實際開孩子**，沒有任何頭髮部件就把髮型改從另一位拿，重配一次（`breed.rs` `bald_card`，只重試一次；
兩邊都讓她光頭時維持原來的抽籤）。原本只有「她自己的髮型顯示不出來」(`hairstyle_gaps`) 的檢查，對「髮型本來就是空的」
這種無效。

「有沒有頭髮」的判定抽成 `portable::hairdeck::visible_hair_parts`：頭髮部件，或**不在** `non_hair_accessory_parts`
裡的飾品。原本 `hair-check` 只認 shader kind 1／10，把 Jeanne 用 `main_item`（kind 8）畫的 mod 頭髮判成光頭——
打包自檢會因此誤判，也會挑錯自檢用的卡。

### 2. 頭髮比頭小一圈（HairDeck）

子卡的 HairDeck 頭髮像頂小帽子蓋在頭頂，額頭與後頸露出頭皮。量出來：顱骨半寬 0.0817 m，髮絲只伸到 0.071 m。
`fit()` 按這顆頭的顱寬縮放，但從父母臉畫出來的髮型本身可能就比這顆頭窄。

修法：`build()` 在 fit 之後加一道覆蓋保證——髮絲伸出的最遠距離不到顱半寬時，整個 fit 繞中心放大到剛好蓋住
（上限 1.25 倍；本來就夠寬的髮型不動）。那張子卡 0.071 → 0.083 m。report 多 `cover_grow`、`widest_strand`。

### 3. 頭髮表面一片片「魚鱗」

每根髮絲是 4 頂點一圈的扁管。`card_vf` 原本**每一圈都封口**：一片橫向的四邊形卡在髮絲裡，和扁管的正面幾乎共面，
描邊外殼把它推出表面 → 滿頭橫向黑鱗片。只留頭尾兩個封口後乾淨了，順便省掉五分之一的三角預算
（每根 `2 + 10(n-1)` → `8(n-1) + 4`）。

### 看一張卡的頭髮怎麼坐在頭上

```powershell
.\Tools\ok-extract\target\release\ok-extract.exe <遊戲> --oklib hair-check <卡>...
```

印 `OKHAIRCHECK ok|fail`，每片頭髮的 shader kind、blend、三角數，以及 `fit scale`、`cranium_half_x`、頭與頭髮各自的
包圍盒和 `width ratio`。「頭髮大小不對」不必靠截圖，看這行就知道。

### 驗收（2026-11-25 晚，F）

- 九對（十八張街頭女主角卡）：修前 1 對光頭，修後 9/9 過。
- 那張帶 HairDeck 頭髮的子卡在讀卡器裡實拍（F 樹 Editor `-game`）：後腦勺的橫向黑鱗沒有了，瀏海是乾淨的髮絲；
  頭髮包住整顆頭，不再是蓋在頭頂的小帽子。截圖在 `Saved/BreedHairCheck/`。
- `cargo check --release`（預設與 `--no-default-features`）、`cargo build --release`、`OpenKoikatsuEditor` 與遊戲
  `OpenKoikatsu`（Win64 Development）都過。`cargo test --release --lib` 555 passed / 1 failed，那一條是
  [ERROR_LOG](ERROR_LOG.md) 2026-11-24 記過的既有失敗。
- F 樹的基礎庫本來沒有 `mods_index.db`（開發庫，mod 直接讀遊戲），讀卡器會整張卡擋下來；這輪用
  `ok-extract D:/KoikatuSunshinezz --oklib mods-index <base_v1>` 建了（7296 guids）。新 checkout 要開 OK 卡也得先建。

## 未做

- 資源包裁剪：匯出的完整卡帶所有祖先的整包資源，代數越多越大（第 4 代 145 MB；與服裝卡同一個待辦）。依賴卡不受影響。
- 孩子卡的父母卡被刪或搬走（相對位置也變）就開不了；讀卡器沒有「找父母」的介面，只在錯誤訊息列出找過的路徑。
- 在讀卡器編輯依賴卡後另存，會走「編輯過的 OK 卡」流程，結果是完整卡（不再依賴父母）。
- 卡片圖（`breed_picture`）是 T 字姿勢的正面照；三視角大圖用讀卡器的站姿另外拍。
- 用飾品做的頭髮跟著衣服那一方（飾品在服裝裡），不跟「髮型」基因走；要讓它跟頭髮走，得把頭部飾品從另一方的服裝搬過來。
- ABMX 骨骼、膚色貼圖疊加的混合；顯性／隱性等位基因（隔代遺傳）；能力值與比賽。
