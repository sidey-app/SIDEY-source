import { commerceProducts } from "../../public/assets/commerce-products.js";
import commerceCatalog from "../../../assets/v1/commerce-catalog.json";
import commerceEn from "../../../assets/v1/locale/commerce/en.json";
import commerceJa from "../../../assets/v1/locale/commerce/ja.json";
import commerceKo from "../../../assets/v1/locale/commerce/ko.json";
import commerceZhHant from "../../../assets/v1/locale/commerce/zh-Hant.json";
import type { Locale } from "../i18n/landing";

export type StoreCategory = "characters" | "throwables" | "bubbles";
export type StoreAssetMode = "character" | "throwable" | "cannon" | "bubble";

export interface StoreProduct {
  id: string;
  name: string;
  description: string;
  price: string;
  commerceID?: string;
  keepsake?: StoreProduct;
  sound?: string;
  isKeepsake?: boolean;
  isTree?: boolean;
  asset?: string;
  mode: StoreAssetMode;
  previewAsset?: string;
  emitterAsset?: string;
  mirrorsMovement?: boolean;
  bubbleTheme?: "default" | "bunny-pink" | "butter-chick" | "starry-cat";
}

export interface StoreCategoryContent {
  eyebrow: string;
  title: string;
  description: string;
  products: StoreProduct[];
}

export type StoreCatalog = Record<StoreCategory, StoreCategoryContent>;

interface CommerceLocalization {
  display_name: string;
  description: string;
}

const commerceLocalizations: Record<Locale, Record<string, CommerceLocalization>> = {
  ko: commerceKo,
  en: commerceEn,
  ja: commerceJa,
  "zh-Hant": commerceZhHant,
};

const ko: StoreCatalog = {
  characters: {
    eyebrow: "캐릭터",
    title: "화면에 데려올 새 친구들.",
    description: "캐릭터를 누르면 실제 SIDEY에서 움직이는 모습을 먼저 볼 수 있어요.",
    products: [
      { id: "pixel_hamster", name: "아기 햄스터", description: "작은 귀와 분홍 볼을 가진 SIDEY의 기본 친구예요.", price: "기본 제공", asset: "assets/characters/pixel_hamster.png", mode: "character" },
      { id: "pixel_cat", name: "아기 고양이", description: "회색 줄무늬와 뾰족한 귀가 귀여운 친구예요.", price: "기본 제공", asset: "assets/characters/pixel_cat.png", mode: "character" },
      { id: "pixel_puppy", name: "복실 강아지", description: "카라멜빛 귀와 복슬복슬한 얼굴을 가진 친구예요.", price: "기본 제공", asset: "assets/characters/pixel_puppy.png", mode: "character" },
      { id: "pixel_rabbit", name: "아기 토끼", description: "긴 귀와 보랏빛 목도리가 잘 어울리는 친구예요.", price: "기본 제공", asset: "assets/characters/pixel_rabbit.png", mode: "character" },
      { id: "pixel_penguin", name: "꼬마 펭귄", description: "남색 몸과 민트색 목도리로 종종 걸어요.", price: "기본 제공", asset: "assets/characters/pixel_penguin.png", mode: "character" },
    ],
  },
  throwables: {
    eyebrow: "던지기 장난감",
    title: "말랑공부터 미니 대포까지.",
    description: "말랑공, 하트, 미니 대포처럼 친구에게 던지며 놀 수 있는 장난감을 먼저 구경해 보세요.",
    products: [
      { id: "patch_soft_ball", name: "패치 말랑공", description: "기본 캐릭터들이 친구에게 가볍게 던지는 말랑공이에요.", price: "기본 제공", asset: "assets/previewer/patch_soft_ball.png", sound: "assets/store/impact-patch_soft_ball.wav", mode: "throwable" },
    ],
  },
  bubbles: {
    eyebrow: "말풍선",
    title: "말풍선도 내 취향대로.",
    description: "메시지와 입력 중 표시의 색과 작은 장식을 바꿀 수 있어요.",
    products: [
      { id: "bubble_default", name: "기본 말풍선", description: "어떤 화면에서도 또렷하게 읽히는 SIDEY의 기본 말풍선이에요.", price: "기본 제공", mode: "bubble", bubbleTheme: "default" },
    ],
  },
};

