# 人物编辑器对齐原作：**身体与脸部**的盘点与缺口清单

这一份只盘 **顔（脸）** 与 **体（身体）** 两个分页（2026-11-19 的分工：衣服与配件在
`CHARACTER_EDITOR_PARITY_CLOTHES.md`、头发与眼睛细节与外挂栏位在 `CHARACTER_EDITOR_PARITY_HAIR_EYES.md`，
三份格式相同、可以直接合成总表）。整体骨架（7 个分页、48 个分类、266 个颜色项）在
[CHARACTER_EDITOR_PARITY_PLAN.md](CHARACTER_EDITOR_PARITY_PLAN.md)。

## 一、来源与怎么重新算一次

原作程式码在本机 `D:\XKoikatuSunshine\kks_decomp`（**注意是 `XKoikatuSunshine`**；AGENTS.md／README 写的游戏
路径只是范例，实际路径是本机设定）。**原作程式码不进版控**，这份文件只记结构、项目名与资料键。

```powershell
.\Tools\lua\lua.exe Tools\scan_kks_editor_shape.lua -Markdown
```

[`Tools/scan_kks_editor_shape.lua`](../Tools/scan_kks_editor_shape.lua) 把每个分类的滑杆对到它写的体型索引。
配对**不是**照栏位宣告顺序：每个 `Cvs*.cs` 另外建一个 `sliders = new Slider[N] { ... }` 阵列，**那个阵列**才和
`arrIndex` 一一对应。照宣告顺序配会错——`CvsBodyShapeAll` 宣告 47 个滑杆但阵列里只有 44 个，顺序也不同
（2026-11-19 第一版就是这样错的，发出去之前抓到）。脚本会把阵列没收进去的滑杆单独列出来，不会悄悄吞掉。

自洽检查：脚本产出的资料键去重之后正好是 **52 个 `shape.face.*` ＋ 44 个 `shape.body.*`**，和
`cf_customhead.txt`／`cf_custombody.txt` 第一栏的最大索引（51／43）一致，也和我们现有的滑杆数一致。

## 二、结论（先讲，细节在后面）

1. **体型滑杆 96 项，资料端与 UI 都已经有，是完整的**：原作脸部 52、身体 44，我们的
   `shape.face.0..51`／`shape.body.0..43` 一一对应，读卡器也有这 96 个滑杆。
2. **非体型的细项（光泽、细节强度、胸部柔软度、痣／彩绘／晒痕／指甲／化妆等）资料端几乎都已经有**，
   因为 `appearance/properties.rs` 是**对卡片解码后的区段做通用走访**：face／body／hair／clothes／accessory／makeup
   里每一个数值、布林、颜色都会被列出来（体型值另走 `shape.*`，被明确跳过）。所以这一块的缺口**主要在 UI**：
   没有照原作的分类分组、没有原作的范围与预设、标签是通用推出来的。
3. **真正要注意的一个差异：滑杆范围。** 原作这 96 个滑杆是 **0–1**（画面显示 0–100），我们给的是 **−1–2**
   （ABMX 扩张，`OKCharacterMCPRegistry.cpp` 第 60 行）。要「和原作一样」的话，UI 预设该夹在 0–1，
   另给一个「扩张」开关才放到 −1–2。这是设计决定，不是 bug，但两边不讲清楚会对不起来。

这一节的「我们有没有」是**读我们自己的程式码判的**（`properties.rs` 的走访范围、`appearance.rs` 的
`targets()`、`Parameters()` 的 96 个滑杆），**没有逐项在跑起来的读卡器上点过**；逐项实测留到实作那一轮。

## 三、非体型细项：原作栏位 ↔ 我们的资料端

下面是「顔／体」两页的分类里**不是体型值**的滑杆与开关，以及它们在卡片里的栏位。
`properties` 的通用走访会把这些栏位列出来，所以标「资料端已有」。

