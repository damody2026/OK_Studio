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

## 17. 解掉那个冲突：**「沿用」与「重建」说的是两批不同的 MID，两句都对**

### 17a. 先做比对（协调要求）

| 档案 | F | E | md5 |
|---|---:|---:|---|
| `KKRuntimePose/.../KKRuntimeMaterial.cpp` | 338 行 | 441 行 | **DIFFER** |
| `KKRuntimePose/.../KKRuntimeSharedMaterial.cpp` | 608 行 | 609 行 | **DIFFER** |
| `KKUnityBundle/.../KKPreviewRuntimeMaterials.inl` | 169 行 | 169 行 | **SAME** |

两个 `KKRuntimePose` 的档都不同（E 多了诊断）。**但这不是冲突的来源**：§16 的 OK 侧行号我读的就是
**E 树**，而且逐字核过——E 树 `KKPreviewActor.cpp:5241-5246`：

```cpp
UMaterialInterface* Parent=Mesh->GetMaterial(Slot);UTexture* Current=nullptr;
if(!Parent||!Parent->GetTextureParameterValue(FMaterialParameterInfo(Name),Current))continue;
auto* M=Cast<UMaterialInstanceDynamic>(Parent);
if(!M){M=UMaterialInstanceDynamic::Create(Parent,this);Mesh->SetMaterial(Slot,M);...}
UTexture* Target=Value;if(!Target && M->Parent)M->Parent->GetTextureParameterValue(FMaterialParameterInfo(Name),Target);
if(Target && Target!=Current)M->SetTextureParameterValue(Name,Target);
```

### 17b. 冲突的真正来源：**两批 MID**

| 哪一批 | 建立 | 换卡时 | 谁的贴图 |
|---|---|---|---|
| **每次载入自己建的**（e-cardload 看的那批） | `KKRuntimeSharedMaterial.cpp:419`，`UMaterialInstanceDynamic::Create(Parent, GetTransientPackage())`，**没有任何 MID 快取** | **整批重建**；旧的随 `CookedRoleMaterials.Reset()` 失去 actor 那一份强参照 | `:420` 把 `OKCreateRuntimePreparedTexture` 的卡片贴图设进去 |
| **元件槽里沿用的**（我看的那批） | `KKPreviewActor.cpp:5244`、`:5190`、`:5274`：槽里**已经有**材质就沿用（不是 MID 才包一层） | **沿用同一个**，只 `SetTextureParameterValue` 重新指向（`:5246`、`:5256`、`:5276`） | shadow depth／反射 cube／`Main` 这类**后设**参数 |

**e-cardload 说「`KKRuntimeMaterial.cpp` 全档 `SetTextureParameterValue` 命中 0」也是对的——
我引的从来不是那个档**（是 `KKRuntimeSharedMaterial.cpp` 与 `KKPreviewActor.cpp`）。
**两句话都成立，没有人读错；混的是「哪一批 MID」。**

**而机制相关的是第一批**：它们每次载入重建、Outer 是 transient package、
贴图就是故障那种卡片贴图 —— 也就是协调说的「重建」那一支，**我 §16d 指的残余形状因此仍然活著**。

### 17c. 接著问的三题

1. **`KKRuntimePose` 有没有自订 scene proxy：没有。**
   `grep -rln "FPrimitiveSceneProxy\|CreateSceneProxy" Plugins/KKRuntimePose`（E 树）**零命中**。
   这条路上唯一的自订 proxy 是 `KKUnityBundle` 的 `FKKStreamSceneProxy`（`KKStreamMeshProxy.cpp:144`）。
2. **它怎么取得材质**：存**裸 `UMaterialInterface*`**（`FKKStreamProxySection::Material`，`:69`），
   每帧 `Section->Material->GetRenderProxy()`（`:463`、`:580`、`:595`）。**不存 `FMaterialRenderProxy*`、不持参照。**
3. **MID 被 GC 时 proxy 有没有被通知：没有任何通知机制。** 引擎的保护是间接的两层——
   元件的 `OverrideMaterials` 是 `UPROPERTY`（材质在槽里就不会被收），
   以及 `SetMaterial` 会 `MarkRenderStateDirty` 重建 proxy。
   per-load 的那批 MID 由 `Actor->CookedRoleMaterials`／`CookedRoleOutlines`（`UPROPERTY`）持有
   （`KKPreviewRuntimeMaterials.inl:168`），贴图由 `Actor->LoadedTextures` 持有；
   三处 `Reset()` 在 `KKPreviewActor.cpp:5318`、`:5661`、`:8007`。

**静态读不出来的那一步（我说清楚是读不出来，不是没查）**：
有没有哪一条路**让一个 MID 失去最后一个强参照、而当时还有一个活著的 proxy 的 `Material` 指著它**。
要判它需要知道 `Reset()`／槽位覆写与 proxy 重建的**实际先后**，那是执行期顺序，
`CookedRoleMaterials.Reset()` 的三个呼叫点与元件槽的覆写**不在同一个函式里**，
静态追不出谁先谁后。**e-cardload 的交接反查 log 正好量的就是这件事**
（「MID 放手时还在不在、参数现值是什么」），所以这一题交给那边的事实。

**不谈修法**（按指示）。

## 18. 更正我自己那句，并补上元件的生命周期

### 18a. 「MID 沿用、只重新指向」那句的依据，以及它**不足以**支撑我给它的标签

**依据是真程式码，不是从引擎一般行为推的，也不是 `OKCrowdRuntimeScene.cpp:798`：**
E 树 `Plugins/KKUnityBundle/.../KKPreviewActor.cpp:5241-5246`（§17a 已逐字引用），
在 `SetSharedTextureParameter` 这条路上。

**但它证明的只是「沿用槽里现有的那个 MID」，不是「跨卡沿用」。**
槽里那一个是不是上一张卡的，取决于元件有没有活过换卡——**这一点我当时没查就写成了「跨卡沿用」，
那是我多讲的一步**。查了之后（18b）结论是：**对持久元件成立，对其余部件不成立**。

### 18b. 换卡时元件：**部件的元件整批销毁，身体与头是持久的**

E 树 `KKPreviewActor.cpp:5341-5359`：

```cpp
for (FKKLoadedPart& Part : Parts)
    if (Part.Comp && Part.Comp != BodyMesh && Part.Comp != HeadMesh)
        Part.Comp->DestroyComponent();
Parts.Reset();
// BodyMesh/HeadMesh are persistent: just clear their sections so the next
// outfit refills them instead of stacking new sections.
if (BodyMesh) BodyMesh->ClearAllMeshSections();
if (HeadMesh) { HeadMesh->ClearAllMeshSections(); ... }
```

| | 换卡时 | 对 MID 的后果 |
|---|---|---|
| 一般部件的元件 | **`DestroyComponent()`** | 槽位连元件一起消失 ⇒ 那些 MID 失去这一份强参照；加上 `CookedRoleMaterials.Reset()` ⇒ **可被 GC**。而元件销毁会一起拆掉它的 render state 与 proxy，**所以这些部件不会留下活著的旧 proxy** |
| `BodyMesh`／`HeadMesh` | **持久**，只 `ClearAllMeshSections()`（清 section，**不清 `OverrideMaterials`**） | 槽里仍是上一张卡的 MID，直到新载入 `SetMaterial` 覆写 ⇒ **这才是我那句「沿用」真正成立的地方**；而只要 MID 还在槽里，它与它的贴图都还有强参照（**所以这条路留下的是泄漏，不是悬空**） |

**所以两种读法在同一个档里都成立**：per-load 的那批（`KKRuntimeSharedMaterial.cpp:419`）**跨卡重建**，
身体／头的材质槽**跨卡沿用**。

### 18c. 这对残余形状的影响：**它变窄了，但没有被排除**

- 部件元件销毁时 proxy 一起拆 ⇒ **「旧 proxy 指著死 MID」不可能来自那些部件**。
- 持久元件的槽持著旧 MID ⇒ 那些 MID 不会死 ⇒ **也不会悬空**。
- **剩下的只有一种**：一个 MID 既**不在**持久元件的槽里，也**不随元件销毁一起拆 proxy**——
  也就是**持久元件的 section 材质被覆写、而 proxy 的旧 section 还活著**的那个窗口
  （`ClearAllMeshSections` → 重新填 → `SetMaterial`，三步的先后与 proxy 重建的先后）。
  **这正是我上一节说静态读不出来的那一步**，而且现在范围只剩 `BodyMesh`／`HeadMesh` 这两个元件。

e-cardload 的交接 log 判准（**它自己定的，我同意**）：**同一个 MID 名字跨两张卡出现 ＝ 沿用，
不同 ＝ 重建**。按 18b，两者会同时看到——**身体／头的槽是同一个名字，部件的是新名字**；
若量到的是这个样子，那就不是谁读错，而是这两批本来就不同。

**不谈修法**（按指示）。

## 19. 持久元件那条也被排除了——**而排除它的是协调自己给的那把尺**

三题照问，E 树为准；引擎行号读 `F:/UE5.8`（§11 已证同一份）。

### 19a. 第 2 题先答，因为它决定另外两题：**`ClearAllMeshSections` 会 `MarkRenderStateDirty`**

`UKKAffineProceduralMeshComponent` 继承 `UProceduralMeshComponent`
（`KKAffineProceduralMeshComponent.h:28`），而那是引擎外挂的实作：

```cpp
// F:\UE5.8\Engine\Plugins\Runtime\ProceduralMeshComponent\...\ProceduralMeshComponent.cpp:784-790
void UProceduralMeshComponent::ClearAllMeshSections()
{
    ProcMeshSections.Empty();
    UpdateLocalBounds();
    UpdateCollision();
    MarkRenderStateDirty();     // ← 有
}
```

**所以「只清 section、旧 proxy 继续带著旧 `FMaterialRenderProxy` 每帧重送」不成立**：
render state 被标脏 ⇒ proxy 重建，旧 proxy 连它的 section 与材质指标一起在 render thread 上销毁。
`SetMaterial` 也一样会换掉 `OverrideMaterials[i]` 并 invalidate（`MeshComponent.cpp:63-100`）。

### 19b. 第 1、3 题：换卡时这两个槽会被 `SetMaterial` 换成新 MID

载入路径上对元件设材质的点（E 树 `KKPreviewActor.cpp`）：`:3666`、`:3673`、`:3680`、`:3711`、
`:5190`、`:5244`、`:5274`、`:7051`、`:7065`、`:7087`。
`:5190`／`:5244`／`:5274` 是「槽里不是 MID 才包一层」，其余是**直接换成这次载入建的材质**。
**每一条都走 `UMeshComponent::SetMaterial`，所以每一条都会通知 render state。**

### 19c. 用那把尺检查：**两个分支都和事实矛盾，所以这条线整个排除**

协调给的约束：**放手后 3 帧记忆体就真的被释放**，所以任何「某个 `UPROPERTY` 还指著那张贴图」的解释都不成立。

| 分支 | 结果 |
|---|---|
| 旧 MID **留在**持久元件的槽里（有参数没被覆写） | `OverrideMaterials` 是 `UPROPERTY` ⇒ MID 活著 ⇒ 它的 `TextureParameterValues` 也是 `UPROPERTY` ⇒ **那张贴图不可能被 GC** ⇒ **和「3 帧後真的释放」矛盾** |
| 旧 MID **被换掉** | `SetMaterial` 标脏 ⇒ proxy 重建 ⇒ **没有活著的 proxy 还指著旧 MID** ⇒ 旧 MID 之后被 GC 时没有人在用它 |

**两边都不成立，所以 §16d／§18c 那个残余形状（MID 被 GC 而 proxy 的裸指标还指著它）到此排除**——
**而且是用协调自己定的尺排除的，不是我放弃。** 顺带：那把尺也把「未覆写参数」这个解释整类排除，
因为它必然伴随一个活著的 `UPROPERTY` 参照。

### 19d. 于是我们自己的程式码**全部**排除过一遍了

| 侧 | 结论 |
|---|---|
| DreamGUI 的所有贴图绑定 | §13a：全部持参照；§14b：卡片贴图没有路径进 UI；§14c：brush 是强参照 |
| 3D 预览的容器 | §15a／§15b：没有裸 `FRHITexture*` 成员；proxy 不存贴图；贴图到 GPU 存的是 texture reference |
| MID 这条 | §16c：覆写会盖掉旧裸指标；§19c：两个分支都和 3 帧的事实矛盾 |

**与全部事实相容的，只剩不在我们程式码里的东西**：

1. **建立者不在我们插的那些点上** —— e-cardload 九个建立点、三趟 48／48／93 笔，故障那张**一次都没出现**。
   这件事本身就说明建立者在别处。**我建议普查时不要漏掉 `OKGalleryWidget.cpp:140` 与 `:1431`**
   （卡片 PNG 与 APNG 影格，`CreateTransient` 不给名字、尺寸随 PNG 变，三条线索全符合，
   而且它们由 `AnimatedPreviewTextures` 持有、换卡时 `Reset()`）。
2. **消费者是引擎自己的常驻结构**（streaming／pool／descriptor 一类），这一类我没有读。
3. **故障 shader 的身分仍未定**（§1a、§5a）：四颗 global shader 共用 `MainPS` 这个进入点名，
   而我们从头到尾只有那个名字。`r.Shaders.ExtraData=1` 重编一次就能让崩溃档自己印出 type 名。

**这三件里，第 3 件最便宜，而且它决定另外两件要往哪个方向找。**

**不谈修法**（按指示）。

## 20. 自製 GPU 提交那一层：**也是干净的，而且连「存贴图」这件事都没有**

E 树、只读。

### 20a. `KKRuntimePose` 与 `KKCrowdGpuPacking` 的 shader 参数**全部是缓冲区，没有一个贴图**

```
grep -rn "TextureRHI|ShaderResourceView|SHADER_PARAMETER_TEX|SHADER_PARAMETER_SRV|SHADER_PARAMETER_RDG" \
     Plugins/KKRuntimePose/Source Plugins/KKCrowdGpuPacking/Source
```

命中的只有 `SHADER_PARAMETER_RDG_BUFFER_SRV`／`_UAV`（`KKCrowdGpuPacking.cpp:15-18`、
`OKClothCoverGpu.cpp:14-39` 等）——**全是 buffer**。
`TextureRHI`／`ShaderResourceView` 在这两个外挂的 `Source` 下**零命中**。
GPU 磁碟快取（`KKRuntimeGpuDiskCache.cpp`）、pose 快取（`KKRuntimePoseCache.cpp`）、
GPU rig（`KKRuntimeGpuRig.cpp`）、coating（`CoatingBindings` 是 `TRefCountPtr<FRDGPooledBuffer>`）
**都只经手缓冲区**。

### 20b. 全专案再扫一次：**我们自己的程式码没有任何 render 侧贴图成员**

扫 `Source` ＋ `KKUnityBundle`／`KKRuntimePose`／`KKCrowdGpuPacking`／`OKStudio`／`OKHGShading`／
`OKAnimation`／`KKImportedAssets` 的 `Source`，`FRHITexture`／`FShaderResourceViewRHIRef`／
`FTextureRHIRef` 一共**三处，而且三处都是 render command 内的区域变数**：
`KKTextureRuntime.cpp:149`、`:197`（`ReadSurfaceData`）、`KKRuntimeMaterial.cpp:469`（读 mip）。

### 20c. toon shadow capture：走的是标准 UObject 路径，**按那把尺排除**

| 环节 | 存什么 | 行号 |
|---|---|---|
| capture 元件 | `UPROPERTY TObjectPtr<USceneCaptureComponent2D>` | `KKPreviewActor.h:938-939` |
| 双 render target | `UPROPERTY TArray<TObjectPtr<UTextureRenderTarget2D>>` | `KKPreviewActor.h:940-941` |
| 材质怎么读到它 | `Dynamic->SetTextureParameterValue(TEXT("KKShadowDepth"), Shadow->Depth)` | `KKPreviewActor.cpp:3705`；用到它的 MID 收在 `ToonShadowMaterials`（`KKPreviewActor.h:990-991`，`UPROPERTY`） |

**它没有自己的 pass 参数去存角色贴图**，而且每一环都是强参照——
按协调给的尺（放手后 3 帧记忆体就真的释放），**持有参照的一律排除**，所以这条连候选都不是。

### 20d. 把那把尺写成通则，省掉以后重复讨论

> **凡是持有 `FTextureRHIRef`／`FShaderResourceViewRHIRef`／`UPROPERTY` 贴图参照的容器，
> 都会延命，因此都与「3 帧后真的释放」矛盾，一律不是候选。**
> 能成立的只有**既不持 UObject 参照、也不持 RHI 参照**的绑定。

照这条尺，到目前为止在我们自己的程式码里找到的「不持有」只有两个，而且都已排除：
- `FKKStreamProxySection::Material`（裸 `UMaterialInterface*`，每帧读）——§19c 两个分支都矛盾；
- `FDreamUIMaterialParameters::Textures`（裸 `const UTexture*`）——§13a，GC 可达性分析后就放掉，
  而且送进 uniform buffer 时换成 reference。

### 20e. 所以这一层也干净，下一层我同意用量测而不是读碼

剩下的是**引擎自己的** cached mesh draw command／GPU Scene／PSO binding 那一层。
那一层的特点正是「一次建立、每帧重送、而且存的是解析过的绑定」，符合这把尺；
但它在引擎里、而且与 `MarkRenderStateDirty` 的互动是执行期顺序，**读碼读不出来**。
协调说的做法（故障时印出正在绑的材质与 PSO）是对的方向。

**而我仍然把 shader 身分列为第一优先**：若那颗 shader 根本不是 UI 的，
上面十几节的搜索范围有一半是对的、一半白走。`r.Shaders.ExtraData=1` 重编一次就能定下来（§5d）。

**不谈修法**（按指示）。

## 21. 尺改了：逐条审计 §13c／§14c／§19／§20 的排除，哪几条作废

**新事实**（协调转述 e-cardload，我未复核）：放手那一刻 **7187 笔 MID 还活著而且还指著那张贴图**
（故障那张的六条反查全部 `ALIVE same=1`）；贴图在放手后**又活了 6459 帧**（就是那些 `UPROPERTY` 撑著），
16815 释放、16894 前不可达，**故障在释放之后 960 帧**。

**尺的正确形式**：

| 版本 | 成立？ |
|---|---|
| 「有 `UPROPERTY` 引用 ⇒ 贴图不会被回收」用在**故障那一刻** | **成立**（那时它已经被 GC 掉了） |
| 同一句用在**sweep 放手那一刻** | **不成立**——放手不等于死亡，中间隔著 6459 帧 |
| 「持有 RHI 参照 ⇒ 记忆体延命 ⇒ 排除」 | **成立**（记忆体确实被释放了），不受影响 |

