const std = @import("std");
const ops = @import("ops.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const File = Io.File;
const Dir = Io.Dir;
const Writer = Io.Writer;

const MAX_ARGS = 128;

const Cmd = enum {
    set,
    del,
    push,
    pop,
    pick,
    omit,
    pretty,
    compact,
    type,
    merge,
    @"new",
    get,
    keys,
    has,
    length,
};

const CmdInfo = struct {
    cmd: Cmd,
    args_start: usize,
    args_end: usize,
};

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const io = init.io;

    var args_iter = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args_iter.deinit();

    var args_buf: [MAX_ARGS][]const u8 = undefined;
    var args_len: usize = 0;
    while (args_iter.next()) |arg| {
        if (args_len >= MAX_ARGS) break;
        args_buf[args_len] = try gpa.dupe(u8, arg);
        args_len += 1;
    }
    defer for (args_buf[0..args_len]) |a| gpa.free(a);

    var processed_buf: [MAX_ARGS][]const u8 = undefined;
    var processed_len: usize = 0;
    {
        var si: usize = 0;
        while (si < args_len) {
            const a = args_buf[si];
            var is_jj_start = false;
            if (a.len >= 3 and a[0] == '^' and a[1] == 'j' and a[2] == 'j') is_jj_start = true;
            if (is_jj_start) {
                var inline_tokens: [64][]const u8 = undefined;
                var inline_count: usize = 0;
                if (a.len > 3 and a[a.len - 1] == '^') {
                    const content = a[3 .. a.len - 1];
                    var ci: usize = 0;
                    while (ci < content.len) {
                        while (ci < content.len and content[ci] == ' ') ci += 1;
                        if (ci >= content.len) break;
                        const tok_start = ci;
                        while (ci < content.len and content[ci] != ' ') ci += 1;
                        if (inline_count < inline_tokens.len) {
                            inline_tokens[inline_count] = content[tok_start..ci];
                            inline_count += 1;
                        }
                    }
                    si += 1;
                } else {
                    si += 1;
                    while (si < args_len) {
                        const t = args_buf[si];
                        if (t.len > 0 and t[t.len - 1] == '^') {
                            if (t.len > 1) {
                                if (inline_count < inline_tokens.len) {
                                    inline_tokens[inline_count] = t[0 .. t.len - 1];
                                    inline_count += 1;
                                }
                            }
                            si += 1;
                            break;
                        }
                        if (inline_count < inline_tokens.len) {
                            inline_tokens[inline_count] = t;
                            inline_count += 1;
                        }
                        si += 1;
                    }
                }
                if (inline_count > 0) {
                    var result_json: ?ops.JsonValue = null;
                    var inline_cmds: [32]CmdInfo = undefined;
                    var inline_cmd_count: usize = 0;
                    var ti: usize = 0;
                    while (ti < inline_count) {
                        const tok = inline_tokens[ti];
                        const maybe_cmd = parseCmdName(tok);
                        if (maybe_cmd) |c| {
                            const start = ti + 1;
                            ti += 1;
                            var end = start;
                            while (end < inline_count) : (end += 1) {
                                if (parseCmdName(inline_tokens[end]) != null) break;
                            }
                            if (inline_cmd_count < inline_cmds.len) {
                                inline_cmds[inline_cmd_count] = .{ .cmd = c, .args_start = start, .args_end = end };
                                inline_cmd_count += 1;
                            }
                            ti = end;
                        } else {
                            ti += 1;
                        }
                    }
                    if (inline_cmd_count == 0) {
                        var root: ops.JsonValue = .{ .object = .empty };
                        var ki: usize = 0;
                        while (ki + 1 < inline_count) {
                            const key_dup = try gpa.dupe(u8, inline_tokens[ki]);
                            var val = ops.inferType(inline_tokens[ki + 1]);
                            if (val == .string) val = .{ .string = try gpa.dupe(u8, val.string) };
                            switch (root) {
                                .object => |*obj| try obj.put(gpa, key_dup, val),
                                else => {},
                            }
                            ki += 2;
                        }
                        result_json = root;
                    } else {
                        var has_set = false;
                        var has_push = false;
                        var push_has_dot_path = false;
                        for (inline_cmds[0..inline_cmd_count]) |info| {
                            if (info.cmd == .set) has_set = true;
                            if (info.cmd == .push) {
                                has_push = true;
                                const ca = inline_tokens[info.args_start..info.args_end];
                                if (ca.len >= 1 and ca[0].len > 1 and ca[0][0] == '.' and ca[0][1] != '.') {
                                    push_has_dot_path = true;
                                }
                            }
                        }
                        const default_array = has_push and !has_set and !push_has_dot_path;
                        var root: ops.JsonValue = if (default_array) .{ .array = .empty } else .{ .object = .empty };
                        for (inline_cmds[0..inline_cmd_count]) |info| {
                            const ca = inline_tokens[info.args_start..info.args_end];
                            switch (info.cmd) {
                                .set => try execSet(gpa, &root, ca, File.stderr(), io),
                                .del => try execDel(gpa, &root, ca, File.stderr(), io),
                                .push => try execPush(gpa, &root, ca, File.stderr(), io),
                                .pop => try execPop(gpa, &root, ca, File.stderr(), io),
                                .pick => try execPick(gpa, &root, ca, File.stderr(), io),
                                .omit => try execOmit(gpa, &root, ca, File.stderr(), io),
                                else => {},
                            }
                        }
                        result_json = root;
                    }
                    if (result_json) |rj| {
                        var aw = Writer.Allocating.init(gpa);
                        try rj.writeTo(&aw.writer);
                        const json_str = try gpa.dupe(u8, aw.writer.buffer[0..aw.writer.end]);
                        if (processed_len < MAX_ARGS) {
                            processed_buf[processed_len] = json_str;
                            processed_len += 1;
                        }
                        var mut = rj;
                        mut.deinit(gpa);
                    }
                }
            } else {
                if (processed_len < MAX_ARGS) {
                    processed_buf[processed_len] = a;
                    processed_len += 1;
                }
                si += 1;
            }
        }
    }
    const args = processed_buf[0..processed_len];

    if (args.len < 2) {
        try usage(File.stderr(), io);
        return 1;
    }

    var file_path: ?[]const u8 = null;
    var cmd_start: usize = 1;

    if (std.mem.eql(u8, args[1], "-f") or std.mem.eql(u8, args[1], "--file")) {
        if (args.len < 4) {
            try File.writeStreamingAll(File.stderr(), io, "error: -f requires a file path\n");
            return 1;
        }
        file_path = args[2];
        cmd_start = 3;
    }

    // Pre-read stdin once so both readInput (root) and execMerge (merge source)
    // can share the same buffer. pipe data can only be consumed once.
    const is_tty = File.stdin().isTty(io) catch false;
    const stdin_data: []u8 = if (is_tty) &[_]u8{} else readStdinAlloc(gpa, io) catch |err| {
        writeErrorFmt(gpa, io, "error: cannot read stdin: {}\n", .{err});
        return 1;
    };
    defer gpa.free(stdin_data);

    if (cmd_start >= args.len) {
        try usage(File.stderr(), io);
        return 1;
    }

    const stdout_file = File.stdout();
    const stderr_file = File.stderr();

    var commands: [32]CmdInfo = undefined;
    var cmd_count: usize = 0;
    var shorthands: [64]usize = undefined;
    var shorthand_count: usize = 0;
    var i: usize = cmd_start;

    while (i < args.len) {
        const token = args[i];
        const maybe_cmd = parseCmdName(token);
        if (maybe_cmd) |c| {
            const start = i + 1;
            i += 1;
            var end = start;
            while (end < args.len) : (end += 1) {
                if (parseCmdName(args[end]) != null) break;
            }
            if (cmd_count < commands.len) {
                commands[cmd_count] = .{ .cmd = c, .args_start = start, .args_end = end };
                cmd_count += 1;
            }
            i = end;
        } else {
            if (shorthand_count < shorthands.len) {
                shorthands[shorthand_count] = i;
                shorthand_count += 1;
            }
            i += 1;
        }
    }

    if (cmd_count == 0 and shorthand_count == 0) {
        try usage(File.stderr(), io);
        return 1;
    }

    if (shorthand_count > 0) {
        var root_mut = try readInput(gpa, file_path, stdin_data, io, false);
        for (shorthands[0..shorthand_count]) |idx| {
            try execShorthand(gpa, &root_mut, args[idx], stderr_file, io);
        }
        try writeResult(root_mut, gpa, stdout_file, io);
        root_mut.deinit(gpa);
        return 0;
    }

    if (commands[0].cmd == .@"new") {
        return execNew(gpa, args[commands[0].args_start..commands[0].args_end], stdout_file, stderr_file, io);
    }

    if (commands[0].cmd == .get and cmd_count == 1) {
        const root = try readInput(gpa, file_path, stdin_data, io, false);
        return execGet(gpa, root, args[commands[0].args_start..commands[0].args_end], stdout_file, stderr_file, io);
    }

    if (commands[0].cmd == .keys and cmd_count == 1) {
        const root = try readInput(gpa, file_path, stdin_data, io, false);
        return execKeys(gpa, root, args[commands[0].args_start..commands[0].args_end], stdout_file, stderr_file, io);
    }

    if (commands[0].cmd == .has and cmd_count == 1) {
        const root = try readInput(gpa, file_path, stdin_data, io, false);
        return execHas(gpa, root, args[commands[0].args_start..commands[0].args_end], stdout_file, stderr_file, io);
    }

    if (commands[0].cmd == .length and cmd_count == 1) {
        const root = try readInput(gpa, file_path, stdin_data, io, false);
        return execLength(gpa, root, args[commands[0].args_start..commands[0].args_end], stdout_file, stderr_file, io);
    }

    var has_set = false;
    var has_push = false;
    var push_has_dot_path = false;
    for (commands[0..cmd_count]) |info| {
        if (info.cmd == .set) has_set = true;
        if (info.cmd == .push) {
            has_push = true;
            const ca = args[info.args_start..info.args_end];
            if (ca.len >= 1 and ca[0].len > 1 and ca[0][0] == '.' and ca[0][1] != '.') {
                push_has_dot_path = true;
            }
        }
    }
    const default_array = has_push and !has_set and !push_has_dot_path;

    var root_mut = try readInput(gpa, file_path, stdin_data, io, default_array);

    var last_was_pretty = false;
    for (commands[0..cmd_count]) |info| {
        const cmd_args = args[info.args_start..info.args_end];
        switch (info.cmd) {
            .set => try execSet(gpa, &root_mut, cmd_args, stderr_file, io),
            .del => try execDel(gpa, &root_mut, cmd_args, stderr_file, io),
            .push => try execPush(gpa, &root_mut, cmd_args, stderr_file, io),
            .pop => try execPop(gpa, &root_mut, cmd_args, stderr_file, io),
            .pick => try execPick(gpa, &root_mut, cmd_args, stderr_file, io),
            .omit => try execOmit(gpa, &root_mut, cmd_args, stderr_file, io),
            .merge => try execMerge(gpa, &root_mut, cmd_args, stdin_data, io, stderr_file, io),
            .pretty => last_was_pretty = true,
            .compact => last_was_pretty = false,
            .type => {
                if (cmd_count == 1) {
                    return execType(gpa, root_mut, cmd_args, stdout_file, stderr_file, io);
                }
            },
            .@"new" => {},
            .get => {
                if (cmd_count == 1) {
                    return execGet(gpa, root_mut, cmd_args, stdout_file, stderr_file, io);
                }
            },
            .keys => {
                if (cmd_count == 1) {
                    return execKeys(gpa, root_mut, cmd_args, stdout_file, stderr_file, io);
                }
            },
            .has => {
                if (cmd_count == 1) {
                    return execHas(gpa, root_mut, cmd_args, stdout_file, stderr_file, io);
                }
            },
            .length => {
                if (cmd_count == 1) {
                    return execLength(gpa, root_mut, cmd_args, stdout_file, stderr_file, io);
                }
            },
        }
    }

    if (last_was_pretty) {
        try writeResultPretty(root_mut, gpa, stdout_file, io);
    } else {
        try writeResult(root_mut, gpa, stdout_file, io);
    }
    return 0;
}

