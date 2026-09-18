# SubagentStart additionalContext ランブック（Cowork 実機）

**問い**: plugin-level の `SubagentStart` hook は Cowork で発火するか。発火するとして、
`hookSpecificOutput.additionalContext` で返した文字列は **subagent の context に実際に届くか**。

## 0. 前提（済み）

- `SubagentStart` / `SubagentStop` / `PostToolUse(Agent|Task)` は Cowork validator を通る（OBS-13）。
- インストール失敗の原因は `plugin.json` の `description` 長だった。**500 文字未満**に保つこと。

## 1. 準備

```bash
./scripts/package-subagentstart.sh    # -> dist/cowork-subagentstart-probe.zip
```

ラダー用 plugin（`sa-l0-*` 〜 `sa-l10-*`, `sa-desc-*`）を入れたままだと、それらの
SessionStart / SubagentStart hook も一緒に発火して `SAL-*` 行が混ざる。**先にアンインストールする。**

## 2. 実行

Cowork タブ（および対照として Code タブ）で:

```
/cowork-subagentstart-probe:sa-check
```

スキルが 4 手順を指示する。要点は「`sa-reporter` subagent を 1 回起動し、その返答をそのまま貼る」。

## 3. 観測点

| マーカー | どこに出るか | 意味 |
|---|---|---|
| `SA-CTL` | main session | plugin hook が surface する土台確認 |
| `SA-JSON` | **subagent** | matcher 無し SubagentStart の additionalContext が届いた（**本命**） |
| `SA-MATCHED` | **subagent** | matcher `sa-reporter` 付き entry も届いた（matcher が効く） |
| `SA-PLAIN` | **subagent** | JSON ではない生 stdout も届く |
| `SA-EXECLOG` | main session | PostToolUse(Agent) が host 側実行ログを再生（hook が走ったかの証拠） |
| `SA-STOP` | main session | SubagentStop が発火した |

## 4. 判定

| subagent 側 | `SA-EXECLOG` | 結論 |
|---|---|---|
| `SA-JSON` あり | count ≥ 1 | **additionalContext 注入は Cowork でも機能する** |
| `SA-JSON` 無し / `SA-PLAIN` あり | count ≥ 1 | JSON は無視され plain stdout のみ届く |
| 両方無し | count ≥ 1 | hook は走ったが subagent へ何も注入されない（出力が捨てられる） |
| 両方無し | count = 0 | **SubagentStart event が発火しない**（または hook 間で host FS が共有されない） |

`SA-CTL` が subagent 側にも出た場合は、注入ではなく親 context の継承を見ている可能性があるので、
`SA-JSON` の有無だけで判断する。

## 5. 結果（測定済み）

`findings/cowork-macos/observations.md` の **OBS-14** に記録。要点:

- SubagentStart は Cowork で発火し、**JSON `additionalContext` は subagent に届く**（ローカル実行・リモート実行とも）
- **生 stdout は届かない**（実行はされ transcript には残るが、モデルの context には入らない）
- matcher `"sa-reporter"` は両環境でマッチせず（hook 名は `SubagentStart:<plugin>:<agent>` の完全名）
- hook の実行場所は実行モードで変わる: ローカル=Mac ホスト / リモート=`host=[vm]`

### 生ログの在り処

- ローカル実行: `~/Library/Application Support/Claude/local-agent-mode-sessions/.../.claude/projects/session/<sid>.jsonl`
  と `.../<sid>/subagents/agent-<id>.jsonl`（subagent の context がそのまま残る。`rendered` の有無で
  「モデルに届いたか」が判別できる）
- リモート実行: ローカルに transcript は無い。claude.ai の会話キャッシュ
  `~/Library/Application Support/Claude/IndexedDB/https_claude.ai_0.indexeddb.blob/` に V8 シリアライズで
  入っており断片的にしか読めない（決定的な行は復元可能）
