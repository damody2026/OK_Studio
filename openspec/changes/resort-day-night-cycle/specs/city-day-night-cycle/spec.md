## Purpose

讓大學城在遊戲執行時具有連續的日期、時鐘、太陽與月亮運動、天空和照明過渡，並將日月位置的模擬與渡假村夜景的美術亮度分開控制，確保夜晚可辨識且不過暗。

## ADDED Requirements

### Requirement: Continuous civil time
系統 SHALL 支援本地時間0≤hour<24、日期、時區、暫停、時間倍率及指定時間；24:00等同下一日00:00，保存／讀取必須保留相同時刻。預設一個遊戲日為60個真實分鐘，並可調整；跨日不得把天體姿態重設到前一天。

#### Scenario: Midnight and save restoration
- **WHEN** 從23:59:59推進到下一秒，並保存後重開遊戲
- **THEN** 日期增加一天、時間為00:00:00，日月與景觀燈按恢復時刻重新求值，沒有一幀白晝或全黑閃爍

#### Scenario: Deterministic seek
- **WHEN** 暫停後依序跳至12:00、02:00、18:30，再返回02:00
- **THEN** 同一日期的02:00取得一致的日月方向、燈光目標值與曝光設定，不依賴走過哪些時刻

### Requirement: Independent solar and lunar simulation
系統 SHALL 按可設定的日期、經緯度、時區和世界北向獨立計算太陽與月亮的方位角、高度角、升落及月相；月亮不可固定為太陽反方向或永遠位於地平線上。月面亮側方向必須與太陽關係一致。月亮保留目前約6倍的美術視直徑，該放大不得改動日月位置資料或地面照度。

#### Scenario: Season and phase change
- **WHEN** 比較春分、夏至、秋分、冬至及新月、上弦、滿月、下弦日期
- **THEN** 日照長度、太陽路徑、月出月落與月相隨輸入改變；天體低於地平線時其直接照明平滑歸零

### Requirement: Coordinated appearance and visibility floor
系統 SHALL 讓天空、大氣、太陽、月亮、環境補光、曝光、月面／光暈、招牌及景觀燈使用同一時刻狀態。夜間必須有獨立於月亮可見性的環境亮度下限，維持步道、景物和人物輪廓；夜間天空色與平均亮度必須明顯低於日間，不得用無界自動曝光把深夜拉成白天。

#### Scenario: Moonless walk
- **WHEN** 無月、月落或新月的深夜沿主要步道行走
- **THEN** 環境仍有柔和夜間補光，可辨識路面與台階；天空保持夜色，燈具不形成孤立的白亮光島

#### Scenario: Twilight continuity
- **WHEN** 以正常速度或24倍速度經過日出、日落與午夜
- **THEN** 日月位置連續插值，天空、曝光與開燈權重平滑轉換，無突然換天空材質、雙太陽或雙月亮

### Requirement: Runtime and repeatable validation
系統 MUST 在打包執行時自行運行，不依賴Editor Python或外部程序。驗收 SHALL 包含每個整點0–23、日期跨午夜、正常與加速循環，以及角色穿越亮區／暗區的曝光表現；日月角度對參考資料在高度角絕對值大於5度時誤差≤0.25度，地平線升落時刻誤差≤5分鐘，且統一折射定義。

#### Scenario: Packaged daily cycle
- **WHEN** 在打包遊戲播放完整一日並執行保存／重載、暫停與時間跳轉
- **THEN** 所有環境狀態正確恢復，Runtime日誌與24個整點樣本可追溯到同一地圖與設定版本
