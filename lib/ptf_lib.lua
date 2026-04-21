--[==[
  ptf_lib.lua — 紫の舌先 釣り自動化 ライブラリ本体
  ------------------------------------------------------
  このファイルはメインスクリプト (purple_tongue_farm.lua) から
  SND の File Dependency 経由で読み込まれる想定。
  エントリポイントは PTF.run(opts).
]==]

------------------------------------------------------------------
-- バージョン (git pre-commit hook で自動置換) --------------------
------------------------------------------------------------------
local LIB_VERSION = "22207bb"                -- AUTO-UPDATED BY HOOK
local LIB_BUILD   = "2026-04-21 13:14"                -- AUTO-UPDATED BY HOOK

------------------------------------------------------------------
-- 固定 ItemId ----------------------------------------------------
------------------------------------------------------------------
local FISH_ITEM_ID = 46249  -- 紫の舌先 (収集品)
local SAND_ITEM_ID = 46246  -- 紫電の霊砂

------------------------------------------------------------------
-- CharacterCondition --------------------------------------------
------------------------------------------------------------------
local COND = {
    mounted      = 4,
    casting      = 27,
    fishing      = 43,
    betweenAreas = 45,
    loadingZone  = 51,  -- 転送中 (betweenAreas と同時に立つ)
}

------------------------------------------------------------------
-- PTF モジュール -------------------------------------------------
------------------------------------------------------------------
local PTF = {}

-- ランタイム設定 (run() で opts から注入される)
local cfg = {}

------------------------------------------------------------------
-- ログ (ファイル + /echo) ---------------------------------------
------------------------------------------------------------------
local LOG_FILE_PATH = "C:\\Users\\mlove\\Documents\\GitHub\\ffxivlua\\ptf.log"
local _log_file = nil
local function _open_log()
    if _log_file then return true end
    local ok, f = pcall(io.open, LOG_FILE_PATH, "a")
    if ok and f then
        _log_file = f
        _log_file:write(string.format(
            "==== session start %s | lib_ver=%s build=%s ====\n",
            os.date("%Y-%m-%d %H:%M:%S"), LIB_VERSION, LIB_BUILD))
        _log_file:flush()
        return true
    end
    return false
end

local function wait(sec) yield("/wait " .. tostring(sec)) end

-- log / _dalamud_log は safe_get 定義後 (下の SND API ユーティリティ内) で定義する

------------------------------------------------------------------
-- SND API アクセスユーティリティ --------------------------------
------------------------------------------------------------------
local function safe_index(obj, key)
    if obj == nil then return nil end
    local ok, v = pcall(function() return obj[key] end)
    if ok then return v end
    return nil
end

local function safe_get(path)
    local obj = _G
    for seg in string.gmatch(path, "[^.]+") do
        if obj == nil then return nil end
        if type(obj) == "table" then
            obj = rawget(obj, seg)
        else
            obj = safe_index(obj, seg)
        end
    end
    return obj
end

-- Dalamud ロガー (safe_get 定義後に配置)
local function _dalamud_log(msg, level)
    level = level or "Log"
    local fn = safe_get("Dalamud." .. level) or safe_get("Dalamud.Log")
    if fn then pcall(fn, msg) end
end

local function log(msg, level)
    local line = "[PTF] " .. tostring(msg)
    if cfg.debug then _dalamud_log(line, level or "Log") end
    if _open_log() then
        pcall(function()
            _log_file:write(os.date("%H:%M:%S ") .. line .. "\n")
            _log_file:flush()
        end)
    end
end

local function log_debug(msg)   log(msg, "LogDebug")   end
local function log_verbose(msg) log(msg, "LogVerbose") end

local function cond(id)
    local svc = rawget(_G, "Svc")
    if svc == nil then return false end
    local c = safe_index(svc, "Condition")
    return c and safe_index(c, id) == true
end

-- 汎用: path で指定した API 関数を呼んで値を返す (失敗時 default)
local function call_api(path, default, ...)
    local fn = safe_get(path)
    if type(fn) == "userdata" or type(fn) == "function" then
        local ok, v = pcall(fn, ...)
        if ok then
            if type(v) == "number" then return v end
            if type(v) == "boolean" then return v end
            return v
        end
    end
    return default
end

-- 汎用: 数値戻り API を tonumber で正規化
local function call_api_num(path, default, ...)
    local v = call_api(path, default, ...)
    return tonumber(v) or default
end

local function item_count(id)
    return call_api_num("Inventory.GetItemCount", 0, id)