fn parseCmdName(token: []const u8) ?Cmd {
    if (std.mem.eql(u8, token, "set")) return .set;
    if (std.mem.eql(u8, token, "del")) return .del;
    if (std.mem.eql(u8, token, "push")) return .push;
    if (std.mem.eql(u8, token, "pop")) return .pop;
    if (std.mem.eql(u8, token, "pick")) return .pick;
    if (std.mem.eql(u8, token, "omit")) return .omit;
    if (std.mem.eql(u8, token, "pretty")) return .pretty;
    if (std.mem.eql(u8, token, "compact")) return .compact;
    if (std.mem.eql(u8, token, "type")) return .type;
    if (std.mem.eql(u8, token, "merge")) return .merge;
    if (std.mem.eql(u8, token, "new")) return .@"new";
    if (std.mem.eql(u8, token, "get")) return .get;
    if (std.mem.eql(u8, token, "keys")) return .keys;
    if (std.mem.eql(u8, token, "has")) return .has;
    if (std.mem.eql(u8, token, "length")) return .length;
    return null;
}

fn usage(stderr: File, io: Io) !void {
    try File.writeStreamingAll(stderr, io,
        \\jj - shell-first JSON CLI
        \\
        \\Usage: jj [-f <file>] <cmd> [args] [<cmd> [args] ...]
        \\       jj <path>=<v>   shorthand: set string
        \\       jj <path>:=<v>  shorthand: set (auto-type)
        \\       jj <path>+=<v>  shorthand: array push
        \\       jj <path>-      shorthand: delete
        \\
        \\Chain multiple commands per invocation:
        \\  jj set a 1 del b push c v1 v2 omit d merge f
        \\
        \\Commands:
        \\  new object|array    Create empty JSON
        \\  get <path> [--raw]  Get value at path
        \\  set <p> <v> [p v].. Set string values
        \\  del <path>          Delete value
        \\  push <path> <v>...  Append to array (3 modes: vals / kv / k=v)
        \\  pop <path>          Pop from array tail
        \\  pick <key>...       Keep only listed keys
        \\  omit <key>...       Remove listed keys
        \\  pretty              Pretty-print JSON
        \\  compact             Compact output
        \\  type <path>         Value type at path
        \\  keys [path]         List object keys (one per line)
        \\  has [path]          Check if path exists
        \\  length [path]       Array / object / string size
        \\  merge <file>        Merge file ('-' = stdin)
        \\
        \\Options:
        \\  -f, --file <path>   Read from file instead of stdin
        \\  --raw               Output string without quotes
        \\
    );
}

