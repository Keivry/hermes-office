> 状态：已确认（2026-10-12）；实现见 `/opt/data/scripts/todo/`。
> 本文是 §1–§6 的设计部分；完整实现计划（T0–T16）见 `/opt/data/.hermes/plans/2026-10-12_112351-todo-reminder-system.md`。

## 1. 目标

用**一个 SQLite 库 + 一个每日 tick + 一个 Matrix 房间内胶囊交互**，统一承载
「一次性待办 / 周期任务 / 生日纪念日」，支持分类分房、农历、提前数天提醒，
并且**创建、完成、撤销全部不走 LLM**（确定性脚本 + Hermes 官方扩展点）。

所有**创建 / 修改 / 完成 / 撤销完成 / 删除**都落一条**追加型审计事件**（`item_event`），与数据变更
**同事务**写入，可随时按条目或时间段查询、导出（见 §4.2–§4.4、§5.4）。

历史**永久保留**（不设 TTL、不自动清理），并且**物理拆分**到独立文件
`state/todo/history.db`：热库 `state/todo/todo.db` 只放运行态（当前状态 / 发过没发过 / 胶囊映射），
历史库独立增长、独立备份、可单独查询与迁移 —— 热库不会被无限增长的历史拖大。
拆分的代价是「跨文件写入可能漂移」，已用 §4.5 的实测证据定死机制（必须是 rollback journal）。

## 2. 已核实的事实基础（源码锚点，实现时按这些写，不要猜）

| 事实 | 位置 |
| --- | --- |
| 插件斜杠命令扩展点：`ctx.register_command(name, handler, description, args_hint)`，handler `fn(raw_args: str) -> str \| None`（同步或异步） | `hermes_cli/plugins.py:647` |
| gateway 派发插件命令：`plugin_handler(user_args)`，同步 handler 走线程池 `_run_in_executor_with_context`，返回值即回给用户的消息 | `gateway/run_inbound.py:1047`（插件分支约 1091–1112） |
| **Matrix 斜杠命令自动豁免 @提及**：`if not is_mentioned and not body.startswith("/")` | `plugins/platforms/matrix/adapter.py:2085` |
| 插件加载：目录 `~/.hermes/plugins/<name>/`，入口 `register(ctx)`；`plugin.yaml` 至少 `name` | `hermes_cli/plugins_loader.py:510-519`、`hermes_cli/plugins_manifest.py:525` |
| 插件启停：`hermes plugins enable <name>` | `hermes_cli/subcommands/plugins.py:129` |
| hook 契约：`~/.hermes/hooks/<name>/HOOK.yaml`（`name`/`description`/`events`）+ `handler.py` 的 `handle(event_type, context)`；**同步 handler 直接在 loop 线程执行**，必须写 `async def` | `gateway/hooks.py:45-71, 126-140` |
| Matrix 反应转发补丁（`reaction:added` / `reaction:removed`） | `github-work/hermes-office/patches/035-matrix-reaction-hook-forwarding.patch`（已推送） |
| 反应 payload 语义：added → `reaction`=emoji、`message_ts`=被反应的消息 event id、`event_ts`=反应事件 id、`channel_id`=room_id；removed → `redacts`=被撤回的反应事件 id，`reaction`/`message_ts` 为空 | 同上 patch 的 `_forward_reaction_event` docstring |
| 号码胶囊 emoji 集（与内置选择器一致）：`1️⃣…9️⃣`（`f"{d}\ufe0f\u20e3"`）+ 🔟（`\U0001f51f`） | `plugins/platforms/matrix/adapter.py:426` |
| 编辑消息（`m.replace`）payload 形状 | `plugins/platforms/matrix/adapter.py:1473-1482` |
| 发送 CLI：`scripts/matrix-send/send_message.py`，成功 stdout 打印 `{"ok":true,...,"event_id":"$..."}`；env 文件 `env/matrix-send/environment`（含 `MATRIX_SEND_HOMESERVER/USER_ID/PASSWORD/ACCESS_TOKEN`）；登录后回写 access token | 同文件 `send()` 返回、`main()` 第 521 行、第 96 行 `update_env_file_value` |
| mautrix 0.21.1 只在 `/opt/hermes/.venv/bin/python` 中可用 | 实测 |
| cron 任务 `script` 相对 `<HERMES_HOME>/scripts/` 解析，默认 cwd = 脚本所在目录，**env 被 sanitize**（别指望外部环境变量） | `cron/scheduler_script.py:323-346, 447, 489-500` |
| 备份白名单 `STATE_FILES`（不是整目录打包） | `scripts/backup/hermes_backup.py:23-34` |
| **跨库原子提交的官方保证**：「Transactions involving multiple attached databases are atomic, **assuming … the journal_mode is not WAL**. If … the journal_mode is WAL, then transactions continue to be atomic within each individual database file. But if the host computer crashes in the middle of a COMMIT where two or more database files are updated, **some of those files might get the changes where others might not**」 | SQLite 官方 `lang_attach.html`（2025-02-06 版）、`wal.html` 缺点第 2 条 |
| **实测漂移率**（本机 SQLite 3.53.1，两库 + `ATTACH`，在 COMMIT 期间 SIGKILL，各 50 次）：`journal_mode=delete` → **0/50 漂移**；`journal_mode=wal` → **33/50 漂移**（t=4/h=3、t=2/h=1 … 即热库多提交了一条，历史库漏记） | `/opt/data/cache/scratch/xdb_commit_crash.py` 实跑结果 |
| **authorizer 回调第 4 参是 `db_name`**，可区分 `main` / `hist`：实测 `DELETE FROM hist.h` 被 `SQLITE_DENY` 拒、`DELETE FROM main.t` 放行 | `/opt/data/cache/scratch/auth_probe.py` 实跑结果 |
| 插件 handler 签名只有 `raw_args: str`（拿不到发送者），但 gateway 在调用前后用 `_session_env_scope(_plugin_context)` 绑好了会话 ContextVar，**同步 handler 又在线程池执行且 contextvars 随行** → handler 内可 `get_session_env("HERMES_SESSION_USER_ID" / "_USER_NAME" / "CHAT_ID" / "PLATFORM" / "MESSAGE_ID")` 取到真实操作人与房间 | `hermes_cli/plugins.py:647`、`gateway/run_inbound.py:1086-1105`、`gateway/session_context.py:41-47,173`（实测 `from gateway.session_context import get_session_env` 可导入，签名 `(name, default="")`） |
| 农历库 `lunardate` 0.3.0 已装入 `/opt/data/state/todo/venv`（Python 3.14），API 为 snake_case（`from_solar_date` / `to_solar_date`），支持 1900–2099 | 实测，4 组节气对照全通过 |

