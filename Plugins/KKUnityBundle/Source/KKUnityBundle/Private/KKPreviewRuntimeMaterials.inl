// The card's parts as instances of the shared parents (KKRuntimeSharedMaterial), in every build: a packaged game
// loads the cooked parents and their shader library; the editor and -game load the same assets uncooked (their shaders
// compile once per machine and stay in the DDC), so a new card compiles nothing. In the editor a part no parent covers
// keeps its own transient graph (ApplyPartMaterial); a packaged game leaves such a part out (hidden) and loads the rest.
// Both paths consume the complete native material metadata and textures.
#if !WITH_EDITOR
#include "ShaderCodeLibrary.h"
#endif
// Eyes, eyelines and eyebrows mixed with the hair over them (the user, 2026-11-22: 眼睛、眼框、眉毛應該要跟前髮混色，畫出
// 半透明的效果), as Koikatsu's foreground eyes / eyebrows draw them through it. Those parts take the <Parent>_Fg
// variants (Tools/GpuPoseAudit PrepareForegroundMaterial.cpp, made by Tools/prepare_face_materials.lua), and all her
// hair's meshes draw into custom depth / stencil (UpdateForegroundHair): where her own hair is just in front of
// them (ok.ForegroundNear) they show at ok.ForegroundThrough over it.
// 2026-11-22 later: "不是前髮半透明，是頭髮跟眼睛相關的元件半透明混合畫" -- every hair part, not only the front hair.
static TAutoConsoleVariable<float> CVarOkForegroundThrough(TEXT("ok.ForegroundThrough"),.5f,
    TEXT("Card reader: how much of the eyes, eyelines and eyebrows shows through her hair (0 hidden by it .. 1 drawn over it). Live."));
static TAutoConsoleVariable<float> CVarOkForegroundNear(TEXT("ok.ForegroundNear"),12.f,
    TEXT("Card reader: only hair less than this far (cm) in front of the eyes / eyebrows lets them through. Live."));
