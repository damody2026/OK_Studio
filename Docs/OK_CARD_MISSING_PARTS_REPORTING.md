# 缺件回报：开卡少了东西，谁来说（2026-11-18）

记录「卡开起来少了部件，却没有任何一行讯息说出来」这个盲点的现况与量到的事实。头发那条的修法按使用者定的优先序
排在 OK 卡契约（`Docs/ERROR_LOG.md` 2026-11-18 demo_C050）与**转卡当下的缺口回报**之后，这份文件先把根因留着。

## 现在有哪几条回报通道

| 通道 | 在哪里 | 看得到什么 | 看不到什么 |
|---|---|---|---|
| 转卡的 `absent=` | `oklib.rs` `make_ok_card`（`LAST_ABSENT_ZIPMODS`、`okAb`） | 本机没有那个 zipmod、因此转进卡时就缺的部件 | 本机**有** zipmod、但开卡自己把部件跳掉的情况 |
| 严格开卡的缺口 | `okstrict.rs` | 卡内 `okLc`／`okLt` 答不出来的问题（开卡直接失败） | 「开得起来，只是少了一件」 |
| `--oklib outfit-gaps` | `outfit_gaps.rs` | 服装栏位指名了东西、而目录里查不到那一笔 | 目录查得到、但开卡阶段才跳掉的部件；以及 `id == 0` 的头发（直接 `continue`） |
| 读卡器的 sweep | `Tools/reader_package_sweep.lua` 的 `missing=` 栏 | 上面 `outfit-gaps` 那一类 | 同上 |

## 量到的事实：所谓「光头」的三种，其中只有一种是真的少东西

用 `ok-extract X:/NoGame --oklib strict-check <基础库> <卡>` 看开卡自己印的行（以 `E:\OKPackage\TestCards-20261118` 为例）：

```
kks_F_20240615   : skip dummy hair id=500 cat=101 nohairB
heroine_keqing   : skip dummy hair id=500 cat=101 nohairB
kks_anwa_subaru  : skip dummy hair id=990 cat=101 Twilek Head
```

- `id=500 nohairB` 是**原版的「没有后发」**那一笔：卡本身就不要后发。`heroine_keqing` 一样是这笔，而她头发好好的
  —— 她的头发是从配件槽来的（`outfit_gaps` 把这类归成 `hair_accessory`）。**这不是缺件，不该报。**
