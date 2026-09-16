-- ポチッとモール（水曜のDX道場 第3回ハンズオン）
-- 専門家C「配送追跡スペシャリスト」用 Supabaseスキーマ（配送会社DB用プロジェクト）
--
-- ※このSQLは、配送会社DB専用のSupabase Project（GASでいう「配送会社DB」スプレッドシートに相当）で実行する。
--   ECサイトDBとは別のProjectとして分離すること（別組織の体を取っているため）。

create table delivery_status (
  id serial primary key,
  delivery_no text not null,      -- 配送番号（例：DV-000000001）
  recorded_at timestamp not null, -- 記録日時
  location text not null,         -- 所在地
  status text not null            -- ステータス（荷物受領／発送／中継センター到着／中継センター出発／配達中／配達完了）
);

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
-- Difyエージェント（専門家C）のツール呼び出し規約
-- ============================================================
-- ・配送状況取得：Get Rows(delivery_status) フィルタ：delivery_no
--   該当する行が無い場合（0件）は「まだ発送されていない」ことを意味する、とエージェントのプロンプトで教えておく
--   （GAS版の found:false と同じ考え方。Supabase版では0件レスポンス自体がその意味を持つ）。
--
-- ★フィルタの実際の書式（eq.など）はDifyプラグインの挙動次第のため、Get Rows(delivery_status)で
--   まず単純な1条件フィルタ（例：delivery_no=eq.DV-000000002）を試して書式を確認する。

-- ============================================================
-- データ投入について
-- ============================================================
-- 既存のGoogle Sheets（配送会社DB）をCSVでエクスポートし、Supabaseのテーブルエディタの
-- 「Insert」→「Import data from spreadsheet」機能でこのテーブルに読み込んでください
-- （列名を上記に合わせて英語にリネームしてからのインポートが必要です）。
--
-- 列名の対応表：
--   配送番号→delivery_no、記録日時→recorded_at、所在地→location、ステータス→status
--
-- Row Level Security(RLS)について：
-- DifyプラグインはSupabaseの「service_role」キーを使うため、RLSは自動的にバイパスされます。
-- ハンズオンのデモ用途なので今回はRLSを有効化しない設計としています。
