# ffxivlua

FFXIV SomethingNeedDoing (SND) 用の Lua 自動化スクリプト集。

## スクリプト一覧

### `purple_tongue_farm.lua`
紫の舌先（Purple Tongue）を釣って精選し、紫電の霊砂（Purple Lightning Sand）を自動収集するスクリプト。

**機能**
- 3 箇所の釣りポイントを指定時間でローテーション
- インベントリが一杯になったら自動で精選(Aetherial Reduction)
- 紫電の霊砂を指定数集めたら終了
- **SND の `[[SND Metadata]]` 機能を使用。全設定をゲーム内 Config タブから編集可能**

**必要プラグイン**
- SomethingNeedDoing (Expanded Edition)
- vnavmesh
- Lifestream
- AutoHook

**使い方**
1. SND に `purple_tongue_farm.lua` をインポート
2. マクロを選択 → **Config タブ**で以下の値を設定（ゲーム内でGUI編集可）
   - `target_sand_count` : 紫電の霊砂の目標数（既定 99）
   - `time_per_spot_sec` : 1 釣り場あたりの滞在秒数（既定 900 = 15 分）
   - `bait_item_id`      : 使用する餌の ItemId
   - `autohook_preset`   : AutoHook 側のプリセット名（既定 "紫の舌先"）
   - `aetheryte_name`    : Lifestream エーテライト名（既定 "朋友の灯火"）
   - `spot1_x/y/z` 〜 `spot3_x/y/z` : 3 つの釣り場ワールド座標
   - `use_flight` / `needs_collectable` / `debug`
3. AutoHook で「紫の舌先」用プリセットを事前に作成
4. 漁師でログイン、インベントリを空けて実行

**固定値（ItemId、スクリプト先頭で定義）**

| 名称 | ItemId |
|---|---|
| 紫の舌先 | 46249 |
| 紫電の霊砂 | 46246 |

**既定の釣り場座標 (朋友の灯火 付近)**

| # | X | Y | Z |
|---|---|---|---|
| 1 |   6.215 | 25.185 |  24.578 |
| 2 | -24.975 | 21.487 | -58.947 |
| 3 | 158.372 | 24.070 | -17.322 |

## 参考

- https://github.com/Jaksuhn/SomethingNeedDoing
- https://github.com/Jaksuhn/SomethingNeedDoing/wiki/Macro-Configs
- https://github.com/pot0to/pot0to-SND-Scripts/
- https://github.com/lycopersicon-esculentum/ffxiv-snd-scripts