| 原作分类 | 原作项目 | 种类 | 卡片栏位 | 我们 |
|---|---|---|---|---|
| 顔全体 | `sldDetailPow` 细节强度 | 滑杆 | `face.detailPower` | 资料端已有／UI 缺 |
| 顔全体 | 脸型选图 | 选图 | `face.headId` | 已有（`appearance` 的 `head`） |
| 顔全体 | 细节选图 | 选图 | `face.detailId` | 已有（`face_detail`） |
| 頬 | `sldGlossPow` 脸颊光泽 | 滑杆 | `face.cheekGlossPower` | 资料端已有／UI 缺 |
| 口 | `sldGlossPow` 嘴唇光泽 | 滑杆 | `face.lipGlossPower` | 资料端已有／UI 缺 |
| 口 | 虎牙 | 开关 | `face.doubleTooth` | 资料端已有／UI 缺 |
| ほくろ（痣） | 位置 X／Y、大小 | 滑杆 3 | `face.moleLayout` | 资料端已有／UI 缺 |
| ほくろ | 痣选图、颜色 | 选图＋颜色 | `face.moleId`／`face.moleColor` | 已有（`mole`） |
| メイク（妆） | 眼影／腮红／唇／脸部彩绘 | 滑杆 8、开关 7 | `face.baseMakeup`（含各层）、`face.lipLineId`／`lipLineColor` | 资料端已有／UI 缺 |
| 目② | 瞳孔大小与位置 | 滑杆 4 | `face.pupilWidth`／`pupilHeight`／`pupilX`／`pupilY` | **已有**（`eye_page page=eyes` 的 properties） |
| 目② | 左右眼同设定 | 开关 | `face.isPupilSameSetting` | 资料端已有／UI 缺 |
| 目② | 高光位置 | 滑杆 4 | `face.hlUpX`／`hlUpY`／`hlDownX`／`hlDownY` | **已有** |
| 目② | 眼睛画在最前 | 开关 | `face.foregroundEyes` | 资料端已有／UI 缺 |
| 体全体 | `sldDetailPow`／`sldGlossPow` | 滑杆 2 | `body.detailPower`／`body.skinGlossPower` | 资料端已有／UI 缺 |
| 体全体 | 肤色主／次 | 颜色 | `body.skinMainColor`／`skinSubColor` | 资料端已有／UI 缺 |
| 体全体 | 附加线条 | 开关 | `body.drawAddLine` | 资料端已有／UI 缺 |
| 胸 | 柔软度、重量 | 滑杆 2 | `body.bustSoftness`／`body.bustWeight` | 资料端已有／UI 缺 |
| 胸 | 乳晕大小 | 滑杆 | `body.areolaSize` | 资料端已有／UI 缺 |
| 胸 | 乳头光泽 | 滑杆 | `body.nipGlossPower` | 资料端已有／UI 缺 |
| 胸 | 乳头选图、颜色 | 选图＋颜色 | `body.nipId`／`body.nipColor` | 已有（`nipple`） |
| 爪 | 指甲光泽 | 滑杆 | `body.nailGlossPower` | 资料端已有／UI 缺 |
| 爪 | 指甲颜色 | 颜色 | `body.nailColor` | 资料端已有／UI 缺 |
| 下毛 | 选图、颜色 | 选图＋颜色 | `body.underhairId`／`underhairColor` | 已有（`underhair`） |
| 日焼け（晒痕） | 选图、颜色 | 选图＋颜色 | `body.sunburnId`／`sunburnColor` | 已有（`sunburn`） |
| ボディペイント | 两层的位置／大小、选图、颜色 | 滑杆 8、开关 4 | `body.paintId`／`paintColor`／`paintLayout`／`paintLayoutId` | 资料端已有／UI 缺 |

**两边都缺的目前只有一项候选**：原作「体全体」的骨骼类型（`body.typeBone`，体型骨架切换）我们 `card.rs`
读得到，但没有当成可编辑项暴露，也没有 UI。要不要做，要先确认它在 OK 卡上改了会不会和已经烘焙进卡的资源冲突。

