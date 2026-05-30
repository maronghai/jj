# jj — Shell-first JSON CLI

Lightweight, composable, pipe-oriented JSON command-line tool. Written in Zig 0.16, zero dependencies, single binary.

> `jo`'s ease of use + `jq`'s mutation power + UNIX pipe philosophy

---

## Design Philosophy

| Principle       | Embodiment                                                |
| --------------- | --------------------------------------------------------- |
| No DSL          | `jj set user.name abc` instead of `.user.name = abc`      |
| Shell-first     | stdin/stdout by default, naturally pipeable               |
| Auto path       | `set user.profile.name x` auto-creates intermediate nodes |
| Type inference  | `:=` and push object mode auto-detect bool/null/number    |
| `^jj^` inline   | `set a ^jj b 1^` equivalent to `set a '{"b":1}'`         |
| Composable      | Multi-command chaining in a single pipe                   |
| Zero deps       | Single binary, no runtime, no GC                          |

---

## Build

```sh
zig build -Doptimize=ReleaseSmall   # ~576KB
zig build                           # debug
zig build test                      # run 143 unit tests
```

---

## Command Reference

| Command                   | Description                                           |
| ------------------------ | ----------------------------------------------------- |
| `new object\|array`      | Create empty JSON                                     |
| `get <path> [--raw]`     | Read value (`--raw` strips quotes)                    |
| `set <p> <v> [p v]...`   | Set value, supports multi-pair syntax and JSON inline |
| `del <path>`             | Delete value                                          |
| `push <path> <v>...`     | Append to array (three modes, see below)              |
| `pop <path>`             | Pop last element from array                           |
| `pick <key>...`          | Keep only specified fields                            |
| `omit <key>...`          | Remove specified fields                               |
| `pretty`                 | Pretty-print output                                   |
| `compact`                | Compact output                                        |
| `type <path>`            | Get type of value at path                             |
| `merge <file>`           | Merge with JSON file                                  |

---

## Basic Usage

### Create

```sh
jj new object              # => {}
jj new array               # => []
```

### Read

```sh
echo '{"name":"abc","age":18}' | jj get name        # => "abc"
echo '{"name":"abc","age":18}' | jj get name --raw  # => abc
echo '{"name":"abc","age":18}' | jj get age --raw   # => 18
echo '{"name":"abc","age":18}' | jj type age        # => number
```

### set — Set Values

```sh
# Basic set (value defaults to string)
echo '{}' | jj set user.name abc
# => {"user":{"name":"abc"}}

# Multi-pair syntax — set multiple fields at once
echo '{}' | jj set a 1 b 2 c 3
# => {"a":"1","b":"2","c":"3"}

# JSON inline — values starting with { or [ are auto-parsed
echo '{}' | jj set config '{"timeout":30,"retries":3}'
# => {"config":{"timeout":30,"retries":3}}

# Mixed usage
echo '{}' | jj set name app config '{"port":8080}' debug:=true
# => {"name":"app","config":{"port":8080},"debug":true}
```

### del — Delete

```sh
echo '{"name":"abc","age":18}' | jj del age
# => {"name":"abc"}
```

### push — Append to Array

Push has three modes, automatically determined by argument form:

| Mode          | Syntax                     | Behavior                                           |
| ------------- | -------------------------- | -------------------------------------------------- |
| Plain values  | `push v1 v2 v3`            | Append multiple values to root array (inferType)   |
| Root object   | `push . k1 v1 k2 v2`       | Build object and append to root array; merge if root is object |
| Path object   | `push .path k1 v1 k2 v2`   | Build object and append to named path's array      |

```sh
# Mode 1: plain values
echo '[]' | jj push hello world
# => ["hello","world"]

# Mode 2a: root is array → append object
echo '[]' | jj push . role user content hello
# => [{"role":"user","content":"hello"}]

# Mode 2b: root is object → merge
echo '{"a":1}' | jj push . b 2
# => {"a":1,"b":2}

# Mode 3: path object — auto-create array
echo '{}' | jj push .items name widget count 5
# => {"items":[{"name":"widget","count":5}]}

# Traditional key=value syntax still supported
echo '{}' | jj push history role=user content=hello
# => {"history":[{"role":"user","content":"hello"}]}

# Push inline JSON
echo '[]' | jj push '{"x":1,"y":2}'
# => [{"x":1,"y":2}]
```

### pop — Pop

```sh
echo '{"items":[1,2,3]}' | jj pop items
# => {"items":[1,2]}
```

### pick / omit — Field Filtering

```sh
echo '{"a":1,"b":2,"c":3}' | jj pick a b    # => {"a":1,"b":2}
echo '{"a":1,"b":2,"c":3}' | jj omit b c    # => {"a":1}
```

### pretty / compact — Formatting