### 21a. 逐条审计

| 条目 | 当初的依据 | 判定 |
|---|---|---|
| §19c 分支一：旧 MID 留在持久元件槽里 ⇒ 贴图收不走 ⇒ 矛盾 | **放手时那个错版本** | **作废。改回候选**——而且新事实正好长这样：MID 的 `UPROPERTY` 把贴图撑了 6459 帧，之后 MID 自己也死，两个一起走 |
| §19c 分支二：旧 MID 被换掉 ⇒ `SetMaterial` 标脏 ⇒ proxy 重建 | **结构事实**（引擎 `MeshComponent.cpp:63-100`） | **维持**。但它只管「经元件建立的 proxy」 |
| §19c 的「『未覆写参数』整类排除」 | **错版本** | **作废**，而且反过来：未覆写的参数**正是**「贴图被撑很久再一起死」的机制 |
| §16d／§18c 的残余形状（MID 被 GC 而某个绑定还指著它） | 靠分支一排除 | **恢复为候选**（分支二仍对元件那条路不利） |
| §19a `ClearAllMeshSections` 会 `MarkRenderStateDirty` | **结构事实**（`ProceduralMeshComponent.cpp:784-790`） | **维持** |
| §19b 两槽都走 `SetMaterial` | **结构事实**（十个呼叫点） | **维持** |
| §20a／§20b shader 参数全是缓冲区、`FRHITexture` 只有三处区域变数 | **结构事实**（grep） | **维持** |
| §20c toon shadow 排除 | **部分用错版本**（「每一环都是强参照」） | **重基**：改用**型别与命名**——那是 `UTextureRenderTarget2D`，UObject 自动名会是 `TextureRenderTarget2D_<n>`，而报告里是 **`Texture2D_<n>`**（§13b-2 同一把筛子）；而且它不是 `CreateTransient` 的 `PF_B8G8R8A8` 贴图。**重基后仍排除** |
| §20d 我写成通则的那把尺 | 含错版本的 `UPROPERTY` 那一臂 | **改写**：见 21b |
| §14c brush 是 `UPROPERTY` ⇒ 泄漏不是悬空 | **错版本**（协调只要我审 §19／§20，但这是同一个错） | **降为「只在故障那一刻成立」**：brush 若在故障时还握著它，那它就不会是已释放的那一张；但 brush 被清掉／`UDreamImage` 自己死掉之后，贴图就能死。§14b（卡片贴图没有路径进 UI）是结构事实，**不受影响**，所以 UI 侧整体仍排除 |
| §13a 的四十秒论证 | 「每帧重新解析，没有一条能揣住位址」 | **维持**，它从来不靠 `UPROPERTY` 那一臂 |

### 21b. 尺的改写版（之后都用这一版）

> 1. **故障那一刻**，那张贴图没有任何 UObject 引用（它已被 GC）。所以**候选不必在放手时就不持引用**，
>    只要在故障那一刻不再持有。**「放手时还有 UPROPERTY 指著它」不构成排除。**
> 2. **持有 RHI 参照**（`FTextureRHIRef`／`FShaderResourceViewRHIRef`／uniform buffer 的 ResourceTable）
>    **仍然是排除**：那会让记忆体延命，而记忆体确实被释放了。
> 3. 要找的东西**活过两个 UObject 的死亡**（贴图与 MID），**而且不持 RHI 参照**，并且**每帧还在画**。

### 21c. 按新尺，现在还活著的候选

1. **§16d／§18c 的形状**（恢复）：某个绑定指著已死的 MID 的 `FMaterialInstanceRenderProxy`，
   而那份 proxy 的 `TextureParameterArray` 是**裸 `const UTexture*`**（§16a）。
   它满足新尺的三条：不持 UObject 参照、不持 RHI 参照、每帧被读。
   **唯一的阻碍仍是分支二**——经元件建立的 proxy 会在 `SetMaterial` 时重建。
   **所以这条的成立条件很窄也很明确：要有一个 proxy 没有被那次重建换掉。**
2. 引擎自己的 cached mesh draw command／GPU Scene（同样符合三条，而且**它就是「一次解析、每帧重送」**）。
3. shader 身分仍未定（§5a）。

**不谈修法**（按指示）。

## 22. 怎么才能看见 shader／pass 身分：**有一条是免费的，而且可能已经在手上的报告里**

读 `E:/PhysX/UE5.8`（协调指定；§11 已证与 F 位元组相同），只读。**每个名字都从宣告处抄的。**

### 22a. 免费的那一条：**RHI breadcrumb 预设就是开的，而且崩溃时会印出当时活著的 pass**

| 项目 | 值 | 行号 |
|---|---|---|
| `r.GPUCrashDebugging.Breadcrumbs` | **预设 1（开）**，`ECVF_ReadOnly` | `Runtime/RHI/Private/RHI.cpp:2133-2138` |
| 说明原文 | 「a vendor-agnostic method for determining **which passes were active** when a GPU crash occurs」 | 同上 |
| 崩溃时谁印 | `FD3D12DynamicRHI::DumpActiveBreadcrumbs(...)`：`D3D12Util.cpp:928`（`EVerbosity::Error`）、`D3D12RHI.cpp:910`（`Warning`） | — |
| 印出来长什么样 | 每个 device／pipeline 一段，表头 `Device %d, Pipeline %s: (In: 0x…, Out: 0x…)`，底下是 breadcrumb 树 | `RHI/Private/RHIBreadcrumbs.cpp:162-200` |
| 命令列开关 | `-gpubreadcrumbs`；另有总开关 `-gpucrashdebugging`／`-nogpucrashdebugging`（`RHI.cpp:2092-2110`） | — |

**breadcrumb 的名字就是 pass／event 名**（`RDG_EVENT_NAME` 那一类），所以它足以分开
`DreamUIRender_WorldSpace`／`DreamUIRender_*` 与角色的 base pass——**这正是我们缺的那个身分**。
**第一步不是跑新趟，是去现有的崩溃报告里找这一段**（关键字 `Device 0, Pipeline`）。零成本。

### 22b. DRED 今天是关的，而「BreadcrumbContext」**不是一个 cvar**

| 项目 | 预设 | 行号 |
|---|---|---|
| `r.D3D12.DRED` | **0**，`ECVF_RenderThreadSafe \| ECVF_ReadOnly`（**只能启动时设**） | `D3D12RHI/Private/D3D12Adapter.cpp:156-161` |
| `r.D3D12.LightweightDRED` | **0**，同上旗标 | `D3D12Adapter.cpp:163-168` |

今天那份报告印的是 `DRED: No PageFault data.`，和 DRED 预设 0 一致。
**这一版没有 `r.D3D12.DRED.BreadcrumbContext` 这个名字**（grep 零命中）——
breadcrumb context 在 DRED 打开时就是**无条件强制开**的：
`DredSettings1/2->SetBreadcrumbContextEnablement(D3D12_DRED_ENABLEMENT_FORCED_ON)`
（`D3D12Adapter.cpp:602`、`:616`），印出来的路径在 `D3D12Util.cpp:208-215`（`GetBreadcrumbContexts`）。
**所以只要 `r.D3D12.DRED=1`，那串 `DrawIndexedInstanced` 就会带 context，不需要另一个旗标。**

### 22c. shader 身分：这一版实际存在的三个旗标（都 `ECVF_ReadOnly`，而且都要 shader 重编）

| cvar | 预设 | 作用 | 行号 |
|---|---:|---|---|
| **`r.Shaders.SymbolsInfo`** | 0 | 「save out a slimmer **ShaderSymbols.Info which contains shader platform hashes and shader debug info**」——**这就是 hash → shader 的反查表**，而且比完整 PDB 便宜 | `Runtime/Engine/Private/ShaderCompiler/ShaderCompiler.cpp:383-390` |
| `r.Shaders.ExtraData` | 0 | 「extra shader data that can be used at runtime… includes **shader names**」⇒ Aftermath 会印出 shader 名而不是 `fragment_02`（注册处 `D3D12NvidiaExtensions.cpp:40`、名字来源 `RHIResources.h:848-885`） | `ShaderCompiler.cpp:451-457` |
| `r.Shaders.Symbols` | 0 | ＝ `GenerateSymbols` ＋ `WriteSymbols`，整套 PDB，最重 | `ShaderCompiler.cpp:374-381` |

- 三个的说明都写著「**This setting can be overriden in any Engine.ini under the `[ShaderCompiler]` section**」，
  而且 `FShaderSymbolSettingHelper` 读的就是 `[ShaderCompiler]`／`[ShaderCompiler_BuildMachine]`
  两段加上该 cvar（`RenderCore/Private/ShaderCore.cpp:766-784`）。
- `ShaderSymbols.Info` 的输出位置：`<Project>/Saved/ShaderSymbols/<ShaderFormat>/`（这里是 `PCD3D_SM6`），
  可用命令列 `-ShaderSymbolsExport=<路径>` 覆写（`Developer/ShaderCompilerCommon/Private/ShaderSymbolExport.cpp:67-90`）。
- 另有 `r.Shaders.GenerateSymbols`（0，`:391-396`）与 `r.Shaders.WriteSymbols.Zip`（0，`:443-449`）。

### 22d. 成本排序（最便宜的在前）

1. **翻现有报告找 breadcrumb 段**（§22a）——**不用跑、不用改、不用建置**。若有，pass 身分当场就有。
2. **`r.D3D12.DRED=1`**（启动时设）再跑一趟——会补上 DRED 的 page-fault 物件清单与带 context 的 breadcrumb。
3. **`r.Shaders.ExtraData=1`**（`[ShaderCompiler]`）＋ shader 重编——之后**每一次**崩溃档都会直接印出
   shader type 名。一次成本，长期收益。
4. **`r.Shaders.SymbolsInfo=1`** ＋ 重编——拿到 hash 反查表，可以把 `E6753E1E…` 对回 shader。
5. **要改引擎才能做到的**：「印出故障当下 command list 正在绑的材质／PSO」——
   **这一版没有现成旗标**。`D3D12Util.cpp` 的 `LogPageFaultData` 只印资源与 heap（§12c），
   breadcrumb 印 pass、DRED 印最后几个操作，**三者都不印「这一笔 draw 用的是哪个 `FMaterialRenderProxy`」**。
   要那个就得在 D3D12 的 PSO／draw 路径上自己记，属於改引擎（而我被交代不碰引擎程式码）。
   **按 1–4 的收益，我判断不需要走到这一步。**

### 22e. 顺便把一个教训写成方法（协调要求）

> **一个依据被推翻时，要去搜它的所有引用处，而不是等别人指出。**
> 今天这把尺（`UPROPERTY` 可达性）被改版时，协调只指了 §19／§20，
> 但同一个错依据还用在 §14c；是我自己去搜才找到的。
> 同理，一个**名字**被证明不存在时（`DreamGUI.LogDeferredRelease` 不是 cvar、
> `r.D3D12.DRED.BreadcrumbContext` 不存在），要把它在计画里的所有出现处一起划掉。
> 这一条已写进 [MEASUREMENT_STANDARD_20261119.md](MEASUREMENT_STANDARD_20261119.md)。

**不谈修法**（按指示）。

---

调查：f-sceneload。现象、e-cardload 的趟数与追踪报告都是转述，报告原文与崩溃档我没有自己看过；
§11 的两棵引擎比对、§12–§20 的程式码是我自己读的（§14–§20 的 OK 侧读的是 E 树的副本，只读）；
§21 是在协调更正那把尺之后对我自己先前排除的审计；§22 读的是 `E:/PhysX/UE5.8`。

---

## §23 breadcrumb 命中之后：built-in draw 的 12 个贴图槽，与那个只存位址的一处

读的是 E 树（只读）。breadcrumb 的那三行**是我们自己加的**，不是引擎的：
`Plugins/DreamGUI/Source/DreamGUIRenderer/Private/DreamUIRender/DreamUIRenderer.cpp:1027`、`:1030`、`:1033`
（`RHI_BREADCRUMB_EVENT_F`，注解写明「Only recorded when breadcrumbs are」）。它们只在
`FDreamUIRenderer::DrawBuiltInBatch`（`:900`）里，材质路径没有。breadcrumb scope 是 RAII、到函式结尾才结束，
所以 `[Active]` 落在 `DreamUIMore` ⇒ **故障那一笔 draw 是 built-in shader 路径的 draw**，不是材质路径。
这把范围收到下面这 12 个槽。

### 23a 槽的全表：7 个被印出，5 个没有

绑定全在 `DreamUIRenderer.cpp:983-1017`。PS 10 个、VS 2 个：

| 槽 | 绑定行 | 来源成员 | breadcrumb | 没有贴图时 |
|---|---|---|---|---|
| `DreamUI_MainTex` | `:992` | `Params.MainTextureRHI` | `main=` | `GWhiteTexture` |
| `DreamUI_FontTex` | `:994` | `FontTextureRHI` | `font=` | `GBlackArrayTexture` |
| `DreamUI_WidgetDataTex` | `:996` | `WidgetDataTextureRHI` | `widget=` | `GBlackTexture` |
| `DreamUI_ClipDataTex` | `:997` | `ClipDataTextureRHI` | `clip=` | `GBlackTexture` |
| `DreamUI_RectBlockDataTex` | `:998` | `RectBlockDataRHI` | `rect=` | `GBlackTexture` |
| `DreamUI_PaintDataTex` | `:1000` | `PaintDataRHI` | `paint=` | `GBlackTexture` |
| `DreamUI_MaskTex0` | `:1002` | `MaskTexture0RHI` | `mask0=` | `GWhiteTexture` |
| **`DreamUI_MaskTex1`** | `:1004` | `MaskTexture1RHI` | **没印** | `GWhiteTexture` |
| **`DreamUI_SceneDepthTex`** | `:1006` | 函式参数 `FRHITexture* SceneDepthTexture` | **没印** | `GBlackTexture` |
| **`DreamUI_BackdropTex`** | `:1015` | `InBackdrop->Texture` | **没印** | `GBlackTexture` |
| **`DreamUI_RenderLayerTable`**（VS） | `:983` | `RenderLayerTableRHI` | **没印** | `GBlackTexture` |
| **`DreamUI_RenderLayerWidgetData`**（VS） | `:984` | `WidgetDataTextureRHI` | **没印**（与 `widget=` 同一个） | `GBlackTexture` |

**所以「breadcrumb 里搜 `Texture2D_` 零命中」不等于那张卡片贴图没被绑。** 没印出来的 5 个之中，
`MaskTex1`、`RenderLayerTable` 可以是任意外部 `UTexture`；`SceneDepthTex` 与 `BackdropTex` 是 pass 内的
RDG 资源（`:845`、`:1589-1594`、`:2358-2360`），不是卡片贴图。**要补的是 MaskTex1 与 RenderLayerTable
这两行，一行 breadcrumb 就有。**

### 23b render thread 那一侧存的是什么：持有，**除了交接的那一瞬间**

`DreamGUIRenderer/Public/DreamUIRender/DreamUIBaseShaders.h:51-95`——`FDreamUIBuiltInDrawParams` 是两半：

- game thread 那一半：**`TWeakObjectPtr<const UTexture>`**（`:55-78`），注解说明是为了「a section that waits
  in a pool keeps its parameters, and a texture can be collected meanwhile」；
- render thread 那一半：**`FTextureReferenceRHIRef`**（`:80-92`，`TRefCountPtr`，**持有**）。

绑定时 `TextureOrFallback`（`DreamUIRenderer.cpp:970-974`）绑的是
`static_cast<FRHITexture*>(InReference)`——**绑的是 texture reference 物件本身**，不是被引用的贴图。
reference 被持有，而 UTexture 死亡时 `RHIClearTextureReference` 会把它指向黑色贴图
（`StreamableTextureResource.cpp:231-242`）。**所以跨帧那一段，这 12 个槽没有一个是裸位址。**

### 23c 降级点就一处，而它已经被埋了桩

`FDreamUIBuiltInTextures`（同一档 `:22-33`）是**九个裸 `const UTexture*`**。降级与还原：

- **降级**：`DreamUIBaseShaders.cpp:55-70` `GetTexturesForRenderCommand()`——把九个 weak ptr `.Get()` 成裸指标，
  由 lambda 捕获进 render command（呼叫点 `DreamGUI/Private/Core/DreamUIMesh/DreamUIMeshComponent.cpp:697`、
  `:1529`、`:1597`、`:2613`）；
- **解参**：`DreamUIBaseShaders.cpp:72-110` `ResolveTextures_RenderThread()`——在 render thread 上
  **解参那些裸指标**：`:88-91` `InTexture->TextureReference.TextureReferenceRHI`、`InTexture->GetResource()`。

**这就是那把新尺要找的「只存位址」的一处，而且是唯一一处。** 它的形状正是「位址不在任何 heap 里」：
UObject 若在 enqueue 与 execute 之间被清掉，`:89` 读的是已释放的 UObject 记忆体，拿到的不是旧指标而是
**凭空捏出来的 `FRHITextureReference` 指标**。

**这一条已经有桩，预设关**：`DreamGUI.LogStaleTextures`（`DreamUIBaseShaders.cpp:25-28`，`ECVF_RenderThreadSafe`，
**不是 ReadOnly，可执行期开**），命中时印 `slot=` `name=` `garbage=` `unreachable=` `frame=`。
档内写明的事前预测是 **NO hits**，理由是 `UTexture::IsReadyForFinishDestroy` 会等 resource release fence。
**这是零风险、一个 cvar、不必重编的一趟**，而且它直接回答「是谁还在画」：若有命中，画的人就是这个 render command。

### 23d 新候选：动态 sprite atlas 的页面——型别、名字、建法全都对上

breadcrumb 里 `main=DreamUIDynamicSpriteAtlasData_Texture_0`。这个名字只有一个产地：
`DreamGUI/Private/Core/DreamUIDynamicSpriteAtlasData.cpp` 的 `CreateAtlasTexture`，
名字 `DreamUIDynamicSpriteAtlasData_Texture_%d`、outer 是 `GetTransientPackage()`；它呼叫的
`DreamUIUtils.cpp` 的 `FDreamUIUtils::CreateTexture` 用 **`PF_B8G8R8A8`**、**正方形 `InSize×InSize`**、
**单一 mip**、`RF_Transient`（页面上限预设 `SIZE_2048x2048`，`DreamUISettings.h:53`）。

**这推翻不了也证实不了 §16–§18 的归属，但它给了一个零成本的判别**：故障那张 `B8G8R8A8_TYPELESS` 贴图
**是不是正方形**。atlas 页面必然正方（2048×2048 或 1024×1024 一类）；卡片 runtime 贴图与读卡缩图
（`OKReaderScreen.cpp:1216-1221`，上限 288×402）**不是**。e-cardload 的追踪报告里已经有宽高，**翻一下就知道。**

