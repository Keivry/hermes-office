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
消息，并把「消息 event id + emoji → 条目」写进 DB；发送成功后**由机器人先播种号码胶囊**（对刚发出的
消息逐个 PUT `m.reaction`）—— **客户端只把已存在的反应渲染成可点的小气泡**，不播种用户在表情选择器里
根本找不到号码胶囊；用户点胶囊产生的反应经**补丁 035** 转发到
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
      │                                                        │ 播种 1️⃣..🔟（机器人）
      │                                                        │ 点 1️⃣ / 再点一次
      │  reaction:added / reaction:removed                      ▼
      └──────── hooks/todo-reaction/handler.py ◄── 补丁 035 转发反应
                          │ asyncio.create_subprocess_exec
                          ▼
                 todo.py react → 改 DB → matrix_edit.py 编辑原消息（m.replace）
```

播种那一步很关键：Matrix 客户端**只把「已存在」的反应渲染成可点的小气泡**，从没出现过的 emoji
（号码胶囊）在选择器里要翻到符号区才找得到 —— 不播种，用户就点不到、完成信号永远收不到。
机器人播出去的反应**不会**回流到 hook（`adapter._is_self_sender` 丢掉自己发的），所以不自触发。

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
  notes             TEXT NOT NULL DEFAULT '',                   -- 详情（show / list --notes 给全文）
  category          TEXT NOT NULL DEFAULT 'personal',           -- work | personal | 任意自定义
  kind              TEXT NOT NULL CHECK(kind IN('task','repeat','date')),
  status            TEXT NOT NULL DEFAULT 'open' CHECK(status IN('open','done','dropped')),
  -- start_at / due_at 是「一段时间」的两端，只有 task / repeat 用
  --   task：start = 开始日（默认今天）、due = 截止日（NULL = 无截止，天天出现且不标逾期）
  --   repeat：start = 系列起点（唯一锚点）、due = 系列终点（NULL = 永久重复）
  --   date：两者都不用（走 solar_* / lunar_*）
  start_at          TEXT,                                       -- 'YYYY-MM-DD'
  due_at            TEXT,
  next_due_at       TEXT,                                       -- after: 的运行期锚点（完成日+N）；every: 恒 NULL
  calendar          TEXT NOT NULL DEFAULT 'solar' CHECK(calendar IN('solar','lunar')),
  -- 纪念日（kind='date'）的月-日：公历走 solar_*，农历走 lunar_*；年份可空（空 = 不显示第 N 年）
  solar_month       INTEGER,
  solar_day         INTEGER,
  solar_year        INTEGER,
  lunar_month       INTEGER,
  lunar_day         INTEGER,
  lunar_year        INTEGER,
  lunar_prefer_leap INTEGER NOT NULL DEFAULT 1,                 -- 1=有闰月按闰月
  repeat_rule       TEXT,                                       -- JSON，见 §5
  lead_days         INTEGER NOT NULL DEFAULT 0,
  priority          INTEGER NOT NULL DEFAULT 2,                 -- 1 高 2 中 3 低
  deleted_at        TEXT,                                       -- 软删时间；NULL=未删（rm 只软删）
  room              TEXT,                                       -- 覆盖默认房间；NULL=按 category 映射
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);

-- 子任务清单：只挂 kind='task'（v1）。随条目级联删（purge 时自动清）。
-- 刻意不复用 item 表：那样会污染 _numbering_rows() 的行号语义（子任务会占一个行号）。
CREATE TABLE IF NOT EXISTS subtask(
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id    INTEGER NOT NULL REFERENCES item(id) ON DELETE CASCADE,
  title      TEXT NOT NULL,
  state      TEXT NOT NULL DEFAULT 'pending' CHECK(state IN('pending','done')),
  position   INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
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

-- 已发出的提醒：一个 (期次,日期,时段) 只发一次 → 幂等
CREATE TABLE IF NOT EXISTS reminder(
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  occurrence_id INTEGER NOT NULL REFERENCES occurrence(id) ON DELETE CASCADE,
  notify_date   TEXT NOT NULL,
  -- 时段维度：一天跑多次 tick（早/中/晚）时每个时段各发一次；
  -- 纪念日固定写 'day' → 一天最多一行（TODO_SLOT_MODE_ANNIVERSARY=all 才按时段）。
  slot          TEXT NOT NULL DEFAULT 'day',
  room          TEXT NOT NULL,
  event_id      TEXT,                                           -- 那条汇总消息
  sent_at       TEXT NOT NULL,
  UNIQUE(occurrence_id, notify_date, slot)
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

CREATE INDEX IF NOT EXISTS idx_occ_item   ON occurrence(item_id, occurrence_date);
CREATE INDEX IF NOT EXISTS idx_occ_date   ON occurrence(occurrence_date);
CREATE INDEX IF NOT EXISTS idx_rem_date   ON reminder(notify_date);
CREATE INDEX IF NOT EXISTS idx_key_item   ON reminder_key(item_id);
CREATE INDEX IF NOT EXISTS idx_sub_item   ON subtask(item_id, position, id);
```

### 4.2 历史库 `state/todo/history.db`（追加型，永不修改）

独立文件、独立 `meta`（各有自己的 `schema_version` 值，**但两库共用同一个 `SCHEMA_VERSION`
常量、版本不符时一起清空重建** —— 升热库版本会连历史库一起重建，"迁移节奏解耦"只说对了一半），
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
   （`sqlite3.set_authorizer` 那条断言测试**当年规划的 T2b 没有落地**，现存测试未覆盖；靠代码评审与
   `store/audit.py` 只 SELECT 的读路径保证）。
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
> 永远不要改成 WAL。** 两道防线：`open_db()` 每次显式设置 + `doctor` 每次体检
> （曾计划加一条 `test_journal_mode_is_not_wal` 单测，**实际没有落地** —— 别按它排障）。

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

**提醒窗口**：`notify_date = occurrence_date - lead_days`（`lead_days` 有 `MAX_LEAD_DAYS=36500` 兜底）。

- `task`（无 `due_at`）：每天出现在列表，直到 done，**不标逾期**（无截止就无所谓逾期）。
- `task`（有 `due_at`）：提醒门 = **`start_at − lead`**；`start ≤ today < due` 标「进行中」，
  `today == due` 标 `⏰`，过了 `due` 标 `❗逾期 N 天` 并继续提醒。
- `repeat`：`today >= notify_date` 起提醒，逾期继续提醒并标「逾期 N 天」；过了系列终点不再出期次。
- `date`：`notify_date <= today <= occurrence_date`，当天过后停（不点也不删）。

**物化窗口**：tick 每次补算 `[today-7, today+400]`（task/repeat 其实只用到 +60，统一 400 更简单且幂等）。
task 的下界取 `min(today−7, due_at)`，且 `collect_today` 另外捞 `occ_date < today−7` 仍 pending 的
task 期次 —— 逾期 >7 天的条目**不许消失**（D7）。

