export const supportedLocales = ["ko", "en", "ja", "zh-Hant"] as const;
export type Locale = (typeof supportedLocales)[number];

export function localePathSegment(locale: Locale) {
  return locale === "zh-Hant" ? "zh-hant" : locale;
}

export function localeRoot(locale: Locale, base = import.meta.env.BASE_URL) {
  return `${base}${localePathSegment(locale)}/`;
}

export function localizeCanonicalPath(path: string, locale: Locale) {
  return path.replace(/^(ko|en|ja|zh-hant)\//, `${localePathSegment(locale)}/`);
}

const ui = {
  ko: {
    meta: {
      title: "SIDEY — 화면 가장자리의 친구들",
      description: "가까운 친구의 상태와 짧은 메시지를 작은 픽셀 동물로 보여주는 데스크톱 메신저 SIDEY.",
      ogTitle: "SIDEY — 친구가 화면 한쪽에 총총.",
      ogDescription: "가까운 친구의 지금과 짧은 메시지를 작은 픽셀 동물로 만나는 데스크톱 메신저.",
      ogAlt: "화면 가장자리에 다섯 픽셀 동물이 나란히 있는 SIDEY 소셜 카드",
    },
    skip: "본문으로 건너뛰기",
    navigation: {
      navigation: "주요 메뉴", home: "SIDEY 홈", openMenu: "메뉴 열기", closeMenu: "메뉴 닫기", features: "기능", download: "다운로드",
      faq: "자주 묻는 질문", whatsNew: "새로운 기능", store: "상점", support: "지원", characters: "캐릭터", throwables: "투척물", bubbles: "말풍선",
      useLightTheme: "라이트 모드로 전환", useDarkTheme: "다크 모드로 전환",
    },
    hero: {
      title: "화면에 친구가 총총.",
      description: "친구들이 조그만 픽셀 캐릭터가 되어 화면 가장자리를 돌아다녀요. 일하다 슬쩍 보고, 생각나면 짧게 한마디 건네 보세요.",
      downloadsLabel: "다운로드 선택", appStoreDownload: "App Store 다운로드", macDownload: "macOS 다운로드", windowsDownload: "Windows 다운로드",
      choosePlatform: "운영체제 선택", platformMenu: "운영체제 직접 선택", menuToggle: "다른 운영체제 선택",
      windowsStatus: "Windows 10 1809(build 17763) 이상 · x64", browserTitle: "오늘 할 일 | 메모", browserNote: "오늘 할 일",
      message: "저녁 7시에 볼까?", typingLabel: "토리 입력 중",
      names: { kong: "콩이 · 나", bori: "보리", mongsil: "몽실", tori: "토리" },
      caption: "모니터 속 브라우저 아래에서 걷거나 졸고 잠든 픽셀 동물 친구들과 짧은 말풍선이 보이는 SIDEY 장면",
    },
    motion: {
      title: "가만히 있기는 심심하잖아요.", description: "온라인이면 걷고, 자리를 비우면 졸고, 오프라인이면 잠들어요. 심심하면 작은 장난도 칠 수 있고요.", label: "SIDEY 캐릭터 상태와 동작 예시",
      presence: { eyebrow: "평소 모습", title: "걷고, 졸고, 잠들고.", description: "온라인, 자리 비움, 오프라인. 친구의 상태에 따라 캐릭터 모습도 달라져요.", online: "온라인", away: "자리 비움", offline: "오프라인" },
      throw: { eyebrow: "친구와 놀기", title: "말 대신 말랑공 하나.", description: "빙수가 말랑공을 던지면 토리한테 툭 닿아요.", source: "빙수", target: "토리" },
      pulse: { eyebrow: "크게 인사", title: "가끔은 크게 인사해요.", description: "몽실이를 더블클릭하면 화면 한쪽에서 쑥 커져요.", name: "몽실" },
      names: { kong: "콩이", bori: "보리", cloud: "구름" },
    },
    showcase: {
      title: "일할 때도, 화면 한쪽에.",
      introduction: "SIDEY는 작업 중에도 화면 가장자리에 있어요. 친구가 뭐 하고 있나 슬쩍 보고, 생각나면 한마디 건네면 돼요.",
      label: "SIDEY가 화면에 머무는 방식", caption: "macOS에서 SIDEY가 보이는 화면 예시",
      alt: "메모 창을 띄운 macOS 바탕화면 아래쪽에 SIDEY 픽셀 친구들이 함께 있는 모습",
      steps: [
        ["01", "하던 일은 그대로", "SIDEY가 떠 있어도 뒤에 있는 앱을 평소처럼 클릭하고 쓸 수 있어요."],
        ["02", "친구의 지금을 슬쩍", "걷고, 졸고, 잠드는 모습만 봐도 친구가 지금 접속해 있는지 알 수 있어요."],
        ["03", "생각나면 한마디", "SIDEY를 열어 짧은 메시지를 보내거나 작은 장난을 주고받을 수 있어요."],
      ],
    },
    download: {
      title: "내 컴퓨터에도 SIDEY를.", description: "macOS와 Windows에서 쓸 수 있어요. 내 컴퓨터에 맞는 버전을 골라 설치하면 돼요.",
      macButton: "Mac App Store", windowsButton: "Windows 다운로드", releaseNotes: "릴리스 정보",
      macSystem: "macOS 26 이상 · Apple Silicon(arm64)", windowsSystem: "Windows 10 1809(build 17763) 이상 · x64",
      copyFailure: "복사하지 못했습니다. 해시를 직접 선택해 주세요.",
      hashCopy: "SHA-256 해시 복사", hashCopied: "SHA-256 해시를 복사했습니다.",
    },
    faq: {
      title: "자주 묻는 질문",
      intro: "처음 쓰기 전에 궁금할 만한 것만 모았어요.",
      items: [
        ["SIDEY는 어떤 앱인가요?", "가까운 친구들이 작은 픽셀 캐릭터가 되어 화면 가장자리에 머무는 초대 전용 데스크톱 메신저예요. 한 그룹에는 최대 12명까지 함께할 수 있어요."],
        ["어떤 컴퓨터에서 사용할 수 있나요?", "Apple Silicon을 탑재한 macOS 26 이상과 x64 기반 Windows 10 1809(build 17763) 이상을 지원해요. Intel Mac은 현재 지원하지 않아요."],
        ["친구는 어떻게 초대하나요?", "비공개 그룹을 만들고 초대 코드를 친구에게 보내면 돼요. 한 그룹에는 최대 12명, 한 사람은 최대 5개 그룹에 참여할 수 있어요."],
        ["SIDEY가 화면이나 키보드 입력을 읽나요?", "아니요. 화면 내용, 사용 중인 앱, 다른 앱에서 누른 키, 마우스 좌표, 파일, 마이크, 카메라는 수집하지 않아요. 입력 중 표시는 SIDEY 입력창에 글을 쓸 때만 전송돼요."],
        ["메시지는 얼마나 보관되나요?", "최근 메시지는 3일 동안 보관하고, 이후에는 영구 삭제해요."],
        ["모든 게임이나 전체 화면 앱 위에도 보이나요?", "항상은 아니에요. 일반적인 작업 화면에서는 보이지만, 보안 화면·DRM 앱·관리자 권한 앱·일부 단독 전체 화면 게임에서는 보이지 않을 수 있어요."],
      ],
    },
    whatsNew: {
      appStoreHistory: "macOS 업데이트 내용은 Mac App Store에서 확인하세요.",
      title: "새로운 기능", intro: "SIDEY의 최신 업데이트를 살펴보세요. 새로워진 기능을 놓치지 않도록 한곳에 모았어요.",
      tabs: { label: "운영체제별 새로운 기능", macos: "macOS", windows: "Windows" },
      viewRelease: "GitHub Release에서 전체 내용 보기", koreanOriginalNotice: "전체 릴리스 노트는 한국어 원문으로 제공됩니다.", viewKoreanOriginal: "한국어 원문 보기", openDetails: "변경 내용 펼치기", closeDetails: "변경 내용 접기", loadedMore: "지난 업데이트를 더 불러왔습니다.",
    },
  },
  en: {
    meta: {
      title: "SIDEY — Your friends at the edge of your screen",
      description: "SIDEY is a desktop messenger that shows your closest friends' presence and short messages as tiny pixel animals at the edge of your screen.",
      ogTitle: "SIDEY — Tiny friends at the edge of your screen.",
      ogDescription: "See your closest friends' presence and short messages as tiny pixel animals.",
      ogAlt: "SIDEY social card with five pixel animals lined up along the edge of a screen",
    },
    skip: "Skip to content",
    navigation: {
      navigation: "Main navigation", home: "SIDEY home", openMenu: "Open menu", closeMenu: "Close menu", features: "Features", download: "Download",
      faq: "FAQ", whatsNew: "What's New", store: "Store", support: "Support", characters: "Characters", throwables: "Throwables", bubbles: "Bubbles",
      useLightTheme: "Switch to light mode", useDarkTheme: "Switch to dark mode",
    },
    hero: {
      title: "Friends at the edge of your screen.",
      description: "Your friends become tiny pixel characters wandering along the edge of your screen. Glance over while you work, and send a quick note when they cross your mind.",
      downloadsLabel: "Download options", appStoreDownload: "Download on App Store", macDownload: "Download for macOS", windowsDownload: "Download for Windows",
      choosePlatform: "Choose your platform", platformMenu: "Choose a platform manually", menuToggle: "Choose another platform",
      windowsStatus: "Windows 10 1809 (build 17763) or later · x64", browserTitle: "Today’s tasks | Notes", browserNote: "Today's list",
      message: "Meet at seven?", typingLabel: "Rosie is typing",
      names: { kong: "Mochi · ME", bori: "Milo", mongsil: "Luna", tori: "Rosie" },
      caption: "A SIDEY scene with pixel animal friends walking, dozing, and sleeping along the bottom of a browser inside a monitor",
    },
    motion: {
      title: "Standing still would be boring.", description: "Friends walk when they're online, doze when they're away, and sleep when they're offline. You can mess with each other a little, too.", label: "SIDEY character states and actions",
      presence: { eyebrow: "Everyday presence", title: "Walking, dozing, sleeping.", description: "Online, away, or offline—their character changes with their presence.", online: "Online", away: "Away", offline: "Offline" },
      throw: { eyebrow: "Play with a friend", title: "Sometimes a soft ball says it best.", description: "Coco tosses a soft ball and it lands with a little bonk on Rosie.", source: "Coco", target: "Rosie" },
      pulse: { eyebrow: "Big hello", title: "Sometimes hello needs to be bigger.", description: "Double-click Charlie and they suddenly pop up bigger at the edge of your screen.", name: "Charlie" },
      names: { kong: "Mochi", bori: "Milo", cloud: "Luna" },
    },
    showcase: {
      title: "There while you work.",
      introduction: "SIDEY stays at the edge of your screen while you work. Glance over to see what your friends are up to, and say something when they cross your mind.",
      label: "How SIDEY fits into your screen", caption: "SIDEY alongside a macOS workspace",
      alt: "A macOS desktop with a Notes window and SIDEY pixel friends along the bottom edge of the screen",
      steps: [
        ["01", "Keep doing what you're doing", "You can keep clicking and using the app behind SIDEY like you normally would."],
        ["02", "See what they're up to", "Walking, dozing, and sleeping show whether your friends are around."],
        ["03", "Say something when you want", "Open SIDEY to send a short message or trade a small bit of mischief."],
      ],
    },
    download: {
      title: "Bring SIDEY to your desktop.", description: "SIDEY is available for macOS and Windows. Pick the version that matches your computer and install it.",
      macButton: "Mac App Store", windowsButton: "Download for Windows", releaseNotes: "Release notes",
      macSystem: "macOS 26 or later · Apple Silicon (arm64)", windowsSystem: "Windows 10 1809 (build 17763) or later · x64",
      copyFailure: "Could not copy. Please select the hash manually.",
      hashCopy: "Copy SHA-256 hash", hashCopied: "SHA-256 hash copied.",
    },
    faq: {
      title: "Questions you might have.",
      intro: "A few things worth knowing before you start.",
      items: [
        ["What is SIDEY?", "SIDEY is an invite-only desktop messenger where your closest friends hang out along the edge of your screen as tiny pixel characters. Each private group can have up to 12 people."],
        ["Which computers are supported?", "SIDEY runs on Apple silicon Macs with macOS 26 or later, and x64 PCs with Windows 10 1809 (build 17763) or later. Intel Macs are not currently supported."],
        ["How do I invite friends?", "Create a private group and send the invite code directly to your friends. A group can have up to 12 members, and each person can join up to five groups."],
        ["Does SIDEY watch what I do on my computer?", "No. SIDEY does not collect your screen, open apps, keystrokes from other apps, pointer location, files, microphone, or camera. Typing status is only sent while you type in SIDEY's own message box."],
        ["How long are messages kept?", "Recent messages are kept for three days, then permanently deleted."],
        ["Will SIDEY show over every game and fullscreen app?", "Not always. SIDEY stays visible during normal desktop use, but it may not appear over secure screens, DRM-protected apps, elevated apps, or some exclusive-fullscreen games."],
      ],
    },
    whatsNew: {
      appStoreHistory: "View macOS version history on the Mac App Store.",
      title: "What's New", intro: "See the latest changes to SIDEY, grouped by macOS and Windows.",
      tabs: { label: "What's new by operating system", macos: "macOS", windows: "Windows" },
      viewRelease: "View the full GitHub Release", koreanOriginalNotice: "Full release notes are currently available in the original Korean.", viewKoreanOriginal: "View the Korean original", openDetails: "Show changes", closeDetails: "Hide changes", loadedMore: "More previous updates loaded.",
    },
  },
  ja: {
    meta: {
      title: "SIDEY — 画面の端にいる友だち",
      description: "仲のいい友だちの様子や短いメッセージを、小さなピクセルキャラクターで届けるデスクトップメッセンジャー、SIDEY。",
      ogTitle: "SIDEY — 画面の端を歩く、小さな友だち。",
      ogDescription: "仲のいい友だちの今と短いメッセージを、小さなピクセルキャラクターで感じられます。",
      ogAlt: "5匹のピクセルキャラクターが画面の端に並ぶSIDEYのソーシャルカード",
    },
    skip: "本文へスキップ",
    navigation: {
      navigation: "メインメニュー", home: "SIDEY ホーム", openMenu: "メニューを開く", closeMenu: "メニューを閉じる", features: "機能", download: "ダウンロード",
      faq: "よくある質問", whatsNew: "新機能", store: "ストア", support: "サポート", characters: "キャラクター", throwables: "投げアイテム", bubbles: "吹き出し",
      useLightTheme: "ライトモードに切り替える", useDarkTheme: "ダークモードに切り替える",
    },
    hero: {
      title: "画面の端を、友だちがトコトコ。",
      titleParts: ["画面の端を、", "友だちが", "トコトコ。"],
      description: "友だちが小さなピクセルキャラクターになって、画面の端を歩き回ります。作業の合間にちらっと眺めたり、思い立ったときに短いひと言を送ったり。",
      downloadsLabel: "ダウンロードを選択", appStoreDownload: "App Storeでダウンロード", macDownload: "macOS版をダウンロード", windowsDownload: "Windows版をダウンロード",
      choosePlatform: "OSを選択", platformMenu: "OSを選択してください", menuToggle: "別のOSを選ぶ",
      windowsStatus: "Windows 10 1809（ビルド17763）以降 · x64", browserTitle: "今日やること | メモ", browserNote: "今日やること",
      message: "7時に会う？", typingLabel: "おもちが入力中",
      names: { kong: "むぎ・私", bori: "モカ", mongsil: "きなこ", tori: "おもち" },
      caption: "モニター内のブラウザ下部で、歩いたり、うとうとしたり、眠ったりするピクセルの友だちと短い吹き出しが見えるSIDEYの画面",
    },
    motion: {
      title: "じっとしているだけじゃ、つまらない。", titleParts: ["じっとしている", "だけじゃ、", "つまらない。"], description: "オンラインなら歩き、離席中はうとうとし、オフラインになると眠ります。ちょっとしたいたずらもできます。", label: "SIDEYのキャラクター状態とアクション",
      presence: { eyebrow: "いつもの様子", title: "歩いて、うとうとして、眠る。", titleParts: ["歩いて、", "うとうとして、", "眠る。"], description: "オンライン、離席中、オフライン。友だちの状態に合わせてキャラクターの様子も変わります。", online: "オンライン", away: "離席中", offline: "オフライン" },
      throw: { eyebrow: "友だちと遊ぶ", title: "言葉の代わりに、やわらかボール。", titleParts: ["言葉の代わりに、", "やわらかボール。"], description: "ラテが投げたやわらかボールが、おもちにこつんと当たります。", source: "ラテ", target: "おもち" },
      pulse: { eyebrow: "大きくあいさつ", title: "たまには、大きなあいさつを。", titleParts: ["たまには、", "大きなあいさつを。"], description: "くるみをダブルクリックすると、画面の端でぐんと大きくなります。", name: "くるみ" },
      names: { kong: "むぎ", bori: "モカ", cloud: "きなこ" },
    },
    showcase: {
      title: "仕事中も、画面の片隅に。",
      introduction: "SIDEYは作業中も画面の端にいます。友だちが今何をしているかちらっと眺めて、話したくなったらひと言送るだけ。",
      label: "SIDEYが画面にいる様子", caption: "macOSでSIDEYを使っている画面例",
      alt: "メモを開いたmacOSのデスクトップ下部にSIDEYのピクセルキャラクターが並ぶ様子",
      steps: [
        ["01", "作業はそのまま", "SIDEYが表示されていても、背後のアプリをいつもどおりクリックして使えます。"],
        ["02", "友だちの今をちらっと", "歩く、うとうとする、眠る姿を見るだけで、友だちが今いるかどうか分かります。"],
        ["03", "話したいときにひと言", "SIDEYを開いて短いメッセージを送ったり、小さないたずらを送り合ったりできます。"],
      ],
    },
    download: {
      title: "あなたのデスクトップにもSIDEYを。", description: "macOSとWindowsに対応しています。お使いのパソコンに合うバージョンを選んでインストールしてください。",
      titleParts: ["あなたの", "デスクトップにも", "SIDEYを。"],
      macButton: "Mac App Store", windowsButton: "Windows版をダウンロード", releaseNotes: "リリースノート",
      macSystem: "macOS 26以降 · Appleシリコン（arm64）", windowsSystem: "Windows 10 1809（ビルド17763）以降 · x64",
      copyFailure: "コピーできませんでした。ハッシュを選択してコピーしてください。",
      hashCopy: "SHA-256ハッシュをコピー", hashCopied: "SHA-256ハッシュをコピーしました。",
    },
    faq: {
      title: "よくある質問",
      intro: "使い始める前に知っておきたいことをまとめました。",
      items: [
        ["SIDEYとは？", "仲のいい友だちが小さなピクセルキャラクターになって画面の端にいる、招待制のデスクトップメッセンジャーです。1つのグループには最大12人まで参加できます。"],
        ["どのパソコンで使えますか？", "Appleシリコン搭載のmacOS 26以降と、x64版Windows 10 1809（ビルド17763）以降に対応しています。Intel Macには現在対応していません。"],
        ["友だちを招待するには？", "非公開グループを作り、招待コードを友だちに直接送ります。1グループは最大12人、1人につき最大5グループまで参加できます。"],
        ["SIDEYは画面やキーボード入力を読み取りますか？", "いいえ。画面の内容、使用中のアプリ、ほかのアプリでのキー入力、ポインターの位置、ファイル、マイク、カメラは収集しません。入力中の表示は、SIDEYのメッセージ欄に入力している間だけ送信されます。"],
        ["メッセージはいつまで保存されますか？", "直近のメッセージは3日間保存され、その後完全に削除されます。"],
        ["すべてのゲームやフルスクリーンアプリの上に表示されますか？", "必ずしも表示されるわけではありません。通常のデスクトップでは表示されますが、セキュリティ画面、DRM保護されたアプリ、管理者権限で動くアプリ、一部の排他的フルスクリーンゲームでは表示されない場合があります。"],
      ],
    },
    whatsNew: {
      appStoreHistory: "macOSの更新内容はMac App Storeで確認できます。",
      title: "新機能", intro: "SIDEYの最新アップデートをチェック。新しくなった機能を見逃さないよう、ひとつにまとめました。",
      tabs: { label: "OS別の新機能", macos: "macOS", windows: "Windows" },
      viewRelease: "GitHub Releaseですべて見る", koreanOriginalNotice: "リリースノート全文は現在、韓国語の原文で提供しています。", viewKoreanOriginal: "韓国語の原文を見る", openDetails: "変更内容を表示", closeDetails: "変更内容を閉じる", loadedMore: "過去のアップデートをさらに読み込みました。",
    },
  },
  "zh-Hant": {
    meta: {
      title: "SIDEY — 待在螢幕邊緣的朋友",
      description: "SIDEY 是桌面通訊軟體，讓親近好友化身為螢幕邊緣的小小像素動物，顯示上線狀態與簡短訊息。",
      ogTitle: "SIDEY — 小小好友，就在螢幕邊緣。",
      ogDescription: "透過小小像素動物，看看親近好友的近況與簡短訊息。",
      ogAlt: "五隻像素動物排列在螢幕邊緣的 SIDEY 社群分享圖片",
    },
    skip: "跳到主要內容",
    navigation: {
      navigation: "主要導覽", home: "SIDEY 首頁", openMenu: "開啟選單", closeMenu: "關閉選單", features: "功能", download: "下載",
      faq: "常見問題", whatsNew: "新功能", store: "商店", support: "支援", characters: "角色", throwables: "投擲道具", bubbles: "對話框",
      useLightTheme: "切換至淺色模式", useDarkTheme: "切換至深色模式",
    },
    hero: {
      title: "朋友就在螢幕邊緣走走停停。",
      description: "好友會化身成小小像素角色，在螢幕邊緣散步。工作時瞄一眼近況，想起對方時就傳一句簡短訊息。",
      downloadsLabel: "下載選項", appStoreDownload: "從 App Store 下載", macDownload: "下載 macOS 版", windowsDownload: "下載 Windows 版",
      choosePlatform: "選擇作業系統", platformMenu: "手動選擇作業系統", menuToggle: "選擇其他作業系統",
      windowsStatus: "Windows 10 1809（組建 17763）或更新版本 · x64", browserTitle: "今天要做的事｜備忘錄", browserNote: "今天要做的事",
      message: "晚上七點見？", typingLabel: "麻糬正在輸入",
      names: { kong: "麥麥 · 我", bori: "摩卡", mongsil: "栗子", tori: "麻糬" },
      caption: "SIDEY 畫面中，像素動物朋友在瀏覽器視窗下方散步、打瞌睡或睡覺，旁邊顯示簡短對話框",
    },
    motion: {
      title: "一直站著也太無聊了。", description: "好友上線時會散步，離開時會打瞌睡，離線後就睡覺。偶爾也能互相開個小玩笑。", label: "SIDEY 角色狀態與動作示例",
      presence: { eyebrow: "平常的模樣", title: "散步、打瞌睡、睡覺。", description: "線上、離開或離線，角色會隨好友的狀態改變模樣。", online: "線上", away: "離開", offline: "離線" },
      throw: { eyebrow: "和朋友玩", title: "有時候，一顆軟球就夠了。", description: "拿鐵丟出軟球，輕輕碰到麻糬。", source: "拿鐵", target: "麻糬" },
      pulse: { eyebrow: "大聲打招呼", title: "偶爾也要好好打聲招呼。", description: "按兩下栗子，牠就會在螢幕邊緣突然變大。", name: "栗子" },
      names: { kong: "麥麥", bori: "摩卡", cloud: "栗子" },
    },
    showcase: {
      title: "工作時，也陪在螢幕一角。",
      introduction: "工作時，SIDEY 會留在螢幕邊緣。瞄一眼就知道好友在不在，想聊時再傳一句話。",
      label: "SIDEY 在螢幕上的呈現方式", caption: "在 macOS 工作畫面中使用 SIDEY 的示例",
      alt: "開著備忘錄視窗的 macOS 桌面，SIDEY 像素好友排列在螢幕底部",
      steps: [
        ["01", "照常做手邊的事", "即使 SIDEY 顯示在畫面上，也能照常點按並使用後方的 App。"],
        ["02", "瞄一眼好友近況", "看看角色在散步、打瞌睡還是睡覺，就知道好友現在是否上線。"],
        ["03", "想聊時說一句", "開啟 SIDEY 傳送簡短訊息，也能互相丟個小道具。"],
      ],
    },
    download: {
      title: "把 SIDEY 帶到你的桌面。", description: "SIDEY 支援 macOS 與 Windows。選擇適合你電腦的版本並安裝即可。",
      macButton: "Mac App Store", windowsButton: "下載 Windows 版", releaseNotes: "版本資訊",
      macSystem: "macOS 26 或更新版本 · Apple 晶片（arm64）", windowsSystem: "Windows 10 1809（組建 17763）或更新版本 · x64",
      copyFailure: "無法複製，請手動選取雜湊值。",
      hashCopy: "複製 SHA-256 雜湊值", hashCopied: "已複製 SHA-256 雜湊值。",
    },
    faq: {
      title: "常見問題",
      intro: "開始使用前，先看看這些常見問題。",
      items: [
        ["SIDEY 是什麼？", "SIDEY 是邀請制桌面通訊軟體，讓親近好友化身為螢幕邊緣的小小像素角色。每個私人群組最多可有 12 人。"],
        ["支援哪些電腦？", "SIDEY 支援配備 Apple 晶片、執行 macOS 26 或更新版本的 Mac，以及執行 Windows 10 1809（組建 17763）或更新版本的 x64 電腦。目前不支援 Intel Mac。"],
        ["如何邀請朋友？", "建立私人群組後，直接把邀請碼傳給朋友。每個群組最多 12 人，每人最多可加入 5 個群組。"],
        ["SIDEY 會讀取螢幕或鍵盤輸入嗎？", "不會。SIDEY 不會收集螢幕內容、使用中的 App、在其他 App 按下的按鍵、游標座標、檔案、麥克風或相機資料。只有在 SIDEY 的訊息輸入框打字時，才會傳送輸入中狀態。"],
        ["訊息會保留多久？", "近期訊息會保留 3 天，之後永久刪除。"],
        ["所有遊戲或全螢幕 App 上都會顯示嗎？", "不一定。SIDEY 可在一般桌面環境中顯示，但可能無法顯示在安全性畫面、受 DRM 保護的 App、具較高權限的 App，或部分獨佔全螢幕遊戲上。"],
      ],
    },
    whatsNew: {
      appStoreHistory: "前往 Mac App Store 查看 macOS 版本記錄。",
      title: "新功能", intro: "查看 SIDEY 在 macOS 與 Windows 上的最新更新。",
      tabs: { label: "依作業系統查看新功能", macos: "macOS", windows: "Windows" },
      viewRelease: "在 GitHub Release 查看完整內容", koreanOriginalNotice: "完整版本資訊目前僅提供韓文原文。", viewKoreanOriginal: "查看韓文原文", openDetails: "顯示變更內容", closeDetails: "收合變更內容", loadedMore: "已載入更多舊版更新。",
    },
  },
} as const;

export function isLocale(value: string | undefined): value is Locale {
  return supportedLocales.includes(value as Locale);
}

export function getTranslations(locale: Locale) {
  return ui[locale];
}

export const getLandingCopy = getTranslations;