页面确实会被丢掉，而且**丢掉它的就是开卡时在打包新 sprite**：
`PackSprite`（`:300-316`）在页面满了时先 `EvictUnusedSprites` → `RepackPages`（`:231-261`）→
`DropEmptyPages`（`:265-281`，`AtlasTextureArray.RemoveAt(i)`，注解写「This is where the memory actually
goes back -- one page is a full atlas texture」）。页面的强参照只有 `AtlasTextureArray`（`TObjectPtr`）与
每个已打包 sprite 的 `AtlasTexture`（`DreamUISpriteData.h:80`，`UPROPERTY(Transient)`）；`ReleaseAtlasTextures`
（`:110-126`）把后者一并清成 `nullptr`。**两者都放手之后，页面就只是个可回收的 UObject——没有 fence、没有
延迟删除**，下一次 GC 就释放它的 RHI 贴图。

通知只有一条路：`NotifyRenderSpritesAtlasChanged`（`:283-293`）走 `RenderSpriteArray`
（**`TWeakObjectPtr`**，`DreamUIDynamicSpriteAtlasData.h:35`）呼叫 `ApplyAtlasTextureChange`，
元件那一侧（`DreamSpriteBase.cpp:43-51`）重取 `Sprite->GetAtlasTexture()` 并 `MarkCanvasUpdate(true)`，
当帧重建 draw call、当帧重新解参。**所以结构上是守住的——条件是每个在画它的元件都在 `RenderSpriteArray` 里。**
登记只有一处：`DreamUISpriteData.cpp:479-500` 的 `AddUISprite`，而且**只对实作
`IDreamUISpriteRenderInterface` 并自己呼叫它的元件生效**（静态打包那一支还包在 `#if WITH_EDITOR` 里，`:487`）。
**一个画了页面却没登记的元件，永远收不到这个通知**——它的 proxy 持有的 reference 会被清成黑色；
而它的 weak ptr 失效之后，那一节的 `MainTexture` 就是 null，下一次 `GetTexturesForRenderCommand` 交出 null，
**不是裸位址**。所以这条到目前为止也没有「只存位址」的出口；**真正的出口还是 23c 那一处。**

### 23e 外部 `UTexture2D` 进到这些槽的入口（Q4）

- `MainTex`：`DreamCanvas.cpp:4018` `BuiltIn.MainTexture = DrawCallItem.Texture.Get()`；
  `DrawCallItem.Texture` 来自 geometry 的 `Texture`（`DreamCanvas.cpp:2817`、`:2937`、`:3541`），
  而 geometry 的设定者只有四处：`DreamImage.cpp:238`、`DreamRectBlock.cpp:1406`、`DreamSpriteBase.cpp:45`
  （都是 `Sprite->GetAtlasTexture()`，即**打包后的页面**，不是来源贴图）、
  `DreamText.cpp:838` 与 `DreamVisualBatchMesh.cpp:270`（`GetTextureToCreateGeometry()`）。
  **所以外部 `UTexture2D` 走正常 sprite 路径时绑的是 atlas 页面，不是它自己**——
  例外是 `PackSprite` 对非 `PF_B8G8R8A8` 的来源直接拒收（`:302`），那种 sprite 不会被打包。
- `MaskTex0/1`：`DreamCanvas.cpp:4025-4026`，来自 clip mask 的 `FDreamUIMaskTextures::Slots`（任意外部贴图）。
- `RenderLayerTable`／`WidgetData`／`ClipData`／`RectBlockData`／`PaintData`：`DreamCanvas.cpp:4019-4024`，
  全是 DreamGUI 自己的 data texture 与 world subsystem 的 row texture。
- 另外两个把外部贴图直接塞进 `MainTexture` 的入口：
  `DreamGUIExtensions/Private/Extensions/DreamCanvasRenderTargetPreviewer.cpp:261`（render target）、
  `DreamLayerGroup.cpp:102`（mask 槽）。
- 读卡那一侧，唯一把外部物件交给 DreamGUI 的是 `OKReaderScreen.cpp` 的 `SetResourceObject`
  （`:193`、`:254`、`:1297`、`:1457`），进的是 `FDreamUIImageBrush::ResourceObject`
  （`DreamUIImageBrush.h:54-62`，**`UPROPERTY`，强参照**），再经 sprite 打包成页面。

### 23f 我没读的

材质路径的绑定（`FDreamUIMaterialProxy` 的非持有 `TArray<TPair<FName, const UTexture*>>`，§13）这次没重读：
breadcrumb 指的是 built-in 路径，故障那一笔不是材质路径的。若日后 breadcrumb 指向材质路径，§13 要重开。

---

## §24 外部 `UTexture2D` 进到 `DreamUI_MainTex` 的入口：就一条，而且读卡器正在用它

读的是 E 树（只读）。

### 24a 裸 `UTexture` 放进 brush，就直接被绑——不经 atlas、也不登记

`DreamGUI/Private/Core/Components/DreamImage.cpp:253-272` `UDreamImage::GetTextureToCreateGeometry()`：

1. `:255-258`——**ResourceObject 是 `UTexture` ⇒ 直接 return 它本身**；
2. `:259-262`——`ISlateTextureAtlasInterface` ⇒ return `GetSlateAtlasData().AtlasTexture`；
3. `:263-270`——`UDreamUISpriteData_BaseObject` ⇒ 这里**才**呼叫 `AddUISprite(this)` 登记，再 return 打包后的页面；
4. `:271`——其余是预设白图。

**第 1 条就是入口。** 它的后果有两件，都重要：

- 该贴图**原封不动**成为 `UIGeometry->Texture` → `DrawCallItem.Texture`（`DreamCanvas.cpp:2817`／`:2937`）→
  `BuiltIn.MainTexture`（`:4018`）→ `DreamUI_MainTex`（`DreamUIRenderer.cpp:992`）。**没有打包、没有复制、没有格式检查。**
- **它永远不在任何 `RenderSpriteArray` 里**（登记只在第 3 条分支）。所以 §23d 那条 atlas 的通知链
  （`NotifyRenderSpritesAtlasChanged`）**对这类元件完全不适用**——它唯一的生存连结是
  `FDreamUIImageBrush::ResourceObject`（`DreamUIImageBrush.h:54-62`，`UPROPERTY` 强参照）
  加上 draw call 那一侧的 `TWeakObjectPtr`。

另有一条同形状的：`UDreamUISpriteData::InitSpriteData`（`DreamUISpriteData.cpp`）的
`else//no need to pack to atlas, so spriteTexture self is the atlas` 分支——**`AtlasTexture = SpriteTexture`**，
即 sprite 的「页面」就是外部贴图本身。走到这里有两个自动触发：来源格式不是 `PF_B8G8R8A8`（印
「cannot be packed into the BGRA8 sprite atlas; using it individually」并把 `PackingTag` 清成 `NAME_None`），
以及 `PackSprite` 失败后同样清 tag。**所以「用了 sprite」不等于「绑的是 atlas 页面」。**

### 24b 读卡器那四处，绑的正是裸 `UTexture2D`

`Source/OpenKoikatsu/OKReaderScreen.cpp` 的四处 `Brush.SetResourceObject(...)` 全部走 24a 第 1 条：

| 行 | 来源 |
|---|---|
| `:189-193` | `UOKAppearanceButton::Thumbnail` 的 UMG brush 里的 `UTexture` ——**外观挑选器的缩图** |
| `:249-254` | 任意 UMG `UImage` 的 brush 里的 `UTexture` |
| `:1457`（`Show`） | 卡片列表每格的缩图 `UTexture2D` |
| `:1297` | 同上，清成 `nullptr` |

**外观缩图是这样做出来的**：`Source/OpenKoikatsu/OKGalleryAppearance.cpp:71`——从磁碟读 PNG，
`UTexture2D::CreateTransient(W, H, PF_B8G8R8A8)`，**上限 2048×2048、非正方**、
`CreateTransient` 不给名字 ⇒ 名字就是 **`Texture2D_<n>`**，而且它自己呼叫
`OKLogRuntimeTextureLife(TEXT("created(appearance-thumb)"), ...)`。

**这一条要先讲清楚**：`Texture2D_<n>` ＋ `B8G8R8A8` ＋ 非正方 ＋ 进同一本 runtime 贴图生命日志，
**外观缩图与卡片 runtime 贴图在追踪报告里长得一模一样**。§16–§18 把故障那张按「名字／格式／尺寸」
归给 `KKTextureRuntime`／`KKRuntimeMaterial`，**这个判别并不唯一**——外观缩图同样符合，而且**它是会被绑进
`DreamUI_MainTex` 的那一种**。这正好解掉 §18 留下的矛盾（「取样者是 UI shader」对上「贴图属於卡片 runtime」）。

**判别办法（不必跑新趟）**：故障那张的 owner／建立点。`OKGalleryAppearance.cpp:71` 印的是
`created(appearance-thumb)`，`KKRuntimeMaterial` 那边印的是别的字串；追踪报告里那一笔的建立事件字串就能分开。
`AppearanceTextures`（`OKGalleryAppearance.cpp:306`）与 `CachedThumb` 的快取则决定它何时失去最后一个强参照。

### 24c 回答「DreamGUI 会不会去拿当前角色的贴图来画」

**读卡器这四处不会。** 它们绑的是磁碟 PNG 解出来的缩图（`CachedThumb(Path)`）与卡片列表缩图
（`OKReaderScreen.cpp:1216-1221`，上限 288×402），**都不是活角色的 runtime 贴图**；
我在 `Source/` 与 `Plugins/{KKRuntimePose,KKUnityBundle,OKStudio}` 里搜 `SetResourceObject`／
`UDreamUISpriteData`，除上述四处外，命中的只有编辑器的 Slate brush（`OKModelEditorToolkit.cpp:357/:362`）
与 OK Studio 的两处（`SOKStoryView.cpp:176`、`SOKStudioVngePanels.cpp:324`），**读卡器流程里没有**。

**所以「那张贴图放手时还被新卡用着」与「DreamGUI 在画它」两件事，在程式码上没有共同的站点。**
要让它们相容，只有两种可能，而且都可以用现有资料判：

1. 故障那张**不是**卡片 runtime 贴图，而是**外观缩图**（24b 的判别）；
2. 取样者**不是** DreamGUI——这正是 e-cardload 的 `-LegacyReader` 三趟要判的。

### 24d 粒度到此为止之后，剩下的读法

breadcrumb 既然八笔同时 `[Active]`、只印 7 个槽，就不可能靠它指认。**能把范围再收一次的最便宜的事，
是把漏印的两个槽补进 breadcrumb**（`MaskTex1`、`RenderLayerTable`，`DreamUIRenderer.cpp:1033` 那一行后面
加一个 `RHI_BREADCRUMB_EVENT_F`），以及 **开 `DreamGUI.LogStaleTextures`（§23c，执行期 cvar、不必重编）**。
这两件都不是修法，是量测。

---

## §25 那四处 brush 实际放进去的是哪些贴图：没有一处是角色 runtime 贴图

读的是 E 树（只读）。**先更正 §24b**：我在那里说「归属判别并不唯一，因为外观缩图同样叫 `Texture2D_<n>`、
同样 BGRA8」。这个保留**正确但已被更强的证据覆盖**：e-cardload 的交接反查显示故障那张被交给 12 个 MID，
**而且带着材质参数名**（`_overtex1`、`_MainTex`、`_DetailMask`、`_NormalMap`、`_liquidmask`、`_Texture2/3`），
跨两个 actor 透过 identity 快取共用。**外观缩图不会被 `SetTextureParameterValue` 设成 `_overtex1`。**
所以归属是量到的，不是靠名字推的；§24b 那一段只保留「名字／格式不足以分辨」这个事实，
**不再作为「故障那张可能是外观缩图」的依据**。

### 25a 逐处：放进 brush 的是哪一种贴图

镜射的入口是 `UOKDreamControl::Sync()`（`OKReaderScreen.cpp:163`），镜射控件的建立在 `:629`
——**`Source->IsA<UImage>()` 就给一个 DreamGUI 镜像**，所以站点 2 的覆盖面是「读卡器镜射树里的每一个 UMG `UImage`」。

| 站点 | 行 | 放进去的物件 | 来源 | 种类 |
|---|---|---|---|---|
| 1 | `:189-193` | `A->Thumbnail->GetBrush().GetResourceObject()` | `OKGalleryAppearance.cpp:306` `B->Thumbnail->SetBrushFromTexture(G->CachedThumb(Path))`；`CachedThumb` → `OKGalleryAppearance.cpp:71` 从**磁碟 PNG** 解码 `CreateTransient(W,H,PF_B8G8R8A8)`（上限 2048），日志字串 `created(appearance-thumb)` | **外观素材缩图** |
| 2 | `:248-254` | 任何被镜射的 UMG `UImage` 的 `GetBrush().GetResourceObject()`（只取 `UTexture`） | 读卡器树里实际有贴图的 `UImage`：`OKGalleryWidget.cpp:1447` `PreviewImage->SetBrushFromTexture(Tex,true)`（`Tex` = `TextureFromPng(Selected.Header.PreviewPng)` 或 `AnimatedPreviewTextures[0]`）、`:1774`（APNG 逐帧换，`AnimatedPreviewTextures[Frame]`，建立在 `:1432`，日志 `created(gallery-apng)`）、`OKHScene.cpp:4725`（`CoordImages`，建立在 `:4724`，日志 `created(hscene-coord)`） | **卡片 PNG 预览／APNG 影格／服装清单缩图** |
| 3 | `:1457`（`Show`） | `UTexture2D* Texture` 参数 | 清单缩图池，`:1216-1221` `CreateTransient(Thumb.Width,Thumb.Height,PF_B8G8R8A8)`，上限 288×402 | **卡片清单缩图** |
| 4 | `:1297` | `nullptr` | 同上，退场时清掉 | — |

**四处全部是「CPU 解码出来的像素再 `CreateTransient` 上传」的 UI 缩图／预览**，没有一处读材质参数、
没有一处拿 `KKRuntimeMaterial` 的输出。

### 25b 「有没有任何一处会拿到当前角色正在用的 runtime 贴图」——没有

`OKCreateRuntimePreparedTexture`（`KKRuntimeMaterial.h:42`，`KKRuntimeMaterial.cpp:517`）是建那种贴图的**唯一**入口。
全树（`Source/`、`Plugins/KKRuntimePose/Source`、`Plugins/KKUnityBundle/Source`）的呼叫端只有三类：

- `Plugins/KKUnityBundle/Source/KKUnityBundle/Private/KKPreviewRuntimeMaterials.inl:74`
  ——进 `Role.Textures` 与 `To.Textures`，然后 `SetTextureParameterValue` 到 MID；
- `Source/OpenKoikatsu/OKCrowdRuntimeScene.cpp:1173`——人群场景，进 `E->Textures`；
- `Source/OpenKoikatsu/OKCrowdRuntimeGpuProbe.cpp:160/162/165/166/213/277/278`——自我测试。

**没有一处把它交给 UMG `UImage`、`FSlateBrush` 或 `FDreamUIImageBrush`。** 反方向也搜过：
`Source/` 里 `SetBrushFromTexture`／`SetBrush(` 的全部命中是 `OKGalleryAppearance.cpp:306`、
`OKGalleryWidget.cpp:1112/1332/1447/1449/1774`、`OKHScene.cpp:4725`，来源都在 25a 表里；
`SetBrushFromMaterial` 零命中，所以也没有「把角色材质本身当 brush」的路径
（`KKPreviewActor.cpp:3705` 的 `SetTextureParameterValue(TEXT("KKShadowDepth"), Shadow->Depth)`
是 render target 进 MID，不进 UI）。读卡器里也没有 `SceneCapture`／`TextureRenderTarget2D` 的角色预览。

**所以链子没有闭合。** 结论照协调给的两分法写：消费端的机制形状在 DreamGUI（§24a 那一条裸 `UTexture` 分支是真的，
而且读卡器确实在用），**但被绑进去的不是那张贴图**——`_overtex1` 那一张进不了这四个站点。
**还缺一步**，而且缺的那一步不在这四处。

### 25c 这个否定把范围收到哪里

若 `-LegacyReader` 三趟 0/3 不故障（取样者确实是 DreamGUI），那么 25b 的否定意味着：
**绑进 `DreamUI_MainTex` 的那张 UI 缩图，与故障的那张角色贴图，是两张不同的贴图**，
而故障发生在画前者的 draw 里。这只剩两种形状能同时成立：

1. **取样的不是 `MainTex` 这个槽**，而是 §23a 列的、**breadcrumb 没印的那几个**
   （`MaskTex1`、`RenderLayerTable`）——但这两个在读卡器里也没有角色贴图的来源，所以同样要先量；
2. **取样的不是 shader 绑的那个 descriptor**，而是 descriptor 表／PSO 这一层把别的位址带进了这一笔 draw
   ——这一层我没读，而且它不是「某个 C++ 成员存了裸位址」的形状，不能用那把尺找。

**第 1 条可以用一行 breadcrumb 排掉**（§23a 末），**这是现在最便宜的下一步**；
第 2 条要等第 1 条排掉之后再谈，而且它要的是量测不是阅读。

---

## §26 `VirtualTextureUpdate` 那个节点：名字是历史遗留，没有已配置的 VT 时它只有一个 UAV transition

引擎读的是 `E:/PhysX/UE5.8`（与 F 的 `F:/UE5.8` 同一个 commit，§11），专案读的是 E 树（只读）。

### 26a VT 支援预设是**开**的，而且本专案从没覆写

`r.VirtualTextures` **预设 1**，`ECVF_RenderThreadSafe | ECVF_ReadOnly`
（`Source/Runtime/Engine/Private/Texture.cpp:66-70`），对应专案设定 `URendererSettings::bVirtualTextures`
（`Classes/Engine/RendererSettings.h:413-417`，`ConfigRestartRequired`）；判定走
`UseVirtualTexturing()`（`Runtime/RenderCore/Private/RenderUtils.cpp:1194-1199`）。

本专案 **`Config/*.ini` 里 `VirtualTexture` 零命中**，`Source/`、`Plugins/KKRuntimePose/Source`、
`Plugins/KKUnityBundle/Source`、`Plugins/KKCard/Source` 里 `VirtualTextureStreaming`／`VirtualTexture` 也**零命中**。
**所以 VT 支援是开的（引擎预设），但「支援开着」不等於「有任何 VT 贴图存在」。**

### 26b 读卡器那些 `CreateTransient` 贴图**不可能**进 VT 系统

