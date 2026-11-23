# 影片匯入的權重要自備（發佈包）

讀卡器的「影片匯入」（`ok-video.exe`）用 GVHMR 從影片估計 3D 動作。它需要的模型權重**不能隨發佈包散布**，所以發佈包裡沒有，要使用者自己取得並放好。沒放好的時候，影片匯入面板會顯示「此功能需要自備 SMPL-X／GVHMR 權重」，這是正常狀態，不是程式壞了。

## 為什麼不附

| 權重 | 授權 |
|---|---|
| SMPL-X 人體模型（`body_models/smplx/SMPLX_*.npz`） | 要在 SMPL-X 官網註冊並同意授權才能下載，**授權不允許再散布** |
| GVHMR（`gvhmr/`）與它用到的 HMR2、ViTPose、YOLO 等權重 | GVHMR 的授權只允許教育、研究與非商業用途 |

所以影片匯入**只能用於非商業用途**。

## 怎麼取得

1. SMPL-X：到 SMPL-X 官網（smpl-x.is.tue.mpg.de）註冊、同意授權，下載 SMPL-X 模型（npz），把 `SMPLX_NEUTRAL.npz`、`SMPLX_MALE.npz`、`SMPLX_FEMALE.npz` 放進 `body_models/smplx/`。
2. GVHMR 與其他權重：照 GVHMR 專案（github.com/zju3dv/GVHMR）的說明下載 checkpoints，放成下面的結構。

## 放在哪裡

資料夾要長這樣（名稱是 checkpoints 資料夾裡的子資料夾）：

```
checkpoints/
  body_models/smplx/SMPLX_NEUTRAL.npz（及 MALE、FEMALE）
  gvhmr/
  hmr2/
  vitpose/
  yolo/
```

兩種放法，擇一：

- **放進發佈包**：把整個 checkpoints 資料夾放成 `<發佈包根目錄>\GVHMR\checkpoints\`。`ok-video.exe` 會從自己往上找這個位置。
- **放在任何地方**：設定環境變數 `OK_GVHMR_MODELS` 指向你的 checkpoints 資料夾，例如在 PowerShell 執行 `[Environment]::SetEnvironmentVariable('OK_GVHMR_MODELS','D:\GVHMR\checkpoints','User')`，再重新開讀卡器。

找的順序：`OK_GVHMR_MODELS` → 專案的 `local-instance.json` 的 `gvhmr_models` → 從 `ok-video.exe` 往上每一層的 `GVHMR\checkpoints` → `<專案>\ref\GVHMR\inputs\checkpoints`。要有 `body_models` 與 `gvhmr` 兩個子資料夾才算找到；找不到時面板會列出找過的位置。

開發環境的建置與流程見 [VIDEO_MOTION.md](VIDEO_MOTION.md)。