**已确认的产品决策**：工作/个人各一个房间（用户自建）；需要农历；纪念日提前 7 天、周期任务当天、
一次性待办按 `lead_days`；提前期内**每天一行**；闰月生日「有闰月按闰月、无闰月按普通月」；
腊月三十遇小月**取该月最后一天**；点击 = 完成本期，**再点一次 = 撤销**；回显用
**编辑原消息**（不发新消息）；gateway 停机期间漏掉的点击**不补偿**；
创建/修改/完成/撤销完成都要留**完整历史**（谁、何时、在哪个房间、做了什么），
历史**永久保留**且**物理拆分**到独立的 `state/todo/history.db`。

## 3. 架构

一个 **tick**（cron 每天 09:00，0 次 LLM）遍历全库、物化期次（occurrence）、按房间发**一条**汇总
消息，并把「消息 event id + emoji → 条目」写进 DB；用户点胶囊产生的反应经**补丁 035** 转发到
`hooks/todo-reaction`，hook 只做转发、判断逻辑全在 `todo.py react` 里，完成后由
`matrix_edit.py` 用 `m.relates_to.m.replace` **就地编辑**那条提醒消息。
创建/完成/删除也走 `/todo` **插件斜杠命令**（同样不经过模型）。

```
             ┌──────────────── cron 09:00 (script=todo/tick.py, 0 LLM)
             ▼
 todo.py tick ── 物化 occurrence ── 选出今天该提醒的 ── 按 category→room 分组
      │                                                        │
      │  写 reminder(occurrence_id, notify_date) 幂等           │ matrix-send 发送
      │  写 reminder_key(event_id, emoji) → 条目                 ▼
      │                                              Matrix 房间（work / personal）
      │                                                        │ 点 1️⃣ / 再点一次
      │  reaction:added / reaction:removed                      ▼
      └──────── hooks/todo-reaction/handler.py ◄── 补丁 035 转发反应
                          │ asyncio.create_subprocess_exec
                          ▼
                 todo.py react → 改 DB → matrix_edit.py 编辑原消息（m.replace）
```