- `UTexture2D::CreateTransient`（`Runtime/Engine/Private/Texture2D.cpp`）**从头到尾没有碰
  `VirtualTextureStreaming`**：它只设 platform data 的 `SizeX/SizeY/NumSlices/PixelFormat`、
  `bNotOfflineProcessed`、第 0 层 mip。`VirtualTextureStreaming` 是 `uint8 : 1` 的 `UPROPERTY`
  （`Classes/Engine/Texture.h:1610-1611`），UObject 零初始化 ⇒ **0**。
- 门槛是 `UTexture2D::IsCurrentlyVirtualTextured()`（`Texture2D.cpp`）：
  **`VirtualTextureStreaming && GetPlatformData() && GetPlatformData()->VTData`** 两个都要。
  `VTData` 只有资产烘焙（editor texture build）才会产生，`CreateTransient` 不建。

**所以协调的预期是对的：`KKRuntimeMaterial` 与读卡器的 `CreateTransient` 贴图全部不是 VT。**
母材质有没有 VT 取样节点这一题，用二进位 grep 扫了，**先讲它的区分力**：拿一个一定不用 VT 的
贴图资产当对照——`Content/IndependentResources/RuntimeMaterials/R1145/T_black.uasset` 里
`VirtualTextureStreaming` 命中 1 次（那是**序列化属性名**，每个 `UTexture2D` 资产都有），
`RuntimeVirtualTexture` 与 `MaterialExpressionRuntimeVirtualTextureSample` 都 **0**。
**所以 `VirtualTextureStreaming` 这个字串没有判别力，`RuntimeVirtualTexture*` 有。**

按这个标准扫全 `Content/`：`RuntimeVirtualTexture`／`MaterialExpressionRuntimeVirtualTextureSample`／
`RuntimeVirtualTextureOutput` 的命中**只有** `Content/Scenes/CrowdRoom/EnvironmentR1/M_*.uasset`（9 个）
与 `Content/Scenes/StreetSocial/Materials/StreetMaterial00.uasset`。
`Content/Koikatsu`、`Content/PaintDemo`、`Content/IndependentResources`、
`Plugins/KKRuntimePose/Content`、`Plugins/OKStudio/Content` **零命中**。
**这些命中全在 CrowdRoom／StreetSocial 的内容里，读卡器场景不载入它们。**

### 26c 那个 breadcrumb 节点实际是什麼：**VT feedback，不是 page upload**

`VirtualTextureUpdate` 这个名字在整个 Renderer 里**只有一处**产生：
`Runtime/Renderer/Private/VT/VirtualTextureFeedbackResource.cpp:125`
`RDG_EVENT_SCOPE_STAT(GraphBuilder, VirtualTextureUpdate, "VirtualTextureUpdate")`，
而且它上面一行的注解自己讲明名字是历史遗留：
「VirtualTextureFeedback would be a more descriptive stat name, but VirtualTextureUpdate was used
historically and some profile tools may depend on that.」

**真正的 VT page update 不叫这个名字**：那是 `FVirtualTextureSystem::BeginUpdate`／`EndUpdate`
（`Runtime/Renderer/Private/DeferredShadingRenderer.cpp:1917`、`:2296`）。

这个 scope 里的内容，按顺序：

1. `:127-131` `AddPass(..., RDG_EVENT_NAME("VirtualTextureFeedbackTransition"), ...)`
   ——`EndUAVOverlap` ＋ 一个 `FRHITransitionInfo(UAV, UAVMask → SRVCompute)`。**纯 transition，不取样任何东西。**
2. `:134-138` **`if (!FVirtualTextureSystem::Get().HasAllocatedVirtualTextures()) return;`**
   （`VirtualTextureSystem.h:189`：`AllocatedVTs.Num() > 0`），注解写
   「If there are no allocated VTs then we can assume that no GPU feedback was generated.」
3. 之后才是压缩与 readback：`RegisterExternalBuffer(PooledBuffer, ERDGBufferFlags::SkipTracking)`、
   `CompactedFeedback`／`HashTableKeys`／`HashTableElementIndices`／`HashTableElementCounts` 等
   **全部是 RDG buffer，没有一个是贴图**（`:140-175`）。

**所以第 3 题的答案**：这个 pass 读的是一个 pooled feedback buffer 与几个当帧 RDG buffer，
**它不绑任何贴图、也没有 page table／physical space 的贴图快取**；page table／physical space 属於
`FVirtualTextureSystem`，那是另一个 pass 的事，而且在没有 `AllocatedVTs` 时整条都不跑。
**「只存位址」的形状在这里找不到。**

### 26d 第 4 题：节点为什麼还在——**scope 开在 early-out 之前**

`RDG_EVENT_SCOPE_STAT` 在 `:125`，early-out 在 `:135`。**所以就算一个 VT 都没有，
`VirtualTextureUpdate` 这个节点照样存在，里面就只有那一个 `VirtualTextureFeedbackTransition`。**
它不是「RDG 的空 pass」，是「一个 UAV transition」——**但同样不可能在贴图位址上 page fault。**

### 26e 那个冲突，照协调要求明确写出来

把 26c／26d 与 §25 并排，就得到一个不自洽的三角，**我不绕过它**：

- **26c／26d**：`VirtualTextureUpdate` 分支不取样贴图 ⇒ **故障不在它身上**（除非 `AllocatedVTs > 0`，
  而那要量，见下）。
- **§25**：角色 runtime 贴图（故障那张，带 `_overtex1` 等参数名）**进不了 DreamGUI 的四个 brush 站点**，
  程式码上没有第五条路。
- **两者相加**：`[Active]` 的两个分支，一个不碰贴图，另一个碰的不是这张贴图。**所以至少有一个前提是错的。**

**三个候选，按便宜排序**，每一个都可以用现有资料或零成本的一步判：

1. **`[Active]` 不等於「出错的那一个」。** breadcrumb 只说「这些还没结束」。在 D3D12 上
   `DumpActiveBreadcrumbs` 印的是 In／Out 标记之间尚未回收的节点，**整个 `RenderFinish` 子树都会在那里**，
   包括与故障无关的同层节点。**这一条是我认为最可能的**，而且它意味着 breadcrumb 这条线到此为止，
   不该再从「哪个节点 Active」推取样者。
2. **`AllocatedVTs > 0`**（例如某个 engine／plugin 内容带了 VT）。**零成本判别**：在那一趟的 log 里
   下 `r.VT.Dump`（`VirtualTextureSystem.cpp:301`）或 `r.VT.DumpPoolUsage`（`:305`）；
   或者直接看现有崩溃档里有没有 VT 相关的 pool 配置行。**不必重编。**
3. **取样者不在这两个分支里**，而是在 descriptor 表／PSO 那一层（§25c 第 2 条）。这一层我没读，
   而且它不是「某个 C++ 成员存了裸位址」的形状，**那把尺找不到它**。

**`-LegacyReader` 三趟正好把候选 1 与候选 2／3 分开**：若 0/3 不故障，取样者确实与 DreamUI 的 draw 相关，
那麼 §25 的否证就说明「绑进去的贴图」与「故障的贴图」是两张，**问题落在候选 3**；
若照样故障，取样者与 DreamUI 无关，**而候选 2 只要一行 `r.VT.Dump` 就能判掉**，剩下的还是候选 3。
**两种结果都指向候选 3，所以我建议把量测力气放在那里，而不是继续读 VT。**

---

## §27 `E6753E1E…` 是什麼、怎麼变成名字：**那串就是 DXIL 容器的 HASH 区块，而最便宜的一步是免费的**

读的是 `E:/PhysX/UE5.8`（只读）。§22 列过三个符号旗标，这一节补的是它们与 Aftermath 的接法，以及那串 hash 的身分。

### 27a 那串 hash 的出处：**是 UE 自己印的，而且它是 DXIL 的 `HASH` 区块**

`Runtime/RHICore/Internal/ShaderBinaryUtilities.h` 的 `GetShaderBinaryDebugHashDXBC` 走 DXBC 区块表，
三个区块各填一个栏位：

| 区块（四字元反序） | 填进 `FShaderDebugData` 的 | 内容 |
|---|---|---|
| `'HSAH'` ＝ `HASH` | **`Hash`** | `DXIL::FShaderHashInfo{ uint32 Flags; uint8 Digest[16]; }` → `BytesToHex(16 bytes)` ⇒ **正好 32 个 hex 字元** |
| `'0VSP'` ＝ `PSV0` | `FunctionName` | revision ≥ 3 时，从 string table 取 `EntryNameOffset` 处的**进入点名**（`FPSVRevision3Info`） |
| `'NDLI'` ＝ `ILDN` | `PDBName` | 长度必须是 `32 + strlen(".pdb")` ⇒ **`<同一串 32 hex>.pdb`** |

崩溃时 `AppendGpuCrashShaderBinaryInfo`（`Runtime/RHICore/Private/RHICoreNvidiaAftermath.cpp:384-423`）
依序印：`Aftermath Binary Hash = %llu`（`:396`）、`DebugName = '%s'`（`:406`）、`Function = %s`（`:411`）、
`Shader PDB = %s`（`:416`）、**`Shader Hash = %s`（`:420-421`）**。

**所以 `E6753E1EA9F1F20775D8BC0AD963B1EF` 就是 `Shader Hash =` 这一行，来自 DXIL 容器里的 `HASH` 区块**
——**不需要任何旗标**，它是从 shader 的位元组里当场解出来的。

**这给出一个免费的第一步，比重编早一步**：既然 `Shader Hash =` 印出来了，表示
(a) 这个 shader **有**被注册（`ShaderBinaryToDebugHash`），(b) 崩溃时**查到了** `Candidate`
（`:398-403`，查不到会印 `! Failed to associate Aftermath hash`）。
**所以同一段 log 里 `DebugName =`／`Function =`／`Shader PDB =` 哪几行在、哪几行不在，直接告诉我们缺的是什麼**：

- `Function =` 不在 ⇒ `PSV0` revision < 3，或区块解析提早 `continue`；
- `Shader PDB =` 不在 ⇒ 容器里没有 `ILDN`（没开符号时 DXC 不写）；
- **`DebugName =` 不在 ⇒ `r.Shaders.ExtraData` 是 0**（见 27b）。

**先 grep 现有崩溃档这四行，零成本。**

### 27b 第 2 题：是同一条路，而且开了 `ExtraData` 就会直接印出 shader 名

链子每一环都查到了：

1. `Source/Runtime/D3D12RHI/Private/D3D12NvidiaExtensions.cpp:40`
   `RegisterShaderBinary(Value->Code.GetData(), Value->Code.Num(), Value->HasShaderName() ? Value->GetShaderName() : nullptr)`
   ——**注册时才决定有没有名字**；
2. `FRHIShader::HasShaderName()` ＝ `!Debug.ShaderName.IsEmpty()`（`Runtime/RHI/Public/RHIResources.h:857`），
   而整个 `Debug` 结构只在 `RHI_INCLUDE_SHADER_DEBUG_DATA` 下存在
   （`:704-708`：`#if !(UE_BUILD_SHIPPING || UE_BUILD_TEST)` ⇒ **Development 有，Shipping／Test 没有**，
   没有时 `HasShaderName()` 直接 `return false`，`:880-881`）；
3. `Debug.ShaderName` 的唯一填入点：`Source/Runtime/D3D12RHI/Private/D3D12Shaders.cpp:38`
   `OutShader.Debug.ShaderName = InShaderCode.FindOptionalData(FShaderCodeName::Key)`；
4. 那笔 optional data 的唯一写入点：
   `Source/Developer/Windows/ShaderFormatD3D/Private/D3DShaderCompiler.inl:560-563`
   ——**`if (Input.Environment.CompilerFlags.Contains(CFLAG_ExtraShaderData))` 才写**；
5. 那个 flag 的设定点：`Source/Runtime/Engine/Private/ShaderCompiler/ShaderCompiler.cpp:3654-3658`
   `if (ShouldEnableExtraShaderData(ShaderFormatName))`，而
   `ShouldEnableExtraShaderData`（`Runtime/RenderCore/Private/ShaderCore.cpp:978-982`）就是读
   **`r.Shaders.ExtraData`**（预设 0，§22）。

**所以：`r.Shaders.ExtraData=1` ＋ 重编之后，崩溃 log 会直接多一行 `DebugName = '<shader type 名>'`**，
不必解 dump、不必 Nsight。**这正是我们要的那个名字。**

那 1 秒的等待是另一回事，但同一个档：**late shader associations**
（`RHICoreNvidiaAftermath.cpp:845-885`，`GLateShaderAssociateFunc` ＋ `ShaderDebugInfoLookup` callback），
上限是 `r.GPUCrashDebugging.Aftermath.LateShaderAssociations.TimeLimit` **预设 7.5 秒**（`:112-117`，`ECVF_Default`）
与 `...FrameLimit` **预设 10**（`:119-124`）。注册本身的总开关是
`r.GPUCrashDebugging.Aftermath`（`:98-102`，**预设 1**，`ECVF_ReadOnly`）——**已经是开的**，这也解释了为什麼
`Shader Hash =` 本来就有。

### 27c 第 3 题：**旧的 `.nv-gpudmp` 事后解不了**

两个独立的理由，都查到了：

1. **三个符号旗标都进 shader map key**：`Runtime/RenderCore/Private/Shader.cpp:1862-1885`
   ——`ExtraData`、`Symbols`、`SymbolsInfo`、`FullDbg` 各自 `KeyGen.Append`。**key 变 ⇒ DDC 失效 ⇒ 重编。**
2. **重编出来的容器位元组会不一样**：`Source/Developer/Windows/ShaderFormatD3D/Private/D3DShaderCompilerDXC.cpp:278-279`
   ——`bStripReflection = !Input.Environment.CompilerFlags.Contains(CFLAG_ExtraShaderData)`，
   **开了 ExtraData 就不再剥掉 reflection**。容器内容变 ⇒ **`HASH` 区块的 digest 变** ⇒
   旧 dump 里的 `E6753E1E…` 对不上新符号。

另外，旧 dump 旁边本来就**没有** shader debug info：`.nvdbg` 只在
`r.GPUCrashDebugging.Aftermath.DumpShaderDebugInfo` ≠ 0 时才写
（`RHICoreNvidiaAftermath.cpp:105-110`，**预设 0**，`ECVF_ReadOnly`；写出路径
`FPaths::ProjectLogDir()/<id0>-<id1>.nvdbg`，`:358-382`，并 `FGenericCrashContext::AddFile` 挂进崩溃档）。
**所以「连重跑都不必」不成立——要名字就得重编一次再跑一趟。**

### 27d 第 4 题：不重编能做到什麼、做不到什麼

**能做到（免费）**：

1. **grep 现有崩溃档的那四行**（27a 末）。`Shader Hash =` 已经在了，所以这一步只是看另外三行哪几行在。
   **这是最便宜的一步，而且可能 `Function =` 本来就印了进入点名。**
2. **那 16 个位元组可以在磁碟上的 shader 位元码里直接搜**：`E6753E1E…` 是 `HASH` 区块的 digest，
   **原封不动躺在容器里**，所以把那 32 hex 转回 16 bytes 去搜 shader library
   （`.ushaderbytecode`／`ShaderArchive-*`）或 `GlobalShaderCache-*.bin`，就能找到是哪个容器。
   **这一步定位得到容器，但不保证拿到 UE 的 shader type 名**——容器→type 还要查 archive 的索引表，
   那张表是用 UE 自己的 output hash（`FShaderHash`）当键，不是 DXIL 的 `HASH`。

**做不到**：**我找不到任何 console 命令会 dump「shader type ↔ hash」的对照。**
存在的两个相关命令都不印这个：`ListShaderMaps`（`Runtime/RenderCore/Private/ShaderMap.cpp:85-86`，
还要先开 `:40` 那个追踪 cvar）与 `DumpShaderStats`（`Runtime/RenderCore/Private/Shader.cpp:1468`）。
**所以第 4 题的答案是：没有现成的离线对照表；最接近的是上面第 2 条的位元组搜寻。**

**成本排序（覆盖 §22 的排序）**：
① grep 现有崩溃档的 `DebugName =`／`Function =`／`Shader PDB =` 三行（免费）→
② 把那 32 hex 转 16 bytes 搜 shader 位元码（免费，定位容器）→
③ `r.Shaders.ExtraData=1` ＋ 重编一次 ＋ 重跑一趟（之后每一份崩溃档都直接印 `DebugName`）→
④ `r.Shaders.SymbolsInfo=1`／`Symbols=1` 拿完整 PDB（最重，而且 ③ 已经给出名字，通常不必走到）。

**③ 之后旧 dump 全部作废**（27c），所以**①②要在 ③ 之前做完**。

---

## §28 绑定那一侧：现场绑、每个槽每笔都写、而 texture reference **持有** RHI 贴图——所以那十个槽结构上做不到这件事

读的是 E 树与 `E:/PhysX/UE5.8`（只读）。

### 28a 第 1 题：现场绑，没有槽阵列、没有 descriptor table

`FDreamUIRenderer::DrawBuiltInBatch`（`DreamGUIRenderer/Private/DreamUIRender/DreamUIRenderer.cpp:900`）
每一笔 draw：

- `FDreamUIBaseVS::FParameters VSParameters;`（`:981`）与 `FDreamUIBasePS::FParameters PSParameters;`（`:988`）
  都是**函式区域变数**，每笔 draw 重新建；
- **12 个贴图槽每一个都无条件赋值**（`:983-984`、`:992-1015`），没有「这个槽这次不写」的分支；
- 一次 `SetShaderParameters`（`:985` VS、`:1016` PS）送出去，**DreamGUI 这一侧不保留任何 descriptor**。

唯一的跨 draw 快取是 `FDreamUIBuiltInDrawCache`，而它**只存 shader 与 pipeline 身分**：
`InOutCache->VertexShader`／`PixelShaders[Permutation]`（`:921-938`）与
`InOutCache->Pipeline.Matches/Remember(BlendMode, bIsDepthValid, ReverseCulling, Permutation, NumSamples)`
（`:951-968`）。**没有贴图。**

**所以第 3 题的形状（shader 无条件读 N 个槽、某些没被写入有效值 ⇒ 读到上一次的 descriptor）在这里不成立**：
每个槽每笔都被写。

### 28b fallback 的语义：只在「从没设过」，不在「设过但死了」——但这不重要

`TextureOrFallback`（`:970-974`）：

```
return InReference != nullptr ? static_cast<FRHITexture*>(InReference) : Fallback->TextureRHI.GetReference();
```