```sh
echo '{"name":"abc","age":18}' | jj pretty
# {
#   "name": "abc",
#   "age": 18
# }

echo '{"name":"abc","age":18}' | jj compact
# => {"name":"abc","age":18}
```

### merge — Merge File

```sh
echo '{"a":1}' | jj merge extra.json
```

---

## Type Inference

`inferType` is automatically active in push object mode and `:=` shorthand:

| Input    | Result              |
| -------- | ------------------- |
| `true`   | `boolean: true`     |
| `false`  | `boolean: false`    |
| `null`   | `null`              |
| `42`     | `integer: 42`       |
| `-7`     | `integer: -7`       |
| `3.14`   | `number: 3.14`      |
| `1e3`    | `number: 1000.0`    |
| `hello`  | `string: "hello"`   |

```sh
# Auto-infer in push object
echo '[]' | jj push . name widget active true count 42 weight 3.14
# => [{"name":"widget","active":true,"count":42,"weight":3.14}]

# Auto-infer for push plain values
echo '[]' | jj push true 42 null hello
# => [true,42,null,"hello"]
```

---

## Shell-native Shorthand

```sh
echo '{}' | jj user.name=abc          # set string
echo '{}' | jj user.age:=18           # set auto-type (number)
echo '{}' | jj active:=true           # set auto-type (bool)
echo '{}' | jj tags+=dev              # array push
echo '{"name":"abc"}' | jj name-      # delete
```

| Syntax | Type        | Example          |
| ------ | ----------- | ---------------- |
| `=`    | string      | `user.name=abc`  |
| `:=`   | auto detect | `user.age:=18`   |
| `+=`   | array push  | `tags+=dev`      |
| `-`    | delete      | `user.age-`      |

---

## Multi-command Chaining

Multiple commands execute sequentially on the same JSON, no extra pipes needed:

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

## Dot Path Syntax

```
.                     Root path (normalizePath: . → "")
.a                    Equivalent to a (strip leading .)
.a.b                  Equivalent to a.b
user.name             Object field
history.0.role        Array index
items.-               Last element (- = last)
```

normalizePath rules: `.` → `""`, `.a` → `a`, `.a.b` → `a.b`, `a.b` → `a.b`

---

## `^jj^` Inline JSON Construction

Use `^jj <command> <args>... [command> <args>...]^` in set/push value position to execute jj command chains and embed the result:

```sh
# ^jj set^ — construct object
echo '{}' | jj set a ^jj set b 1 ^
# => {"a":{"b":"1"}}

# ^jj push^ — construct array
echo '{}' | jj set a ^jj push 1 2 3 ^
# => {"a":[1,2,3]}

# Multi-command chain — set + push execute on same root
echo '{}' | jj set a ^jj set b 2 push .c 3 ^
# => {"a":{"b":"2","c":[3]}}

echo '{}' | jj set a ^jj set b 2 set c:=true push .d 4 ^
# => {"a":{"b":"2","c":true,"d":[4]}}

# set + del chain
echo '{}' | jj set a ^jj set b 2 set c 3 del b ^
# => {"a":{"c":"3"}}

# set + omit chain
echo '{}' | jj set a ^jj set b 2 set c 3 set d 4 omit c ^
# => {"a":{"b":"2","d":"4"}}

# Push object mode
echo '{}' | jj set items ^jj push . x 1 y 2 ^
# => {"items":[{"x":1,"y":2}]}

# Single-token form (quoted, no shell word-splitting)
echo '{}' | jj set a '^jj set b 2 push .c 3^'
# => {"a":{"b":"2","c":[3]}}
```

Supported commands: `set`, `push`, `del`, `pop`, `pick`, `omit`. Falls back to key-value pair construction when no command name is present.

`^jj^` preprocessing runs before command dispatch: tokens are split by command name into a command chain, executed sequentially on the same root, and the result is serialized as a JSON inline value.

---

## Smart Concatenation

Shell word-splitting breaks JSON objects containing spaces. `jj` progressively appends arguments and attempts to parse, stopping on first success:

```sh
# After shell expansion {"b":"a b c"} is split into 3 tokens
# jj smart-concatenates them back into valid JSON
echo '{}' | jj set a '{"b":"a b c"}'
# => {"a":{"b":"a b c"}}
```

This mechanism applies to both `set` and `push` JSON inline values.

---

## TTY Detection

When stdin is a terminal (no pipe input), `jj` doesn't block — it auto-creates a default value:

```sh
# No stdin → auto-create object
jj set a 1 b 2
# => {"a":"1","b":"2"}

# Only push, no set → auto-create array
jj push 1 2 3
# => ["1","2","3"]

# Push with .path form → auto-create object
jj push .items name widget
# => {"items":[{"name":"widget"}]}
```

