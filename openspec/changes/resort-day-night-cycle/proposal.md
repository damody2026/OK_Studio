## Why

目前主地圖只有已保存的固定月夜：建築入口有122座庭園燈與122座步道燈，但尚未逐一設計戶外景點夜景，也沒有遊戲內連續時鐘。使用者希望全城戶外景點有渡假村夜燈，並具備完整0–24小時日照／月照；夜色清楚、步道可辨識，局部燈光與環境的反差柔和。

## What Changes

- 建立持續運行的日期／時間與太陽、月亮位置／月相系統，提供暫停、加速、指定時刻及跨日保存。
- 統一控制日光、月光、天空、環境補光、受限曝光、招牌與景觀燈；清晨和黃昏漸變，夜間有獨立的可讀性下限。
- 逐點覆蓋20個PK戶外空間、30個D景點裝置／19分區，以及海灣、旅館、商店街、住宅、交通入口與連接步道；使用完整ID清單防止漏景點。
- 設計暖色庭園燈、欄杆／座椅線光、遮光矮燈、柔和樹冠燈、雕塑洗光與低亮度水景燈；先調整現有燈，避免同位置疊加過亮。
- 建立夜間反差、動線淨空、逐時刻原生實拍、保存重開與效能預算的驗收。
- 使用者追加：全城深度衝突盤點，修正共面重複與過近表面，並以近遠移動、斜角及LOD切換實拍驗收z-fighting；必要原幾何修正逐項留存可回復記錄。

## Capabilities

### New Capabilities

- `city-day-night-cycle`：可保存、可控制的連續日期與全天日月天空模擬，包含受控的夜間可讀性和過渡。
- `outdoor-night-lighting`：所有登記戶外景點、景物與連接路線的分區夜燈、營業／深夜調光、視覺與效能驗收。

### Modified Capabilities

無現有主spec；本次兩項均為新增能力。

## Impact

- 目標：`StreetSocialCity/StreetSocialCity.uproject`及`/Game/UniversityCity/Maps/UniversityCity`，不是`StreetSocial.cmd`的街區demo。
- 擬新增獨立的`CityEnvironment` Runtime插件、環境控制資料資產與MPC；專案目前無頂層Source，已有`CityLocalization` Runtime插件可作建置模式參考，語言插件本身不混入環境邏輯。
- 安裝／驗收工具仍以Lua內嵌Unreal Python調用Editor；遊戲時鐘與燈光更新不依賴Editor Python。可共用的離線驗收工具採Rust。
- 遷移固定`CitySun`／`CityStreetFill`／`CitySkyLight`／`ResortMoonlight`／`ResortMoonBounce`與1957個夜景Actor的控制權；不重建122棟建築，不改427層與室內用途。
- 全部內容仍留本機，不提交StreetSocialCity；規畫階段不修改或保存主地圖。實作時重讀最新SHA，不把歷史備份覆蓋到其他作業的新內容。

本變更目前是規畫。設計、規格、覆蓋清單與任務完成，不代表全天系統或景點新夜燈已實作。