**两库分离**：图中每个「改 DB」的箭头都要同时写两个文件 ——

- **热库 `state/todo/todo.db`**：`item` / `occurrence` / `reminder` / `reminder_key` / `reaction_seen`
  （运行态：当前状态、幂等判重、撤销反查）；
- **历史库 `state/todo/history.db`**：只有 `item_event`（追加型审计，永久保留）。

一个连接用 `ATTACH DATABASE '…/history.db' AS hist` 挂上历史库，**两库要么在同一个事务里一起提交、
要么一起回滚**（前提：两个库都不是 WAL，见 §4.5）。`tick` 的发送记录留在 `reminder` 表；
历史查询在同一个连接里一条 SQL 跨库 `UNION ALL` 合并呈现，**绝不双写**。

## 4. 数据模型（两库分离）

拆分原则一句话：**热库只放「运行需要的东西」，历史库只放「要永久留的东西」**。
判据是「删掉它系统还能不能跑」——`reminder`（今天发过没）和 `reminder_key`（点 3️⃣ 是哪个条目）
删掉就废了，所以留热库；`item_event` 删掉只是少查一条历史，所以拆出去。

```
state/todo/todo.db      ← 运行态，体积恒定（条目数 + 期次窗口），高频读写
state/todo/history.db   ← 只追加，永久增长，写多读少，可单独备份/迁移/归档
```

### 4.1 运行库 `state/todo/todo.db`

```sql
PRAGMA journal_mode=DELETE;     -- 必须！跨库原子提交的前提（见 §4.5）
PRAGMA busy_timeout=5000;
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS item(
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  title             TEXT NOT NULL,
  notes             TEXT NOT NULL DEFAULT '',
  category          TEXT NOT NULL DEFAULT 'personal',           -- work | personal | 任意自定义
  kind              TEXT NOT NULL CHECK(kind IN('task','repeat','date')),
  status            TEXT NOT NULL DEFAULT 'open' CHECK(status IN('open','done','dropped')),
  due_at            TEXT,                                       -- task: 'YYYY-MM-DD[ HH:MM]'
  calendar          TEXT NOT NULL DEFAULT 'solar' CHECK(calendar IN('solar','lunar')),
  lunar_month       INTEGER,                                    -- date+lunar 时必填
  lunar_day         INTEGER,
  lunar_prefer_leap INTEGER NOT NULL DEFAULT 1,                 -- 1=有闰月按闰月
  repeat_rule       TEXT,                                       -- JSON，见 §5
  lead_days         INTEGER NOT NULL DEFAULT 0,
  priority          INTEGER NOT NULL DEFAULT 2,                 -- 1 高 2 中 3 低
  deleted_at        TEXT,                                       -- 软删时间；NULL=未删（rm 只软删）
  room              TEXT,                                       -- 覆盖默认房间；NULL=按 category 映射
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);

-- 期次：task 有 due_at → 1 条；repeat → 每期 1 条；date → 每年 1 条
CREATE TABLE IF NOT EXISTS occurrence(
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id         INTEGER NOT NULL REFERENCES item(id) ON DELETE CASCADE,
  occurrence_date TEXT NOT NULL,                                -- 'YYYY-MM-DD' 公历
  state           TEXT NOT NULL DEFAULT 'pending' CHECK(state IN('pending','done','skipped')),
  ack_at          TEXT,
  UNIQUE(item_id, occurrence_date)
);

-- 已发出的提醒：一个 (期次,日期) 只发一次 → 幂等
CREATE TABLE IF NOT EXISTS reminder(
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  occurrence_id INTEGER NOT NULL REFERENCES occurrence(id) ON DELETE CASCADE,
  notify_date   TEXT NOT NULL,
  room          TEXT NOT NULL,
  event_id      TEXT,                                           -- 那条汇总消息
  sent_at       TEXT NOT NULL,
  UNIQUE(occurrence_id, notify_date)
);

-- 胶囊 → 条目映射（持久化，无 TTL；重启网关后照样能点）
CREATE TABLE IF NOT EXISTS reminder_key(
  event_id      TEXT NOT NULL,
  emoji         TEXT NOT NULL,
  item_id       INTEGER NOT NULL,
  occurrence_id INTEGER NOT NULL,
  PRIMARY KEY(event_id, emoji)
);

-- 反应事件登记：撤销（redaction）只给被撤回的反应事件 id，靠这张表反查
CREATE TABLE IF NOT EXISTS reaction_seen(
  reaction_event_id TEXT PRIMARY KEY,
  msg_event_id      TEXT NOT NULL,
  emoji             TEXT NOT NULL,
  user_id           TEXT NOT NULL,
  action            TEXT NOT NULL,
  seen_at           TEXT NOT NULL
);
```

