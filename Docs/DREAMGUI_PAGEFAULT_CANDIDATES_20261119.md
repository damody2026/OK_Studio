# 读卡开卡时 GPU 页错误：候选清单与可检验性（2026-11-19）

> **档名归档用，内容已经不只是 DreamGUI 的事。** 这份从「DreamGUI 侧的候选」开始写，
> 但 **DreamGUI 这一支已被实测与读碼双向排除**：它每一条贴图绑定都持参照（§13a）、
> 四十秒的存活期把那张表变成排除证据（§13a 的更新）、卡片角色贴图没有任何路径进到 UI 绘製（§14b）、
> 而 brush 本身是强参照（§14c）。现在的主线是**消费端**（§15）。
> 档名没有改，因为别的 session 的纪录与讯息都引用这个路径。

只读调查，**没有改任何程式、没有建置、没有跑引擎、没有抢槽位**。下面全部是**候选与各自的检验方式**，
不是成因。被我查过而**查不出破口**的路径也照实列出来，免得下一个人重走一遍。

## 0. 现象（协调 session 转述，我没有自己复核过崩溃档）

- 读卡器开卡时 GPU 页错误；Aftermath 报的 shader 名是 `MainPS`，hash `E6753E1EA9F1F20775D8BC0AD963B1EF`，
  `"Shader name": "fragment_02"`；`Found 0 active heaps containing page fault address`。
- 约每次开卡 4%（`q̂≈0.039`，CI 0.015–0.096），**和哪张卡无关、和帧号无关**（frame 212–520）。

## 1. 先说两件会改变搜索范围的事实

### 1a. `MainPS` 不只一个 —— 这个名字指不到唯一的 shader

`F:\OpenKoikatsu\Plugins\DreamGUI\Source` 里**有四个 global shader 的进入点都叫 `MainPS`**：

| 类别 | usf | 怎么画 |
|---|---|---|
| `FDreamUIBasePS` | `DreamUIBase.usf` | **手录命令**（非 RDG）的内建 UI 画法 |
| `FDreamUICompositePS` | `DreamUIComposite.usf` | RDG pass |
| `FDreamUILayerStyleCompositePS` | `DreamUILayerStyleComposite.usf` | RDG pass |
| `FDreamUIBackdropCompositePS` | `DreamUIBackdropComposite.usf` | RDG pass |

所以「故障的 shader 是 `FDreamUIBasePS`」是一个**假设，不是读数**。它要紧：后三个取样的是
**RDG 的 pooled／transient 贴图**，而 transient 记忆体是**设计上就会被别人叠用**的那一类 ——
`Found 0 active heaps` 最自然的解释就是「这块位址已经不属于任何活着的 heap」。
`FDreamUIBasePS` 走的是手录绑定，两边要查的东西完全不同。

**先把身分定下来**，否则后面每一步都可能在查错的那个 shader。

### 1b. 协调指的 `FDreamUIDeferredRelease` / `GFrameNumberRenderThread`，**F 这份副本里没有**

`grep -rn "FDreamUIDeferredRelease\|GFrameNumberRenderThread" Plugins/DreamGUI/Source` 没有任何命中
（只有 `DreamUIManager_Tick.cpp`、`DreamTween` 与测试里不相干的 `DeferredRelease`／`GFrameNumber`）。
那两个名字应该是 **E 树为了诊断自己加的**。按指示我没有去读 E 树那份。

## 2. 候选，按「可能性 × 可检验性」排

### 候选 1：故障的其实是三个 RDG composite 之一，取样到被叠用的 transient 记忆体

- **对象**：RDG 的 pooled／transient 贴图（group 的图、backdrop 的拷贝、style 的中间图）。
- **哪里释放／重用**：RDG 自己的 transient allocator —— **同一块实体记忆体在同一帧内给不同 pass 轮用**。
- **MainPS 还可能引用到它的地方**：composite pass 把上一层的图当 SRV 取样。
- **少了什么保护**：如果某个 pass 读的贴图没有在 pass parameters 里宣告（RDG 就不知道它要活到那时），
  transient 会把那块记忆体判给别人。我在 `FDreamUIWorldRenderPSParameter` 与 `FDreamUIBackdropDrawPassParameters`
  里看到的宣告都是对的（见第 3 节），**composite 三个 pass 我没有逐一核对**。
- **检验（现成旗标，不用改程式，排第一就是因为这个）**：
  - `r.RDG.TransientAllocator 0` —— 关掉叠用。开卡 N 次，看 4% 掉不掉。
  - `r.RDG.ImmediateMode 1`、`r.RDG.Debug 1` —— 让越界引用当场露出来。
  - shader 身分：`r.DumpShaderDebugInfo 2` / `r.Shaders.Symbols 1` 后比对 hash `E6753E1E…`。
  - **阳性样本与趟数**：每个 cvar 都要先回读一次确认吃进去（那只排除打错字）；
    「关掉之后不崩」在 q≈0.04 下需要的趟数见
    [CRASH_FIX_EVIDENCE_MATH_20261119.md](CRASH_FIX_EVIDENCE_MATH_20261119.md)（95% 信心要约 75 趟），
    **十趟不崩什么都证明不了**。

### 候选 2：`FDataTextureResource::ReplaceTexture` —— 旧贴图在 render thread 当场放掉，reference 在 RHI thread 才改指

`Plugins/DreamGUI/Source/DreamGUI/Private/Core/DreamUIDataTexture.cpp:126-139`

```cpp
FTextureRHIRef Texture = RHICmdList.CreateTexture(Desc);
...
TextureRHI = Texture;                                  // 旧的 FRHITexture 当场掉一个 ref（render thread）
if (TextureReferenceRHI.IsValid())
    RHICmdList.UpdateTextureReference(TextureReferenceRHI, TextureRHI);  // 改指排进命令列，之后才执行
```

- **对象**：widget data／clip data／rect block data／paint data 这几张资料贴图的 RHI 贴图。
- **哪里释放**：`Grow_RenderThread`（`:57-70`）长高时 `ReplaceTexture` 重建，旧的在 **render thread 立刻**掉 ref。
- **MainPS 还引用它的地方**：`DreamUIRenderer.cpp:991-999` 把这几张**以 texture reference** 绑进 `MainPS`／`MainVS`。
- **少了什么保护**：放掉与改指**不在同一条时间线上**（一个 render thread、一个 RHI thread），
  中间这段只靠 D3D12 的 deferred deletion queue 撑着。这不是「一定会错」，是「保护来自别人而不是这段程式」。
- **和开卡的交集**：资料贴图是**部件变多就长高**的，重建卡片列表（开卡时的事）正好让它长。
- **检验**：
  - `r.DreamUI.RenderLayers 0` —— 把 render layer table／widget data 这条路整个拿掉（现成 cvar）。
  - 不改程式的量法：先把卡片列表整个滚完（资料贴图长到够高、不再 grow），**然后**才开卡 N 次，
    和「一开进来就开卡」比。注意没有 grow 的计数器，到达证据另缺（见第 4 节）。

### 候选 3：`RenewFontTexture` —— 旧的字体图集只 `RemoveFromRoot()`，由 GC 在不确定的时点收走

`Plugins/DreamGUI/Source/DreamGUI/Private/Core/DreamUIFontData_FreeTypeRender.cpp:3434-3468`

- **对象**：`UTexture2DArray` 字体图集（`MainPS` 的 `DreamUI_FontTex`）。
- **哪里释放**：图集要多一个 slice 时整张换新，旧的 `OldTexture->RemoveFromRoot()` 就算完，**没有等渲染**。
- **少了什么保护**：没有同步点；什么时候真的死掉由 GC 决定。
  原则上安全是因为**引擎**会在放掉贴图前清掉 reference（`F:\UE5.8\Engine\Source\Runtime\Engine\Private\Rendering\StreamableTextureResource.cpp:231-242`：
  `RHIClearTextureReference` 在 `TextureRHI.SafeRelease()` 之前）—— **保护又是来自引擎，不是这段程式**。
- **和开卡的交集**：开卡会画出新的字（卡名、标签、「正在打開」提示），新字形 → 新 slice → 换图集。
- **检验**：把专案设定 `Max Font Atlas Slices`（`UDreamUISettings::GetMaxFontAtlasSlices`）调大，
  让这次测试中不会换图集；或先把要用的字都显示一遍暖机。两种都不用改程式。

### 候选 4（低，但它是唯一「只有开卡才发生」×「释放／重用」的交集）：缩图用三秒计时器退场

`F:\OpenKoikatsu\Source\OpenKoikatsu\OKReaderScreen.cpp:1238-1251`

```cpp
void UOKReaderScreen::RetireThumb(UTexture2D* Texture) { RetiredThumbs.Add(Texture); RetiredThumbTimes.Add(Now); }
// Retired pictures go after three seconds (DreamGUI has redrawn the tiles without them by then).
```

- **对象**：`UTexture2D::CreateTransient` 做的卡片缩图（`:1216-1221`），被塞进 `UDreamImage` 的 brush，
  也就是 `MainPS` 的 `DreamUI_MainTex`。
- **哪里释放**：列表重建（`:1091`）或卷出视野（`:1264`）时退场，**三秒后**从 `RetiredThumbs` 移除交给 GC。
- **少了什么保护**：这是**计时器，不是同步**。它自己的注解就写明了危险：
  「DreamGUI's draw data built before the brush changed must not outlive its texture」。
- **为什么还是排低**：`CardThumbs`／`RetiredThumbs` 都是 `UPROPERTY`（`OKReaderScreen.h:210,220`），
  在手上时不会被 GC；而且引擎的 clear-before-release（上面那段）让 reference 不会指到死贴图。
- **检验**：三秒改大（要改程式，一行）；或**不改程式**的版本：开卡时不要卷动卡片列表、
  让列表不重建，退场根本不发生，再比 4% 有没有变。

### 低优先（不在交集内，但不删）

