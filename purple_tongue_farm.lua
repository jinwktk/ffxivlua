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
    default: "29717"
    description: 使用する餌 (AutoHook /bait の引数。ItemId または餌名 例 "ラグワーム")
    type: string
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
-- バージョン識別（git pre-commit hook で自動置換される） ----------
------------------------------------------------------------------
local SCRIPT_VERSION = "cfb0bc4"          -- AUTO-UPDATED BY HOOK
local SCRIPT_BUILD   = "2026-04-20 17:45" -- AUTO-UPDATED BY HOOK

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
local BAIT_ITEM_ID         = cfg("bait_item_id", "29717")
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

------------------------------------------------------------------
-- ファイルログ (リポジトリ直下 ptf.log に追記) ---------------------
------------------------------------------------------------------
local LOG_FILE_PATH = "C:\\Users\\mlove\\Documents\\GitHub\\ffxivlua\\ptf.log"
local _log_file = nil
local function _open_log()
    if _log_file then return true end
    local ok, f = pcall(io.open, LOG_FILE_PATH, "a")
    if ok and f then
        _log_file = f
        _log_file:write(string.format(
            "==== session start %s | ver=%s build=%s ====\n",
            os.date("%Y-%m-%d %H:%M:%S"), SCRIPT_VERSION, SCRIPT_BUILD))
        _log_file:flush()
        return true
    end
    return false
end

local function log(msg)
    local line = "[PTF] " .. tostring(msg)
    if DEBUG then yield("/echo " .. line) end
    if _open_log() then
        pcall(function()
            _log_file:write(os.date("%H:%M:%S ") .. line .. "\n")
            _log_file:flush()
        end)
    end
end

local function wait(sec)
    yield("/wait " .. tostring(sec))
end

-- SND Expanded Edition は Svc (userdata) / Inventory / IPC などの名前空間
-- userdata への field アクセスは pcall + . 構文でやる必要がある
local function safe_get(path)
    local obj = _G
    local first = true
    for seg in string.gmatch(path, "[^.]+") do
        if obj == nil then return nil end
        local t = type(obj)
        if first and t == "table" then
            obj = rawget(obj, seg)
        elseif t == "table" then
            obj = rawget(obj, seg)
        elseif t == "userdata" or t == "table" then
            local ok, v = pcall(function() return obj[seg] end)
            obj = ok and v or nil
        else
            -- 関数やプリミティブは辿れない
            local ok, v = pcall(function() return obj[seg] end)
            obj = ok and v or nil
        end
        first = false
    end
    return obj
end

-- userdata の index を pcall でアクセス
local function safe_index(obj, key)
    if obj == nil then return nil end
    local ok, v = pcall(function() return obj[key] end)
    if ok then return v end
    return nil
end

local function cond(id)
    -- Svc は userdata 前提。.Condition 経由でインデクサに渡す
    local svc = rawget(_G, "Svc")
    if svc == nil then return false end
    local c = safe_index(svc, "Condition")
    if c == nil then return false end
    local v = safe_index(c, id)
    return v == true
end

local function item_count(id)
    local fn = safe_get("Inventory.GetItemCount")
    if fn then
        local ok, v = pcall(fn, id)
        if ok then return tonumber(v) or 0 end
    end
    return 0
end

local function free_slots()
    local fn = safe_get("Inventory.GetFreeInventorySlots")
    if fn then
        local ok, v = pcall(fn)
        if ok then return tonumber(v) or 0 end
    end
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
-- プレイヤー状態 / 位置 ------------------------------------------
------------------------------------------------------------------

local function player_obj()
    local svc = rawget(_G, "Svc")
    local cs = safe_index(svc, "ClientState")
    return safe_index(cs, "LocalPlayer")
end

local function client_state()
    local svc = rawget(_G, "Svc")
    return safe_index(svc, "ClientState")
end

local function player_ready()
    local p = player_obj()
    return p ~= nil
end

local function player_casting()
    local p = player_obj()
    if not p then return false end
    local ok, v = pcall(function() return p.IsCasting end)
    return ok and v == true
end

local function path_running()
    local fn = safe_get("IPC.vnavmesh.IsRunning")
    if fn then
        local ok, v = pcall(fn)
        return ok and v == true
    end
    return false
