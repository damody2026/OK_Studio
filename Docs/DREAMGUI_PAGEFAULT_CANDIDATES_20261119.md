# 读卡开卡时 GPU 页错误：DreamGUI 侧的候选清单与可检验性（2026-11-19）

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

---

调查：f-sceneload（F 树，只读）。现象的转述来自协调 session，崩溃档我没有自己看过。
