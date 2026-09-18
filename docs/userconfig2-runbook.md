# userConfig 再検証 runbook（Claude Desktop: Code タブ / Cowork タブ）

対象バージョン: Claude Code **2.1.238**（この環境の `claude --version`）。
前回検証（`cowork-userconfig-probe`, 2026-05-27）は 2.1.14x 系で、その後 **仕様が変わっている**。

## 何が変わったので再検証するのか

公式 docs（`code.claude.com/docs/en/plugins-reference` / `.../hooks`）の現行記述：

1. **shell form の hook が `${user_config.*}` を参照すると、実行されずエラーになる。**
   > "A plugin hook whose `command` references `${user_config.*}` fails with an error instead of running."
   > "Before v2.1.207, shell-form plugin hooks also substituted `${user_config.*}`."
   → 前回 probe の hooks.json は **全部 shell form** だったので、そのままでは今の仕様を測れない。
2. **exec form（`args` あり）なら `${user_config.*}` は置換される**（shell を介さない）。
3. env 経由は `CLAUDE_PLUGIN_OPTION_<KEY>`（hook process 向け、と docs は書く）。
4. skill だけでなく **agent content** でも非機密値は置換される、と明記された。
5. option の宣言可能フィールドが増えている：`default` / `multiple` / `min` / `max` / type に `directory` `file`。
   （`default` は以前 feature request だったもの）
6. `pluginConfigs` は **user settings / `--settings` / managed settings からしか読まれない**。
   project の `.claude/settings.json` は無視される。

## 使う plugin

| zip | 役割 |
|---|---|
| `dist/cowork-userconfig2-probe.zip` | 本体。exec form 置換 / env / skill body / agent content / `default` / 型別 UI |
| `dist/userconfig2-shellform-violator.zip` | shell form + `${user_config.*}` の失敗のしかただけを隔離して見る |

violator を別 plugin にしてあるのは、失敗が本体 probe を巻き添えにしないため。

再生成：

```sh
./scripts/package-userconfig2.sh
```

## 入力する値（固定）

| key | 入れる値 |
|---|---|
| `opt_plain` | `OPTPLAIN-VAL` |
| `req_plain` | `REQPLAIN-VAL` |
| `opt_secret` | `OPTSECRET-VAL`（ダミー。実 secret は使わない） |
| `req_secret` | `REQSECRET-VAL`（同上） |
| `def_plain` | **空のまま**（`default` の効きを見るため） |
| `num_opt` | `42` |
| `bool_opt` | ON |
| `multi_opt` | `M1`, `M2` |
| `vio_plain`（violator） | `VIOPLAIN-VAL` |

## 手順

各面（**Code タブ** と **Cowork タブ**）で同じことを 2 回やる。

### Phase 1: install（UI 有無の判定はここ）

1. zip を install する。
2. **install 中に入力フォームが出たか**を記録。出た場合は上表の値を入れる。
3. `required: true`（`req_plain` / `req_secret`）が未入力でも install が通るか。
4. 型別 UI の見た目：`num_opt` は数値入力か / `bool_opt` はトグルか / `multi_opt` は複数入力か / `sensitive` はマスクされるか。
5. **後から編集する導線があるか**（設定画面 / `/plugin configure` 相当）。

UI が一つも無かった面では、手で値を入れる fallback を試す（CLI 由来の経路が Desktop にも効くか）:

```json
// ~/.claude/settings.json
{ "pluginConfigs": { "cowork-userconfig2-probe@<marketplace-or-inline>": {
  "options": { "opt_plain": "OPTPLAIN-VAL", "req_plain": "REQPLAIN-VAL" } } } }
```

### Phase 2: SessionStart を撮る

新しいセッションを開き、context に出た次の行を全部控える。

- `UC2-CTL shell_form_static=alive` / `UC2-CTL exec_form_static=alive`（対照）
- `UC2-EXEC <key>=[...]` × 8（exec form 置換）
- `UC2-ENV CLAUDE_PLUGIN_OPTION_*` × 8 +（`all_prefixed_names`）

### Phase 3: skill / agent / Bash tool

```
/cowork-userconfig2-probe:uc2-check
```

body の `BODY <key>=[...]` 行、Bash tool の `TOOL_ENV ...` 行を記録。
その後 `uc2-agent` を呼んで `AGENT <key>=[...]` を記録。

### Phase 4: violator

violator zip を install → 新セッション → `VIO-CTL before` / `VIO-SHELL` / `VIO-CTL after` の
3 行のうちどれが出たか、エラー表示がどこに出たかを記録。

## 記録先

`findings/userconfig2/observations.md` に、面（code / cowork）ごとに上の生ログを貼る。
確定した差分だけ `docs/team-report.md` の §1.4 / §1.5 / §2.4 / §2.5 に反映する。
