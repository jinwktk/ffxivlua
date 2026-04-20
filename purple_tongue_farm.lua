--[[=====================================================================
  紫の舌先 釣り & 精選(紫電の霊砂)自動化スクリプト for SomethingNeedDoing
  ---------------------------------------------------------------------
  概要:
    - 事前登録した 3 つの釣り場をローテーション（一定時間で移動）
    - インベントリが一杯になったら精選(Aetherial Reduction)で
      紫電の霊砂を取り出す
    - 紫電の霊砂を目標数集めたら終了
  前提プラグイン (SND に以下が入っていること):
    - SomethingNeedDoing (Expanded Edition 推奨)
    - vnavmesh           （地上移動 /vnav flyto）
    - Lifestream         （エーテライトTP /li tp）
    - AutoHook           （合わせ自動化 /ahset preset）
    - Artisan (任意)     （精選ループ時のウィンドウ操作補助）
  参考:
    https://github.com/Jaksuhn/SomethingNeedDoing
    https://github.com/pot0to/pot0to-SND-Scripts/
    https://github.com/lycopersicon-esculentum/ffxiv-snd-scripts
  使い方:
    1. 下の「ユーザー設定」の値を埋める
    2. 漁師でログイン、インベントリを空けて実行
=====================================================================]]

------------------------------------------------------------------
-- ユーザー設定 ----------------------------------------------------
------------------------------------------------------------------

-- 紫の舌先 (Purple Tongue) の ItemId  ※要確認
local FISH_ITEM_ID          = 44131
-- 紫電の霊砂 (Purple Lightning Sand) の ItemId  ※要確認
local SAND_ITEM_ID          = 44137
-- 収集目標数（紫電の霊砂）
local TARGET_SAND_COUNT     = 99

-- 使用する餌 ItemId  ※要確認 (例: ヴァーサタイル・ルアー等)
local BAIT_ITEM_ID          = 29717

-- AutoHook プリセット名（事前に AutoHook に登録しておく）
local AUTOHOOK_PRESET       = "紫の舌先"

-- 1 ポイントあたりの滞在時間 (秒)
local TIME_PER_SPOT_SEC     = 900        -- 15 分

-- 釣り場 3 箇所: aetheryte は Lifestream のエーテライト名 or ID
-- 座標はワールドワールド座標 (Position)。
-- タイプ: "fly" = /vnav flyto, "walk" = /vnav moveto
local FISHING_SPOTS = {
    { name = "ポイント1", aetheryte = "フィーストファイアズ",
      x = 0.0, y = 0.0, z = 0.0, mount = true, type = "fly" },
    { name = "ポイント2", aetheryte = "フィーストファイアズ",
      x = 0.0, y = 0.0, z = 0.0, mount = true, type = "fly" },
    { name = "ポイント3", aetheryte = "フィーストファイアズ",
      x = 0.0, y = 0.0, z = 0.0, mount = true, type = "fly" },
}

-- 精選対象が収集品扱い（漁獲時に収集品ONが必要）か
local NEEDS_COLLECTABLE     = true

-- インベントリ満杯判定: 空きスロット数がこの値以下になったら精選へ
local INVENTORY_FREE_LIMIT  = 1

-- デバッグ出力
local DEBUG = true

------------------------------------------------------------------
-- ヘルパー --------------------------------------------------------
------------------------------------------------------------------

local function log(msg)
    if DEBUG then yield("/echo [PTF] " .. tostring(msg)) end
end

local function wait(sec)
    yield("/wait " .. tostring(sec))
end

-- キャストなど、特定状態になるまで待つ
local function wait_until(cond_fn, timeout_sec)
    local t = 0
    while not cond_fn() do
        yield("/wait 0.5")
        t = t + 0.5
        if timeout_sec and t > timeout_sec then return false end
    end
    return true
end

-- アイテム個数（全インベントリ合計）
local function item_count(id)
    return GetItemCount(id) or 0
end

-- 空きスロット数（SND 標準 API）
local function inventory_free_slots()
    if GetInventoryFreeSlotCount then
        return GetInventoryFreeSlotCount()
    end
    return 35  -- フォールバック
end

local function is_busy()
    return GetCharacterCondition(32) -- 32 = 釣り中(Fishing)
end

local function in_combat()
    return GetCharacterCondition(26)
end

------------------------------------------------------------------
-- 移動 ------------------------------------------------------------
------------------------------------------------------------------

