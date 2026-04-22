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
local LIB_VERSION = "5a5b9e8"                -- AUTO-UPDATED BY HOOK
local LIB_BUILD   = "2026-04-22 20:28"                -- AUTO-UPDATED BY HOOK

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
-- 状態機械 (FSM) ------------------------------------------------
------------------------------------------------------------------
-- 明示的に現在のフェーズを持ち、状態遷移をログに残す。
-- これにより「釣り中のはずなのにマウント/精選している」のような
-- 不整合を検出しやすくする。
local STATE = {
    IDLE      = "idle",       -- 何もしていない / 初期状態
    TRAVELING = "traveling",  -- テレポ / 飛行 / 地上移動中
    AT_SPOT   = "at_spot",    -- 釣り位置到着 & セットアップ前
    FISHING   = "fishing",    -- キャスト〜ヒット〜AutoHook ループ中
    PURIFYING = "purifying",  -- 精選ウィンドウ操作中
}
local _state = STATE.IDLE
local function set_state(s)
    if _state == s then return end
    -- log は後方で定義されるため、pcall で安全化
    local msg = string.format("[state] %s → %s", _state, s)
    pcall(function() log(msg) end)
    _state = s
end
local function in_state(s) return _state == s end

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

-- 収集品の紫の舌先のみカウント (精選対象はコレクタブルだけ)
-- Inventory.GetCollectableItemCount(id, minQuality=1) が最優先
local function fish_count(id)
    local c = call_api_num("Inventory.GetCollectableItemCount", nil, id, 1)
    if c ~= nil then return c end
    -- フォールバック: GetCollectableItemCount が使えない環境では 0 扱い
    return 0
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
    if cond(COND.mounted) then return true end
    -- ハードガード: FSM 状態で釣り/精選中はマウント禁止。FSM を唯一の源として扱う。
    -- (cond.fishing は AutoHook 残骸で起動時から立ちっぱなしのケースがあるため
    -- ゲーム条件での判定は採用しない)
    if _state == STATE.FISHING or _state == STATE.PURIFYING then
        log(string.format("  (guard) mount_up 拒否 state=%s", _state))
        return false
    end
    -- 念のため釣りが残っていたら止めてからマウント (FSM が TRAVELING / AT_SPOT でも
    -- 実状態として cond.fishing=true なら先にクリア)
    if cond(COND.fishing) or cond(COND.casting) then
        log("  (recover) fishing/casting が残っている → /ahoff + /ac 中断")
        yield("/ahoff")
        wait(0.3)
        for i = 1, 3 do
            if not cond(COND.fishing) and not cond(COND.casting) then break end
            yield('/ac 中断')
            wait_until(function()
                return not cond(COND.fishing) and not cond(COND.casting)
            end, 2)
        end
    end
    log("マウント: /mount ウィング・オブ・ミスト")
    yield('/mount ウィング・オブ・ミスト')
    local ok = wait_until(function() return cond(COND.mounted) end, 8)
    if not ok then log("  警告: マウント失敗 (戦闘中/釣り中/Job制限?)") end
    return ok
end

local function dismount()
    if not cond(COND.mounted) then return true end
    local fn = safe_get("Actions.ExecuteGeneralAction")
    if fn then pcall(fn, 23) else yield('/gaction マウント解除') end
    local ok = wait_until(function() return not cond(COND.mounted) end, 4)
    if not ok then log("  警告: マウント解除失敗") end
    return ok
end

-- ガード: fly=true で移動する前に必ずマウント済みにする。
-- IPC.vnavmesh.PathfindAndMoveTo(dest, true) / /vnav flyto は
-- マウント前提のため、ここで invariant を満たす。
local function ensure_mount_for_fly(fly)
    if not fly then return true end
    if cond(COND.mounted) then return true end
    return mount_up()
end

-- ガード: 釣り/精選/キャスト前に必ずマウント解除
local function ensure_dismounted(reason)
    if not cond(COND.mounted) then return true end
    log("  (invariant) マウント解除 理由=" .. tostring(reason))
    return dismount()
end

