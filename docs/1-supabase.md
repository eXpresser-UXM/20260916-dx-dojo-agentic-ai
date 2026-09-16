# Supabaseの構築手順

専門家B（注文・商品情報スペシャリスト）と専門家C（配送追跡スペシャリスト）が扱うデータは、Supabase（PostgreSQL）に置いています。この2つのデータストアは「ポチッとモール（ECサイト運営会社）」と「配送会社」という別組織の体を取っているため、Supabaseの**Projectを2つ**に分けて構築します（Supabaseは1 Project = 1 Postgresデータベースのため）。

## 1. ECサイトDB用Projectの構築（専門家B用）

1. Supabaseで新しいProjectを作成する（名前は任意。例：`pochitto-mall-ec`）
2. SQL Editorで [`supabase/ec_schema.sql`](../supabase/ec_schema.sql) を実行し、以下のテーブル・ビューを作成する
   - `categories`（分類一覧マスタ）
   - `products`（商品一覧）
   - `users`（会員マスタ。本人確認の起点）
   - `orders`（注文一覧。1行＝1商品明細の粒度。氏名・生年月日は持たず、`user_id`経由で`users`を参照する正規化された形）
   - `my_orders_view`（`orders`と`users`を結合した、自分の注文一覧を読み取るための便宜ビュー。書き込みは正規化された`orders`テーブルに直接行う）
3. 続けて同じSQL Editorで [`supabase/ec_seed.sql`](../supabase/ec_seed.sql) を実行し、ダミーデータ（カテゴリ・商品・会員・注文）を投入する

## 2. 配送会社DB用Projectの構築（専門家C用）

1. Supabaseで、ECサイトDB用とは**別の**新しいProjectを作成する（例：`pochitto-mall-delivery`）
2. SQL Editorで [`supabase/delivery_schema.sql`](../supabase/delivery_schema.sql) を実行し、`delivery_status`テーブル（配送番号ごとに、荷物受領→発送→中継センター到着→中継センター出発→配達中→配達完了、という記録が時系列で複数行積み上がる設計）を作成する
3. 続けて [`supabase/delivery_seed.sql`](../supabase/delivery_seed.sql) を実行し、ダミーの配送記録を投入する

## 3. テーブルをData APIに公開する（重要・両Project共通）

2026年時点のSupabaseの仕様変更により、`CREATE TABLE`しただけではDify等が呼び出すData API（PostgREST）にテーブルが自動公開されず、次のようなエラーになります。

```
PGRST205 "Could not find the table 'public.xxx' in the schema cache"
```

`ec_schema.sql` / `delivery_schema.sql` にはこのGRANT文がすでに含まれていますが、万が一テーブル作成後にこのエラーが出た場合は、両Projectそれぞれで [`supabase/fix_expose_tables.sql`](../supabase/fix_expose_tables.sql) を実行してください（`categories`・`products`・`users`・`orders`に加えて`my_orders_view`のようなビューも、Postgresの`ALL TABLES IN SCHEMA`にはビューが含まれるため、このGRANTでカバーされます）。

```sql
grant usage on schema public to anon, authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to anon, authenticated, service_role;
alter default privileges in schema public
  grant select, insert, update, delete on tables to anon, authenticated, service_role;
notify pgrst, 'reload schema';
```

## 4. 接続情報とAPIキーの扱い

DifyのSupabaseプラグイン（Custom Tool）を各専門家エージェントに設定する際、Project SettingsのAPI設定画面から次の情報を控えます。

- **Project URL**
- **API Key**

SupabaseのAPI Keyは`secret key`（旧`service_role`キー相当。RLSを自動的にバイパスするフル権限キー）と`publishable key`（旧`anon`キー相当）の2種類が発行されます。本ハンズオンは`Row Level Security(RLS)`を有効化していないため、上記3.のGRANTにより`anon`ロールにも全テーブル・ビューへのCRUD権限が与えられており、`publishable key`でも読み書きが可能です。運用ポリシーとして、

- `secret key`は岡さん自身の動作確認・トラブルシュート用に留め、他人と共有しない
- 当日、参加者が各自インポートするDifyアプリ（コンシェルジュ＋専門家A・B）から共有Supabase Projectへ接続する際は、`publishable key`を使う

という使い分けにしています。RLSを有効化しない設計はあくまでハンズオンのデモ用途としての割り切りであり、本番運用する場合はここが大きな注意点になる、という点は「使う上での注意点」パートでも触れる価値があります。

## 5. フィルタ書式について（実地検証済み・重要な注意点）

DifyのSupabase公式プラグイン（`Get Rows`等）のフィルタ条件は、当初PostgRESTの一般的な書式である`eq.`付き（例：`delivery_no=eq.DV-000000003`）を想定していましたが、**実機検証の結果、正しくは`eq.`を付けない単純な書式（例：`delivery_no=DV-000000003`）であることが確定しています。** `eq.`付きの書式では意図通りに絞り込まれず、0件やフィルタが効かない結果になることがあるため注意してください。複数条件を指定する場合は`&`で連結します（例：`name=山田 太郎&birthdate=1988-02-03`）。

この書式は各専門家のプロンプト（`dify/expert_b_prompt.md`・`dify/expert_c_prompt.md`）にも明記済みです。念のため、各専門家のプロンプトには「フィルタが0件を返した場合は、フィルタなしで全件取得して自分で照合し直す」というフォールバック手順も入れてあります。

## 6. `Update Row(s)`についての既知の注意点

`Get Rows`はフィルタ書式さえ正しければ安定して動作しますが、`Update Row(s)`（注文のキャンセル・返品処理で使用）については、本ハンズオンの検証時点で0件更新（`{"data": []}`）となる事象が発生したことがあり、確実に成功する書式・条件の組み合わせがまだ確定していません。イベント本番の前に、Difyの画面上で`Update Row(s)`を最小構成（主キー`id`のみでフィルタする等）で直接テストし、想定通り更新されることを確認しておくことを強く推奨します。