- `id=990 Twilek Head` 是一个 **mod 的头**挂在头发槽上，而那笔目录项的 `MainData` 就是 `p_dummy`：
  `is_dummy_part` 跳掉它是**和游戏一致**的（`ChaControl.ChangeHairNoAsync` 也只跳 `p_dummy`），这个 mod 的头是
  从别的槽（换头／换身体那套）来的，不是从头发槽。所以这一笔**本身不是缺件**。
  要判断她是不是真的少东西，得看那个换头的 mod 在不在，而不是看头发槽被跳掉。
  （2026-11-18 先写成「这是真的少东西」，是看到 `skip dummy hair` 就下结论，没去看 `is_dummy_part` 只认 `p_dummy`。）
  另外这两张（`kks_anwa_subaru`、`kks_F_20240615`）**不是 OK 卡**，是 `ref\KoikatuSunshine (2)\` 的原作卡直接开，
  所以它们的缺件回报属于「原作卡开卡」那一侧，按使用者定的优先序排在转卡侧之后。
- 第三种是 `outfit_gaps::of_outfit` 的 `if id == 0 { continue; }`：mod 盖掉原版 id 0 的发型时，卡上记的是 0，
  于是整笔被跳过。原本是为了别把「原版 id 0 是真发型」误报成缺件，代价是盖掉它的 mod 不在时也不报。

## 该报的条件

1. **非原版名字的 `skip dummy hair`**（`id=990 Twilek Head` 这类）要进缺件清单；`nohairB`／`nohairF` 这类原版的不报。
2. `id == 0` 的头发要看「有没有 resolve 指名一个 mod」：有 mod 指名而那个 mod 不在，就是缺件；没有就是原版发型，不报。
3. 回报的位置优先在**转卡那一侧**：一张卡转出来少了头发，使用者不该等到之后开卡才发现。

## `hair=` 栏为什么一直是 n/a

`reader_package_sweep.lua` 本来想用 MCP `reader_call geometry` 数头发件数，但那份 JSON 只有 `role`／`part`，
角色只分到 `body`／`head`，没有部件名字，数出来每张卡都是 0；改去数日志也会把上面那些 OK 卡数成 0。
**宁可写 n/a，也不要写一个会被当成「光头」的 0。** 要做对需要 MCP 多一个工具：
列出已载入角色的每个部件（role／category／slot／来源 GUID／mesh 名）。这件已回报给协调者。

## 真正光头的两张：`kks_Saria` 与 `kks_CharacterExport_Female`（2026-11-18 量）

两张都是**原作卡直接开**。拿装着游戏的那台（`D:\XKoikatuSunshine`）开一次、印出头发槽，两张**一模一样**：

```
hair id=500 cat=101 resolve=("yamadamod.nohairB", "nohairB", "ChaFileHair.HairBack", 500, 100083550, 101)  entry=None
hair id=0   cat=102/103/104  entry=("なし", "p_dummy")      → skip dummy hair
```

- 头发槽本身是**「没有后发」加三个「なし」**：卡自己就不要头发网格，这是设计，不是缺件。
- 她们看得到的头发**全部是 hair accessory 的 mod**：Saria 是 `com.DeathWeasel.AccessoryHairFront/Back`、
  `yamadamod.acchairF2`、`yamadamod.acchairP`、`cm3d201`；CharacterExport_Female 是 `Sny.Towa.Mod`、`aa001`。
  这台没有这些 zipmod → 没有头发 → **光头**。所以是第 (1) 类：**卡指名 mod 头发，本机没有那个 zipmod**。

### 但是回报在「没有游戏」那一侧会少掉

同一张 Saria：

| 开法 | 印出来的 `item missing` 行数 | 有没有 `part=hair` / `part=hair_accessory` |
|---|---:|---|
| 有游戏（`D:\XKoikatuSunshine`） | 17 | 有：`hair cat=101 guid=yamadamod.nohairB`、六笔 `hair_accessory` |
| 包里（基础库、卡旁没有 zipmod） | 4 | **都没有**，只剩 pantyhose、shoes_outer、两笔 accessory |

同一张卡、同一套 `outfit_gaps`，少了 13 行。原因在于基础库底下这些 id 在**目录里查得到**（库记着这些项），
于是不算缺口，但资料其实不在 → 部件没画出来、也没人报。**这就是使用者看到的「光头没人报」。**
转卡那一侧（一定有游戏与 zipmod）报得完整，所以要修的是「基础库底下开原作卡」的这条回报。
### 「4 行 vs 17 行」查清楚了：**不是没有游戏就读不出来，是那条检查问错了问题**

同一张 Saria、同一份基础库，三种开法：

| 开法 | `item missing` 行数 | 头发槽查到什么 |
|---|---:|---|
| 有游戏（`D:\XKoikatuSunshine`） | 17 | `entry=None` → 报 `part=hair guid=yamadamod.nohairB` |
| `--oklib replay <基础库>`（只有库，没有游戏） | 4 | `entry=Some(("なし","p_dummy",101))` → `skip dummy hair`，不报 |
| 包里的读卡器（同样只有库） | 4 | 同上 |

所以**没有游戏那一侧读得出卡指名了什么**（`hairresolve cat=101 slot=500 guid=yamadamod.nohairB` 照样印得出来），
不是资讯不够。两边差的是查表结果：库把 `101/500` 解成真正的 `なし`（`p_dummy`，设计上就不画），
有游戏那边的 GUID 查表反而失败成 `entry=None`，**多报的那一行其实是误报**。

真正的洞在另一个地方。Saria 有 15 个配件槽（大多挂在 `a_n_headside`，就是她的头发），在库底下开：

- 只有 `Saria_Acc_Mod` 那两个被报成 `item missing`；
- **其余 13 个槽既没有被报缺，也没有产生任何网格**（整份 log 里没有一行 accessory 的 `meshes=`），
- 原因是库的目录（`sources.okidx`）里**记着那些项**，连 zip 路径都给得出来
  （`probe replay 101 500` → `zip=base_v1\mods\Sideloader Modpack\yamadamod\[yamadamod]nohairB rev8.zipmod`），
  但 `base_v1\mods\` 这个资料夹**根本不存在**。查表成功 → 不算缺口 → 资料拿不到 → 部件没建出来 → **没有人说一句**。

**结论是 (b)：包里那条路径没走到该走的检查。** `outfit_gaps` 问的是「目录里有没有这一项」，
该问的是「卡要的这个槽最后有没有做出东西来」。按后者问，头发、头发配件、衣服全都涵盖，
也不会有有游戏那边的误报。

## 读卡时去哪里找 zipmod（2026-11-18 量过的现况）

开一张**原作卡**时（`oklib::open_original_card` → `with_zipmods`），按这个次序找：

| 次序 | 来源 | 由谁决定 |
|---:|---|---|
| 1 | **卡所在的资料夹**里的 `.zipmod`／`.zip`，以及它底下的 `mods/` 子资料夹 | 自动，不必指定 |
| 2 | 游戏目录 `mods/` 里**卡指名的** GUID 对应的那几个档 | 给了游戏目录（CLI 参数、`Config/DefaultGame.ini` 的 `Root`，或 `OK_GAME_ROOT`）时自动 |
| 3 | 游戏安装本身（卡没指名但开卡要用的东西、它的 UncensorSelector 设定） | 同上 |

**优先序是「卡旁边先」**，理由：使用者把 zipmod 放到卡旁边，是针对**这张卡**的明确指示；
游戏目录里的是全机器共用的、可能是别的版本。同一个 GUID 两边都有时，照这个次序先用卡旁边那份，
使用者不必动游戏目录就能修好一张卡。基础库自己记着的资料排在最前（它是已经转好的模型），
卡旁边的 zipmod 补的是库里没有的东西。

实测（`ok-card-open-bench --sequence`，就是读卡器开卡那条路）：洛天依 AI 那张卡（`ref/png/Koikatu_F_...洛 天依.png`）
指名 GUID `jq_lty_ai`，基础库没有它：

| 卡旁边放什么 | 缺件行数 | 开卡 |
|---|---:|---|
| 什么都不放 | 9（bottom、gloves、pantyhose、shoes_inner／outer、shorts、accessory、两个 top_sub） | 2.6 s |
| `jq_lty_ai.zipmod` | **0** | 5.6 s |
| `mods/jq_lty_ai.zipmod`（子资料夹） | **0** | 14.8 s |
| `九泉_洛天依_AI.zip`（副档名是 `.zip`） | **0**（2026-11-18 修好之前是 9） | 5.4 s |

最后一列是这次补的：`mods.rs` 的 `collect_zipmods_walk` 只认 `.zipmod`，而专案其他每一处
（`gamefs.rs`、`oklib_convert.rs`、`unity/references.rs`）都同时认 `.zip`，卡片包附的档又常是 `.zip`，
于是「把它丢在卡旁边」没有用。没有 manifest 的压缩档不宣告任何 GUID、也列不出东西，所以多看一眼不会有副作用。

## 给设定页的查询：`ok_zipmod_count`

使用者在新版 UI 的设定页选一个游戏目录之后，**不必等到开卡才知道选对没有**：

```
extern "C" int32_t ok_zipmod_count(const char* path);   // Unreal 直接宣告，不用 bindings table、不用 session
```

回传 ≥0 是那个目录 `mods/` 底下的 zipmod 数（目录名本身就是 `mods` 时直接算它），
**-2** 是「这路径底下没有 `mods/`」，**-1** 是「这路径读不到／不是资料夹」。CLI 同一条逻辑可单独试：

```
ok-extract X:/NoGame --oklib zipmods <目录>...
OKZIPMODS ok    D:/XKoikatuSunshine   7296
OKZIPMODS none  X:/NoSuchPlace        X:/NoSuchPlace is not a directory
```

开卡用的游戏目录由 Unreal 那一侧（`UKKGameRoot`：使用者设定优先、`Config/DefaultGame.ini` 的 `Root` 当预设）
在每次开卡时传进来，Rust 不自己记；没有设定（打包版 `-NoGameRoot`）时就只有「卡旁边」那条，**不是错误**。

## 记录等级：缺件不是 Error

缺件的行走 `ffi_log` 等级 0（Unreal 的 `LogOkExtract: Log`），讯息里也不再带 `ERROR` 字样：
一张卡指名了这台机器没有的 mod，是**预期内**的状况，说一声就好，不该混进「日志里的错误」里。
真正让开卡失败的（okstrict 的缺口、读不出来的资料）照旧是失败，会让开卡停下来。
`p_dummy`（`なし`、`nohairB`、`enk.acc.bald` 这种「这个槽就是空的」的目录项）照游戏行为跳过，
只留一行 verbose，不进缺件清单。

## 同一个 GUID 两边都有，谁赢

`oklib::with_zipmods_and`（`Tools/ok-extract/src/oklib.rs`）把三个 fallback 依序推进 `gamefs`，
先回答的那个赢：

1. `roots[0]` = 卡所在资料夹（`loose_mods: true`，含其 `mods/` 子资料夹）
2. `roots[1]` = 游戏目录里**卡指名的** GUID 那几个档（`card_zipmods`）
3. `roots[2]` = 游戏安装本身（`installation: true`，卡没指名但要用的东西与它的 UncensorSelector 设定）

所以**卡旁边那份赢**；基础库自己记着的（已经转好的模型）排在这三个之前。
OK 卡不走这条：它只读自己的 `okLc`／`okLt` 与基础库，连游戏目录都不看（`okstrict.rs`）。

## 哪些缺件只是回报，哪些会让卡开不起来

| 状况 | 结果 | 谁判的 |
|---|---|---|
| 原作卡指名的 zipmod 这台机器没有 → 那个槽没东西 | **回报**一行 `item missing …`，其余照开 | `outfit_gaps.rs` |
| 目录项是 `p_dummy`（`なし`／`nohairB`／`enk.acc.bald`） | **不算缺件**，只留一行 verbose（游戏本身就是跳过） | `extract.rs is_dummy_part` |
| 压缩档在、但里面没有这个部件的 mesh | **回报**，`why=its archive holds no mesh for it` | `accessory_extract.rs` |
| 部件建出来了、但材质家族没人支援 | **回报**一行 warning，该部件不画（整张卡照开） | `KKRuntimeSharedMaterial.cpp`；`--oklib crowd-check` 可不开 Unreal 先查 |
| **OK 卡**开卡时要读自己的 `okLc`／`okLt` 没记的东西 | **FAIL**：开卡停下并列出缺口，不回退去翻 mods 树 | `okstrict.rs` |
| 卡本身读不出来（PNG chunk、MessagePack、库缺档） | **FAIL** | `card.rs`／`oklib::ensure_library` |

判准是「画面少一块」还是「这张卡的资料不完整」：前者是使用者这台机器的 mod 状态，说一声就好；
后者表示 OK 卡或基础库坏了，必须停下来修（`demo_C050` 就是这一类，见 `Docs/ERROR_LOG.md` 2026-11-18）。

## 材质家族没支援，部件会被整个丢掉（2026-11-18 修）

`kks_Saria` 的眼线阴影 `cf_O_eyeline_kage` 在打包版留下唯一一条属于我们的 warning：

```
Unsupported shared material family: part cf_O_eyeline_kage (head, shader Koikano/main_eyew)
```

查出来**不是 `Koikano/main_eyew` 没支援**（`OKRuntimeSharedMaterialRecipe` 一直认得它，
对应 `KoikanoEyeWhite`），而是它要求那个部件是 `translucent` + unlit：

- Unity 把 `rendEyelineUp` 的 slot1（阴影）画在跟 slot0（眼线本身）同一个 submesh 上，
  `extract.rs` 当初就把**眼线的** blend 直接给了阴影部件。
- 这张卡的眼线被 Material Editor 换成 `KKUSS` 着色器（`masked`、lit），阴影自己的材质
  `cf_m_eyeline_kage` 仍是 `Koikano/main_eyew`。阴影于是拿到 `masked`，recipe 对不上，整个部件被丢掉。

修法：阴影部件用**它自己的材质**算 blend（`blend_for_mesh("head", &kage)`）。
量测（`ok-extract --oklib crowd-check`，不必开 Unreal）：

| 卡 | 修正前 | 修正后 |
|---|---|---|
| `kks_Saria` | `cf_O_eyeline_kage:Koikano/main_eyew:0:masked` | `-` |
| 其余 29 张测试卡 | `-`（`kks_haruno_chika` 另见下） | `-` |

顺手补的：`crowd-check` 的 `ANY_KIND` 少了 `Koikano/main_clothes_emblem`（C++ 那边 2026-11-17 加的），
`kks_haruno_chika` 的校徽被误报成不支援；已补上，现在 30 张全部 `-`。
**这张表是 C++ `OKRuntimeSharedMaterialRecipe` 的镜子，那边加一个家族，这边就要加。**

### 丢掉它对画面的影响：这张卡上量不到

同一个画面（开发版读卡器、`kks_Saria`、正面脸部、focus `[0,0,166]`／distance 55）拍三张：

| 图 | 内容 |
|---|---|
| `E:\OKPackage\EyelineKage\with_kage.png` | 修正前：部件在，但拿到眼线的 `masked` blend |
| `E:\OKPackage\EyelineKage\without_kage.png` | 临时把 `cf_O_eyeline_kage` 整个不输出 |
| `E:\OKPackage\EyelineKage\fixed_kage.png` | 修正后：阴影用自己的材质（`translucent`／unlit） |

三张**在脸上逐像素相同**（唯一差异是右下角 FPS 读数那块 28×30 像素）。
也就是说这张卡的眼线阴影本来就几乎看不见——她的眼线被 Material Editor 换成了 `KKUSS`，
`EyelineShadowTex` × 肤色在这个取景下没有可见贡献。

所以这个修正的价值不在画面变好看，而在：**打包版不会再因为它整个拒绝这个部件并留一条 warning**，
而且眼线没被换材质的一般卡片（阴影本来就是 `Koikano/main_eyew` + `_ALPHAPREMULTIPLY_ON` → translucent）
blend 完全没变——30 张测试卡 `crowd-check` 的结果除了 `kks_Saria` 之外一行都没动。
