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