## 5. 命令契约与消息模板

### 5.1 `/todo`（插件斜杠命令，0 LLM；Matrix 上无需 @）

```
/todo add 买牛奶 今天 个人              # 位置参数由 todo.py 解析
/todo add --kind repeat --rule weekly:1 --start 2026-11-02 --due 2027-01-31 --title 周会材料 --category work
/todo add --kind date --lunar 8-15 --title 妈妈生日          # 农历，可写 --lunar 1950-8-15 记年份
/todo add --kind date --date 03-15 --title 老婆生日 --category personal
                                        # 公历生日，可写完整 --date 1990-03-15（记年份 → 显示「第 N 年」）
/todo add 报销 --due 2026-10-01 --notes "发票在抽屉"  # 补一条早该做的事：start 跟着到那天，一上来就逾期
/todo sub add 3 买牛奶 · /todo sub list 3 · /todo sub done 3 2   # 子任务（只挂 kind=task）
/todo list [--category work] [--all] [--json] [--notes]   # --notes = 展开备注全文
/todo today [--category work]
/todo done 3        # 也接受 #3
/todo undo 3
/todo rm 3
/todo help
```

CLI 完整签名（`todo.py`，argparse）：

```
# 全局审计参数（挂在一个 add_help=False 的 parent parser 上，顶层与各子命令都接受）
--source S --actor U --actor-name N --room R --html-out PATH
#   --html-out 只对报表型命令（list/today/show/history）写文件；list --json 与回执/help 明确不写

add    --title/位置参数  [--kind task|repeat|date] [--category C]
       [--start D] [--due D]                # 只收完整日期 YYYY-MM-DD（也认 今天/明天/后天/周X）
       [--date D]                           # kind=date 公历：MM-DD 或 YYYY-MM-DD
       [--rule SPEC] [--lead N] [--calendar solar|lunar] [--lunar M-D|YYYY-M-D] [--notes S]
       [--priority N] [--item-room !room:server]
edit   ID|#ID [--title T] [--start D] [--due D] [--date D] [--rule SPEC] [--lead N]
       [--category C] [--priority N] [--notes S] [--calendar solar|lunar]
       [--lunar M-D] [--item-room R]
list   [--category C] [--kind K] [--all] [--json] [--notes]
today  [--category C] [--date YYYY-MM-DD]
show   ID|#ID                              # 当前状态 + 备注全文 + 子任务 + 历史时间线
history [ID|#ID] [--limit 30] [--all]      # 无 ID = 最近 N 条（跨库合并；N=TODO_HISTORY_DEFAULT_LIMIT，默认 30）
log    [--since D] [--until D] [--action A] [--category C] [--json]
export-history --out F [--since D] [--until D] [--format jsonl|csv]   # 归档（历史库专用）
doctor [--reconcile]                       # 两库健康检查 / 对账（见 T9c）
tick   [--dry-run] [--date D] [--category C] [--slot 09|12|20]   # --slot = 手动指定时段（补跑/复现用）
done   ID|#ID     [--date YYYY-MM-DD]      # --date = 补记的完成日：先认 ≤ 该日最早的未完成期次，
                                           #   没有才按期建行（回执写「期次 X · 补记日 D」）；
                                           #   task 完成会级联把子任务一起置 done
undo   ID|#ID                              # task 撤销会复原子任务（含此前已单独勾完的）
rm     ID|#ID                              # 软删（写 delete 事件）
purge  ID|#ID --yes                        # 物理删（写 purge 事件，历史保留；子任务级联清）
sub    add ID 标题 | list ID | done ID 序号 | undo ID 序号 | rm ID 序号
                                           # 只挂 kind=task；子任务全勾完 → 父项自动完成
tick   [--dry-run] [--date YYYY-MM-DD] [--category C] [--slot 09|12|20]
react  --action add|remove [--emoji E] [--msg-event-id X] [--reaction-event-id Y]
       [--redaction-event-id Z]
       [--user U] [--room R]               # 内部命令：只给 reaction hook 调，不写进 help
selftest
```

**编号（2026-10-14 起）**：纯数字 = **`/todo list` 的行号**（未删条目按 `(priority, id)` 排序的第 N 行，
实现见 `todo_common.py:_numbering_rows()`；显示与解析共用这一份，过滤视图里显示的也是**全局**行号）；`#N` =
条目 id（`AUTOINCREMENT`，删除后不复用，永远精确）。7 个入口（`edit/show/history/done/undo/rm/purge`）
同口径：越界/非法报 `❌ …` 且 **rc=2、零写入**；已删条目**不占行号**，在 `list --all` 里显示成 `(已删) #id`。

**退出码（2026-10-14 统一）**：`0` 成功 · `1` 内部错误 · `2` 没做成（编号越界/非法、
无变更、缺参数、已是目标状态）。脚本/cron 按退出码判断，不要再返回「错误串 + rc=0」。
两类缺参数都归 2：CLI 自己判的给 `❌ …` 提示；argparse 自身的缺必填参数打印 `usage: …`（不带 `❌`，
但同样是 rc=2，别只按 `❌` 前缀判定失败）。

**报表自带 HTML（2026-10-14）**：`list`/`today`/`show`/`history` 生成 Element X 友好的 HTML
（`render.doc_to_html` / `text_to_html`，词汇表只有 `<p>`/`<strong>`），由 `--html-out` 落盘、插件经
`send_report.py` 子进程直发，**不交网关 markdown 渲染** —— 行首 `#` 会被 markdown 当 H1（Android 上
巨大字号 + 行距丢失，就是本轮修的 bug）。同一份 HTML 的纯文本兜底 body 由 `render.html_to_text` 统一给
（发送与 `m.replace` 共用），超 48KiB 按整段截断并附说明。

`--rule SPEC` 语法：`weekly:1` / `biweekly:3` / `monthly:1` / `monthly:-1`(月末) / `yearly:5-1` /
`every:60d`(固定节奏，未完成也照常出下一期) / `after:60d`(完成后起算，证书续签这类)
（周几 1=周一 … 7=周日；`monthly:-1` = 该月最后一天；间隔单位 `d`/`w`/`m`/`y`，**可省 = 天**）。

**重复系列的起点一律是 `--start`**（rev.5 统一，不写 = 今天）：`every:` / `after:` / 周期规则
（`weekly:`/`monthly:`/`yearly:`）共用同一个锚点，`--due` 只表示**系列终点**（不写 = 永久重复）。
运行期锚点另有口径：`every:` 恒用「起点 + k×N」（`item.next_due_at` 为 NULL）；`after:` 的锚点是
**完成日 + N**（存在 `item.next_due_at`，完成时推进、撤销时回退）。两者的 `--lead` 默认取
`TODO_LEAD_INTERVAL`（未设 = 0），其余规则仍用 `TODO_DEFAULT_LEAD_*`
（详见文末「更新记录（2026-10-13）：间隔重复规则」与「更新记录（2026-10-15）：时间段模型」）。

