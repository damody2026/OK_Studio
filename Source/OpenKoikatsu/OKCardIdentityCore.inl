// A card's identity in plain C++ (no Unreal types), so it can be built on its own and checked against
// Tools/ok-extract/src/oklib.rs `card_identity` (Docs/OK_MOD_S2_CARD_CHUNKS.md). Included by OKCardIdentity.cpp.
//
// The identity: the card's okId chunk (64 hex digits, lowercased) when it has one, else the sha256 of its bytes
// without the okVo (her own TTS voice), okMx (mod data) and okMr (mod resources) chunks. Same rule as oklib.rs and
// Tools/prepare_street_social_selection.lua.
#pragma once
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace OKCardIdentityCore {

struct FSha256 {
	uint32_t H[8] = {0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au, 0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u};
	uint8_t Block[64];
	size_t Used = 0;
	uint64_t Total = 0;

	static uint32_t Rotr(uint32_t X, int N) { return (X >> N) | (X << (32 - N)); }
	void Compress(const uint8_t* P) {
		static const uint32_t K[64] = {
			0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
			0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
			0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
			0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
			0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
			0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
			0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
			0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u};
		uint32_t W[64];
		for (int I = 0; I < 16; ++I) W[I] = (uint32_t(P[I * 4]) << 24) | (uint32_t(P[I * 4 + 1]) << 16) | (uint32_t(P[I * 4 + 2]) << 8) | uint32_t(P[I * 4 + 3]);
		for (int I = 16; I < 64; ++I) {
			const uint32_t S0 = Rotr(W[I - 15], 7) ^ Rotr(W[I - 15], 18) ^ (W[I - 15] >> 3);
			const uint32_t S1 = Rotr(W[I - 2], 17) ^ Rotr(W[I - 2], 19) ^ (W[I - 2] >> 10);
			W[I] = W[I - 16] + S0 + W[I - 7] + S1;
		}
		uint32_t A = H[0], B = H[1], C = H[2], D = H[3], E = H[4], F = H[5], G = H[6], Hh = H[7];
		for (int I = 0; I < 64; ++I) {
			const uint32_t T1 = Hh + (Rotr(E, 6) ^ Rotr(E, 11) ^ Rotr(E, 25)) + ((E & F) ^ (~E & G)) + K[I] + W[I];
			const uint32_t T2 = (Rotr(A, 2) ^ Rotr(A, 13) ^ Rotr(A, 22)) + ((A & B) ^ (A & C) ^ (B & C));
			Hh = G; G = F; F = E; E = D + T1; D = C; C = B; B = A; A = T1 + T2;
		}
		H[0] += A; H[1] += B; H[2] += C; H[3] += D; H[4] += E; H[5] += F; H[6] += G; H[7] += Hh;
	}
	void Update(const uint8_t* P, size_t N) {
		Total += N;
		if (Used) {
			const size_t Take = N < 64 - Used ? N : 64 - Used;
			memcpy(Block + Used, P, Take); Used += Take; P += Take; N -= Take;
			if (Used < 64) return;
			Compress(Block); Used = 0;
		}
		for (; N >= 64; P += 64, N -= 64) Compress(P);
		if (N) { memcpy(Block, P, N); Used = N; }
	}
	void Hex(char Out[65]) {
		const uint64_t Bits = Total * 8;
		const uint8_t One = 0x80, Zero = 0;
		Update(&One, 1);
		while (Used != 56) Update(&Zero, 1);
		uint8_t Len[8];
		for (int I = 0; I < 8; ++I) Len[I] = uint8_t(Bits >> (56 - 8 * I));
		Update(Len, 8);
		static const char Digits[] = "0123456789abcdef";
		for (int I = 0; I < 32; ++I) { const uint8_t Byte = uint8_t(H[I / 4] >> (24 - 8 * (I % 4))); Out[I * 2] = Digits[Byte >> 4]; Out[I * 2 + 1] = Digits[Byte & 15]; }
		Out[64] = 0;
	}
};

inline uint32_t ReadBE32(const uint8_t* P) { return (uint32_t(P[0]) << 24) | (uint32_t(P[1]) << 16) | (uint32_t(P[2]) << 8) | uint32_t(P[3]); }
inline bool IsKind(const uint8_t* P, const char* Kind) { return memcmp(P, Kind, 4) == 0; }
inline bool IsHex(char C) { return (C >= '0' && C <= '9') || (C >= 'a' && C <= 'f') || (C >= 'A' && C <= 'F'); }

// Writes the identity (64 lowercase hex digits) into Out. False: not a PNG, or a chunk runs past the end.
inline bool Identity(const uint8_t* Data, size_t Size, char Out[65]) {
	static const uint8_t Signature[8] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};
	if (Size < 8 || memcmp(Data, Signature, 8) != 0) return false;
	for (size_t At = 8; At + 12 <= Size;) {
		const size_t Len = ReadBE32(Data + At);
		if (Len > Size - At - 12) break;
		if (IsKind(Data + At + 4, "okId")) {
			bool bHex = Len == 64;
			for (size_t I = 0; bHex && I < 64; ++I) bHex = IsHex(char(Data[At + 8 + I]));
			if (bHex) {
				for (size_t I = 0; I < 64; ++I) { const char C = char(Data[At + 8 + I]); Out[I] = C >= 'A' && C <= 'F' ? char(C - 'A' + 'a') : C; }
				Out[64] = 0;
				return true;
			}
			break;
		}
		if (IsKind(Data + At + 4, "IEND")) break;
		At += 12 + Len;
	}
	FSha256 Hash;
	Hash.Update(Data, 8);
	size_t At = 8;
	while (At + 12 <= Size) {
		const size_t Len = ReadBE32(Data + At);
		if (Len > Size - At - 12) return false;
		const uint8_t* Kind = Data + At + 4;
		if (!IsKind(Kind, "okVo") && !IsKind(Kind, "okMx") && !IsKind(Kind, "okMr")) Hash.Update(Data + At, 12 + Len);
		At += 12 + Len;
		if (IsKind(Kind, "IEND")) break;
	}
	Hash.Update(Data + At, Size - At);
	Hash.Hex(Out);
	return true;
}

} // namespace OKCardIdentityCore
