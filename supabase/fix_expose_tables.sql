-- PGRST205「Could not find the table ... in the schema cache」対処用
-- ECサイトDB用Project・配送会社DB用Projectの両方のSQL Editorで実行してください。
--
-- 原因：テーブルはCREATE TABLEで作成されていても、Data API（PostgREST）側に
-- 明示的な権限（GRANT）が無いと「テーブルが見えない」扱いになる仕様のため
-- （2026年時点のSupabaseの挙動。新規テーブルはAPIに自動公開されない）。

grant usage on schema public to anon, authenticated, service_role;

grant select, insert, update, delete on all tables in schema public to anon, authenticated, service_role;

-- 今後このスキーマ内に新しいテーブル・ビューを追加したときも自動的に権限が付くようにする
alter default privileges in schema public
  grant select, insert, update, delete on tables to anon, authenticated, service_role;

-- PostgRESTにスキーマ情報の再読み込みを指示する
notify pgrst, 'reload schema';