end

-- 収集品 (HQ / collectable) を含めた総数
local function fish_count(id)
    local total = item_count(id)
    local hq = call_api_num("Inventory.GetItemCount", nil, id, true)
    if hq and hq > total then total = hq end
    total = total + (call_api_num("Inventory.GetCollectableItemCount", 0, id, 1) or 0)
    total = total + (call_api_num("Inventory.GetHQItemCount", 0, id) or 0)
    return total
end

local function free_slots()
    return call_api_num("Inventory.GetFreeInventorySlots", 35)
end

-- より細かいポーリングで反応を早くする (0.25秒刻み)
local function wait_until(fn, timeout_sec, step)
    step = step or 0.25
    local t = 0
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

local function zone_id()
    local svc = rawget(_G, "Svc")
    local cs = safe_index(svc, "ClientState")
    local v = safe_index(cs, "TerritoryType")
    return v and tonumber(v)
end

local function player_pos()
    local p = player_obj()
    if not p then return nil end
    local pos = safe_index(p, "Position")
    if not pos then return nil end
    return safe_index(pos, "X"), safe_index(pos, "Y"), safe_index(pos, "Z")
end

local function dist_xz(ax, az, bx, bz)
    local dx, dz = ax - bx, az - bz
    return math.sqrt(dx * dx + dz * dz)
end

local function distance_to(x, y, z)
    local px, py, pz = player_pos()
    if not px then return nil end
    local dx, dy, dz = px - x, (py or 0) - (y or 0), pz - z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function path_running() return call_api("IPC.vnavmesh.IsRunning", false) == true end
local function pathfind_in_progress() return call_api("IPC.vnavmesh.PathfindInProgress", false) == true end
local function vnav_busy() return path_running() or pathfind_in_progress() end

------------------------------------------------------------------
-- 移動 ------------------------------------------------------------
------------------------------------------------------------------
local function already_near_spots()
    local px, _, pz = player_pos()
    log(string.format("位置判定 pos=(%s,%s) zoneId=%s",
        tostring(px), tostring(pz), tostring(zone_id())))
    if not px then return false end
    for i, s in ipairs(cfg.spots) do
        local d = dist_xz(px, pz, s.x, s.z)
        log(string.format("  spot%d 距離=%.1f", i, d))
        if d <= 500 then
            log("  → 500以内、テレポ省略")
            return true
        end
    end
    return false
end

local function teleport_to(aetheryte)
    if already_near_spots() then return end

    log("テレポ: " .. aetheryte)
    local li_exec = safe_get("IPC.Lifestream.ExecuteCommand")
    if li_exec then
        pcall(li_exec, aetheryte)
    else
        yield('/li ' .. aetheryte)
    end

    -- 転送開始まで最大8秒、完了まで最大60秒
    if wait_until(function() return cond(COND.betweenAreas) or cond(COND.loadingZone) end, 8) then
        wait_until(function() return not cond(COND.betweenAreas) and not cond(COND.loadingZone) end, 60)
        log("  テレポ完了 zoneId=" .. tostring(zone_id()))
        wait(1.5)  -- 3→1.5 ロード後の入力受付を最低限確保
    else
        log("  テレポ開始せず")
        wait(1)
    end
end

local function mount_up()
    if cond(COND.mounted) then return end
    log("マウント: /mount ウィング・オブ・ミスト")
    yield('/mount ウィング・オブ・ミスト')
    wait_until(function() return cond(COND.mounted) end, 8)
end

local function dismount()
    if not cond(COND.mounted) then return end
    local fn = safe_get("Actions.ExecuteGeneralAction")
    if fn then pcall(fn, 23) else yield('/gaction マウント解除') end
    wait_until(function() return not cond(COND.mounted) end, 4)
end

local function wait_arrival(spot, timeout_sec)
    local t, step, last_log = 0, 0.5, 0
    while t < timeout_sec do
        local d = distance_to(spot.x, spot.y, spot.z)
        if t - last_log >= 5 then
            log(string.format("  移動中 d=%s busy=%s",
                d and string.format("%.1f", d) or "?", tostring(vnav_busy())))
            last_log = t
        end
        if d and d <= 3.0 then return true end
        -- vnav 停止 + 起動から 3 秒経過 で到着/スタック判定
        if t > 3 and not vnav_busy() then
            return d and d <= 8.0
        end
        yield("/wait " .. step)
        t = t + step
    end
    return false
end