| 候选 | 为什么低 |
|---|---|
| `FDreamUILayerStyleComposite::ResolveTextures_RenderThread`（`:83-91`）抓的是 `Resource->TextureRHI` 原始 RHI 贴图而不是 reference | `PatternRHI` 是 `FTextureRHIRef`**计数持有**（`DreamUILayerStyleComposite.h:75`）：会**过期**，不会**悬空**。 |
| 字体图集的 staging texture pool（`DreamUIFontData_FreeTypeRender.cpp:2968-3030`）Acquire／Release | 那些贴图只当 `CopySrc`，**从来不绑进 PS**；它死了会错在 copy，不是 fragment。 |
| 材质路径的 `FMaterialRenderProxy` | 真要故障，faulting shader 会是材质自己的 PS，不叫 `MainPS`。 |
| `DreamVisualPostProcess` 的 proxy | 注解说这个坑已经修过（三方共享 `TSharedPtr`，最后一个 ref 在 render thread 销毁）。 |
| 采样器（`SamplerStateRHI` 原始指标） | sampler 是 static state，而且页错误位址落在 sampler heap 的话报法不一样。 |

## 3. 我查过、而且**查不出破口**的（别重走）

`MainPS`（指 `FDreamUIBasePS`）萤幕空间路径上每一个会被取样的槽，我都追到绑定点了：

| 槽 | 绑的是什么 | 结论 |
|---|---|---|
| `DreamUI_MainTex`／`FontTex`／`MaskTex0/1`／四张资料贴图 | `FTextureReferenceRHIRef`（`DreamUIRenderer.cpp:989-1000`） | reference 由 `FTextureReferenceRHIRef` 计数持有；贴图死时引擎**先清 reference 再放贴图**。查不出悬空。 |
| `DreamUI_SceneDepthTex` | 萤幕空间**传 `nullptr`**（`:2358-2360`）→ 绑 `GBlackTexture` | 读卡器的 UI 根本不取样场景深度。 |
| `DreamUI_BackdropTex` | RDG：pass parameters 有 `RDG_TEXTURE_ACCESS(BackdropTexture, SRVGraphics)`（`:845`），lambda 内 `MarkResourceAsUsed()` + `GetRHI()`（`:1589-1594`、`:2335` 起） | 教科书写法。 |
| 顶点／索引缓冲区、primitive uniform buffer | `FDreamUISectionDrawState`（`IDreamUIRendererPrimitive.h:38-56`）用 `FBufferRHIRef` 计数持有，batch 持 `TRefCountPtr` | 「pass 可能比 proxy 活得久」这件事作者已经处理过。 |
| 游戏执行绪快照 → render thread 解析 | 呼叫点（`DreamUIMeshComponent.cpp:697,1529,1597,2613,3174`）**都是在 enqueue 当下取快照**，解析就在那一条命令里 | 符合它自己宣告的不变式。 |

**没读的**：`DreamUIMeshComponent` 的 section pool 回收路径没有逐行读；三个 composite pass 的参数宣告没有逐一核对
（候选 1 就是这个缺口）。

## 4. 反向检查：交集必须成立

每次开卡约 4%，而 UI 每一帧都在画 —— 所以成因**必须落在**
「只有开卡才发生的事」∩「DreamGUI 的释放／重用」。目前能在程式里指名的交集只有：

1. **卡片列表重建 → 缩图退场**（候选 4，OK 自己的程式，唯一一个真正「只有开卡」的）。
2. **部件数量变多 → 资料贴图长高重建**（候选 2）。
3. **新字形 → 字体图集换新**（候选 3）。
4. **开卡把游戏执行绪卡住很久 → GC 落点与渲染的相对时序改变**（候选 1、3 都靠这个放大）。

不在这四项里的候选（上面的低优先表）**保留但压低**。

**还缺一个读数**：这三项都没有自己的到达证据（没有 grow／renew／retire 的计数器）。
要把「旋钮到达了」和「旋钮没效果」分开，得先有计数器，这需要改程式 —— **本回合没有改**。

## 5. shader 身分：离线能做到哪一步（第二轮，仍是只读）

### 5a. `fragment_02` 不是 `.usf` 里的名字，是 Aftermath 自己编的

引擎把 shader 注册给 Aftermath 的地方只有一处
（`F:\UE5.8\Engine\Source\Runtime\D3D12RHI\Private\D3D12NvidiaExtensions.cpp:40`）：

```cpp
RegisterShaderBinary(Value->Code.GetData(), Value->Code.Num(),
                     Value->HasShaderName() ? Value->GetShaderName() : nullptr);
```

`HasShaderName()` 看的是 `FRHIShader::Debug.ShaderName`（`RHI/Public/RHIResources.h:848-885`），
那个字串**只有在 shader 编译时带了 extra data 才会有**（`r.Shaders.ExtraData`，
`RenderCore/Private/ShaderCore.cpp:978-982`，是**编译期**的 shader format 设定，不是执行期开关）。
我们这次拿到的名字是 `fragment_02`，**完全不像 UE 的命名**（UE 的会是 `檔名.usf/進入點` 这种形状），
所以几乎确定是**传了 `nullptr`**、由 Aftermath 按「第几个 fragment shader」自己编号。

**所以 `fragment_02` 不含识别力，`MainPS` 也不含（四个 type 共用，见 1a）。**

### 5b. 那个 hash 是哪一种 hash

`E6753E1EA9F1F20775D8BC0AD963B1EF` 是 **32 个 hex ＝ 128 bit**。
UE 自己的 `FSHAHash` 是 **160 bit（40 hex）**，所以**这不是 UE 的 shader hash**，
对不进 UE 的任何表；它的长度与 **DXIL container 内嵌的 shader hash** 一致。
要对上，手里得有**那颗 shader 编出来的 DXIL bytes**。

### 5c. 现在这台机器上**办不到**离线比对，缺的是什么