fn readFileAlloc(gpa: Allocator, io: Io, path: []const u8) ![]const u8 {
    const f = try Dir.cwd().openFile(io, path, .{});
    defer f.close(io);
    var buf: [4096]u8 = undefined;
    var file_reader = f.reader(io, &buf);
    var aw = Writer.Allocating.init(gpa);
    _ = try file_reader.interface.streamRemaining(&aw.writer);
    return try gpa.dupe(u8, aw.writer.buffer[0..aw.writer.end]);
}

fn readInput(
    gpa: Allocator,
    file_path: ?[]const u8,
    stdin_data: []const u8,
    io: Io,
    default_array: bool,
) !ops.JsonValue {
    if (file_path) |fp| {
        const data = readFileAlloc(gpa, io, fp) catch |err| {
            writeErrorFmt(gpa, io, "error: cannot open file: {}\n", .{err});
            std.process.exit(1);
        };
        defer gpa.free(data);
        if (data.len == 0) {
            if (default_array) {
                const arr: std.ArrayList(ops.JsonValue) = .empty;
                return .{ .array = arr };
            } else {
                const obj: std.array_hash_map.String(ops.JsonValue) = .empty;
                return .{ .object = obj };
            }
        }
        return ops.parse(gpa, data) catch |err| {
            writeErrorFmt(gpa, io, "error: parse error: {}\n", .{err});
            std.process.exit(1);
        };
    }

    // No piped stdin available — create a default root.
    if (stdin_data.len == 0) {
        if (default_array) {
            const arr: std.ArrayList(ops.JsonValue) = .empty;
            return .{ .array = arr };
        } else {
            const obj: std.array_hash_map.String(ops.JsonValue) = .empty;
            return .{ .object = obj };
        }
    }

    return ops.parse(gpa, stdin_data) catch |err| {
        writeErrorFmt(gpa, io, "error: parse error: {}\n", .{err});
        std.process.exit(1);
    };
}

/// Reads all of stdin into a freshly allocated buffer. Caller owns the result
/// and must `gpa.free`. Used by `merge` and exposed for testability.
fn readStdinAlloc(gpa: Allocator, io: Io) ![]u8 {
    var buf: [4096]u8 = undefined;
    var file_reader = File.stdin().reader(io, &buf);
    var aw = Writer.Allocating.init(gpa);
    _ = file_reader.interface.streamRemaining(&aw.writer) catch {};
    return try gpa.dupe(u8, aw.writer.buffer[0..aw.writer.end]);
}

fn writeErrorFmt(gpa: Allocator, io: Io, comptime fmt: []const u8, args: anytype) void {
    var aw = Writer.Allocating.init(gpa);
    aw.writer.print(fmt, args) catch {};
    File.writeStreamingAll(File.stderr(), io, aw.writer.buffer[0..aw.writer.end]) catch {};
}

fn writeResult(root: ops.JsonValue, gpa: Allocator, stdout: File, io: Io) !void {
    var aw = Writer.Allocating.init(gpa);
    try root.writeTo(&aw.writer);
    try aw.writer.writeByte('\n');
    try File.writeStreamingAll(stdout, io, aw.writer.buffer[0..aw.writer.end]);
}

fn writeResultPretty(root: ops.JsonValue, gpa: Allocator, stdout: File, io: Io) !void {
    var aw = Writer.Allocating.init(gpa);
    try root.writePretty(&aw.writer, 0);
    try aw.writer.writeByte('\n');
    try File.writeStreamingAll(stdout, io, aw.writer.buffer[0..aw.writer.end]);
}

fn execNew(gpa: Allocator, cmd_args: []const []const u8, stdout: File, stderr: File, io: Io) !u8 {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'new' requires 'object' or 'array'\n");
        return 1;
    }
    if (std.mem.eql(u8, cmd_args[0], "object")) {
        const obj: std.array_hash_map.String(ops.JsonValue) = .empty;
        try writeResult(.{ .object = obj }, gpa, stdout, io);
        return 0;
    } else if (std.mem.eql(u8, cmd_args[0], "array")) {
        const arr: std.ArrayList(ops.JsonValue) = .empty;
        try writeResult(.{ .array = arr }, gpa, stdout, io);
        return 0;
    } else {
        try File.writeStreamingAll(stderr, io, "error: 'new' requires 'object' or 'array'\n");
        return 1;
    }
}

fn execGet(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, stderr: File, io: Io) !u8 {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'get' requires a path\n");
        return 1;
    }
    const path = normalizePath(cmd_args[0]);
    var is_raw = false;
    for (cmd_args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--raw")) is_raw = true;
    }
    var result = ops.get(root, path, gpa) catch |err| {
        switch (err) {
            ops.OpError.PathNotFound => {
                writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path});
                return 2;
            },
            ops.OpError.InvalidType => {
                writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path});
                return 3;
            },
            ops.OpError.InvalidPath => {
                writeErrorFmt(gpa, io, "error: invalid path: {s}\n", .{path});
                return 3;
            },
            else => return err,
        }
    };
    defer result.deinit(gpa);
    var aw = Writer.Allocating.init(gpa);
    if (is_raw) {
        switch (result) {
            .string => |s| try aw.writer.print("{s}\n", .{s}),
            .integer => |i| try aw.writer.print("{d}\n", .{i}),
            .number => |f| try aw.writer.print("{d}\n", .{f}),
            .boolean => |b| try aw.writer.print("{s}\n", .{if (b) "true" else "false"}),
            .null => try aw.writer.writeAll("null\n"),
            else => {
                try result.writeTo(&aw.writer);
                try aw.writer.writeByte('\n');
            },
        }
    } else {
        switch (result) {
            .string => |s| try aw.writer.print("\"{s}\"\n", .{s}),
            else => {
                try result.writeTo(&aw.writer);
                try aw.writer.writeByte('\n');
            },
        }
    }
    try File.writeStreamingAll(stdout, io, aw.writer.buffer[0..aw.writer.end]);
    return 0;
}

