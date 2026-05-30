# jj — Shell-first JSON CLI

轻量、可组合、面向管道的 JSON 命令行工具。用 Zig 0.16 编写，零依赖，单二进制。

> `jo` 的易用性 + `jq` 的修改能力 + UNIX pipe 风格

---

## 设计哲学

| 原则            | 体现                                          |
| --------------- | --------------------------------------------- |
| 无 DSL          | `jj set user.name abc` 而非 `.user.name = abc` |
| shell-first     | 默认 stdin/stdout，天然 pipe                   |
| 自动路径创建    | `set user.profile.name x` 中间节点自动补全      |
| 类型推断        | `:=` 和 push 对象模式自动识别 bool/null/number  |
| `^jj^` 内联构造 | `set a ^jj b 1^` 等价于 `set a '{"b":1}'`       |
| 可组合          | 多指令链式执行，一次 pipe 完成多步操作          |
| 零依赖          | 单二进制，无运行时，无 GC                       |

---

## 构建

```sh
zig build -Doptimize=ReleaseSmall   # ~576KB
zig build                           # debug
zig build test                      # 运行 143 个单元测试
```

---

## 命令总览

| 命令                     | 说明                                        |
| ------------------------ | ------------------------------------------- |
| `new object\|array`      | 创建空 JSON                                 |
| `get <path> [--raw]`     | 读取值（`--raw` 去引号）                     |
| `set <p> <v> [p v]...`   | 设置值，支持多对语法和 JSON 内联             |
| `del <path>`             | 删除值                                      |
| `push <path> <v>...`     | 追加到数组（三种模式，见下文）                |
| `pop <path>`             | 弹出数组末尾                                |
| `pick <key>...`          | 仅保留指定字段                              |
| `omit <key>...`          | 移除指定字段                                |
| `pretty`                 | 格式化输出                                  |
| `compact`                | 压缩输出                                    |
| `type <path>`            | 查看字段类型                                |
| `merge <file>`           | 合并 JSON 文件                              |

---

## 基础用法

### 创建

```sh
jj new object              # => {}
jj new array               # => []
```

### 读取

```sh
echo '{"name":"abc","age":18}' | jj get name        # => "abc"
echo '{"name":"abc","age":18}' | jj get name --raw  # => abc
echo '{"name":"abc","age":18}' | jj get age --raw   # => 18
echo '{"name":"abc","age":18}' | jj type age        # => number
```

### set — 设置值

```sh
# 基本设置（值默认为 string）
echo '{}' | jj set user.name abc
# => {"user":{"name":"abc"}}

# 多对语法 — 一次设置多个字段
echo '{}' | jj set a 1 b 2 c 3
# => {"a":"1","b":"2","c":"3"}

# JSON 内联 — 值以 { 或 [ 开头时自动 parse
echo '{}' | jj set config '{"timeout":30,"retries":3}'
# => {"config":{"timeout":30,"retries":3}}

# 混合使用
echo '{}' | jj set name app config '{"port":8080}' debug:=true
# => {"name":"app","config":{"port":8080},"debug":true}
```

### del — 删除

```sh
echo '{"name":"abc","age":18}' | jj del age
# => {"name":"abc"}
```

### push — 追加到数组

push 有三种模式，根据参数形式自动判断：

| 模式           | 语法                      | 行为                                  |
| -------------- | ------------------------- | ------------------------------------- |
| 独立值         | `push v1 v2 v3`           | 追加多个值到根数组（inferType 推断）   |
| 根对象         | `push . k1 v1 k2 v2`      | 构建对象追加到根数组；root 为对象时 merge |
| 路径对象       | `push .path k1 v1 k2 v2`  | 构建对象追加到命名路径的数组           |

```sh
# 模式 1：独立值
echo '[]' | jj push hello world
# => ["hello","world"]

# 模式 2a：root 为数组 → 追加对象
echo '[]' | jj push . role user content hello
# => [{"role":"user","content":"hello"}]

# 模式 2b：root 为对象 → merge
echo '{"a":1}' | jj push . b 2
# => {"a":1,"b":2}

# 模式 3：路径对象 — 自动创建数组
echo '{}' | jj push .items name widget count 5
# => {"items":[{"name":"widget","count":5}]}

# 传统 key=value 语法仍然支持 TODO
echo '{}' | jj push history role=user content=hello
# => {"history":[{"role":"user","content":"hello"}]}

# push 内联 JSON
echo '[]' | jj push '{"x":1,"y":2}'
# => [{"x":1,"y":2}]
```

### pop — 弹出

```sh
echo '{"items":[1,2,3]}' | jj pop items
# => {"items":[1,2]}
```

### pick / omit — 字段过滤

```sh
echo '{"a":1,"b":2,"c":3}' | jj pick a b    # => {"a":1,"b":2}
echo '{"a":1,"b":2,"c":3}' | jj omit b c    # => {"a":1}
```

### pretty / compact — 格式化

```sh
echo '{"name":"abc","age":18}' | jj pretty
# {
#   "name": "abc",
#   "age": 18
# }

echo '{"name":"abc","age":18}' | jj compact
# => {"name":"abc","age":18}
```

