// What mods registered (OKStudioMod.h) shown in the studio: the command table, the top tool row, the object tree's context
// menu and the rows of the 狀態 / 畫面設定 pages. The panel's own code only calls in here.
#include "SOKStudioPanel.h"

namespace
{
	/** The mod buttons of the top tool row; rebuilt when the registry changes (mods register after the studio opens too),
	 *  which also refreshes the panel's command table and open page. */
	class SOKStudioModTools : public SCompoundWidget
	{
	public:
		SLATE_BEGIN_ARGS(SOKStudioModTools) {}
			SLATE_ARGUMENT(TFunction<void(const TSharedRef<SHorizontalBox>&)>, Build)
			SLATE_ARGUMENT(TFunction<void()>, OnRegistryChanged)
		SLATE_END_ARGS()

		void Construct(const FArguments& Args)
		{
			Build = Args._Build;
			OnRegistryChanged = Args._OnRegistryChanged;
			Rebuild();
		}

		virtual void Tick(const FGeometry& Geometry, double Now, float Delta) override
		{
			SCompoundWidget::Tick(Geometry, Now, Delta);
			if (Generation == FOKStudioModRegistry::Get().Generation()) return;
			Rebuild();
			if (OnRegistryChanged) OnRegistryChanged();
		}

	private:
		void Rebuild()
		{
			Generation = FOKStudioModRegistry::Get().Generation();
			TSharedRef<SHorizontalBox> Box = SNew(SHorizontalBox);
			if (Build) Build(Box);
			ChildSlot[Box];
		}

		TFunction<void(const TSharedRef<SHorizontalBox>&)> Build;
		TFunction<void()> OnRegistryChanged;
		int32 Generation = -1;
	};

	const FOKStudioModControl* FindControl(const FString& Owner, const FString& Id)
	{
		return FOKStudioModRegistry::Get().Controls().FindByPredicate([&](const FOKStudioModControl& C) { return C.Owner == Owner && C.Id == Id; });
	}
}

void SOKStudioPanel::SyncModCommands()
{
	const FOKStudioModRegistry& Registry = FOKStudioModRegistry::Get();
	if (ModCommandGeneration == Registry.Generation()) return;
	ModCommandGeneration = Registry.Generation();
	for (const FString& Id : ModCommandIds) { Commands.Remove(Id); CommandOrder.Remove(Id); }
	ModCommandIds.Reset();
	for (const FOKStudioModCommand& C : Registry.Commands())
	{
		const FString Id = C.Id();
		if (Commands.Contains(Id)) continue;
		// Looked up again when run: a mod disabled since leaves a command that fails instead of calling into it.
		AddCommand(Id, C.Label, [Id](const FString& Arg) { const FOKStudioModCommand* X = FOKStudioModRegistry::Get().FindCommand(Id); return X && X->Run && X->Run(Arg); });
		ModCommandIds.Add(Id);
	}
}

void SOKStudioPanel::AddModTools(const TSharedRef<SHorizontalBox>& Box)
{
	// A mod's status line goes to this panel's status bar while it is open.
	FOKStudioModRegistry::Get().ShowStatus = [Weak = TWeakPtr<SWidget>(AsShared())](const FString& Text)
	{
		if (const TSharedPtr<SWidget> Panel = Weak.Pin()) StaticCastSharedPtr<SOKStudioPanel>(Panel)->SetStatus(Text);
	};
	Box->AddSlot().AutoWidth()
	[
		SNew(SOKStudioModTools)
		.Build([this](const TSharedRef<SHorizontalBox>& Row)
		{
			for (const FOKStudioModToolbarButton& B : FOKStudioModRegistry::Get().ToolbarButtons())
			{
				const FString Tooltip = B.Tooltip.IsEmpty() ? B.Label : B.Tooltip;
				Row->AddSlot().AutoWidth().Padding(0.f, 0.f, 7.f, 0.f)
					[Tagged(*FString::Printf(TEXT("ModTool_%s.%s"), *B.Owner, *B.Id), SNew(SBox).MinDesiredWidth(33.f).ToolTipText(FText::FromString(Tip(Tooltip, B.Command)))
						[OKStudioStyle::Button(FText::FromString(B.Label), Cmd(B.Command, B.Arg), 0.f, 33.f, false, 10.f)])];
			}
		})
		.OnRegistryChanged([this]
		{
			SyncModCommands();
			// The open page shows the rows of what is registered now.
			if (Page == EPage::State || Page == EPage::Scene) DeferRebuild();
		})
	];
}