fn normalizePath(path: []const u8) []const u8 {
    if (path.len == 0) return path;
    if (std.mem.eql(u8, path, ".")) return "";
    if (path[0] == '.') return path[1..];
    return path;
}

fn parseValue(gpa: Allocator, str: []const u8) !ops.JsonValue {
    if (str.len > 0 and (str[0] == '{' or str[0] == '[')) {
        return ops.parse(gpa, str);
    }
    return .{ .string = try gpa.dupe(u8, str) };
}

/// Deinitializes a `String(JsonValue)` map, freeing every key and value.
fn deinitObject(gpa: Allocator, obj: *std.array_hash_map.String(ops.JsonValue)) void {
    var it = obj.iterator();
    while (it.next()) |e| {
        gpa.free(e.key_ptr.*);
        var v = e.value_ptr.*;
        v.deinit(gpa);
    }
    obj.deinit(gpa);
}

/// Wraps `ops.push` with the standard error → stderr mapping shared by all
/// push modes. `set_mode` switches to `ops.set` (used when the root is an
/// object and `.` push means "merge into root").
fn pushOrSet(
    gpa: Allocator,
    root: *ops.JsonValue,
    path: []const u8,
    value: ops.JsonValue,
    io: Io,
    set_mode: bool,
) !void {
    if (set_mode) {
        ops.set(root, path, value, gpa) catch |err| {
            switch (err) {
                ops.OpError.InvalidType, ops.OpError.InvalidPath => {
                    writeErrorFmt(gpa, io, "error: invalid type/path: {s}\n", .{path});
                },
                else => return err,
            }
        };
    } else {
        ops.push(root, path, value, gpa) catch |err| {
            switch (err) {
                ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                ops.OpError.InvalidType => writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path}),
                else => return err,
            }
        };
    }
}

const ObjectBuildResult = struct {
    obj: std.array_hash_map.String(ops.JsonValue),
    consumed: usize,
};

/// Builds an object from a `[k1, v1, k2, v2, ...]` argv slice. Stops as soon
/// as fewer than 2 tokens remain (odd trailing token is left for the caller
/// to handle — typically as a JSON fallback).
fn buildObjectFromPairs(
    gpa: Allocator,
    rest: []const []const u8,
    io: Io,
) !ObjectBuildResult {
    var obj: std.array_hash_map.String(ops.JsonValue) = .empty;
    errdefer deinitObject(gpa, &obj);

    var k: usize = 0;
    while (k + 1 < rest.len) {
        const key = rest[k];
        const val_str = rest[k + 1];
        const key_dup = try gpa.dupe(u8, key);
        errdefer gpa.free(key_dup);
        var val: ops.JsonValue = undefined;
        if (looksLikeJson(val_str)) {
            const result = parseSmartJsonValue(gpa, val_str, rest[k + 2 ..]) catch {
                writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{val_str});
                return error.InvalidJson;
            };
            val = result.value;
            k += 2 + result.consumed;
        } else {
            val = ops.inferType(val_str);
            if (val == .string) {
                val = .{ .string = try gpa.dupe(u8, val.string) };
            }
            k += 2;
        }
        try obj.put(gpa, key_dup, val);
    }
    return .{ .obj = obj, .consumed = k };
}

/// Smart-stitches a JSON value from shell-tokenized args. When `val_str` starts
/// with `{` or `[`, attempts to parse it as JSON; on parse failure, appends a
/// space + the next token from `rest` and retries. Returns the parsed value
/// and how many additional tokens were consumed.
///
/// `rest` is the slice of subsequent argv tokens; the helper will not consume
/// past its length. If no combination parses, returns `error.InvalidJson`.
///
/// Used by `set`/`push` to recover from shell tokenization that splits
/// JSON literals (e.g. `'{"a":1}'` becomes 3 tokens after expansion).
const SmartJsonResult = struct {
    value: ops.JsonValue,
    consumed: usize,
};

fn parseSmartJsonValue(
    gpa: Allocator,
    val_str: []const u8,
    rest: []const []const u8,
) !SmartJsonResult {
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(gpa);
    try json_buf.appendSlice(gpa, val_str);
    var consumed: usize = 0;
    while (consumed < rest.len) {
        if (ops.parse(gpa, json_buf.items)) |_| {
            break;
        } else |_| {}
        try json_buf.append(gpa, ' ');
        try json_buf.appendSlice(gpa, rest[consumed]);
        consumed += 1;
    }
    const value = ops.parse(gpa, json_buf.items) catch return error.InvalidJson;
    return .{ .value = value, .consumed = consumed };
}

