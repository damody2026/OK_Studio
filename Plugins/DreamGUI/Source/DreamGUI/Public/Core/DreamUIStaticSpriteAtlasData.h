// Copyright 2019-Present LexLiu. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "DreamUISettings.h"
#include "Engine/DataAsset.h"
#include "Utils/MaxRectsBinPack/MaxRectsBinPack.h"
#include "Engine/Texture2D.h"
#include "DreamUIStaticSpriteAtlasData.generated.h"

class UDreamUISpriteData;
class UDreamSpriteBase;
class IDreamUISpriteRenderInterface;

//Static packing Sprite into atlas
UCLASS(NotBlueprintable, NotBlueprintType)
class DREAMGUI_API UDreamUIStaticSpriteAtlasData :public UObject
{
	GENERATED_BODY()
private:
	friend class FDreamUIStaticSpriteAtlasDataCustomization;
	/** weather or not use srgb for generated atlas texture */
	UPROPERTY(EditAnywhere, Category = "Atlas-Setting")
		bool AtlasTextureUseSRGB = true;
	UPROPERTY(EditAnywhere, Category = "Atlas-Setting")
		TEnumAsByte<TextureFilter> AtlasTextureFilter = TextureFilter::TF_Trilinear;
#if WITH_EDITORONLY_DATA
	/** space between two sprites when package into atlas */
	UPROPERTY(EditAnywhere, Category = "Atlas-Setting")
		int32 SpaceBetweenSprites = 2;
	/** Repeat edge pixel fill spaced between other sprites in atlas texture */
	UPROPERTY(EditAnywhere, Category = "Atlas-Setting")
		int32 EdgePixelPadding = 2;
	/** If packing atlas texture's size is larger than this, then packing operation will abort. */
	UPROPERTY(EditAnywhere, Category = "Atlas-Setting")
	EDreamUIAtlasTextureSizeType MaxTextureSize = EDreamUIAtlasTextureSizeType::SIZE_2048x2048;
#endif

	/** Generated atlas texture. */
	UPROPERTY(VisibleAnywhere, Transient, Category = "DreamGUI")
		TArray<TObjectPtr<UTexture2D>> AtlasTextureArray;
#if WITH_EDITORONLY_DATA
	/** Collected Sprite array to pack. */
	UPROPERTY(EditAnywhere, Category = "DreamGUI")
		TArray<TObjectPtr<UDreamUISpriteData>> SpriteDataArray;
	UPROPERTY(Transient)
	TArray<TObjectPtr<UDreamUISpriteData>> PrevSpriteDataArray;
	/** collection of all objects that use this atlas to render. Object must implement IUISpriteRenderableInterface. */
	UPROPERTY(VisibleAnywhere, Transient, Category = "DreamGUI", AdvancedDisplay)
		TArray<TWeakObjectPtr<UObject>> RenderSpriteArray;
	/**
	 * Store texture mip data, so we can recreate atlas texture with this data.
	 */
	UPROPERTY(Transient)
	TArray<uint8> TexturePixelData;
	UPROPERTY()
	FString TexturePixelDataMD5;
	UPROPERTY()
	bool bIsAtlasPackDirty = true;
#endif
	UPROPERTY()
	TArray<int32> TextureSizeArray;
	UPROPERTY()
	TArray<uint8> TexturePixelDataForBuild;
#if WITH_EDITOR
	FString GetCacheDataPath(const FString& InFileName)const;
	/** Check Sprite and render Sprite, remove not valid. */
	void CheckSprite();
	bool PackAtlas();
public:
	virtual void PostInitProperties() override;
	virtual void PreEditChange(FProperty* PropertyAboutToChange)override;
	virtual void PostEditChangeProperty(struct FPropertyChangedEvent& PropertyChangedEvent)override;
	bool ContainsSpriteData(UDreamUISpriteData* InSpriteData)const;
	void AddSpriteData(UDreamUISpriteData* InSpriteData);
	void RemoveSpriteData(UDreamUISpriteData* InSpriteData);
	void AddRenderSprite(TScriptInterface<IDreamUISpriteRenderInterface> InSprite);
	void RemoveRenderSprite(TScriptInterface<IDreamUISpriteRenderInterface> InSprite);
	
	void MarkNotInitialized();
	void MarkAtlasPackDirty();
	/** Return true if some spriteData is invalid */
	bool CheckInvalidSpriteData()const;
	void CleanupInvalidSpriteData();

	virtual void BeginCacheForCookedPlatformData(const ITargetPlatform* TargetPlatform)override;
	virtual void WillNeverCacheCookedPlatformDataAgain()override;
	virtual void ClearCachedCookedPlatformData(const ITargetPlatform* TargetPlatform)override;
private:
	bool TryPackAtlas(UDreamUISpriteData* Sprite, rbp::MaxRectsBinPack& RectBinPack, TArray<rbp::Rect>& PackedRects, TArray<UDreamUISpriteData*>& PackedSprites);
	bool bWarningIsAlreadyAppearedAtCurrentPackingSession = false;
	bool bIsYesToAll = false;
	bool bIsNoToAll = false;
	bool bIsAddedToDelayedCall = false;
#endif
private:
	bool bIsInitialized = false;
	virtual void BeginDestroy()override;
	bool InitCheck();
	/**
	 * Pages this atlas put in the root set because something in the disregard-for-GC pool points at them: this atlas
	 * itself, or a sprite packed into it (NotePageHolder). Nothing else roots a page.
	 */
	TArray<TWeakObjectPtr<UTexture2D>> PagesRootedForPermanentHolders;
	void ReleasePermanentHolderRoots();
public:
	/**
	 * Say that Holder now points at Page, one of this atlas's pages. The pages are transient textures made at run time
	 * and owned by this atlas alone; an object in the disregard-for-GC pool (one loaded while the engine starts) may
	 * point only at objects in the pool or in the root set, and a cooked Development build's GC verification fails on
	 * the first collection otherwise -- as it did for the dynamic atlas's page under the default white sprite (2026-11-18).
	 * So a page a pooled holder points at is rooted, until this atlas makes its pages again or goes away. In the editor
	 * the pool is empty and this roots nothing.
	 */
	void NotePageHolder(const UObject* Holder, UTexture2D* Page);
#if !UE_BUILD_SHIPPING
	/**
	 * DreamGUI.Debug.PermanentSpriteOnStaticAtlas [unprotected]: point the default white sprite -- in the disregard-for-GC
	 * pool in a cooked build -- at the page of a static atlas made here, collect garbage, and put the sprite back. With
	 * "unprotected" the page is not rooted, which is what a cooked Development build's GC verification stops on: the
	 * command reproduces the failure NotePageHolder prevents.
	 */
	static void DebugPermanentSpriteOnStaticAtlas(bool bProtected, FOutputDevice& Out);
#endif
	UFUNCTION(BlueprintCallable, Category = DreamGUI)
		UTexture2D* GetAtlasTexture(int32 Index);
	UFUNCTION(BlueprintCallable, Category = DreamGUI)
		bool ReadPixel(int InTextureIndex, const FVector2D& InUV, FColor& OutPixel);
};