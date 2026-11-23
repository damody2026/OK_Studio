# 發佈包內的第三方資料與授權

這份清單隨發佈包放在 `Licenses/THIRD_PARTY.md`（由 `Tools/package_studio_release.lua` 放入）。

## HairDeck 權重（`HairDeckData/`）

讀卡器與 OK Studio 的「參考圖生成頭髮」、配種的頭髮混合用 `ok-hairdeck.exe`（本專案以 Rust 改寫的推論程式），它讀包根目錄的 `HairDeckData/`：

| 檔案 | 來源 | 授權 |
|---|---|---|
| `HairDeckData/ckpt/image_model`、`color_model`、`chain_model`、`card_vae`，`HairDeckData/data/*.json` | HairDeck（github.com/hyz317/HairDeck）發佈的權重 | Apache License 2.0，全文見 `Licenses/Apache-2.0.txt` |
| `HairDeckData/third_party/weights/dinov3/model.safetensors` | Meta DINOv3 ViT-L/16 | **DINOv3 License**，依其授權再散布，全文見 `Licenses/DINOv3-LICENSE.md` |

HairDeck 權重來自 Meta DINOv3 的部分依 DINOv3 License 再散布；使用、再散布或修改都要遵守該授權（包括隨附授權全文與其使用限制）。

## 沒有放進包的

- **影片匯入的權重**（SMPL-X、GVHMR 等）：SMPL-X 不允許再散布、GVHMR 只限非商業用途，所以發佈包不附，要使用者自備。見 `Docs/VIDEO_WEIGHTS.md`。
- **HairDeck 的 SAM 3、BiRefNet**：Rust 版不需要。