`--start` / `--due` 只接受完整日期 `YYYY-MM-DD`（也认 今天/明天/后天/周X）：含糊的 `MM-DD` 不进这两列，
否则会产出静默死条目。`--date` / `--lunar` 才是月-日入口，`--date MM-DD` 补成「下一个未到的该月日」
（含今天；`2-29` 落在非闰年时往后找闰年），`--lunar M-D` 由农历转公历。`add` 与 `edit` 走同一校验，
非法日期报 `❌ …` 且 **rc=2、不入库**（详见文末「更新记录（2026-10-13）」）。

### 5.2 提醒消息模板（每房一条，胶囊 ≤10，超出分页）

```
📋 待办提醒 · 2026-10-12 09:00 · 工作

逾期
❗ 交房租（每月 1 号 · 逾期 2 天）

今天
1️⃣ 周会材料（每周一）

生日 / 纪念日
2️⃣ 妈妈生日（3 天后 · 10-15）

未来 7 天
· 周三 结婚纪念日

点号码表情 = 完成本期 / 再点一次 = 撤销
```

点击后**编辑同一条**：

```
📋 待办提醒 · 2026-10-12 09:00 · 工作

✅ 1️⃣ 周会材料（09:12 完成）
⬜ 2️⃣ 交房租（每月 1 号，逾期 2 天）
...
已更新 09:12 · 剩 2 项
```

消息以 **HTML** 发出（`formatted_body`，只 `p`/`strong`），`body` 是同一份 HTML 经
`render.html_to_text` 反推的纯文本兜底；`m.replace` 的**顶层与 `m.new_content` 两层都带**
`format`/`formatted_body`（上面两段是等价的纯文本视图）。

### 5.3 配置文件 `/opt/data/env/todo/environment`