fn execSet(gpa: Allocator, root: *ops.JsonValue, cmd_args: []const []const u8, stderr: File, io: Io) !void {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'set' requires at least one argument\n");
        return;
    }
    var i: usize = 0;
    while (i < cmd_args.len) {
        const arg = cmd_args[i];

        // 1. path- 形态 (shorthand delete)
        if (arg.len > 0 and arg[arg.len - 1] == '-') {
            const path = normalizePath(arg[0 .. arg.len - 1]);
            ops.del(root, path, gpa) catch |err| {
                switch (err) {
                    ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                    else => return err,
                }
            };
            i += 1;
            continue;
        }

        // 2. =, :=, += shorthand
        if (std.mem.indexOfScalar(u8, arg, '=')) |eq_pos| {
            const op: enum { set_string, set_auto, push_array } = blk: {
                if (eq_pos > 0) {
                    if (arg[eq_pos - 1] == ':') break :blk .set_auto;
                    if (arg[eq_pos - 1] == '+') break :blk .push_array;
                }
                break :blk .set_string;
            };
            const path_end = switch (op) {
                .set_string => eq_pos,
                .set_auto, .push_array => eq_pos - 1,
            };
            const path = normalizePath(arg[0..path_end]);
            const val_str = arg[eq_pos + 1 ..];

            var value: ops.JsonValue = undefined;
            var consumed: usize = 0;

            if (val_str.len > 0 and (val_str[0] == '{' or val_str[0] == '[')) {
                const result = parseSmartJsonValue(gpa, val_str, cmd_args[i + 1 ..]) catch {
                    writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{val_str});
                    return;
                };
                value = result.value;
                consumed = result.consumed;
            } else if (op == .set_string) {
                value = parseValue(gpa, val_str) catch |err| {
                    writeErrorFmt(gpa, io, "error: invalid value: {s}\n", .{val_str});
                    return err;
                };
            } else {
                value = ops.inferType(val_str);
                if (value == .string) {
                    value = .{ .string = try gpa.dupe(u8, value.string) };
                }
            }

            switch (op) {
                .set_string, .set_auto => {
                    ops.set(root, path, value, gpa) catch |err| {
                        switch (err) {
                            ops.OpError.InvalidType, ops.OpError.InvalidPath => {
                                writeErrorFmt(gpa, io, "error: invalid type/path: {s}\n", .{path});
                            },
                            else => return err,
                        }
                    };
                },
                .push_array => {
                    ops.push(root, path, value, gpa) catch |err| {
                        switch (err) {
                            ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                            ops.OpError.InvalidType => writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path}),
                            else => return err,
                        }
                    };
                },
            }
            i += 1 + consumed;
            continue;
        }

        // 3. path value 形式（隐式 set）
        if (i + 1 >= cmd_args.len) {
            try File.writeStreamingAll(stderr, io, "error: 'set' requires path value pairs\n");
            return;
        }
        const path = normalizePath(arg);
        const value_str = cmd_args[i + 1];
        var auto_type = false;
        if (std.mem.eql(u8, value_str, "--type") or std.mem.eql(u8, value_str, ":=")) {
            auto_type = true;
            i += 2;
            if (i >= cmd_args.len) {
                try File.writeStreamingAll(stderr, io, "error: 'set' := requires a value\n");
                return;
            }
        }
        const actual_val = if (auto_type) cmd_args[i] else value_str;
        var value: ops.JsonValue = undefined;
        var consumed: usize = 0;
        if (actual_val.len > 0 and (actual_val[0] == '{' or actual_val[0] == '[')) {
            const rest_start = if (auto_type) i + 1 else i + 2;
            const result = parseSmartJsonValue(gpa, actual_val, cmd_args[rest_start..]) catch {
                writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{actual_val});
                return;
            };
            value = result.value;
            consumed = result.consumed;
            i = rest_start + consumed;
        } else if (auto_type) {
            value = ops.inferType(actual_val);
            if (value == .string) {
                value = .{ .string = try gpa.dupe(u8, value.string) };
            }
            i += 1;
        } else {
            value = parseValue(gpa, actual_val) catch |err| {
                writeErrorFmt(gpa, io, "error: invalid value: {s}\n", .{actual_val});
                return err;
            };
            i += 2;
        }
        ops.set(root, path, value, gpa) catch |err| {
            switch (err) {
                ops.OpError.InvalidType, ops.OpError.InvalidPath => {
                    writeErrorFmt(gpa, io, "error: invalid type/path: {s}\n", .{path});
                },
                else => return err,
            }
        };
    }
}

fn execDel(gpa: Allocator, root: *ops.JsonValue, cmd_args: []const []const u8, stderr: File, io: Io) !void {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'del' requires a path\n");
        return;
    }
    ops.del(root, normalizePath(cmd_args[0]), gpa) catch |err| {
        switch (err) {
            ops.OpError.PathNotFound => {
                writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{cmd_args[0]});
            },
            ops.OpError.InvalidType => {
                writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{cmd_args[0]});
            },
            else => return err,
        }
    };
}

// =====================================================================
// execPush — dispatcher + 4 mode-specific functions.
//
// Mode 1 (execPushRootArray): root is array, first arg is "." / empty
//                             → build object from kv pairs (or parse JSON
//                               literal) and push to root
// Mode 2 (execPushRootObject): root is object, first arg is "." / empty
//                              → set k/v pairs into root (merge semantics)
// Mode 3 (execPushNamedPath): first arg is ".path" → push object/JSON/values
//                             to that path's array (auto-creating if missing)
// Mode 4 (execPushValues):  no leading dot → push to path (or root if array)
//                           with kv pairs / independent values / JSON
// =====================================================================

fn execPushRootArray(gpa: Allocator, root: *ops.JsonValue, rest: []const []const u8, io: Io) !void {
    const path: []const u8 = "";
    if (rest.len == 0) {
        try pushOrSet(gpa, root, path, .null, io, false);
        return;
    }
    // JSON literal path: rest[0] begins with `{` or `[`
    if (looksLikeJson(rest[0])) {
        const result = parseSmartJsonValue(gpa, rest[0], rest[1..]) catch {
            writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{rest[0]});
            return;
        };
        try pushOrSet(gpa, root, path, result.value, io, false);
        return;
    }
    // Build object from kv pairs. On failure, k=v parse error → propagate.
    var result = try buildObjectFromPairs(gpa, rest, io);
    errdefer deinitObject(gpa, &result.obj);
    if (result.obj.count() == 0 and result.consumed < rest.len) {
        // Odd trailing token — try parsing it (and any further tokens) as JSON.
        const jr = parseSmartJsonValue(
            gpa,
            rest[result.consumed],
            rest[result.consumed + 1 ..],
        ) catch {
            writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{rest[result.consumed]});
            return;
        };
        try pushOrSet(gpa, root, path, jr.value, io, false);
        return;
    }
    try pushOrSet(gpa, root, path, .{ .object = result.obj }, io, false);
}

fn execPushRootObject(gpa: Allocator, root: *ops.JsonValue, rest: []const []const u8, io: Io) !void {
    var k: usize = 0;
    while (k + 1 < rest.len) {
        const key = rest[k];
        const val_str = rest[k + 1];
        var val: ops.JsonValue = undefined;
        if (looksLikeJson(val_str)) {
            const r = parseSmartJsonValue(gpa, val_str, rest[k + 2 ..]) catch {
                writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{val_str});
                return;
            };
            val = r.value;
            k += 2 + r.consumed;
        } else {
            val = ops.inferType(val_str);
            if (val == .string) {
                val = .{ .string = try gpa.dupe(u8, val.string) };
            }
            k += 2;
        }
        try pushOrSet(gpa, root, key, val, io, true);
    }
}

fn execPushNamedPath(gpa: Allocator, root: *ops.JsonValue, path: []const u8, rest: []const []const u8, io: Io) !void {
    if (rest.len == 0) {
        try pushOrSet(gpa, root, path, .null, io, false);
        return;
    }
    if (looksLikeJson(rest[0])) {
        const result = parseSmartJsonValue(gpa, rest[0], rest[1..]) catch {
            writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{rest[0]});
            return;
        };
        try pushOrSet(gpa, root, path, result.value, io, false);
        return;
    }
    var result = try buildObjectFromPairs(gpa, rest, io);
    errdefer deinitObject(gpa, &result.obj);
    if (result.obj.count() > 0) {
        try pushOrSet(gpa, root, path, .{ .object = result.obj }, io, false);
        return;
    }
    // No kv pairs formed — treat rest as independent values
    for (rest) |val_str| {
        var val = ops.inferType(val_str);
        if (val == .string) {
            val = .{ .string = try gpa.dupe(u8, val.string) };
        }
        try pushOrSet(gpa, root, path, val, io, false);
    }
}

