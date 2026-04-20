--[=====[
[[SND Metadata]]
author: jinwktk
version: 0.2.0
description: 紫の舌先を釣って精選し、紫電の霊砂を指定数集めるスクリプト。3つの釣り場を一定時間でローテーションする。
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
    default: 29717
    description: 使用する餌の ItemId (ゲーム内でアイテムを右クリック→マクロにコピーで確認)
    type: int
    min: 1
    max: 999999
    required: true
  autohook_preset:
    default: 紫の舌先
    description: AutoHook 側で事前登録したプリセット名
    type: string
    required: true
  aetheryte_name:
    default: 朋友の灯火
    description: Lifestream で使うエーテライト名 (日本語可)
    type: string
    required: true
  spot1_x:
    default: 6.215
    description: 釣り場1 X
    type: float
    required: true
  spot1_y:
    default: 25.185
    description: 釣り場1 Y (高度)
    type: float
    required: true
  spot1_z:
    default: 24.578
    description: 釣り場1 Z
    type: float
    required: true
  spot2_x:
    default: -24.975
    description: 釣り場2 X
    type: float
    required: true
  spot2_y:
    default: 21.487
    description: 釣り場2 Y (高度)
    type: float
    required: true
  spot2_z:
    default: -58.947
    description: 釣り場2 Z
    type: float
    required: true
  spot3_x:
    default: 158.372
    description: 釣り場3 X
    type: float
    required: true
  spot3_y:
    default: 24.070
    description: 釣り場3 Y (高度)
    type: float
    required: true
  spot3_z:
    default: -17.322
    description: 釣り場3 Z
    type: float
    required: true
  use_flight:
    default: true
    description: 釣り場への移動に飛行マウントを使う
    type: bool
    required: true
  needs_collectable:
    default: true
    description: 収集品として釣る (精選に必要。紫の舌先は true)
    type: bool
    required: true
  debug:
    default: true
    description: /echo でデバッグメッセージを出す
    type: bool
    required: true
[[End Metadata]]
--]=====]

--[==[
  紫の舌先 釣り & 精選(紫電の霊砂) 自動化スクリプト for SomethingNeedDoing
  ---------------------------------------------------------------------
  概要:
    - 事前登録した 3 つの釣り場をローテーション（一定時間で移動）
    - インベントリが一杯になったら精選(Aetherial Reduction)で
      紫電の霊砂を取り出す
    - 紫電の霊砂を目標数集めたら終了
  ---------------------------------------------------------------------
  設定はスクリプト冒頭の [[SND Metadata]] ブロックに宣言されており、
  SND のマクロ Config タブから GUI 上で変更できる。
]==]

------------------------------------------------------------------
-- 固定 ItemId (ゲーム側で変わらないため Config 化しない) ----------
------------------------------------------------------------------
local FISH_ITEM_ID = 46249  -- 紫の舌先 (収集品)
local SAND_ITEM_ID = 46246  -- 紫電の霊砂

------------------------------------------------------------------
-- Config 読み込み ------------------------------------------------
------------------------------------------------------------------
local function cfg(key, fallback)
    if Config and Config.Get then
        local ok, v = pcall(Config.Get, key)
        if ok and v ~= nil then return v end
    end
    return fallback
end

local TARGET_SAND_COUNT    = cfg("target_sand_count", 99)
local TIME_PER_SPOT_SEC    = cfg("time_per_spot_sec", 900)
local INVENTORY_FREE_LIMIT = cfg("inventory_free_limit", 1)
local BAIT_ITEM_ID         = cfg("bait_item_id", 29717)
local AUTOHOOK_PRESET      = cfg("autohook_preset", "紫の舌先")
local AETHERYTE_NAME       = cfg("aetheryte_name", "朋友の灯火")
local USE_FLIGHT           = cfg("use_flight", true)
local NEEDS_COLLECTABLE    = cfg("needs_collectable", true)
local DEBUG                = cfg("debug", true)

local FISHING_SPOTS = {
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
}

------------------------------------------------------------------
-- 定数: CharacterCondition ---------------------------------------
------------------------------------------------------------------
local COND = {
    mounted      = 4,
    casting      = 27,
    fishing      = 43,
    betweenAreas = 45,
}

------------------------------------------------------------------
-- ヘルパー --------------------------------------------------------
------------------------------------------------------------------

local function log(msg)
    if DEBUG then yield("/echo [PTF] " .. tostring(msg)) end
end

local function wait(sec)
    yield("/wait " .. tostring(sec))
end

local function cond(id)
    if Svc and Svc.Condition then
        return Svc.Condition[id] == true
    end
    if GetCharacterCondition then return GetCharacterCondition(id) end
    return false
end

local function item_count(id)
    if Inventory and Inventory.GetItemCount then
        return Inventory.GetItemCount(id) or 0
    end
    if GetItemCount then return GetItemCount(id) or 0 end
    return 0
end