### merge — 合并文件

```sh
echo '{"a":1}' | jj merge extra.json
```

---

## 类型推断

`inferType` 在 push 对象模式和 `:=` 简写中自动激活：

| 输入        | 推断结果           |
| ----------- | ------------------ |
| `true`      | `boolean: true`    |
| `false`     | `boolean: false`   |
| `null`      | `null`             |
| `42`        | `integer: 42`      |
| `-7`        | `integer: -7`      |
| `3.14`      | `number: 3.14`     |
| `1e3`       | `number: 1000.0`   |
| `hello`     | `string: "hello"`  |

```sh
# push 对象中值自动推断
echo '[]' | jj push . name widget active true count 42 weight 3.14
# => [{"name":"widget","active":true,"count":42,"weight":3.14}]

# push 独立值也推断
echo '[]' | jj push true 42 null hello
# => [true,42,null,"hello"]
```

---

## Shell-native 简写

```sh
echo '{}' | jj user.name=abc          # set string
echo '{}' | jj user.age:=18           # set auto-type (number)
echo '{}' | jj active:=true           # set auto-type (bool)
echo '{}' | jj tags+=dev              # array push
echo '{"name":"abc"}' | jj name-      # delete
```

| 语法  | 类型        | 示例            |
| ----- | ----------- | --------------- |
| `=`   | string      | `user.name=abc` |
| `:=`  | auto detect | `user.age:=18`  |
| `+=`  | array push  | `tags+=dev`     |
| `-`   | delete      | `user.age-`     |

---

## 多指令链式执行

多个命令在同一份 JSON 上依次执行，无需多次 pipe：

```sh
echo '{"a":1,"b":2,"c":3}' | jj set d 4 del b omit c
# => {"a":1,"d":"4"}

echo '{}' | jj set a 1 push tags dev push tags staging del a
# => {"tags":["dev","staging"]}

echo '{"name":"test","secret":"xxx","token":"yyy"}' | jj omit secret token set status active pretty
# {
#   "name": "test",
#   "status": "active"
# }
```

---

## Dot Path 语法

```
.                     根路径（normalizePath: . → ""）
.a                    等价 a（去掉前导 .）
.a.b                  等价 a.b
user.name             对象字段
history.0.role        数组索引
items.-               末尾元素（- = last）
```

normalizePath 规则：`.` → `""`，`.a` → `a`，`.a.b` → `a.b`，`a.b` → `a.b`

---

## `^jj^` 内联 JSON 构造

在 set/push 的 value 位置使用 `^jj <command> <args>... [command> <args>...]^` 语法，自动执行 jj 命令链并嵌入结果：

```sh
# ^jj set^ — 构造对象
echo '{}' | jj set a ^jj set b 1 ^
# => {"a":{"b":"1"}}

# ^jj push^ — 构造数组
echo '{}' | jj set a ^jj push 1 2 3 ^
# => {"a":[1,2,3]}

# 多命令链式 — set + push 在同一个 root 上执行
echo '{}' | jj set a ^jj set b 2 push .c 3 ^
# => {"a":{"b":"2","c":[3]}}

echo '{}' | jj set a ^jj set b 2 set c:=true push .d 4 ^
# => {"a":{"b":"2","c":true,"d":[4]}}

# set + del 链式
echo '{}' | jj set a ^jj set b 2 set c 3 del b ^
# => {"a":{"c":"3"}}

# set + omit 链式
echo '{}' | jj set a ^jj set b 2 set c 3 set d 4 omit c ^
# => {"a":{"b":"2","d":"4"}}

# push 对象模式
echo '{}' | jj set items ^jj push . x 1 y 2 ^
# => {"items":[{"x":1,"y":2}]}

# 单 token 形式（引号包围）
echo '{}' | jj set a '^jj set b 2 push .c 3^'
# => {"a":{"b":"2","c":[3]}}
```

支持的命令：`set`、`push`、`del`、`pop`、`pick`、`omit`。无命令名时退化为 key-value 对构造。

`^jj^` 预处理在命令分发前执行：将 token 按命令名分割为命令链，在同一个 root 上依次执行，结果序列化为 JSON 内联值。

---

## 智能拼接

shell 分词会破坏含空格的 JSON 对象。`jj` 自动逐个追加参数并尝试 parse，成功即停止：

```sh
# shell 展开后 {"b":"a b c"} 被分成 3 个 token
# jj 智能拼接回完整 JSON
echo '{}' | jj set a '{"b":"a b c"}'
# => {"a":{"b":"a b c"}}
```

此机制在 `set` 和 `push` 的 JSON 内联值中均生效。

---

## TTY 检测

stdin 为终端时（无 pipe 输入），`jj` 不阻塞等待，自动创建默认值：

```sh
# 无 stdin → 自动创建对象
jj set a 1 b 2
# => {"a":"1","b":"2"}

# 只有 push 无 set → 自动创建数组
jj push 1 2 3
# => ["1","2","3"]

# push 有 .path 形式 → 自动创建对象
jj push .items name widget
# => {"items":[{"name":"widget"}]}
```

