# jj — Shell-first JSON CLI

A lightweight, composable, pipe-oriented JSON command-line tool. Written in Zig 0.16 with zero dependencies and a single ~576KB binary.

> `jo`'s ease of use + `jq`'s mutation power + UNIX pipe philosophy

> [!NOTE]
> **Name collision.** `jj` shares its name with [Jujutsu VCS](https://github.com/martinvonz/jj) (a modern Rust VCS) and the historical [tidwall/jj](https://github.com/tidwall/jj) Go JSON library. This project is an independent shell-first JSON CLI and is not related to either.

## See it in action

```text
$ echo '{}' | jj set name app port:=8080 debug:=true
{"name":"app","port":8080,"debug":true}

$ echo '[1,2,3]' | jj pop .
[1,2]

$ echo '{"a":1,"b":2,"c":3}' | jj set d:=4 del b omit c pretty
{
  "a": 1,
  "c": 3,
  "d": 4
}
```

---

## Why jj?

| Tool    | Strengths                | Weaknesses                       |
| ------- | ------------------------ | -------------------------------- |
| jq      | Powerful expressions     | DSL learning curve               |
| jo      | Dead simple              | Create-only, no mutation         |
| yq      | Full YAML / JSON         | Complex, Go dependency           |
| fx      | Interactive REPL         | Not script-friendly              |
| **jj**  | **Shell-first, mutates JSON** | **No streaming / transform DSL** |

What makes `jj` different:

- **No DSL.** `jj set user.name alice` instead of `jq '.user.name = "alice"'`
- **Multi-command chains.** `jj set a 1 del b omit c pretty` in one pipe
- **Auto path creation.** `set server.tls.cert.path x` builds intermediate objects
- **Auto type inference.** `debug:=true` becomes a boolean, not the string `"true"`
- **Shell-native shorthand.** `user.age=18`, `tags+=dev`, `user.age-`

---

## Build & Install

Build from source (Zig 0.16+ required):

```sh
git clone <repo> && cd jj
zig build -Doptimize=ReleaseSmall
./zig-out/bin/jj --version    # → jj 0.0.14
```

Run the test suite (143 unit tests):

```sh
zig build test
```

Run the benchmark suite:

```sh
zig build bench
```

---

## Quick start

### Create

```sh
$ jj new object
{}

$ jj new array
[]
```

### Read

```sh
$ echo '{"name":"alice","age":30}' | jj get name
"alice"

$ echo '{"name":"alice","age":30}' | jj get age --raw
30

$ echo '{"name":"alice","age":30}' | jj type age
number
```

### Build

```sh
# Values default to strings; `:=` enables type inference
$ echo '{}' | jj set name app port:=8080 debug:=true
{"name":"app","port":8080,"debug":true}

# Multi-pair syntax — set several fields in one call
$ echo '{}' | jj set a 1 b 2 c 3
{"a":"1","b":"2","c":"3"}
```

### Modify

```sh
$ echo '{"a":1,"b":2,"c":3}' | jj set a 99 del b omit c
{"a":99}
```

### Filter

```sh
$ echo '{"a":1,"b":2,"c":3}' | jj pick a c
{"a":1,"c":3}

$ echo '[10,20,30]' | jj pop .
[10,20]
```

### Format

```sh
$ echo '{"name":"alice","age":30}' | jj pretty
{
  "name": "alice",
  "age": 30
}
```

---

## Demos

### 1. Clean up an API response

```text
$ curl -s https://api.example.com/users/1
{"id":"u_1","name":"Alice","email":"alice@example.com","token":"secret","internal_id":42}

$ curl -s https://api.example.com/users/1 \
    | jj pick id name email omit token internal_id
{"id":"u_1","name":"Alice","email":"alice@example.com"}
```

### 2. Build an OpenAI chat completion payload

```text
$ msgs=$(jj new array)
$ msgs=$(echo "$msgs" | jj push . role system content "You are a helpful assistant.")
$ msgs=$(echo "$msgs" | jj push . role user content "What is 2+2?")
$ msgs=$(echo "$msgs" | jj push . role assistant content "It's 4.")

$ echo "$msgs" | jj pretty
[
  {
    "role": "system",
    "content": "You are a helpful assistant."
  },
  {
    "role": "user",
    "content": "What is 2+2?"
  },
  {
    "role": "assistant",
    "content": "It's 4."
  }
]
```

### 3. Patch a config file in place

```text
$ cat config.json
{"server":{"host":"localhost","port":8080,"tls":false},"log_level":"info"}

$ jj -f config.json set server.port:=9090 server.tls:=true log_level=debug
{"server":{"host":"localhost","port":9090,"tls":true},"log_level":"debug"}
```

### 4. `^jj^` inline construction

```text
# ^jj ... ^ runs an inline jj chain and embeds the result
$ echo '{}' | jj set user ^jj set name alice age:=30 ^
{"user":{"name":"alice","age":30}}

# Mix set + push in a single inline chain
$ echo '{}' | jj set a ^jj set b 2 push .c 3 ^
{"a":{"b":"2","c":[3]}}

# Single-token (quoted) form — no shell word-splitting
$ echo '{}' | jj set a '^jj set b 2 push .c 3^'
{"a":{"b":"2","c":[3]}}
```

### 5. Shell-native shorthand in a single line

```text
# Set, delete, and type-infer in one go — no `set` / `del` keywords
$ echo '{"name":"alice","age":30,"secret":"xxx","debug":false}' \
    | jj age:=31 secret- debug:=true
{"name":"alice","age":31,"debug":true}

# Mix shorthand with full commands and pretty-print
$ echo '{"a":1,"b":2,"c":3}' | jj set d:=4 del b omit c pretty
{
  "a": 1,
  "c": 3,
  "d": 4
}
```

### 6. TTY mode — no input needed

```text
# When stdin is a terminal, jj auto-creates a sensible default root
$ jj set a 1 b 2
{"a":"1","b":"2"}

$ jj push 1 2 3
[1,2,3]

$ jj push .items name widget count 5
{"items":[{"name":"widget","count":5}]}
```

### 7. Merge — apply overrides to a base

```text
$ cat base.json
{"server":{"host":"localhost","port":8080},"debug":false,"version":"1.0"}

$ cat overrides.json
{"server":{"port":9090},"debug":true}

$ jj -f base.json merge overrides.json
{"server":{"host":"localhost","port":9090},"debug":true,"version":"1.0"}
```

---

## Command reference

| Command                      | Description                                              |
| ---------------------------- | -------------------------------------------------------- |
| `new object` / `new array`   | Create empty JSON                                        |
| `get <path> [--raw]`         | Read a value (`--raw` strips quotes for strings)         |
| `set <p> <v> [p v]...`       | Set values; supports multi-pair, JSON inline, `:=` type  |
| `del <path>`                 | Delete a value                                           |
| `push <path> <v>...`         | Append to array (3 modes — see below)                    |
| `pop <path>`                 | Pop the last element of an array                         |
| `pick <key>...`              | Keep only listed keys                                    |
| `omit <key>...`              | Remove listed keys                                       |
| `pretty`                     | Pretty-print output                                      |
| `compact`                    | Compact output                                           |
| `type <path>`                | Print the value type at a path                           |
| `keys [path]`                | List object keys (one per line)                          |
| `has [path]`                 | Print `true` / `false` if the path exists                |
| `length [path]`              | Print array / object / string length                     |
| `merge <file>`               | Merge a JSON file (use `-` or omit for stdin)            |

---

## Features

### Multi-command chaining

Multiple commands execute sequentially on the same JSON, no extra pipes:

```sh
$ echo '{"a":1,"b":2,"c":3}' | jj set d 4 del b omit c
{"a":1,"d":"4"}

$ echo '{}' | jj set a 1 push tags dev push tags staging del a
{"tags":["dev","staging"]}

$ echo '{"name":"test","secret":"xxx","token":"yyy"}' \
    | jj omit secret token set status active pretty
{
  "name": "test",
  "status": "active"
}
```

### Shell-native shorthand

Skip the `set` / `del` / `push` keywords with operator suffixes:

```sh
$ echo '{}' | jj user.name=alice            # set string
$ echo '{}' | jj user.age:=30               # set auto-type
$ echo '{}' | jj active:=true               # boolean, not string
$ echo '{}' | jj tags+=dev                  # array push
$ echo '{"name":"abc"}' | jj name-          # delete
```

| Syntax | Operation        | Example           |
| ------ | ---------------- | ----------------- |
| `=`    | set string       | `user.name=alice` |
| `:=`   | set auto-detect  | `user.age:=30`    |
| `+=`   | array push       | `tags+=dev`       |
| `-`    | delete           | `name-`           |

### Dot path syntax

```
.                     root (normalizePath: . → "")
.a                    equivalent to a (drop leading .)
.a.b                  equivalent to a.b
user.name             object field
history.0.role        array index
items.-               last element (- = maxInt(usize) sentinel)
```

### Type inference

`inferType` is active in `push` object mode and `:=` shorthand:

| Input   | Result             |
| ------- | ------------------ |
| `true`  | `boolean: true`    |
| `false` | `boolean: false`   |
| `null`  | `null`             |
| `42`    | `integer: 42`      |
| `-7`    | `integer: -7`      |
| `3.14`  | `number: 3.14`     |
| `1e3`   | `number: 1000.0`   |
| `hello` | `string: "hello"`  |

```sh
$ echo '[]' | jj push . name widget active true count 42 weight 3.14
[{"name":"widget","active":true,"count":42,"weight":3.14}]

$ echo '[]' | jj push true 42 null hello
[true,42,null,"hello"]
```

### push — three modes

`push` picks a mode based on the first argument:

| Mode          | Syntax                     | Behavior                                                                 |
| ------------- | -------------------------- | ------------------------------------------------------------------------ |
| Plain values  | `push v1 v2 v3`            | Append to root array (type-inferred)                                     |
| Object build  | `push . k1 v1 k2 v2`       | Build object — append to root array, or merge into root if it's an object |
| Named path    | `push .path k1 v1 k2 v2`   | Build object — append to `.path`'s array (auto-creates if missing)       |

```sh
# Mode 1: plain values
$ echo '[]' | jj push hello world
["hello","world"]

# Mode 2a: root is array → append object
$ echo '[]' | jj push . role user content hello
[{"role":"user","content":"hello"}]

# Mode 2b: root is object → merge
$ echo '{"a":1}' | jj push . b 2
{"a":1,"b":2}

# Mode 3: named path — auto-creates the array
$ echo '{}' | jj push .items name widget count 5
{"items":[{"name":"widget","count":5}]}

# Inline JSON
$ echo '[]' | jj push '{"x":1,"y":2}'
[{"x":1,"y":2}]
```

### `^jj^` inline construction

Use `^jj <command> <args>... [command> <args>...]^` in a `set` or `push` value position to execute a sub-chain and embed the result. Supports `set`, `push`, `del`, `pop`, `pick`, `omit`.

```sh
# ^jj set^ — construct an object
$ echo '{}' | jj set a ^jj set b 1 ^
{"a":{"b":"1"}}

# ^jj push^ — construct an array
$ echo '{}' | jj set a ^jj push 1 2 3 ^
{"a":[1,2,3]}

# Multi-command chain — set + push on the same root
$ echo '{}' | jj set a ^jj set b 2 set c:=true push .d 4 ^
{"a":{"b":"2","c":true,"d":[4]}}
```

### Smart concatenation

Shell tokenization breaks JSON literals containing spaces. `jj` progressively glues tokens back together until a valid JSON value parses:

```sh
# After shell expansion `{"b":"a b c"}` arrives as 3 tokens
# jj stitches them back into a single JSON object
$ echo '{}' | jj set a '{"b":"a b c"}'
{"a":{"b":"a b c"}}
```

Works for both `set` and `push` JSON inline values.

### TTY detection

When stdin is a terminal, `jj` does **not** block. It picks a sensible default root based on the commands:

| First command        | Default root |
| -------------------- | ------------ |
| `set` (or any mix)   | `{}`         |
| `push` (no `.path`)  | `[]`         |
| `push .path ...`     | `{}`         |

```sh
$ jj set a 1 b 2
{"a":"1","b":"2"}

$ jj push 1 2 3
[1,2,3]

$ jj push .items name widget
{"items":[{"name":"widget"}]}
```

### File mode

```sh
# -f reads from a file instead of stdin
$ jj -f config.json set server.port:=8080
# equivalent to:
$ cat config.json | jj set server.port:=8080
```

### Options

| Option                | Description                              |
| --------------------- | ---------------------------------------- |
| `-f, --file <path>`   | Read from a file instead of stdin        |
| `--raw`               | Print string / number / bool without quotes |

### Exit codes

| Error           | Code |
| --------------- | ---- |
| parse error     | 1    |
| path not found  | 2    |
| invalid type    | 3    |

---

## Real-world scenarios

### AI agent — build OpenAI messages

```sh
msgs=$(jj new array)
msgs=$(echo "$msgs" | jj push . role system content "$SYSTEM_PROMPT")
msgs=$(echo "$msgs" | jj push . role user content "hello")
msgs=$(echo "$msgs" | jj push . role assistant content "hi")
```

### CI/CD — bump the version

```sh
VERSION=$(cat package.json | jj get version --raw)
echo "Current version: $VERSION"

cat package.json | jj version=1.2.4 > package.json.tmp
mv package.json.tmp package.json
```

### Config patching

```sh
# Three equivalent ways to patch server.port and server.host
jj -f config.json set server.port 8080 server.host localhost
jj -f config.json server.port=8080 server.host=localhost
jj -f config.json server.port:=8080 server.host=localhost
```

### API response filtering

```sh
curl api.example.com | jj get data.items | jj pick id name
```

---

## Internals

### JSON value representation

```
JsonValue = union(enum)
  null
  boolean: bool
  integer: i64          # integers stored separately — no precision loss
  number:  f64          # floats
  string:  []const u8   # gpa.dupe owned
  array:   ArrayList(JsonValue)
  object:  String(JsonValue)   # ordered map
```

### Parser

Hand-written recursive descent, supporting:

- Full JSON: `null` / `bool` / `int` / `float` / `string` / `array` / `object`
- Scientific notation: `1e3`, `-2.5E+10`
- String escapes: `\" \\ \/ \n \r \t \b \f`
- Unicode escape: `A` (auto-encoded as 1 / 2 / 3-byte UTF-8)
- Duplicate keys: later value wins, old key / value freed safely

### Path operations

- `parsePath` — dot path → `[]PathSegment` (key / index). `-` is a sentinel for the last element.
- `set` — recursive traversal + auto-create intermediate nodes (`null → object / array`).
- `del` — `fetchSwapRemove` on objects, `orderedRemove` on arrays.
- `push` — auto-creates an empty array when the path doesn't exist.
- `pop` — `arr.pop().?` returns the value, caller owns it.
- `pick` / `omit` — traversal-based field filtering.
- `inferType` — try in order: `bool` → `null` → `parseInt` → `parseFloat` → `string`.

### Memory safety

- `deinit` recursively frees children and keys; `parseString` returns `gpa.dupe` to own the slice.
- `parseObject` `errdefer` cleans up already-allocated key / value pairs on error.
- `fetchPut` on duplicate key: free the new key, keep the old (and free the old value).
- `set ""` (empty path) replaces the root: deinit-then-assign.

143 unit tests, zero leaks (validated with Zig's testing allocator).

---

## Tech stack

| Item         | Value                                  |
| ------------ | -------------------------------------- |
| Language     | Zig 0.16.0                             |
| JSON parser  | Hand-written recursive descent         |
| Memory       | Unmanaged containers + explicit `gpa`  |
| Tests        | 143 unit tests (`ops_test` + `main`)   |
| Platforms    | Linux / macOS / Windows                |
| Binary size  | `ReleaseSmall` ~576KB                  |

## Project structure

```
jj/
├── build.zig          # Build config (main + ops_test + main_test + bench)
├── build.zig.zon      # Package manifest (Zig 0.16 format)
└── src/
    ├── main.zig       # CLI entry, multi-cmd dispatch, I/O, TTY, ^jj^ preprocessing
    ├── ops.zig        # JsonValue, parser, get/set/del/push/pop/pick/omit/merge
    ├── ops_test.zig   # 143 unit tests
    └── bench.zig      # Performance benchmarks
```

## License

MIT
