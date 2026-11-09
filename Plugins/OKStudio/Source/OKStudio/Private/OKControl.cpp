#include "OKControl.h"
#include "Containers/Queue.h"
#include "Containers/Ticker.h"
#include "Dom/JsonObject.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformProcess.h"
#include "HAL/Runnable.h"
#include "HAL/RunnableThread.h"
#include "HttpServerResponse.h"
#include "IPAddress.h"
#include "Misc/CoreDelegates.h"
#include "Misc/DateTime.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Misc/ScopeLock.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "SocketSubsystem.h"
#include "Sockets.h"
#include <atomic>

namespace
{
	constexpr int32 MaxRequestBytes = 64 << 20;
	constexpr double RequestTimeout = 600;

	struct FRoute
	{
		EHttpServerRequestVerbs Verbs;
		OKControl::FHandler Handler;
	};

	struct FRequest
	{
		uint64 Connection = 0;
		int32 Port = 0;
		TSharedPtr<FHttpServerRequest> Http;
	};

	struct FReply
	{
		uint64 Connection = 0;
		TSharedPtr<FHttpServerResponse> Http;
	};

	struct FConnection
	{
		FSocket* Socket = nullptr;
		int32 Port = 0;
		TArray<uint8> In, Out;
		int32 Sent = 0;
		bool bDispatched = false;
		double Began = 0;
	};

	struct FPeriodic
	{
		int32 Id = 0;
		double Seconds = 0, Next = 0;
		TFunction<void()> Work;
	};

	FString Status(int32 Code)
	{
		switch (Code)
		{
		case 200: return TEXT("OK");
		case 403: return TEXT("Forbidden");
		case 404: return TEXT("Not Found");
		case 405: return TEXT("Method Not Allowed");
		case 413: return TEXT("Payload Too Large");
		default: return TEXT("Status");
		}
	}

	TArray<uint8> Bytes(int32 Code, const TMap<FString, TArray<FString>>& Headers, const TArray<uint8>& Body)
	{
		FString Head = FString::Printf(TEXT("HTTP/1.1 %d %s\r\n"), Code, *Status(Code));
		for (const auto& Header : Headers)
			if (!Header.Key.Equals(TEXT("content-length"), ESearchCase::IgnoreCase) && !Header.Key.Equals(TEXT("connection"), ESearchCase::IgnoreCase))
				for (const FString& Value : Header.Value) Head += Header.Key + TEXT(": ") + Value + TEXT("\r\n");
		Head += FString::Printf(TEXT("Content-Length: %d\r\nConnection: close\r\n\r\n"), Body.Num());
		const FTCHARToUTF8 Utf8(*Head);
		TArray<uint8> Out;
		Out.Append(reinterpret_cast<const uint8*>(Utf8.Get()), Utf8.Length());
		Out.Append(Body);
		return Out;
	}

	TArray<uint8> Plain(int32 Code, const FString& Text)
	{
		const FTCHARToUTF8 Utf8(*Text);
		TArray<uint8> Body;
		Body.Append(reinterpret_cast<const uint8*>(Utf8.Get()), Utf8.Length());
		return Bytes(Code, { { TEXT("Content-Type"), { TEXT("text/plain; charset=utf-8") } } }, Body);
	}

	/** Every channel can run console commands, so a page in the user's browser must not reach them: it cannot leave out
	 * Sec-Fetch-Site on a request to 127.0.0.1, and a rebound domain name shows in Host. */
	bool FromBrowserPage(const TMap<FString, FString>& Headers)
	{
		if (Headers.Contains(TEXT("origin"))) return true;
		if (const FString* Site = Headers.Find(TEXT("sec-fetch-site"))) if (*Site != TEXT("none")) return true;
		const FString* Host = Headers.Find(TEXT("host"));
		if (!Host) return false;
		FString Name = *Host;
		Name.Split(TEXT(":"), &Name, nullptr);
		return !Name.Equals(TEXT("127.0.0.1")) && !Name.Equals(TEXT("localhost"), ESearchCase::IgnoreCase);
	}