fn execPushValues(gpa: Allocator, root: *ops.JsonValue, path: []const u8, rest: []const []const u8, io: Io) !void {
    if (rest.len == 0) {
        try pushOrSet(gpa, root, path, .null, io, false);
        return;
    }
    // k=v syntax (e.g. `push history role=user content=hello`)
    if (rest.len >= 2 and containsEquals(rest[0])) {
        var obj: std.array_hash_map.String(ops.JsonValue) = .empty;
        errdefer deinitObject(gpa, &obj);
        for (rest) |kv| {
            if (std.mem.indexOfScalar(u8, kv, '=')) |eq_pos| {
                const key_dup = try gpa.dupe(u8, kv[0..eq_pos]);
                const val = ops.inferType(kv[eq_pos + 1 ..]);
                const val_owned: ops.JsonValue = if (val == .string) .{ .string = try gpa.dupe(u8, val.string) } else val;
                try obj.put(gpa, key_dup, val_owned);
            }
        }
        try pushOrSet(gpa, root, path, .{ .object = obj }, io, false);
        return;
    }
    // Mixed JSON / primitive values
    var m: usize = 0;
    while (m < rest.len) {
        if (looksLikeJson(rest[m])) {
            const r = parseSmartJsonValue(gpa, rest[m], rest[m + 1 ..]) catch {
                writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{rest[m]});
                return;
            };
            try pushOrSet(gpa, root, path, r.value, io, false);
            m += 1 + r.consumed;
        } else {
            var val = ops.inferType(rest[m]);
            if (val == .string) {
                val = .{ .string = try gpa.dupe(u8, val.string) };
            }
            try pushOrSet(gpa, root, path, val, io, false);
            m += 1;
        }
    }
}

fn execPush(gpa: Allocator, root: *ops.JsonValue, cmd_args: []const []const u8, stderr: File, io: Io) !void {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'push' requires at least one value\n");
        return;
    }

    const first_dot = cmd_args[0].len == 0 or
        std.mem.eql(u8, cmd_args[0], ".") or
        (cmd_args[0].len > 1 and cmd_args[0][0] == '.' and cmd_args[0][1] != '.');
    const is_root_array = root.* == .array;
    const dot_only = first_dot and cmd_args[0].len <= 1;
    const dot_with_named = first_dot and cmd_args[0].len > 1;

    if (dot_only and is_root_array) {
        return execPushRootArray(gpa, root, cmd_args[1..], io);
    }
    if (dot_only and !is_root_array) {
        return execPushRootObject(gpa, root, cmd_args[1..], io);
    }
    if (dot_with_named) {
        return execPushNamedPath(gpa, root, normalizePath(cmd_args[0]), cmd_args[1..], io);
    }
    const path: []const u8 = if (is_root_array) "" else normalizePath(cmd_args[0]);
    const rest = if (is_root_array) cmd_args[0..] else cmd_args[1..];
    return execPushValues(gpa, root, path, rest, io);
}

fn containsEquals(s: []const u8) bool {
    return std.mem.indexOfScalar(u8, s, '=') != null;
}

fn looksLikeJson(s: []const u8) bool {
    return s.len > 0 and (s[0] == '{' or s[0] == '[');
}

fn execPop(gpa: Allocator, root: *ops.JsonValue, cmd_args: []const []const u8, stderr: File, io: Io) !void {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'pop' requires a path\n");
        return;
    }
    const popped = ops.pop(root, normalizePath(cmd_args[0]), gpa) catch |err| {
        switch (err) {
            ops.OpError.PathNotFound => {
                writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{cmd_args[0]});
            },
            ops.OpError.InvalidType => {
                writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{cmd_args[0]});
            },
            else => return err,
        }
        return;
    };
    _ = popped;
}

fn execPick(gpa: Allocator, root: *ops.JsonValue, cmd_args: []const []const u8, stderr: File, io: Io) !void {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'pick' requires at least one key\n");
        return;
    }
    ops.pick(root, cmd_args, gpa) catch |err| {
        switch (err) {
            ops.OpError.InvalidType => {
                try File.writeStreamingAll(stderr, io, "error: pick requires an object\n");
            },
            else => return err,
        }
    };
}

fn execOmit(gpa: Allocator, root: *ops.JsonValue, cmd_args: []const []const u8, stderr: File, io: Io) !void {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'omit' requires at least one key\n");
        return;
    }
    ops.omit(root, cmd_args, gpa) catch |err| {
        switch (err) {
            ops.OpError.InvalidType => {
                try File.writeStreamingAll(stderr, io, "error: omit requires an object\n");
            },
            else => return err,
        }
    };
}

fn execType(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, stderr: File, io: Io) !u8 {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'type' requires a path\n");
        return 1;
    }
    const path = normalizePath(cmd_args[0]);
    var result = ops.get(root, path, gpa) catch |err| {
        switch (err) {
            ops.OpError.PathNotFound => {
                writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path});
                return 2;
            },
            ops.OpError.InvalidType => {
                writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path});
                return 3;
            },
            else => return err,
        }
    };
    defer result.deinit(gpa);
    var aw = Writer.Allocating.init(gpa);
    try aw.writer.print("{s}\n", .{result.getTypeName()});
    try File.writeStreamingAll(stdout, io, aw.writer.buffer[0..aw.writer.end]);
    return 0;
}

fn execKeys(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, _: File, io: Io) !u8 {
    // No arg means root path (matches `get` convention)
    const path: []const u8 = if (cmd_args.len >= 1) normalizePath(cmd_args[0]) else "";
    var owned = ops.keys(root, path, gpa) catch |err| {
        switch (err) {
            ops.OpError.PathNotFound => {
                writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path});
                return 2;
            },
            ops.OpError.InvalidType => {
                writeErrorFmt(gpa, io, "error: 'keys' requires an object at path: {s}\n", .{path});
                return 3;
            },
            else => return err,
        }
    };
    defer {
        for (owned.items) |k| gpa.free(k);
        owned.deinit(gpa);
    }
    var aw = Writer.Allocating.init(gpa);
    for (owned.items) |k| {
        try aw.writer.print("{s}\n", .{k});
    }
    try File.writeStreamingAll(stdout, io, aw.writer.buffer[0..aw.writer.end]);
    return 0;
}

fn execHas(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, _: File, io: Io) !u8 {
    // No arg means root path
    const path: []const u8 = if (cmd_args.len >= 1) normalizePath(cmd_args[0]) else "";
    const result = ops.has(root, path, gpa);
    var aw = Writer.Allocating.init(gpa);
    try aw.writer.print("{s}\n", .{if (result) "true" else "false"});
    try File.writeStreamingAll(stdout, io, aw.writer.buffer[0..aw.writer.end]);
    return 0;
}