local function move_to(spot)
    local d = distance_to(spot.x, spot.y, spot.z)
    if d and d <= 5.0 then
        log(string.format("到着済 d=%.1f", d))
        return
    end

    if cfg.use_flight then mount_up() end

    local cmdv = cfg.use_flight and "/vnav flyto " or "/vnav moveto "
    yield(cmdv .. string.format("%.2f %.2f %.2f", spot.x, spot.y, spot.z))

    local arrived = wait_arrival(spot, 240)
    yield("/vnav stop")
    if not arrived then log("警告: 到達タイムアウト") end

    dismount()
end

-- 指定座標の方向に向ける (pointToFace)
-- IPC.vnavmesh.MoveTo (直接移動、pathfind せず) を試してダメなら /vnav moveto
local function face_point(fx, fy, fz)
    log(string.format("face (%.1f,%.1f,%.1f)", fx, fy, fz))

    -- 1st: IPC.vnavmesh.MoveTo (vectorList, fly?) 直接呼び出し
    local move_to = safe_get("IPC.vnavmesh.MoveTo")
    local pf_mv   = safe_get("IPC.vnavmesh.PathfindAndMoveTo")
    local started = false
    if move_to then
        local ok, err = pcall(move_to, {{X = fx, Y = fy, Z = fz}}, false)
        log("  IPC.vnavmesh.MoveTo ok=" .. tostring(ok) .. " err=" .. tostring(err))
        started = ok
    end
    if not started and pf_mv then
        local ok, err = pcall(pf_mv, {X = fx, Y = fy, Z = fz}, false)
        log("  IPC.vnavmesh.PathfindAndMoveTo ok=" .. tostring(ok) .. " err=" .. tostring(err))
        started = ok
    end
    if not started then
        yield(string.format("/vnav moveto %.2f %.2f %.2f", fx, fy, fz))
    end

    -- 動き出したら短時間だけ歩かせて (回頭主眼、水際から離れない)
    if wait_until(function() return path_running() end, 2) then
        wait(0.3)
        log("  回頭完了")
    else
        log("  path開始せず、向き未変更の可能性")
    end
    yield("/vnav stop")
    wait(0.2)
end

local function goto_spot(spot)
    log("→ " .. spot.name)
    teleport_to(cfg.aetheryte)
    move_to(spot)

    -- スポット固有 face があればそれを優先、なければ共通 cfg.face
    local f = spot.face or cfg.face
    if f then face_point(f.x, f.y, f.z) end

    -- キャスト前にマウントを必ず降りる
    if cond(COND.mounted) then
        log("キャスト前にマウント解除")
        dismount()
    end
end

------------------------------------------------------------------
-- 釣り / 精選 ----------------------------------------------------
------------------------------------------------------------------
-- 現在のクラスが漁師 (FSH=18) か判定
local function is_fisher()
    local p = player_obj()
    if not p then return false end
    local cj = safe_index(p, "ClassJob")
    if not cj then return false end
    -- ClassJob は LazyRow 構造が多く .RowId / .Id / .Value.RowId を試す
    local id = safe_index(cj, "RowId")
               or safe_index(cj, "Id")
               or (safe_index(cj, "Value") and safe_index(safe_index(cj, "Value"), "RowId"))
    return id == 18
end

local function ensure_fisher()
    if is_fisher() then return true end
    log("漁師以外 → /gearset change FSH")
    yield('/gearset change FSH')
    local ok = wait_until(is_fisher, 6)
    if not ok then
        log("  警告: 漁師に切替失敗 (FSH のギアセットを登録してください)")
    end
    return ok
end

local function setup_rig()
    ensure_fisher()
    log(string.format("setup_rig bait=%s preset=%s", tostring(cfg.bait), cfg.autohook_preset))
    yield('/bait ' .. tostring(cfg.bait))
    wait(0.8)
    yield('/ahpreset ' .. cfg.autohook_preset)
    yield("/ahon")
    wait(0.4)
    if cfg.needs_collectable then
        yield('/ac 収集品採集')
        wait(0.5)
    end
end

local function cast()
    if cond(COND.mounted) then dismount() end
    yield('/ac キャスティング')
    wait(1)
end

-- 釣り中フラグを確実に落とす。AutoHook off → おさめる → fishing=false 待機。
-- 精選前に必須 (釣り中は精選アクション不可)
local function quit_fishing()
    log("釣り終了")
    yield("/ahoff")
    wait(0.3)
    for i = 1, 3 do
        if not cond(COND.fishing) then break end
        yield('/ac 中断')
        wait_until(function() return not cond(COND.fishing) end, 3)
    end
    wait_until(function() return not cond(COND.casting) end, 3)
    log("  fishing=" .. tostring(cond(COND.fishing)))
