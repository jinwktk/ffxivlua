# ffxivlua

FFXIV SomethingNeedDoing (SND) 用の Lua 自動化スクリプト集。

## スクリプト一覧

### `purple_tongue_farm.lua`
紫の舌先（Purple Tongue）を釣って精選し、紫電の霊砂（Purple Lightning Sand）を自動収集するスクリプト。

**機能**
- 3 箇所の釣りポイントを指定時間でローテーション
- インベントリが一杯になったら自動で精選(Aetherial Reduction)
- 紫電の霊砂を指定数集めたら終了

**必要プラグイン**
- SomethingNeedDoing (Expanded Edition 推奨)
- vnavmesh
- Lifestream
- AutoHook

**使い方**
1. `purple_tongue_farm.lua` 冒頭の「ユーザー設定」を確認
   - `FISH_ITEM_ID = 46249`（紫の舌先）  GarlandTools 確認済み
   - `SAND_ITEM_ID = 46246`（紫電の霊砂）GarlandTools 確認済み
   - `BAIT_ITEM_ID`（使用する餌の ItemId）  **要設定**
   - `AUTOHOOK_PRESET`（AutoHook に事前登録したプリセット名）  **要設定**
   - `FISHING_SPOTS` の `aetheryte` が正しいか確認（既定: エレクトープ発電所）
   - `TIME_PER_SPOT_SEC`（1 箇所の滞在秒数、既定 900 = 15 分）
   - `TARGET_SAND_COUNT`（紫電の霊砂の目標数、既定 99）

**登録済み座標 (Heritage Found / クル・シャゲ想定)**
| # | X | Y | Z |
|---|---|---|---|
| 1 |   6.215 | 25.185 |  24.578 |
| 2 | -24.975 | 21.487 | -58.947 |
| 3 | 158.372 | 24.070 | -17.322 |
2. 漁師でログイン、インベントリを空ける
3. SND で本スクリプトを実行

## 参考

- https://github.com/Jaksuhn/SomethingNeedDoing
- https://github.com/pot0to/pot0to-SND-Scripts/
- https://github.com/lycopersicon-esculentum/ffxiv-snd-scripts