-- 到着判定。arrival_radius 以下で「到着」、vnav 停止時は stuck_radius で打ち切り判定。
-- 釣り位置のように水面に面する精度が必要な場合は arrival_radius を小さく指定する。
local function wait_arrival(spot, timeout_sec, arrival_radius, stuck_radius)
    arrival_radius = arrival_radius or 3.0
    stuck_radius   = stuck_radius   or 8.0
    local t, step, last_log = 0, 0.5, 0
    while t < timeout_sec do
        local d = distance_to(spot.x, spot.y, spot.z)
        if t - last_log >= 5 then
            log(string.format("  移動中 d=%s busy=%s target_r=%.1f",
                d and string.format("%.2f", d) or "?",
                tostring(vnav_busy()), arrival_radius))
            last_log = t
        end
        if d and d <= arrival_radius then return true end
        -- vnav 停止 + 起動から 3 秒経過 で到着/スタック判定
        if t > 3 and not vnav_busy() then
            return d and d <= stuck_radius
        end
        yield("/wait " .. step)
        t = t + step
    end
    return false
end

-- 任意座標への移動ヘルパー。
-- arrival_radius: 成功扱いにする距離 (未指定なら 3.0)
-- stuck_radius:   vnav 停止時に success 扱いに許す最大距離 (未指定なら 8.0)
local function move_to_point(tx, ty, tz, fly, timeout, arrival_radius, stuck_radius)
    if fly then ensure_mount_for_fly(true) end
    local cmdv = fly and "/vnav flyto " or "/vnav moveto "
    yield(cmdv .. string.format("%.2f %.2f %.2f", tx, ty, tz))
    local fake = { x = tx, y = ty, z = tz }
    local arrived = wait_arrival(fake, timeout or 240, arrival_radius, stuck_radius)
    yield("/vnav stop")
    return arrived
end

-- 釣り位置への厳密移動。水面に面させるため 1.5m 以内まで追い込む。
-- vnav が途中で諦めたら最大 max_retries 回まで再度 moveto を叩き直す。
local function move_to_fishing_point(tx, ty, tz, max_retries)
    max_retries = max_retries or 3
    local target_r = 1.5  -- 釣り位置の到着半径 (厳密)
    local stuck_r  = 2.5  -- vnav 停止時でもこれ以下なら成功扱い
    for attempt = 1, max_retries do
        local d = distance_to(tx, ty, tz)
        if d and d <= target_r then
            log(string.format("  釣り位置到達 d=%.2f (attempt=%d)", d, attempt))
            return true
        end
        log(string.format("  釣り位置移動 attempt=%d/%d 現在d=%s",
            attempt, max_retries,
            d and string.format("%.2f", d) or "?"))
        move_to_point(tx, ty, tz, false, 60, target_r, stuck_r)
        wait(0.3)
    end
    local d = distance_to(tx, ty, tz)
    local ok = d and d <= stuck_r
    log(string.format("  釣り位置リトライ終了 最終d=%s %s",
        d and string.format("%.2f", d) or "?", ok and "OK" or "NG"))
    return ok
end

-- 近距離なら飛行せず地上歩きにする閾値 (座標単位 ~ m)
local SHORT_HOP_THRESHOLD = 30.0

