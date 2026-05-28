# `jj` — Shell-first JSON CLI

轻量级、可组合、面向管道（pipe）的 JSON 命令行工具。

目标是成为：

> `jo` 的易用性 + `jq` 的修改能力 + UNIX 工具链风格

---

# 1. 项目目标

## 核心目标

提供一个：

* 小体积
* 零依赖
* 高性能
* shell-first
* stdin/stdout-first
* 易读易写

的 JSON CLI 工具。

适用于：

* shell scripting
* AI Agent orchestration
* MCP tools
* CI/CD
* Linux automation
* API scripting
* structured stdout pipelines

---

# 2. 设计理念

## 2.1 不设计 DSL

拒绝：

```jq
.user.name |= ...
```

采用：

```sh
jj set user.name abc
```

或者：

```sh
jj user.name=abc
```

---

## 2.2 shell-first

所有命令：

* 默认 stdin 输入
* 默认 stdout 输出
* 可 pipe
* 可组合

示例：

```sh
cat a.json | jj set user.name abc
```

---

## 2.3 人类可读优先

优先：

```sh
jj push history role=user content=hello
```

而不是：

```jq
.history += [{"role":"user","content":"hello"}]
```

---

## 2.4 小而快

目标：

| 指标         | 目标      |
| ---------- | ------- |
| Linux 静态体积 | < 200KB |
| 启动时间       | < 5ms   |
| 无运行时依赖     | YES     |
| 单二进制       | YES     |

---

# 3. 核心使用场景

---

# 3.1 AI Agent Runtime

## 构造 OpenAI messages

```sh
msgs=$(jj new array)

msgs=$(echo "$msgs" | jj push \
  role=system \
  content="$SYSTEM_PROMPT")

msgs=$(echo "$msgs" | jj push \
  role=user \
  content="hello")
```

---

# 3.2 Shell Automation

```sh
curl api.xxx.com |
  jj get data.items |
  jj pick id name
```

---

# 3.3 配置修改

```sh
jj -f config.json set server.port 8080
```

---

# 3.4 CI/CD

```sh
VERSION=$(cat package.json | jj get version)
```

---

# 4. CLI 设计

---

# 4.1 基础语法

```sh
jj <command> [args]
```

---

# 4.2 stdin/stdout 模式

默认：

* stdin 读取 JSON
* stdout 输出 JSON

---

# 4.3 文件模式

```sh
jj -f config.json set port 8080
```

等价于：

```sh
cat config.json | jj set port 8080
```

---

# 5. 数据路径设计

---

# 5.1 Dot Path

使用：

```txt
user.name
history.0.role
config.server.port
```

不使用：

```jq
.user.name
```

---

# 5.2 Array Index

```txt
history.0.content
```

---

# 5.3 自动创建路径

```sh
jj set user.profile.name abc
```

自动生成：

```json
{
  "user": {
    "profile": {
      "name": "abc"
    }
  }
}
```

---

# 6. 核心命令

---

# 6.1 new

创建 JSON。

## 创建对象

```sh
jj new object
```

输出：

```json
{}
```

---

## 创建数组

```sh
jj new array
```

输出：

```json
[]
```

---

# 6.2 set

设置字段。

```sh
jj set user.name abc
```

结果：

```json
{
  "user": {
    "name": "abc"
  }
}
```

---

# 6.3 get

读取字段。

```sh
jj get user.name
```

输出：

```txt
abc
```

---

# 6.4 del

删除字段。

```sh
jj del user.age
```

---

# 6.5 push

向数组追加元素。

---

## push object

```sh
jj push history role=user content=hello
```

结果：

```json
{
  "history": [
    {
      "role": "user",
      "content": "hello"
    }
  ]
}
```

---

## push primitive

```sh
jj push tags dev
```

---

# 6.6 pop

```sh
jj pop history
```

---

# 6.7 pick

保留字段。

```sh
jj pick id name version
```

---

# 6.8 omit

删除多个字段。

```sh
jj omit password token secret
```

---

# 6.9 merge

合并 JSON。

```sh
jj merge extra.json
```

---

# 6.10 pretty

格式化输出。

```sh
jj pretty
```

---

# 6.11 compact

压缩输出。

```sh
jj compact
```

---

# 6.12 type

查看字段类型。

```sh
jj type user.age
```

输出：

```txt
number
```

---

# 7. Shell-native 简写语法

支持：

```sh
jj user.name=abc
jj user.age:=18
jj tags+=dev
jj user.age-
```

---

# 7.1 类型推断

| 语法 | 类型          |
| -- | ----------- |
| =  | string      |
| := | auto detect |
| += | array push  |
| -  | delete      |

---

# 8. 数据类型

支持：

* string
* number
* bool
* null
* object
* array

---

# 9. 输出模式

---

# 9.1 默认 JSON 输出

```json
{"name":"abc"}
```

---

# 9.2 Raw 输出

```sh
jj get name --raw
```

输出：

```txt
abc
```

---

# 9.3 Pretty 输出

```sh
jj pretty
```

---

# 10. 错误处理

---

# 10.1 明确错误信息

```txt
path not found: user.profile.name
```

---

# 10.2 非零退出码

| 错误             | code |
| -------------- | ---- |
| parse error    | 1    |
| path not found | 2    |
| invalid type   | 3    |

---

# 11. 性能目标

---

# 11.1 二进制体积

| 平台         | 目标      |
| ---------- | ------- |
| Linux musl | < 200KB |
| Windows    | < 300KB |

---

# 11.2 启动速度

目标：

```txt
< 5ms
```

---

# 11.3 内存

小 JSON：

```txt
< 5MB RSS
```

---

# 12. 技术实现

---

# 12.1 语言

使用：

* Zig 0.16+
* 单二进制
* 无 GC

---

# 12.2 JSON Parser

优先：

* streaming parser
* arena allocator

---

# 12.3 平台支持

* Linux
* macOS
* Windows

---

# 13. 与现有工具对比

| 工具 | 优点          | 缺点     |
| -- | ----------- | ------ |
| jq | 强大          | DSL 太重 |
| jo | 简单          | 不支持修改  |
| yq | YAML 强      | 更复杂    |
| fx | 交互友好        | 不适合脚本  |
| jj | shell-first | 功能较少   |

---

# 14. MVP 范围

第一阶段仅实现：

* new
* get
* set
* del
* push
* pretty
* compact

---

# 15. 非目标（Non-goals）

---

## 不做 DSL

不会支持：

```jq
map(select(.x > 1))
```

---

## 不做脚本语言

不会：

* 内置循环
* 内置条件语句
* 自定义函数

---

## 不做数据库

不会：

* JSON query engine
* SQL-like syntax

---

# 16. 长期规划

---

# 16.1 YAML 支持

未来：

```sh
jj --yaml
```

---

# 16.2 JSONL 支持

```sh
cat logs.jsonl | jj ...
```

---

# 16.3 Streaming Mode

大文件流式处理。

---

# 16.4 AI Agent Mode

例如：

```sh
jj openai message ...
jj anthropic tool-call ...
```

---

# 17. 项目定位

`jj` 不是：

* jq replacement
* JSON database
* programming language

而是：

> 面向 shell 与 AI orchestration 的轻量 JSON Swiss Army Knife。