	class FServer final : public FRunnable
	{
	public:
		FServer()
		{
			Ticker = FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateRaw(this, &FServer::Drain));
			Started = FDateTime::UtcNow().ToUnixTimestamp();
			Thread.Reset(FRunnableThread::Create(this, TEXT("OKControl"), 0, TPri_BelowNormal));
			FCoreDelegates::OnEnginePreExit.AddRaw(this, &FServer::Shutdown);
		}

		void Shutdown()
		{
			if (bStop) return;
			bStop = true;
			if (Thread) Thread->WaitForCompletion();
			Thread.Reset();
			FTSTicker::RemoveTicker(Ticker);
			IFileManager::Get().Delete(*RegistryFile(), false, true, true);
		}

		FString RegistryFolder() const { return OKControl::Checkout() / TEXT("Saved/OKControl"); }
		FString RegistryFile() const { return RegistryFolder() / FString::Printf(TEXT("%u.json"), FPlatformProcess::GetCurrentProcessId()); }

		int32 Open(int32 Port)
		{
			ISocketSubsystem* Sockets = ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM);
			if (!Sockets) return 0;
			TSharedRef<FInternetAddr> Address = Sockets->CreateInternetAddr(FNetworkProtocolTypes::IPv4);
			bool bValid = false;
			Address->SetIp(TEXT("127.0.0.1"), bValid);
			Address->SetPort(Port);
			FSocket* Socket = Sockets->CreateSocket(NAME_Stream, TEXT("OKControl"), FNetworkProtocolTypes::IPv4);
			if (!Socket) return 0;
			Socket->SetReuseAddr(false);
			Socket->SetNonBlocking(true);
			if (!bValid || !Socket->Bind(*Address) || !Socket->Listen(16))
			{
				Sockets->DestroySocket(Socket);
				return 0;
			}
			FScopeLock Lock(&Guard);
			Listeners.Add(Port, Socket);
			return Port;
		}

		void SetValue(const FString& Key, const FString& Value)
		{
			FScopeLock Lock(&Guard);
			Values.Add(Key, Value);
			bRegistryDirty = true;
		}

		int32 AddPeriodic(double Seconds, TFunction<void()> Work)
		{
			FScopeLock Lock(&PeriodicGuard);
			FPeriodic& P = Periodics.AddDefaulted_GetRef();
			P.Id = ++LastPeriodic;
			P.Seconds = Seconds;
			P.Work = MoveTemp(Work);
			return P.Id;
		}

		void RemovePeriodic(int32 Id)
		{
			FScopeLock Lock(&PeriodicGuard);
			Periodics.RemoveAll([Id](const FPeriodic& P) { return P.Id == Id; });
		}

		TMap<int32, TMap<FString, FRoute>> Routes;	// game thread
		TMap<FString, int32> Channels;	// game thread

	private:
		uint32 Run() override
		{
			while (!bStop)
			{
				Accept();
				for (FReply Reply; Replies.Dequeue(Reply);)
					if (FConnection* C = Connections.Find(Reply.Connection))
						C->Out = Bytes(Reply.Http->Code == EHttpServerResponseCodes::Unknown ? 200 : int32(Reply.Http->Code), Reply.Http->Headers, Reply.Http->Body);
				for (auto It = Connections.CreateIterator(); It; ++It)
					if (!Pump(It->Key, It->Value))
					{
						ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM)->DestroySocket(It->Value.Socket);
						It.RemoveCurrent();
					}
				RunPeriodics();
				WriteRegistry();
				FPlatformProcess::Sleep(Connections.IsEmpty() ? .01f : .001f);
			}
			for (auto& C : Connections) ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM)->DestroySocket(C.Value.Socket);
			Connections.Reset();
			FScopeLock Lock(&Guard);
			for (auto& L : Listeners) ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM)->DestroySocket(L.Value);
			Listeners.Reset();
			return 0;
		}

		void Accept()
		{
			FScopeLock Lock(&Guard);
			for (auto& L : Listeners)
			{
				bool bPending = false;
				while (L.Value->HasPendingConnection(bPending) && bPending)
				{
					FSocket* Socket = L.Value->Accept(TEXT("OKControl"));
					if (!Socket) break;
					Socket->SetNonBlocking(true);
					FConnection& C = Connections.Add(++LastConnection);
					C.Socket = Socket;
					C.Port = L.Key;
					C.Began = FPlatformTime::Seconds();
				}
			}
		}

		/** false: the connection is finished. */
		bool Pump(uint64 Id, FConnection& C)
		{
			if (!C.Out.IsEmpty())
			{
				int32 Sent = 0;
				if (!C.Socket->Send(C.Out.GetData() + C.Sent, C.Out.Num() - C.Sent, Sent)) return C.Socket->GetConnectionState() == SCS_Connected;
				C.Sent += Sent;
				return C.Sent < C.Out.Num();
			}
			if (FPlatformTime::Seconds() - C.Began > RequestTimeout) return false;
			if (C.bDispatched) return true;
			uint8 Chunk[65536];
			int32 Read = 0;
			while (C.Socket->Recv(Chunk, sizeof(Chunk), Read, ESocketReceiveFlags::None) && Read > 0) C.In.Append(Chunk, Read);
			if (C.Socket->GetConnectionState() == SCS_ConnectionError) return false;
			if (C.In.Num() > MaxRequestBytes) { C.Out = Plain(413, TEXT("too large\n")); return true; }
			Parse(Id, C);
			return true;
		}

		void Parse(uint64 Id, FConnection& C)
		{
			int32 End = INDEX_NONE;
			for (int32 I = 0; I + 3 < C.In.Num(); ++I)
				if (C.In[I] == '\r' && C.In[I + 1] == '\n' && C.In[I + 2] == '\r' && C.In[I + 3] == '\n') { End = I; break; }
			if (End == INDEX_NONE) return;
			const FUTF8ToTCHAR Head(reinterpret_cast<const ANSICHAR*>(C.In.GetData()), End);
			TArray<FString> Lines;
			FString(Head.Length(), Head.Get()).ParseIntoArray(Lines, TEXT("\r\n"));
			TArray<FString> First;
			if (Lines.IsEmpty() || Lines[0].ParseIntoArray(First, TEXT(" ")) < 2) { C.Out = Plain(404, TEXT("bad request\n")); return; }
			TMap<FString, FString> Headers;
			for (int32 I = 1; I < Lines.Num(); ++I)
			{
				FString Name, Value;
				if (Lines[I].Split(TEXT(":"), &Name, &Value)) Headers.Add(Name.TrimStartAndEnd().ToLower(), Value.TrimStartAndEnd());
			}
			const int32 Length = Headers.Contains(TEXT("content-length")) ? FCString::Atoi(*Headers[TEXT("content-length")]) : 0;
			if (Length < 0 || Length > MaxRequestBytes) { C.Out = Plain(413, TEXT("too large\n")); return; }
			if (C.In.Num() < End + 4 + Length) return;
			if (FromBrowserPage(Headers)) { C.Out = Plain(403, TEXT("not from a browser page\n")); return; }
			auto Http = MakeShared<FHttpServerRequest>();
			Http->Verb = First[0] == TEXT("GET") ? EHttpServerRequestVerbs::VERB_GET : First[0] == TEXT("POST") ? EHttpServerRequestVerbs::VERB_POST : EHttpServerRequestVerbs::VERB_NONE;
			FString Path = First[1], Query;
			if (Path.Split(TEXT("?"), &Path, &Query))
			{
				TArray<FString> Pairs;
				Query.ParseIntoArray(Pairs, TEXT("&"));
				for (const FString& Pair : Pairs)
				{
					FString Name, Value;
					if (Pair.Split(TEXT("="), &Name, &Value)) Http->QueryParams.Add(Name, Value);
					else Http->QueryParams.Add(Pair, FString());
				}
			}
			Http->FullPath = FHttpPath(Path);
			Http->RelativePath = FHttpPath(Path);
			for (const auto& Header : Headers) Http->Headers.Add(Header.Key, { Header.Value });
			Http->Body.Append(C.In.GetData() + End + 4, Length);
			C.bDispatched = true;
			C.In.Empty();
			Requests.Enqueue({ Id, C.Port, Http });
		}

		void RunPeriodics()
		{
			FScopeLock Lock(&PeriodicGuard);
			const double Now = FPlatformTime::Seconds();
			for (FPeriodic& P : Periodics)
				if (Now >= P.Next)
				{
					P.Next = Now + P.Seconds;
					P.Work();
				}
		}

		void WriteRegistry()
		{
			TMap<FString, FString> Copy;
			TArray<int32> Ports;
			{
				FScopeLock Lock(&Guard);
				if (!bRegistryDirty) return;
				bRegistryDirty = false;
				Copy = Values;
			}
			TSharedRef<FJsonObject> O = MakeShared<FJsonObject>();
			O->SetNumberField(TEXT("pid"), FPlatformProcess::GetCurrentProcessId());
			O->SetNumberField(TEXT("started"), double(Started));
			for (const auto& V : Copy) O->SetStringField(V.Key, V.Value);
			FString Text;
			FJsonSerializer::Serialize(O, TJsonWriterFactory<>::Create(&Text));
			const FString File = RegistryFile();
			IFileManager::Get().MakeDirectory(*RegistryFolder(), true);
			if (FFileHelper::SaveStringToFile(Text, *(File + TEXT(".tmp")), FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM)) IFileManager::Get().Move(*File, *(File + TEXT(".tmp")), true);
		}

		/** Game thread: the requests that came since the last tick. The route is looked up here, so one that went with its
		 * scene is not called. */
		bool Drain(float)
		{
			for (FRequest Request; Requests.Dequeue(Request);)
			{
				const uint64 Id = Request.Connection;
				FHttpResultCallback Done = [this, Id](TUniquePtr<FHttpServerResponse>&& Response)
				{
					Replies.Enqueue({ Id, TSharedPtr<FHttpServerResponse>(Response.Release()) });
				};
				const TMap<FString, FRoute>* Port = Routes.Find(Request.Port);
				const FRoute* Route = Port ? Port->Find(Request.Http->RelativePath.GetPath()) : nullptr;
				if (Route && EnumHasAnyFlags(Route->Verbs, Request.Http->Verb)) Route->Handler(*Request.Http, Done);
				else
				{
					TUniquePtr<FHttpServerResponse> Missing = FHttpServerResponse::Create(Route ? TEXT("wrong verb\n") : TEXT("no such route\n"), TEXT("text/plain; charset=utf-8"));
					Missing->Code = Route ? EHttpServerResponseCodes::BadMethod : EHttpServerResponseCodes::NotFound;
					Done(MoveTemp(Missing));
				}
			}
			return true;
		}

		TUniquePtr<FRunnableThread> Thread;
		FTSTicker::FDelegateHandle Ticker;
		std::atomic<bool> bStop{ false };
		int64 Started = 0;

		FCriticalSection Guard;	// Listeners, Values
		TMap<int32, FSocket*> Listeners;
		TMap<FString, FString> Values;
		bool bRegistryDirty = true;

		FCriticalSection PeriodicGuard;
		TArray<FPeriodic> Periodics;
		int32 LastPeriodic = 0;

		TQueue<FRequest, EQueueMode::Mpsc> Requests;
		TQueue<FReply, EQueueMode::Mpsc> Replies;
		TMap<uint64, FConnection> Connections;	// control thread
		uint64 LastConnection = 0;
	};

	FServer& Server()
	{
		static FServer* Instance = new FServer();
		return *Instance;
	}

	int32 PortBase()
	{
		FString Text;
		TSharedPtr<FJsonObject> Config;
		double Base = 47860;
		if (FFileHelper::LoadFileToString(Text, *(OKControl::Checkout() / TEXT("local-instance.json"))) && FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text), Config) && Config)
			Config->TryGetNumberField(TEXT("port_base"), Base);
		return int32(Base);
	}
}

