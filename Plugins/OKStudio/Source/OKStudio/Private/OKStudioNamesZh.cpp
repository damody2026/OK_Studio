// Traditional Chinese for the Studio motion lists (U217). The catalogue's names stay as they are, for search and for the
// scene files; this is only what the lists show. Everyday words only: a name not found here shows as it is.
#include "OKStudioCatalog.h"

namespace
{
	const TMap<FString, FString>& Table()
	{
		static const TMap<FString, FString> Names = {
			// Groups
			{ TEXT("キャラ"), TEXT("角色") }, { TEXT("スタジオ"), TEXT("攝影棚") }, { TEXT("バトル"), TEXT("戰鬥") }, { TEXT("アウトドア"), TEXT("戶外") },
			{ TEXT("サマー"), TEXT("夏日") }, { TEXT("汎用"), TEXT("通用") }, { TEXT("アフタースクール"), TEXT("放學後") }, { TEXT("サンシャイン"), TEXT("陽光") },
			// Categories
			{ TEXT("基本"), TEXT("基本") }, { TEXT("ポーズ"), TEXT("姿勢") }, { TEXT("感情"), TEXT("情緒") }, { TEXT("歩く・走る"), TEXT("走路與跑步") },
			{ TEXT("立ち"), TEXT("站立") }, { TEXT("会話"), TEXT("對話") }, { TEXT("椅子"), TEXT("椅子") }, { TEXT("椅子・机"), TEXT("椅子與桌子") },
			{ TEXT("床"), TEXT("地板") }, { TEXT("食べる"), TEXT("吃東西") }, { TEXT("アクション"), TEXT("動作") }, { TEXT("リアクション"), TEXT("反應") },
			{ TEXT("寝"), TEXT("躺臥") }, { TEXT("ライブ"), TEXT("現場演出") }, { TEXT("追加"), TEXT("追加") }, { TEXT("和"), TEXT("和風") },
			{ TEXT("メカ"), TEXT("機械") }, { TEXT("ダンス"), TEXT("舞蹈") }, { TEXT("ファンタジー"), TEXT("奇幻") }, { TEXT("グラビア"), TEXT("寫真") },
			{ TEXT("休日"), TEXT("假日") }, { TEXT("ハロウィン"), TEXT("萬聖節") }, { TEXT("クリスマス"), TEXT("聖誕節") }, { TEXT("カットイン"), TEXT("特寫") },
			{ TEXT("格闘"), TEXT("格鬥") }, { TEXT("気弾"), TEXT("氣彈") }, { TEXT("片手剣"), TEXT("單手劍") }, { TEXT("盾と剣"), TEXT("盾與劍") },
			{ TEXT("小太刀"), TEXT("小太刀") }, { TEXT("小太刀二刀"), TEXT("雙小太刀") }, { TEXT("拳銃"), TEXT("手槍") }, { TEXT("二丁拳銃"), TEXT("雙槍") },
			{ TEXT("投擲"), TEXT("投擲") }, { TEXT("魔法杖"), TEXT("魔杖") }, { TEXT("魔法本"), TEXT("魔法書") }, { TEXT("両手剣"), TEXT("雙手劍") },
			{ TEXT("棒・槍"), TEXT("棍與槍") }, { TEXT("槌・鎌"), TEXT("鎚與鐮") }, { TEXT("ライフル"), TEXT("步槍") }, { TEXT("弓矢"), TEXT("弓箭") },
			{ TEXT("ストレッチ"), TEXT("伸展") }, { TEXT("動き回る"), TEXT("走動") }, { TEXT("ダイブ"), TEXT("跳水") },
			// Motions
			{ TEXT("初期ポーズ"), TEXT("初始姿勢") }, { TEXT("立ちポーズ"), TEXT("站姿") }, { TEXT("決めポーズ右"), TEXT("帥氣姿勢 右") }, { TEXT("決めポーズ左"), TEXT("帥氣姿勢 左") },
			{ TEXT("中腰"), TEXT("半蹲") }, { TEXT("座り"), TEXT("坐") }, { TEXT("しゃがみ"), TEXT("蹲下") }, { TEXT("しゃがみ歩き"), TEXT("蹲著走") },
			{ TEXT("正座"), TEXT("跪坐") }, { TEXT("横座り"), TEXT("側坐") }, { TEXT("女の子座り"), TEXT("鴨子坐") }, { TEXT("お姉さん座り"), TEXT("側身坐") },
			{ TEXT("プール座り"), TEXT("池畔坐") }, { TEXT("座り会話 右"), TEXT("坐著對話 右") }, { TEXT("座り会話 左"), TEXT("坐著對話 左") },
			{ TEXT("歩く"), TEXT("走路") }, { TEXT("走る"), TEXT("跑步") }, { TEXT("走り"), TEXT("跑步") }, { TEXT("話す"), TEXT("說話") },
			{ TEXT("待機"), TEXT("待機") }, { TEXT("倒れる"), TEXT("倒下") }, { TEXT("攻撃"), TEXT("攻擊") }, { TEXT("防御"), TEXT("防禦") },
			{ TEXT("喜"), TEXT("喜") }, { TEXT("怒"), TEXT("怒") }, { TEXT("哀"), TEXT("哀") }, { TEXT("驚恥他"), TEXT("驚訝害羞等") },
			{ TEXT("あくび"), TEXT("打哈欠") }, { TEXT("くしゃみ"), TEXT("打噴嚏") }, { TEXT("なるほど"), TEXT("原來如此") }, { TEXT("ごめんごめん"), TEXT("抱歉抱歉") },
			{ TEXT("やすめ"), TEXT("稍息") }, { TEXT("イエッサ"), TEXT("遵命") }, { TEXT("エッヘン"), TEXT("得意") }, { TEXT("チッチッチ"), TEXT("嘖嘖嘖") },
			{ TEXT("ジタバタ"), TEXT("手腳亂動") }, { TEXT("パタパタ"), TEXT("搧風") }, { TEXT("フィーバー"), TEXT("狂熱") }, { TEXT("シューティング"), TEXT("射擊") },
			{ TEXT("スイング"), TEXT("揮棒") }, { TEXT("スクワット"), TEXT("深蹲") }, { TEXT("ヨガ"), TEXT("瑜伽") }, { TEXT("シャドーボクシング"), TEXT("空拳") },
			{ TEXT("ポールダンス"), TEXT("鋼管舞") }, { TEXT("モンキーダンス"), TEXT("猴子舞") }, { TEXT("ダンス練習"), TEXT("練舞") }, { TEXT("ダンス練習待機"), TEXT("練舞待機") },
			{ TEXT("チアダンス練習"), TEXT("啦啦隊練習") }, { TEXT("チアダンス待機"), TEXT("啦啦隊待機") }, { TEXT("ゾンビ"), TEXT("殭屍") }, { TEXT("ゾンビ攻撃"), TEXT("殭屍攻擊") },
			{ TEXT("ゾンビ這いつくばり"), TEXT("殭屍爬行") }, { TEXT("荒ぶる鷹のポーズ"), TEXT("展翅老鷹姿勢") }, { TEXT("高笑い"), TEXT("大笑") }, { TEXT("駄々っ子"), TEXT("耍賴") },
			{ TEXT("頭を抱える"), TEXT("抱頭") }, { TEXT("腹減った"), TEXT("肚子餓") }, { TEXT("暑がる"), TEXT("怕熱") }, { TEXT("恥ずかしがる"), TEXT("害羞") },
			{ TEXT("悩みつつ休憩"), TEXT("煩惱休息") }, { TEXT("顔遠ざけて悩む"), TEXT("別過臉煩惱") }, { TEXT("謝罪"), TEXT("道歉") }, { TEXT("応援"), TEXT("加油") },
			{ TEXT("手を振る"), TEXT("揮手") }, { TEXT("伸び"), TEXT("伸懶腰") }, { TEXT("呼び出し"), TEXT("叫人") }, { TEXT("待ち合わせ"), TEXT("等人") },
			{ TEXT("参拝"), TEXT("參拜") }, { TEXT("着替え"), TEXT("換衣服") }, { TEXT("服を選ぶ"), TEXT("挑衣服") }, { TEXT("髪を直す"), TEXT("整理頭髮") },
			{ TEXT("容姿を確認する"), TEXT("確認儀容") }, { TEXT("容姿を確認する待機"), TEXT("確認儀容待機") }, { TEXT("リップクリームを塗る"), TEXT("擦護唇膏") }, { TEXT("リップクリームを塗る待機"), TEXT("擦護唇膏待機") },
			{ TEXT("自撮り"), TEXT("自拍") }, { TEXT("自撮り待機"), TEXT("自拍待機") }, { TEXT("ツーショット"), TEXT("雙人合照") }, { TEXT("スマホを眺める"), TEXT("看手機") },
			{ TEXT("フリック操作"), TEXT("滑手機") }, { TEXT("ゲームをする"), TEXT("打電動") }, { TEXT("音楽を聴く"), TEXT("聽音樂") }, { TEXT("本を読む"), TEXT("看書") },
			{ TEXT("本を読む待機"), TEXT("看書待機") }, { TEXT("本を見る"), TEXT("翻書") }, { TEXT("本を探す"), TEXT("找書") }, { TEXT("勉強をする"), TEXT("讀書") },
			{ TEXT("勉強をする待機"), TEXT("讀書待機") }, { TEXT("ノートにメモ"), TEXT("記筆記") }, { TEXT("絵を描く"), TEXT("畫畫") }, { TEXT("絵を描く待機"), TEXT("畫畫待機") },
			{ TEXT("筆で色乗せる"), TEXT("上色") }, { TEXT("筆で色乗せる 確認"), TEXT("上色確認") }, { TEXT("粘土形整えてる"), TEXT("捏黏土") }, { TEXT("掃く"), TEXT("掃地") },
			{ TEXT("箒持ち待機"), TEXT("拿掃把待機") }, { TEXT("箒持ち待機さぼり"), TEXT("拿掃把偷懶") }, { TEXT("机を拭く"), TEXT("擦桌子") }, { TEXT("窓を拭く"), TEXT("擦窗戶") },
			{ TEXT("水やり"), TEXT("澆水") }, { TEXT("ポスターを貼る"), TEXT("貼海報") }, { TEXT("チラシを配る"), TEXT("發傳單") }, { TEXT("引き出しを漁る"), TEXT("翻抽屜") },
			{ TEXT("棚を漁る"), TEXT("翻櫃子") }, { TEXT("物色"), TEXT("東翻西找") }, { TEXT("自販機"), TEXT("自動販賣機") }, { TEXT("外を眺める"), TEXT("看窗外") },
			{ TEXT("空を見る"), TEXT("看天空") }, { TEXT("滝を見てる"), TEXT("看瀑布") }, { TEXT("滝を見上げる"), TEXT("仰望瀑布") }, { TEXT("鳥の巣観察"), TEXT("觀察鳥巢") },
			{ TEXT("釣り"), TEXT("釣魚") }, { TEXT("水切り"), TEXT("打水漂") }, { TEXT("砂いじり"), TEXT("玩沙") }, { TEXT("丸太とび"), TEXT("跳圓木") },
			{ TEXT("平均台"), TEXT("平衡木") }, { TEXT("温泉につかる"), TEXT("泡溫泉") }, { TEXT("浮き輪で浮かぶ"), TEXT("坐泳圈") }, { TEXT("シャチの浮き輪に乗る"), TEXT("騎虎鯨泳圈") },
			{ TEXT("サーフボードでぷかぷか"), TEXT("趴衝浪板漂浮") }, { TEXT("クロールで泳ぐ"), TEXT("自由式") }, { TEXT("ビーチボール"), TEXT("沙灘球") }, { TEXT("ビーチチェアで寝る"), TEXT("躺沙灘椅") },
			{ TEXT("ビーチチェアで飲み物を飲む"), TEXT("沙灘椅喝飲料") }, { TEXT("ビーチチェアで飲み物を飲む待機"), TEXT("沙灘椅喝飲料待機") }, { TEXT("エアーマットで寝ころぶ"), TEXT("躺充氣墊") }, { TEXT("団扇で涼む"), TEXT("搧扇子") },
			{ TEXT("スイカ割り 探す人"), TEXT("打西瓜 找的人") }, { TEXT("スイカ割り 誘導"), TEXT("打西瓜 指路") }, { TEXT("テニス 素振り"), TEXT("網球 揮拍") }, { TEXT("テニス ラケット持ち待機"), TEXT("網球 拿拍待機") },
			{ TEXT("バスケ ボール持ち待機"), TEXT("籃球 拿球待機") }, { TEXT("バスケ 汗を拭く"), TEXT("籃球 擦汗") }, { TEXT("卓球 素振り"), TEXT("桌球 揮拍") }, { TEXT("卓球 玉突き"), TEXT("桌球 顛球") },
			{ TEXT("体洗う"), TEXT("洗身體") }, { TEXT("頭洗う"), TEXT("洗頭") }, { TEXT("食事"), TEXT("用餐") }, { TEXT("飲む"), TEXT("喝") },
			{ TEXT("飲む待機"), TEXT("喝待機") }, { TEXT("お茶を飲む"), TEXT("喝茶") }, { TEXT("お茶を飲む待機"), TEXT("喝茶待機") }, { TEXT("お茶をたてる"), TEXT("點茶") },
			{ TEXT("お茶をたてる待機"), TEXT("點茶待機") }, { TEXT("串焼きを作る"), TEXT("烤串") }, { TEXT("串焼きを食べる"), TEXT("吃烤串") }, { TEXT("三線を弾く"), TEXT("彈三線") },
			{ TEXT("三線の音を合わせる"), TEXT("調三線") }, { TEXT("三線持ち待機"), TEXT("拿三線待機") }, { TEXT("ウクレレ"), TEXT("烏克麗麗") }, { TEXT("貝殻の音を聴く"), TEXT("聽貝殼") },
			{ TEXT("貝殻の音を聴く 姿勢を変える"), TEXT("聽貝殼 換姿勢") }, { TEXT("貝殻の音を聴く 貝殻をみる"), TEXT("聽貝殼 看貝殼") }, { TEXT("空を見る 姿勢を変える"), TEXT("看天空 換姿勢") }, { TEXT("姿勢を変える"), TEXT("換姿勢") },
			{ TEXT("足を組み換える"), TEXT("換腳翹腳") }, { TEXT("足を組み待機"), TEXT("翹腳待機") }, { TEXT("机で寝る"), TEXT("趴桌睡") }, { TEXT("机に座る"), TEXT("坐桌上") },
			{ TEXT("机によりかかる"), TEXT("靠桌子") }, { TEXT("椅子で寝る"), TEXT("靠椅子睡") }, { TEXT("ベンチで寝る"), TEXT("躺長椅") }, { TEXT("うつぶせで寝る"), TEXT("趴睡") },
			{ TEXT("ソファーでまったり"), TEXT("沙發放鬆") }, { TEXT("寝たふり"), TEXT("裝睡") }, { TEXT("寝返り"), TEXT("翻身") }, { TEXT("寝返り待機"), TEXT("翻身待機") },
			{ TEXT("壁チラ右"), TEXT("牆邊偷看 右") }, { TEXT("壁チラ左"), TEXT("牆邊偷看 左") }, { TEXT("壁押し"), TEXT("推牆") }, { TEXT("壁立ち"), TEXT("靠牆站") },
			{ TEXT("捕まえる"), TEXT("抓住") }, { TEXT("腹パン"), TEXT("打肚子") }, { TEXT("隠す"), TEXT("遮掩") }, { TEXT("隠すループ"), TEXT("遮掩循環") },
			{ TEXT("オタ芸"), TEXT("應援舞") }, { TEXT("ペンライトを振る"), TEXT("揮螢光棒") }, { TEXT("水を掛ける"), TEXT("潑水") }, { TEXT("水を掛けられる"), TEXT("被潑水") },
			{ TEXT("準備体操"), TEXT("暖身操") }, { TEXT("もつ"), TEXT("拿著") }, { TEXT("アニメ"), TEXT("動畫") },
		};
		return Names;
	}

