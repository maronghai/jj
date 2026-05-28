# `jj` — Shell-first JSON CLI

轻量级、可组合、面向管道的 JSON 命令行工具。

> `jo` 的易用性 + `jq` 的修改能力 + UNIX 工具链风格

## 特性

- **小体积** — 单二进制，零依赖，ReleaseSmall ~574KB
- **高性能** — Zig 编译为原生代码，无 GC，启动 < 5ms
- **shell-first** — 默认 stdin/stdout，天然可 pipe
- **无 DSL** — 直接用 `jj set user.name abc`，不学新语法
- **多指令链式执行** — `jj set a 1 del b push c v omit d` 一次操作多个命令
- **类型推断** — `:=` 语法自动识别 number / bool / null

## 快速开始

### 构建

```sh
zig build -Doptimize=ReleaseSmall
```

### 基本用法

```sh
# 创建
jj new object          # => {}
jj new array           # => []

# 读取
echo '{"name":"abc","age":18}' | jj get name --raw   # => abc
echo '{"name":"abc","age":18}' | jj get age --raw    # => 18
echo '{"name":"abc","age":18}' | jj type age          # => number

# 设置（自动创建路径）
echo '{}' | jj set user.name abc
# => {"user":{"name":"abc"}}

# 删除
echo '{"name":"abc","age":18}' | jj del age
# => {"name":"abc"}

# 向数组追加（自动创建数组）
echo '{}' | jj push history role=user content=hello
# => {"history":[{"role":"user","content":"hello"}]}

echo '{}' | jj push tags dev
# => {"tags":["dev"]}

# 从数组弹出
echo '{"items":[1,2,3]}' | jj pop items
# => {"items":[1,2]}

# 保留 / 移除字段
echo '{"a":1,"b":2,"c":3}' | jj pick a b    # => {"a":1,"b":2}
echo '{"a":1,"b":2,"c":3}' | jj omit b c    # => {"a":1}

# 格式化
echo '{"name":"abc"}' | jj pretty
# => {
#      "name": "abc"
#    }

echo '{"name":"abc"}' | jj compact
# => {"name":"abc"}

# 合并
echo '{"a":1}' | jj merge extra.json

# 多指令链式操作（同一份 JSON 依次执行）
echo '{"a":1,"b":2,"c":3}' | jj set d 4 del b omit c
# => {"a":1,"d":"4"}

echo '{}' | jj set a 1 push tags dev push tags staging del a
# => {"tags":["dev","staging"]}

echo '{"name":"test","secret":"xxx","token":"yyy"}' | jj omit secret token set status active pretty
# => {
#      "name": "test",
#      "status": "active"
#    }

# 文件模式（等价于 cat + pipe）
jj -f config.json set server.port 8080
```

### Shell-native 简写

```sh
echo '{}' | jj user.name=abc          # set string
echo '{}' | jj user.age:=18           # set auto-type (number)
echo '{}' | jj tags+=dev              # array push
echo '{"name":"abc"}' | jj name-      # delete
```

| 语法     | 类型         | 示例              |
| -------- | ------------ | ----------------- |
| `=`      | string       | `user.name=abc`   |
| `:=`     | auto detect  | `user.age:=18`    |
| `+=`     | array push   | `tags+=dev`       |
| `-`      | delete       | `user.age-`       |

## Dot Path 语法

```txt
user.name              # 对象字段
history.0.role         # 数组索引
config.server.port     # 嵌套路径
items.-                # 末尾元素（- 表示 last）
```

## 实战场景

### AI Agent Runtime — 构造 OpenAI messages

```sh
msgs=$(jj new array)

msgs=$(echo "$msgs" | jj push \
  role=system \
  content="$SYSTEM_PROMPT")

msgs=$(echo "$msgs" | jj push \
  role=user \
  content="hello")
```

### Shell Automation — 管道过滤

```sh
curl api.xxx.com |
  jj get data.items |
  jj pick id name
```

### CI/CD — 读取版本号

```sh
VERSION=$(cat package.json | jj get version --raw)
```

### 配置修改

```sh
jj -f config.json set server.port 8080
```

## 命令一览

| 命令                | 说明                     |
| ------------------- | ------------------------ |
| `new object\|array` | 创建空 JSON              |
| `get <path>`        | 读取值                   |
| `set <path> <val>`  | 设置值（string）          |
| `del <path>`        | 删除值                   |
| `push <path> ...`   | 向数组追加元素            |
| `pop <path>`        | 从数组弹出末尾元素        |
| `pick <key> ...`    | 仅保留指定字段            |
| `omit <key> ...`    | 移除指定字段              |
| `pretty`            | 格式化输出               |
| `compact`           | 压缩输出                 |
| `type <path>`       | 查看字段类型              |
| `merge <file>`      | 合并 JSON 文件           |

## 选项

| 选项               | 说明                      |
| ------------------ | ------------------------- |
| `-f, --file`       | 从文件读取（替代 stdin）    |
| `--raw`            | 输出原始值（字符串不加引号） |

## 退出码

| 错误            | code |
| --------------- | ---- |
| parse error     | 1    |
| path not found  | 2    |
| invalid type    | 3    |

## 与现有工具对比

| 工具 | 优点         | 缺点       |
| ---- | ------------ | ---------- |
| jq   | 强大         | DSL 太重   |
| jo   | 简单         | 不支持修改  |
| yq   | YAML 强      | 更复杂     |
| fx   | 交互友好     | 不适合脚本  |
| jj   | shell-first  | 功能较少   |

## 技术栈

- **语言** — Zig 0.16.0
- **JSON 解析** — 手写递归下降 parser
- **内存** — Unmanaged 容器，无 GC
- **平台** — Linux / macOS / Windows

## 项目结构

```
zson/
├── build.zig          # 构建配置
├── build.zig.zon      # 包清单
└── src/
    ├── main.zig       # CLI 入口 & 命令分发
    └── ops.zig        # JSON 值表示、解析、路径操作
```

## License

MIT