namespace OKControl
{
	int32 Listen(const FString& Channel, int32 Offset, int32 Explicit)
	{
		check(IsInGameThread());
		FServer& S = Server();
		if (const int32* Port = S.Channels.Find(Channel)) return *Port;
		int32 Port = 0;
		if (Explicit > 0) Port = S.Open(Explicit);
		else
		{
			const int32 First = PortBase() + Offset;
			for (int32 Try = 0; Try < 40 && !Port; ++Try) Port = S.Open(First + Try * 100);
		}
		if (!Port)
		{
			UE_LOG(LogTemp, Warning, TEXT("OK control: no port for %s"), *Channel);
			return 0;
		}
		S.Channels.Add(Channel, Port);
		S.SetValue(TEXT("port_") + Channel, FString::FromInt(Port));
		UE_LOG(LogTemp, Display, TEXT("OK control: %s on 127.0.0.1:%d"), *Channel, Port);
		return Port;
	}

	void Bind(const FString& Channel, const FString& Path, EHttpServerRequestVerbs Verbs, FHandler Handler)
	{
		check(IsInGameThread());
		FServer& S = Server();
		if (const int32* Port = S.Channels.Find(Channel)) S.Routes.FindOrAdd(*Port).Add(Path, { Verbs, MoveTemp(Handler) });
	}

