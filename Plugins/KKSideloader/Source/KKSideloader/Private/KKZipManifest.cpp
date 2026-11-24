#include "KKZipManifest.h"
#include "HAL/FileManager.h"
#include "Misc/Paths.h"
#include "String/LexFromString.h"
#include "Serialization/Archive.h"
#include "XmlFile.h"
#include "zlib.h"

namespace
{
	struct FVersionToken { bool Number=true; int32 Value=0; FString Text; };
	TArray<FVersionToken> VersionTokens(FString Version){
		Version.TrimStartAndEndInline();while(!Version.IsEmpty()&&(Version[0]=='v'||Version[0]=='V'||Version[0]=='r'||Version[0]=='R'||Version[0]==' '))Version.RightChopInline(1);
		if(Version.IsEmpty())Version=TEXT("0");TArray<FVersionToken> Result;FString Run;
		auto Emit=[&](){FVersionToken Token;Token.Text=Run.IsEmpty()?TEXT("0"):Run;Token.Number=LexTryParseString(Token.Value,*Token.Text);Result.Add(Token);Run.Reset();};
		for(TCHAR C:Version){if(C=='.'||C==' '||C=='-'||C==','||C=='_'){Emit();continue;}
			if(!Run.IsEmpty()&&FChar::IsDigit(Run[Run.Len()-1])!=FChar::IsDigit(C))Emit();Run.AppendChar(C);}
		Emit();return Result;
	}
	uint16 U16(const uint8* P) { return uint16(P[0]) | (uint16(P[1]) << 8); }
	uint32 U32(const uint8* P) { return uint32(P[0]) | (uint32(P[1]) << 8) | (uint32(P[2]) << 16) | (uint32(P[3]) << 24); }
	bool ReadAt(FArchive& File, int64 Offset, int32 Size, TArray<uint8>& Bytes)
	{
		if (Offset < 0 || Size < 0 || Offset > File.TotalSize() - Size) return false;
		File.Seek(Offset); Bytes.SetNumUninitialized(Size);
		File.Serialize(Bytes.GetData(), Size);
		return !File.IsError();
	}
}

namespace KKZip
{
	int32 CompareVersions(const FString& A,const FString& B){
		const auto L=VersionTokens(A),R=VersionTokens(B);const FVersionToken Zero;
		for(int32 I=0;I<FMath::Max(L.Num(),R.Num());++I){const auto& X=L.IsValidIndex(I)?L[I]:Zero;const auto& Y=R.IsValidIndex(I)?R[I]:Zero;
			if(X.Number&&Y.Number){if(X.Value!=Y.Value)return X.Value<Y.Value?-1:1;}
			else {const FString XS=X.Number?FString::FromInt(X.Value):X.Text,YS=Y.Number?FString::FromInt(Y.Value):Y.Text;
				if(XS==TEXT("0")&&YS!=TEXT("0"))return -1;if(YS==TEXT("0")&&XS!=TEXT("0"))return 1;
				const int32 C=XS.Compare(YS,ESearchCase::CaseSensitive);if(C)return C;}}
		return 0;
	}