判的是**那个 reference 指标是不是 null**，而 reference 在 `ResolveTextures_RenderThread`
（`DreamUIBaseShaders.cpp:86-110`）里只有在「解参当时 `UTexture` 是 null」才会是空的。
**所以 `mask0=fallback` 的意思是「这笔 draw 的元素没有一个读遮罩」，不是「它死了所以换成白图」。**

**但这件事不重要**，因为下面这条把整类都关掉了。

### 28c 硬结论：texture reference **持有** RHI 贴图，所以绑着它不可能读到已释放的记忆体

`Runtime/RHI/Public/RHITextureReference.h` 的 `FRHITextureReference`：

- 成员是 **`TRefCountPtr<FRHITexture> ReferencedTexture;`**——**计数参照，不是裸指标**；
- 唯一的改写入口是 `SetReferencedTexture`，注解写明「Called only from
  `FDynamicRHI::RHIUpdateTextureReference`」；
- 还有一个 `static TRefCountPtr<FRHITexture> DefaultTexture;`，注解说明它是给
  「reference 为 nullptr 时使用的全域黑图」。

D3D12 那一侧（`Runtime/D3D12RHI/Private/D3D12TextureReference.cpp`）：

- `FD3D12DynamicRHI::RHIUpdateTextureReference`（`:109-122`）**先把 null 换成 `GetDefaultTexture()`**
  （`:112`），再 enqueue 到 RHI 执行绪，而且为了「FRHITextureReferences 在这个命令执行前就被删掉」的
  旧崩溃 bug，**额外对 reference 本身取了一个 refcount**（`:111`，注解写明）；
- `SwitchToNewTexture`（`:44-78`）同样 `NewTexture = InNewTexture ? InNewTexture : GetDefaultTexture()`（`:46-47`）。

**把这两件合起来**：
一个被 DreamGUI 持有（`FTextureReferenceRHIRef`，§23b）的 texture reference，
**它所引用的 RHI 贴图也被它计数持有** ⇒ 那块配置**不可能**在 reference 还指着它的时候被释放；
要释放，必须先经 `RHIUpdateTextureReference` 把它换成**全域黑图**。
**所以：绑一个 texture reference，解出来的只会是「还活着的那张」或「全域黑图」，不会是已释放的位址。**

这和 e-cardload 量到的次序也一致（不可达 51209 → **配置释放 51214**）：配置能释放，正说明当时已经没有
任何 reference 持有它。

**结论：`MainTex`、`FontTex`、`WidgetData`、`ClipData`、`RectBlockData`、`PaintData`、`MaskTex0`、`MaskTex1`、
`RenderLayerTable`、`RenderLayerWidgetData` 这十个 reference 背书的槽，结构上做不到「读已释放的位址」。**

### 28d 第 2 题：没有以索引／handle 为键的贴图注册表

除了 §23d 的动态 sprite atlas，整个 DreamGUI 里我只找到一处以位址为键的表：
`DreamGUIRenderer/Private/DreamUIRender/DreamUICompositor.cpp:205`
`static TMap<FRHITexture*, uint32> LastHandedOut;`——那是 `DreamGUI.Experiment.LogPoolReuse`
（`:186-189`，**预设 0**）的量测用，**只把位址当键比对，从不解参**。不是候选。

`FDreamUIMaskTextures::Slots`（`DreamGUI/Public/Core/DreamUIClipMask.h:237`）是
`TWeakObjectPtr<UTexture> Slots[2]`——**weak，不是 handle**，而且注销与 UObject 死亡同步（weak 失效即 null）。

### 28e 第 4 题的答案：**在 reference 那十个槽上「找不到路」**，而剩下的两个是裸位址

12 个槽里**只有两个不是 reference**：

| 槽 | 绑定行 | 存的是 | 生命週期 |
|---|---|---|---|
| `DreamUI_SceneDepthTex` | `:1006` | 函式参数 `FRHITexture* SceneDepthTexture`（**裸指标**） | 由呼叫端在 pass 内传入；screen space 时是 `GBlackTexture`（`:2358-2360`） |
| `DreamUI_BackdropTex` | `:1015` | `InBackdrop->Texture`，型别 `FRHITexture*`（`DreamUIRenderer.h:29`，**裸指标**，plugin 内唯一的裸 `FRHITexture*` 成员） | pass 内由 RDG 产生（`:845`、`:1589-1594`） |

**这两个是 built-in draw 里唯一「只存位址」的绑定**，而且两者都是 DreamGUI 自己的 render target／黑图，
**不是卡片的 runtime 贴图**。所以冲突没有消失，反而更尖锐了：

> 傾印档说出错的是一颗 pixel shader、PC 在那颗 shader 里（`fragment_02 ＠ 0x00045f90`）、
> 而唯一还在飞的绘製是 DreamUI 的 draw；但那颗 PS 能读的 12 个槽里，10 个结构上不可能、
> 2 个绑的不是那张贴图。

**所以照协调的要求，我明确说：这一侧找不到路。** 并且把「下一步该插哪里」讲到行：

1. **插桩点：`DreamUIRenderer.cpp:1017`**（`SetShaderParameters` 之后、`RHI_BREADCRUMB_EVENT_F` 之前）。
   那里已经有现成的 `Named()` lambda（`:1021-1026`）可以照抄形状，把 **12 个槽解出来的
   `FRHITexture*` 位址**印出来（reference 的要印 `GetReferencedTexture()`，不是 reference 自己的位址），
   和 `0x000000256bd01000` 比对。**这一步会直接判掉「是不是这 12 个槽之一」。**
2. **顺手补 §23a 漏印的两个 breadcrumb 槽**（`MaskTex1`、`RenderLayerTable`），同一笔改动。
3. **若 12 个位址都对不上**，那么取样的就不是 shader 绑的那一笔 descriptor，而是 descriptor 表／PSO
   那一层（§25c 第 2 条、§26e 候选 3）——**那层我没读，而且它不是「某个 C++ 成员存了裸位址」的形状，
   那把尺找不到它。**

**另外一个可以免费核对的线索**：`0x000000256bd01000` **是页对齐的**（低 12 位全 0），
而 `Type = AddressTranslationError` 正是「整页已经不在页表里」的样子——
这与「那张贴图的配置被释放、页被还给系统」一致，但**它对「是哪个槽带进来的」没有分辨力**，
所以还是要靠第 1 步的位址比对。

---

## §29 三题直答（§28 已答一与二，这一节补第三题：**那条「没有新值就不动」的路径找到了，在 group 那一支**）

读的是 E 树（只读）。协调那三题与 §28 交叉，所以这里只补新材料，重複的指回 §28。

### 29a 第 1 题：每个槽在 render 侧存什麼——**十个是持有的 reference，两个是裸位址**

完整表在 §23a，型别在 §23b／§28c。一句话版：

- `MainTex`／`FontTex`／`WidgetData`／`ClipData`／`RectBlockData`／`PaintData`／`MaskTex0`／`MaskTex1`／
  `RenderLayerTable`／`RenderLayerWidgetData` ⇒ **`FTextureReferenceRHIRef`**
  （`DreamUIBaseShaders.h:80-92`，`TRefCountPtr`），**不是裸指标、不是 SRV、不是 `UTexture*`**；
- `SceneDepthTex`（`DreamUIRenderer.cpp:1006`，函式参数）与 `BackdropTex`
  （`:1015`，`FDreamUIBuiltInBackdrop::Texture`，`DreamUIRenderer.h:29`）⇒ **裸 `FRHITexture*`**，
  两者都是 pass 内 RDG 产物。
- `UTexture*` 只在**交接那一瞬间**存在（`FDreamUIBuiltInTextures` 的九个裸 `const UTexture*`，
  `DreamUIBaseShaders.h:22-33`），由 `GetTexturesForRenderCommand`（`:55-70`）产生、
  `ResolveTextures_RenderThread`（`:72-110`）当场换成 reference。

**而 §28c 的硬结论是：reference 的 `ReferencedTexture` 是 `TRefCountPtr<FRHITexture>`，
所以持有 reference 等於持有那张 RHI 贴图；配置要能释放，必定已被 `SwitchToNewTexture` 换成全域黑图。**
⇒ 那十个槽绑出来只会是「活的」或「黑图」。

### 29b 第 2 题：fallback **只在「从没设过」**

`TextureOrFallback`（`DreamUIRenderer.cpp:970-974`）判 `InReference != nullptr`，而 reference 只在
「解参当时 `UTexture` 是 null」才为空（`DreamUIBaseShaders.cpp:86-110`）。
**所以 `mask0=fallback` ＝「这笔 draw 没有元素读遮罩」，不是「它死了所以换白图」。**
协调担心的「死掉的槽留著旧 descriptor」在这一层确实没有救援机制——**但 29a 末那条让它不构成问题。**

### 29c 第 3 题：清除时机——**mesh 那一支清，group 那一支不清，而 group 还有一个 `bSame` 早退**

这是这一节的新材料，四个点：

1. **mesh section 的 proxy 入池时会清掉**：
   `FDreamUISectionProxy_Mesh::Disable()`（`DreamGUI/Private/Core/DreamUIMesh/DreamUIMeshComponent.cpp:194-200`）
   ＝ `Material = nullptr; BuiltIn = FDreamUIBuiltInDrawParams(); bDrawStateStale = true; bCanRender = false;`
   而且它上面的注解写明**旧行为是 bug**：「A direct mesh's section used to keep both, and went on drawing
   the old mesh through a material that might no longer exist.」入池由
   `PoolAllSectionData_RenderThread()`（`:640-656`）对每个 section 呼叫 `Disable()`。
2. **group section 的 proxy 入池时不清**：
   `FDreamUIRenderSectionProxy_Group::Disable()`（`:233-237`）**只有 `bCanRender = false;`**，
   `Desc`（`FDreamUICompositeDesc`，含 `Textures` 的那几个 `FTextureReferenceRHIRef` 与
   `ClipMaskTextures`）**原封不动留著**。
3. **而 group 那一支正是「只在有新值时才写」**：
   `UDreamUIMeshComponent::SetGroupSectionComposite`（`:2164-2189`）先算 `bSame`，
   比的其中包含 `Sent.Textures.MainTexture == InDesc.Textures.MainTexture`、`...ClipDataTexture`、
   `...MaskTexture0/1`——**这些都是 `TWeakObjectPtr`，而 `TWeakObjectPtr::operator==` 比的是
   index/serial 组合，不是解参后的指标**。所以**一个 weak ptr 指向已死物件时，它和自己仍然相等**：
   **贴图死了、desc 其他栏位没变 ⇒ `bSame` 为真 ⇒ `return`，render 侧那一份永远不会被重新解参。**
   **这就是协调问的那条路径，位置在 `:2171-2182`。**
4. **built-in 那一支没有这种早退**：`SetMeshSectionBuiltIn`（`:2597-2624`）每次呼叫都送，
   `SetMeshSectionBuiltIn_RenderThread`（`:675-680`）无条件 `MeshSection->BuiltIn = Params; bDrawStateStale = true;`。
   另外 `EnableMeshSection_RenderThread`（`:669-674`，注解「A pooled mesh section taken back by a draw call
   without new geometry: drawn again, with InMaterial」）**只设 `Material` 与 `bCanRender`，不碰 `BuiltIn`**
   ——这只因为 `Disable()` 已经清过才安全。

**但照那把尺，这四点全部不合**：group 留下来的是 `FTextureReferenceRHIRef`（持有）与
`FTexture2DResource` 解出来的 `FTextureRHIRef`（`DreamVisualPostProcessRenderProxy.h:161`、`:177`，
也持有），**不是位址**。持有就不可能让配置被释放（§28c），所以它们会变成黑图或变成洩漏，**不会变成故障**。

### 29d 我卡在哪（照协调要求明说）

**卡在同一件事上：整个 DreamGUI 的 render 侧，我找不到任何「跨帧保存一个贴图位址」的储存。** 盘点过的：

| 可能的形状 | 实际是什麼 | 行 |
|---|---|---|
| 槽阵列／descriptor table | 没有；每笔 draw 都是函式区域 `FParameters`，12 个槽全写 | `DreamUIRenderer.cpp:981-1016` |
| 跨 draw 快取 | 只存 shader 与 pipeline 身分，没有贴图 | `:921-938`、`:951-968` |
| 以索引／handle 为键的注册表 | 没有；唯一以位址为键的是预设关的量测，只比对不解参 | `DreamUICompositor.cpp:205`、`:186-189` |
| 入池残留 | mesh 清、group 不清，但留的是**持有的** handle | `DreamUIMeshComponent.cpp:194-200`、`:233-237` |
| post-process 的 mask | `FTextureRHIRef`（持有真正的 RHI 贴图）＋注解说明为何不留 `FTexture2DResource*` | `DreamVisualPostProcessRenderProxy.h:177`、`.cpp:/SetMaskTexture_GameThread/` |
| 裸 `FRHITexture*` | **只有两个**，都是 pass 内 RDG 产物 | `DreamUIRenderer.cpp:1006`、`:1015`、`.h:29` |

**所以我这一侧的结论是明确的否定**：按程式码，DreamGUI 的 built-in draw 不可能把一个已释放的贴图位址绑进
`MainPS`。而 `-LegacyReader` 0/3 ＋ 基线 6/6 说 Dream 读卡器画面路径是必要条件。
**两者相加，剩下的解释不在「DreamGUI 存了什麼」这一层**，而在：

1. **绑进去的 descriptor 与 shader 实际取样的 descriptor 不是同一个**（descriptor 表／PSO 那一层，
   §25c 第 2 条、§26e 候选 3）；或
2. **故障的贴图根本不是那 12 个槽的任何一个**，而是 Dream 画面路径**同时**让别的东西（角色预览的
   render target、toon shadow 的 capture、群组 pool 的 target）进入某个状态。

**两条都要位址比对才能分，所以插桩位置我给两处**（e-cardload 可以一次改完）：

- **主位置 `DreamUIRenderer.cpp:1017`**（`SetShaderParameters` 之后、breadcrumb 之前）：把
  **12 个槽解出来的 `FRHITexture*` 位址**印出来（reference 的要印 `GetReferencedTexture()`），
  和 `0x000000256bd01000` 比对。**这一步直接判掉上面两条。**
- **次位置：同一行顺手补 §23a 漏印的 `MaskTex1` 与 `RenderLayerTable` 两个 breadcrumb 槽。**

**若 12 个位址都对不上，这条线就该转到 descriptor／PSO 那一层，而那层不能用这把尺读——要量。**

---

## §30 引擎那一半：**引擎会清掉，而且前提本身也不成立**——这一支否证

读的是 `E:/PhysX/UE5.8`（只读）。协调的假设有两个支点，两个都查了，两个都不成立。

### 30a 第 1／2 题：引擎确实会把内层指标换掉，位置与次序如下

`UTexture::BeginFinalReleaseResource()`（`Runtime/Engine/Private/Texture.cpp:1332-1347`）依序做三件事：

1. **`ReleaseResource()`**（`:1335-1338`）→ `UTexture::ReleaseResource()` 把资源交给一个 render command
   （`ENQUEUE_RENDER_COMMAND(DeleteResource)`，内含 `ToDelete->ReleaseResource(); delete ToDelete;`）
   → **`FStreamableTextureResource::ReleaseRHI()`**
   （`Runtime/Engine/Private/Rendering/StreamableTextureResource.cpp`）：

   ```cpp
   if (ensure(TextureReferenceRHI.IsValid()))
   {
       RHIClearTextureReference(TextureReferenceRHI);   // :237
   }
   TextureRHI.SafeRelease();                            // :240
   ```

   **清除在 `:237`，在同一个 render command、render thread 上，而且在 `TextureRHI.SafeRelease()`（`:240`）之前。**
2. **然后**才 `TextureReference.BeginRelease_GameThread()`（`:1339-1342`）→
   `FTextureReference::ReleaseRHI()`（`Runtime/RenderCore/Private/RenderResource.cpp:535-538`）
   ＝ **只有 `TextureReferenceRHI.SafeRelease();`**（放掉引擎自己那一份计数，**不碰内层**）。
3. `ReleaseFence.BeginFence()`（`:1344`），而 `UTexture::IsReadyForFinishDestroy` 等这个 fence
   ⇒ **UObject 不会在这两个 render command 跑完之前被清掉。**

`RHIClearTextureReference` ＝ `UpdateTextureReference(ref, nullptr)`
（`Runtime/RHI/Public/RHICommandList.h:5334-5337`），D3D12 侧把 null **换成 `GetDefaultTexture()`**
（`Runtime/D3D12RHI/Private/D3D12TextureReference.cpp:112`，`SwitchToNewTexture` 再确认一次 `:46-47`），
并且**连带改写那个 reference 自己的 bindless descriptor**（`:55-74`）。

**而且不只 streamable 这一类。** 基底 `FTexture::ReleaseRHI`（`RenderResource.cpp`）
**不**清 reference（它只 `SafeRelease` 三个 RHI handle），清除是各衍生类自己做的，而它们**全都做**：

| 资源类 | 清除行 |
|---|---|
| `FStreamableTextureResource`（`FTexture2DResource` 的基底，**`CreateTransient` 走这条**） | `Rendering/StreamableTextureResource.cpp:237` |
| `FTexture2DDynamicResource` | `Texture2DDynamic.cpp:82` |
| `FTextureCubeResource` | `TextureCube.cpp:513` |
| `FTextureCubeArrayResource` | `TextureCubeArray.cpp:187` |
| `FTextureRenderTarget2DResource` | `TextureRenderTarget2D.cpp:605` |
| 2DArray／Cube／Volume render target | `:297`／`:363`／`:297` |
| `FWebBrowserTextureResource` | `WebBrowserTextureResource.cpp:138` |

**所以照协调的第 2 题：引擎会清掉，清除在 `Rendering/StreamableTextureResource.cpp:237`——这一支不要追。**

### 30b 而且那个前提本身是错的：**间接物件确实持有底层贴图**

协调写「持有那个间接物件会让间接物件活著，但间接物件本身不持有底层贴图」。
`Runtime/RHI/Public/RHITextureReference.h` 的 `FRHITextureReference`：

```cpp
protected:
    TRefCountPtr<FRHITexture> ReferencedTexture;   // 计数参照，不是裸指标
```

**是 `TRefCountPtr`。** （§28c 已记过，这里再钉一次，因为整个假设压在这句话上。）
于是只有两条分支，而**两条都不可能产生「已释放的位址」**：

1. **清除有跑**（30a 证明它会跑）⇒ 内层变成**全域黑图** ⇒ 取样黑图，不会故障；
2. **清除没跑**（假设某条路漏了）⇒ 内层**仍然计数持有那张 RHI 贴图** ⇒ **那块配置根本不可能被释放**
   ⇒ 结果是滞留／洩漏，**不是 page fault**。