	void Unbind(const FString& Channel)
	{
		check(IsInGameThread());
		FServer& S = Server();
		if (const int32* Port = S.Channels.Find(Channel)) S.Routes.Remove(*Port);
	}

	void Publish(const FString& Key, const FString& Value)
	{
		Server().SetValue(Key, Value);
	}

	FString Checkout()
	{
		static const FString Root = []
		{
			for (FString Start : { FPaths::ConvertRelativePathToFull(FPaths::ProjectDir()), FPaths::ConvertRelativePathToFull(FPlatformProcess::BaseDir()) })
				for (FString Dir = Start; !Dir.IsEmpty();)
				{
					if (IFileManager::Get().FileExists(*(Dir / TEXT("Tools/ok_instance.lua")))) return Dir.TrimChar(TEXT('/'));
					const FString Parent = FPaths::GetPath(Dir.EndsWith(TEXT("/")) ? Dir.LeftChop(1) : Dir);
					if (Parent == Dir || Parent.Len() < 3) break;
					Dir = Parent;
				}
			return FPaths::ConvertRelativePathToFull(FPaths::ProjectDir());
		}();
		return Root;
	}

	bool TakenByOther(const FString& Key, const FString& Value)
	{
		const FString Folder = Checkout() / TEXT("Saved/OKControl");
		const uint32 Self = FPlatformProcess::GetCurrentProcessId();
		TArray<FString> Files;
		IFileManager::Get().FindFiles(Files, *(Folder / TEXT("*.json")), true, false);
		for (const FString& File : Files)
		{
			const uint32 Pid = uint32(FCString::Atoi64(*FPaths::GetBaseFilename(File)));
			if (Pid == Self) continue;
			if (!FPlatformProcess::IsApplicationRunning(Pid))
			{
				IFileManager::Get().Delete(*(Folder / File), false, true, true);
				continue;
			}
			FString Text, Seen;
			TSharedPtr<FJsonObject> O;
			if (FFileHelper::LoadFileToString(Text, *(Folder / File)) && FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text), O) && O && O->TryGetStringField(Key, Seen) && Seen == Value) return true;
		}
		return false;
	}

	int32 Every(double Seconds, TFunction<void()> Work)
	{
		return Server().AddPeriodic(Seconds, MoveTemp(Work));
	}

	void Cancel(int32 Id)
	{
		Server().RemovePeriodic(Id);
	}
}