// Koikatsu's foreground parts (ChaForegroundComponent): the eyebrows and the eyes (eyelines, eyeballs, gag eyes).
static bool OKPreviewForegroundFacePart(const FString& Name){
    static const TCHAR* Parts[]={TEXT("cf_O_mayuge"),TEXT("cf_O_eyeline"),TEXT("cf_O_eyeline_low"),TEXT("cf_Ohitomi_L"),TEXT("cf_Ohitomi_R"),TEXT("cf_Ohitomi_L02"),TEXT("cf_Ohitomi_R02"),TEXT("cf_O_gag_eye_00"),TEXT("cf_O_gag_eye_01"),TEXT("cf_O_gag_eye_02")};
    for(const TCHAR* P:Parts)if(Name.Equals(P,ESearchCase::IgnoreCase))return true;return false;
}
// Her hair: the hair slots (role hair_*), HairDeck / Tripo hair, and hair worn in an accessory slot (mod hair: a hair
// shader, or hair / kami in its name; as portable_hairdeck.rs tells hair accessories from the rest).
static bool OKPreviewHairPart(const FKKRuntimeMaterialPart& P){
    if(P.Role.Contains(TEXT("hair"))&&!P.Role.Contains(TEXT("acc")))return true;
    if(P.Role.StartsWith(TEXT("clothes")))return false;
    if(P.Name.StartsWith(TEXT("Tripo_")))return true;
    if(P.Role!=TEXT("accessory"))return false;
    if(P.Name.Contains(TEXT("hair"))||P.Name.Contains(TEXT("kami")))return true;
    TSharedPtr<FJsonObject> Root;const TSharedPtr<FJsonObject>* Mat=nullptr;FString Shader;
    return FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(P.SourceMetadataJson),Root)&&Root&&Root->TryGetObjectField(TEXT("material"),Mat)&&(*Mat)->TryGetStringField(TEXT("shader"),Shader)&&Shader.Contains(TEXT("hair"));
}
static UMaterialInterface* OKPreviewForegroundParent(const FString& Root,const FString& Name){
    if(Name.IsEmpty())return nullptr;const FString Fg=Name+TEXT("_Fg");
    if(!FPackageName::DoesPackageExist(Root/Fg))return nullptr;
    return LoadObject<UMaterialInterface>(nullptr,*(Root/Fg+TEXT(".")+Fg));
}
void AKKPreviewActor::UpdateForegroundHair(){
    if(ForegroundFaceMaterials.IsEmpty())return;
    const float Through=FMath::Clamp(CVarOkForegroundThrough.GetValueOnGameThread(),0.f,1.f),Near=FMath::Max(0.f,CVarOkForegroundNear.GetValueOnGameThread());
    const int32 Count=GetComponents().Num();
    if(Count==ForegroundSeenComponents&&Through==ForegroundSeenThrough&&Near==ForegroundSeenNear)return;
    ForegroundSeenComponents=Count;ForegroundSeenThrough=Through;ForegroundSeenNear=Near;
    // Her own id: another character's front hair (the one-on-one's partner) does not let her eyes through.
    if(!ForegroundStencil){static uint8 Next=0;Next=uint8(Next%254+1);ForegroundStencil=Next;}
    for(const auto& M:ForegroundFaceMaterials)if(auto* I=M.Get()){
        I->SetScalarParameterValue(TEXT("__OK_ForegroundStencil"),ForegroundStencil);
        I->SetScalarParameterValue(TEXT("__OK_ForegroundThrough"),Through);I->SetScalarParameterValue(TEXT("__OK_ForegroundNear"),Near);
    }
    // Every hair mesh of hers (role hair_*, not hair accessories; HairDeck / Tripo hair too, which draws on its own
    // graph): the user corrected "the front hair" to all hair over the eyes (2026-11-22). Parts by session index;
    // outline shells are left out (they would let the eyes through a rim around the hair).
    TSet<int32> HairParts(ForegroundHairParts);for(const FKKLoadedPart& Part:Parts)if(Part.SessionIndex!=INDEX_NONE&&Part.Role.Contains(TEXT("hair"))&&!Part.Role.Contains(TEXT("acc")))HairParts.Add(Part.SessionIndex);
    static const FString Prefixes[]={TEXT("KKSessionPart_"),TEXT("KKMorphPart_")};
    int32 Drawn=0;
    for(UActorComponent* C:GetComponents()){
        auto* Mesh=Cast<UMeshComponent>(C);if(!Mesh)continue;int32 Index=INDEX_NONE;
        for(FName Tag:Mesh->ComponentTags){const FString Text=Tag.ToString();for(const FString& Prefix:Prefixes)if(Text.StartsWith(Prefix)){Index=FCString::Atoi(*Text.Mid(Prefix.Len()));break;}if(Index!=INDEX_NONE)break;}
        if(Index==INDEX_NONE)for(const FKKLoadedPart& Part:Parts)if(Part.Comp==Mesh){Index=Part.SessionIndex;break;}
        const bool bHair=Index!=INDEX_NONE&&HairParts.Contains(Index)&&!Mesh->GetName().Contains(TEXT("Outline"));
        Drawn+=bHair;
        if(FPlatformMisc::GetEnvironmentVariable(TEXT("OK_FOREGROUND_DUMP"))==TEXT("1"))UE_LOG(LogTemp,Display,TEXT("OK foreground mesh %s part=%d hair=%d"),*Mesh->GetName(),Index,bHair?1:0);
        if(Mesh->bRenderCustomDepth!=bHair)Mesh->SetRenderCustomDepth(bHair);
        if(bHair&&Mesh->CustomDepthStencilValue!=ForegroundStencil)Mesh->SetCustomDepthStencilValue(ForegroundStencil);
    }
    // The stencil half of custom depth (r.CustomDepth 3) is off by default.
    if(auto* V=IConsoleManager::Get().FindConsoleVariable(TEXT("r.CustomDepth")))if(V->GetInt()!=3)V->Set(3,ECVF_SetByCode);
    UE_LOG(LogTemp,Display,TEXT("OK foreground eyes: %d parts through %d hair meshes, stencil=%d through=%.2f near=%.1f"),ForegroundFaceMaterials.Num(),Drawn,ForegroundStencil,Through,Near);
}
// OKPrepareCookedRole's progress across load batches: the textures and the part instances (a character's ~160 MIDs took
// ~40 ms, and with its textures up to ~200 ms, in one frame) are made a few milliseconds at a time.
struct FOKCookedRoleBuild {FString Root;bool HG=false;FKKRuntimeMaterialScene Scene;TArray<UTexture2D*> Textures;int32 NextTexture=0,NextPart=0,Uncovered=0;};
// 1: the actor's shared-parent instances are ready; 0: continue in a later batch (Budget seconds were spent; 0 = no
// limit); -1: failed (Error).
// Whose parts the instances are for: hers as she loads, or a donor's staged for a change of clothes (wardrobe.rs).
struct FOKCookedRoleTarget {FOkSession& Source;TArray<TObjectPtr<UMaterialInstanceDynamic>>& Materials;TArray<TObjectPtr<UMaterialInstanceDynamic>>& Outlines;TSharedPtr<FOKCookedRoleBuild>& Build;TArray<TObjectPtr<UTexture2D>>& Textures;bool bWardrobe;};
static int32 OKPrepareCookedRole(AKKPreviewActor* Actor,FString& Error,double Budget,const FOKCookedRoleTarget& To){
    if(!To.Build&&!To.Materials.IsEmpty())return 1;
    const double Deadline=Budget>0.?FPlatformTime::Seconds()+Budget:DBL_MAX;
    auto Fail=[&](){To.Build.Reset();To.Materials.Reset();To.Outlines.Reset();return -1;};
    if(!To.Build){
    auto Setup=[&]()->bool{
    {TRACE_CPUPROFILER_EVENT_SCOPE(KK_CookedRolePrepare);if(!To.Source.PrepareRuntimeMaterials(Error))return false;}
    FString Manifest;
    if(!FParse::Value(FCommandLine::Get(),TEXT("StreetSocialManifest="),Manifest))FParse::Value(FCommandLine::Get(),TEXT("CrowdRuntimeScene="),Manifest);
    FString Root;
    FParse::Value(FCommandLine::Get(),TEXT("RuntimeMaterialRoot="),Root);
    if(Root.IsEmpty()){
        FString Json;TSharedPtr<FJsonObject> Object;
        if(FFileHelper::LoadFileToString(Json,*Manifest)&&FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),Object)&&Object)Object->TryGetStringField(TEXT("material_root"),Root);
    }
#if WITH_EDITOR
    // The card reader in the editor / -game: the street's display root (the HG one is next to it, below).
    if(Root.IsEmpty())Root=TEXT("/Game/IndependentResources/RuntimeMaterials/StreetDisplay27");
#endif
    // The host's root for this actor (OK Studio items: the one with the depth-writing ForgeStudioOpaque parent).
    if(!Actor->SharedMaterialRootOverride.IsEmpty())Root=Actor->SharedMaterialRootOverride;
    if(Root.IsEmpty()){Error=TEXT("High model requires a cooked shared material root");return false;}
    // The cooked parents' shaders live in their own library (Tools/rebuild_street_social_patch.ps1 cooks it as
    // RuntimeMaterialBake), which the engine does not open by itself: RuntimeMaterialLibrary= or manifest material_library.
#if !WITH_EDITOR
    FString Library;
    if(!FParse::Value(FCommandLine::Get(),TEXT("RuntimeMaterialLibrary="),Library)){
        FString Json;TSharedPtr<FJsonObject> Object;
        if(FFileHelper::LoadFileToString(Json,*Manifest)&&FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),Object)&&Object)Object->TryGetStringField(TEXT("material_library"),Library);
    }
    if(Library.IsEmpty())Library=TEXT("RuntimeMaterialBake");
    // Shared with the reader's startup preload (OKPreloadRuntimeSharedMaterialParents), which opens it first.
    OKOpenRuntimeMaterialShaderLibrary(Library);
