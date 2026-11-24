-- Read current semantic contracts, never infer office names from an old drawing.
-- 這條產線的輸出放在工作樹底下，不是某一台機器的位置（使用者 2026-11-24：每台電腦都不一樣）。
local root=require('ok').root
local code=[====[
import sys,json
from pathlib import Path
sys.path.insert(0,'@OKROOT@/Tools')
from street_city_campus_contract import context
rows={k:{'building':context(k)['building'],'rooms':context(k)['rooms']} for k in ['T4','RB','SC','IB']}
Path('@OKROOT@/output/street-social-city-production/activity-scenes-v1/campus-supplement.json').write_text(json.dumps(rows,ensure_ascii=False),'utf8')
]====]
assert(os.execute('python -c "'..code:gsub('\r?\n','; ')..'"'))