**而 e-cardload 量到配置确实被释放了（不可达 51209 → 配置释放 51214），这本身就证明分支 1 发生了。**
所以这个机制在两个独立的理由上都被否证。

至于 `LogStaleTextures` 命中 0：协调说它检查的是 game thread 物件的状态——**这点说得对**
（`DreamUIBaseShaders.cpp:32-51` 的 `CheckNotStale` 只看 `IsValid`／`IsUnreachable`）。
**但那不是盲点，因为内层指标按 30a／30b 不会悬空。**

### 30c 第 4 题：那组 `*RHI` 成员**会跨帧沿用**，但这正是它被设计成 reference 的原因

`ResolveTextures_RenderThread` 只在 `SetMeshSectionBuiltIn` 送出的那个 render command 里跑
（`DreamGUI/Private/Core/DreamUIMesh/DreamUIMeshComponent.cpp:2597-2624`，以及 group／desc 的
`:697`、`:1529`、`:1597`、`:2613`），而 `SetMeshSectionBuiltIn` 只在画布重建 draw call 时被呼叫
（`DreamCanvas.cpp:4011-4035`）。**画布没重建的帧，那组 `*RHI` 就是上一次解参的结果，原样沿用。**

**但沿用不构成问题，而且文件里本来就写明了这是目的**
（`DreamGUIRenderer/Public/DreamUIRender/DreamUIBaseShaders.h:40-46`）：
「A reference follows its texture through every rebuild of the texture's resource -- a font atlas repacked,
a data texture grown, an UpdateResource -- and **outlives the texture, pointing at a black one once it is gone.
The resource pointers they replace were kept across frames and left dangling by each of those**…」
——**换成 reference 这件事，就是为了修掉「跨帧保存资源指标会悬空」这个旧 bug。**

顺带：`Sampler(InTextures.Main)` 存的是 `FSamplerStateRHIRef`（同档 `:81` 起），**也是持有**，
而且 sampler state 在 UE 是共用的静态物件，不随贴图死亡。

### 30d 所以现在的位置

**这一侧（DreamGUI 存什麼 ＋ 引擎怎麼清）两边都查到底，结论是一致的否定**：
built-in draw 的那十个 reference 槽不可能把已释放的位址绑进 `MainPS`。
加上 §28e／§29d 的盘点（没有槽阵列、没有 handle 注册表、入池残留留的是持有 handle、
裸 `FRHITexture*` 只有两个 RDG 产物），**「DreamGUI 存了一个裸位址」这条假设可以关掉了。**

**而 `-LegacyReader` 0/3 ＋ 基线 6/6 仍然成立**，所以 Dream 读卡器画面路径确实是必要条件——
**但它成为必要条件的方式不在这十二个槽里。** 剩两条，两条都要位址比对：

1. **绑进去的 descriptor 与 shader 实际取样的不是同一个**（descriptor 表／PSO 那一层）；
2. **故障的不是这十二个槽的任何一个**，而是 Dream 画面路径同时让别的东西进入某个状态
   （角色预览的 render target、toon shadow 的 capture、群组 pool 的 target）。

插桩位置与 §29d 相同：**`DreamUIRenderer.cpp:1017`**，印 12 个槽解出来的 `FRHITexture*`
（reference 的印 `GetReferencedTexture()`），和 `0x000000256bd01000` 比对；
**这一步是现在唯一能分开上面两条的量测。**

---

## §31 那两个裸位址的槽：短答三件，加上那把尺的一处事实更正

读的是 E 树与 `E:/PhysX/UE5.8`（只读）。

### 31a 第 1 题：是哪两个、什麼型别、写入与绑定在哪一行

| 槽 | 型别 | 写入 | 绑上 shader |
|---|---|---|---|
| `DreamUI_SceneDepthTex` | **`FRHITexture*`**（`DrawBuiltInBatch` 的函式参数，不是 SRV、不是 reference 的裸指标） | pass lambda 内由 RDG 的 `SceneDepthTex` 取得；screen space 没有深度时直接传 `GBlackTexture`（`DreamUIRenderer.cpp:2358-2360`） | `DreamUIRenderer.cpp:1006` |
| `DreamUI_BackdropTex` | **`FRHITexture*`**（`FDreamUIBuiltInBackdrop::Texture`，`DreamUIRenderer.h:29`，整个 plugin 唯一的裸 `FRHITexture*` 成员） | pass lambda 内 `Backdrop.Texture = InBackdrop->GetRHI();`（`DreamUIRenderer.cpp:2363-2365` 一带，前一行先 `InBackdrop->MarkResourceAsUsed()`） | `DreamUIRenderer.cpp:1015` |

两者的来源都是**宣告在 pass 参数结构里的 RDG 贴图**：
`RDG_TEXTURE_ACCESS(BackdropTexture, ERHIAccess::SRVGraphics)`（`:1588`，
`FDreamUIBackdropDrawPassParameters`）、`PassParameters->SceneDepthTex = SceneDepth`（`:1595` 一带）。

### 31b 第 2 题：**没有。鍊子不在这里闭合。**

group 那一支的 `FDreamUICompositeDesc`（`DreamGUIRenderer/Public/DreamUIRender/DreamUICompositor.h:30-76`）
的成员是：`Role`、`Id`、`BlendMode`、`Opacity`、`WorldBounds`、`CanvasToWorld`、`MaskClipCoordinate`、
**`FDreamUIBuiltInDrawParams Textures`**、`bExternal`、`CanvasToUV`、`Effect`、`Style`、`StyleRect`。

**那个 `Textures` 就是 `FDreamUIBuiltInDrawParams` 本身，而它没有任何裸 `FRHITexture*` 成员**
（`DreamUIBaseShaders.h:80-92` 全是 `FTextureReferenceRHIRef`／`FSamplerStateRHIRef`）。
`SceneDepthTexture` 是函式参数、`FDreamUIBuiltInBackdrop` 是另一个 pass 内的结构，
**两个都不在 Desc 里，也不在任何 section proxy 里。**

### 31c 第 3 题：它们的清除时机——**不需要清，因为它们每次 pass 重新产生**

- `FDreamUIBuiltInBackdrop Backdrop;` 是**pass lambda 里的堆叠区域变数**（`DreamUIRenderer.cpp:2361`），
  每次 pass 执行时重新建、填 `GetRHI()`、用完就随 lambda 结束消失；
- `SceneDepthTexture` 同样是每次 pass 传进来的参数。

RDG 对宣告在 pass 参数里的贴图保证「pass 执行期间已配置且有效」，而 `MarkResourceAsUsed()` 把它钉在
该 pass 的生命期内。**所以这两个裸位址从不跨帧、从不被保存，也就没有「来源贴图被 GC 时谁去清」这个问题
——它们的来源不是 `UTexture`，是 RDG 的 render target。**

### 31d 那把尺：一处事实更正（这一句决定整个方向）

协调写「`FTextureReferenceRHIRef` 这种间接物件本身被持有也不会延命底层贴图」。
**在这一版引擎里这句话是错的**：`Runtime/RHI/Public/RHITextureReference.h:53`

```cpp
TRefCountPtr<FRHITexture> ReferencedTexture;
```

**是计数参照**（读写只经 `SetReferencedTexture`，`:48-51`；读经 `GetReferencedTexture`，`:32`）。
**所以持有一个 texture reference，等於连带持有它当下引用的那张 RHI 贴图。**

**也正因为这样，引擎必须在释放前主动把内层换掉——而它确实这麼做（§30a）**：

> **会清。** `UTexture::BeginFinalReleaseResource`（`Runtime/Engine/Private/Texture.cpp:1332-1347`）
> 先 `ReleaseResource()`，那条 render command 走到
> **`FStreamableTextureResource::ReleaseRHI()` 的 `RHIClearTextureReference(TextureReferenceRHI)`
> ——`Runtime/Engine/Private/Rendering/StreamableTextureResource.cpp:237`，在同一个 render command、
> 在 `TextureRHI.SafeRelease()`（`:240`）之前、也在引擎放掉自己那一份 reference（`:1339-1342`）之前**；
> D3D12 把 null 换成全域黑图（`D3D12TextureReference.cpp:112`、`:46-47`），并改写该 reference 的
> bindless descriptor（`:55-74`）。`ReleaseFence.BeginFence()`（`:1344`）＋`IsReadyForFinishDestroy`
> 保证 UObject 不会在这些命令跑完前被清掉。清除不是 streamable 独有，八个贴图资源类全都做（§30a 的表）。

**所以照改过的尺重判，结论不变，但理由更紧**：

1. 那十个槽持有的 handle **会**让底层贴图活著（31d）⇒ 配置不可能在它们还指著时被释放；
2. 而配置**确实**被释放了（你们量到不可达 51209 → 配置释放 51214）⇒ **清除已经发生** ⇒
   那十个槽此刻解出来的是**全域黑图**；
3. 那两个裸位址的槽不跨帧、来源是 RDG render target（31a／31c）。

**⇒ 十二个槽没有一个能在故障当下指向已释放的卡片贴图。** 这是程式码层面的否定，
而它和傾印档（`MainPS`、`1 total`、PC 在那颗 shader 里）并存，所以差的那一步**不在「谁存了什麼」这一层**。

**下一步仍然只有位址比对能分**：`DreamUIRenderer.cpp:1017` 印 12 个槽解出来的 `FRHITexture*`
（reference 的印 `GetReferencedTexture()`，裸的直接印），与 `0x000000256bd01000` 比对。
**若 12 个都不是它，取样进来的就不是 shader 绑的那一笔 descriptor，线索就转到 descriptor 表／PSO 那一层。**

---

## §32 DreamGUI 内「归还／重用而指标还在用」的清查：五处，前三名与检验方式

前提照使用者定调：**错在 DreamGUI 里**。读的是 E 树 `Plugins/DreamGUI` 与 `E:/PhysX/UE5.8`（只读）。
判准照协调放宽：**凡是「资源被归还／释放／重用，而某个指向它的东西之后还会被拿去画」的形状都列**，
不要求符合「故障时没有任何参照」。

### 32a 先讲一件历史线索：**前人已经怀疑过同一件事，而且留了半个结论**

`DreamGUIRenderer/Private/DreamUIRender/DreamUICompositor.cpp:176-191` 的注解（`DreamUIGroupPoolReuse`）：

> 「MEASUREMENT (default off), to say what the "**DelayFrames changes some timing**" actually is.
> A group's target comes from `GRenderTargetPool`, and `FDreamUIDeferredRelease` postpones handing it back.
> If a larger `Frames.Pooled` makes the pool keep MORE distinct elements and hand the same one out FURTHER
> APART, then the queue's effect is simply "memory is reused later" … If the reuse distance does not move,
> that timing is something else.」

**也就是说：已经有人量到「改 DelayFrames 会影响重现」，但还没判定那个 timing 是什麼。**
`Note(FRHITexture*)`（`:197`）与 `static TMap<FRHITexture*, uint32> LastHandedOut`（`:205`）就是为这件事埋的桩
（`DreamGUI.Experiment.LogPoolReuse`，`:186-189`，预设 0），**而它只把位址当键比对、从不解参，所以它本身不是 bug。**
**这段是今天最该先翻的历史线索。**

### 32b 候选一（最像）：群组 render target 归还后**立刻**可被再发出，门槛是帧不是 fence

鍊子：

1. 取得：`GRenderTargetPool.FindFreeElement(...)` → `Frame.Pooled`（`DreamUICompositor.cpp:296`），
   **注册的是 pool element 本身**（`:300`，注解写明「so that it is not handed out again before the passes
   recorded here have run」），`Frame.TextureRHI = Frame.Pooled->GetRHI()`（`:302`，型别是
   `FTextureRHIRef`，`DreamUICompositor.h:116`，**持有**）。
2. 归还：`FDreamUICompositeStack::PopAndComposite()` → **`FDreamUIDeferredRelease::Hold(Top.Pooled)`**
   （`:407-408`，注解「Back to the pool only after the frames that may still read it」）。
3. 放手：`FDreamUIDeferredRelease::Tick_RenderThread()`（`DreamUIDeferredRelease.cpp:115-153`）的判准是
   **`Now - Entry.Frame >= FramesFor(Entry)`，其中 `Now = GFrameNumberRenderThread`**，
   而 `Frames.Pooled` **预设 3**（`:19-22`）。**三个 render frame，不是三个 GPU 完成。**
   到期的 entry 被移进 `Due`，**而 texture／buffer／pooled 三种都没有任何呼叫——它们是靠 `Due` 离开作用域
   时掉参照**（`:134-152`，只有 `Entry.Release` 那种会被呼叫）。
4. 掉的是 `TRefCountPtr<IPooledRenderTarget>` 的最后一份 ⇒ 元件回到 `GRenderTargetPool`；
   再发出的条件只有 **`Element->IsFree()`**（`Runtime/RenderCore/Private/RenderTargetPool.cpp:202`，
   加上 desc hash 与 desc 相等比对），**没有 GPU fence**。

**缺什麼证据**：这条本身只能造成「内容被下一个使用者写坏」，**不会 unmap 记忆体**，
所以不能直接解释 `AddressTranslationError`。要变成 page fault，还需要那个元件**后来被池子真正释放**——
`FRenderTargetPool::TickPoolElements()` 在 `AllocationLevelInKB > MinimumPoolSizeInKB` 时释放
`UnusedForNFrames > 2` 的最旧元件（`:400-420`），**而那条走 UE 自己的延迟删除（有 fence）**。
**所以这条要嘛需要第三个环节，要嘛真正的问题是「归还太早」造成的别的後果。**

**检验方式（零成本，两个桩都已经在、都是执行期 cvar、不必重编）**：

- **`DreamGUI.DeferredRelease.LogEntries 1`**（`DreamUIDeferredRelease.cpp:40-43`）——印每一笔放手的
  `kind=` `name=` `WxH` `held=` 帧数 `now=`，注解写明它就是为这次 page fault 埋的
  （「the only way to answer whether a texture the GPU faulted on was released by THIS queue」）。
  **拿 `name=`／`WxH` 对故障那张。**
- **`DreamGUI.Experiment.LogPoolReuse 1`**（`DreamUICompositor.cpp:186-189`）——印 handouts／distinct／
  reuse gap min-max，**直接回答 32a 那个没判完的问题**。
- 两者併跑，再把 `DreamGUI.DeferredRelease.Frames.Pooled` 调大（例如 16）看重用间隔与故障率一起动不动。
- **另外，`Tick_RenderThread` 第一次跑时会印一行 `DreamGUI deferred release frames in effect: texture=… pooled=…`**
  （`:51-62`，`LogScalesOnce`）——**现有的 log 里就能确认旗标到位，不必重跑。**

### 32c 候选二：font atlas staging 池，归还与再发出之间**没有任何延迟**

`FDreamUIFontAtlasStagingPool`（`DreamGUI/Private/Core/DreamUIFontData_FreeTypeRender.cpp:2955-3032`）：

- `Release(FTextureRHIRef&&)`（`:3016-3031`）——**直接 `FreeTextures.FindOrAdd(Size).Add(MoveTemp(InTexture))`**，
  没有帧延迟、没有 fence；超过 `AtlasStagingPoolByteBudget` 才整个放手（`:3025-3028`），
  **那条才走 UE 的 fenced 删除**；
- `Acquire(...)`（`:2989-3014`）——**立刻 `Bucket->Pop()`** 拿同一张回来，当 region 上传的中介
  （建立时 `SetInitialState(ERHIAccess::CopySrc)`，`:3010-3013`）；
- 格式换掉时 `FreeTextures.Empty()`（`:2995-3000`）——那是整批掉参照。

**缺什麼证据**：同样只造成「上传内容错乱」，不 unmap。而且它只在 font atlas 有 dirty region 时动。
**检验方式**：先用现有 log 确认开卡当下 font atlas 有没有在成长／有 dirty slice；
**不改码就只能看这个**（这个池子没有 cvar）。**所以它排第二：形状符合，但触发条件还没证据。**

### 32d 候选三：`DreamUIDataTexture::ReplaceTexture` 的换图次序

`DreamGUI/Private/Core/DreamUIDataTexture.cpp:132-149`：

```cpp
FTextureRHIRef Texture = RHICmdList.CreateTexture(Desc);
RHICmdList.UpdateTexture2D(Texture, ...);
if (TextureRHI.IsValid() && IsInRenderingThread()) { FDreamUIDeferredRelease::Hold(TextureRHI); }  // :143
TextureRHI = Texture;                                                                              // :145
if (TextureReferenceRHI.IsValid()) { RHICmdList.UpdateTextureReference(TextureReferenceRHI, TextureRHI); }  // :147-148
```

`UpdateTextureReference` 是**入队**的（§30a），所以在它执行之前 reference 仍指著旧的那张。
**但旧的那张同时被 deferred queue 的 `FTextureRHIRef` 与 reference 自己的 `TRefCountPtr` 持有
（§31d）⇒ 活著。** 所以**这一条我判安全**；列出来是因为它是「换新的、旧的只 Hold 三帧」的形状，
而三帧门槛是帧不是 fence（候选一的同一个弱点）。
**检验方式与候选一相同：`LogEntries` 会把这些 `name=DreamUIDataTexture` 的放手一併印出来。**

### 32e 另两项的结论

**第 4 项（dynamic sprite atlas 与 font atlas 本体）**：两者的页面都是 `UTexture2D`／`UTexture2DArray`
（§23d、`DreamUIDynamicSpriteAtlasData.cpp` 的 `CreateAtlasTexture`），**走 GC ＋ 引擎的 fenced 释放
（§30a），不是「归还重用」形状**。重用那一半在 32c 的 staging 池里，已列。

**第 5 项（RDG 外部资源）**：`RegisterExternalTexture` 共 10 处——`DreamUICompositor.cpp:300`、
`DreamUIRenderer.cpp:306`、`:502`、`:503`、`:516`、`:517`、`:530`、`:531`、`:554`、`:1234`、`:1241`。
两件事：

1. **`DreamUIRenderer.cpp:1222-1234` 的注解记录了一个「已修的、形状完全相同的 bug」**，值得整段引用：
   > 「Registering the raw texture wraps it in a throw-away `FPooledRenderTarget` that keeps the texture
   > alive but **not the POOL ELEMENT**, so the element went back to `GRenderTargetPool` the moment this
   > function returned -- which is **before `GraphBuilder.Execute()` runs a single one of the passes
   > recorded below**. The next `FindFreeElement` of the same description in the same frame … then got the
   > very same texture.」
   **修法是改成注册 pooled target（`:1234`）。这证明这个 code base 曾经真的有这个 bug，而且是在 pool 这一层。**
