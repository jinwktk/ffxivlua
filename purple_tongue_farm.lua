--[[=====================================================================
  紫の舌先 釣り & 精選(紫電の霊砂) 自動化スクリプト for SomethingNeedDoing
  ---------------------------------------------------------------------
  概要:
    - 事前登録した 3 つの釣り場をローテーション（一定時間で移動）
    - インベントリが一杯になったら精選(Aetherial Reduction)で
      紫電の霊砂を取り出す
    - 紫電の霊砂を目標数集めたら終了

  前提プラグイン:
    - SomethingNeedDoing (Expanded Edition)
    - vnavmesh
    - Lifestream
    - AutoHook

  参考:
    https://github.com/Jaksuhn/SomethingNeedDoing
    https://github.com/pot0to/pot0to-SND-Scripts/
    https://github.com/lycopersicon-esculentum/ffxiv-snd-scripts
=====================================================================]]

------------------------------------------------------------------
-- ユーザー設定 ----------------------------------------------------
------------------------------------------------------------------

-- 紫の舌先 (収集品)  GarlandTools 確認済み
local FISH_ITEM_ID          = 46249
-- 紫電の霊砂 の ItemId   GarlandTools 確認済み
local SAND_ITEM_ID          = 46246
-- 目標数（紫電の霊砂）
local TARGET_SAND_COUNT     = 99

-- 使用する餌 ItemId（漁師の釣り餌）  ※要確認
local BAIT_ITEM_ID          = 29717

-- AutoHook プリセット名（事前に AutoHook に登録しておく）
local AUTOHOOK_PRESET       = "紫の舌先"

-- 1 ポイントあたりの滞在時間 (秒)
local TIME_PER_SPOT_SEC     = 900         -- 15 分

-- 釣り場 3 箇所
--   aetheryte : Lifestream に渡すエーテライト名（日本語名可）
--   x,y,z     : ワールド座標
--   fly       : 飛行で移動するか
local FISHING_SPOTS = {
    { name = "ポイント1", aetheryte = "朋友の灯火",
      x =   6.215, y =  25.185, z =  24.578, fly = true },
    { name = "ポイント2", aetheryte = "朋友の灯火",
      x = -24.975, y =  21.487, z = -58.947, fly = true },
    { name = "ポイント3", aetheryte = "朋友の灯火",
      x = 158.372, y =  24.070, z = -17.322, fly = true },
}

-- 紫の舌先は収集品でのみ精選可 → true のまま
local NEEDS_COLLECTABLE     = true

-- インベントリ空きスロットがこの値以下 → 精選へ
local INVENTORY_FREE_LIMIT  = 1

local DEBUG                 = true

------------------------------------------------------------------
-- 定数: CharacterCondition ---------------------------------------
------------------------------------------------------------------
local COND = {
    mounted      = 4,
    casting      = 27,
    fishing      = 43,
    betweenAreas = 45,
}

-- Action IDs（必要な場合は固定IDで直接叩ける。未使用でも保持）
local ACTION = {
    cast_fishing   = 289,   -- キャスティング
    quit_fishing   = 299,   -- おさめる
}

-- GeneralAction IDs
local GA = {
    mount_roulette = 9,
    dismount       = 23,
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
    -- SND 標準: Svc.Condition[id]
    if Svc and Svc.Condition then
        return Svc.Condition[id] == true
    end
    -- フォールバック（旧 SND）
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
    yield("/gaction \"マウント解除\"")
    wait_until(function() return not cond(COND.mounted) end, 5)
end

local function move_to(spot)
    if spot.fly then mount_up() end

    if IPC and IPC.vnavmesh and IPC.vnavmesh.PathfindAndMoveTo then
        IPC.vnavmesh.PathfindAndMoveTo({x = spot.x, y = spot.y, z = spot.z}, spot.fly or false)
        wait_until(function()
            return not IPC.vnavmesh.PathfindInProgress() and not IPC.vnavmesh.IsRunning()
        end, 240)
    else
        -- フォールバック: /vnav コマンド
        local cmd = spot.fly and "/vnav flyto " or "/vnav moveto "
        yield(cmd .. string.format("%.2f %.2f %.2f", spot.x, spot.y, spot.z))
        wait_until(function()
            -- 停止判定は距離で（座標APIが無ければ概ね時間で切る）
            return false
        end, 240)
        yield("/vnav stop")
    end

    dismount()
    wait(1)
end

local function goto_spot(spot)
    log("→ " .. spot.name)
    teleport_to(spot.aetheryte)
    move_to(spot)
end

------------------------------------------------------------------
-- 釣り ------------------------------------------------------------
------------------------------------------------------------------

local function setup_rig()
    -- 餌セット
    yield('/item ' .. tostring(BAIT_ITEM_ID))
    wait(1.5)
    -- AutoHook プリセット
    yield('/ahset "' .. AUTOHOOK_PRESET .. '"')
    yield("/ahon")
    wait(1)
    -- 収集品モード
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
    -- 初キャスト
    if not cond(COND.fishing) then cast() end

    while (os.time() - start_t) < duration_sec do
        if free_slots() <= INVENTORY_FREE_LIMIT then
            return "inv_full"
        end
        if item_count(SAND_ITEM_ID) >= TARGET_SAND_COUNT then
            return "done"
        end
        -- AutoHook が拾って勝手に合わせ→次キャストに進む想定
        -- 釣り状態が切れていたら再キャスト
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
        -- 精選ウィンドウを開く → 対象アイテムを指定
        yield('/ac "精選"')
        wait(1)
        yield('/item ' .. tostring(FISH_ITEM_ID))
        wait(1)
        -- 精選演出（キャスト中扱い）
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