### 4.2 历史库 `state/todo/history.db`（追加型，永不修改）

独立文件、独立 `meta`（自己的 `schema_version`，迁移节奏与热库解耦），
因此可以单独备份、单独迁移、单独查询 —— 热库的日常备份不会被历史体积拖大。

```sql
PRAGMA journal_mode=DELETE;     -- 必须与热库一致（见 §4.5）
PRAGMA busy_timeout=5000;

CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);

-- 只 INSERT，永不 UPDATE/DELETE；故意不加外键：条目被 purge 之后历史必须仍然在
CREATE TABLE IF NOT EXISTS item_event(
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  at              TEXT NOT NULL,           -- 'YYYY-MM-DD HH:MM:SS'（Asia/Shanghai）
  action          TEXT NOT NULL,           -- create|update|complete|undo_complete|delete|purge
  item_id         INTEGER,                 -- 无外键
  occurrence_id   INTEGER,
  title           TEXT,                    -- 快照字段，历史单独可读
  category        TEXT,
  kind            TEXT,
  actor           TEXT NOT NULL DEFAULT '',      -- Matrix user_id（如 @keivry:mt.keivry.ren）
  actor_name      TEXT NOT NULL DEFAULT '',
  source          TEXT NOT NULL,           -- cli|plugin:/todo|hook:todo-reaction|tick|import
  room            TEXT,
  matrix_event_id TEXT,                    -- 相关 Matrix 事件 id（提醒消息 / 反应事件）
  reaction_emoji  TEXT,
  before_json     TEXT,                    -- 变更前关键字段快照
  after_json      TEXT,                    -- 变更后关键字段快照
  note            TEXT                     -- 如「已生成期次不变」
);
CREATE INDEX IF NOT EXISTS idx_event_item ON item_event(item_id, at);
CREATE INDEX IF NOT EXISTS idx_event_at   ON item_event(at);
```

### 4.3 跨库原子写入（关键机制，写错就丢历史）

```python
# store.py
def open_db(db_path=None, history_path=None):
    """返回一个「热库 + hist 已挂载」的连接。所有写路径都用它，绝不各开两个连接。"""
    con = sqlite3.connect(db_path or DB, timeout=5)
    con.row_factory = sqlite3.Row
    con.isolation_level = None                      # 手动管事务
    for pragma in ("journal_mode=DELETE", "busy_timeout=5000", "foreign_keys=ON"):
        con.execute("PRAGMA " + pragma)
    con.execute("ATTACH DATABASE ? AS hist", (str(history_path or HIST),))
    con.execute("PRAGMA hist.journal_mode=DELETE")
    con.execute("PRAGMA hist.busy_timeout=5000")
    return con


def record_event(con, action, *, item=None, occ=None, before=None, after=None, ctx=None, note=""):
    """只收 con —— 从接口上就强制调用方待在同一事务里。写 hist.item_event。"""
    con.execute(
        "INSERT INTO hist.item_event(at, action, item_id, occurrence_id, title, category, kind,"
        " actor, actor_name, source, room, matrix_event_id, reaction_emoji, before_json,"
        " after_json, note) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", ...)
```

### 4.4 三条硬规则（写成测试，不靠自觉）

1. **单一入口**：所有写操作都经 `store.record_event(action, item, occ, before, after, ctx)`，
   并与数据变更写在**同一个 `with con:` 事务**里 —— 数据落了历史必落；写历史失败则数据一起回滚。
2. **历史不可变**：`item_event` 只有 INSERT 与 SELECT，任何代码路径不得 UPDATE/DELETE 它
   （测试用 `sqlite3.set_authorizer`，按回调第 4 参 `db_name == "hist"` 断言 UPDATE/DELETE 被拒，
   不影响热库正常写 —— 见 T2b）。
3. **删除语义**：`rm` = 软删（`status='dropped'` + `deleted_at`）并写 `delete` 事件；物理删除只走
   `purge`（需 `--yes`），写 `purge` 事件，`occurrence`/`reminder` 一并删但 **`item_event` 全留**。