const en: StoreCatalog = {
  characters: {
    eyebrow: "Characters",
    title: "New friends for your screen.",
    description: "Open a preview to see how each character moves in SIDEY.",
    products: [
      { id: "pixel_hamster", name: "Baby Hamster", description: "SIDEY's original companion, with tiny ears and rosy cheeks.", price: "Included", asset: "assets/characters/pixel_hamster.png", mode: "character" },
      { id: "pixel_cat", name: "Baby Cat", description: "A soft gray tabby with a pair of perfectly pointy ears.", price: "Included", asset: "assets/characters/pixel_cat.png", mode: "character" },
      { id: "pixel_puppy", name: "Fluffy Puppy", description: "A caramel-eared pup with a wonderfully fluffy face.", price: "Included", asset: "assets/characters/pixel_puppy.png", mode: "character" },
      { id: "pixel_rabbit", name: "Baby Rabbit", description: "Long ears and a violet scarf make this little friend easy to spot.", price: "Included", asset: "assets/characters/pixel_rabbit.png", mode: "character" },
      { id: "pixel_penguin", name: "Little Penguin", description: "A navy penguin who waddles along in a mint scarf.", price: "Included", asset: "assets/characters/pixel_penguin.png", mode: "character" },
    ],
  },
  throwables: {
    eyebrow: "Tossable toys",
    title: "From soft balls to mini cannons.",
    description: "Preview toys you can toss at your friends, from soft balls and hearts to mini cannons.",
    products: [
      { id: "patch_soft_ball", name: "Patch Soft Ball", description: "The soft little ball every SIDEY character can toss at a friend.", price: "Included", asset: "assets/previewer/patch_soft_ball.png", sound: "assets/store/impact-patch_soft_ball.wav", mode: "throwable" },
    ],
  },
  bubbles: {
    eyebrow: "Bubbles",
    title: "Make your bubbles your own.",
    description: "Change the colors and small decorations on messages and typing indicators.",
    products: [
      { id: "bubble_default", name: "Classic Bubble", description: "SIDEY's crisp, easy-to-read bubble for every desktop.", price: "Included", mode: "bubble", bubbleTheme: "default" },
    ],
  },
};

const ja: StoreCatalog = {
  characters: {
    eyebrow: "キャラクター",
    title: "画面に迎える、新しい友だち。",
    description: "キャラクターを選ぶと、SIDEYで歩く様子をプレビューできます。",
    products: [
      { id: "pixel_hamster", name: "ベビーハムスター", description: "小さな耳と桃色のほっぺが目印の、SIDEYの定番キャラクターです。", price: "基本付属", asset: "assets/characters/pixel_hamster.png", mode: "character" },
      { id: "pixel_cat", name: "こねこ", description: "やわらかな灰色のしま模様と、ぴんとした耳がかわいいキャラクターです。", price: "基本付属", asset: "assets/characters/pixel_cat.png", mode: "character" },
      { id: "pixel_puppy", name: "ふわふわ子犬", description: "キャラメル色の耳と、ふわふわの顔が愛らしいキャラクターです。", price: "基本付属", asset: "assets/characters/pixel_puppy.png", mode: "character" },
      { id: "pixel_rabbit", name: "こうさぎ", description: "長い耳と紫色のマフラーがよく似合う、小さな友だちです。", price: "基本付属", asset: "assets/characters/pixel_rabbit.png", mode: "character" },
      { id: "pixel_penguin", name: "ちびペンギン", description: "紺色の体にミント色のマフラーを巻いて、ちょこちょこ歩きます。", price: "基本付属", asset: "assets/characters/pixel_penguin.png", mode: "character" },
    ],
  },
  throwables: {
    eyebrow: "投げて遊ぶおもちゃ",
    title: "やわらかボールからミニ大砲まで。",
    description: "ボールやハート、ミニ大砲など、友だちに投げて遊べるおもちゃをプレビューできます。",
    products: [
      { id: "patch_soft_ball", name: "パッチやわらかボール", description: "どの基本キャラクターでも、友だちにぽんと投げられるやわらかなボールです。", price: "基本付属", asset: "assets/previewer/patch_soft_ball.png", sound: "assets/store/impact-patch_soft_ball.wav", mode: "throwable" },
    ],
  },
  bubbles: {
    eyebrow: "吹き出し",
    title: "吹き出しも、自分らしく。",
    description: "メッセージや入力中表示の色と、小さな飾りを変えられます。",
    products: [
      { id: "bubble_default", name: "基本の吹き出し", description: "どんな画面でも読みやすい、SIDEYの標準吹き出しです。", price: "基本付属", mode: "bubble", bubbleTheme: "default" },
    ],
  },
};