## 四、体型滑杆逐项（96 项，脚本产出）

原作在「顔型全体」「体型全体」两页把同样的值再列一次（全部 52／44 项），所以下面只列**按部位分的那几页**；
那两张全表就是这 96 项的联集。所有项目：种类＝滑杆，原作范围 **0–1**（显示 0–100），我们的范围 **−1–2**，
预设值依性别与项目（`OKShapeDefaults::Value`），卡片里存在 `face.shapeValueFace`／`body.shapeValueBody`。

**顔／顔全体**（6 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldFaceBaseW` | `shape.face.0` |
| 2 | `sldFaceUpZ` | `shape.face.1` |
| 3 | `sldFaceUpY` | `shape.face.2` |
| 4 | `sldFaceUpSize` | `shape.face.3` |
| 5 | `sldFaceLowZ` | `shape.face.4` |
| 6 | `sldFaceLowW` | `shape.face.5` |

**顔／耳**（5 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldEarSize` | `shape.face.47` |
| 2 | `sldEarRotY` | `shape.face.48` |
| 3 | `sldEarRotZ` | `shape.face.49` |
| 4 | `sldEarUpForm` | `shape.face.50` |
| 5 | `sldEarLowForm` | `shape.face.51` |

**顔／あご**（8 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldChinLowY` | `shape.face.6` |
| 2 | `sldChinLowZ` | `shape.face.7` |
| 3 | `sldChinY` | `shape.face.8` |
| 4 | `sldChinW` | `shape.face.9` |
| 5 | `sldChinZ` | `shape.face.10` |
| 6 | `sldChinTipY` | `shape.face.11` |
| 7 | `sldChinTipZ` | `shape.face.12` |
| 8 | `sldChinTipW` | `shape.face.13` |

**顔／頬**（5 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldCheekBoneW` | `shape.face.14` |
| 2 | `sldCheekBoneZ` | `shape.face.15` |
| 3 | `sldCheekW` | `shape.face.16` |
| 4 | `sldCheekZ` | `shape.face.17` |
| 5 | `sldCheekY` | `shape.face.18` |

**顔／眉**（5 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldEyebrowY` | `shape.face.19` |
| 2 | `sldEyebrowX` | `shape.face.20` |
| 3 | `sldEyebrowRotZ` | `shape.face.21` |
| 4 | `sldEyebrowInForm` | `shape.face.22` |
| 5 | `sldEyebrowOutForm` | `shape.face.23` |

**顔／目①**（14 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldEyelidsUpForm1` | `shape.face.24` |
| 2 | `sldEyelidsUpForm2` | `shape.face.25` |
| 3 | `sldEyelidsUpForm3` | `shape.face.26` |
| 4 | `sldEyelidsLowForm1` | `shape.face.27` |
| 5 | `sldEyelidsLowForm2` | `shape.face.28` |
| 6 | `sldEyelidsLowForm3` | `shape.face.29` |
| 7 | `sldEyeY` | `shape.face.30` |
| 8 | `sldEyeX` | `shape.face.31` |
| 9 | `sldEyeZ` | `shape.face.32` |
| 10 | `sldEyeTilt` | `shape.face.33` |
| 11 | `sldEyeH` | `shape.face.34` |
| 12 | `sldEyeW` | `shape.face.35` |
| 13 | `sldEyeInX` | `shape.face.36` |
| 14 | `sldEyeOutY` | `shape.face.37` |

**顔／鼻**（3 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldNoseTipH` | `shape.face.38` |
| 2 | `sldNoseY` | `shape.face.39` |
| 3 | `sldNoseBridgeH` | `shape.face.40` |

**顔／口**（6 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldMouthY` | `shape.face.41` |
| 2 | `sldMouthW` | `shape.face.42` |
| 3 | `sldMouthZ` | `shape.face.43` |
| 4 | `sldMouthUpForm` | `shape.face.44` |
| 5 | `sldMouthLowForm` | `shape.face.45` |
| 6 | `sldMouthCornerForm` | `shape.face.46` |