```
TODO_DB=/opt/data/state/todo/todo.db
TODO_HISTORY_DB=/opt/data/state/todo/history.db
TODO_ROOM_WORK=!待用户提供:mt.keivry.ren
TODO_ROOM_PERSONAL=!待用户提供:mt.keivry.ren
TODO_OWNER_USER=@keivry:mt.keivry.ren
TODO_DEFAULT_LEAD_ANNIVERSARY=7
TODO_DEFAULT_LEAD_TASK=0
TODO_LEAD_INTERVAL=0
TODO_MAX_CAPSULES=10
TODO_TICK_SLOTS=09,12,20
TODO_SLOT_MODE_ANNIVERSARY=day
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
/opt/data/scripts/todo/todo.py          CLI 入口（docstring/sys.path/--html-out 落盘/main）
/opt/data/scripts/todo/todo_common.py   公共小工具：Result / 审计上下文 / 编号（行号↔#id）/ 归属与房间
/opt/data/scripts/todo/todo_view.py     纯文本视图：item_line / item_brief（HTML 渲染在 render.py）
/opt/data/scripts/todo/todo_rules.py    重复规则与锚点：日期词/规则解析、算下一期、完成与撤销语义
/opt/data/scripts/todo/todo_items.py    add / edit / list / done / undo / rm / purge
/opt/data/scripts/todo/todo_tick.py     物化期次 + 预览 + 按房发送 + 提醒幂等键（tick / today）
/opt/data/scripts/todo/todo_react.py    胶囊反应 → 就地编辑原消息（m.replace）
/opt/data/scripts/todo/todo_query.py    history / show / log / export-history
/opt/data/scripts/todo/todo_health.py   doctor / selftest
/opt/data/scripts/todo/todo_cli.py      HELP_TEXT / _HelpParser / build_parser
/opt/data/scripts/todo/store/           存储层包（门面 + 8 模块，见下）
    __init__.py    门面：显式 re-export 全部对外名（import store; store.X(...) 契约不变）
    config.py      环境/路径：读 env/todo/environment、两库路径与默认值
    db.py          连接/建表/迁移/事务（DDL、open_db、transaction、_conn/_now 等包内公用件）
    events.py      审计写入：record_event（历史库唯一写入口）+ 条目快照与 diff
    items.py       item / occurrence：增查改软删物理删、期次读写、状态机
    anchor.py      锚点原语：complete / undo_complete
    reminder.py    reminder / reminder_key / reaction_seen：提醒幂等、胶囊去重、消息↔条目
    audit.py       审计读取：历史三源合并、计数、JSONL/CSV 导出与格式
    health.py      doctor（两库体检 + 对账）/ item_title / today_str
/opt/data/scripts/todo/sched.py         日期与农历、重复规则、期次物化、提醒选取
/opt/data/scripts/todo/render.py        消息渲染 + 胶囊分配 + 点击后重渲染
/opt/data/scripts/todo/matrix_edit.py   m.replace（stdlib urllib，读同一 env 文件）
/opt/data/scripts/todo/notify.py        发送（包 send_message.py，回收 event_id）
/opt/data/scripts/todo/tick.py          cron 入口（纯 stdlib 启动器，wake-gate）
/opt/data/scripts/todo/send_report.py   插件发送入口（纯 stdlib 启动器；报表 HTML 直发，2026-10-14）
/opt/data/scripts/todo/tests/react_test.py          ← 点击语义 + 完成/撤销/幂等（T9）
/opt/data/scripts/todo/tests/add_test.py            ← 建库与 --due / 农历校验
/opt/data/scripts/todo/tests/interval_test.py       ← every: / after: 间隔规则 + 审查回归（T16）
/opt/data/scripts/todo/tests/numbering_test.py      ← 行号 vs #id / 越界零写入 / 退出码 / --html-out（2026-10-14）
/opt/data/scripts/todo/tests/html_message_test.py   ← HTML 词汇表与转义 / 兜底 body 单源 / m.replace 两层 / 单行化 / 截断（2026-10-14）
/opt/data/scripts/todo/tests/store_package_test.py  ← store 包纯度（禁 sched/render/notify/lunardate）+ 门面覆盖现状调用面（2026-10-14，从 interval_test.py 拆出）
/opt/data/state/todo/history.db                     ← 历史库（运行时自动创建；永久保留）
（设计阶段的 `test_sched/test_store/test_render/test_cli/test_history/test_matrix_edit` 六个文件
 未按原计划拆分：实现按「一个测试类一个文件」收敛成上面六个，且一律 `*_test.py` 命名
 —— 躲开 disk-cleanup 对 `test_*` 的跟踪，所以 `unittest` 必须带 `-p '*_test.py'`。）
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

代码位置 `/opt/data/scripts/todo/`：`todo.py`（薄入口 + `todo_*.py` 家族：`todo_cli` argparse、
`todo_items` 条目命令、`todo_query` 查询、`todo_sub` 子任务、`todo_tick` 物化提醒、`todo_react` 胶囊、
`todo_health` 体检、`todo_rules` 规则锚点、`todo_view` 视图、`todo_common` 编号/审计）、
`store/`（包：门面 `__init__.py` + 9 模块，两库/审计/对账/子任务）、
`sched.py`（农历/重复规则/选取）、`render.py`（渲染与胶囊）、`matrix_edit.py`（`m.replace` 编辑 + `m.reaction` 播种）、
`notify.py`（发送/编辑/播种）、`tick.py`（cron 入口）；测试 `tests/`（**当日** 2 个文件 / 15 条：
`react_test.py` + `add_test.py`；**现值见文末「更新记录」—— 15 个文件 / 190 条**）。

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
   这个 bug 是离线端到端测试（`tests/react_test.py`）抓出来的 —— 单元测试只看单点行为不会暴露它。
   另外：审计里存**客户端原样的** emoji（保留 VS16），只用归一化后的形态做匹配，别把原样形态丢掉。

### 关键验证证据（都是实跑）

| 项目 | 证据 |
| --- | --- |
| 单测 | `python -m unittest discover -s tests -p '*_test.py'` → `Ran 15 tests ... OK`（**2026-10-12 当时**的 6 条点击语义 + 9 条 `--due` 校验；现为 `Ran 74 tests ... OK`，见文末更新记录）。**必须带 `-p '*_test.py'`**：五个文件都按 `*_test.py` 命名（避开 disk-cleanup 对 `test_*` 的跟踪），默认 `test*.py` 模式会跑 0 条（退出码 5，不会静默通过） |
| 代码风格 | `ruff check .` + `ruff format --check .` 全过 |
| 跨库原子（rollback journal） | 实证 0/50 漂移；WAL 33/50 漂移 → 铁律写进 `open_db()` + 单测 + `doctor` |
| 历史不可篡改 | `sqlite3.set_authorizer` 按 `db_name=="hist"` 拒绝 UPDATE/DELETE，`main` 照常 |
| 同事务回滚 | `test_event_and_data_are_one_transaction`：写完事件后抛错 → 数据与历史一起回滚 |
| 拆分 | `test_tables_live_in_the_right_file`：热库无 `item_event`，历史库只有 `item_event`+`meta` |
| 幂等发送 | `reminder(occurrence_id, notify_date, slot)` 唯一 + `INSERT OR IGNORE`；同**时段**重跑不发第二条 |
| dry-run 可复现 | 两次 `tick --dry-run --date D` 输出 md5 相同（预览固定 09:00） |
| 备份 | 白名单含两库；`VACUUM INTO` 快照；恢复演练 `integrity_check=ok` + 表齐 + `schema_version` |
| 插件 | `hermes plugins doctor` rc=0、`validate` 「Validation passed.」、无内置命令冲突、已 enable |
| hook | AST OK + `HOOK.yaml` events 解析为 `['reaction:added','reaction:removed']` |

---

## 更新记录（2026-10-13）：`--due` 校验与可选年份

**问题（静默死条目）**：`--due 03-15` 原本 rc=0、回执「已添加」，但 `due_at` 原样存成 `'03-15'` →
`sched.date_of()` 解析不出（返回 `None`）→ 纪念日 `anniversary_month_day()` = `(None, None)` →
**该条目永远不产生提醒，`tick` 也不报错**（`errors: []`），`list` 里显示成光秃秃的「纪念日」。

**修法**（`todo.py`，代码仓 commit `4619175`）：

1. 新增 `_normalize_due(text, today)`：`YYYY-MM-DD` 原样保留；`MM-DD` 补成「下一个未到的该月日」
   （含今天；`2-29` 落在非闰年时往后找闰年）；非法日期抛 `ValueError` → CLI 返回 `Result(…, 2)`
   → **rc=2 且不入库**。
2. `add` 与 `edit` 的 `--due` 统一走该校验（`kind=task` 同样受益，避免同类死条目）。
3. `kind=date` 的两条既有用法错误（缺日期、`--lunar` 与 `--due` 二选一）由「打印提示 + rc=0」改为 **rc=2**。
   其余「参数错误只打印提示、rc 仍为 0」的路径属既有约定，本次未动。
4. `HELP_TEXT` 纪念日行补 `--due MM-DD` 写法与「`--lead` 默认 7」（`store.default_lead('date') == 7`，
   与 §1 产品决策「纪念日提前 7 天」一致）。

**验证**（实跑）：`pytest tests` 15 passed；`unittest -p '*_test.py'` 15 OK；`selftest` ✓；
真实库 `doctor --reconcile` 全 ✓（只读体检，两库 mtime 未变）；`HELP_TEXT` 四路径逐字一致；
`ruff check` + `ruff format --check` 通过。新增 `tests/add_test.py`（9 条）：`MM-DD` 补全 / 闰日 /
`task` 同口径 / `edit` 同口径 / 非法 rc=2 且不入库 / **「生日前 3 天真的进提醒」防死条目回归**。

行为示例（今天 2026-10-13）：`/todo add 老婆生日 --kind date --due 03-15 --category personal`
→ 落库 `2027-03-15`、`lead_days=7`；`tick --dry-run --date 2027-03-12` 输出
`1️⃣ 老婆生日（3 天后 · 03-15）`。

---

## 更新记录（2026-10-13）：间隔重复规则 `every:` / `after:`（schema v2 → v3）

**动机**：`repeat` 原本只有「周/月/年」这类日历规则，缺「隔多长时间重复一次」。典型场景是 **SSL 证书续签**：
完成之后过一段时间才需要再次提醒（完成日 + N），而不是固定日历日。

1. 规则新增两条（语义由名字承载，不加 `--anchor` 参数）：`every:Nd` = **固定节奏**
   （期次 = 锚点 + k×N，未完成也照常出下一期）、`after:Nd` = **完成后起算**（锚点 = 完成日，完成后推 N）。
   单位 `d`/`w`/`m`/`y`（可省 = 天，`every:1w` ≡ `every:7d`）；首个日期用 `--due`（不写 = 今天）；
   `--lead` 默认取 `TODO_LEAD_INTERVAL`（未设 = 0）。
2. 存储：`item` 增 `next_due_at TEXT`（`after:` 的运行期锚点；`every:` 恒 NULL）→ **schema v2 → v3**，
   幂等 `ALTER TABLE … ADD COLUMN`；迁移在 `store.ensure()` 里跑，`doctor` 只读、不触发迁移。
3. 完成 / 撤销：`store.complete(next_due_at=)` 推进锚点；`store.undo_complete(reset_anchor=)` 回退锚点
   并清掉「完成时算出来的那一期」（= 当前锚点那一期 + 锚点之后的期次；已发过提醒的置 `skipped`），
   同时把落在新锚点上的 `skipped` 复活为 `pending`；完成行追加 `· ↻ 下次 YYYY-MM-DD`。
   （清理范围在二轮审查中收窄过：原来扫掉「所有 pending」，会连补记场景下用户本来就逾期的那一期
   一起删掉 —— 见下一条更新记录。）
4. 校验口径与 `--due` 对齐：非法 / 超大间隔（含首期推不出来）在 `add`/`edit` 即报
   `❌ 重复规则不合法：…` + **rc=2、不入库**；`done --date` 早于条目创建日报 rc=2；补记导致 `ack+N`
   已过期时把锚点钳到今天并在回执里说明。`materialize()` **逐条目隔离**：单条脏规则只进 `errors[]`
   （tick 因 `errors` 非空返回 rc=1 —— cron wake-gate 语义），不再让整轮 tick 停摆。
5. `describe_rule`：`every:2w` → 「每 2 周」（不再折算成 14 天）；`HELP_TEXT` 与 `add/edit --help` 同步。

**验证（实跑）**：`pytest tests` **49 passed**（原 15 + interval 26 + 审查回归 8）；`unittest -p '*_test.py'`
49 OK；`ruff check` / `format --check` 通过；`selftest` ✓；真实库 v2 → v3 迁移后行数逐项一致、两库仍非 WAL、
`doctor --reconcile` 全 ✓。

---

## 更新记录（2026-10-13 二轮审查）：再修 4 处缺陷

对第一轮修复（`4286a70`）做第二轮对抗验证（修复落地核对 + **mutation 验红** + 残留猎杀 + 文档口径核对），
又抓到 4 条真缺陷，全部修复，并各配一条**改前必红**的回归用例（`interval_test.py` 3 条 + `react_test.py` 1 条）：

1. **提前完成下一期 → 条目永久静默死亡**（`after:` 专用）：在 `lead` 窗口内点胶囊完成「下一期」时，
   `ack + N` 正好等于刚完成那期的日期 → 锚点原地打转，`materialize` 找不到可提醒的期次。
   修法：锚点改为 `max(完成日, 被完成期次日) + N`，并加「锚点不得落在**已完成**期次上」的护栏。
2. **`yearly` 的月/日不校验**：`yearly:13-1` / `yearly:0-0` 照样入库（`yearly:5-40` 被静默夹成 `5-31`），
   之后**每天** tick 都抛裸 `bad month number 13` → 整轮 rc=1、条目永不出期次。修法：与 `monthly` 同口径，
   入口校验「月 1–12、日 1–31」→ `❌ 重复规则不合法：…` + rc=2、不入库。
3. **撤销会删掉无关的逾期期次**：`undo` 的清理范围从「所有 pending」收窄为「本次完成派生的那一期
   （= 当前锚点）+ 锚点之后的期次」，锚点回退到「被撤销那期日期；若还有更早的未完成期次就以它为准」。
4. **`react` 不传 `--room` 会崩**：完成**已经落库**之后才 `AttributeError`（rc=1、回执丢失）→
   改 `getattr(args, "room", "")`。

另修一处**注释与代码相反**（`store.complete` 里「复活 skipped」那段注释写成了「不复活」）。

**验证（实跑）**：`pytest tests` **53 passed**（49 + 本轮 4 条回归）；`unittest -p '*_test.py'` → 53 OK；
4 条新用例在改前代码（`4286a70`）上 **4/4 全红**；`ruff check` / `format --check` 通过；真实两库未被本轮触碰
（mtime 不变）。

---

## 更新记录（2026-10-13 三轮）：补记 `done --date` 认已有的未完成期次

二轮审查末尾记的「已知残留」：`done --date D` 走 `upsert_occurrence(D)`，若已有**逾期未完成的期次**
（`D' ≠ D`），就为 D 另建一行并完成它 —— 逾期那期永远留在 `pending`（`list` 对不上、之后 `done`
还会去完成错的那一期），**撤销补记后更是变成两行 `pending`**。

