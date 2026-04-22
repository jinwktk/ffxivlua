# ffxivlua

FFXIV SomethingNeedDoing (SND) 用の Lua 自動化スクリプト集。

## ファイル構成

```
purple_tongue_farm.lua      ← メイン（SND Metadata + Config + 実行）
lib/
  └── ptf_lib.lua          ← 実装本体（ヘルパー / 移動 / 釣り / 精選）
```

メインは設定と呼び出しだけ。実装を変更しても SND 側はメインを再読込しなくて済む。

## セットアップ

### 1. Macro Dependencies に lib/ptf_lib.lua を追加

SND のマクロ画面 → **Macro Dependencies** → **Add New Dependency** →
- **Local** を選択
- **Local Dependency Type: File** を選択
- 下記のフルパスを貼り付け:
  ```
  C:\Users\mlove\Documents\GitHub\ffxivlua\lib\ptf_lib.lua
  ```
- **Add File Dependency** を押す

これで `_G.PTF` が使えるようになる。

### 2. メインスクリプトを登録

`purple_tongue_farm.lua` を SND マクロとしてインポート or 貼り付け。

### 3. Config タブでパラメータ調整

ゲーム内の Config タブから変更可能:
- `target_sand_count`(99) / `time_per_spot_sec`(900)
- `bait_item_id` / `autohook_preset`(紫の舌先) / `aetheryte_name`(朋友の灯火)
- 3点の `spot1_x/y/z` 〜 `spot3_x/y/z`
- `use_flight` / `needs_collectable` / `debug`
- `auto_repair`(true) / `repair_threshold_pct`(20) — 自己修理の有効化と閾値(%)
- `extract_materia`(true) — 錬精度 100% 装備の自動マテリア抽出

### 4. 実行
- 漁師でログイン、インベントリを空ける
- AutoHook で指定プリセットを事前作成
- 自己修理を有効にする場合は **自己修理アクション (GA 6) 習得 + Dark Matter Cluster (33916) を携帯**
- マテリア抽出を有効にする場合は **マテリア精製アクション (GA 14) を習得済**
- SND でマクロを実行

## バージョン識別

`ptf.log` 先頭と `/echo` に **コミットSHA + ビルド日時** が出る。

### pre-commit hook セットアップ (初回のみ)
```
git config core.hooksPath .githooks
```

コミット毎に `SCRIPT_VERSION` / `LIB_VERSION` が自動更新される。

## 固定値 (ItemId)

| 名称 | ItemId |
|---|---|
| 紫の舌先 | 46249 |
| 紫電の霊砂 | 46246 |

## 既定の釣り場 (朋友の灯火付近)

| # | X | Y | Z |
|---|---|---|---|
| 1 | 202.16898 | 128.0406  | -13.583072 |
| 2 | 156.48239 | 118.76656 |  67.60431 |
| 3 |  47.8799  | 118.18503 |  91.6896  |

## 参考

- https://github.com/Jaksuhn/SomethingNeedDoing
- https://github.com/Jaksuhn/SomethingNeedDoing/wiki/Macro-Configs
- https://github.com/OhKannaDuh/Ferret （モジュール化の参考）
- https://github.com/WigglyMuffin/SNDScripts （API使用例）