local function move_to(spot)
    set_state(STATE.TRAVELING)

    -- 既に釣り位置にいる? (厳密: 1.5m 以内のみ到着済扱い)
    local d = distance_to(spot.x, spot.y, spot.z)
    if d and d <= 1.5 then
        log(string.format("到着済 d=%.2f", d))
        ensure_dismounted("到着済")
        return
    end

    -- 近距離なら飛行/マウント自体スキップ → 無駄なマウント乗降を削減
    if d and d <= SHORT_HOP_THRESHOLD then
        log(string.format("近距離 d=%.1f → 地上歩きのみ", d))
        ensure_dismounted("近距離移動")
        move_to_fishing_point(spot.x, spot.y, spot.z, 3)
        return
    end

    -- landing が設定されているなら「①飛んで landing」「②降車」「③地上歩きで釣り場」
    if spot.landing then
        log("→ landing (飛行)")
        if cfg.use_flight then
            -- invariant: fly の前に必ずマウント
            if not ensure_mount_for_fly(true) then
                log("  マウント不可 → 地上歩きにフォールバック")
            end
        end
        -- landing は多少ズレてもOK (arrival_r=3.0, stuck_r=8.0 デフォルト)
        local ok_land = move_to_point(spot.landing.x, spot.landing.y, spot.landing.z,
            cfg.use_flight and cond(COND.mounted), 240)
        if not ok_land then log("  warn: landing 未到達") end

        -- 釣り位置へは必ず地上歩き、かつ厳密に追い込む
        ensure_dismounted("landing到着")

        log("→ 釣り位置 (地上、厳密)")
        move_to_fishing_point(spot.x, spot.y, spot.z, 3)
    else
        -- landing なしなら飛んで直接、その後 dismount して釣り位置へ厳密移動
        if cfg.use_flight then ensure_mount_for_fly(true) end
        local arrived = move_to_point(spot.x, spot.y, spot.z,
            cfg.use_flight and cond(COND.mounted), 240)
        if not arrived then log("警告: 到達タイムアウト") end
        ensure_dismounted("スポット到着")
        -- マウント降下後、水際まで厳密に歩く
        move_to_fishing_point(spot.x, spot.y, spot.z, 3)
    end
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
    set_state(STATE.TRAVELING)
    teleport_to(cfg.aetheryte)
    move_to(spot)

    -- スポット固有 face があればそれを優先、なければ共通 cfg.face
    local f = spot.face or cfg.face
    if f then face_point(f.x, f.y, f.z) end

    -- キャスト前にマウントを必ず降りる (invariant)
    ensure_dismounted("キャスト前")
    set_state(STATE.AT_SPOT)
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

-- Addon が実際に表示されているか判定する。
-- 重要: Addons.GetAddon はウィンドウが閉じていてもオブジェクトを返すので、
-- 「オブジェクト取得=表示中」と見なすのは誤り。必ず Ready/IsVisible/Visible を検査する。
-- 返り値: true=表示中, false=非表示, nil=判定不能
local function addon_visible(name)
    -- 1) 明示的にブール値を返す API を優先
    for _, path in ipairs({
        "IsAddonReady", "IsAddonVisible",
        "Addons.IsAddonReady", "Addons.IsAddonVisible",
    }) do
        local fn = safe_get(path)
        if fn then
            local ok, v = pcall(fn, name)
            if ok and type(v) == "boolean" then return v end
        end
    end
    -- 2) フォールバック: GetAddon で Ready/IsVisible/Visible フィールドを明示検査
    local get_fn = safe_get("Addons.GetAddon")
    if get_fn then
        local ok, v = pcall(get_fn, name)
        if ok then
            if v == nil then return false end
            if type(v) == "table" or type(v) == "userdata" then
                local ready = safe_index(v, "Ready")
                local vis   = safe_index(v, "IsVisible")
                local vis2  = safe_index(v, "Visible")
                if ready ~= nil then return ready == true end
                if vis   ~= nil then return vis   == true end
                if vis2  ~= nil then return vis2  == true end
                -- 明示的な可視フラグが無い場合は判定不能
                return nil
            end
        end
    end
    return nil  -- 判定不能
end

-- キャスト前にゴミ addon (精選残骸など) が開いていたら閉じる
local function close_stale_addons()
    if addon_visible("PurifyResult") then
        yield('/callback PurifyResult true 0')
        wait(0.3)
    end
    if addon_visible("PurifyItemSelector") then
        yield('/callback PurifyItemSelector true -1')  -- キャンセル
        wait(0.3)
    end
    if addon_visible("Repair") then
        yield('/callback Repair true -1')
        wait(0.3)
    end
    if addon_visible("SelectYesno") then
        yield('/callback SelectYesno true 1')  -- No (安全側)
        wait(0.3)
    end
end

------------------------------------------------------------------
-- 自己修理 (時間ベース throttle) --------------------------------
------------------------------------------------------------------
-- 耐久API が無い環境向け。定期的に Repair ウィンドウを開き、
-- 「Yes/No」ダイアログの出現を修理要否の判定に使う。
local _last_repair_attempt = 0   -- os.time() の値

