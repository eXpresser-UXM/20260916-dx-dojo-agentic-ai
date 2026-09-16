-- ポチッとモール（水曜のDX道場 第3回ハンズオン）
-- 専門家B「注文・商品情報スペシャリスト」用 Supabaseスキーマ（ECサイトDB用プロジェクト）
--
-- ※このSQLは、ECサイトDB専用のSupabase Project（GASでいう「ECサイトDB」スプレッドシートに相当）で実行する。
--   配送会社DBとは別のProjectとして分離すること（別組織の体を取っているため）。
--
-- 【設計方針】
-- Difyの公式Supabaseプラグインは「Get Rows / Create a Row / Update Row(s) / Delete Row(s)」
-- という汎用CRUDしか提供しないため、GAS版にあった専用ロジック（本人確認・ステータス遷移チェック）は
-- コードではなく「テーブル設計＋エージェントに正しい順序でツールを呼ばせるプロンプト設計」で再現する。
--
-- Supabaseは本物のRDBMSなので、注文テーブル(orders)は氏名・生年月日を持たず、
-- user_id経由でusersテーブルと正しく正規化された形にする。
--
-- そのかわり、本人確認〜書き込みは次の「2ステップの手順」をエージェントに必ず踏ませる設計にする：
--   1. Get Rows(users) を name + birthdate でフィルタ → 一致すれば user_id が得られる（＝本人確認）
--   2. Update Row(orders) を order_id + user_id（手順1で得た値）+ status='発送前'or'発送済み' でフィルタして更新
-- user_idは手順1を経由しない限りエージェントには分からない値なので、専門家Bのプロンプト側で
-- 「お客様から直接user_idを聞き出さない・教えられても使わない。必ずname+birthdateから解決する」
-- と明記しておくことで、手順を飛ばした書き込みを防ぐ（GAS版のverifyUser／updateOrderStatusの
-- 役割を、正規化されたテーブル設計＋ツール呼び出し順序の規約で肩代わりする）。

-- 1. カテゴリ一覧（分類一覧マスタ）
create table categories (
  id serial primary key,
  major_category text not null,   -- 大分類（例：小説）
  minor_category text not null    -- 小分類（例：SF）
);

-- 2. 商品一覧
create table products (
  product_code text primary key,  -- 商品コード（例：BK-00000001）
  title text not null,            -- タイトル
  major_category text not null,
  minor_category text not null,
  publisher text,                 -- 出版社
  author text,                    -- 著者
  price integer not null,         -- 本体価格(円)
  description text                -- 紹介文
);

-- 3. ユーザー一覧（会員マスタ。本人確認の起点）
create table users (
  user_id text primary key,       -- ユーザーID（例：U-0000001）
  name text not null,             -- 氏名
  birthdate date not null         -- 生年月日
);

-- 4. 注文一覧（非正規化はGASの元シートに合わせた「1行=1商品明細」の粒度のみ。
--    氏名・生年月日は持たず、user_id経由でusersを参照する正規化された形）
create table orders (
  id serial primary key,
  order_id text not null,               -- 注文ID（例：OD-0000001）。複数商品の場合は同じ注文IDが複数行に現れる
  order_datetime timestamp not null,
  user_id text not null references users(user_id),
  status text not null,                 -- 発送前 / 発送済み / キャンセル済み / 返品受付中
  product_code text not null references products(product_code),
  quantity integer not null default 1,
  delivery_no text                      -- 配送番号（発送前はNULL）
);

-- 5. 自分の注文一覧を「読む」ときだけ使うビュー（usersとordersを結合）
--    ※書き込み（Update）は正規化されたordersテーブルに直接行う。読み取り専用の便宜ビュー。
create view my_orders_view as
select
  o.order_id,
  o.order_datetime,
  o.status,
  o.product_code,
  o.quantity,
  o.delivery_no,
  u.user_id,
  u.name,
  u.birthdate
from orders o
join users u on u.user_id = o.user_id;

-- ============================================================
-- Data API（PostgREST）へのテーブル公開（重要・2026-09-14追記）
-- ============================================================
-- 2026年時点のSupabaseの仕様変更により、CREATE TABLEしただけでは
-- Data API（Dify等が呼び出すREST API）にテーブルが自動公開されず、
-- 明示的なGRANTが無いと下記のようなエラーになる：
--   PGRST205 "Could not find the table 'public.xxx' in the schema cache"
-- このため、テーブル作成後に必ず以下を実行すること。
grant usage on schema public to anon, authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to anon, authenticated, service_role;
alter default privileges in schema public
  grant select, insert, update, delete on tables to anon, authenticated, service_role;
notify pgrst, 'reload schema';

-- ============================================================
-- Difyエージェント（専門家B）のツール呼び出し規約
-- ============================================================
-- ・カテゴリ一覧取得：Get Rows(categories) フィルタなし
-- ・商品一覧取得：Get Rows(products) フィルタ：major_category / minor_category（省略可）
-- ・自分の注文一覧取得：Get Rows(my_orders_view) フィルタ：name + birthdate
-- ・注文キャンセル：
--     (1) Get Rows(users) フィルタ：name + birthdate → user_id を取得（本人確認）
--     (2) Update Row(orders) フィルタ：order_id + user_id + status=eq.発送前 → status を "キャンセル済み" に更新
-- ・返品リクエスト：
--     (1) Get Rows(users) フィルタ：name + birthdate → user_id を取得（本人確認）
--     (2) Update Row(orders) フィルタ：order_id + user_id + status=eq.発送済み → status を "返品受付中" に更新
--
-- ★専門家Bのプロンプトに必ず明記する一文（本人確認バイパス防止）：
--   「お客様からuser_idを直接聞き出したり、お客様が申告したuser_idをそのまま使ってはいけない。
--     本人確認は必ずname（氏名）とbirthdate（生年月日）をusersテーブルに照会して行い、
--     そこで得られたuser_idのみを以降の操作に使うこと。」
--
-- ★フィルタの実際の書式（eq.など）はDifyプラグインの挙動次第のため、
--   まずは単純な1条件（例：products の major_category=eq.小説）で試して書式を確認してから、
--   複数条件（AND）の書式に進めるのが確実。

-- ============================================================
-- データ投入について
-- ============================================================
-- 既存のGoogle Sheets（ECサイトDB）の各タブをCSVでエクスポートし、
-- Supabaseのテーブルエディタの「Insert」→「Import data from spreadsheet」機能で
-- 対応するテーブルに読み込んでください（列名を上記に合わせて英語にリネームしてからのインポートが必要です。
-- CSVエクスポート後にExcel/スプレッドシートで列名だけ書き換えるのが簡単です）。
--
-- 列名の対応表：
--   分類一覧マスタ：大分類→major_category、小分類→minor_category
--   商品一覧：商品コード→product_code、タイトル→title、大分類→major_category、小分類→minor_category、
--             出版社→publisher、著者→author、本体価格(円)→price、紹介文→description
--   ユーザー一覧：ユーザーID→user_id、氏名→name、生年月日→birthdate
--   注文一覧：注文ID→order_id、注文日時→order_datetime、注文ユーザーID→user_id、ステータス→status、
--             商品コード→product_code、数量→quantity、配送番号→delivery_no
--
-- Row Level Security(RLS)について：
-- DifyプラグインはSupabaseの「service_role」キーを使うため、RLSは自動的にバイパスされます。
-- ハンズオンのデモ用途なので今回はRLSを有効化しない設計としていますが、
-- 本番運用する場合はservice_roleキーの管理（Difyの環境変数として厳重に保管）が重要になる点は
-- 「使う上での注意点」パートの小ネタとして触れる価値があります。