	bool IsSuffixChar(TCHAR C)
	{
		return (C >= TEXT('0') && C <= TEXT('9')) || (C >= 0xFF10 && C <= 0xFF19) || C == TEXT(' ') || C == TEXT('A') || C == TEXT('B') || C == 0xFF21 || C == 0xFF22;
	}
}

FString FOKStudioCatalog::ZhName(const FString& Name)
{
	if (const FString* Whole = Table().Find(Name)) return *Whole;
	// 女／男 before a name are the same words here.
	const bool bSex = Name.Len() > 2 && (Name[0] == TEXT('女') || Name[0] == TEXT('男')) && Name[1] == TEXT(' ');
	const FString Body = bSex ? Name.Mid(2) : Name;
	// A number or a letter after the name: 立ち３ is 站立 3.
	int32 End = Body.Len();
	while (End > 0 && IsSuffixChar(Body[End - 1])) --End;
	const FString* Word = Table().Find(Body.Left(End));
	if (!Word) return Name;
	FString Suffix = Body.Mid(End).TrimStartAndEnd();
	for (TCHAR& C : Suffix.GetCharArray())
		if (C >= 0xFF10 && C <= 0xFF19) C = TCHAR(TEXT('0') + (C - 0xFF10));
		else if (C == 0xFF21 || C == 0xFF22) C = TCHAR(TEXT('A') + (C - 0xFF21));
	return (bSex ? Name.Left(2) : FString()) + *Word + (Suffix.IsEmpty() ? FString() : TEXT(" ") + Suffix);
}