local function try_repair_gear()
    if not cfg.auto_repair then return end

    local now = os.time()
    local interval = cfg.repair_interval_sec or 1800   -- 30 分
    if (now - _last_repair_attempt) < interval then
        -- まだ前回から短時間 → スキップ
        return
    end
    _last_repair_attempt = now

    log(string.format("★ 定期修理トライ (間隔 %d 秒)", interval))

    -- 釣り中なら先に止める
    if _state == STATE.FISHING or cond(COND.fishing) or cond(COND.casting) then
        log("  修理前: 釣り/キャストを停止")
        yield("/ahoff")
        wait(0.3)
        for i = 1, 3 do
            if not cond(COND.fishing) and not cond(COND.casting) then break end
            yield('/ac 中断')
            wait_until(function()
                return not cond(COND.fishing) and not cond(COND.casting)
            end, 2)
        end
        set_state(STATE.AT_SPOT)
    end
    ensure_dismounted("修理前")
    close_stale_addons()

    yield('/ac 自己修理')
    local opened = wait_until(function()
        return addon_visible("Repair") == true
    end, 5)
    if not opened then
        log("  Repair ウィンドウ開かず (自己修理アクション未習得 or Dark Matter 無)")
        return
    end
    wait(0.5)

    -- 「まとめて修理」を押す。全部耐久MAXなら Yes/No が出ずにボタン自体が無反応。
    yield('/callback Repair true 0')
    if wait_until(function() return addon_visible("SelectYesno") == true end, 2) then
        log("  修理対象あり → Yes")
        yield('/callback SelectYesno true 0')  -- Yes
        -- 修理キャスト完了待ち
        wait_until(function() return not cond(COND.casting) end, 20)
        wait(1.0)
        log("  修理完了")
    else
        log("  修理不要 (耐久OK)")
    end

    -- Repair ウィンドウを閉じる
    if addon_visible("Repair") == true then
        yield('/callback Repair true -1')
        wait(0.3)
    end
end

local function cast()
    -- invariant: マウント解除 & 残存 UI クローズ
    ensure_dismounted("cast前")
    close_stale_addons()
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

-- 「魚に警戒されてしまった」メッセージ検知用フラグ
-- 外部 (SND Trigger Events / OnChatMessage) から _G.PTF_fish_sense = true で設定
-- ・設定方法の例 (SND 別マクロで):
--     function OnChatMessage()
--       local m = TriggerData and TriggerData.message or ""
--       if m:find("魚たちに警戒") or m:find("少し場所を変え") then
--         _G.PTF_fish_sense = true
--       end
--     end
local function fish_sense_triggered()
    if _G.PTF_fish_sense then
        _G.PTF_fish_sense = false
        return true
    end
    return false
end

local function fish_at_spot(duration_sec)
    log("fish_at_spot 開始 duration=" .. duration_sec)
    _G.PTF_fish_sense = false  -- スポット開始時にリセット
    set_state(STATE.FISHING)
    setup_rig()
    local start_t = os.time()
    log("  fishing条件: " .. tostring(cond(COND.fishing)))

    local max_cast_failures = 3
    local cast_failures = 0

    while (os.time() - start_t) < duration_sec do
        -- invariant: 釣り中にマウントされたら即解除 (不意の操作混入を防ぐ)
        if cond(COND.mounted) then
            log("  警告: 釣り中にマウント検知 → 強制解除")
            ensure_dismounted("fish_at_spot 中マウント異常")
        end

        -- 魚に警戒されたメッセージが来ていれば即座にスポット変更
        if fish_sense_triggered() then
            log("  魚に警戒された → 次のポイントへ")
            return "fish_sense"
        end
        if free_slots() <= cfg.inventory_free_limit
           and fish_count(FISH_ITEM_ID) > 0 then
            return "inv_full"
        end
        if item_count(SAND_ITEM_ID) >= cfg.target then return "done" end

        if not cond(COND.fishing) and not cond(COND.casting) then
            cast()
            local ok = wait_until(function()
                if fish_sense_triggered() then return true end
                return cond(COND.fishing) or cond(COND.casting)
            end, 5)
            if _G.PTF_fish_sense == false and not ok then
                cast_failures = cast_failures + 1
                log(string.format("  キャスト失敗 %d/%d (釣り場外の可能性)",
                    cast_failures, max_cast_failures))
                if cast_failures >= max_cast_failures then
                    log("  → 次のポイントへ移動")
                    return "no_fish_spot"
                end
            elseif ok then
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
    -- FSM を AT_SPOT に戻す。これをしないと後続の reduce_all が FISHING 判定で拒否される。
    -- quit_fishing() 内で fishing=false を待機済みなので安全。
    set_state(STATE.AT_SPOT)
end

