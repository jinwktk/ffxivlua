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
  use_flight:
    default: true
    type: bool
    required: true
  needs_collectable:
    default: true
    type: bool
    required: true
  auto_repair:
    default: true
    description: 装備耐久が閾値を下回ったら自己修理を実行する (要 自己修理アクション + Dark Matter)
    type: bool
    required: true
  repair_threshold_pct:
    default: 20
    description: 装備耐久の最低値 (%) がこの値以下で修理を発動
    type: int
    min: 1
    max: 99
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
local SCRIPT_VERSION = "0baebc5"                -- AUTO-UPDATED BY HOOK
local SCRIPT_BUILD   = "2026-04-22 20:22"                -- AUTO-UPDATED BY HOOK

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
    auto_repair         = cfg("auto_repair", true),
    repair_threshold_pct = cfg("repair_threshold_pct", 20),
    debug               = cfg("debug", true),
    -- 釣り場座標: landing=マウント解除用の地上ポイント、x/y/z=実際の釣り位置
    spots = {
        { name = "ポイント1",
          landing = { x = 210.15103, y = 127.40002,  z = -9.579741 },
          x = 202.16898, y = 128.0406,  z = -13.583072 },
        { name = "ポイント2",
          landing = { x = 161.51698, y = 117.974045, z =  71.1879   },
          x = 156.48239, y = 118.766556, z =  67.60431 },
        { name = "ポイント3",
          landing = { x =  46.232803, y = 117.93005, z = 101.74118 },
          x =  47.8799,  y = 118.18503,  z =  91.6896 },
    },
    -- 共通 pointToFace (キャスト前に全スポットでこの方角へ向き直す)
    face = { x = 83.00321, y = 121.52815, z = -50.590492 },
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