`F:\OpenKoikatsu\Saved\ShaderDebugInfo\PCD3D_SM6\` 已经存在（28 MB），结构正是按**shader type 名**分目录：

```
Global/FOKGpuRigSkeletonCS/0/{CompileDXC.bat, DebugCompileArgs.txt, DebugHash_<64hex>, *.usf}
```

**但里面没有任何 DreamUI 的项目**（`ShaderTypeStats.csv` 里 `dream` 命中 0 次）——
那是前人某次针对性 dump 留下的，只有两颗 OK 的 compute shader。
所以**不跑引擎就比不出来**：缺的不是方法，是那四颗 shader 的 bytes。

### 5d. 可执行的下一步（都是旗标，不改程式；按便宜排）

1. **`r.Shaders.ExtraData=1`**（编译期设定，要让 shader 重编一次）→
   之后**崩溃档会直接印出 shader type 名**，不必再比 hash。这是最干净的一条。
2. **`r.ShaderDevelopmentMode=1`**：global shader 会自动 dump debug info
   （`ShaderCompiler.cpp:325-333` 的说明里写明了这一点），
   产物就会出现 `Global/FDreamUIBasePS/<permutation>/`，含 `CompileDXC.bat`
   → 用引擎自带的 dxc 重编那一颗，读 DXIL container 的 hash 去比 `E6753E1E…`。
   **风险要讲明**：UE 会对 container 再加工，重编出来的 hash **不保证**与执行期那颗相同；
   对不上**不能**当成「不是这颗」。
3. `r.DumpShaderDebugInfo=1` ＋ `r.DumpShaderOutputCacheHits=true`
   （`ShaderCompilerJobCache.cpp:109-114`，`ECVF_ReadOnly`，要走 ini／命令列）→
   **连 DDC 命中的也 dump 出 output bytecode**，这是真正那颗的 bytes，不是重编的。
4. 就算 type 定下来了，**还剩 permutation**：`FDreamUIBasePS` 有四个 bool 维度
   （`FBlendDepth`／`FDepthFade`／`FPlainColor`／`FBackdrop`，`DreamUIBaseShaders.h:142-151`）＝ 16 个；
   `FDreamUIBackdropCompositePS` 有 3×2×2×2 ＝ 24 个（`DreamUIBackdropEffects.cpp:139-144`）；
   `FDreamUILayerStyleCompositePS` 是 slots 的整数范围（`DreamUILayerStyleComposite.cpp:60`）。
   hash 指到的是「type ＋ permutation」，所以 type 级的答案只是缩小，不是终点。

**结论照实说：离线区分不了，必须开旗标让它自己说出来。** 这不是猜一个 type，是一个能做的下一步。

## 6. 缩图纹理那条路径——以及一处**和转述不符**的地方

### 6a. 它们在 DreamGUI 这一侧是什么

- `UTexture2D::CreateTransient(W,H,PF_B8G8R8A8)`，一张卡一个 UObject
  （`Source/OpenKoikatsu/OKReaderScreen.cpp:1216-1221`），SRGB，走一般 `UpdateResource`。
- 塞进 `UDreamImage` 的 brush（`:183`、`:244`、`:1084`），也就是 `MainPS` 的 `DreamUI_MainTex`，
  绑定方式是 **texture reference**（第 3 节）。
- **不是 pooled RT，不是每张一个 draw-call 专属 descriptor**：就是普通 UI 贴图，
  每张一个 RHI 贴图 ＋ 它的 view。

### 6b. 谁在什么时候释放

`RetireThumb`（`:1238-1242`）→ `RetiredThumbs` 保留 **3.0 秒**（`TickThumbnails`，`:1246-1251`）→ 移出阵列 → GC 收。
和 `FDreamUIDeferredRelease` 的关系：**没有关系，因为 F 这份副本里没有那个东西**（见 1b）。
这里唯一的「延后释放」就是上面那个三秒计时器，它在 **OK 自己的程式**里，不在 DreamGUI 里。

### 6c. 和转述不符：**读卡器并不是「为目录里每张卡持有一份缩图」**

程式里是**按视野**持有的（`TickThumbnails`，`:1252-1266`）：

- 距离 > `Far` 的格子**把缩图丢掉**（`:1264`）；只有距离 ≤ `Near` 的才去解码；
- 同时最多 **3 个解码在飞**（`:1270`）。

所以**活着的缩图张数由卷动视窗决定，不由目录大小决定**。
61 张 vs 30 张会不会因此翻倍，取决于「30 张是不是已经塞满那个视窗」——
**这一点我没有量，不能替它断定**。

**真正随目录大小线性成长的是另一样东西：DreamGUI 的 widget 数。**
卡片列表是**一张卡一个 `CardTile` 控件**（`:1534-1549`，上限 400 张），
所以 61 个档 ≈ 30 个档的两倍 widget。而 widget 数增加会推到的，是
**widget data／clip／rect block 这几张资料贴图的列数**→ `Grow` → `ReplaceTexture`（候选 2），
以及顶点／索引缓冲区的大小。**「累积压力越过门槛」对得上的是这一条，不是缩图张数。**

## 7. 哪一种耗尽最能自然产生 `Found 0 active heaps containing page fault address`

**先回答题目：不是「配额用光」那一类，而是「那块位址所属的 heap 已经不在活着的 heap 清单里」——
也就是 heap 被释放、或被 residency 逐出。** 理由：这句话说的是 **heap**，
而配额用光的典型症状是**建立失败／OOM／device removed 带别的理由**，不会是一个
「取样到一个不属于任何活 heap 的位址」的页错误。

按「最自然 → 最不自然」：

| 耗尽／释放的对象 | 会不会产生这句话 | 今天这台机器上的实际数字 |
|---|---|---|
| **bindless resource descriptor 的 GPU heap 被长大后释放** | **最自然**：descriptor heap 本身就是一个 heap；旧 heap 释放后，先前录好的命令列若还指著它，GPU 读到的就是不属于任何活 heap 的位址 | 今天的读卡日志：`Bindless is enabled (Configuration=RayTracing). Initializing allocators with 32768 Resource and 2048 Sampler descriptors`（`Saved/Logs/CardReader/20261119-165632-58ba874e.log:1065`）。长大与释放在 `D3D12BindlessDescriptors.cpp:230-251`（`ResizeGrowAndAllocate`）与 `:420-491`（`GarbageCollect`，`D3D12.Bindless.GarbageCollectLatency` 预设 **600** 个 cycle）。**释放前有 `check(!GpuHeap.bInUse)`**，所以这是候选、不是结论 |
| **residency 逐出**（记忆体压力下把 heap 逐出 GPU 可见记忆体） | **很自然**：heap 还在、但不 resident，访问它就是「没有活著的 heap 含这个位址」 | `D3D12.ResidencyManagement` 预设 **1**（`D3D12Adapter.cpp:32-35`，`ECVF_ReadOnly`）。引擎还自带一个专门用来复现它的旋钮：`D3D12.ResidencyDebugBudgetMB`，说明里写「Use a small value (e.g. 128) to force aggressive eviction/MakeResident churn」（`D3D12Adapter.cpp:206-209`） |
| RDG transient 叠用（候选 1） | 自然：叠用的那块记忆体在别人手上，原主人读到的就不属于自己的活 heap | 见候选 1 |
| descriptor **槽位**用光（不长大、直接回收槽位） | 不自然，而且**数字上排除**：硬体上限 `MaxNonSamplerDescriptors: 1000000`，实际配置 32768；缩图是按视野持有的几十张，单凭缩图推不到 32768 | 同上日志 `:1049`、`:1065` |
| 贴图记忆体用光 | **不自然**：会是建立失败／OOM，不是页错误 | — |
| 某个固定大小阵列满了 | 不自然：会是 check／越界，形状不同 | — |

### 7a. 这一条怎么检验（旗标，不改程式）

- **机制点读数（最重要，这是「到达」证据）**：`stat D3D12Bindless` ——
  stat group 里有 `Resource Heaps Allocated`（`D3D12Stats.h:45`）与 descriptor 配置数。
  **开卡时 descriptor 数有没有逼近 32768、heap 数有没有变**，是这条候选成立与否的直接读数，
  不是「设了 cvar 所以应该有效」。
- 把门槛推开：`D3D12.Bindless.ResourceDescriptorHeapSize` 调大（例如 262144）、
  `D3D12.Bindless.GarbageCollectLatency` 调到极大（旧 heap 永不释放）。
  两个都是 `ECVF_ReadOnly`，**要走命令列／ini，执行期 `game_exec` 设不进去**；
  到达证据就是启动那行 `Initializing allocators with N Resource`。
- residency 那一轴：`D3D12.ResidencyManagement 0`（关掉）、
  或反过来 `D3D12.ResidencyDebugBudgetMB 128`（**强迫 churn**）。
  后者是难得的**阳性方向**实验：如果 4% 跳到接近必然，就指向 residency；
  如果完全不动，这一轴就可以压低。
- 趟数照 [CRASH_FIX_EVIDENCE_MATH_20261119.md](CRASH_FIX_EVIDENCE_MATH_20261119.md)：
  q≈0.04 时「不崩」要约 75 趟才有 95% 信心；**而「强迫 churn 后崩得更凶」只要几趟就有力**，
  所以**先做阳性方向的那个**。

## 8. 这一轮改了什么判断

- 第 1 节那个「先定 shader 身分」仍然第一，但**方法从「离线比对」改成「开旗标让它自报」**：
  F 树上没有那四颗 shader 的 bytes，离线比对缺料。
- 候选 2（资料贴图 `Grow`／`ReplaceTexture`）**上升**：e-cardload 的 61 张三趟（位置 15／16／16、
  秒数 138.6–139.3，**协调转述，我未复核**）指向累积压力越过门槛，而随目录大小线性成长的是
  **widget 数**，widget 数正是这几张资料贴图的列数。
- 新增一条和 DreamGUI 无关、但最合「0 active heaps」字面的候选：
  **bindless descriptor GPU heap 长大后释放**（§7），它有现成计数器可读、有现成旗标可推门槛。
- 转述里「读卡器为每张卡持有一份缩图」与程式不符（§6c）：缩图是**按视野**持有的。

## 9. 把 bindless descriptor heap 读到底（第三轮）——**结论是它解释不了这个故障**

> **［前提已撤回，2026-11-19 晚］§9 与 §10 的推论，都建立在「`Found 0 active heaps` 是一个量测」这个前提上，
> 而这个前提没了。** e-cardload 在同一段报告里找到我们三个都跳过的一行：
> `PageFault: Logging all resource enabled: **No**`，后面三行全是 0（active resources／active heaps／
> released resources），`DRED: No PageFault data.`
> **三个零来自同一个没开的追踪**（§12b：追踪关着时 `SetHeap` 不取 heap 的 GPU 位址、不登记，那个查询必然回 0）。
> 所以那个零不是「找遍了都没有」，是「没有在找」。
>
> §9 的两个结论本身**仍然成立**，而且已被 e-cardload 的 log 实测佐证
> （`Configuration=RayTracing` → 图形侧不用 bindless；释放是 fence 门控不是帧数），
> **但它们当初是为了解释一个不存在的观测而写的**——把它们当成「这条路排除了」的纪录读，
> 不要当成「这条路曾经有证据」。§7 那张「哪一种耗尽最合这句话」的表同理：它整张都在解释那个零。

读的是 **F 组自己的引擎 `F:/UE5.8`**（`Tools\ok_engine.lua` 回报的就是这个；协调写的 `E:\PhysX\UE5.8` 是 E 组那份，我没读）。全部只读。

### 9a. 先讲结论，因为它会省掉两格实验

**今天的配置是 `Configuration=RayTracing`，而 `RayTracing` 这一级的 bindless 对「任何图形」都是关的**，
所以 **DreamGUI 的 `MainPS` 根本不从 bindless heap 读 descriptor**：

```cpp
enum class ERHIBindlessConfiguration { Disabled, RayTracing, Minimal, All };   // RHIDefinitions.h:1433-1445
inline bool IsBindlessEnabledForAnyGraphics(ERHIBindlessConfiguration C)
{ return C >= ERHIBindlessConfiguration::Minimal; }                            // RHIDefinitions.h:1462-1465
```

`RayTracing < Minimal` → `false`。而 resource manager 的建构子正是用这个判断决定要不要开 GPU heap：

```cpp
if (IsBindlessEnabledForAnyGraphics(GetConfiguration()))
{
    ActiveGpuHeapIndex = AddActiveGPUHeap();   // D3D12BindlessDescriptors.cpp:311-315
}
```

所以在这台机器今天的配置下，**bindless 的 GPU heap 只为 ray tracing dispatch 才会实体化**；
图形的 descriptor 走的是另一条路（online／local view heap，见 9d）。
**「开大 bindless heap」与「关掉 bindless」这两趟，量的会是 `MainPS` 不使用的东西。**
这条候选到此为止——**不是因为读不出来，是因为读出来了**。

### 9b. 长大与释放的路径（即使结论如上，纪录下来免得重查）

| 环节 | 程式 | 事实 |
|---|---|---|
| 容量从哪来 | `D3D12BindlessDescriptors.cpp:127-178` | 初始容量 ＝ `GBindlessResourceDescriptorHeapSize`；**32768 来自引擎自己的 `F:\UE5.8\Engine\Config\Windows\BaseWindowsEngine.ini:24`**，不是专案设的。上限 `MaxResourceHeapSize` ＝ 装置上限（今天日志 `MaxNonSamplerDescriptors: 1000000`） |
| 长大 | `:228-260` | 越过容量就 `ResizeGrowAndAllocate`：容量**翻倍**（32768→65536→…，上限 1M），重建 CPU heap 并复制，再 `bRequestNewActiveGpuHeap = true` |
| 撞到上限 | `:247-250` | `UE_LOGF(..., Fatal, "Hit D3D12 device limits on descriptors...")`——**是会带讯息的 Fatal，不是静默回收**。所以「槽位用光就重用」这个形状在这一版不存在 |
| 旧 GPU heap 怎么处置 | `:420-491`（`GarbageCollect`） | 不在用的先进 `PooledGpuHeaps`，再等 `GBindlessResourceDescriptorGarbageCollectLatency`（**600** 个 GC cycle）才 `SafeRelease()`。RayTracing 配置另有一条提早路：explicit heap 连 600 cycle 没用过就 `ReleaseGPUHeaps()` 全放 |
| `ReleaseGPUHeaps` | `:338-371` | `bInUse` 的走 `DeferredFreeHeap`（等 GPU 用完），**不在用的当场 `SafeRelease()`** |

### 9c. 核心问题的答案：**是 fence，不是帧数**

`bInUse` 只在 `Recycle()` 里被清掉（`:494-511`，而且前面有 `check(GpuHeap.bInUse)`），
而 `Recycle` 的唯一呼叫来源是**延迟删除佇列**：

```cpp
case FD3D12DeferredDeleteObject::EType::BindlessDescriptorHeap:
    ...GetBindlessDescriptorManager().Recycle(ObjectToDelete.DescriptorHeap);   // D3D12RHI.cpp:409