**历史三源合并**（查询时一条 SQL 跨库合并，不双写）：`hist.item_event`（变更）+
`main.reminder`（提醒已发送：期次/日期/房间/event_id）+ `main.reaction_seen`（原始反应：谁何时按了什么，
含被忽略的）。后两者留在热库是因为它们是**运行态**（幂等判重、撤销反查都靠它们），
体积也远小于事件表；如果你连原始反应也想一起归档，说一声，一并移进 `history.db`。

**期次状态的完整轨迹**：`occurrence.state` 只存**当前**状态，状态迁移全部落在 `item_event` 的
`before_json`/`after_json` 里 —— 所以「这一期什么时候被谁完成、又什么时候被撤销」永远查得到，
不会被后续操作覆盖。

### 4.5 为什么不给这两个库开 WAL（实测证据）

同一份负载，把 `journal_mode` 换个值，在 COMMIT 期间 SIGKILL 各 50 次：

- `journal_mode=delete`（rollback journal）：**0/50 漂移** —— 两库始终一致；
- `journal_mode=wal`：**33/50 漂移** —— 热库多提交一条、历史库漏记，而且**静默无报错**。

这就是 SQLite 官方说的「WAL 下跨库事务只在单库内原子，COMMIT 中途崩溃可能有的库生效有的不生效」。
对本系统来说漂移方向正好是最坏那种：**待办状态改了，但历史没记**。所以：

> **铁律：`todo.db` 与 `history.db` 都必须 `journal_mode=DELETE`（或 TRUNCATE/PERSIST），
> 永远不要改成 WAL。** 在 `open_db()` 里显式设置并写进测试（`test_journal_mode_is_not_wal`）。

代价是失去 WAL 的读写并发。本系统负载是「每天几次用户写 + 一次 tick」，单用户单机，
`busy_timeout=5000` 足够；WAL 在这里收益为零、风险为实。
**若将来真的需要 WAL**（例如并发量上来了），唯一正确做法是改成 outbox 模式：热库内建
`event_outbox` 与数据同事务写入（此时单库内原子），提交后立刻 flush 到 `history.db`，
按 `event_uuid` 唯一索引去重（至少一次投递），再由 `tick` 兜底补 flush。
复杂度明显更高，**现在不做**。

### 4.6 期次完成语义（务必按此实现）

- `task`：点击 → `item.status='done'` **且** occurrence `done`；撤销 → 两者回滚。
- `repeat`：点击 → **仅**该 occurrence `done`，条目继续存在，下一期由 tick 自动物化。
- `date`：点击 → **仅**当年 occurrence `done` =「今年已祝福」，无「完成」概念。

**提醒窗口**：`notify_date = occurrence_date - lead_days`。

- `task`（无 `due_at`）：每天出现在列表，直到 done。
- `task`（有 `due_at`）/ `repeat`：`today >= notify_date` 起提醒，逾期继续提醒并标「逾期 N 天」。
- `date`：`notify_date <= today <= occurrence_date`，当天过后停（不点也不删）。

**物化窗口**：tick 每次补算 `[today-7, today+400]`（task/repeat 其实只用到 +60，统一 400 更简单且幂等）。

## 5. 命令契约与消息模板

### 5.1 `/todo`（插件斜杠命令，0 LLM；Matrix 上无需 @）

```
/todo add 买牛奶 今天 个人              # 位置参数由 todo.py 解析
/todo add --kind repeat --rule weekly:1 --title 周会材料 --category work
/todo add --kind date --calendar lunar --lunar 8-15 --lead 7 --title 妈妈生日
/todo list [--category work] [--all] [--json]
/todo today [--category work]
/todo done 3        # 也接受 #3
/todo undo 3
/todo rm 3
/todo help
```

CLI 完整签名（`todo.py`，argparse）：