end

local function pathfind_in_progress()
    local fn = safe_get("IPC.vnavmesh.PathfindInProgress")
    if fn then
        local ok, v = pcall(fn)
        return ok and v == true
    end
    return false
end

local function zone_id()
    local cs = client_state()
    if cs == nil then return nil end
    local v = safe_index(cs, "TerritoryType")
    if v ~= nil then return tonumber(v) end
    return nil
end

local function player_pos()
    local p = player_obj()
    if not p then return nil, nil, nil end
    local pos = safe_index(p, "Position")
    if not pos then return nil, nil, nil end
    local x = safe_index(pos, "X")
    local y = safe_index(pos, "Y")
    local z = safe_index(pos, "Z")
    if x ~= nil and y ~= nil and z ~= nil then
        return x, y, z
    end
    return nil, nil, nil
end

local function distance_to(x, y, z)
    local px, py, pz = player_pos()
    if not px then return nil end
    local dx, dy, dz = px - x, (py or 0) - (y or 0), pz - z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function dist_xz(ax, az, bx, bz)
    local dx, dz = ax - bx, az - bz
    return math.sqrt(dx * dx + dz * dz)
end

------------------------------------------------------------------
-- 移動 ------------------------------------------------------------
------------------------------------------------------------------

-- 既に目的地付近 (釣り場いずれかに近い) ならテレポ省略
local function already_near_spots()
    local px, _, pz = player_pos()
    log(string.format("位置判定  pos=(%s,%s,%s) zoneId=%s",
        tostring(px), "…", tostring(pz), tostring(zone_id())))
    if not px then return false end
    for i, s in ipairs(FISHING_SPOTS) do
        local d = dist_xz(px, pz, s.x, s.z)
        log(string.format("  spot%d 距離=%.1f", i, d))
        if d <= 500 then
            log("  → 500以内、テレポ省略")
            return true
        end
    end
    return false
end

-- Lifestream によるテレポ (Svc.Condition[45]/[51] で完了検出)
local function teleport_to(aetheryte)
    if already_near_spots() then return end

    log("テレポ: " .. aetheryte)

    -- IPC.Lifestream.ExecuteCommand が使えるならそちらを優先
    local li_exec = safe_get("IPC.Lifestream.ExecuteCommand")
    if li_exec then
        local ok = pcall(li_exec, aetheryte)
        log("  IPC.Lifestream.ExecuteCommand  ok=" .. tostring(ok))
    else
        yield('/li ' .. aetheryte)
        log("  /li コマンド送信")
    end

    -- テレポ開始を待つ (betweenAreas = 45, betweenAreas51 = 51)
    local started = wait_until(function()
        return cond(45) or cond(51)
    end, 10)
    log("  テレポ開始: " .. tostring(started))

    -- 到着待ち
    if started then
        wait_until(function()
            return not cond(45) and not cond(51)
        end, 60)
        log("  テレポ完了 zoneId=" .. tostring(zone_id()))
        wait(3)
    else
        log("  警告: テレポ開始せず、続行")
        wait(3)
    end
end

local function mount_up()
    if cond(COND.mounted) then
        log("既にマウント中")
        return
    end
    log("マウント開始")
    -- 優先: Actions.ExecuteGeneralAction(9) = マウントルーレット
    local fn = safe_get("Actions.ExecuteGeneralAction")
    if fn then
        pcall(fn, 9)
    else
        yield('/gaction "マウントルーレット"')
    end
    local ok = wait_until(function() return cond(COND.mounted) end, 8)
    if not ok then
        log("  マウント失敗、/mount フォールバック")
        yield('/mount "Company Chocobo"')
        wait_until(function() return cond(COND.mounted) end, 5)
    end
    wait(1)
    log("  マウント完了: " .. tostring(cond(COND.mounted)))
end

local function dismount()
    if not cond(COND.mounted) then return end
    log("マウント解除")
    local fn = safe_get("Actions.ExecuteGeneralAction")
    if fn then
        pcall(fn, 23)  -- マウント解除
    else
        yield('/gaction "マウント解除"')
    end
    wait_until(function() return not cond(COND.mounted) end, 5)