```

而那个佇列是在 `EnqueueEndOfPipeTask` 里跑的（`D3D12RHI.cpp:363-377`），它**对每一条 queue 都建一个
`ED3D12SyncPointType::GPUAndCPU` 的 sync point，并把全部 sync point 当成这个 task 的 prereq**
（`D3D12RHI.cpp:319-360`）。也就是：

> **清掉 `bInUse` 要等 GPU fence，不是等帧数。** 600 这个数字是**在 fence 之后再多等的那一段**，
> 不是唯一的保护。

所以**它和 `FDreamUIDeferredRelease` 不是同一个毛病形状**：那个（在 E 树）是帧数，这个是 fence。
「一帧很长、GPU 佇列很深」不会让它提早释放——fence 本来就是在等那件事。
另外 Development 建置里 `check` 是开的，`Recycle` 与 pool 回收各有一个 `check`，
**真要是顺序错了，会先看到 check 失败，而不是页错误**。这又是一条反对它的证据。

### 9d. 图形真正走的那条，以及「同一帧内配置又释放」在哪

这才是 `MainPS` 的 descriptor 来源：**online／local view heap 的环状配置**。
它**每条命令列都在配置、而且配完就等 sync point 回收槽位**——
也就是协调问的「同一帧内配置又释放」，在这条路上是**常态**，不是例外：

```cpp
void FD3D12LocalOnlineHeap::RecycleSlots()
{
    FSyncPointEntry SyncPoint;
    while (SyncPoints.Peek(SyncPoint) && SyncPoint.SyncPoint->IsComplete())  // D3D12DescriptorCache.cpp:1285-1294
    { SyncPoints.Dequeue(SyncPoint); FirstUsedSlot = SyncPoint.LastSlotInUse + 1; }
}
```

**也是 fence 门控**（`IsComplete()`），不是帧数。环绕用完会 `HeapLoopedAround`／`HeapRolledOver`（`:1265-1283`）。
所以如果要在「descriptor 被还在飞的绘製读到」这个形状上继续查，**该推的门槛是这一组，不是 bindless 那一组**。

### 9e. 开卡时谁大量配置 descriptor

- **每一个 SRV／UAV view 建立时都会拿一个 bindless handle**，闸门只看 descriptor 型别、**不看配置**
  （`D3D12View.cpp:215-237`）；`FRHITextureReference` 也各拿一个（`D3D12TextureReference.cpp:8`）。
  所以开卡（一张卡几百张贴图）＋ 61 张缩图**确实会把 32768 这个水位推高**，`stat D3D12Bindless` 看得到。
  **但推高的是 CPU 侧的那本帐**；在 RayTracing 配置下它不改变 `MainPS` 读到的东西（9a）。
- 图形这一侧：每条命令列从 online view heap 取槽位，每帧重来；卡片列表的 widget 愈多，
  每帧要绑的 view 愈多 → 环绕愈快 → 槽位回收压力愈大。**这一条才和「61 张更早当」同向**。

### 9f. 旗标清单（名称与预设都从这一版原始码抄的，附行号）

**全部 `ECVF_ReadOnly`** —— 只能在**启动时**经命令列或 ini 设定，执行期 `game_exec`／主控台设不进去。

| cvar | 预设 | 宣告 | 备注 |
|---|---:|---|---|
| `D3D12.Bindless.ResourceDescriptorHeapSize` | 1000000 | `D3D12BindlessDescriptors.cpp:11-17` | **但 Windows ini 覆写成 32768**（`Engine\Config\Windows\BaseWindowsEngine.ini:24`） |
| `D3D12.Bindless.SamplerDescriptorHeapSize` | 2048 | `:26-30` | ini 也写了 2048（同档 `:25`） |
| `D3D12.Bindless.GarbageCollectLatency` | 600 | `:19-24` | 单位是 GC cycle，不是帧 |
| `D3D12.Bindless.HeapUpdateUniqueUploadThreshold` | 1024 | `:34-40` | |
| `D3D12.GlobalResourceDescriptorHeapSize` | 1000000 | `D3D12StateCache.cpp:11-17` | **图形这一侧** |
| `D3D12.GlobalSamplerDescriptorHeapSize` | 2048 | `:19-25` | |
| `D3D12.LocalViewHeapSize` | 500000 | `:29-35` | **图形这一侧，9d 那条环** |
| `D3D12.GlobalSamplerHeapSize` | 2048 | `:37-43` | |
| `D3D12.OnlineDescriptorHeapSize` | 500000 | `:48-54` | **图形这一侧** |
| `D3D12.OnlineDescriptorHeapBlockSize` | 2000 | `:56-62` | |
| `D3D12.BindlessOnlineDescriptorHeapSize` | 500000 | `:64-70` | |
| `D3D12.BindlessOnlineDescriptorHeapBlockSize` | 2000 | `:72-78` | |
| `D3D12.ResidencyManagement` | 1 | `D3D12Adapter.cpp:32-35` | 关掉它＝不逐出 |
| `D3D12.ResidencyDebugBudgetMB` | -1（关） | `D3D12Adapter.cpp:206-209` | 说明写明「用小值（例如 128）强迫 eviction／MakeResident churn」——**阳性方向实验** |

**bindless 的开关不是 cvar，是两条路**：

1. **命令列参数**：`-BindlessOff`／`-BindlessRT`／`-BindlessMinimal`／`-BindlessAll`／`-Bindless`（＝Minimal）
   （`Runtime/RHI/Private/RHI.cpp:1130-1163`）。
   **重点警告：整段包在 `#if WITH_EDITOR` 里。** 读卡器平常是 `UnrealEditor.exe -game`
   （`CardReaderDevelopment.cmd` → `Tools/run_card_reader_development.lua`），那是 editor 建置，**旗标有效**；
   但若是从 package 跑（`Saved\StreetSocial\Build\*.stage` 里的游戏执行档），`WITH_EDITOR=0`，
   **这个旗标会静默无效**——到达证据就看启动日志有没有那行
   `Bindless is enabled (Configuration=...)` 跟著变。
2. **ini 设定 `BindlessConfiguration=`**，在 per-shader-platform 的设定区段里读
   （`Runtime/RenderCore/Private/ShaderPlatformConfig.cpp:27-67`；值的字串解析在
   `Runtime/RHI/Private/RHIStrings.cpp:774-801`）。
   **改它会改 shader 的编译设定 → 会触发 shader 重编**，这不是一个便宜的旋钮。

「不要长大、直接报错」**没有 cvar**：能不能长大是编译期巨集
`D3D12RHI_BINDLESS_RESOURCE_MANAGER_SUPPORTS_RESIZING`（`D3D12BindlessDescriptors.cpp:227`）。
撞到装置上限时本来就是 Fatal（9b）。

### 9g. 机制点读数（这些才是「到达」证据）

`stat D3D12Bindless`（stat group `STATGROUP_D3D12Bindless`，`D3D12Stats.h:45` 一带）里有：
`Resource Heaps Allocated`、`...HeapsActive`、`...HeapsInUseByGPU`、`Bindless Resource Descriptors Allocated`、
heap 的 GPU 记忆体用量。**开卡时 descriptor 数有没有逼近 32768、heap 数有没有变**，是这条候选的直接读数；
按 9a，就算读到它长大了，也不等于 `MainPS` 受影响。

## 10. 这一轮之后，候选剩下什么

- **bindless descriptor heap：降到最低**（9a：图形不读它；9c：fence 门控而非帧数；两个 `check` 会先炸）。
  **请不要拿它去跑那两格实验。**
- **同形状但图形真的在用的那条**：online／local view heap 的环状槽位回收（9d）。
  它也是 fence 门控，所以**不是现成的毛病**，但它是「还在飞的绘製读到被重用的 descriptor」这个假说
  在这台机器上**唯一真的相关**的实作；要推门槛就推 `D3D12.OnlineDescriptorHeapSize`／
  `D3D12.LocalViewHeapSize`／`D3D12.OnlineDescriptorHeapBlockSize`。
- **residency 逐出**（§7）：**现在是最合「整个 heap 不在了」而又还没被排除的那一个**，
  而且 `D3D12.ResidencyDebugBudgetMB 128` 是**少数能往阳性方向推**的实验（强迫 churn 看 4% 会不会跳）。
  建议把原本要给 bindless 的两格实验改到这里。
- 候选 1（RDG transient 叠用）与候选 2（资料贴图 `ReplaceTexture`）不受这一轮影响。

## 11. 引擎身分比对：**两棵引擎在这些档上位元组相同，§9 的结论直接适用**（2026-11-19）

协调指出我读的是 `F:/UE5.8`、而 e-cardload 跑的是 `E:/PhysX/UE5.8`，要求先排除身分问题。比完了：

### 11a. 两棵 checkout

| 项目 | 结果 |
|---|---|
| `git rev-parse HEAD` | **两边同一个 commit**：`11576da863ff7a31b0e6763e06f49180a2696023` |
| `git status --porcelain`（E 那棵） | **干净**，没有未提交改动 |
| 我引用过的 **21 个档**的 md5 | **全部 SAME**（下表） |

逐档（`Engine/` 起算，F:/UE5.8 vs E:/PhysX/UE5.8，md5 相同）：
`Config/Windows/BaseWindowsEngine.ini`、
`Source/Runtime/D3D12RHI/Private/` 的 `D3D12BindlessDescriptors.cpp`／`.h`／`D3D12StateCache.cpp`／
`D3D12Adapter.cpp`／`D3D12RHI.cpp`／`D3D12View.cpp`／`D3D12DescriptorCache.cpp`／
`D3D12TextureReference.cpp`／`D3D12NvidiaExtensions.cpp`／`D3D12Stats.h`、
`Source/Runtime/RHI/` 的 `Public/RHIDefinitions.h`／`Private/RHI.cpp`／`Private/RHIStrings.cpp`／`Public/RHIResources.h`、
`Source/Runtime/RenderCore/Private/` 的 `ShaderPlatformConfig.cpp`／`ShaderCore.cpp`、
`Source/Runtime/Engine/Private/` 的 `Rendering/StreamableTextureResource.cpp`／`Texture.cpp`／
`ShaderCompiler/ShaderCompiler.cpp`／`ShaderCompiler/ShaderCompilerJobCache.cpp`。

**所以 §9 的三个结论（bindless 在 RayTracing 级不覆盖图形 descriptor、释放是 fence 门控不是帧数、
预设配置等级与 32768 的来源）对 e-cardload 的趟次同样成立。**

### 11b. 哪一棵是谁在用（读设定档，不是推测）