```
# 全局审计参数（挂在一个 add_help=False 的 parent parser 上，顶层与各子命令都接受）
--source S --actor U --actor-name N --room R

add    --title/位置参数  [--kind task|repeat|date] [--category C] [--due "YYYY-MM-DD[ HH:MM]"]
       [--rule SPEC] [--lead N] [--calendar solar|lunar] [--lunar M-D] [--notes S]
       [--priority 1|2|3] [--room !room:server]
edit   ID [--title T] [--due D] [--rule SPEC] [--lead N] [--category C] [--priority N]
       [--notes S] [--calendar solar|lunar] [--lunar M-D] [--room R]
list   [--category C] [--kind K] [--all] [--json]
today  [--category C]
show   ID                                  # 当前状态 + 历史时间线
history [ID] [--limit 50] [--all]          # 无 ID = 全库最近 N 条（跨库合并）
log    [--since D] [--until D] [--action A] [--category C] [--json]
export-history --out F [--since D] [--until D] [--format jsonl|csv]   # 归档（历史库专用）
doctor [--reconcile]                       # 两库健康检查 / 对账（见 T9c）
done   ID | #ID     [--date YYYY-MM-DD]
undo   ID | #ID
rm     ID                                  # 软删（写 delete 事件）
purge  ID --yes                            # 物理删（写 purge 事件，历史保留）
tick   [--dry-run] [--date YYYY-MM-DD] [--category C]
react  --action add|remove [--emoji E] [--msg-event-id X] [--reaction-event-id Y]
       [--user U] [--room R]
selftest
```

`--rule SPEC` 语法：`weekly:1` / `biweekly:3` / `monthly:1` / `monthly:-1`(月末) / `yearly:5-1`
（周几 1=周一 … 7=周日；`monthly:-1` = 该月最后一天）。

### 5.2 提醒消息模板（每房一条，胶囊 ≤10，超出分页）

```
📋 待办提醒 · 2026-10-12 09:00 · 工作

今天
1️⃣ 周会材料（每周一）
2️⃣ 交房租（每月 1 号，逾期 2 天）

生日 / 纪念日
3️⃣ 妈妈生日（3 天后 · 10-15）

未来 7 天
· 周三 结婚纪念日

点击号码表情 = 完成本期 / 再点一次 = 撤销
```

点击后**编辑同一条**：

```
📋 待办提醒 · 2026-10-12 09:00 · 工作

✅ 1️⃣ 周会材料（09:12 完成）
⬜ 2️⃣ 交房租（每月 1 号，逾期 2 天）
...
已更新 09:12 · 剩 2 项
```

### 5.3 配置文件 `/opt/data/env/todo/environment`

```
TODO_DB=/opt/data/state/todo/todo.db
TODO_HISTORY_DB=/opt/data/state/todo/history.db
TODO_ROOM_WORK=!待用户提供:mt.keivry.ren
TODO_ROOM_PERSONAL=!待用户提供:mt.keivry.ren
TODO_OWNER_USER=@keivry:mt.keivry.ren
TODO_DEFAULT_LEAD_ANNIVERSARY=7
TODO_DEFAULT_LEAD_TASK=0
TODO_MAX_CAPSULES=10
TODO_MATRIX_ENV_FILE=/opt/data/env/matrix-send/environment
TODO_SEND_PY=/opt/data/scripts/matrix-send/send_message.py
TODO_SEND_PYTHON=/opt/hermes/.venv/bin/python
TODO_HISTORY_DEFAULT_LIMIT=30
```

### 5.4 历史查询

```
/todo history 3                          # 单条目时间线
/todo history                            # 全库最近 30 条
/todo log --since 2026-10-01 --json      # 机器可读（SSH / 报表用）
```

`todo.py history 3` 输出示例：

```
#3 交房租 · repeat · personal · 每月 1 号 · 进行中
2026-09-25 08:11:32  创建      @keivry  plugin:/todo  每月 1 号 · lead 0
2026-10-01 09:00:03  提醒发送  system   tick          房间 personal · $ev1
2026-10-01 09:07:44  完成      @keivry  hook 1️⃣       occurrence 2026-10-01 pending→done
2026-10-01 09:08:10  撤销完成  @keivry  取消 1️⃣       occurrence 2026-10-01 done→pending
2026-10-01 09:31:02  完成      @keivry  hook 1️⃣       occurrence 2026-10-01 pending→done
2026-10-05 10:02:00  修改      @keivry  plugin:/todo  lead_days 0→3（已生成期次不变）
2026-10-12 09:00:02  提醒发送  system   tick          房间 personal · $ev2
```

`history` / `log` 都是**跨库查询**（一个连接里 `hist.item_event` 与热库 `reminder`/`reaction_seen`
一起 `UNION ALL`），所以你看到的是一条完整时间线，不需要自己去拼两个文件。
归档与体检：

```
/todo export-history --out /opt/data/backup/todo-history-2026.jsonl --since 2026-01-01
/todo doctor --reconcile
```