fn execLength(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, _: File, io: Io) !u8 {
    // No arg means root path
    const path: []const u8 = if (cmd_args.len >= 1) normalizePath(cmd_args[0]) else "";
    const n = ops.length(root, path, gpa) catch |err| {
        switch (err) {
            ops.OpError.PathNotFound => {
                writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path});
                return 2;
            },
            ops.OpError.InvalidType => {
                writeErrorFmt(gpa, io, "error: 'length' requires an array, object, or string at path: {s}\n", .{path});
                return 3;
            },
            else => return err,
        }
    };
    var aw = Writer.Allocating.init(gpa);
    try aw.writer.print("{d}\n", .{n});
    try File.writeStreamingAll(stdout, io, aw.writer.buffer[0..aw.writer.end]);
    return 0;
}

fn execMerge(
    gpa: Allocator,
    root: *ops.JsonValue,
    cmd_args: []const []const u8,
    stdin_data: []const u8,
    io: Io,
    stderr: File,
    _: Io,
) !void {
    // Source selection:
    //   - arg == "-"  → read from stdin (pre-read buffer)
    //   - no arg      → read from stdin (matches shell convention)
    //   - otherwise   → file path
    const merge_input: []const u8 = blk: {
        if (cmd_args.len < 1 or std.mem.eql(u8, cmd_args[0], "-")) {
            if (stdin_data.len == 0) {
                writeErrorFmt(gpa, io, "error: 'merge' from stdin but no stdin available\n", .{});
                return;
            }
            break :blk stdin_data;
        } else {
            const file_buf = readFileAlloc(gpa, io, cmd_args[0]) catch |err| {
                writeErrorFmt(gpa, io, "error: cannot open file: {}\n", .{err});
                return;
            };
            // Parse now, free after. The file_buf is owned here.
            defer gpa.free(file_buf);
            const other = ops.parse(gpa, file_buf) catch |err| {
                writeErrorFmt(gpa, io, "error: parse error in merge source: {}\n", .{err});
                return;
            };
            mergeInto(gpa, root, other, stderr, io) catch |err| {
                var mut = other;
                mut.deinit(gpa);
                return err;
            };
            var mut = other;
            mut.deinit(gpa);
            return;
        }
    };

    const other = ops.parse(gpa, merge_input) catch |err| {
        writeErrorFmt(gpa, io, "error: parse error in merge source: {}\n", .{err});
        return;
    };
    var other_mut = other;
    defer other_mut.deinit(gpa);

    try mergeInto(gpa, root, other_mut, stderr, io);
}

/// Performs the actual merge: copies all keys from `other` into `root.*`.
/// Both must be objects. Reports errors via stderr.
fn mergeInto(gpa: Allocator, root: *ops.JsonValue, other: ops.JsonValue, stderr: File, io: Io) !void {
    switch (root.*) {
        .object => |*obj| {
            switch (other) {
                .object => |other_obj| {
                    var iter = other_obj.iterator();
                    while (iter.next()) |entry| {
                        const key_dup = try gpa.dupe(u8, entry.key_ptr.*);
                        const val_dup = try entry.value_ptr.*.clone(gpa);
                        const existing = try obj.fetchPut(gpa, key_dup, val_dup);
                        if (existing) |old| {
                            // Key already present: fetchPut returned the old
                            // (key, value) pair. The map STILL references
                            // `old.key` — we must NOT free it, or the entry's
                            // key pointer dangles and subsequent readTo prints
                            // garbage. Our own `key_dup` (which the map did
                            // not adopt) must be freed.
                            var old_val = old.value;
                            old_val.deinit(gpa);
                            gpa.free(key_dup);
                        }
                    }
                },
                else => {
                    try File.writeStreamingAll(stderr, io, "error: merge source must be an object\n");
                },
            }
        },
        else => {
            try File.writeStreamingAll(stderr, io, "error: merge target must be an object\n");
        },
    }
}

fn execShorthand(gpa: Allocator, root: *ops.JsonValue, cmd: []const u8, stderr: File, io: Io) !void {
    if (cmd.len == 0) {
        try File.writeStreamingAll(stderr, io, "error: unknown command\n");
        return;
    }
    const last = cmd[cmd.len - 1];
    if (last == '-') {
        const path = cmd[0 .. cmd.len - 1];
        ops.del(root, path, gpa) catch |err| {
            switch (err) {
                ops.OpError.PathNotFound => {
                    writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path});
                },
                else => return err,
            }
        };
        return;
    }
    if (std.mem.indexOfScalar(u8, cmd, '=')) |eq_pos| {
        const path = cmd[0..eq_pos];
        const rest = cmd[eq_pos + 1 ..];
        if (eq_pos > 0 and cmd[eq_pos - 1] == ':') {
            const actual_path = cmd[0 .. eq_pos - 1];
            var value = ops.inferType(rest);
            if (value == .string) {
                value = .{ .string = try gpa.dupe(u8, value.string) };
            }
            ops.set(root, actual_path, value, gpa) catch |err| {
                switch (err) {
                    ops.OpError.InvalidType, ops.OpError.InvalidPath => {
                        writeErrorFmt(gpa, io, "error: invalid type/path: {s}\n", .{actual_path});
                    },
                    else => return err,
                }
            };
        } else if (eq_pos > 0 and cmd[eq_pos - 1] == '+') {
            const actual_path = cmd[0 .. eq_pos - 1];
            const value = parseValue(gpa, rest) catch |err| {
                writeErrorFmt(gpa, io, "error: invalid value: {s}\n", .{rest});
                return err;
            };
            ops.push(root, actual_path, value, gpa) catch |err| {
                switch (err) {
                    ops.OpError.PathNotFound => {
                        writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{actual_path});
                    },
                    ops.OpError.InvalidType => {
                        writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{actual_path});
                    },
                    else => return err,
                }
            };
        } else {
            const value = parseValue(gpa, rest) catch |err| {
                writeErrorFmt(gpa, io, "error: invalid value: {s}\n", .{rest});
                return err;
            };
            ops.set(root, path, value, gpa) catch |err| {
                switch (err) {
                    ops.OpError.InvalidType, ops.OpError.InvalidPath => {
                        writeErrorFmt(gpa, io, "error: invalid type/path: {s}\n", .{path});
                    },
                    else => return err,
                }
            };
        }
        return;
    }
    writeErrorFmt(gpa, io, "error: unknown command: {s}\n", .{cmd});
}

// ============================================================================
// Tests
// ============================================================================

test "parseCmdName all known commands" {
    try std.testing.expectEqual(Cmd.set, parseCmdName("set").?);
    try std.testing.expectEqual(Cmd.del, parseCmdName("del").?);
    try std.testing.expectEqual(Cmd.push, parseCmdName("push").?);
    try std.testing.expectEqual(Cmd.pop, parseCmdName("pop").?);
    try std.testing.expectEqual(Cmd.pick, parseCmdName("pick").?);
    try std.testing.expectEqual(Cmd.omit, parseCmdName("omit").?);
    try std.testing.expectEqual(Cmd.pretty, parseCmdName("pretty").?);
    try std.testing.expectEqual(Cmd.compact, parseCmdName("compact").?);
    try std.testing.expectEqual(Cmd.type, parseCmdName("type").?);
    try std.testing.expectEqual(Cmd.merge, parseCmdName("merge").?);
    try std.testing.expectEqual(Cmd.@"new", parseCmdName("new").?);
    try std.testing.expectEqual(Cmd.get, parseCmdName("get").?);
    try std.testing.expectEqual(Cmd.keys, parseCmdName("keys").?);
    try std.testing.expectEqual(Cmd.has, parseCmdName("has").?);
    try std.testing.expectEqual(Cmd.length, parseCmdName("length").?);
}