实测（改前，`kind=date` 纪念日 10-20、当天没点、10-21 补记）：

```
done 1 --date 2026-10-21   →  期次 1/2026-10-20/pending  2/2027-10-20/pending  5/2026-10-21/done
undo 1                     →  期次 1/2026-10-20/pending  2/2027-10-20/pending  5/2026-10-21/pending
```

修法（`cmd_done`）：`--date D` 时**先认已有的未完成期次** —— 取「`≤ D` 里最早的 `pending` 期次」
作为完成对象（没有这样的期次才按 D 新建）；完成日 `ack` 仍是 D（`after:` 锚点照旧按 D 算）。
回执写成 `完成 #1 标题（期次 2026-10-20 · 补记日 2026-10-21）`，免得被看成改期。改后同一场景：

```
done 1 --date 2026-10-21   →  期次 1/2026-10-20/done  2/2027-10-20/pending
undo 1                     →  期次 1/2026-10-20/pending  2/2027-10-20/pending   （回到原状，不多行）
```

口径与不带 `--date` 的路径一致（那条由 `sched.pick_completion_date` 选期次）——**两条路径都只动
已有期次，不为未来凭空建行**。

**验证（实跑）**：新增回归 `test_backfill_consumes_existing_overdue_occurrence`（`interval_test.py`）
在改前代码（`3c9cec2`）上**红在行为断言上**（`'2026-10-21' unexpectedly found in [...]`）；
`pytest tests` **54 passed**；`unittest -p '*_test.py'` → 54 OK；`ruff check` / `format --check` 通过；
`selftest` ✓；真实两库 `doctor --reconcile` 全 ✓ 且 mtime 不变。

---

## 更新记录（2026-10-14）：序号改「行号」+ 报表/提醒自带 HTML + 退出码统一

**起因（用户报的两个问题）**：① 「列表序号把已删的也算上 / 显示的序号与 `done N` 命中的不是同一条」；
② Element X（Android）里 `/todo list` 渲染成一坨。

**根因**：① 行首编号以前直接是 `item.id` —— 删掉中间一条后断号，且 `done 3` 命中的是 id=3 而不是「第 3 行」；
② 网关把回复正文交给 python-markdown（`nl2br`；单段落还会剥 `<p>`），行首 `#3 · 买菜 · work` 被解析成
`<h1>`（实测 `<h1>3 · 买菜 · work</h1>`）→ Android 上巨大字号、项间不换行。

**改动**：

1. **序号（方案 A）**：`_numbering_rows()`（未删条目按 `(priority, id)` 排序的第 N 行）是序号**唯一基准**，
   显示（`item_line` / `_row_number`）与解析（`_resolve_handle`）共用；`#id` 保留精确语义
   （`AUTOINCREMENT`，删除后不复用）；7 个入口统一口径，越界/非法报告 `❌ …` 且 **rc=2、零写入**；
   `list --json` 增 `index`（纯增字段，已删为 null）；已删条目显示成 `(已删) #id`（行首不再是 `#`）；
   标题/备注里的换行由 `render.one_line()` 折成单行（否则能伪造出一行）；`isdecimal()` 替 `isdigit()`
   （`²` 曾裸抛 `ValueError` 且 rc=1）。