`--json` 每行一个 JSON 对象（JSONL），字段 = `item_event` 的列 + `rendered` 文本，
便于以后接报表或做统计。`/todo` 的**每次写操作回复末尾附一行回执**：
`已记录 · 2026-10-12 09:12`（让用户确信历史已经落库）。

## 6. 文件清单

**新建**

```
/opt/data/scripts/todo/todo.py          CLI 入口（argparse，子命令分发）
/opt/data/scripts/todo/store.py         DB 打开/建表/CRUD/幂等写入
/opt/data/scripts/todo/sched.py         日期与农历、重复规则、期次物化、提醒选取
/opt/data/scripts/todo/render.py        消息渲染 + 胶囊分配 + 点击后重渲染
/opt/data/scripts/todo/matrix_edit.py   m.replace（stdlib urllib，读同一 env 文件）
/opt/data/scripts/todo/notify.py        发送（包 send_message.py，回收 event_id）
/opt/data/scripts/todo/tick.py          cron 入口（纯 stdlib 启动器，wake-gate）
/opt/data/scripts/todo/tests/test_sched.py
/opt/data/scripts/todo/tests/test_store.py
/opt/data/scripts/todo/tests/test_render.py
/opt/data/scripts/todo/tests/test_cli.py
/opt/data/scripts/todo/tests/test_history.py        ← 审计历史（T2b / T6b / T9b）
/opt/data/state/todo/history.db                     ← 历史库（运行时自动创建；永久保留）
/opt/data/scripts/todo/tests/test_matrix_edit.py
/opt/data/env/todo/environment
/opt/data/hooks/todo-reaction/HOOK.yaml
/opt/data/hooks/todo-reaction/handler.py
/opt/data/plugins/todo/plugin.yaml
/opt/data/plugins/todo/__init__.py
/opt/data/github-work/hermes-office/docs/todo-reminder-design.md
skills/todo-reminder/SKILL.md（技能库，见 T16）
```

**已存在、复用**：`/opt/data/state/todo/venv`（lunardate 0.3.0）、
`/opt/data/scripts/matrix-send/send_message.py`、`/opt/data/env/matrix-send/environment`、
`patches/035-matrix-reaction-hook-forwarding.patch`（已推送）。

**修改**：`/opt/data/scripts/backup/hermes_backup.py`（白名单加两个库 + 一致快照，见 T13/T13b）、
`/opt/data/config.yaml`（仅启用插件后由 `hermes plugins enable` 写入）。

---

---

## 实现记录（2026-10-12）

状态：**核心已实现并验证**（T0–T13b 完成；T14 端到端 PoC 与 T15 补丁部署等用户输入）。

代码位置 `/opt/data/scripts/todo/`：`todo.py`（CLI 全量子命令）、`store.py`（两库/审计/对账）、
`sched.py`（农历/重复规则/选取）、`render.py`（渲染与胶囊）、`matrix_edit.py`（`m.replace`）、
`notify.py`（发送/编辑）、`tick.py`（cron 入口）；测试 `tests/`（46 条）。

### 与本文档的偏差（都是有原因的选择，不是遗漏）

1. **条目房间覆盖用 `--item-room`，不是 `--room`**：`--room` 被审计参数（谁在哪个房间操作）占用了，
   同一条命令里一个旗标两个含义会互相吃掉。审计参数 `--source/--actor/--actor-name/--room` 由顶层与
   各子命令统一接受。
2. **`hist.item_event` 保留 `AUTOINCREMENT`**：审计行号永不复用（将来有人手删也不会错位），代价是
   历史库里多一张 SQLite 内部表 `sqlite_sequence` —— 所以「历史库只有 item_event + meta」的断言写成
   `hist - {"sqlite_sequence"} == {"item_event", "meta"}`。
3. **原子性靠显式 `transaction()`，不靠 `with con:`**：`sqlite3` 默认 `isolation_level=""` 会在 DML 前
   隐式 BEGIN，裸 `INSERT` 不 commit 就在 `close()` 时被**静默回滚**（实现时真的把 `schema_version`
   弄丢过一次）。`open_db()` 现在用 `autocommit=True`，所有写路径走 `store.transaction(con)`。
4. **`purge` 同时清掉该条目的 `reminder_key`**：否则历史消息里的胶囊还会指向已删条目（点了没反应）。
   `item_event` 依旧全留、且写明 `action='purge'`。