local function free_slots()
    if Inventory and Inventory.GetFreeInventorySlots then
        return Inventory.GetFreeInventorySlots() or 0
    end
    if GetInventoryFreeSlotCount then return GetInventoryFreeSlotCount() end
    return 35
end

local function wait_until(fn, timeout_sec)
    local t, step = 0, 0.5
    while not fn() do
        yield("/wait " .. step)
        t = t + step
        if timeout_sec and t >= timeout_sec then return false end
    end
    return true
end

------------------------------------------------------------------
-- 移動 ------------------------------------------------------------
------------------------------------------------------------------

local function teleport_to(aetheryte)
    log("テレポ: " .. aetheryte)
    yield('/li tp ' .. aetheryte)
    wait(2)
    wait_until(function() return cond(COND.betweenAreas) end, 5)
    wait_until(function() return not cond(COND.betweenAreas) end, 40)
    wait(3)
end

local function mount_up()
    if cond(COND.mounted) then return end
    yield("/gaction マウントロット")
    wait_until(function() return cond(COND.mounted) end, 5)
    wait(1)
end

local function dismount()
    if not cond(COND.mounted) then return end
    yield('/gaction "マウント解除"')
    wait_until(function() return not cond(COND.mounted) end, 5)
end

local function move_to(spot)
    if USE_FLIGHT then mount_up() end

    if IPC and IPC.vnavmesh and IPC.vnavmesh.PathfindAndMoveTo then
        IPC.vnavmesh.PathfindAndMoveTo({x = spot.x, y = spot.y, z = spot.z}, USE_FLIGHT)
        wait_until(function()
            return not IPC.vnavmesh.PathfindInProgress() and not IPC.vnavmesh.IsRunning()
        end, 240)
    else
        local cmd = USE_FLIGHT and "/vnav flyto " or "/vnav moveto "
        yield(cmd .. string.format("%.2f %.2f %.2f", spot.x, spot.y, spot.z))
        wait(30)
        yield("/vnav stop")
    end

    dismount()
    wait(1)
end

local function goto_spot(spot)
    log("→ " .. spot.name)
    teleport_to(AETHERYTE_NAME)
    move_to(spot)
end

------------------------------------------------------------------
-- 釣り ------------------------------------------------------------
------------------------------------------------------------------

local function setup_rig()
    yield('/item ' .. tostring(BAIT_ITEM_ID))
    wait(1.5)
    yield('/ahset "' .. AUTOHOOK_PRESET .. '"')
    yield("/ahon")
    wait(1)
    if NEEDS_COLLECTABLE then
        yield('/ac "収集品採集"')
        wait(1)
    end
end

local function cast()
    yield('/ac "キャスティング"')
    wait(2)
end

local function quit_fishing()
    if cond(COND.fishing) then
        yield('/ac "おさめる"')
        wait_until(function() return not cond(COND.fishing) end, 6)
        wait(1)
    end
end

-- 1 ポイント分の釣りループ
-- return: "inv_full" | "timeout" | "done"
local function fish_at_spot(duration_sec)
    setup_rig()
    local start_t = os.time()
    if not cond(COND.fishing) then cast() end

    while (os.time() - start_t) < duration_sec do
        if free_slots() <= INVENTORY_FREE_LIMIT then
            return "inv_full"
        end
        if item_count(SAND_ITEM_ID) >= TARGET_SAND_COUNT then
            return "done"
        end
        if not cond(COND.fishing) and not cond(COND.casting) then
            cast()
        end
        wait(2)
    end
    return "timeout"
end

local function stop_fishing()
    yield("/ahoff")
    wait(0.5)
    quit_fishing()
end

------------------------------------------------------------------
-- 精選 (Aetherial Reduction) --------------------------------------
------------------------------------------------------------------

local function reduce_all()
    log("精選開始  fish=" .. item_count(FISH_ITEM_ID))
    local safety = 0
    while item_count(FISH_ITEM_ID) > 0 and safety < 500 do
        yield('/ac "精選"')
        wait(1)
        yield('/item ' .. tostring(FISH_ITEM_ID))
        wait(1)
        wait_until(function() return not cond(COND.casting) end, 15)
        wait(0.5)
        safety = safety + 1
        if item_count(SAND_ITEM_ID) >= TARGET_SAND_COUNT then break end
    end
    log("精選完了  sand=" .. item_count(SAND_ITEM_ID))
end

------------------------------------------------------------------
-- メインループ ----------------------------------------------------
------------------------------------------------------------------

local function main()
    log("開始: 目標 紫電の霊砂 " .. TARGET_SAND_COUNT .. " 個")
    local idx = 1
    while item_count(SAND_ITEM_ID) < TARGET_SAND_COUNT do
        goto_spot(FISHING_SPOTS[idx])
        local reason = fish_at_spot(TIME_PER_SPOT_SEC)
        stop_fishing()

        if reason == "inv_full" then
            reduce_all()
        elseif reason == "done" then
            break
        end
        idx = idx % #FISHING_SPOTS + 1
    end
    log("完了: 紫電の霊砂 " .. item_count(SAND_ITEM_ID) .. " 個")
end

main()
