#include "OKCardIdentity.h"

#include "OKCardIdentityCore.inl"

FString OKCardIdentity(const TArray<uint8>& Bytes)
{
	char Hex[65];
	if (!OKCardIdentityCore::Identity(Bytes.GetData(), size_t(Bytes.Num()), Hex)) return FString();
	return FString(ANSI_TO_TCHAR(Hex));
}
