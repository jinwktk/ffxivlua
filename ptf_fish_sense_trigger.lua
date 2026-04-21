--[=====[
[[SND Metadata]]
author: jinwktk
version: 0.1.0
description: 「魚たちに警戒されてしまった」の検知用チャットトリガー。メインスクリプト (purple_tongue_farm) に _G.PTF_fish_sense フラグを立てる。
trigger_events:
  - type: OnChatMessage
    filter:
      message_regex: "魚たちに警戒|少し場所を変え"
[[End Metadata]]
--]=====]

-- チャットフィルタに一致したら実行される
-- (SND Expanded のトリガー仕様に依存。filter 未対応版は OnChatMessage 関数で判定)
local msg = (TriggerData and TriggerData.message) or ""
if msg:find("魚たちに警戒") or msg:find("少し場所を変え") then
    _G.PTF_fish_sense = true
    yield('/echo [PTF-trigger] 魚に警戒 検知 → スポット変更フラグON')
end
