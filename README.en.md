Your current README is already technically solid.
What it lacks is:

* emotional hook
* “instant understanding”
* viral comparison framing
* AI-agent positioning
* visual scanning optimization

The biggest improvement is:

> turn it from “documentation” into “a landing page”.

Here’s a more GitHub-viral version.

---

````markdown
# jj

> JSON CLI for shell scripts and AI agents.

`jq` is powerful.  
`jo` is simple.  

`jj` is both.

```sh
jj user.name=alice
jj tags+=dev
jj user.age-
```

No DSL.  
No quotes hell.  
Just JSON manipulation that feels like UNIX.

---

## Why?

Building JSON in shell scripts still looks like this:

```sh
jq '.history += [{"role":"user","content":"hello"}]'
```

Or even worse:

```sh
jq -n --arg role user --arg content hello ...
```

With `jj`:

```sh
jj push history role=user content=hello
```

Readable. Pipeable. Scriptable.

---

## Features

- Tiny single binary (~574KB ReleaseSmall)
- Zero dependencies
- Native performance (Zig, no GC)
- Pipe-first stdin/stdout design
- No DSL or query language
- Auto-create nested paths
- Shell-native syntax
- Works great with AI agents and MCP tools

---

# Quick Start

## Build

```sh
zig build -Doptimize=ReleaseSmall
```

---

# Examples

## Create JSON

```sh
jj new object
# {}
```

```sh
jj new array
# []
```

---

## Read Values

```sh
echo '{"name":"alice","age":18}' | jj get name --raw
# alice
```

```sh
echo '{"name":"alice","age":18}' | jj type age
# number
```

---

## Set Values

```sh
echo '{}' | jj set user.name alice
```

Output:

```json
{"user":{"name":"alice"}}
```

Nested paths are created automatically.

---

## Delete Values

```sh
echo '{"name":"alice","age":18}' | jj del age
```

```json
{"name":"alice"}
```

---

## Push Into Arrays

```sh
echo '{}' | jj push history role=user content=hello
```

```json
{"history":[{"role":"user","content":"hello"}]}
```

Primitive values also work:

```sh
echo '{}' | jj push tags dev
```

```json
{"tags":["dev"]}
```

---

# Shell-Native Syntax

`jj` supports compact shell-style operations:

```sh
jj user.name=alice
jj user.age:=18
jj tags+=dev
jj user.age-
```

| Syntax | Meaning |
|---|---|
| `=` | set string |
| `:=` | auto-detect type |
| `+=` | array push |
| `-` | delete key |

---

# AI Agent Friendly

Building OpenAI messages in shell becomes readable:

```sh
msgs=$(jj new array)

msgs=$(echo "$msgs" | jj push \
  role=system \
  content="you are CTO")

msgs=$(echo "$msgs" | jj push \
  role=user \
  content="hello")
```

Perfect for:

- AI agent runtimes
- MCP tools
- shell orchestration
- CI/CD pipelines
- structured stdout workflows

---

# Pipe-First Design

Everything works with stdin/stdout.

```sh
cat package.json | jj get version --raw
```

```sh
curl api.xxx.com |
  jj get data.items |
  jj pick id name
```

---

# Dot Path Syntax

```txt
user.name
history.0.role
config.server.port
items.-
```

---

# Commands

| Command | Description |
|---|---|
| `new object|array` | create empty JSON |
| `get <path>` | read value |
| `set <path> <val>` | set value |
| `del <path>` | delete value |
| `push <path> ...` | append to array |
| `pop <path>` | pop array item |
| `pick <key> ...` | keep keys |
| `omit <key> ...` | remove keys |
| `pretty` | pretty print |
| `compact` | compact print |
| `type <path>` | show JSON type |
| `merge <file>` | merge JSON |

---

# Philosophy

`jj` is not trying to replace `jq`.

`jq` is a programming language.

`jj` is:

> `sed` for JSON.

Simple operations.  
Fast pipelines.  
Shell-first workflows.

---

# Performance

| x | size@win |
|--|--:|
| jq | ~384KB |
| jj | ~120KB |

- Native Zig binary
- No runtime
- No GC
- Startup < 5ms

---

# Tech Stack

- Zig 0.16
- Recursive descent JSON parser
- Unmanaged containers
- Linux / macOS / Windows

---

# Roadmap

Planned:

- JSONL support
- streaming mode
- YAML support
- OpenAI/MCP helpers
- large-file processing

---

# License

MIT
````