2. **`:1241` 我查完了：安全，而且是设计如此。** 它注册的是裸 RHI 贴图，但那张贴图正是
   `:1241` 前四行刚从 `GRenderTargetPool.FindFreeElement` 取得的 `MSAARenderTarget`（`:1218`）的 RHI
   （`:1236` `ScreenColorRenderTargetTexture = MSAARenderTarget->GetRHI()`），
   而 `:1234` **已经注册过那个 pool element**，上面那段注解的最后一句就说明了后果：
   「every later `RegisterExternalTexture` of the same RHI texture **resolves to it**」
   ——所以 `:1241` 解析到同一个已经持有 pool 强参照的 RDG 贴图。
   另外 `MSAARenderTarget` 是 renderer 的成员（`DreamUIRenderer.h:369`，`TRefCountPtr<IPooledRenderTarget>`），
   **跨帧持有那个元件**，所以它根本不会在帧之间回到池子。**这一条排除。**

### 32f 前三名与一句话检验

| 名次 | 候选 | 行 | 一句话检验 |
|---|---|---|---|
| 1 | 群组 target 归还只等 3 个 render frame、再发出只看 `IsFree()` | `DreamUICompositor.cpp:407`、`DreamUIDeferredRelease.cpp:19-22`／`:115-133`、`RenderTargetPool.cpp:202` | **`DreamGUI.DeferredRelease.LogEntries 1` ＋ `DreamGUI.Experiment.LogPoolReuse 1`，两个现成 cvar，不必重编** |
| 2 | font atlas staging 池零延迟重用 | `DreamUIFontData_FreeTypeRender.cpp:3016-3031`／`:2989-3014` | **先确认开卡当下 font atlas 有 dirty region**（现有 log） |
| 3 | `DreamUIDataTexture::ReplaceTexture` 的 3 帧门槛 | `DreamUIDataTexture.cpp:143-148` | **同候选一的 `LogEntries`，`name=DreamUIDataTexture` 那几笔** |

**三条共同的缺口都一样**：它们解释「资源被别人覆写」，不解释「整页不在页表」。
**所以若 e-cardload 的 mode 2 失败，下一步不是直接挑这三条去改，而是先用候选一那两个现成 cvar
把「故障那张是不是这个队列放手的」问掉——那是零成本，而且注解说那个桩就是为这件事埋的。**

---

## §33 descriptor／绑定这一层：**唯一跨帧的持有者是材质 proxy 的 uniform expression cache**，而且前人已经为它埋好工具

读的是 E 树 `Plugins/DreamGUI`（只读）。**先更正我自己上一节的建议**：我一直在说「要在
`DreamUIRenderer.cpp:1017` 插桩印 12 个槽」——**那件事有一半已经做好了**，见 33e。

### 33a 第 1 题：跨帧保存的 shader binding——**SRV／descriptor handle 全数零命中**

全 plugin（`DreamGUI`、`DreamGUIRenderer`、其余模组）grep：

| 形状 | 命中 |
|---|---|
| `CreateShaderResourceView` | **0** |
| `FShaderResourceViewRHIRef`／`TRefCountPtr<FRHIShaderResourceView>` | **0** |
| `FRHIDescriptorHandle` | **0** |
| `CreateUniformBuffer*` | **4 处，全部 `UniformBuffer_SingleFrame`** |

四处 uniform buffer：`DreamUIRenderer.cpp:1492`、`:2219`（view UB）、
`DreamUIShaders.cpp:128`、`:143`。唯一「做一次、重复用」的是 `InOutDepthTextureBuffer`
（`DreamUIShaders.cpp:136-150`，`if (!InOutDepthTextureBuffer.IsValid())` 才建），
**而它的持有者是 pass lambda 的区域变数**（`DreamUIRenderer.cpp:1614`
`TUniformBufferRef<FDreamUIWorldRenderDepthTexUB> DepthTextureBuffer;`，用在 `:1682`、`:1713`）
**＋ `UniformBuffer_SingleFrame`**。所以它跨 draw、不跨帧。**这一类没有候选。**

### 33b 第 2 题：**唯一跨帧的 descriptor 持有者，是 `FDreamUIMaterialProxy` 继承的 uniform expression cache**

`FDreamUIMaterialProxy` 是 `FMaterialRenderProxy` 的子类，所以它带著引擎的
`UniformExpressionCache[FeatureLevel]`——**一个 uniform buffer，其 resource table 持有该材质的贴图**。
它只在三个地方被重建：

| 时机 | 行 |
|---|---|
| `SetParameters_GameThread` 送出的 render command 里 `CacheUniformExpressions(RHICmdList, false)` | `DreamUIMaterialProxy.cpp:154-165`（`:163`） |
| `FollowSource_RenderThread`（父材质的 expression cache serial 变了才动） | `:167-185`（`:181-184`） |
| `LetGoOfUnreachable`（`PostReachabilityAnalysis`） | `:188-220`（`:219`） |

**没有任何每帧重建。** 所以「descriptor 比贴图活得久」这个形状在 DreamGUI 里**只有这一处**。

清理责任与它的缺口：`LetGoOfUnreachable` 挂在 `FCoreUObjectDelegates::PostReachabilityAnalysis`
（`:122`，`Create` 里一次性注册），只走 `LiveProxies()`（`:46`、`:143`，一张 `TWeakPtr` 清单），
只在 `IsGone(InTexture.Value)` 时把那笔贴图从 `GameThreadParameters.Textures` `RemoveAll` 再重建快取
（`:211-219`），注解写「Carried out before the objects are freed: freeing them waits for the render thread
to pass their release.」**缺口是：它只管 proxy 自己那张 `TArray<TPair<FName, const UTexture*>> Textures`
（`DreamUIMaterialProxy.h:15`，非持有），父材质（`GetParent()`，`:222-232`）自己的 uniform expression
cache 不在它手上。**

### 33c **前人已经为这一条埋好工具，而且读法事先登记了**（这是本节最重要的一段）

`DreamUIMaterialProxy.cpp:79-98` 的注解，照抄要点：

> 「EXPERIMENT (default off), and **NOT a fix candidate**: when on, a proxy that has lost its last reference is
> never deleted at all -- it is deliberately leaked. … **`Frames.Func=240` only moved the crash from card 4/7
> to 19/15**, so a count cannot say whether the destructor is the trigger. Never running it can.
>
> Reading registered before the run: if the crash disappears in BOTH reproductions, **the trigger is the
> proxy's destructor itself (which lets go of the texture refcounts its uniform buffer holds for the material,
> and MainPS binds the same textures)**. If it still faults, the destructor is not the trigger…」

三件因此确定：

1. **旗标会动它**：`Frames.Func=240` 把崩溃从第 4／7 张移到第 19／15 张——**不是消掉，是推后**；
2. **`DreamGUI.Experiment.NeverDeleteProxy`**（`:95-98`，预设 0，`ECVF_RenderThreadSafe`，**执行期可开、不必重编**）
   是现成的判别器，而且是「永不解构」而非「延后解构」，所以它能分开计数分不开的两件事；
3. **假设本身已经把 `MainPS` 接上了**：proxy 的 uniform buffer 为材质持有贴图 refcount，而 `MainPS` 绑同一批贴图。

**这是今天唯一一个「能分辨机制、零建置、读法事先登记」的工具。**

### 33d 第 3 题：RDG 外部注册有没有存过帧——**没有**

`FRDGTextureRef` 作为成员的全部出现：`DreamUICompositor.h:114`（`FFrame::Texture`）、`:126`（`HeldBase`）
——两者都在 `FDreamUICompositeStack` 里，**那是一帧的栈**；`DreamUILayerStyleComposite.h:30`、
`Effects/DreamUIBackdropEffectPasses.h:19`／`:50`——pass 内。**没有一处跨帧。**
`MSAARenderTarget` 是 renderer 成员，但它持有的是 pool element（§32e），属於跨帧**滞留**，不是悬空。

### 33e 第 4 题：`DreamUI_SceneDepthTex`，以及 **`DreamGUI.LogTextureSlots` 已经存在而且已接上**

**SceneDepthTex 绑的是谁的 RHI**：`DreamUIRendererLocal::SceneDepthOf(GraphBuilder, InView)`
（`DreamUIRenderer.cpp:1178-1199` 一带，呼叫在 `:1201-1203`）——取的是**场景渲染器的**
`GetSceneTextureShaderParameters(InView)` 的 `SceneTextures->GetContents()->SceneDepthTexture`
（行动平台走 `MobileSceneTextures`），**拿不到就 `GSystemTextures.GetDepthDummy(GraphBuilder)`**；
render-target 模式（`RendererType == EDreamUIRendererType::RenderTarget`）**直接用 dummy**。
绑定点：built-in 走 `:1006`（裸 `FRHITexture*`，pass 内），材质路径走 `:1682`／`:1713`
（包进那个 single-frame uniform buffer）。**两条都不跨帧保存。**

**有没有现成 cvar 关掉它**：**没有。** 我把 `DreamGUI.*` 的全部 cvar 都列了（下表），没有 depth blend 的开关；
最接近的是把画布设成 screen space——那时 `:2358-2360` 直接给 `GBlackTexture`——**但那是内容设定，不是 cvar。**

**现成 cvar 全表（这张表对下一趟直接有用）**：

| cvar／命令 | 预设 | 行 |
|---|---|---|
| `DreamGUI.LogStaleTextures` | 0 | `DreamUIBaseShaders.cpp:27` |
| **`DreamGUI.LogTextureSlots`** | 0 | `DreamUIBaseShaders.cpp:69-72` |
| `DreamGUI.Experiment.LogPoolReuse` | 0 | `DreamUICompositor.cpp:187` |
| **`DreamGUI.Experiment.NoBackdrop`** | 0 | `DreamUICompositor.cpp:348` |
| `DreamGUI.DeferredRelease.Frames.Texture/Buffer/Pooled/Func` | 3／3／3／3 | `DreamUIDeferredRelease.cpp:12/16/20/24` |
| `DreamGUI.DeferredRelease.LogEntries` | 0 | `DreamUIDeferredRelease.cpp:41` |
| `DreamGUI.LogDeferredRelease`（命令） | — | `DreamUIDeferredRelease.cpp:164` |
| **`DreamGUI.Experiment.NeverDeleteProxy`** | 0 | `DreamUIMaterialProxy.cpp:96` |
| `DreamGUI.LogHeldTextures` | 0 | `DreamCanvas.cpp:4115` |
| `DreamGUI.Memory`（命令） | — | `DreamUIMemoryReport.cpp:487` |

**更正我自己的建议**：`DreamGUI.LogTextureSlots` **已经写好并接上了**
——定义 `DreamUIBaseShaders.cpp:54-108`，呼叫 `:167-175`，在 `ResolveTextures_RenderThread` 里
对**九个 reference 槽**各印一次 `src=` `ref=` `referenced=` `referenced_name=` `frame=`，
只在值变化时印，外加每 600 帧一次心跳（所以乾淨的一趟也能看出仪器活著）。
注解把读法也登记好了，而且**它自己就引用了我 §28c／§31d 给的那条事实**：

> 「the indirection does NOT merely borrow its target. `FRHITextureReference` holds it as
> `TRefCountPtr<FRHITexture>` (RHITextureReference.h:53) … The measured chain says the allocation WAS
> released, so one of these must be true: **(a)** the reference was pointed somewhere else (a default texture)
> before the release, leaving nothing stale -- then no slot ever names the faulting texture; or **(b)** a slot
> still names it, and then **the release happened despite a live refcount, which would be the find**.」

**所以 §28／§31 那条「不可能」已经被接成一个可量的二分法，而且桩已经在。**
**它还没覆盖的只有两件**：`SceneDepthTex`／`BackdropTex` 这两个裸位址槽（不在那九个里），
以及「每笔 draw 真正绑进去的那一笔」（桩在 resolve 点，不在 `:1016` 的绑定点）。

### 33f 前三名，以及每条能不能解释 `AddressTranslationError`

| 名次 | 候选 | 行 | 怎麼验 | 能解释整页不在页表吗 |
|---|---|---|---|---|
| 1 | **材质 proxy 的 uniform expression cache 跨帧持有贴图，而只在三个时机重建** | `DreamUIMaterialProxy.cpp:154-165`／`:167-185`／`:188-220`；缺口在 `:222-232` 的父材质 cache | **`DreamGUI.Experiment.NeverDeleteProxy 1`**（`:96`，执行期 cvar，读法已登记于 `:79-93`）；对照 `DreamGUI.DeferredRelease.Frames.Func` 240 已知会把崩溃推后 | **差一环**：uniform buffer 的 resource table 是持有参照，持有就不该被释放。要成立，必须「释放绕过了 refcount」——**而那正好是 33e 的 (b)**，所以这两条是同一个检验的两面 |
| 2 | **`DreamGUI.LogTextureSlots` 的 (a)/(b) 二分**（判别器，不是候选） | `DreamUIBaseShaders.cpp:69-108`／`:167-175` | **开 cvar 跑会故障的那一趟**，看有没有任何 slot 的 `referenced_name=` 对上故障那张 | **(b) 成立就能解释**：那意味著释放路径没看 refcount，页才会真的被还掉；(a) 成立则这整条关掉 |
| 3 | 群组 pool 归还只等 3 帧（§32b）＋ font staging 零延迟重用（§32c） | `DreamUICompositor.cpp:407`；`DreamUIFontData_FreeTypeRender.cpp:3016-3031` | `DreamGUI.DeferredRelease.LogEntries 1` ＋ `DreamGUI.Experiment.LogPoolReuse 1` | **不能**：它们解释「内容被覆写」，不解释 unmap。差的那一环是「谁把页还给系统」 |

**一句话**：这一层查完之后，**唯一跨帧的 descriptor 持有者只有材质 proxy 那一个**，
而它和 §28／§31 的「不可能」会在同一个检验上碰头——
**`NeverDeleteProxy` 与 `LogTextureSlots` 两个现成 cvar 併跑一趟，就能同时判掉第 1 与第 2 名。**

---

## §34 材质那条的清理缺口：**查完之后它不是缺口——而且这一节把 §33 自己的第 1 名除名**

读的是 `E:/PhysX/UE5.8` 与 E 树（只读）。**结论先讲：引擎在材质这条用的是同一个 reference 间接物件，
而且把这个竞态写在注解里并化解了。所以 §33 第 1 名（材质 proxy 的 cache 持有已死贴图）不成立。**

### 34a 第 1 题：重建条件全表，以及「贴图被 GC」会不会触发

`CacheUniformExpressions` 的入口：

| 入口 | 行 |
|---|---|
| `CacheUniformExpressions_GameThread` → enqueue render command | `Materials/MaterialRenderProxy.cpp:676-690` |
| 加入延迟清单 `DeferredUniformExpressionCacheRequests`，由 `UpdateDeferredCachedUniformExpressions` 消化；`GDeferUniformExpressionCaching` 关掉就当场做 | `:664-675` |
| （`WITH_EDITOR`）async shader compile 结果上传时，扫 `GetMaterialRenderProxyMap()` 全部 proxy 重建 | `Materials/MaterialShared.cpp:5748-5767` |
| `MaterialShared.cpp:190` | `:190` |

`InvalidateUniformExpressionCache` 的呼叫者：

| 呼叫者 | 行 | 触发事由 |
|---|---|---|
| `UMaterialInstance` | `Materials/MaterialInstance.cpp:498`、`:537` | 材质实例的参数变更 |
| `InvalidateMaterialRenderProxyExpressionCache` | `MaterialRenderProxy.cpp:334-341` | **由 `OnVirtualTextureDestroyedCB` 呼叫——VT producer 被销毁** |
| `CacheUniformExpressions` 自己 | `:672` | 重建前先失效 |
| **proxy 的 `ReleaseRHI`／解构** | `:846`（并在 `:836-844` 把自己从延迟清单移除） | proxy 自己要走了 |

**所以第 1 题的答案是：没有任何一条是「因为贴图参数的 UObject 被 GC」而触发的。**
唯一和贴图死亡相关的是 VT producer 那一条（`:334-341`），**而 §26 已确认本专案的卡片贴图不是 VT**
（`CreateTransient` 不设 `VirtualTextureStreaming`、没有 `VTData`）。

**引擎不靠「重建 cache」来处理贴图死亡——它靠别的机制，就是 34b。**

### 34b 第 2 题：存的是 reference 不是贴图，**而引擎把这个竞态写明了**

`FUniformExpressionSet::FillUniformBuffer`
（`Runtime/Engine/Private/Materials/MaterialUniformExpressions.cpp:1698-1750`）：

```cpp
// :1708-1711 的注解（原文）
// TextureReference.TextureReferenceRHI is cleared from a render command issued by UTexture::BeginDestroy
// It's possible for this command to trigger before a given material is cleaned up and removed from deferred update list
if (Value && Value->GetResource() && Value->TextureReference.TextureReferenceRHI && (Value->GetMaterialType() & ValidTextureTypes) != 0u)
{
    …
    *ResourceTableTexturePtr = Value->TextureReference.TextureReferenceRHI;   // :1729
    …
}
if (!bValueValid)
{
    *ResourceTableTexturePtr = GWhiteTexture->TextureRHI;                     // :1744-1748
}
```

三件事因此确定：

1. **写进 resource table 的是 `TextureReference.TextureReferenceRHI`——那个间接物件，不是贴图本体**
   （`:1729`；cube／2DArray／cubeArray／volume 各型别同样，`:1767`／`:1807`／`:1846`／`:1886`）；
2. **引擎知道并处理这个竞态**：注解讲的正是「贴图的 `BeginDestroy` 发出的 render command 可能比材质被清掉还早」，
   化解方式是「reference 为 null ⇒ `bValueValid=false` ⇒ 退回 `GWhiteTexture`」；
3. 持有链：uniform buffer 的 `ResourceTable` 对列出的资源取 refcount ⇒ **持有那个 `FRHITextureReference` 物件**；
   而那个物件的内层在贴图死亡时被引擎换成全域黑图（§30a，`Rendering/StreamableTextureResource.cpp:237`）。

**所以「贴图死了但 proxy 的 cache 还持有它 RHI 的参照」这句话，在这一版引擎里不成立**：
cache 持有的是间接物件，内层已经被换掉。**§33 的第 1 名除名。**
这和你给的 `slot_hits_fault_texture=0` 方向一致——**九个 reference 槽没指名它，而材质这条存的是同一种 reference，
所以材质这条也不会指名它。**

### 34c 第 3 题：我们这边那组合够不够——**不够，而且理由是 MID 自己就是强参照**