const zhHant: StoreCatalog = {
  characters: {
    eyebrow: "角色",
    title: "帶新朋友來到你的螢幕。",
    description: "選擇角色，預覽在 SIDEY 裡走動的模樣。",
    products: [
      { id: "pixel_hamster", name: "小倉鼠", description: "SIDEY 的經典夥伴，有著小耳朵和粉紅臉頰。", price: "隨附", asset: "assets/characters/pixel_hamster.png", mode: "character" },
      { id: "pixel_cat", name: "小貓", description: "柔和的灰色虎斑，加上一對尖尖的小耳朵。", price: "隨附", asset: "assets/characters/pixel_cat.png", mode: "character" },
      { id: "pixel_puppy", name: "蓬鬆小狗", description: "焦糖色耳朵和蓬鬆臉蛋的可愛夥伴。", price: "隨附", asset: "assets/characters/pixel_puppy.png", mode: "character" },
      { id: "pixel_rabbit", name: "小兔子", description: "長耳朵與紫色圍巾，讓這位小朋友格外醒目。", price: "隨附", asset: "assets/characters/pixel_rabbit.png", mode: "character" },
      { id: "pixel_penguin", name: "小企鵝", description: "深藍色的小企鵝，圍著薄荷色圍巾搖搖擺擺地走。", price: "隨附", asset: "assets/characters/pixel_penguin.png", mode: "character" },
    ],
  },
  throwables: {
    eyebrow: "投擲玩具",
    title: "從軟球到迷你大砲。",
    description: "先預覽能丟向朋友一起玩的玩具，例如軟球、愛心和迷你大砲。",
    products: [
      { id: "patch_soft_ball", name: "拼布軟球", description: "所有基本角色都能輕輕丟向好友的小軟球。", price: "隨附", asset: "assets/previewer/patch_soft_ball.png", sound: "assets/store/impact-patch_soft_ball.wav", mode: "throwable" },
    ],
  },
  bubbles: {
    eyebrow: "對話框",
    title: "對話框也能換成你的風格。",
    description: "變更訊息與輸入中提示的顏色和小裝飾。",
    products: [
      { id: "bubble_default", name: "基本對話框", description: "在各種桌面背景上都清楚易讀的 SIDEY 標準對話框。", price: "隨附", mode: "bubble", bubbleTheme: "default" },
    ],
  },
};

export const includedProductIDs = new Set(["pixel_hamster", "pixel_cat", "pixel_puppy", "pixel_rabbit", "pixel_penguin", "patch_soft_ball", "bubble_default"]);

// The same paid catalog drives the app, server, and public store. Never fall back
// to a different locale for a newly added product: a missing translation fails the build.
function completeCatalog(locale: Locale, catalog: StoreCatalog): StoreCatalog {
  for (const category of ["characters", "throwables", "bubbles"] as const) {
    const kind = category.slice(0, -1);
    const previous = catalog[category].products;
    const paid = commerceCatalog.filter((entry) => entry.kind === kind).sort((a, b) => a.sort_order - b.sort_order);
    const included = previous.filter((product) => includedProductIDs.has(product.id));
    catalog[category].products = [...included, ...paid.map((entry): StoreProduct => {
      const presentation = commerceProducts[entry.id as keyof typeof commerceProducts];
      const translated = commerceLocalizations[locale][entry.id];
      if (!translated) throw new Error(`Missing ${locale} store translation: ${entry.id}`);
      const renderID = entry.render_asset_id ?? entry.item_id;
      return {

        id: entry.item_id,
        commerceID: entry.id,
        name: translated.display_name,
        description: translated.description,
        price: locale === "ko" ? `${entry.direct_price.toLocaleString("ko-KR")}원` : `₩${entry.direct_price.toLocaleString("en-US")}`,
        mode: presentation.mode as StoreAssetMode,
        asset: presentation.asset,
        mirrorsMovement: ["pixel_starlight_upalupa", "pixel_guinea_pig"].includes(entry.item_id),
        emitterAsset: entry.id === "throwable_toy_cannon" ? "assets/cosmetics/throwable_toy_cannon_emitter.png" : undefined,
        bubbleTheme: kind === "bubble" ? entry.item_id.replace("bubble_", "").replaceAll("_", "-") as StoreProduct["bubbleTheme"] : undefined,
        isTree: entry.item_id === "pixel_tree",
        isKeepsake: Boolean(entry.related_character_product_id),
        sound: kind === "throwable" ? `assets/store/impact-${renderID}.wav` : undefined,
      };
    })];
  }
  for (const character of catalog.characters.products) {
    const paired = commerceCatalog.find((entry) => entry.related_character_product_id === character.commerceID);
    character.keepsake = paired ? catalog.throwables.products.find((product) => product.commerceID === paired.id) : undefined;
  }
  return catalog;
}

export const storeCategoriesByLocale: Record<Locale, StoreCatalog> = {
  ko: completeCatalog("ko", ko), en: completeCatalog("en", en), ja: completeCatalog("ja", ja), "zh-Hant": completeCatalog("zh-Hant", zhHant),
};
export const storeCategories = storeCategoriesByLocale.ko;

export function getStoreCategories(locale: Locale): StoreCatalog {
  return storeCategoriesByLocale[locale];
}