-- 精選ウィンドウを強制的に「閉じた → 新規に開き直す」状態に遷移させる。
-- 目的: 表示判定が不安定でも確実にフレッシュな状態で callback を撃てるようにする。
local function reopen_purify_window()
    -- 1) 残骸 UI を閉じる
    close_stale_addons()
    wait(0.3)
    -- 2) /ac 精選 でオープン
    log("  精選ウィンドウ オープン (/ac 精選)")
    yield('/ac 精選')
    -- 3) 表示まで待機 (判定不能時もタイムアウトで抜けて進む)
    wait_until(function() return addon_visible("PurifyItemSelector") == true end, 3)
    wait(0.6)
    local vis = addon_visible("PurifyItemSelector")
    log("  PurifyItemSelector visible=" .. tostring(vis))
    return vis ~= false  -- true or nil (判定不能) を成功扱い
end

local function reduce_all()
    -- ハードガード: FSM が釣り中の場合のみ実行拒否。
    -- cond.fishing だけで拒否すると AutoHook 残骸で起動時に精選できなくなるため
    -- FSM を唯一の源として扱う。必要なら呼び出し側で stop_fishing() を先に行う。
    if _state == STATE.FISHING then
        log("  (guard) reduce_all 拒否 state=FISHING")
        return
    end
    -- 念のため: 実際にゲーム側で釣り/キャスト中なら先にクリア
    if cond(COND.fishing) or cond(COND.casting) then
        log("  (recover) reduce_all 前に fishing/casting 残存 → /ahoff + /ac 中断")
        yield("/ahoff")
        wait(0.3)
        for i = 1, 3 do
            if not cond(COND.fishing) and not cond(COND.casting) then break end
            yield('/ac 中断')
            wait_until(function()
                return not cond(COND.fishing) and not cond(COND.casting)
            end, 2)
        end
    end

    local n = fish_count(FISH_ITEM_ID)
    log("精選開始 fish=" .. n)
    if n <= 0 then
        log("  紫の舌先 0 → 精選スキップ")
        return
    end

    set_state(STATE.PURIFYING)

    -- invariant: マウント中は精選不可
    ensure_dismounted("精選前")

    local use_item = safe_get("Inventory.UseItem")
    local exec_ga  = safe_get("Actions.ExecuteGeneralAction")
    log(string.format("  API check Inventory.UseItem=%s Actions.ExecuteGeneralAction=%s",
        tostring(type(use_item)), tostring(type(exec_ga))))

    -- 毎回フレッシュに開き直す (前回の残骸が残っていると callback が空振る)
    reopen_purify_window()

    local safety = 0
    local prev_fish = n
    local stuck = 0
    local max_stuck = 3  -- 8→3 に短縮 (スタックしたら即リセット)
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

        -- 前回の精選結果ダイアログが残っていれば閉じる (閉じないと次の callback が効かない)
        if addon_visible("PurifyResult") == true then
            log("  PurifyResult を閉じる")
            yield('/callback PurifyResult true 0')
            wait(0.5)
        end

        -- 選択ウィンドウが開いているか確認。閉じていたら再オープン
        local vis = addon_visible("PurifyItemSelector")
        if vis == false then
            log("  PurifyItemSelector 閉じていた → 再オープン")
            if not reopen_purify_window() then
                log("  警告: 精選ウィンドウ再オープン失敗 → 打ち切り")
                break
            end
        end

        -- 精選アクション発動
        yield('/callback PurifyItemSelector true 12 0')
        log("  /callback PurifyItemSelector true 12 0")
        wait(1.0)

        -- 精選演出完了まで待機 (cast 条件が落ちる)
        wait_until(function() return not cond(COND.casting) end, 15)
        wait(0.8)

        -- 結果ダイアログが出たら必ず閉じる (次の iter で呼ぶ前に片付ける)
        if addon_visible("PurifyResult") == true then
            yield('/callback PurifyResult true 0')
            wait(0.5)
        end

        -- 進捗判定
        local new_fish = fish_count(FISH_ITEM_ID)
        if new_fish >= prev_fish then
            stuck = stuck + 1
            log(string.format("  減少せず %d/%d (fish=%d)", stuck, max_stuck, new_fish))
            if stuck >= max_stuck then
                -- 完全リセットを1度試み、それでもダメなら打ち切り
                log("  進捗なし → 完全リセットして再試行")
                close_stale_addons()
                wait(0.5)
                if not reopen_purify_window() then
                    log("  リセット後もウィンドウ開けず → 打ち切り")
                    break
                end
                -- リセット後に改めて 1 回試行してもダメなら打ち切り
                yield('/callback PurifyItemSelector true 12 0')
                wait(1.0)
                wait_until(function() return not cond(COND.casting) end, 15)
                wait(0.8)
                if addon_visible("PurifyResult") == true then
                    yield('/callback PurifyResult true 0')
                    wait(0.5)
                end
                local retry_fish = fish_count(FISH_ITEM_ID)
                if retry_fish >= prev_fish then
                    log("  リセット後も減らず → 打ち切り")
                    break
                end
                prev_fish = retry_fish
                stuck = 0
            end
        else
            stuck = 0
            prev_fish = new_fish
        end
        safety = safety + 1
    end
    -- クリーンアップ
    close_stale_addons()
    log("精選完了 fish=" .. fish_count(FISH_ITEM_ID) .. " sand=" .. item_count(SAND_ITEM_ID))
    set_state(STATE.AT_SPOT)
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
    cfg.auto_repair        = cfg.auto_repair ~= false     -- 既定 true
    cfg.repair_threshold_pct = cfg.repair_threshold_pct or 20
    cfg.repair_interval_sec = cfg.repair_interval_sec or 1800  -- 30 分
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

    -- 起動時クリーンアップ: 前回セッションの残骸 (AutoHook ON / 釣り中 / 精選画面) を一掃
    log("起動時クリーンアップ")
    yield("/ahoff")
    wait(0.3)
    if cond(COND.fishing) or cond(COND.casting) then
        for i = 1, 3 do
            if not cond(COND.fishing) and not cond(COND.casting) then break end
            log("  前回の釣りが残存 → /ac 中断")
            yield('/ac 中断')
            wait_until(function()
                return not cond(COND.fishing) and not cond(COND.casting)
            end, 3)
        end
    end
    close_stale_addons()
    _state = STATE.IDLE  -- 明示的に初期化

    -- 精選を実行すべきか判定
    -- 原則: 「インベ空きが少ない」か「舌先を一定数以上持っている」場合のみ精選
    -- これにより毎スポット移動ごとの「マウント→精選→マウント」を減らす
    local function should_purify(reason)
        local fish = fish_count(FISH_ITEM_ID)
        if fish <= 0 then return false end
        if reason == "inv_full" then return true end
        if free_slots() <= cfg.inventory_free_limit + 2 then return true end
        -- 舌先が溜まっていれば実益があるので精選
        if fish >= 10 then return true end
        return false
    end

    local idx = 1
    while item_count(SAND_ITEM_ID) < cfg.target do
        goto_spot(cfg.spots[idx])

        -- 装備耐久チェック (定期的に Repair ウィンドウを試し、修理要なら実行)
        try_repair_gear()

        -- 釣り開始前のインベントリ空きチェック
        local free = free_slots()
        local fish = fish_count(FISH_ITEM_ID)
        log(string.format("釣り前チェック  空き=%d 舌先=%d", free, fish))
        if free <= cfg.inventory_free_limit and fish <= 0 then
            log("  ERROR: インベ満杯かつ舌先0 → 精選不能のため中断")
            log("  不要アイテムを整理してから再実行してください")
            break
        end
        if should_purify("pre_fish") then
            log("  → 釣り前に精選実行")
            reduce_all()
        else
            log("  → 精選はスキップ (空き十分 or 舌先少)")
        end

        local reason = fish_at_spot(cfg.time_per_spot)
        stop_fishing()

        if should_purify(reason) then
            log("  釣り後: 精選実行 reason=" .. tostring(reason))
            reduce_all()
        else
            log("  釣り後: 精選スキップ (空き十分) reason=" .. tostring(reason))
        end
        if reason == "done" then break end
        idx = idx % #cfg.spots + 1
    end
    log("完了: sand=" .. item_count(SAND_ITEM_ID))
    set_state(STATE.IDLE)
    close_log()
end

-- 外部からもクローズ可能に
PTF.close = close_log

-- SND の File Dependency は毎回ロードするため、常に最新を _G.PTF に入れる
_G.PTF = PTF
return PTF