- `OKReleaseStaleKeptRuntimeTextures`（`Plugins/KKRuntimePose/.../KKRuntimeMaterial.cpp:265` 一带）只做
  `RemoveAt`，掉的是 `FRecentRuntimeTexture` 那份 `TStrongObjectPtr`——**纯 game-thread 记帐，这点你查得对**；
- 但 MID 对贴图参数本身是**强参照**：`FTextureParameterValue::ParameterValue` 是
  **`UPROPERTY(EditAnywhere, BlueprintReadWrite) TObjectPtr<class UTexture>`**
  （`Runtime/Engine/Public/Materials/MaterialInstance.h` 的 `struct FTextureParameterValue`）。
  **所以只要 MID 还活著，我们这边放手也收不走那张贴图。**
- 要那张贴图被 GC，**MID 必须也已不可达**——这正是你们量到的（贴图与 12 个 MID 都死）。
  而 MID 死亡时：`UMaterialInstance` 那侧把 `FMaterialInstanceResource` 交给 render thread 删除，
  proxy 的解构／`ReleaseRHI` 走 `InvalidateUniformExpressionCache(true)`（`MaterialRenderProxy.cpp:846`）
  并把自己从延迟清单移除（`:836-844`）。

**所以：这组合不足以让一张被 GC 的贴图留在某个 proxy 的 cache 里。**
`FMaterialInstanceResource` 存的那些裸 `const UTexture*`（`MaterialInstanceSupport.h:412/454`）确实是裸的，
**但它们活不过 MID**，而 MID 活著时贴图不会死——两头都没有「只存位址」的出口。

### 34d 第 4 题：接缝在哪、责任面在哪

既然 34b／34c 都是否定，**那条接缝不是「谁忘了清 cache」，也不在 DreamGUI 与我们之间。**
能同时满足「配置被释放」与「`MainPS` 取样到它」的事实只剩一个：

> **有一条路径释放了那张贴图的 RHI 配置，而没有走 `UTexture::BeginFinalReleaseResource`**
> ——因此 reference 从未被清、`TRefCountPtr` 从未被尊重。

**这正好就是 `LogTextureSlots` 注解事先登记的 (b)。** 责任面因此分成两句，而且它们互斥：

- **(b) 成立**（有 slot 的 `referenced_name=` 对上故障那张）⇒ 责任在**释放端**：某处绕过了 refcount
  或绕过了 `BeginFinalReleaseResource`。那一端目前看起来**不是** DreamGUI（它只持有 handle，§28–§31）、
  **也不是** `OKReleaseStaleKeptRuntimeTextures`（它只 `RemoveAt`，34c）。**那就要往 D3D12 的配置器／pool
  去找**（§12 的三分类：committed 真销毁、pool 以 fence 回收、transient 在已注册 heap 内别名）。
- **(a) 成立**（没有任何 slot 指名它，**而 e-cardload 上一趟量到的就是 0**）⇒ `MainPS` 取样的不是任何
  reference 槽，责任面回到**「每笔 draw 真正绑进去的那一笔」与那两个裸位址槽**（§31a：`SceneDepthTex`、
  `BackdropTex`，来源都是 RDG render target）。**那就把问题移到 RDG／`GRenderTargetPool`，
  也就是 §32b 差的那一环「谁把页还给系统」。**

**而你给的 `slot_hits_fault_texture=0` 已经选了 (a)。** 所以依我这一侧读到的东西，
**下一个该查的不是材质、不是 DreamGUI 的保存，而是「`BackdropTex`／`SceneDepthTex` 这两个 RDG 来源的页，
在群组 target 归还之后会不会被还给系统」。**

### 34e 前三名与能否解释 `AddressTranslationError`

| 名次 | 候选 | 行 | 怎麼验 | 能解释整页不在页表吗 |
|---|---|---|---|---|
| 1 | **`BackdropTex` 的来源：群组 target 归还后那块页的归属**（§32b ＋ §31a 合併） | `DreamUICompositor.cpp:407`、`:296-302`；`RenderTargetPool.cpp:202`、`:400-420` | **`DreamGUI.Experiment.NoBackdrop 1`**（`DreamUICompositor.cpp:348`，现成 cvar）＋ `LogEntries 1` ＋ `LogPoolReuse 1`；若 NoBackdrop 让故障消失，这条就定位了 | **可能能**：若池子释放那条元件走的是 transient／aliased 配置，页会真的被还掉。**差的证据是「那次释放走的是哪一类配置器」** |
| 2 | **(b) 的可能性：有路径绕过 `BeginFinalReleaseResource`** | 判准在 `MaterialUniformExpressions.cpp:1712`／`StreamableTextureResource.cpp:237` | **`DreamGUI.LogTextureSlots 1`**；e-cardload 已量到 0，**再一趟确认 0 稳定**就除名 | **能**：绕过 refcount 的释放正是「页被还掉」的唯一自洽解释 |
| 3 | 材质 proxy 的 uniform expression cache | `MaterialRenderProxy.cpp:664-690`／`:846`；`MaterialUniformExpressions.cpp:1729` | `DreamGUI.Experiment.NeverDeleteProxy 1`（已排给 e-cardload） | **不能**：34b 证明它存的是 reference、内层已被换成黑图。**本节将它从第 1 名降到此处**；`NeverDeleteProxy` 那一趟若 3/3 仍故障，就与此一致 |

**一句话**：材质这条查完是**否定**，而且它顺手把 §33 的第 1 名推翻。
**`slot_hits_fault_texture=0` 既然已经选了 (a)，力气应该转到 `NoBackdrop` 那一格**——
它是现成 cvar、零建置，而且是现在唯一还能解释「整页不在页表」的那一条的入口。

---

## §35 不带 refcount 的裸指标全扫：**只找到一处跨帧的，而它从不解参**；外加一条你那格不空白的更正

读的是 E 树 `Plugins/DreamGUI`（只读）。

### 35a 第 1 题：backdrop 的写入、清除与绑定保证——**它根本不跨帧，所以没有清除者可言**

`FDreamUIBuiltInBackdrop` 在整个 plugin 的**全部**出现（grep，零遗漏）：

| 出现 | 身分 |
|---|---|
| `DreamUIRenderer.h:27-34` | 型别定义（`FRHITexture* Texture`、`FIntPoint Origin`、`bool bOpaque`） |
| `DreamUIRenderer.h:221`、`.cpp:905` | `DrawBuiltInBatch` 的 **函式参数** `const FDreamUIBuiltInBackdrop* InBackdrop` |
| `DreamUIRenderer.cpp:1615` | **pass lambda 内的堆叠区域变数**（world space） |
| `DreamUIRenderer.cpp:2361` | **pass lambda 内的堆叠区域变数**（screen space） |

**没有任何一处是成员、static、TMap 或跨帧捕获。** 所以：

- **谁写进去**：pass lambda 自己，`Backdrop.Texture = InBackdrop->GetRHI()`（`:1619`、`:2365`），
  而前一行先呼叫 `InBackdrop->MarkResourceAsUsed()`；
- **谁负责清**：**没人需要清**——结构随 lambda 结束消失；
- **绑定那一刻凭什麼保证它还活著**：`InBackdrop` 是宣告在 pass 参数结构里的 `FRDGTextureRef`
  （`FDreamUIBackdropDrawPassParameters` 的 `RDG_TEXTURE_ACCESS(BackdropTexture, ERHIAccess::SRVGraphics)`，
  `DreamUIRenderer.cpp:1588`；world space 在 `:1595` 一带 `PassParameters->BackdropTexture = InBackdrop`），
  **RDG 保证宣告在 pass 参数里的资源在该 pass 执行期间已配置且有效**，`MarkResourceAsUsed()` 再把它钉在该 pass 内。

**所以第 1 题的答案是：没有任何路径能让它跨帧留著一个来源已走掉的值。** 这一格可以收掉。

### 35b 第 2 题的更正：**那一格不空白——`NoBackdrop=1` 就是「不配置」那一格**

你写「`NoBackdrop=2` 没有否掉它…配置与交接那一侧照旧跑，所以这一格仍然空白」。
**模式 1 正是为那一侧做的，而且它真的不配置**：

`FDreamUICompositeStack::CopyFrom`（`DreamUICompositor.cpp:363-402`）**第一件事**就是

```cpp
if (DreamUICompositorExperiment::CVarNoBackdrop.GetValueOnRenderThread() == 1)
{
    OutOrigin = FIntPoint::ZeroValue;
    return nullptr;                 // :365-368，在任何 CreateTexture 之前
}
```

cvar 自己的说明也写明两模式的差别（`:348-350`）：
「**1 = never copy what is behind a group (nothing allocated or sampled, callers take their no-backdrop path)**;
2 = copy it as usual but bind the global black texture instead, so only the memory the shader reads differs.」
注解（`:342-346`）还写了它的用意：「is the backdrop copy the resource MainPS faults on? …
**no backdrop copy is ever allocated**」。

**所以 `NoBackdrop=1` 一趟就把「配置／交接」那一格填掉，零建置。**

**配置／交接的完整步骤，以及哪一步没有 refcount 背书**：

| 步 | 做什麼 | 行 | 背书 |
|---|---|---|---|
| 1 | `CopyBackdrop` → `CopyFrom(Frames.Last(), …)` | `:358-361` | — |
| 2 | 建立副本：`GraphBuilder.CreateTexture(Desc, InName)`（MSAA 走 `:388` ＋ `AddResolvePass`） | `:396`／`:388` | **RDG 图的生命期** |
| 3 | 从来源拷贝：`AddCopyTexturePass(GraphBuilder, InFrame.Texture, Copy, …)` | `:397` | 来源是 `FFrame::Texture`，由 `Frame.Pooled` 的 `TRefCountPtr` ＋ `RegisterExternalTexture` 双重钉住（§32b） |
| 4 | 交给 pass：`PassParameters->BackdropTexture = InBackdrop`（`RDG_TEXTURE_ACCESS`） | `:1588`／`:1595` 一带 | **RDG** |
| 5 | pass 内取裸位址：`Backdrop.Texture = InBackdrop->GetRHI()` | `:1619`／`:2365` | **没有 refcount**，但被第 4 步的 RDG pass 保证覆盖；前一行有 `MarkResourceAsUsed()` |
| 6 | 绑定：`PSParameters.DreamUI_BackdropTex = …` | `:1014-1015` | 读第 5 步那个值，同一个 pass 内 |

**⇒ 唯一没有 refcount 的是第 5 步，而它落在 RDG 对该 pass 的保证内。**
**真正「没有 refcount 背书、而且不被 RDG 覆盖」的那一步不在这条链上，而在 §32b**：
群组 target 被 `FDreamUIDeferredRelease::Hold(Top.Pooled)` 放手之后回到 `GRenderTargetPool`，
**再发出只看 `Element->IsFree()`（`RenderTargetPool.cpp:202`），没有 GPU fence。**

### 35c 第 3 题：backdrop 的来源不可能是卡片贴图——型别层面的依据

backdrop 的 RHI 只有**两个产地**，两者都不是 `UTexture`：

1. **`GraphBuilder.CreateTexture(Desc, InName)`**（`DreamUICompositor.cpp:396`、MSAA 的 `:388`）——
   RDG 自己配置的贴图；
2. 它拷贝的来源 `FFrame::Texture` 是 `FRDGTextureRef`（`DreamUICompositor.h:114`），
   而 `FFrame::Texture` 只有两个来源：
   **`GraphBuilder.RegisterExternalTexture(Frame.Pooled, …)`**（`:300`，`Frame.Pooled` 来自
   `GRenderTargetPool.FindFreeElement`，`:296`）或**画布自己的 target**
   （`FDreamUICompositeStack` 建构子的 `InTarget`／`InTargetRHI`，`DreamUICompositor.h:139-141`）。

**一张 `UTexture2D` 的 RHI 进不了这两条**：没有任何路径把 `UTexture::TextureReference` 或
`FTextureResource::TextureRHI` 塞进 `FFrame`，`FFrame` 的两个贴图栏位分别是 `FRDGTextureRef` 与
`FTextureRHIRef`（`:114`、`:116`），而填它们的只有上面两处。**所以这一格可以收掉。**

**但要记一条反向的可能，它比原假说更能解释你的观测**：
backdrop 的记忆体可以是**卡片贴图释放之后的「前住户」**——RDG／pool 把那段位址重新配置给 backdrop 副本，
于是 **故障位址落在卡片贴图的旧区间内，而取样者是 backdrop，没有任何人持有过卡片贴图。**
这同时解释了「位址属於卡片贴图」与「九个槽 `slot_hits_fault_texture=0`」。
**它差的一环**：这样取样到的是**已重新配置、有效**的记忆体，不会 `AddressTranslationError`——
除非该段在「卡片贴图释放」与「backdrop 取得」之间**真的被还给系统**，而那是配置器的事，不是 DreamGUI 的。
**（而 `NoBackdrop=1` 正好能判这一条：若故障消失，取样者就是 backdrop。）**

### 35d 第 4 题：全 plugin 裸指标扫描——**跨帧的只有一处，而它从不解参**

扫 `FRHITexture*`／`FRHIBuffer*`／`FRHIUnorderedAccessView*`／`FRHIShaderResourceView*`（**裸**）：

| 位置 | 身分 | 跨帧？ | 清理者 |
|---|---|---|---|
| **`FDreamUISectionProxy_Mesh::DrawStateVertexBuffer`／`DrawStateIndexBuffer`**（`const FRHIBuffer*`） | `DreamUIMeshComponent.cpp:93-94`，**section proxy 的成员** | **是** | **没有**（`ClearBeforePool`／`Disable` 都不碰，§29c） |
| `FDreamUIBuiltInBackdrop::Texture` | `DreamUIRenderer.h:29` | 否（35a） | 不需要 |
| `DrawBuiltInBatch` 的 `FRHITexture* SceneDepthTexture` | `DreamUIRenderer.cpp:903`、`.h:219` | 否（函式参数） | 不需要 |
| `TextureOrFallback`／`TextureOr`／`TextureOr` 的回传型别 | `DreamUIRenderer.cpp:972-975`、`DreamUICompositor.cpp:520-523`、`Effects/DreamUIBackdropEffects.cpp:574` | 否（lambda 回传） | — |
| `Named()`／`LogSlot()` 里的 `GetReferencedTexture()` | `DreamUIRenderer.cpp:1023`、`DreamUIBaseShaders.cpp:87` | 否（诊断用区域变数） | — |
| `DreamUIGroupPoolReuse::Note` 的参数与 `TMap<FRHITexture*, uint32> LastHandedOut` | `DreamUICompositor.cpp:197`、`:205` | **是（static）** | 没有，**但只当键比对、从不解参**，且预设关 |
| `FDreamUIFontAtlasStagingPool` 相关的 `GetTexture2DArrayRHI()` | `DreamUIFontData_FreeTypeRender.cpp:3178` | 否（区域变数） | — |
| `SetMaterialShaderParameters`／`SetDepthBlendParameter` 的参数 | `DreamUIShaders.h:37`／`:67`／`:73` | 否 | — |
| post-process／effects 的 `static_cast<FRHITexture*>(…GetReference())` | `DreamVisualPostProcessRenderProxy.cpp:263/265/267`、`Effects/DreamUIBackdropEffects.cpp:291` | 否（当场由持有的 ref 解出） | — |
| `IDreamUIRendererPrimitive.h:82-83` `GetVertexBuffer()`／`GetIndexBuffer()` | 回传裸指标 | 否 | 来源 `State->VertexBufferRHI`／`IndexBufferRHI` 是 **`FBufferRHIRef`**（`IDreamUIRendererPrimitive.h:41`、`:47`），由 `TRefCountPtr<const FDreamUISectionDrawState>` 背书 |

**唯一跨帧的那一处（第一列）的实际用法**：`GetDrawState()`（`DreamUIMeshComponent.cpp:96-111`）
只把它们当**比较键**，判断 buffer 有没有被重建：

```cpp
if (bDrawStateStale || !DrawState.IsValid()
    || DrawStateVertexBuffer != DreamUIVertexBuffers.VertexBufferRHI.GetReference()
    || DrawStateIndexBuffer  != IndexBuffer.IndexBufferRHI.GetReference())
{ … 重建 DrawState …; DrawStateVertexBuffer = …GetReference(); }
```

**从不解参。** 所以它不能直接 page fault。**但它有 ABA 风险**：旧 buffer 被释放、新 buffer 恰好配置到同一位址
⇒ 比较说「没变」⇒ `DrawState` 不重建 ⇒ 那一节沿用**旧的 `BuiltIn`**（旧的 12 个槽的 reference）。
`FDreamUISectionDrawState` 自己持有 `FBufferRHIRef` 与那组 reference（`IDreamUIRendererPrimitive.h:38-54`），
**所以后果是「画错参数」，不是悬空。**

### 35e 前三名与能否解释 `AddressTranslationError`

| 名次 | 候选 | 行 | 怎麼验 | 能解释整页不在页表吗 |
|---|---|---|---|---|
| 1 | **backdrop 副本的记忆体是卡片贴图的「前住户」**（35c 的反向可能） | `DreamUICompositor.cpp:396`、`:397`；`DreamUIRenderer.cpp:1619`／`:2365` | **`DreamGUI.Experiment.NoBackdrop 1`**（`:347-350`，**真的不配置**，`:365-368`）；故障消失 ⇒ 取样者是 backdrop | **差一环**：重新配置过的记忆体是有效的。要成立，那段必须在两者之间**真的被还给系统**——**责任在配置器，不在 DreamGUI** |
| 2 | **群组 target 归还只看 `IsFree()`、没有 GPU fence**（§32b，35b 第 5 步之外真正缺背书的那一步） | `DreamUICompositor.cpp:407`；`DreamUIDeferredRelease.cpp:115-133`；`RenderTargetPool.cpp:202`、`:400-420` | `DreamGUI.DeferredRelease.LogEntries 1` ＋ `LogPoolReuse 1` ＋ `Frames.Pooled` 调大 | **差一环**：同上，缺「谁把页还给系统」 |
| 3 | `DrawStateVertexBuffer`／`DrawStateIndexBuffer` 的 ABA | `DreamUIMeshComponent.cpp:93-94`、`:96-111` | 在 `GetDrawState()` 印一次 `(旧位址, 新位址, 是否重建)`（**要改码**，所以排最后） | **不能**：从不解参。**后果是画错参数，不是 fault** |

**一句话**：裸指标这一类扫完了——**跨帧的只有一处，而它从不解参**；backdrop 本身不跨帧。
**所以「谁持有」这条路到此为止，三条候选差的都是同一环：「谁把那一页还给系统」。**
而 **`NoBackdrop=1` 是现在唯一能用一个现成 cvar 把取样者定下来的那一步**——
它不需要解释 unmap，只需要回答「取样的是不是 backdrop」。