- `Tools/lua/ok/init.lua:62-68`：顺序是 `OK_ENGINE_ROOT` → `Tools/engine.local.json` → **预设 `E:/PhysX/UE5.8`**。
- F 树有 `Tools/engine.local.json` ＝ `{"engine": "F:/UE5.8"}` → F 用 F:。
- **E 树没有 `Tools/engine.local.json`**，环境变数也没设 → **E 用预设 `E:/PhysX/UE5.8`**。
- 两棵树的 `Tools/ok_engine.lua` 本身 md5 相同。

### 11c. 更强的一条证据：**E 自己那一趟的日志**

`E:\OpenKoikatsu\Saved\Logs\CardReader\20261119-195124-29f15007.log:1071`

```
LogD3D12RHI: Bindless is enabled (Configuration=RayTracing). Initializing allocators with 262144 Resource and 2048 Sampler descriptors
```

- **配置等级在它那边也是 `RayTracing`**（不是 Minimal／All），所以 §9a 的判断在它的趟次上成立。
- 它的旋钮**确实到达**（命令列同时打了 `[ConsoleVariables]` 与 `[SystemSettings]` 两个，init 印 262144）。
- 但按 §9a，**到达的是一个 `MainPS` 不使用的机制**：
  `IsBindlessEnabledForAnyGraphics(RayTracing) == false`，图形不从 bindless GPU heap 读 descriptor。
  **这正是「旋钮到达了，但到达点不是机制作用的那一点」**——旋钮回读正确，不代表这趟能回答那个问题。
- 附带注意：它那趟还打了 `-ini:Engine:[ConsoleVariables]:r.RDG.ParallelExecute=0`。
  那是**另一个旋钮**，和候选 1 要推的 `r.RDG.TransientAllocator` 不是同一件事，别混成一个差值。

### 11d. 这次比对**没有**覆盖什么

- 只比了**原始码与引擎 ini**。两棵树的**建置产物是各自编的**（`F:/UE5.8/Engine/Binaries/...` 与
  `E:/PhysX/UE5.8/Engine/Binaries/...`），我没有比 exe／dll，也没有比各自的建置设定。
  同 commit ＋ 同源码 ⇒ 行为应当相同，但这是**推论**，不是量到的。
- E 的专案 `Config/` 与 `Saved/Config/` 里**没有**任何 `Bindless`／`D3D12.` 覆写（这次读的时点）；
  它的 262144 是走命令列。**只有 `BindlessConfiguration=` 被改才会翻掉 §9a**，而没人改它。

## 12. `Found 0 active heaps containing page fault address` 到底在说什么

**这句话是 UE 自己印的，不是 Aftermath。** 出处：

```cpp
// F:\UE5.8\Engine\Source\Runtime\D3D12RHI\Private\D3D12Util.cpp:703-710
TArray<FD3D12Heap*> OverlappingHeaps;
InAdapter->FindHeapsContainingGPUAddress(InPageFaultAddress, OverlappingHeaps);
UE_LOGF(LogD3D12RHI, Error, "PageFault: Found %d active heaps containing page fault address", OverlappingHeaps.Num());
```

### 12a. 它列举的是哪一种物件（问题 1）

`FD3D12Heap`，也就是 **D3D12 的记忆体 heap（`ID3D12Heap`）**——**协调的猜测是对的，不是 descriptor heap。**
比对方式是纯位址区间（`D3D12Adapter.cpp:2062-2077`）：

```cpp
for (FD3D12Heap* AllocatedHeap : TrackedHeaps) {
    FInt64Range HeapRange(VA, VA + AllocatedHeap->GetHeapDesc().SizeInBytes);
    if (HeapRange.Contains(InGPUVirtualAddress)) OutHeaps.Add(AllocatedHeap);
}
```

清单是 UE 自己的登记簿 `TrackedHeaps`（`TrackHeapAllocation`／`ReleaseTrackedHeap`，`D3D12Adapter.cpp:1999-2026`），
不是向驱动或 Aftermath 查询。

### 12b. 「0 个」有多少推论力（问题 2）——**比看起来弱很多，有四个独立的理由**

登记的闸门在 `FD3D12Heap::SetHeap`（`D3D12Resources.cpp:703-745`）：

```cpp
if ((bForceGetGPUAddress || Adapter->IsTrackingAllAllocations())
    && !(HeapDesc.Flags & D3D12_HEAP_FLAG_DENY_BUFFERS)
    && HeapDesc.Properties.Type == D3D12_HEAP_TYPE_DEFAULT)
{   ... GPUVirtualAddress = TempResource->GetGPUVirtualAddress();
    if (bTrack) Adapter->TrackHeapAllocation(this); }
```

1. **没取到 GPU 位址的 heap 根本不会进登记簿。** 条件是
   `bForceGetGPUAddress || IsTrackingAllAllocations()`。而**池化配置器建 backing heap 时没有传
   `bForceGetGPUAddress`**（预设 false：`D3D12PoolAllocator.cpp:106`、`:503`、`D3D12Allocation.cpp:325`）；
   只有 `D3D12Resources.cpp:527` 与 `D3D12TransientResourceAllocator.cpp:81` 传了 true。
   **所以在「没开全追踪」时，一般贴图所在的那些池子的 heap 是看不见的，0 几乎是空话。**
2. **「有没有开全追踪」这件事，崩溃档在前两行就印了**：
   `PageFault: Logging all resource enabled: Yes/No`（`D3D12Util.cpp:670`）。
   它的值是 `bTrackAllAllocation = (D3D12.TrackAllAllocations || UE::RHI::UseGPUCrashDebugging() || memtrace)
   && GetResourceHeapTier() == TIER_2`（`D3D12Adapter.cpp:1532`，cvar 在 `:189-192`）。
   **拿这个 0 推论之前，先看那一行是 Yes 还是 No。**
3. **committed resource 不是 heap。** 独立配置的贴图走 `CreateCommittedResource`，没有独立的 `ID3D12Heap`
   登记项；它被销毁后页错误落在那里，**就算全追踪开着也会印 0 active heaps**。
   这类情形该看的是另外两行（12c）。
4. **UPLOAD／READBACK 型别的 heap 永远不登记**（上面条件写死 `HEAP_TYPE_DEFAULT`）。

**所以这句话的正确读法是：「这个位址不在任何一个**有登记的 DEFAULT 型别 heap** 的区间里」，
不是「有一整个 heap 不见了」。** 它**不能**单独支撑「整个 heap 被销毁」这个结论。

### 12c. 真正会指名凶手的是同一个函式印的另外两行——**而且已经在档里了，零机器成本**

`LogPageFaultData` 一共印三组。请把这三组**原文**拿来（不要只转述其中一行）：

| 行 | 程式 | 它说什么 |
|---|---|---|
| `PageFault: Found %d active tracked resources in 16.00 MB range of page fault address` | `D3D12Util.cpp:675-700` | 附近还活着的资源，每笔带 **Name／Desc／Size／距离／`Transient:` 旗标** |
| `PageFault: Found %d active heaps containing page fault address` | `:703-710` | 就是这次讨论的那一行 |
| **`PageFault: Found %d released resources containing the page fault address during last 100 frames`** | **`:712-737`** | **近 100 帧内被释放、而且区间含这个位址的资源**，每笔带 **Name／Desc／Size／`FrameID`（哪一帧释放的）／`DefragFree`／`Transient`／`Heap`** |

最后那一行是整件事里**唯一会直接指名**的读数（资料来自 `FindReleasedAllocationData`，`D3D12Adapter.cpp:2079-2092`）。
另外若 DRED 开着，还会有 `DRED: Recent freed objects with VA ranges that match the faulting VA:`（`:602-615`）。
**在跑任何新实验之前，先把这几行读出来**——它比任何一格旗标实验都便宜。

### 12d. 哪些配置器真的销毁、哪些只是回收重用（问题 3）

协调那个推理**成立**：池化重用不会页错误（位址还在活著的 heap 里，只是内容变了），**只有真的销毁才会**。
分类如下：

| 路径 | 销毁 or 重用 | 程式 | 对「0 active heaps」的意义 |
|---|---|---|---|
| **committed／standalone 资源**（独立配置的贴图） | **真销毁**：记忆体还给驱动 | `CreateCommittedResource`（`D3D12Texture.cpp:111` 一带的注解） | **最符合**：位址不属于任何 heap，也不属于任何登记项 |
| **`FD3D12PoolAllocator`（placed，一般贴图／缓冲区）** | **重用**：区块还给池子，heap 留着 | 释放是 **frame fence 门控**（`D3D12PoolAllocator.cpp:788-812`）；**整池空掉**才 `MemoryPool->Destroy()`，而且还要等 `LastUsedFrameFence + FrameLag <= CompletedFence`（`:850-855`） | 重用时位址仍在 heap 内 → 会印 ≥1（前提是那个 heap 有登记，见 12b.1）。只有整池销毁才会变 0 |
| **upload heap allocator** | 重用 | `CleanUpAllocations(FrameLag)`，`FrameLag = 20` 写死（`D3D12Adapter.cpp:1841-1842`） | upload 型别本来就不登记 |
| **RDG transient allocator（候选 1）** | **重用／叠用**，backing heap 一直活着 | `D3D12TransientResourceAllocator.cpp:81` 建 heap 时传了 **`bForceGetGPUAddress = true`** → **一定有登记** | **所以 transient 叠用造成的页错误会印 ≥1 active heap，不是 0。这一行反过来压低了候选 1。** |
| **pooled RT（`GRenderTargetPool`）** | 重用 | — | 同上，位址仍属活着的配置 |

**结论：候选从「重用太早」收窄到「真的删太早」，而真删的主要形状是 committed 资源。**
（**我没有读**「UE 什么时候把贴图配成 committed、什么时候配成 placed」那段决策，
所以**不能**替它断定缩图或卡片贴图属于哪一类——那是下一步要读的。）

### 12e. `FDreamUIDeferredRelease` 属于哪一类（问题 4）——**在 F 这份副本里读不到**

`FDreamUIDeferredRelease`、`Frames.Texture`、`NeverDeleteProxy` 在
`F:\OpenKoikatsu\Plugins\DreamGUI\Source` 里**一个都没有**（§1b 已查）。那是 E 树自己加的诊断，
按指示我没有读 E 树那份，**所以这一题我答不出来**，要由能读 E 那份 DreamGUI 的人回答。

