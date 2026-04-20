--[=====[
[[SND Metadata]]
author: jinwktk
version: 0.3.0
description: 紫の舌先を釣って精選し、紫電の霊砂を指定数集めるスクリプト。3つの釣り場を一定時間でローテーション。本体は lib/ptf_lib.lua に分離。
plugin_dependencies:
  - vnavmesh
  - Lifestream
  - AutoHook
configs:
  target_sand_count:
    default: 99
    description: 集めたい「紫電の霊砂」の個数
    type: int
    min: 1
    max: 9999
    required: true
  time_per_spot_sec:
    default: 900
    description: 1 つの釣り場に滞在する秒数 (既定 900 秒 = 15 分)
    type: int
    min: 60
    max: 7200
    required: true
  inventory_free_limit:
    default: 1
    description: 空きスロットがこの値以下になったら精選に入る
    type: int
    min: 0
    max: 30
    required: true
  bait_item_id:
    default: "29717"
    description: 使用する餌 (AutoHook /bait の引数。ItemId または餌名)
    type: string
    required: true
  autohook_preset:
    default: 紫の舌先
    description: AutoHook 側で事前登録したプリセット名
    type: string
    required: true
  aetheryte_name:
    default: 朋友の灯火
    description: Lifestream で使うエーテライト名
    type: string
    required: true
  spot1_x:
    default: 6.215
    type: float
    required: true
  spot1_y:
    default: 25.185
    type: float
    required: true
  spot1_z:
    default: 24.578
    type: float
    required: true
  spot2_x:
    default: -24.975
    type: float
    required: true
  spot2_y:
    default: 21.487
    type: float
    required: true
  spot2_z:
    default: -58.947
    type: float
    required: true
  spot3_x:
    default: 158.372
    type: float
    required: true
  spot3_y:
    default: 24.070
    type: float
    required: true
  spot3_z:
    default: -17.322
    type: float
    required: true
  use_flight:
    default: true
    type: bool
    required: true
  needs_collectable:
    default: true
    type: bool
    required: true
  debug:
    default: true
    type: bool
    required: true
[[End Metadata]]
--]=====]

--[==[
  purple_tongue_farm.lua  ---  エントリポイント
  ---------------------------------------------------------------
  本体実装は lib/ptf_lib.lua に分離しているので、SND の
  Macro Dependencies → Add → Local → File で下記のフルパスを
  登録してから実行する:

     C:\Users\mlove\Documents\GitHub\ffxivlua\lib\ptf_lib.lua

  そうするとグローバル PTF が利用可能になる。
]==]

------------------------------------------------------------------
-- バージョン識別 (git pre-commit hook で自動置換される) ---------
------------------------------------------------------------------
local SCRIPT_VERSION = "335fa28"                -- AUTO-UPDATED BY HOOK
local SCRIPT_BUILD   = "2026-04-20 18:15"                -- AUTO-UPDATED BY HOOK

------------------------------------------------------------------
-- Config 読み込み ----------------------------------------------
------------------------------------------------------------------
local function cfg(key, fallback)
    if Config and Config.Get then
        local ok, v = pcall(Config.Get, key)
        if ok and v ~= nil then return v end
    end
    return fallback
end

local opts = {
    target              = cfg("target_sand_count", 99),
    time_per_spot       = cfg("time_per_spot_sec", 900),
    inventory_free_limit = cfg("inventory_free_limit", 1),
    bait                = cfg("bait_item_id", "29717"),
    autohook_preset     = cfg("autohook_preset", "紫の舌先"),
    aetheryte           = cfg("aetheryte_name", "朋友の灯火"),
    use_flight          = cfg("use_flight", true),
    needs_collectable   = cfg("needs_collectable", true),
    debug               = cfg("debug", true),
    spots = {
        { name = "ポイント1",
          x = cfg("spot1_x",   6.215),
          y = cfg("spot1_y",  25.185),
          z = cfg("spot1_z",  24.578) },
        { name = "ポイント2",
          x = cfg("spot2_x", -24.975),
          y = cfg("spot2_y",  21.487),
          z = cfg("spot2_z", -58.947) },
        { name = "ポイント3",
          x = cfg("spot3_x", 158.372),
          y = cfg("spot3_y",  24.070),
          z = cfg("spot3_z", -17.322) },
    },
}

yield(string.format('/echo [PTF] main ver=%s build=%s', SCRIPT_VERSION, SCRIPT_BUILD))

------------------------------------------------------------------
-- ライブラリ呼び出し ------------------------------------------
------------------------------------------------------------------
if not _G.PTF then
    yield('/echo [PTF] ERROR: ptf_lib.lua が読み込まれていません')
    yield('/echo [PTF] SND の Macro Dependencies に Local → File で lib/ptf_lib.lua のフルパスを追加してください')
    yield('/echo [PTF] 終了します')
    return
end

_G.PTF.run(opts)