2. **渲染（Element X）**：报表/提醒**自带 HTML**（`render.doc_to_html` / `text_to_html` / `html_line`，
   词汇表只有 `<p>`/`<strong>`：不用 h1–h6，也不用列表标签）；`m.replace` 的顶层与 `m.new_content`
   两层都带 `formatted_body`；回执与 `HELP_TEXT` 一律不以 `#` 开头（本轮就是 help 那行 `#7 = …` 让 bug 复发）。
3. **发送 / 编辑**：报表由插件经 `scripts/todo/send_report.py` **子进程**发出 —— 插件不再在 gateway 进程内
   import todo 模块（`notify`/`render`/`store`/`matrix_edit` 都是通用名，进程内 import 需 `sys.path` 注入 +
   裸名 import，会污染 gateway 的 `sys.modules` 且跨会话存活）；发送失败落 warning 后回退网关渲染。
   纯文本兜底 body **单源**（`render.html_to_text`：发送走 `matrix-send --plain-file`、就地编辑同源）；
   `sched.py` 的 `lunardate` 改惰性导入（否则缺它的解释器连 `import render` 都失败、报表全退回 markdown）。
4. **退出码统一**：`❌` ⟺ rc=2（此前「已经是完成状态 / 无变化 / 找不到 / 缺字段 / purge 缺 --yes」等分支
   返回错误串但 rc=0，脚本与 cron 无法判断失败）。
5. **性能 / 容量**：`materialize` 改**一条连接 + 一个事务**（此前每条目一条连接：500 条实测 `today` 14.2s，
   插件侧 CLI 超时只有 20s）；报表 HTML 超 `HTML_OUT_MAX_BYTES=48000` 按整段截断 + 附说明（一次报表是
   **一条** Matrix 事件，Synapse 默认 `max_event_size=64KiB`，500 条实测 116KB 会被整条拒收）。
6. **`_strip_tags`** 只剥「看着像标签」的（原 `<[^>]+>` 会把未转义的 `a < b > c` 吃成 `a  c`）。

**验证（实跑）**：`pytest scripts/todo/tests -q` → **74 passed, 5 subtests**（5 个文件 210.9s；新增
`numbering_test.py` 14 条、`html_message_test.py` 6 条）；`ruff check` + `ruff format --check` 通过
（`/opt/data/home/.local/bin/ruff`，脚本目录 + `plugins/todo`）；`help` / `--help` / `-h` / 无参数 /
带审计参数 五路输出 **sha256 完全相同**、2751 字节、**0 行以 `#` 开头**；`selftest` rc=0；
`doctor --reconcile` 全 ✅ rc=0（item=11 / occurrence=139 / item_event=38，与改动前一致）；
`tick --dry-run` rc=0 `errors:[]`；个人房实发 11 条测试条目 → 2 页提醒、`formatted_body` 全 `<p>`、
零 h1，模拟点击后 `m.replace` 两层都带富文本（测试消息与回执已按用户要求 redact）。

**当时未做**：`store.py`(1650 行) / `todo.py`(1679 行) 越过「单文件 >1000 行」阈值的拆分 —— 已于同日
按映射方案落地，见下一条更新记录。

## 更新记录（2026-10-14 二轮）：结构重构（store 包 + todo 家族，零行为变更）

**起因**：`store.py` 1650 行 / `todo.py` 1679 行越过「单文件 ≤1000 行」红线，`build_parser` 单函数 153 行。
用户拍板：**方案 A（按职责细切）+ 两期一起做**。

**改法（纯搬迁）**：`store.py` → `store/` **包**（门面 `__init__.py` + 8 模块，最大 344 行）；
`todo.py` → 薄入口（100 行）+ 9 个 `todo_*.py`（最大 369 行）。拆分依据先落成映射方案
（`cache/scratch/todo_split/PLAN.md`：逐符号归属表 + 风险对策 + 验收清单），映射用 AST 做覆盖自检
（`store` 76/76、`todo` 71/71，无遗漏、无重复）。

**为什么 store 必须是包**：`import store` + `store.X(...)` 是既有对外契约（`todo_*.py`、`notify.py`、
测试进程内都在用）。包门面逐个点名 re-export，调用方**一行都不用改**。副作用要防：包内模块名与
同名函数会互相遮蔽，所以 `env/doctor/history` 三个模块名分别改叫 `config/health/audit`
（`store.env()` / `store.doctor` / `store.history` 仍是函数）。

**为什么 `todo_*.py` 用前缀而不是也做包**：这些模块只被 CLI 子进程 import（全仓 `import todo` 0 处），
不进 gateway 进程，裸名冲突面为零；前缀同时避开与 stdlib 撞名（本目录原有的 `sched.py` 就是同类坑）。

**零行为变更的证据（实跑）**：
1. **147 个原符号 AST 逐字对比**（`ast.unparse` 归一化前后）→ **零缺失、零差异**（唯一新增是门面的 `__all__`）；
2. **CLI 基线 43 条命令**（help/list/today/show/history/log/doctor/export/tick/selftest + 写路径 + 越界错误路径，
   在真实库副本上跑）：拆分**前 = 期 1 = 期 2 三次快照逐字节一致**（rc 也一致）；
3. `pytest scripts/todo/tests -q` → **76 passed, 5 subtests**（原 74 + 新增 2 条守护：store 包纯度、
   门面覆盖现状调用面）；期 1 单跑亦绿；
4. `help` 五路 sha256 仍**完全相同**、2751 字节、0 行首 `#`；`selftest` / `doctor --reconcile` /
   `tick --dry-run` rc=0（真实库 item=11 / occurrence=139 / item_event=38 未变）；`store.__file__` 指向
   `store/__init__.py`；18 个新模块（9 个 `store/*` + 9 个 `todo_*.py`，连同入口 `todo.py` 共 19 个文件）**逐个单独 import** 成功（查循环导入）。

**踩到的两个坑（生成器 bug，都当场修掉）**：① 按 `node.lineno` 切片会**丢掉装饰器**
（`@contextlib.contextmanager` → `transaction` 变成普通生成器函数，`with transaction(con)` 直接
`TypeError`）；② 入口的 `if __name__ == "__main__"` **不是符号**，不补回就「跑完什么都不输出、rc=0」。

**测试守护同步**：`test_only_wrappers_call_store_complete` 的源码扫描从「只读 `todo.py`」改为
「入口 + 全部 `todo_*.py`」（原意不变：全家只允许 2 处 `store.complete(` / 1 处 `store.undo_complete(`）。

**门禁范围**：ruff 从「逐个列文件」改为目录形式 `todo.py todo_*.py store/ tests/ plugins/todo`
（上一轮踩过：新增文件不在门禁里）。

**未做（沿用）**：`build_parser` 仍是一个 153 行的函数——按子命令再拆会引入参数定义与 handler 的
位置耦合，收益不抵风险，留作既有项。