能从引擎这边说的是：**延后几帧本身不决定「销毁 or 重用」。**
到期之后它放掉的是 RHI 物件的参考，之后走 UE 的延迟删除（end-of-pipe、**fence 门控**，§9c），
而那条路最后是**真销毁还是还给池子，取决于这个资源当初是怎么配置的**（committed → 真销毁；
placed／池化 → 还给池子、heap 留着）。所以要判它，得先知道它放掉的那些贴图走哪一条配置路径——
换句话说，**问题 4 的答案依赖 12d 里我还没读的那段决策**。

## 13. 有真资料之后：那张 `B8G8R8A8_TYPELESS` 是谁的，以及谁在不持参照地绑它

新事实（协调转述 e-cardload 的两份追踪报告，我未复核报告原文）：故障位址落在一张**已释放**的
`B8G8R8A8_TYPELESS` 贴图里，趟 2 **1024×1024**、趟 3 **1024×512**；包住它的 64 MB
`PoolAllocator Heap` 也已释放；贴图在 44／60 帧前释放、heap 在 21／38 帧前。

### 13a. 问题 3（先回报）：**DreamGUI 内部找不到「存位址而不持参照」的绑定**

| 绑定 | 存的是什么 | 档案行号 | 持不持有 |
|---|---|---|---|
| 内建绘製的八张贴图（`MainPS`／`MainVS` 的 Main／Font／Mask／四张资料贴图／layer table） | `FTextureReferenceRHIRef` | `DreamUIBaseShaders.h:80-95`，绑定在 `DreamUIRenderer.cpp:989-1000` | **持有 reference 物件**；贴图死时引擎先清 reference 再放贴图 |
| layer style 的 pattern | `FTextureRHIRef` | `DreamUILayerStyleComposite.h:75`，填在 `.cpp:83-91` | **持有 RHI 贴图本身**（会过期，不会悬空） |
| backdrop | **裸 `FRHITexture*`** | `DreamUIRenderer.h:29`（**整个外挂里唯一一个裸 `FRHITexture*` 成员**） | 只在 pass lambda 内由 `GetRHI()` 填、且 pass parameters 宣告了 `RDG_TEXTURE_ACCESS`（`DreamUIRenderer.cpp:845`、`:1589-1594`）→ **作用域限於那个 pass** |
| 材质参数（`DreamUIMaterialProxy`） | **裸 `const UTexture*`**：`TArray<TPair<FName, const UTexture*>> Textures` | `DreamUIMaterialProxy.h:15`、`:19` | **不持有**，注解自己写明「the giver's to keep alive: the proxy holds them as plain pointers」（`:36-40`）。缓解是 `LetGoOfUnreachable()`（`:74`）：GC 的可达性分析之后，每个 proxy 放掉即将被释放的那些 |
| 材质的 uniform buffer 实际存什么 | **`Value->TextureReference.TextureReferenceRHI`**，也就是 reference | 引擎 `MaterialUniformExpressions.cpp:1712-1729`（注解就写著 reference 由 `UTexture::BeginDestroy` 的 render command 清掉）；而 `FRHIUniformBuffer::ResourceTable` 是 `TArray<TRefCountPtr<FRHIResource>>`（`RHIResources.h:1286-1294`） | **持有 reference** |

**所以问题 3 的答案是：在 DreamGUI 这一侧，我找不到一条把贴图位址存起来、又不持任何参照、而且活过那一个 pass 的路。**
唯一真正「不持有」的是材质参数里那串裸 `const UTexture*`，但它是 **UObject 层级**的不持有
（闸门是 GC 可达性），而且送进 uniform buffer 时换成了 reference。
**这把搜索推到问题 4 的那一侧——我们自己的程式码。**

**2026-11-19 晚更新：e-cardload 第四趟把窗口开到 4000 帧，量到那张贴图是在故障前约 2850 帧／约 40 秒
被释放的**（先前的 21–60 帧是预设 100 帧窗口的边缘造成的假象；协调转述，我未复核报告原文）。
**这个数字把上表整个变成排除证据**：表里每一条都是**每帧重新解析**的——
内建绘製的八张在每次 `ResolveTextures_RenderThread` 重取 reference（而 reference 在贴图死时已被引擎清掉）、
layer style 持的是计数参照（它若还握著，那张贴图根本不会被释放）、backdrop 的裸指标只活在那一个 pass、
材质参数在 GC 的可达性分析后由 `LetGoOfUnreachable()` 放掉。
**没有一条能把一个已归还的位址揣四十秒。** 所以那个绑定不在 DreamGUI 这一侧。

### 13b. 问题 1：用「尺寸＋格式＋开卡时建立」三条件筛，**DreamGUI 的贴图几乎全被排除**

| 候选 | 判定 | 依据 |
|---|---|---|
| 读卡器的卡片缩图 | **排除：尺寸不可能** | 解码上限写死 **288×402**（`OKReaderScreen.cpp:1283`），永远到不了 1024 |
| `DreamUIDataTexture`／`DreamUIDataAsTexture`（widget data 等） | **排除：格式不符** | 它的格式只有 `PF_R8`／`PF_R16F`／`PF_R32_FLOAT`／**`PF_R8G8B8A8`**／`PF_A16B16G16R16`／`PF_A32B32G32R32F`（`DreamUIDataAsTexture.cpp:49-77`），**没有 `PF_B8G8R8A8`**。（可惜：它长大正是**高度翻倍**（`:92`），512→1024 的形状本来完全对上，但格式把它排除了——这条我差点要当成命中） |
| render layer table | 排除：格式是 `PF_A32B32G32R32F` | `DreamUIRenderLayerTable.cpp:34` |
| 字体图集 | 排除：是 `UTexture2DArray`，不是 2D 贴图 | §3、`DreamUIFontData_FreeTypeRender.cpp:3434-3468` |
| DreamGUI 动态精灵图集页 | **部分排除**：它是**正方形**（`InTextureSize × InTextureSize`，`DreamUIDynamicSpriteAtlasData.cpp:26-48`），所以能是 1024×1024、**不可能是 1024×512** | 同左；格式闸门是 `PF_B8G8R8A8`（`:300`、`:323`） |
| **卡片自己的贴图（`KKUnityBundle`）** | **三条件全中** | `CreateTransient(W, H, PF_B8G8R8A8)`，尺寸就是来源 mip 的尺寸（`KKTextureRuntime.cpp:96`、`:240-241`）。原作贴图正是 1024×1024／1024×512 这一类；开卡时建立；换卡时上一张的被放掉 |
| 卡片 PNG／APNG 预览影格 | 可能 | `OKGalleryWidget.cpp:140`、`:1414`，尺寸就是 PNG 自己的尺寸；由 `AnimatedPreviewTextures` 持有（`OKCharacterController.h:740`，`UPROPERTY`） |

**注意一个会误导人的细节**：`PF_B8G8R8A8` 在 D3D12 上的平台格式本来就是 `B8G8R8A8_TYPELESS`
（UE 要同时开 UNORM 与 UNORM_SRGB 两种 view），**所以 TYPELESS 不代表 sRGB，也不能用来区分谁建的**。

#### 13b-2. 名字 `Texture2D_1003` 自己就是一个筛子（协调给的线索，我核过程式码）

`Texture2D_NNNN` 是 UE 给**类别恰好是 `UTexture2D`、而且建立时没有给名字**的物件自动取的名。这两件事各排除一批：

| 建立点 | 名字会是什么 | 判定 |
|---|---|---|
| `UDreamUIDataTexture`（资料贴图） | `MakeUniqueObjectName(..., "DreamUIDataTexture")` → `DreamUIDataTexture_N`；而且**类别是子类别 `UDreamUIDataTexture`**，自动名也不会是 `Texture2D_N` | **排除**（`DreamUIDataAsTexture.cpp:80-82`） |
| DreamGUI 动态精灵图集页 | 显式名 `DreamUIDynamicSpriteAtlasData_Texture_%d`（`FDreamUIUtils::CreateTexture` 的 `InDefaultName`，`DreamUIUtils.h:35`） | **排除**（`DreamUIDynamicSpriteAtlasData.cpp:29-33`） |
| `DreamMaskTransition` / `DreamNiagaraSystem` 的贴图 | 都传了显式名 | 排除（`DreamMaskTransition.cpp:85`、`DreamNiagaraSystem.cpp:77`） |
| **`KKTextureRuntime` 的卡片贴图** | **没给名字**（`:96`、`:241` 不传；`:240` 明写 `NAME_None`） | **符合** |
| `OKGalleryWidget.cpp:140`／`:1414`、`OKGalleryAppearance.cpp:70`、`OKReaderScreen.cpp:1219` | 都没给名字 | 符合命名，但 `OKReaderScreen` 那条已被尺寸排除（288×402） |

**所以名字也指向「不是 DreamGUI 建的贴图」**，和 §13b 的尺寸／格式筛选同一个方向。

另外一个**软**讯号（只是量级，不能当证据）：序号 **978／1003** 说明那一次执行里已经建过上千个
匿名 `UTexture2D`。一张卡的贴图是**几百张**的量级，UI 的那几张不是——这和「卡片贴图」同向。

### 13c. 这条筛选的后果：**它把「故障 shader 是 DreamGUI 的 `MainPS`」这个前提又推回台面**

如果故障的那张是**卡片自己的贴图**，那它**根本不是 DreamGUI 的贴图**——DreamGUI 不会去取样角色的身体／衣服贴图。
那么取样它的就是**角色材质的 pixel shader**，不是 UI 的。
**而「故障 shader 是哪一颗」从头到尾没有定下来**（§1a：四个 global shader 的进入点都叫 `MainPS`；
§5a：`fragment_02` 是 Aftermath 自己编的号、hash 是 128-bit 的 DXIL hash、离线比不了）。
**这两件事现在互相咬住了**：要嘛那张贴图是 UI 的（那 §13b 的筛选错了，请给我报告里那张贴图的 **Name** 栏），
要嘛 shader 不是 UI 的（那搜索范围要整个换到角色材质那一侧）。
**报告里 `PageFault: Found ... released resources` 每笔都带 `Name`**（§12c），
**那个名字能一刀切开这两种情形**，比继续读碼便宜得多。

### 13d. 问题 2（部分答）：卡片贴图的拥有者

- 建立后由 `AKKPreviewActor` 的 **`UPROPERTY()` 容器**持有：
  `LoadedTextures`（`KKPreviewActor.h:916-917`）、`WornTextures`（`:616`）、`WornBodyMasks`（`:623`），
  以及材质实例 `CookedRoleMaterials`（`:918`）——**都是 UPROPERTY，所以 GC 层面是有根的**。