void SOKStudioPanel::AddModMenuItems(const TSharedRef<SVerticalBox>& Box)
{
	if (!Game.IsValid() || !Game->Document) return;
	for (const FOKStudioModMenuItem& M : FOKStudioModRegistry::Get().MenuItems())
	{
		if (M.Visible && !M.Visible(*Game->Document, Game->Selection)) continue;
		const FString Command = M.Command, Arg = M.Arg;
		Box->AddSlot().AutoHeight().Padding(0.f, 0.f, 0.f, 1.f)
			[Tagged(*FString::Printf(TEXT("ModMenu_%s.%s"), *M.Owner, *M.Id), OKStudioStyle::Button(FText::FromString(Tip(M.Label, Command)),
				[this, Command, Arg] { FSlateApplication::Get().DismissAllMenus(); RunCommand(Command, Arg); }, 190.f, 18.f, false, 10.f))];
	}
}

void SOKStudioPanel::ModRows(EOKStudioModPanel Where, int32 ObjectId)
{
	ModRowsShown = 0;
	if (!Game.IsValid() || !Game->Document || !Props) return;
	FString Heading;
	for (const FOKStudioModControl& C : FOKStudioModRegistry::Get().Controls())
	{
		if (C.Panel != Where) continue;
		if (C.Owner != Heading) { Heading = C.Owner; Label(TEXT("Mod：") + Heading); }
		const FString Owner = C.Owner, Id = C.Id;
		// The callbacks look the control up each time: rows of a mod removed while the page is open do nothing.
		auto GetV = [this, Owner, Id, ObjectId]() -> FString
		{
			const FOKStudioModControl* X = FindControl(Owner, Id);
			return X && X->Get && Game.IsValid() && Game->Document ? X->Get(*Game->Document, ObjectId) : FString();
		};
		auto SetV = [this, Owner, Id, ObjectId](const FString& V)
		{
			const FOKStudioModControl* X = FindControl(Owner, Id);
			if (X && X->Set && Game.IsValid() && Game->Document && X->Set(*Game->Document, ObjectId, V)) Changed();
		};
		const FString RowTag = FString::Printf(TEXT("ModRow_%s.%s"), *Owner, *Id);
		switch (C.Kind)
		{
		case EOKStudioModControlKind::Toggle:
			Props->AddSlot().AutoHeight().Padding(0.f, 1.f)
				[Tagged(*RowTag, CheckBox(C.Label, [GetV] { const FString V = GetV(); return V == TEXT("1") || V.ToBool(); }, [SetV](bool bOn) { SetV(bOn ? TEXT("1") : TEXT("0")); }))];
			break;
		case EOKStudioModControlKind::Slider:
			Row(C.Label, Tagged(*RowTag, Spin([GetV] { return FCString::Atof(*GetV()); }, [SetV](float V) { SetV(FString::SanitizeFloat(V)); }, C.Min, C.Max, C.Step)));
			break;
		case EOKStudioModControlKind::Dropdown:
			ChoiceF(C.Label, C.Options, [GetV] { return FCString::Atoi(*GetV()); }, [SetV](int32 V) { SetV(FString::FromInt(V)); });
			break;
		case EOKStudioModControlKind::Color:
			Row(C.Label, Tagged(*RowTag, Swatch(TEXT("mod:") + Owner + TEXT(".") + Id, C.Label,
				[GetV] { FLinearColor Color = FLinearColor::White; Color.InitFromString(GetV()); return Color; },
				[SetV](const FLinearColor& Color) { SetV(Color.ToString()); })));
			break;
		case EOKStudioModControlKind::Text:
			Row(C.Label, Tagged(*RowTag, TextBox(GetV, SetV)), 0.3f);
			break;
		case EOKStudioModControlKind::Button:
			Props->AddSlot().AutoHeight().Padding(0.f, 2.f)[Tagged(*RowTag, OKStudioStyle::Button(FText::FromString(C.Label), Cmd(C.Command, C.Arg), 0.f, 20.f, false, 10.f))];
			break;
		}
		++ModRowsShown;
	}
}