## 更新记录（2026-10-14 三轮）：红线收口 —— 测试文件拆出 + 超长函数登记

**起因**：二轮审查（4 路并行）报回两类落差，用户拍板一并处理。

**① `tests/interval_test.py` 1019 行越过「单文件 ≤1000 行」红线**（二轮新增的 3 条守护把它顶了出去）。
处理：`StorePackagePurityTest`（569–614，46 行）整体搬到新文件 `tests/store_package_test.py`——
该类只依赖源码文本（`ast`）与门面属性，与 `every:`/`after:` 的端到端上下文无耦合。搬完
`interval_test.py` **1019 → 971 行**，红线恢复；两个文件合计用例数 **40 不变**（38 + 2）。

**② 超长函数登记（口径与 `build_parser` 一致：留作既有项，不硬拆）**。全仓实测 >100 行的函数恰好三个：

| 函数 | 行数 | 不拆的理由 |
|:--|:--|:--|
| `todo_cli.build_parser()` | 153 | 按子命令再拆会把「参数定义」与「handler 绑定」拆到两处，位置耦合，收益不抵风险（二轮已记录） |
| `store/health.py:doctor()` | 173 | 线性体检清单：一份共享诊断状态（`lines` / `problems`）+ 顺序判定（`check()` 闭包）。拆成多函数要把该状态显式传递或改写成类 —— 属结构性改写而非搬迁，且 `doctor` 的 ❌ 文案是 CLI 稳定输出面，改动即漂移风险 |
| `store/anchor.py:undo_complete()` | 116 | 单事务内「读 → 判分 → 锚点回退 + 清残留期次 → 回滚多表 → 落事件」的线性流程。分段函数会把事务边界与状态依赖散开，而这里**正是拆分最容易出事故的形态**（期次删除/改 skipped 的判定链） |

**证据（实跑）**：搬移用 AST 切片，判据与二轮同一套 —— 原文件其余顶层符号 `ast.unparse` 逐字不变
（`only_old=['StorePackagePurityTest']`、无新增、无共同差异），搬走类新旧逐字相同；`pytest
scripts/todo/tests -q` → **76 passed, 5 subtests**（exit 0），用例集按文件名归一后与改前**完全一致**
（只差那 2 条换了文件）；`ruff check` / `ruff format --check` 对 27 个文件全过。

## 更新记录（2026-10-15）：时间段模型 + 子任务 + 备注详情（schema v3 → v4）

**三件事一次做完**：① 备注/详情能看全；② 三种 kind 各自明确的时间语义（含逾期永不再消失）；
③ 子任务清单。**schema v3 → v4，不向后兼容**（用户明确「数据可丢、无需兼容」）：`init_db` 见版本
不符就**清库重建**（drop 全部表 → 按新 `SCHEMA` 重建），重建前自动 `VACUUM INTO` 快照两库
（`*-schema3-backup-<ts>.db`），另有一份手工 `cp` 备份。旧的 `_migrate_item_next_due_at` /
`_migrate_reminder_slot` 连同迁移回归用例一起删除，`_migrate()` 留空壳 + 注释。

**时间语义（四个概念、四组列，互不重叠）**：

| kind | `start_at` | `due_at` | 其他 |
|:--|:--|:--|:--|
| `task` | 开始日（默认今天；`--due` 写过去时跟着到那天） | 截止日；**NULL = 无截止**：天天出现但不标逾期 | — |
| `repeat` | **系列起点（唯一锚点）**，不写 = 今天 | **系列终点**，不写 = 永久重复 | `next_due_at` 仅 `after:` 用 |
| `date` | 不用 | 不用 | `solar_month/day/year`、`lunar_month/day/year` |

- **`date` 去伪年份**：以前公历生日把月-日塞进 `due_at`，年份是 `_normalize_due` 编的假年份
  （`03-15` → `2027-03-15`）。现在公历走 `solar_*`、农历走 `lunar_*`，`--date 1990-03-15` /
  `--lunar 1950-8-15` 的年份存进 `solar_year` / `lunar_year`，用来显示「第 N 年」（算出的 N < 1
  则不显示，防未来日期印出「第 -8 年」）。
- **`repeat` 起点统一**：以前 `every:`/`after:` 认 `--due` 当锚点，而 `weekly:`/`monthly:`/`yearly:`
  认「创建日地板」并**忽略**存储的 `--due`（同一份 CLI 两种语义）。现在**一律 `--start`**；
  `repeat` 的 `--start` 晚于 `--due` 报 `❌ --start … 晚于 --due …`；`--due` 早于首个期日另报
  「系列终点在第一个期日之前，这条重复永远不会触发」（都是静默死条目，两条都必须拦）。
- **task 窗口三态**：`start ≤ today < due` = 进行中（`⏳ 进行中 · 截止 MM-DD · 还有 N 天`）；
  `today == due` 标 `⏰`；过了 `due` = 逾期（`❗` + `<strong>`）。提醒门用 **`start − lead`**
  （用 `due − lead` 的话「进行中」永远看不到）。`--start` 晚于 `--due` 对 task 是**合法**的
  （「补一条早该做的事」），逾期判定排在「还没开始」之前。
- **D7 逾期 >7 天不许消失**（两处都要改，缺一仍会隐形）：① `_materialize_item` 的 task 地板
  `today−7` → `min(today−7, due)`；② `collect_today` 额外取 `occ_date < today−7` 且仍
  pending 的 task 期次（`store.pending_task_occurrences_before`）。代价：拖 300 天的任务会
  每天三档提醒到完成为止 —— 已确认接受。
- **逾期区**：逾期条目单独成区「逾期」，`render.section_for` 是分区唯一来源（发送与 `m.replace`
  共用），胶囊编号**分区后按显示顺序**重排（否则逾期区会显示成 `2️⃣ 3️⃣ … 1️⃣`）。

**子任务（v1 只挂 `kind='task'`）**：新表 `subtask(id, item_id, title, state, position, created_at,
updated_at)`，**刻意不复用 `item` 表**（会污染 `_numbering_rows()` 的行号语义）。CLI 是嵌套子命令
`sub add|list|done|undo|rm`（`store/subtasks.py`，`MAX_SUBTASK_TITLE=200`、`MAX_SUBTASKS` 上限）。
级联：手动完成父项 → 未完成子任务全部 done；撤销 → 全部复原；**子任务全勾完 → 父项自动完成**。
`sub undo` 单条撤销**不碰**兄弟子任务（`undo_complete(cascade_subtasks=False)`）。子任务**不**
走表情胶囊（一条提醒消息只有自己的胶囊位），仍是 CLI-only。

**新增/改动的列与表**：`item` 加 `start_at`、`solar_month`、`solar_day`、`solar_year`、`lunar_year`；
新增 `subtask`。`store.health.doctor` 增查 schema 版本、纪念日月/日完整性、`subtask` 表。