#endif
    // Render style (ok.RenderStyle, OKHGShading): HG has its own cooked parents
    // next to the Koikatsu ones (HGMaterialRoot= or manifest hg_material_root).
    // Without them the Koikatsu root stays, so an old manifest still plays.
    const IConsoleVariable* StyleVar=IConsoleManager::Get().FindConsoleVariable(TEXT("ok.RenderStyle"));
    bool HG=StyleVar&&StyleVar->GetInt()==1;
    if(HG){
        FString HGRoot;FParse::Value(FCommandLine::Get(),TEXT("HGMaterialRoot="),HGRoot);
        if(HGRoot.IsEmpty()){FString Json;TSharedPtr<FJsonObject> Object;if(FFileHelper::LoadFileToString(Json,*Manifest)&&FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json),Object)&&Object)Object->TryGetStringField(TEXT("hg_material_root"),HGRoot);}
#if WITH_EDITOR
        if(HGRoot.IsEmpty())HGRoot=TEXT("/Game/IndependentResources/RuntimeMaterials/StreetHG06");
#endif
        if(HGRoot.IsEmpty()){UE_LOG(LogTemp,Warning,TEXT("HG render style: no hg_material_root, keeping %s"),*Root);HG=false;}else Root=HGRoot;
    }
    FKKRuntimeMaterialScene Scene;Scene.EnableShadows=(Actor->bCharacterDisplayShadows||Actor->bStudioItemShading)&&!HG;OKApplyCharacterMakerLighting(Scene);Scene.Globals=Actor->StudioShaderGlobals;
    auto Build=MakeShared<FOKCookedRoleBuild>();Build->Root=Root;Build->HG=HG;Build->Scene=Scene;To.Build=Build;
    return true;
    };
    if(!Setup()){To.Build.Reset();return -1;}
    }
    FOKCookedRoleBuild& Role=*To.Build;
    const auto& Data=*To.Source.RuntimeMaterials;
    {TRACE_CPUPROFILER_EVENT_SCOPE(KK_CookedRoleTextures);
    while(Role.NextTexture<Data.Textures.Num()){
        FOkCardProfileScope Profile(GOkCardLoadProfile.bActive?&GOkCardLoadProfile.RoleTextureSeconds:nullptr);
        auto* Texture=OKCreateRuntimePreparedTexture(Data.Textures[Role.NextTexture++],Error);if(!Texture)return Fail();Role.Textures.Add(Texture);To.Textures.Add(Texture);
        if(FPlatformTime::Seconds()>=Deadline)return 0;
    }}
    if(Role.NextPart==0&&To.Materials.IsEmpty()){
        if(!To.bWardrobe){Actor->FlatFaceMaterials.Reset();Actor->FlatFaceState=FKKFaceFlattenState();Actor->ForegroundFaceMaterials.Reset();Actor->ForegroundHairParts.Reset();}
        Actor->ForegroundSeenComponents=-1;
        To.Materials.SetNum(To.Source.PartCount());To.Outlines.SetNum(To.Source.PartCount());
    }
    TRACE_CPUPROFILER_EVENT_SCOPE(KK_CookedRoleParts);
    auto BuildPart=[&](const FKKRuntimeMaterialPart& SourcePart)->int32{
        auto& Textures=Role.Textures;auto& Scene=Role.Scene;const FString& Root=Role.Root;const bool HG=Role.HG;int32& Uncovered=Role.Uncovered;
        OkMeshView View{};if(!To.Source.PartAt(SourcePart.NativePart,View)||(!View.render_visible&&OKTearLevel(View.name)==0)||View.n_verts<=0)return 1; // the tears are built hidden and shown live (ApplyTears): they need theirs
        // Her hair parts by session index, whatever draws them (HairDeck hair takes its own graph): UpdateForegroundHair.
        if(!To.bWardrobe&&OKPreviewHairPart(SourcePart))Actor->ForegroundHairParts.Add(SourcePart.NativePart);
        // OK Studio item state (AKKPreviewActor::ItemColorOverrides, ItemShadowColorOverride: sRGB, the values the game
        // writes to _Color.._Color4 and _ShadowColor) reaches the shared parent as the part's own material values.
        FKKRuntimeMaterialPart Part=SourcePart;
        if(Part.ItemDraw){
            static const TCHAR* ColorNames[]={TEXT("_Color"),TEXT("_Color2"),TEXT("_Color3"),TEXT("_Color4")};
            for(int32 Index=0;Index<4;++Index)
                if(Actor->ItemColorOverrides.IsValidIndex(Index)&&Actor->ItemColorOverrides[Index].A>=0.f){const FLinearColor& O=Actor->ItemColorOverrides[Index];Part.Overrides.Add(ColorNames[Index],FLinearColor(O.R,O.G,O.B,O.A));}
            if(Actor->ItemShadowColorOverride.A>=0.f){const FLinearColor& O=Actor->ItemShadowColorOverride;Part.Values.Add(TEXT("_ShadowColor"),FVector4f(O.R,O.G,O.B,1.f));Part.Overrides.Add(TEXT("_ShadowColor"),FLinearColor(O.R,O.G,O.B,1.f));}
            // A faded item blends: the blending parent (ForgeStudio rather than the depth-writing ForgeStudioOpaque); in the
            // editor its own graph draws it.
            Part.Values.Add(TEXT("_OKItemAlpha"),FVector4f(Actor->ItemAlpha,0.f,0.f,0.f));
#if WITH_EDITOR
            if(Actor->ItemAlpha<1.f){++Uncovered;return 1;}
#endif
        }
        const auto Recipe=OKRuntimeSharedMaterialRecipe(Part);const FString Name=OKRuntimeSharedMaterialParentName(Recipe);
        // OK_LOAD_PROFILE: the part's instances, and of that the shared parents loaded for it.
        FOkCardProfileScope Instance(GOkCardLoadProfile.bActive?&GOkCardLoadProfile.RoleInstanceSeconds:nullptr);
        auto LoadParent=[&](bool Outline){FOkCardProfileScope Load(GOkCardLoadProfile.bActive?&GOkCardLoadProfile.RoleParentSeconds:nullptr);return OKLoadRuntimeSharedMaterialParent(Root,Recipe,Outline);};
        auto FlatParent=[&](UMaterialInterface* Of){FOkCardProfileScope Load(GOkCardLoadProfile.bActive?&GOkCardLoadProfile.RoleParentSeconds:nullptr);return OKRuntimeFlatFaceParent(Of,true);};
        auto* Parent=Name.IsEmpty()?nullptr:LoadParent(false);
        if(!Parent&&Name.IsEmpty()){
#if WITH_EDITOR
            ++Uncovered;return 1; // no shared family: ApplyPartMaterial builds this part's own graph
#endif
        }
        // OK_SHARED_DUMP=<part name part>: every value the shared parent gets for that part (diagnostic).
        {static const FString Dump=FPlatformMisc::GetEnvironmentVariable(TEXT("OK_SHARED_DUMP"));if(!Dump.IsEmpty()&&Part.Name.Contains(Dump)){FKKRuntimeMaterialBinding B;FString E;if(OKPrepareRuntimeSharedMaterialBinding(Part,Scene,B,E)){for(const auto& V:B.Vectors)UE_LOG(LogTemp,Display,TEXT("OK shared dump %s %s=%s"),*Part.Name,*V.Key.ToString(),*V.Value.ToString());for(const auto& V:B.Scalars)UE_LOG(LogTemp,Display,TEXT("OK shared dump %s %s=%g"),*Part.Name,*V.Key.ToString(),V.Value);for(const auto& T:B.Textures)UE_LOG(LogTemp,Display,TEXT("OK shared dump %s %s=texture %d source=%d avgBGRA=%s (%dx%d srgb=%d)"),*Part.Name,*T.Key.ToString(),T.Value,Data.Textures.IsValidIndex(T.Value)?Data.Textures[T.Value].SourceWidth:-1,Data.Textures.IsValidIndex(T.Value)&&!Data.Textures[T.Value].Mips.IsEmpty()&&Data.Textures[T.Value].Mips.Last().BGRA.Num()>=4?*FString::Printf(TEXT("%d,%d,%d,%d"),Data.Textures[T.Value].Mips.Last().BGRA[0],Data.Textures[T.Value].Mips.Last().BGRA[1],Data.Textures[T.Value].Mips.Last().BGRA[2],Data.Textures[T.Value].Mips.Last().BGRA[3]):TEXT("?"),Textures.IsValidIndex(T.Value)&&Textures[T.Value]?Textures[T.Value]->GetSizeX():0,Textures.IsValidIndex(T.Value)&&Textures[T.Value]?Textures[T.Value]->GetSizeY():0,Textures.IsValidIndex(T.Value)&&Textures[T.Value]?int32(Textures[T.Value]->SRGB):-1);}UE_LOG(LogTemp,Display,TEXT("OK shared dump %s recipe=%s outline=%d"),*Part.Name,*Name,Part.Outline?1:0);FKKRuntimeMaterialBinding OB;FString OE;if(Part.Outline&&OKPrepareRuntimeSharedMaterialBinding(Part,Scene,OB,OE,true)){for(const auto& V:OB.Scalars)UE_LOG(LogTemp,Display,TEXT("OK shared outline dump %s %s=%g"),*Part.Name,*V.Key.ToString(),V.Value);for(const auto& T:OB.Textures)UE_LOG(LogTemp,Display,TEXT("OK shared outline dump %s %s=texture %d"),*Part.Name,*T.Key.ToString(),T.Value);}else if(Part.Outline)UE_LOG(LogTemp,Display,TEXT("OK shared outline dump %s failed: %s"),*Part.Name,*OE);}}
        // The head (face, eyes, brows, nose, tears) pressed flat along the view, as in the street (ok.FaceFlatten).
        // Eyes, eyelines and eyebrows on the <Parent>_Fg variant: mixed with her hair (UpdateForegroundHair).
        UMaterialInterface* Fore=Parent&&OKPreviewForegroundFacePart(Part.Name)?OKPreviewForegroundParent(Root,Name):nullptr;
        if(Fore)Parent=Fore;
        UMaterialInterface* Flat=Part.Role==TEXT("head")?FlatParent(Parent):nullptr;
        auto* Material=OKCreateRuntimeSharedMaterial(Part,Textures,Flat?Flat:Parent,Scene,Error);
        if(Material&&Flat)Actor->FlatFaceMaterials.Add(Material);
        if(Material&&Fore)Actor->ForegroundFaceMaterials.Add(Material);
        // Its PSOs asked for now, while the high model is still loading: asked when its part first drew, a cold driver
        // cache had them still compiling and the one-on-one's first frame waited 100-200 ms each (2026-11-12).
        UKKAffineProceduralMeshComponent::PrecacheAhead(Flat?Flat:Parent);
#if WITH_EDITOR
        if(!Material){UE_LOG(LogTemp,Warning,TEXT("Shared material for part %d (%s): %s; its own graph instead"),Part.NativePart,*Name,*Error);Error.Reset();++Uncovered;return 1;}
#endif
        if(!Material){UE_LOG(LogTemp,Warning,TEXT("Part %d (%s) left out: %s"),Part.NativePart,*Part.Name,*Error);Error.Reset();++Uncovered;return 1;}
        if(Actor->ToonRampTex){UTexture* Existing=nullptr;if(Material->GetTextureParameterValue(FMaterialParameterInfo(TEXT("_RampG")),Existing))Material->SetTextureParameterValue(TEXT("_RampG"),Actor->ToonRampTex);}
        // HG faces light from the character's front instead of their bumpy normals.
        if(HG&&Part.Role==TEXT("head")){float Face=0;if(Material->GetScalarParameterValue(FMaterialParameterInfo(TEXT("__OK_HG_Face")),Face))Material->SetScalarParameterValue(TEXT("__OK_HG_Face"),1);}
        // OK_SHARED_PARAM_DUMP=1 (debugging): an item instance's colour, shadow and light parameters.
        if(Part.ItemDraw&&FPlatformMisc::GetEnvironmentVariable(TEXT("OK_SHARED_PARAM_DUMP"))==TEXT("1")){FString Line;for(const TCHAR* N:{TEXT("_Color"),TEXT("_ShadowColor"),TEXT("_LightColor0"),TEXT("_WorldSpaceLightPos0"),TEXT("_ambientshadowG"),TEXT("_LineColorG")}){FLinearColor V;if(Material->GetVectorParameterValue(FMaterialParameterInfo(N),V))Line+=FString::Printf(TEXT(" %s=(%.3f,%.3f,%.3f,%.3f)"),N,V.R,V.G,V.B,V.A);}UE_LOG(LogTemp,Display,TEXT("OK shared item params part=%s parent=%s%s"),*Part.Name,*Name,*Line);}
        To.Materials[Part.NativePart]=Material;
        if(Part.Outline&&OKRuntimeOutlineLayout(Recipe)){
            const FString OutlineName=Name+TEXT("_Outline");
            auto* OutlineParent=LoadParent(true);
            UMaterialInterface* OutlineFlat=Part.Role==TEXT("head")?FlatParent(OutlineParent):nullptr;
            auto* Outline=OKCreateRuntimeSharedMaterial(Part,Textures,OutlineFlat?OutlineFlat:OutlineParent,Scene,Error,true);
            UKKAffineProceduralMeshComponent::PrecacheAhead(OutlineFlat?OutlineFlat:OutlineParent);
            if(Outline&&OutlineFlat)Actor->FlatFaceMaterials.Add(Outline);
#if WITH_EDITOR
            if(!Outline){UE_LOG(LogTemp,Warning,TEXT("Shared outline for part %d (%s): %s"),Part.NativePart,*OutlineName,*Error);Error.Reset();}
#else
            if(!Outline){UE_LOG(LogTemp,Warning,TEXT("Outline of part %d (%s) left out: %s"),Part.NativePart,*Part.Name,*Error);Error.Reset();}
#endif
            if(Outline&&Actor->ToonRampTex){UTexture* Existing=nullptr;if(Outline->GetTextureParameterValue(FMaterialParameterInfo(TEXT("_RampG")),Existing))Outline->SetTextureParameterValue(TEXT("_RampG"),Actor->ToonRampTex);}
            To.Outlines[Part.NativePart]=Outline;
        }
        return 1;
    };
    while(Role.NextPart<Data.Parts.Num()){
        if(BuildPart(Data.Parts[Role.NextPart++])<0)return Fail();
        if(Role.NextPart<Data.Parts.Num()&&FPlatformTime::Seconds()>=Deadline)return 0;
    }
    if(Actor->bCharacterDisplayShadows){
        for(UMaterialInstanceDynamic* Material:To.Materials){
            UTexture* ShadowTex=nullptr;
            if(Material&&Material->GetTextureParameterValue(FMaterialParameterInfo(TEXT("KKShadowDepth")),ShadowTex))Actor->ToonShadowMaterials.AddUnique(Material);
        }
        Actor->ToonShadowBoundIndex=INDEX_NONE;
        if(Actor->ToonShadowTargets.IsValidIndex(Actor->ToonShadowReadIndex))Actor->BindToonShadowTarget(Actor->ToonShadowReadIndex);
        Actor->UpdateToonShadowProjection();
    }
    UE_LOG(LogTemp,Display,TEXT("High model cooked shared materials root=%s style=%s parts=%d own_graph=%d"),*Role.Root,Role.HG?TEXT("hg"):TEXT("koikatsu"),To.Materials.Num(),Role.Uncovered);
    // A Studio item's instances are made and its textures uploaded: the decoded texture data is not needed again, and
    // a scene holds thousands of items (it stayed per actor: 28 -> 39 GB on a 1,900-item scene).
    if(Actor->bStudioItemShading)To.Source.RuntimeMaterials.Reset();
    To.Build.Reset();
    return 1;
}
static int32 OKPrepareCookedRole(AKKPreviewActor* Actor,FString& Error,double Budget=0.){
    return OKPrepareCookedRole(Actor,Error,Budget,FOKCookedRoleTarget{Actor->Session,Actor->CookedRoleMaterials,Actor->CookedRoleOutlines,Actor->CookedRoleBuild,Actor->LoadedTextures,false});
}