5. **`tick` 有错误时非 0 退出**：否则 `wakeAgent:false` 会把「发送全失败」也静默掉，wake-gate 形同虚设。
   现在：无活可干 → 静默；房间没配/发送失败 → rc=1 → 唤醒 agent 报告。
6. **cron job 建为 paused**：两个房间 ID 还是占位符，启用会每天 09:00 报一次「没配房间」。房间配好即 resume。
7. **`store.history()` 返回新→旧**（照测试约定），CLI 展示时翻成时间正序。

### 实现中发现并修掉的 6 个坑（已写进技能 `todo-reminder`）

1. `isolation_level` 默认值静默回滚裸 INSERT（见偏差 3）。
2. `store` 的 mutator 签名是 `(db, item_id, ...)` —— `store.get_item(item_id)` 会把 id 当 db、静默去开
   一个叫 `3` 的库。已加护栏：`resolve_paths` 对非路径参数立刻 `TypeError`。
3. 全新库上必须先 `ensure()` 建表，否则 `add` 直接 `no such table: item`。
4. 规则生成的期次不得早于条目创建日，否则今天新建的「每周一」任务当天就显示「逾期 7 天」。
5. 农历三边界：腊月三十常不存在（退到该月最后一天）、无闰月时优先闰月会抛错（回落普通月）、
   农历十二月落在下一年公历 1–2 月（算「今年生日」要同时看 `year-1` 与 `year`）。
6. **撤销路径的幂等键必须用「撤回事件自己」的 id**：`m.room.redaction` 带的 `redacts` 是**被撤回的
   那个反应**的 id —— 而那个 id 已经被「完成」那次写进 `reaction_seen`（主键）。若拿它再插一次判重，
   `INSERT OR IGNORE` 会直接判成「已处理过」，**撤销永远不会生效**。所以 hook 额外传 `--redaction-event-id`
   （本次撤回事件的 id）作幂等键，`--reaction-event-id` 只用于反查原完成记录。
   这个 bug 是离线端到端测试（`tests/test_react.py`）抓出来的 —— 单元测试只看单点行为不会暴露它。
   另外：审计里存**客户端原样的** emoji（保留 VS16），只用归一化后的形态做匹配，别把原样形态丢掉。

### 关键验证证据（都是实跑）

| 项目 | 证据 |
| --- | --- |
| 单测 | `python -m unittest discover -s tests` → `Ran 51 tests ... OK`（含 6 条点击语义离线端到端） |
| 代码风格 | `ruff check .` + `ruff format --check .` 全过 |
| 跨库原子（rollback journal） | 实证 0/50 漂移；WAL 33/50 漂移 → 铁律写进 `open_db()` + 单测 + `doctor` |
| 历史不可篡改 | `sqlite3.set_authorizer` 按 `db_name=="hist"` 拒绝 UPDATE/DELETE，`main` 照常 |
| 同事务回滚 | `test_event_and_data_are_one_transaction`：写完事件后抛错 → 数据与历史一起回滚 |
| 拆分 | `test_tables_live_in_the_right_file`：热库无 `item_event`，历史库只有 `item_event`+`meta` |
| 幂等发送 | `reminder(occurrence_id, notify_date)` 唯一 + `INSERT OR IGNORE`；同日重跑不发第二条 |
| dry-run 可复现 | 两次 `tick --dry-run --date D` 输出 md5 相同（预览固定 09:00） |
| 备份 | 白名单含两库；`VACUUM INTO` 快照；恢复演练 `integrity_check=ok` + 表齐 + `schema_version=1` |
| 插件 | `hermes plugins doctor` rc=0、`validate` 「Validation passed.」、无内置命令冲突、已 enable |
| hook | AST OK + `HOOK.yaml` events 解析为 `['reaction:added','reaction:removed']` |

### 还没做／等用户拍板

- **两个房间 ID**（`TODO_ROOM_WORK` / `TODO_ROOM_PERSONAL`，**建房间不要开加密**）→ 填好后 resume cron job。
- **补丁 035 部署**：打进运行中的 `/opt/hermes` 需重启 gateway（本对话掉线几秒）；等镜像重建也可以。
  `Dockerfile` 的 roster 注释尚未加 035（计数已是 11，改它会触发 CI）。
- 可选：每年 `export-history` 离线归档（默认不做，每日备份已覆盖）。