test "parseCmdName unknown returns null" {
    try std.testing.expect(parseCmdName("unknown") == null);
    try std.testing.expect(parseCmdName("") == null);
    try std.testing.expect(parseCmdName("Set") == null); // case-sensitive
}

test "normalizePath strips leading dot" {
    try std.testing.expectEqualStrings("", normalizePath(""));
    try std.testing.expectEqualStrings("", normalizePath("."));
    try std.testing.expectEqualStrings("a", normalizePath("a"));
    try std.testing.expectEqualStrings("a", normalizePath(".a"));
    try std.testing.expectEqualStrings("a.b", normalizePath(".a.b"));
    try std.testing.expectEqualStrings("user.name", normalizePath("user.name"));
}

test "looksLikeJson" {
    try std.testing.expect(looksLikeJson("{"));
    try std.testing.expect(looksLikeJson("["));
    try std.testing.expect(looksLikeJson("{}"));
    try std.testing.expect(looksLikeJson("[]"));
    try std.testing.expect(!looksLikeJson(""));
    try std.testing.expect(!looksLikeJson("a"));
    try std.testing.expect(!looksLikeJson("123"));
}

test "containsEquals" {
    try std.testing.expect(containsEquals("a=b"));
    try std.testing.expect(containsEquals("key=value=more"));
    try std.testing.expect(!containsEquals("plain"));
    try std.testing.expect(!containsEquals(""));
}

test "parseValue wraps plain strings" {
    const gpa = std.testing.allocator;
    var v = try parseValue(gpa, "hello");
    defer v.deinit(gpa);
    try std.testing.expect(v == .string);
    try std.testing.expectEqualStrings("hello", v.string);
}

test "parseValue parses inline JSON object" {
    const gpa = std.testing.allocator;
    var v = try parseValue(gpa, "{\"k\":1}");
    defer v.deinit(gpa);
    try std.testing.expect(v == .object);
    try std.testing.expectEqual(@as(usize, 1), v.object.count());
}

test "parseValue parses inline JSON array" {
    const gpa = std.testing.allocator;
    var v = try parseValue(gpa, "[1,2,3]");
    defer v.deinit(gpa);
    try std.testing.expect(v == .array);
    try std.testing.expectEqual(@as(usize, 3), v.array.items.len);
}

test "parseSmartJsonValue single token" {
    const gpa = std.testing.allocator;
    var r = try parseSmartJsonValue(gpa, "42", &.{});
    defer r.value.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 0), r.consumed);
    try std.testing.expect(r.value == .integer and r.value.integer == 42);
}

test "parseSmartJsonValue non-JSON passes through as string" {
    const gpa = std.testing.allocator;
    var r = try parseSmartJsonValue(gpa, "hello", &.{});
    defer r.value.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 0), r.consumed);
    try std.testing.expect(r.value == .string);
    try std.testing.expectEqualStrings("hello", r.value.string);
}

test "parseSmartJsonValue stitches split JSON" {
    const gpa = std.testing.allocator;
    const rest = [_][]const u8{ "\"world\"}" };
    var r = try parseSmartJsonValue(gpa, "{\"x\":", &rest);
    defer r.value.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), r.consumed);
    try std.testing.expect(r.value == .object);
    const x = r.value.object.get("x").?;
    try std.testing.expect(x == .string);
    try std.testing.expectEqualStrings("world", x.string);
}

test "parseSmartJsonValue consumes all on multi-token JSON" {
    const gpa = std.testing.allocator;
    const rest = [_][]const u8{ "1", "2", "3]" };
    var r = try parseSmartJsonValue(gpa, "[", &rest);
    defer r.value.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 3), r.consumed);
    try std.testing.expect(r.value == .array);
    try std.testing.expectEqual(@as(usize, 3), r.value.array.items.len);
}

test "parseSmartJsonValue fails on unparseable input" {
    const gpa = std.testing.allocator;
    const rest = [_][]const u8{ "more" };
    const result = parseSmartJsonValue(gpa, "{{{", &rest);
    try std.testing.expectError(error.InvalidJson, result);
}

test "deinitObject on empty map is safe" {
    const gpa = std.testing.allocator;
    var obj: std.array_hash_map.String(ops.JsonValue) = .empty;
    deinitObject(gpa, &obj);
    // No crash = success
}

test "buildObjectFromPairs basic key-value pairs" {
    const gpa = std.testing.allocator;
    const rest = [_][]const u8{ "a", "1", "b", "2" };
    var r = try buildObjectFromPairs(gpa, &rest, std.testing.io);
    defer deinitObject(gpa, &r.obj);
    try std.testing.expectEqual(@as(usize, 2), r.obj.count());
    try std.testing.expectEqual(@as(usize, 4), r.consumed);
    const a = r.obj.get("a").?;
    try std.testing.expect(a == .string);
    try std.testing.expectEqualStrings("1", a.string);
}

test "buildObjectFromPairs with JSON value" {
    const gpa = std.testing.allocator;
    const rest = [_][]const u8{ "a", "{\"x\":1}" };
    var r = try buildObjectFromPairs(gpa, &rest, std.testing.io);
    defer deinitObject(gpa, &r.obj);
    try std.testing.expectEqual(@as(usize, 1), r.obj.count());
    const a = r.obj.get("a").?;
    try std.testing.expect(a == .object);
    try std.testing.expectEqual(@as(usize, 1), a.object.count());
}

test "buildObjectFromPairs odd trailing token leaves it unconsumed" {
    const gpa = std.testing.allocator;
    const rest = [_][]const u8{ "a", "1", "trailing" };
    var r = try buildObjectFromPairs(gpa, &rest, std.testing.io);
    defer deinitObject(gpa, &r.obj);
    try std.testing.expectEqual(@as(usize, 1), r.obj.count());
    try std.testing.expectEqual(@as(usize, 2), r.consumed);
}

test "buildObjectFromPairs empty input returns empty obj" {
    const gpa = std.testing.allocator;
    const rest = [_][]const u8{};
    var r = try buildObjectFromPairs(gpa, &rest, std.testing.io);
    defer deinitObject(gpa, &r.obj);
    try std.testing.expectEqual(@as(usize, 0), r.obj.count());
    try std.testing.expectEqual(@as(usize, 0), r.consumed);
}