---

## File Mode

```sh
jj -f config.json set server.port 8080
# equivalent to
cat config.json | jj set server.port 8080
```

---

## Options

| Option        | Description                            |
| ------------- | -------------------------------------- |
| `-f, --file`  | Read from file instead of stdin        |
| `--raw`       | Output raw value (no quotes for strings) |

---

## Exit Codes

| Error           | Code |
| --------------- | ---- |
| parse error     | 1    |
| path not found  | 2    |
| invalid type    | 3    |

---

## Real-world Scenarios

### AI Agent — Build OpenAI Messages

```sh
msgs=$(jj new array)
msgs=$(echo "$msgs" | jj push . role system content "$SYSTEM_PROMPT")
msgs=$(echo "$msgs" | jj push . role user content "hello")
```

### Quick Build Without Pipe

```sh
jj set name app version 1.0.0 debug:=false
# => {"name":"app","version":"1.0.0","debug":false}
```

### Shell Pipeline Filtering

```sh
curl api.example.com | jj get data.items | jj pick id name
```

### CI/CD — Read Version

```sh
VERSION=$(cat package.json | jj get version --raw)
```

### Config Modification

```sh
jj -f config.json set server.port 8080 set server.host localhost
jj -f config.json set server.port 8080 server.host localhost
jj -f config.json server.port=8080 server.host=localhost
```

---

## Internals

### JSON Value Representation

```
JsonValue = union(enum)
  null
  boolean: bool
  integer: i64          # integers stored separately, no precision loss
  number: f64           # floats
  string: []const u8    # gpa.dupe-owned
  array:  ArrayList(JsonValue)
  object: String(JsonValue)   # ordered map
```

### Parser

Hand-written recursive descent, supporting:
- Full JSON spec: null / bool / integer / float / string / array / object
- Scientific notation: `1e3`, `-2.5E+10`
- String escapes: `\" \\ \/ \n \r \t \b \f`
- Unicode escape: `\u0041` (1/2/3-byte UTF-8 encoding)
- Duplicate keys: later value overwrites earlier; old key/value properly freed

### Path Operations

- `parsePath` — parse dot path into `PathSegment` sequence (`.key` / `.index`)
- `set` — recursive traversal + auto-create intermediate nodes (null → object/array)
- `del` — `fetchSwapRemove` + key/value deallocation
- `push` — auto-create empty array if path doesn't exist, then append
- `pop` — `orderedRemove` returns popped value
- `pick/omit` — traversal-based field filtering
- `inferType` — try in order: bool → null → parseInt → parseFloat → string

### Memory Safety

- All `deinit` recursively frees child nodes + key strings
- `parseString` returns `gpa.dupe` for ownership
- `fetchPut` duplicate keys: free new key, keep old key
- `parseObject` errdefer frees already-allocated key/value
- `set` empty path root replacement: `root.deinit(gpa)` before assignment
- 143 tests passing, zero leaks

---

## Comparison with Existing Tools

| Tool | Strengths          | Weaknesses                     |
| ---- | ------------------ | ------------------------------ |
| jq   | Powerful           | DSL learning curve             |
| jo   | Simple             | Create only, no mutation       |
| yq   | Full YAML support  | Complex, Go dependency         |
| fx   | Interactive        | Not script-friendly            |
| jj   | Shell-first        | No streaming/transform expressions |

---

## Tech Stack

| Item         | Value                                         |
| ------------ | --------------------------------------------- |
| Language     | Zig 0.16.0                                    |
| JSON parser  | Hand-written recursive descent                 |
| Memory       | Unmanaged containers + explicit gpa, no GC    |
| Tests        | 143 unit tests (ops_test + main)              |
| Platforms    | Linux / macOS / Windows                       |
| Binary size  | ReleaseSmall ~576KB                           |

---

## Project Structure

```
jj/
├── build.zig          # Build config (ops_test + main dual test steps)
├── build.zig.zon      # Package manifest (Zig 0.16 format)
└── src/
    ├── main.zig       # CLI entry: arg parsing, multi-cmd splitting, dispatch,
    │                  #   I/O, TTY detection, normalizePath, parseValue,
    │                  #   execSet (multi-pair + JSON concat), execPush (3 modes +
    │                  #   object build + smart concat), execDel/Pop/Pick/Omit/
    │                  #   Type/Merge, execShorthand
    ├── ops.zig        # JSON core: JsonValue union, parse/get/set/del/
    │                  #   push/pop/pick/omit/merge/inferType,
    │                  #   writeTo/writePretty, parsePath, memory-safe
    │                  #   deinit/clone
    └── ops_test.zig   # 143 unit tests: parse edge cases, writeTo/writePretty,
                       #   clone, paths, all operations, roundtrip, compositions
```

---

## License

MIT