- `KKTextureRuntime` 自己的两个快取用 `TStrongObjectPtr`（虹膜：`:133-148`、`:177`、`:194`，
  可用 `ok.IrisCacheClear` 清掉），**那是强参照，只会延长寿命、不会提早释放**。
  PNG 快取（`:262-280`）存的是解码后的像素，不是贴图，而且按预算汰换。
- **最后一个强参照消失的时机**，因此就是**换卡时 preview actor 与它的材质被拆掉**那一刻——
  和「贴图在故障前 44／60 帧被释放」同向。
- **我没有读**：preview actor 换卡时的拆除顺序、以及有没有任何东西（render thread 的结构、快取的 MID）
  在 actor 死后还握著那些贴图。那是下一步，但按 §13c，**先看那个 Name 栏再决定要不要读**。

### 13e. 问题 4：要找的序列在哪一侧

既然 DreamGUI 都持参照（§13a），放掉最后一个强参照的只能在我们自己的程式码。
程式码里「建立 → 交给 DreamGUI → 之后释放／覆写／汰换」这个序列，目前只找到一处完整的：
**`OKReaderScreen` 把 UMG 那边的贴图镜射进 DreamGUI 的 brush**
（`OKReaderScreen.cpp:179-184`、`:238-244`，清掉在 `:1084`），拥有者留在 UMG 那一侧；
退场是三秒计时器（§6b、候选 4）。**但这一条的贴图是缩图，已被 §13b 的尺寸排除。**
卡片贴图那一侧没有「交给 DreamGUI」这一步——**这正是 §13c 那个矛盾的另一面**。

**不谈修法**（按指示）；这一节只钉拥有者与绑定。

## 14. 「UI 绘製绑了卡片角色贴图」—— **程式码不支持这个猜测**（2026-11-19 晚，e-cardload 的线索之后）

### 14a. 先讲一个版本差：这几个档 **F 树落后 E 树**，所以本节读的是 E 的副本

e-cardload 给的 `OKReleaseStaleRecentRuntimeTextures`／`OKReleaseStaleKeptRuntimeTextures`
**在 F 树里一个都不存在**（全树 grep 零命中）。md5 与行数：

| 档案 | F | E |
|---|---:|---:|
| `Plugins/KKUnityBundle/Source/KKUnityBundle/Private/KKTextureRuntime.cpp` | 414 行 | **461 行** |
| `Plugins/KKUnityBundle/Source/KKUnityBundle/Private/KKPreviewActor.cpp` | 14049 行 | **14085 行** |

两个都 DIFFER。这是共用程式码，所以**崩溃的那一版是 E 的**；本节凡是 `KKTextureRuntime`／
`OKGalleryWidget`／`OKReaderScreen` 的行号都标明读的是 **`E:\OpenKoikatsu`**（只读，没有改动）。
§13 之前那些 OK 侧的行号是 F 的副本，**对不上 E 的报告**，看的时候要换算。

### 14b. 所有把贴图交给 DreamGUI 的地方，只有三处，而且都不是卡片角色贴图

E 树 `Source/OpenKoikatsu` 里 `SetResourceObject` 全部命中：

| 行 | 交出去的是什么 |
|---|---|
| `OKReaderScreen.cpp:193` | `Cast<UTexture>(A->Thumbnail->GetBrush().GetResourceObject())` —— **镜射 UMG 那边 `UOKAppearanceButton::Thumbnail` 的贴图** |
| `OKReaderScreen.cpp:254` | 同上，镜射一个 `UImage` 的贴图 |
| `OKReaderScreen.cpp:1297`／`:1457` | 卡片列表格子的缩图（清成 nullptr／设定） |

再往上游追「那个 UMG 影像里装的是什么」（E 树 `Source/OpenKoikatsu`，`SetBrushFromTexture` 全部命中）：

- `OKGalleryWidget.cpp:1446` ＝ 卡片 PNG 预览（`CreateTransient`，尺寸是 PNG 自己的）
- `OKGalleryWidget.cpp:1773` ＝ APNG 影格 `AnimatedPreviewTextures[Frame]`（`UPROPERTY`，`OKCharacterController.h:740`）
- `OKReaderScreen.cpp:1457` ＝ 清单缩图，**固定 288×402**
- `OKGalleryAppearance.cpp:305` ＝ `CachedThumb(Path)`，自己解码的缩图（`:70`，上限 2048）
- `OKHScene.cpp:4724` ＝ H 场景的服装图，不在读卡器画面

**`KKTextureRuntime` 的卡片角色贴图一次都没有出现在这些路上**。
它们唯一的去处是角色材质：`AKKPreviewActor` 的 `LoadedTextures`／`WornTextures`／`CookedRoleMaterials`
与 `SetSharedTextureParameter`（F 树 `KKPreviewActor.h:616`、`:623`、`:916-918`、`:925`）。
**所以「UI 绘製绑了卡片角色贴图」这个猜测，在程式码里找不到对应的那一段。**

### 14c. 而且就算绑上了也不会悬空：DreamGUI 的 brush 是**强参照**

```cpp
// F:\OpenKoikatsu\Plugins\DreamGUI\Source\DreamGUI\Public\Core\DreamUIImageBrush.h:54-62
USTRUCT(BlueprintType)
struct DREAMGUI_API FDreamUIImageBrush
{
    UPROPERTY(EditAnywhere, BlueprintReadWrite, ...)
    TObjectPtr<UObject> ResourceObject;      // ← UPROPERTY，GC 看得到
```

`UDreamImage::Brush` 也是成员（`DreamImage.h:29`）。**所以一张贴图只要还在某个 DreamGUI brush 里，
GC 就不会收它**——这条路的失误形状是**泄漏**，不是**悬空**。
（这也顺手否掉我自己想到的一个情节：镜射只在 `Texture != ShownTexture.Get()` 时才更新，
而 `ShownTexture` 是 `TWeakObjectPtr`（`OKReaderScreen.h:88` 一带），
看起来可以「两边都变 null 所以不更新、brush 继续指著死贴图」——
但因为 brush 是强参照，那张贴图不会死，所以这个情节产生的是泄漏。）

### 14d. 释放端真正的形状：**放掉的是 UObject 参照，死亡在下一次 GC**

E 树 `KKTextureRuntime.cpp:350-400`：卡片角色贴图被 `RecentTextures`
（`TArray<FRecentTexture>`，`FRecentTexture::Texture` 是 **`TStrongObjectPtr<UTexture2D>`**）按 768 MB 预算留著，
而且注解明写它们**只靠 refcount 活著、不靠可达性**：
「They hold a refcount (TStrongObjectPtr), so GC cannot take them: a reference chain search reads
*not currently reachable but it does have 1 refcount set*」。

`OKReleaseStaleRecentRuntimeTextures`（E 树 `:389-400`）做的事就是**把那个 `TStrongObjectPtr` 从阵列里移掉**，
`RemoveAt` 而已——**它不释放资源、不销毁 UObject**。真正的死亡发生在**下一次 GC**：
`BeginDestroy` → `ReleaseResource` → RHI 贴图被放掉 → 池子把区块还掉（整池空了才还 heap，§12d）。

**这正好解释那四十秒**：释放呼叫与销毁之间隔著一次 GC，所以「释放到故障」的距离不受任何
per-frame 机制的约束，也不该拿 `Frames.*` 那种帧数旋钮去对。
（**反过来说**：这同时意味著「释放」那行 log 印出来的时刻**不是**贴图死亡的时刻。
要定位死亡时刻，得看 GC，不是看那行 log。）

### 14e. 于是矛盾更紧了，而且可以用一个读数切开

- 贴图侧的三条线索（名字、格式、尺寸随卡片变）都指向 `KKTextureRuntime` 的卡片角色贴图。
- 绑定侧：卡片角色贴图**没有**任何路径进到 UI 绘製；而 UI 这一侧每一条绑定都持参照（§13a）。
- 两者只能有一个成立。**如果贴图侧对，那取样它的就不是 UI 的 shader**——
  而「故障 shader 是 `FDreamUIBasePS`」**至今只来自进入点名称**，而那个名字四颗 shader 共用（§1a、§5a）。

**能切开的读数（都不用再读碼）**：
1. 把 `r.Shaders.ExtraData=1` 打开重编一次 shader，**崩溃档会直接印出 shader type 名**（§5d）——
   这是唯一能证明「是不是 UI 的 shader」的读数。
2. 追踪报告里那张贴图的 **`Desc`** 栏（`MakeResourceDescDebugString`，§12c）：
   卡片角色贴图有完整 mip 链、UI 预览贴图没有（`CreateTransient` 预设单一 mip）——
   **mip 数能把「卡片贴图」和「UI 预览贴图」分开**，而且那一栏已经在档里了。

**不谈修法**（按指示）。

---

## 15. 消费端：**3D 预览那一侧也找不到「存位址而不持参照」的容器**（第 4 题成立）

本节行号全部读 **`E:\OpenKoikatsu`**（崩溃的那一版，只读）。

### 15a. 一张卡片贴图从建立到被取样，经过的容器与各自的持有方式

| 容器 | 存什么 | 行号 | 持有？ |
|---|---|---|---|
| `RecentTextures`（全域快取，768 MB 预算） | `TStrongObjectPtr<UTexture2D>`（注解：只靠 refcount 活著、不靠可达性） | `KKTextureRuntime.cpp:356-358` | **强参照（UObject）** |
| `ReadonlyTextures`（内容定址快取） | `TWeakObjectPtr<UTexture2D>` | `:340-341` | 弱——但只是快取查询，不参与绘製 |
| `AKKPreviewActor` 的 `LoadedTextures`／`WornTextures`／`WornBodyMasks` | `UPROPERTY TArray<TObjectPtr<UTexture2D>>` | `KKPreviewActor.h:616`、`:623`、`:916-917` | **强参照** |
| MID（`CookedRoleMaterials`／每个 part 的 `SurfaceMat`） | 贴图参数是 MID 自己的 `UPROPERTY` | 建立在 `KKPreviewActor.cpp:5190`、`:5244`、`:5274` | **强参照** |
| 元件的材质槽 | `UMeshComponent::OverrideMaterials` 是 `UPROPERTY` | `SetMaterial(...)`，例 `:3666`、`:3711`、`:5190` | **强参照**（所以 `CookedRoleMaterials.Reset()`（`:5318`、`:5661`、`:8007`）放掉 actor 那一份时，MID 仍由元件持有） |
| 材质的 uniform expression cache（贴图真正到 GPU 的那一步） | **`TextureReference.TextureReferenceRHI`**，而 ResourceTable 是 `TRefCountPtr` | 引擎 `MaterialUniformExpressions.cpp:1712-1729`、`RHIResources.h:1286-1294` | **持有 reference**，贴图死时引擎已先清掉它 |
| 交给 Rust session 的 | C ABI 传的是**资料 view**（mesh／bone／morph／texture 的位元组），不是 RHI 指标 | `include/ok_extract.h`、`KKRustExtract.cpp` | 不涉及 GPU 位址 |