local function teleport_to(aetheryte)
    log("テレポ: " .. aetheryte)
    yield("/li tp " .. aetheryte)
    -- テレポ完了まで
    wait_until(function() return not GetCharacterCondition(45) end, 30) -- 45 = BetweenAreas
    wait(3)
end

local function fly_to(spot)
    if spot.mount and not GetCharacterCondition(4) then  -- 4 = Mounted
        yield("/gaction マウント")
        wait(2)
        if spot.type == "fly" then
            yield("/gaction \"飛行\"") -- 騎乗後に上昇(環境により不要)
            wait(1)
        end
    end
    local cmd = (spot.type == "fly") and "/vnav flyto " or "/vnav moveto "
    yield(cmd .. string.format("%.1f %.1f %.1f", spot.x, spot.y, spot.z))
    -- 到着判定
    wait_until(function()
        local px, py, pz = GetPlayerRawXPos(), GetPlayerRawYPos(), GetPlayerRawZPos()
        if not px then return true end
        local dx, dy, dz = px - spot.x, py - spot.y, pz - spot.z
        return (dx*dx + dy*dy + dz*dz) < 9
    end, 180)
    yield("/vnav stop")
    if GetCharacterCondition(4) then
        yield("/gaction マウント")
        wait(2)
    end
end

local function go_to_spot(spot)
    log("移動: " .. spot.name)
    teleport_to(spot.aetheryte)
    fly_to(spot)
end

------------------------------------------------------------------
-- 釣り ------------------------------------------------------------
------------------------------------------------------------------

local function setup_fishing()
    -- 餌をセット
    yield("/item " .. tostring(BAIT_ITEM_ID))
    wait(1.5)
    -- AutoHook プリセット適用
    yield('/ahset "' .. AUTOHOOK_PRESET .. '"')
    yield("/ahon")
    wait(1)
    -- 収集品モード
    if NEEDS_COLLECTABLE then
        yield("/ac \"収集品採集\"")
        wait(1)
    end
end

local function cast()
    yield("/ac \"キャスティング\"")
    wait(3)
end

-- 1 ポイント分の釣りループ（時間切れ or インベントリ満杯で戻る）
local function fish_at_spot(duration_sec)
    setup_fishing()
    local start_t = os.time()
    while (os.time() - start_t) < duration_sec do
        if inventory_free_slots() <= INVENTORY_FREE_LIMIT then
            log("インベントリ満杯 → 精選へ")
            return "inv_full"
        end
        if item_count(SAND_ITEM_ID) >= TARGET_SAND_COUNT then
            return "done"
        end
        if not is_busy() then
            cast()
        end
        wait(2)
    end
    return "timeout"
end

local function stop_fishing()
    yield("/ahoff")
    if is_busy() then
        yield("/ac \"おさめる\"")
        wait(3)
    end
end

------------------------------------------------------------------
-- 精選 (Aetherial Reduction) --------------------------------------
------------------------------------------------------------------

-- 紫の舌先(収集品)を全て精選してインベントリを空ける
local function reduce_all()
    log("精選開始")
    local safety = 0
    while item_count(FISH_ITEM_ID) > 0 and safety < 400 do
        -- 精選アクションを実行してから対象アイテム指定
        yield("/ac \"精選\"")
        wait(1)
        yield("/item " .. tostring(FISH_ITEM_ID))
        wait(1)
        -- 精選演出が終わるまで
        wait_until(function() return not GetCharacterCondition(38) end, 15) -- 38 = Crafting/Reducing
        wait(0.5)
        safety = safety + 1
        if item_count(SAND_ITEM_ID) >= TARGET_SAND_COUNT then
            break
        end
    end
    log("精選完了 sand=" .. item_count(SAND_ITEM_ID))
end

------------------------------------------------------------------
-- メインループ ----------------------------------------------------
------------------------------------------------------------------

local function main()
    log("開始: 目標 紫電の霊砂 " .. TARGET_SAND_COUNT .. " 個")
    local idx = 1
    while item_count(SAND_ITEM_ID) < TARGET_SAND_COUNT do
        local spot = FISHING_SPOTS[idx]
        go_to_spot(spot)
        local reason = fish_at_spot(TIME_PER_SPOT_SEC)
        stop_fishing()

        if reason == "inv_full" then
            reduce_all()
        elseif reason == "done" then
            break
        end
        -- 次のポイントへ
        idx = idx % #FISHING_SPOTS + 1
    end
    log("完了: 紫電の霊砂 " .. item_count(SAND_ITEM_ID) .. " 個")
end

main()