	bool ReadManifests(const FString& Path, TArray<FKKLocalMod>& Mods, FString& Error)
	{
		TUniquePtr<FArchive> File(IFileManager::Get().CreateFileReader(*Path));
		if (!File || File->TotalSize() < 22) { Error = TEXT("無法讀取 ZIP 結尾"); return false; }
		TArray<uint8> Tail;
		const int64 TailAt = FMath::Max<int64>(0, File->TotalSize() - 65557);
		if (!ReadAt(*File, TailAt, int32(File->TotalSize() - TailAt), Tail)) return false;
		int32 End = INDEX_NONE;
		for (int32 I = Tail.Num() - 22; I >= 0; --I)
		{
			if (U32(Tail.GetData() + I) == 0x06054b50 && I + 22 + U16(Tail.GetData() + I + 20) == Tail.Num()) { End = I; break; }
		}
		if (End == INDEX_NONE) { Error = TEXT("ZIP 結尾損毀"); return false; }
		const uint8* E = Tail.GetData() + End;
		const uint16 Count = U16(E + 10);
		const uint32 CentralSize = U32(E + 12), CentralAt = U32(E + 16);
		if (U16(E + 4) || U16(E + 6) || U16(E + 8) != Count || Count == 0xffff || CentralAt == 0xffffffff || CentralSize > 16 * 1024 * 1024)
		{ Error = TEXT("不支援多磁碟／ZIP64 或過大索引"); return false; }
		if (int64(CentralAt) + CentralSize > TailAt + End) { Error = TEXT("ZIP 索引超出範圍"); return false; }
		TArray<uint8> Central;
		if (!ReadAt(*File, CentralAt, int32(CentralSize), Central)) return false;
		int32 Pos = 0;
		for (uint16 I = 0; I < Count; ++I)
		{
			if (Pos > Central.Num() - 46 || U32(Central.GetData() + Pos) != 0x02014b50) { Error = TEXT("ZIP 索引損毀"); return false; }
			const uint8* C = Central.GetData() + Pos;
			const uint16 Flags = U16(C + 8), Method = U16(C + 10), NameSize = U16(C + 28);
			const uint32 Crc = U32(C + 16), Packed = U32(C + 20), Raw = U32(C + 24), LocalAt = U32(C + 42);
			const int32 EntrySize = 46 + NameSize + U16(C + 30) + U16(C + 32);
			if (EntrySize > Central.Num() - Pos) { Error = TEXT("ZIP 檔名損毀"); return false; }
			FUTF8ToTCHAR Name(reinterpret_cast<const ANSICHAR*>(C + 46), NameSize);
			FString EntryName(Name.Length(), Name.Get()); EntryName.ReplaceInline(TEXT("\\"), TEXT("/"));
			Pos += EntrySize;
			if (FPaths::GetCleanFilename(EntryName) != TEXT("manifest.xml")) continue;
			if (EntryName.StartsWith(TEXT("/")) || EntryName.Contains(TEXT("../")) || EntryName.Contains(TEXT(":")))
			{ Error = TEXT("manifest 路徑不合法"); return false; }
			if ((Flags & 1) || Raw == 0 || Raw > 1024 * 1024 || Packed > 2 * 1024 * 1024 || (Method != 0 && Method != 8))
			{ Error = TEXT("manifest 加密、過大或壓縮方式不支援"); return false; }
			TArray<uint8> Local, Data;
			if (!ReadAt(*File, LocalAt, 30, Local) || U32(Local.GetData()) != 0x04034b50 || U16(Local.GetData() + 8) != Method)
			{ Error = TEXT("manifest ZIP 標頭不符"); return false; }
			const int64 DataAt = int64(LocalAt) + 30 + U16(Local.GetData() + 26) + U16(Local.GetData() + 28);
			if (DataAt + Packed > CentralAt || !ReadAt(*File, DataAt, int32(Packed), Data)) { Error = TEXT("manifest 資料超出範圍"); return false; }
			TArray<uint8> XmlBytes;
			if (Method == 0)
			{
				if (Packed != Raw) { Error = TEXT("manifest 長度不符"); return false; }
				XmlBytes = MoveTemp(Data);
			}
			else
			{
				XmlBytes.SetNumUninitialized(Raw);
				z_stream Stream{}; Stream.next_in = Data.GetData(); Stream.avail_in = Packed;
				Stream.next_out = XmlBytes.GetData(); Stream.avail_out = Raw;
				if (inflateInit2(&Stream, -MAX_WBITS) != Z_OK) return false;
				const int32 Result = inflate(&Stream, Z_FINISH);
				const bool bExact = Result == Z_STREAM_END && Stream.total_out == Raw && Stream.total_in == Packed;
				inflateEnd(&Stream);
				if (!bExact) { Error = TEXT("manifest 解壓失敗"); return false; }
			}
			if (uint32(crc32(0, XmlBytes.GetData(), XmlBytes.Num())) != Crc) { Error = TEXT("manifest CRC 不符"); return false; }
			FUTF8ToTCHAR Text(reinterpret_cast<const ANSICHAR*>(XmlBytes.GetData()), XmlBytes.Num());
			FString XmlText(Text.Length(),Text.Get());
			// XML permits a UTF-8 BOM; ConstructFromBuffer does not strip the decoded U+FEFF.
			if(!XmlText.IsEmpty()&&XmlText[0]==TCHAR(0xFEFF))XmlText.RightChopInline(1);
			FXmlFile Xml(XmlText, EConstructMethod::ConstructFromBuffer);
			const FXmlNode* Root = Xml.GetRootNode();
			if (!Xml.IsValid() || !Root || Root->GetTag() != TEXT("manifest")) { Error = TEXT("manifest XML 不合法"); return false; }
			FKKLocalMod Mod; Mod.Path = Path;
			for (const FXmlNode* Child : Root->GetChildrenNodes())
			{
				if (Child->GetTag() == TEXT("guid")) Mod.Guid = Child->GetContent().TrimStartAndEnd();
				if (Child->GetTag() == TEXT("name")) Mod.Name = Child->GetContent().TrimStartAndEnd();
				if (Child->GetTag() == TEXT("version")) Mod.Version = Child->GetContent().TrimStartAndEnd();
			}
			if (Mod.Guid.IsEmpty()) { Error = TEXT("manifest 缺少 GUID"); return false; }
			Mods.Add(MoveTemp(Mod));
		}
		if (Mods.IsEmpty()) { Error = TEXT("封包沒有 manifest.xml"); return false; }
		return true;
	}

	bool SameContents(const FString& A, const FString& B)
	{
		TUniquePtr<FArchive> Left(IFileManager::Get().CreateFileReader(*A)), Right(IFileManager::Get().CreateFileReader(*B));
		if (!Left || !Right || Left->TotalSize() != Right->TotalSize()) return false;
		TArray<uint8> L, R;
		for (int64 At = 0; At < Left->TotalSize(); At += 65536)
		{
			const int32 N = int32(FMath::Min<int64>(65536, Left->TotalSize() - At));
			if (!ReadAt(*Left, At, N, L) || !ReadAt(*Right, At, N, R) || L != R) return false;
		}
		return true;
	}

	int32 PickInstalled(const TArray<FKKLocalMod>& Candidates, TFunctionRef<int64(const FKKLocalMod&)> ModifiedTicks)
	{
		// Sideloader.cs: version descending, then file name length; if any version is absent, newest modification time
		// wins. A stable order settles equal priorities without inventing a local override.
		const bool AllVersions=!Candidates.ContainsByPredicate([](const FKKLocalMod& M){return M.Version.IsEmpty();});
		int32 Best=0;
		for(int32 I=1;I<Candidates.Num();++I)
		{
			bool Better;
			if(AllVersions)
			{
				const int32 C=CompareVersions(Candidates[I].Version,Candidates[Best].Version);
				Better=C?C>0:Candidates[I].Path.Len()>Candidates[Best].Path.Len();
			}
			else Better=ModifiedTicks(Candidates[I])>ModifiedTicks(Candidates[Best]);
			if(Better)Best=I;
		}
		return Best;
	}
}
