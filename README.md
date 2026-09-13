# 水曜のDX道場 2026/09/16 発表用構築コード集

## 1. はじめに

「AI技術の『仕組み』を学び直すシリーズ」第3回（Agentic AI）のハンズオンで使用する構築コード一式です。
架空の通販サイト「ポチッとモール」（本・雑誌ECサイト）のカスタマーサポートAIチームを、Difyのマルチエージェント構成（コンシェルジュ＋専門家3人）で構築します。

- 専門家B（注文・商品情報スペシャリスト）・専門家C（配送追跡スペシャリスト）のデータストアはSupabase（PostgreSQL）
- Difyの公式Supabaseプラグイン（Get Rows / Create a Row / Update Row(s) / Delete Row(s)）をカスタムツールとしてエージェントに持たせ、固定のHTTPノードではなくエージェントが自律的にツールを呼ぶ構成にする
- ECサイトDBと配送会社DBは別組織の体を取っているため、Supabaseの**Projectを2つ**に分けて構築する（1 Project = 1 Postgresデータベースのため）

## 2. フォルダ構成

- dify: Dify の構築用コード (DSL)
- supabase: Supabase の構築用コード (DDL, DML)
  - `ec_schema.sql`：ECサイトDB用Project（専門家B）のテーブル・ビュー定義
  - `ec_seed.sql`：ECサイトDB用のダミーデータ投入（INSERT文）
  - `delivery_schema.sql`：配送会社DB用Project（専門家C）のテーブル定義
  - `delivery_seed.sql`：配送会社DB用のダミーデータ投入（INSERT文）

## 3. 構築手順

1. Supabaseで **ECサイトDB用のProject** と **配送会社DB用のProject** を、それぞれ別々に作成する
2. ECサイトDB用ProjectのSQL Editorで `supabase/ec_schema.sql` → `supabase/ec_seed.sql` の順に実行し、テーブル・ビューの作成とダミーデータの投入を行う
3. 配送会社DB用ProjectのSQL Editorで `supabase/delivery_schema.sql` → `supabase/delivery_seed.sql` の順に実行する
4. Difyで公式Supabaseプラグインをインストールし、ECサイトDB用Project・配送会社DB用Projectそれぞれの「プロジェクトURL」と「service_roleキー」を使って認証情報を設定する
5. 専門家B・専門家Cのエージェントに、対応するSupabaseツール（Get Rows / Update Row(s) 等）を追加し、各SQLファイルに記載の「ツール呼び出し規約」（フィルタ条件の付け方、本人確認の手順など）に沿ってプロンプトを設計する

詳細な設計判断の経緯（GASからSupabaseへ移行した理由など）は、プロジェクトの検討メモ（Claude Project）を参照。
