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
1. `purple_tongue_farm.lua` 冒頭の「ユーザー設定」を埋める
   - `FISH_ITEM_ID` / `SAND_ITEM_ID` / `BAIT_ITEM_ID`
   - `AUTOHOOK_PRESET`（AutoHook 側に事前登録）
   - `FISHING_SPOTS` に 3 箇所の座標とエーテライト
   - `TIME_PER_SPOT_SEC`（1 箇所の滞在秒数、既定 15 分）
   - `TARGET_SAND_COUNT`（紫電の霊砂の目標数）
2. 漁師でログイン、インベントリを空ける
3. SND で本スクリプトを実行

## 参考

- https://github.com/Jaksuhn/SomethingNeedDoing
- https://github.com/pot0to/pot0to-SND-Scripts/
- https://github.com/lycopersicon-esculentum/ffxiv-snd-scripts
