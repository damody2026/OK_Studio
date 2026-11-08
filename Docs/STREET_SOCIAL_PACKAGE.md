# 街區打包（給別人玩的版本）

日期：2026-11-08。

`Tools/package_street_social.lua` 把街區打包成一個資料夾（可再壓成 zip），拿到的人用 `StreetSocial.cmd` 啟動。

```powershell
# 先檢查，不複製
.\Tools\lua\lua.exe Tools\package_street_social.lua --out D:\StreetSocialPackage --check
# 打包，可加 zip；--stage 不給就用 Saved/StreetSocial/Build 最新的 stage
.\Tools\lua\lua.exe Tools\package_street_social.lua --out D:\StreetSocialPackage [--stage <X.stage>] [--zip D:\StreetSocial.zip]
```

## 包裡有什麼

| 內容 | 來源 |
|---|---|
| 遊戲 | stage 的 `Windows/`（引擎執行檔、遊戲執行檔、pak）。stage 指向 Content 的兩個 junction（`IndependentResources`、`KKPreview`）不複製，拿到的人第一次啟動時由啟動器自動建立 |
| 執行期 patch | `Saved/StreetSocial/Build/StreetDisplay30Phys.patch` |
| 啟動器與工具 | `StreetSocial.cmd`、`Tools/lua/`、`Tools/*.lua`、原作資料清單（還原用） |
| 已建置的工具 | `ok_rules.dll`、`ok_mind.dll`、`ok_story.dll`、`ok-extract.exe`（對方沒有 cargo） |
| 語音伺服器 | `Build/ok-tts`、`Build/ok-asr`（不含模型與 log；`--no-voice-servers` 可不放） |
| 街區資料 | `Content/IndependentResources` 裡 **git 有追蹤**的檔案 |
| 設定檔 | 新玩家用的 `Saved/StreetSocial/player.json`：內建錄音配音、本機辨識，**金鑰空白**（[玩家設定檔](API_KEYS.md)） |

**不放：** 原作與 mod 資料（`Tools/original_data_manifest.json` 列的檔案、`base_v1`、`KKPreview` 等）、角色卡、存檔、TTS 快取、本機的金鑰。

拿到的人要做的事：
1. 用自己的遊戲還原原作資料：`Tools\lua\lua.exe Tools\original_data.lua restore --game <遊戲資料夾>`，見 [SHARED_RESOURCES_SETUP](SHARED_RESOURCES_SETUP.md)。
2. 準備自己的角色卡，放在 `Saved/StreetSocial/heroines.json` 指到的位置。
3. 要用 AI 對話或雲端語音的話，在遊戲左上角「⚙ 設定」填金鑰。

## 打包前的檢查（任一項不過就停止）

1. **pak 的內容**：用 UnrealPak 列出每個 pak。
   - 有原作資料轉出的資產 → 停止。
   - 有 git 沒追蹤的資產 → 停止，除非用 `--allow <資料夾>` 明確說明那是什麼。
   - cook 產生的檔案（AssetRegistry、Config、shader 庫）不算資產。
2. **金鑰**：找出這台機器上的金鑰，搜尋包裡每個文字檔，找到就停止。
   - 來源：各 `player.json`、舊的 `deepseek.json`／`api-keys.json`、環境變數 `DEEPSEEK_API_KEY`／`DASHSCOPE_API_KEY`。

## 目前的狀態（2026-11-08）

拿 C 組的 stage `nav1108n.stage`（大學城，pak 20 GB）跑 `--check`，結果是停止：

- pak 裡 cook 進了 18 個 `Content/Koikatsu/Data/*`（原作資料清單的 `unreal-catalog` 組：`DA_AnimationAndMouth`、`DT_animation_clips`、`DT_studio_catalog` 等）。要先讓 cook 不帶這些資產，才能打包。
- `Content/UniversityCity` 有 124,416 個資產沒進版控，需要確認來源後再決定能不能用 `--allow Content/UniversityCity` 放行。
- 這台機器上找到 2 把金鑰，包裡都沒有。
- 預估 4,645 個檔案、22.16 GB。

還沒實際複製出一份完整的包，也還沒在另一台機器上試玩過。