end

local function fish_at_spot(duration_sec)
    log("fish_at_spot 開始 duration=" .. duration_sec)
    setup_rig()
    local start_t = os.time()
    log("  fishing条件: " .. tostring(cond(COND.fishing)))

    local max_cast_failures = 3
    local cast_failures = 0

    while (os.time() - start_t) < duration_sec do
        if free_slots() <= cfg.inventory_free_limit
           and fish_count(FISH_ITEM_ID) > 0 then
            return "inv_full"
        end
        if item_count(SAND_ITEM_ID) >= cfg.target then return "done" end

        if not cond(COND.fishing) and not cond(COND.casting) then
            cast()
            local ok = wait_until(function()
                return cond(COND.fishing) or cond(COND.casting)
            end, 5)
            if not ok then
                cast_failures = cast_failures + 1
                log(string.format("  キャスト失敗 %d/%d (釣り場外の可能性)",
                    cast_failures, max_cast_failures))
                if cast_failures >= max_cast_failures then
                    log("  → 次のポイントへ移動")
                    return "no_fish_spot"
                end
            else
                cast_failures = 0
            end
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

local function reduce_all()
    local n = fish_count(FISH_ITEM_ID)
    log("精選開始 fish=" .. n)
    if n <= 0 then
        log("  紫の舌先 0 → 精選スキップ")
        return
    end

    -- マウント中は精選不可 → 必ず降りる
    if cond(COND.mounted) then
        log("  精選前: マウント解除")
        dismount()
    end

    -- 精選が使えるのは Fisher (Lv60+ 精選解禁後)。GA id は 18 (精選)
    local use_item = safe_get("Inventory.UseItem")
    local exec_ga  = safe_get("Actions.ExecuteGeneralAction")
    log(string.format("  API check Inventory.UseItem=%s Actions.ExecuteGeneralAction=%s",
        tostring(type(use_item)), tostring(type(exec_ga))))

    local safety = 0
    local prev_fish = n
    while safety < 500 do
        local cur_fish = fish_count(FISH_ITEM_ID)
        log(string.format("  iter=%d fish=%d sand=%d", safety, cur_fish, item_count(SAND_ITEM_ID)))

        if cur_fish <= 0 then
            log("  舌先消費完了")
            break
        end
        if item_count(SAND_ITEM_ID) >= cfg.target then
            log("  目標到達")
            break
        end

        -- 精選アクション発動 (GA=21 が精選) → だめなら /ac 精選 フォールバック
        local opened = false
        if exec_ga then
            local ok = pcall(exec_ga, 21)
            log("  Actions.ExecuteGeneralAction(21) ok=" .. tostring(ok))
            opened = ok
        end
        if not opened then
            yield('/ac 精選')
            log("  /ac 精選 送信")
        end
        wait(1.5)

        -- PurifyItemSelector が表示されるのを待ってから callback
        local ok_visible = wait_until(function()
            local fn = safe_get("Addons.GetAddon")
                    or safe_get("Addons.IsAddonVisible")
                    or safe_get("IsAddonVisible")
            if fn then
                local ok, v = pcall(fn, "PurifyItemSelector")
                if ok then
                    if type(v) == "boolean" then return v end
                    if type(v) == "table" or type(v) == "userdata" then
                        local vis = safe_index(v, "Ready") or safe_index(v, "IsVisible")
                        if vis ~= nil then return vis == true end
                        return true   -- 取れたら表示されてるとみなす
                    end
                end
            end
            -- 取得不能時は条件で代替 (精選演出 = casting)
            return false
        end, 5)
        log("  PurifyItemSelector visible=" .. tostring(ok_visible))

        -- 表示されなくてもとりあえず callback を送ってみる
        yield('/callback PurifyItemSelector true 12 0')
        log("  /callback PurifyItemSelector true 12 0 送信")
        wait(1.5)

        -- 精選演出完了まで待機 (cast 条件が落ちる)
        wait_until(function() return not cond(COND.casting) end, 15)
        wait(0.5)

        -- 前回から減っていなければ異常
        local new_fish = fish_count(FISH_ITEM_ID)
        if new_fish >= prev_fish then
            log(string.format("  ※減っていない fish=%d→%d", prev_fish, new_fish))
            if safety >= 3 then
                log("  3回以上減少せず → 精選打ち切り")
                break
            end
        end
        prev_fish = new_fish

        safety = safety + 1
    end
    -- ループ終了後、PurifyResult が残っていれば閉じる
    yield('/callback PurifyResult true 0')
    wait(0.5)
    log("精選完了 fish=" .. fish_count(FISH_ITEM_ID) .. " sand=" .. item_count(SAND_ITEM_ID))