end

local function wait_arrival(spot, timeout_sec)
    local t, step = 0, 1.0
    local last_log = 0
    while t < timeout_sec do
        local d = distance_to(spot.x, spot.y, spot.z)
        -- 5 秒おきに進捗ログ
        if t - last_log >= 5 then
            log(string.format("  移動中 d=%s pathfind=%s path=%s",
                d and string.format("%.1f", d) or "?",
                tostring(pathfind_in_progress()),
                tostring(path_running())))
            last_log = t
        end
        if d and d <= 3.0 then return true end
        -- vnavmesh が停止 かつ距離 5 以内 なら到達とみなす
        if t > 5 and not path_running() and not pathfind_in_progress() then
            if d and d <= 8.0 then return true end
            -- スタック検知: 距離が大きく変わらず path 停止
            log("  警告: path 停止、d=" .. tostring(d))
            return false
        end
        yield("/wait " .. step)
        t = t + step
    end
    return false
end

local function move_to(spot)
    local d = distance_to(spot.x, spot.y, spot.z)
    if d and d <= 5.0 then
        log("目的地に到着済 (d=" .. string.format("%.1f", d) .. ")")
        return
    end

    if USE_FLIGHT then mount_up() end

    local cmd = USE_FLIGHT and "/vnav flyto " or "/vnav moveto "
    yield(cmd .. string.format("%.2f %.2f %.2f", spot.x, spot.y, spot.z))

    local arrived = wait_arrival(spot, 240)
    yield("/vnav stop")
    wait(1)

    if not arrived then
        log("警告: 到達タイムアウト、続行")
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
    log("setup_rig 開始")
    -- AutoHook /bait コマンドで餌セット
    log("  /bait " .. tostring(BAIT_ITEM_ID))
    yield('/bait ' .. tostring(BAIT_ITEM_ID))
    wait(1.5)
    log("  AutoHook プリセット=" .. AUTOHOOK_PRESET)
    yield('/ahpreset "' .. AUTOHOOK_PRESET .. '"')
    yield("/ahon")
    wait(1)
    if NEEDS_COLLECTABLE then
        log("  収集品採集 ON")
        yield('/ac "収集品採集"')
        wait(1)
    end
    log("setup_rig 完了")
end

local function cast()
    log("キャスティング")
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
    log("fish_at_spot 開始 duration=" .. duration_sec)
    setup_rig()
    local start_t = os.time()
    log("  fishing条件: " .. tostring(cond(COND.fishing)))
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

-- 起動時に SND 名前空間 API の利用可能性をダンプ
local function dump_api_availability()
    log("=== SND Namespace API チェック ===")
    local paths = {
        "Svc", "Svc.Condition", "Svc.ClientState",
        "Svc.ClientState.LocalPlayer", "Svc.ClientState.TerritoryType",
        "Inventory", "Inventory.GetItemCount", "Inventory.GetFreeInventorySlots",
        "IPC", "IPC.Lifestream", "IPC.Lifestream.ExecuteCommand",
        "IPC.vnavmesh", "IPC.vnavmesh.PathfindAndMoveTo",
        "IPC.vnavmesh.IsRunning", "IPC.vnavmesh.PathfindInProgress",
        "Actions", "Actions.ExecuteAction", "Actions.ExecuteGeneralAction",
        "Config", "Config.Get",
    }
    for _, p in ipairs(paths) do
        local v = safe_get(p)
        log(string.format("  %-42s = %s", p, type(v)))
    end
    log("======================")
end

local function main()
    log(string.format("=== purple_tongue_farm ver=%s build=%s ===",
        SCRIPT_VERSION, SCRIPT_BUILD))
    dump_api_availability()
    local px, py, pz = player_pos()
    log(string.format("現在位置 pos=(%s,%s,%s) zoneId=%s",
        tostring(px), tostring(py), tostring(pz), tostring(zone_id())))
    log(string.format("設定  aetheryte=%s bait=%d preset=%s target=%d time=%d",
        AETHERYTE_NAME, BAIT_ITEM_ID, AUTOHOOK_PRESET,
        TARGET_SAND_COUNT, TIME_PER_SPOT_SEC))
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