**我们自己的程式码里没有任何裸 `FRHITexture*` 成员。** 全树（`Source/OpenKoikatsu`＋
`KKUnityBundle`／`KKRuntimePose`／`KKCrowdGpuPacking`）`FRHITexture` 只出现三次，
而且**三次都是 render command 内的区域变数**：`KKTextureRuntime.cpp:141`、`:189`（`ReadSurfaceData`）、
`KKRuntimeMaterial.cpp:353`（读 mip）。

### 15b. 「一次性建立、之后每帧重用」的那一类，查到的全部是这些

| 结构 | 内容 | 判定 |
|---|---|---|
| `FKKStreamSceneProxy`／`FKKStreamProxySection`（预览网格的自订 scene proxy，render thread 长期存活） | 顶点／索引缓冲区、`FLocalVertexFactory`、`TRefCountPtr<FRDGPooledBuffer>`（GPU deform／coating）——**没有存任何贴图** | 每帧用 `Section->Material->GetRenderProxy()` 重新取材质（`KKStreamMeshProxy.cpp:463`、`:580`、`:595`）→ 贴图每帧经材质重新解析 |
| 同上的 `UMaterialInterface* Material` | **裸 UObject 指标**，而且**每帧被读** | `KKStreamMeshProxy.cpp:69` —— **这是我在消费端找到的唯一一个「每帧读、而且不持有」的东西**。但它持的是**材质**，不是贴图；而材质由元件的 `OverrideMaterials`（`UPROPERTY`）持有，所以它要悬空，得先有一个 MID 在元件还指著它的时候死掉 |
| primitive uniform buffer | `FDynamicPrimitiveUniformBuffer`，`AllocateOneFrameResource`（逐帧） | `:481`、`:605` → 不跨帧 |
| `OKSourceMaterialOracle` 的 `TUniformBufferRef<FPrimitiveUniformShaderParameters>`（`UniformBuffer_MultiFrame`） | 只有 primitive 参数，**没有贴图** | `OKSourceMaterialOracle.cpp:47`、`:70` |
| 两个裸 `UTexture*` 成员 | `KKPreviewActor.h:257` `RampOverride`（注解写明「must stay alive (OKLoadRenderRamp roots it)」，而且只在载入时读一次：`KKPreviewActor.cpp:5423`）；`KKMainItemPlus.h:22` `ForgeShadowDepth` | 都不是每帧绘製读的绑定 |

### 15c. 换卡时谁被通知、有谁的寿命比贴图长

- scene proxy 属于**元件**，元件重建时整个丢掉重做；它不存贴图，所以没有「proxy 比贴图活得久」的问题。
- MID 属于**元件的材质槽**（`UPROPERTY`），比 actor 的 `CookedRoleMaterials` 阵列活得久——
  但那是**强参照**，所以方向是「材质和它的贴图一起被留住」，不是悬空。
- **寿命最长的其实是全域快取 `RecentTextures`**（跨 actor、跨卡片），也就是说
  **贴图比容器活得久**，而不是反过来。

### 15d. 所以第 4 题成立：**找不到不持有参照的容器**

把 §13a（UI 侧）与 §15a／§15b（3D 侧）放在一起：**从卡片贴图到 GPU 的每一条路，
在它被绘製的那一刻都持有某种参照**——UObject 的强参照、RHI 参照，或引擎会在贴图死前清掉的 texture reference。
**我找不到一个「存位址、不持参照、而且每帧被读」的容器。**

按协调自己定的界线，这个结果把方向推回：**那张贴图可能不是我们建的，消费者也可能不是我们的**
（e-cardload 插了九个建立点、三趟 48／48／93 笔，故障那张一次都没出现，和这个结论同向）。
两个还没排除的非我们自己的消费者：

1. **引擎自己的常驻结构**：texture streaming、`FRenderAssetStreamingManager` 的 handle、
   或某个 cached PSO／descriptor table。这一类我没有读。
2. **shader 身分仍未定**（§1a、§5a）：若故障的不是 UI 的 shader，消费端的搜索范围要整个换。
   `r.Shaders.ExtraData=1` 重编一次就能让崩溃档自己印出 shader type 名——**这仍是最便宜的下一步**。

**不谈修法**（按指示）。

## 16. MID 这条路：**协调押的那个前提是对的**（引擎侧已核实），但「重新指向」本身不会悬空

本节 OK 侧行号读 `E:\OpenKoikatsu`（崩溃那一版，只读），引擎行号读 `F:/UE5.8`（§11 已证两棵位元组相同）。

### 16a. 引擎侧前提：**材质实例 render thread 那一半，贴图参数存的是裸 `const UTexture*`**

```cpp
// Engine\Source\Runtime\Engine\Private\Materials\MaterialInstanceSupport.h:412
THashedMaterialParameterMap<const UTexture*> TextureParameterArray;   // FMaterialInstanceRenderProxy
// 同档 :454  TArray<THashedMaterialParameterMap<const UTexture*>::TNamedParameter> TextureParameters;
```

**确认：不是 UObject 参照。** 它的安全完全靠游戏执行绪那一侧
`UMaterialInstance::TextureParameterValues`（`UPROPERTY`）把贴图留住。

### 16b. 那张贴图确实是用 `SetTextureParameterValue` 设给 MID 的，而且 **MID 是沿用、只重新指向**

| 行 | 写法 |
|---|---|
| `KKRuntimePose/.../KKRuntimeSharedMaterial.cpp:419-420` | `auto* M=UMaterialInstanceDynamic::Create(Parent, GetTransientPackage());` 然后 `for(const auto& T:B.Textures) M->SetTextureParameterValue(T.Key, Textures[T.Value]);` |
| `KKUnityBundle/.../KKPreviewRuntimeMaterials.inl:74` | `OKCreateRuntimePreparedTexture(...)` 的结果同时进 `Role.Textures` 与 `To.Textures` |
| `KKPreviewActor.cpp:5246`、`:5256`、`:5276` | `if(Target && Target!=Current) M->SetTextureParameterValue(Name, Target);` ——**沿用同一个 MID、只把参数指向新贴图** |
| `KKPreviewActor.cpp:5190`、`:5244`、`:5274` | `if(!M){ M=UMaterialInstanceDynamic::Create(Parent,this); Mesh->SetMaterial(Slot,M); … }` ——**槽里已有就沿用，不重建** |

### 16c. 但「重新指向」这件事本身**不会**留下旧指标

`SetTextureParameterValue` 会**同时**改游戏执行绪的值并推一笔 render thread 更新，而
`THashedMaterialParameterMap` 是**按名字覆写**（`MaterialInstanceSupport.h:120-126`、`:273`）：
同名参数的旧裸指标被新的盖掉。**所以被重新指向的那些参数是安全的。**

**没被重新指向的那些**（`Target` 为 null、或新卡没有这个参数）两边都还留著旧贴图——
但游戏执行绪那一侧的 `TextureParameterValues` 是 `UPROPERTY`，**那就是强参照**，
所以这种情形产生的是**泄漏**，不是悬空（和 §14c 的 brush 同一个形状）。

### 16d. 剩下的那个形状：**MID 自己死掉，而 scene proxy 还用裸指标指著它**

`KKRuntimeSharedMaterial.cpp:419` 那个 MID 的 **Outer 是 `GetTransientPackage()`**，不是 actor 或元件——
**它没有任何拥有者关系**，活著完全靠接手的人存住（元件的 `OverrideMaterials`、`CookedRoleMaterials`、
或 `Part.SurfaceMat`）。而消费端那条路上有一个**每帧读、不持有**的指标：

```cpp
// E:\OpenKoikatsu\Plugins\KKUnityBundle\...\KKStreamMeshProxy.cpp:69
UMaterialInterface* Material;            // FKKStreamProxySection 的成员，render thread 长期存活
// 每帧：Section->Material->GetRenderProxy()      :463 / :580 / :595
```

接上 16a：**若某个 MID 失去最后一个强参照被 GC 收走，而 scene proxy 这个裸指标还指著它**，
每帧 `GetRenderProxy()` 读到的就是**已释放的 `FMaterialInstanceRenderProxy`**，
它的 `TextureParameterArray` 里是**裸 `const UTexture*`**，指向同一次 GC 一起死掉的卡片贴图——
**一个每帧都在用、不持任何参照、指向已归还位址的绑定**，正是要找的形状，
也和「释放后 105 帧仍在取样」「每趟贴图不同、尺寸不同」相容。

**我没有验证、而且它决定这条成不成立的那一步**：标准路径 `UMeshComponent::SetMaterial` 会
`MarkRenderStateDirty` 重建 proxy，所以换材质本身是安全的。要出事，得有一条路
**换掉／放掉某个 section 的材质而没有重建 render state**。`KKPreviewActor.cpp:5244` 那行同时做了
`Mesh->SetMaterial(Slot,M)` 与 `Part.SurfaceMat=M`，**但 progressive stand-in 换成最终材质、
以及 `:5318`／`:5661`／`:8007` 的 `CookedRoleMaterials.Reset()` 这几条，我没有逐条追 render state
有没有跟著重建**。这是下一步该读的，而且**可量**：e-cardload 的「交接与放手反查」log 只要能印出
「某个 section 的 `Material` 指向的 MID 已不在任何强参照里」，就能直接证实或否掉。

**不谈修法**（按指示）。

---

调查：f-sceneload。现象、e-cardload 的趟数与追踪报告都是转述，报告原文与崩溃档我没有自己看过；
§11 的两棵引擎比对、§12–§16 的程式码是我自己读的（§14–§16 的 OK 侧读的是 E 树的副本，只读）。