**体／体全体**（2 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldHeight` | `shape.body.0` |
| 2 | `sldHeadSize` | `shape.body.1` |

**体／胸**（10 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldBustSize` | `shape.body.4` |
| 2 | `sldBustY` | `shape.body.5` |
| 3 | `sldBustRotX` | `shape.body.6` |
| 4 | `sldBustX` | `shape.body.7` |
| 5 | `sldBustRotY` | `shape.body.8` |
| 6 | `sldBustSharp` | `shape.body.9` |
| 7 | `sldBustForm` | `shape.body.10` |
| 8 | `sldAreolaBulge` | `shape.body.11` |
| 9 | `sldNipWeight` | `shape.body.12` |
| 10 | `sldNipStand` | `shape.body.13` |

**体／上半身**（8 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldNeckW` | `shape.body.2` |
| 2 | `sldNeckZ` | `shape.body.3` |
| 3 | `sldBodyShoulderW` | `shape.body.14` |
| 4 | `sldBodyShoulderZ` | `shape.body.15` |
| 5 | `sldBodyUpW` | `shape.body.16` |
| 6 | `sldBodyUpZ` | `shape.body.17` |
| 7 | `sldBodyLowW` | `shape.body.18` |
| 8 | `sldBodyLowZ` | `shape.body.19` |

**体／下半身**（8 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldWaistY` | `shape.body.20` |
| 2 | `sldBelly` | `shape.body.21` |
| 3 | `sldWaistUpW` | `shape.body.22` |
| 4 | `sldWaistUpZ` | `shape.body.23` |
| 5 | `sldWaistLowW` | `shape.body.24` |
| 6 | `sldWaistLowZ` | `shape.body.25` |
| 7 | `sldHip` | `shape.body.26` |
| 8 | `sldHipRotX` | `shape.body.27` |

**体／腕**（7 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldShoulderW` | `shape.body.37` |
| 2 | `sldShoulderZ` | `shape.body.38` |
| 3 | `sldArmUpW` | `shape.body.39` |
| 4 | `sldArmUpZ` | `shape.body.40` |
| 5 | `sldElbowW` | `shape.body.41` |
| 6 | `sldElbowZ` | `shape.body.42` |
| 7 | `sldArmLow` | `shape.body.43` |

**体／脚**（9 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldThighUpW` | `shape.body.28` |
| 2 | `sldThighUpZ` | `shape.body.29` |
| 3 | `sldThighLowW` | `shape.body.30` |
| 4 | `sldThighLowZ` | `shape.body.31` |
| 5 | `sldKneeLowW` | `shape.body.32` |
| 6 | `sldKneeLowZ` | `shape.body.33` |
| 7 | `sldCalf` | `shape.body.34` |
| 8 | `sldAnkleW` | `shape.body.35` |
| 9 | `sldAnkleZ` | `shape.body.36` |

## 五、分批顺序

1. **目②剩下的开关**（`isPupilSameSetting`／`foregroundEyes`）与 **ほくろ**的三个滑杆：最小，而且眼睛三页
   已经做完，接着补最省。
2. **胸**：柔软度／重量／乳晕大小／乳头光泽四项——使用者最容易注意到的身体细项。
3. **光泽与细节强度**六项（脸全体、脸颊、嘴唇、体全体、指甲、乳头）：同一种控制项，一次做完。
4. **ボディペイント**与 **メイク**：两层彩绘与化妆的位置／大小／颜色，项目多但都已在 properties 里。
5. **肤色与附加线条**：颜色类，跟第 3 项一起做也可以。
6. **滑杆范围的设计决定**（0–1 夹住、另给扩张开关）要先敲定，否则上面每一项的 UI 都要改两次。
7. `body.typeBone`：先确认影响再决定做不做。

每一项的 UI 侧由 e-fork-2 接，资料端若发现缺口由我补；目前盘下来资料端只有第 7 项是真的没有。