end

------------------------------------------------------------------
-- API 可用性ダンプ -----------------------------------------------
------------------------------------------------------------------
local function dump_api()
    log("=== SND API ===")
    local paths = {
        "Svc", "Svc.Condition", "Svc.ClientState.LocalPlayer",
        "Svc.ClientState.TerritoryType",
        "Inventory.GetItemCount", "Inventory.GetFreeInventorySlots",
        "Inventory.GetHQItemCount", "Inventory.GetCollectableItemCount",
        "Inventory.UseItem",
        "IPC.Lifestream.ExecuteCommand", "IPC.vnavmesh.PathfindAndMoveTo",
        "Actions.ExecuteGeneralAction", "Config.Get",
    }
    for _, p in ipairs(paths) do
        log(string.format("  %-42s = %s", p, type(safe_get(p))))
    end
end

------------------------------------------------------------------
-- エントリポイント -----------------------------------------------
------------------------------------------------------------------
-- ログファイルをクローズ (run 終了時に呼ぶ)
local function close_log()
    if _log_file then
        pcall(function() _log_file:close() end)
        _log_file = nil
    end
end

function PTF.run(opts)
    cfg = opts or {}
    cfg.spots              = cfg.spots              or {}
    assert(#cfg.spots > 0, "cfg.spots は 1 つ以上必要")
    cfg.target             = cfg.target             or 99
    cfg.time_per_spot      = cfg.time_per_spot      or 900
    cfg.inventory_free_limit = cfg.inventory_free_limit or 1
    cfg.bait               = cfg.bait               or "29717"
    cfg.autohook_preset    = cfg.autohook_preset    or "紫の舌先"
    cfg.aetheryte          = cfg.aetheryte          or "朋友の灯火"
    cfg.use_flight         = cfg.use_flight ~= false
    cfg.needs_collectable  = cfg.needs_collectable ~= false
    cfg.debug              = cfg.debug ~= false
    -- 共通 pointToFace (すべてのスポットで同じ方角を向かせる場合)
    -- cfg.face = {x=..., y=..., z=...} が渡されれば採用、なければ個別 spot.face のみ
    cfg.face               = cfg.face

    log(string.format("=== purple_tongue_farm lib_ver=%s build=%s ===",
        LIB_VERSION, LIB_BUILD))
    dump_api()
    local px, py, pz = player_pos()
    log(string.format("現在位置 pos=(%s,%s,%s) zoneId=%s",
        tostring(px), tostring(py), tostring(pz), tostring(zone_id())))
    log(string.format("設定 aetheryte=%s bait=%s preset=%s target=%d time=%d",
        cfg.aetheryte, tostring(cfg.bait), cfg.autohook_preset,
        cfg.target, cfg.time_per_spot))

    local idx = 1
    while item_count(SAND_ITEM_ID) < cfg.target do
        goto_spot(cfg.spots[idx])

        -- 釣り開始前のインベントリ空きチェック
        local free = free_slots()
        local fish = fish_count(FISH_ITEM_ID)
        log(string.format("釣り前チェック  空き=%d 舌先=%d", free, fish))
        if fish > 0 then
            -- 舌先があれば常に精選してから釣り始める (インベ空きを最大化)
            log("  舌先あり → 釣り前に精選実行")
            reduce_all()
        elseif free <= cfg.inventory_free_limit then
            -- 空きなし かつ 舌先0 → 精選対象なしで中断
            log("  ERROR: インベ満杯かつ舌先0 → 精選不能のため中断")
            log("  不要アイテムを整理してから再実行してください")
            break
        end

        local reason = fish_at_spot(cfg.time_per_spot)
        stop_fishing()
        if reason == "inv_full" then reduce_all()
        elseif reason == "done" then break end
        idx = idx % #cfg.spots + 1
    end
    log("完了: sand=" .. item_count(SAND_ITEM_ID))
    close_log()
end

-- 外部からもクローズ可能に
PTF.close = close_log

-- SND の File Dependency は毎回ロードするため、常に最新を _G.PTF に入れる
_G.PTF = PTF
return PTF