---

## 文件模式

```sh
jj -f config.json set server.port 8080
# 等价于
cat config.json | jj set server.port 8080
```

---

## 选项

| 选项         | 说明                      |
| ------------ | ------------------------- |
| `-f, --file` | 从文件读取（替代 stdin）    |
| `--raw`      | 输出原始值（字符串不加引号） |

---

## 退出码

| 错误            | code |
| --------------- | ---- |
| parse error     | 1    |
| path not found  | 2    |
| invalid type    | 3    |

---

## 实战场景

### AI Agent — 构建 OpenAI messages

```sh
msgs=$(jj new array)
msgs=$(echo "$msgs" | jj push . role system content "$SYSTEM_PROMPT")
msgs=$(echo "$msgs" | jj push . role user content "hello")
```

### 无 pipe 快速构建

```sh
jj set name app version 1.0.0 debug:=false
# => {"name":"app","version":"1.0.0","debug":false}
```

### Shell 管道过滤

```sh
curl api.example.com | jj get data.items | jj pick id name
```

### CI/CD — 读取版本号

```sh
VERSION=$(cat package.json | jj get version --raw)
```

### 配置修改

```sh
jj -f config.json set server.port 8080 set server.host localhost
jj -f config.json set server.port 8080 server.host localhost
jj -f config.json server.port=8080 server.host=localhost
```

---

## 内部实现

### JSON 值表示

```
JsonValue = union(enum)
  null
  boolean: bool
  integer: i64          # 整数独立存储，不丢失精度
  number: f64           # 浮点数
  string: []const u8    # gpa.dupe 拥有所有权
  array:  ArrayList(JsonValue)
  object: String(JsonValue)   # 有序 map
```

### Parser

手写递归下降，支持：
- 完整 JSON 规范：null / bool / integer / float / string / array / object
- 科学计数法：`1e3`, `-2.5E+10`
- 字符串转义：`\" \\ \/ \n \r \t \b \f`
- Unicode escape：`\u0041` (1/2/3 字节 UTF-8 编码)
- Duplicate key：后值覆盖前值，旧 key/value 正确释放

### 路径操作

- `parsePath` — 将 dot path 解析为 `PathSegment` 序列（`.key` / `.index`）
- `set` — 递归遍历+自动创建中间节点（null → object/array）
- `del` — `fetchSwapRemove` + key/value 释放
- `push` — 路径不存在时自动创建空数组再追加
- `pop` — `orderedRemove` 返回弹出值
- `pick/omit` — 基于遍历的字段过滤
- `inferType` — 顺序尝试：bool → null → parseInt → parseFloat → string

### 内存安全

- 所有 `deinit` 递归释放子节点 + key 字符串
- `parseString` 返回 `gpa.dupe` 拥有所有权
- `fetchPut` duplicate key：释放新 key，保留旧 key
- `parseObject` errdefer 释放已分配的 key/value
- `set` 空路径替换 root：先 `root.deinit(gpa)` 再赋值
- 143 个测试全部通过，零泄漏

---

## 与现有工具对比

| 工具 | 优点         | 缺点                    |
| ---- | ------------ | ----------------------- |
| jq   | 表达力强     | DSL 学习曲线陡          |
| jo   | 简单易用     | 只能创建，不能修改       |
| yq   | YAML 全功能  | 复杂，Go 依赖           |
| fx   | 交互式友好   | 不适合脚本              |
| jj   | shell-first  | 无流式/transform 表达式 |

---

## 技术栈

| 项         | 值                                      |
| ---------- | --------------------------------------- |
| 语言       | Zig 0.16.0                              |
| JSON 解析  | 手写递归下降 parser                     |
| 内存       | Unmanaged 容器 + 显式 gpa，无 GC        |
| 测试       | 143 个单元测试（ops_test + main）        |
| 平台       | Linux / macOS / Windows                 |
| 体积       | ReleaseSmall ~576KB                     |

---

## 项目结构

```
jj/
├── build.zig          # 构建配置（ops_test + main 双测试 step）
├── build.zig.zon      # 包清单（Zig 0.16 格式）
└── src/
    ├── main.zig       # CLI 入口：参数解析、多指令分割、命令分发、
    │                  #   I/O、TTY 检测、normalizePath、parseValue、
    │                  #   execSet（多对+JSON 拼接）、execPush（三种模式+
    │                  #   对象构建+智能拼接）、execDel/Pop/Pick/Omit/
    │                  #   Type/Merge、execShorthand
    ├── ops.zig        # JSON 核心：JsonValue union、parse/get/set/del/
    │                  #   push/pop/pick/omit/merge/inferType、
    │                  #   writeTo/writePretty、parsePath、内存安全
    │                  #   deinit/clone
    └── ops_test.zig   # 143 个单元测试：parse 边界、writeTo/writePretty、
                       #   clone、路径、所有操作、roundtrip、组合操作
```

---

## License

MIT
