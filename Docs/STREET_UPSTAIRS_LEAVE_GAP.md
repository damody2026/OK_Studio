# 楼上离开走不到电梯口（街区导航缺口，2026-11-18）

在 M1 商场楼上的店（arcade 8F、ramen 9F）或 gym 5F，往楼下任何地点导航时，常在 2–3 秒内就报「那里目前走不到，换个地方试试」（`ui.contacts.unreachable_try_elsewhere`）。走进这些店没问题，出不来。

## 重现（c3b1117a stage，`-NoCloud -Sandbox Check1116 -PortBase 48160`，控制埠 48170）

| 步骤 | 结果 |
|---|---|
| `game_warp place=cafe` → `game_goto place=arcade` | 130 s 抵达，停在 (44027,63649,4140) |
| 接着 `game_goto place=cafe`（不瞬移） | 2 s 报走不到，人没动；连续 5 次都一样 |
| `game_warp place=ramen` → `game_goto place=arcade` → `game_goto place=cafe` | 到 arcade 33 s，离开 2 s 报走不到 |
| `game_warp place=ramen`（落在门点 48179,60425,4560）→ `game_goto place=arcade` | 3 s 报走不到 |
| `game_warp place=cafe` → `game_goto place=ramen` → `game_goto place=cafe` | 这次到 ramen 79 s 报走不到；之后从停下处去 cafe 70 s 抵达（ramen 时好时坏） |
| gym 5F：在 (77360,21320,4780) 往楼下地点 goto | 5F 的垫子、镜子走不回 1F（11-17 记录，排程目前不派人到 5F） |

## 量到的失败点（游戏 log，`Street navigation`）

ramen 门点 → arcade：

```
Street navigation: by the elevator of department to floor 7 (2 points to the landing)
Street navigation: blocked why: next=V(X=45760.00, Y=58150.00, Z=4560.00) gap_here=3339 gap_ahead=3332 sweep=none
Street navigation: blocked at V(X=48179.40, Y=60425.00, Z=4560.00), replanned 1 (points=2)
Street navigation: no way (to the lift landing again) from V(X=48179.40, Y=60425.00, Z=4560.00) after 2 replans
```

去电梯口（45760,58150）的路只有 2 个点，就是一条 33 m 的直线，被墙挡住。

## 原因（`Source/OpenKoikatsu/OKStreetSocialElevator.inl`）

- `PlanNavLift`（:352）在楼上时调用 `WalkToLanding(S.Male, Lifts[From]->Position)`。
- `WalkToLanding`（:338）在 `OKStreetCityFar(From, Landing)` 成立时直接跳过 `GridRoute`，改用路网 `PlaceRouteWaypoints`。
- 路网点全部在地面高度（`Tools/export_street_city_game_places.lua` 写 `GROUND_Z`），楼上一定因为 `|P.Z - From.Z| > 150` 被拒，返回空。
- 回到 `Ride`：`Walk` 为空时，若 `OKStreetCityClear` 判直线通（18 cm 扫掠没扫到，或扫掠漏判），就把 `{S.Male, Landing}` 当路线走，撞墙重规划后放弃；判不通则立刻报走不到。arcade 的情况是立刻报。
- 进店不受影响：搭电梯上楼后从电梯口走到店里，走的是另一段路。

可达性扫描（`Tools/street_city_reach_check.lua probe`）上，arcade、ramen 的门和该层电梯口在同一个大区（8F 约 8 万格、9F 7.7 万格），格子路线是存在的。

## 修法（整合 #16 之后，c-street-city 来改）

- 楼上（`OKStreetUpstairs(From)`）时，就算 `OKStreetCityFar`，也先在同一层跑 `GridRoute(From, Landing)`；格子找到就用。
- 格子也失败，才退回路网或直线，维持现在的报错。
- 注意格子跨整层的耗时（gym 1F 130 m 的格子搜寻曾经不够），必要时加距离上限或分段。
- 修好后重测上表每一行，以及 gym 5F 下楼、campus_sports 各层楼梯口。