**命令面变化**：`--start` / `--date` / `list --notes`；`show` 出备注全文 + 子任务；`sub` 家族。
`--start`/`--due` 只收完整 `YYYY-MM-DD`（也认 今天/明天/后天/周X），`MM-DD` 归 `--date`；
`--calendar lunar` 与 `--date` 互斥；空串日期（`--due ""`）按「没给」报 rc=2，不再静默当无截止。
`--lead` 上限 3650 天、农历日 1–30（31 曾会被静默钳）、`notify_date` 的 `lead_days` 有
`MAX_LEAD_DAYS=36500` 兜底（否则 `OverflowError` 会带走整个 tick）。

**测试**：新增 `start_at_test.py`、`date_flag_test.py`、`lunar_test.py`、`subtask_test.py`、
`overdue_test.py`、`notes_test.py`、`rebuild_test.py`；改写 `add_test.py`（参数校验 + 零写入契约）、
`interval_test.py`（14 处 `--due` 改写：13 → `--start`、1 处 date → `--date`）、
`store_package_test.py`（门面新符号 + `subtasks.py` 在纯度扫描内）、
`numbering_test.py`（**子命令清单自检**：`build_parser()` 的每个子命令都要在 `HELP_TEXT` 出现，
反向也查 help 里写的命令必须真存在；`react` 是钩子专用内部命令，走白名单）。

**踩过的坑（已写进技能 `todo-reminder`）**：新写的 `date_flag_test.py` 跑非 `--dry-run` 的 `tick`
且没设离线保险，**真把测试提醒发进了生产房间** —— 胶囊键写在临时库里，生产库没有，用户点号码表情
全部落空（`reaction.log` 里一片 `ignored（找不到对应的完成记录）`）。结论：**换 `TODO_DB` ≠ 不联网**，
测试/探针跑 `tick` 必须 `--dry-run` **且** `TODO_MATRIX_ENV_FILE=<不存在>`。

## 上线配置（2026-10-12，已生效）

### 房间

| 分类 | 房间 ID | 加密 |
| --- | --- | --- |
| 工作 | `!rrQWcHbW2f3uIhCrXH:mt.keivry.ren` | 无（明文发送才可用；实测 `m.room.encryption` 事件不存在） |
| 个人 | `!WZzY1q7LYt2Jsp3Vzv:mt.keivry.ren` | 无 |

两房间成员：`@keivry` + `@paimon`。真实投递验证：走 `notify.send`（与 tick 同一条路径）
各发一条连通测试消息，均返回 `event_id`（投递链路端到端可用）。

### 一天三次：`0 9,12,20 * * *`

原来按「天」去重（`UNIQUE(occurrence_id, notify_date)`），一天跑三次只有第一次发得出去 ——
所以提醒的幂等粒度升级为「天 + 时段」（`schema_version` 1 → 2）：

- **时段归属**：取 `TODO_TICK_SLOTS`（默认 `09,12,20`）里**不晚于当前时刻的最后一个时段**。
  手动跑、网关晚点补跑都落在确定时段上 → 天然幂等；网关停机错过某时段不会事后补发（内容本来就一样）。
- **待办 / 重复任务**：每个时段各发一次（没完成就早中晚都提醒）。
- **纪念日（`kind=date`）**：固定写 `slot='day'` → **一天最多一行**（沿用用户确认的规则）；
  `TODO_SLOT_MODE_ANNIVERSARY=all` 可改成按时段各提醒一次。
- **「未来 7 天」预览行**：只在当天第一个时段出现，免得一天刷三遍。
- **老库自动迁移**：`_migrate()` 检测 `reminder` 缺 `slot` 列 → 重建表并把老行补 `slot='day'`
  （迁移在写 `schema_version` 之前，失败就不会被标成新版本）。真实两库已升到 **v3**
  （v1 → v2 = `slot` 时段维度；v2 → v3 = `item.next_due_at`，见上一条更新记录）。

### cron

`脚本 job`：`script=todo/tick.py`，`schedule=0 9,12,20 * * *`，`deliver=origin`。
成功 → 最后一行 `{"wakeAgent": false}`（0 LLM、0 token）；只有失败才唤醒 agent 报告。

### 补丁 035

`Dockerfile` roster 注释 10 → 11 并加了 035 说明块；推送后 CI（run `38229901049`，`432a194`）
**构建成功**，构建日志可见 `==> Applying 035-matrix-reaction-hook-forwarding.patch` /
`patching file plugins/platforms/matrix/adapter.py` → 035 已在镜像
`ghcr.io/keivry/hermes-office` 里。推送前的独立复验：把 035 打在**已含 007–034 的树**上
（正是 CI 的落地顺序）`patch -p1` rc=0、无 fuzz、无 `.rej/.orig`，`py_compile` 干净，
`ruff` 与基线**完全一致**（前后同为 3 条既存告警，补丁零新增）；且 035 是唯一碰
`plugins/platforms/matrix/adapter.py` 的补丁 → 不存在补丁间交叉干扰。

✅ **035 已在运行环境生效**（2026-10-13 复核，原「要等新镜像」的等待已解除）：运行树
`/opt/hermes/plugins/platforms/matrix/adapter.py` 已含 `_forward_reaction_event()` 与
`reaction:added` 转发分支，该文件 mtime 2026-10-13 10:09；gateway 进程 2026-10-13 10:30:37
启动（晚于该 mtime → 加载的就是这份代码）；hook 本体 `/opt/data/hooks/todo-reaction/HOOK.yaml`
的 `events` 已声明 `reaction:added` / `reaction:removed`。

✅ **端到端复验完成**（2026-10-16）：真实胶囊点击已跑通 —— 手动播种 1️⃣ 后用户实点，链路
`reaction.log`（`reaction:added`）→ `reaction_seen` 落库 → `occurrence 1053 pending→done` →
原消息就地编辑为 `✅ 1️⃣ 备份系统（10:24 完成）` 全部到位（此前 2026-10-13 的结论只有代码级证据）。

🔴 **同次排障发现的真实断点（已修）**：提醒消息**从未播种过号码胶囊反应**，而客户端只把
「已存在的反应」渲染成可点气泡 —— 消息上没有 chip，用户就点不动。此前"点不了"的观感被误判为
补丁 035 未生效 / 客户端限制 / 加密房间；服务端取证（personal 房 `@keivry` 的 `m.reaction` = 0 条，
房内反应全部来自 `@paimon` 的 ✅ 回执）才定位到根因。修法：`matrix_edit.py` 加
`send_reaction`/`react_many`/`react` + `--emoji` CLI；`notify.py` 加 `seed()`；`todo_tick.py` 发送成功后
按 `page["keys"]` 播种（失败不连坐已发出的提醒）。机器人自己的反应不会回流到 hook
（`_is_self_sender` 过滤），故不自触发。测试 +9（`seed_test.py`），全量 190 通过。

### 已确认不做

- 每年 `export-history` 离线归档：不做（每日备份已覆盖）。
