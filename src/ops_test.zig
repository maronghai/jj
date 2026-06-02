const std = @import("std");
const ops = @import("ops.zig");

const Allocator = std.mem.Allocator;
const JsonValue = ops.JsonValue;

fn serialize(gpa: Allocator, val: JsonValue) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(gpa);
    defer aw.deinit();
    try val.writeTo(&aw.writer);
    return try gpa.dupe(u8, aw.written());
}

fn serializePretty(gpa: Allocator, val: JsonValue) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(gpa);
    defer aw.deinit();
    try val.writePretty(&aw.writer, 0);
    return try gpa.dupe(u8, aw.written());
}

test "parse null" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "null");
    defer val.deinit(gpa);
    try std.testing.expect(val == .null);
}

test "parse boolean true" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "true");
    defer val.deinit(gpa);
    try std.testing.expect(val == .boolean and val.boolean == true);
}

test "parse boolean false" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "false");
    defer val.deinit(gpa);
    try std.testing.expect(val == .boolean and val.boolean == false);
}

test "parse integer" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "42");
    defer val.deinit(gpa);
    try std.testing.expect(val == .integer and val.integer == 42);
}

test "parse negative integer" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "-7");
    defer val.deinit(gpa);
    try std.testing.expect(val == .integer and val.integer == -7);
}

test "parse float" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "3.14");
    defer val.deinit(gpa);
    try std.testing.expect(val == .number);
    try std.testing.expectApproxEqAbs(3.14, val.number, 1e-10);
}

test "parse scientific notation" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "1e3");
    defer val.deinit(gpa);
    try std.testing.expect(val == .number);
    try std.testing.expectApproxEqAbs(1000.0, val.number, 1e-10);
}

test "parse string" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "\"hello\"");
    defer val.deinit(gpa);
    try std.testing.expect(val == .string);
    try std.testing.expectEqualStrings("hello", val.string);
}

test "parse string with escapes" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "\"a\\nb\\tc\\\\d\\\"e\"");
    defer val.deinit(gpa);
    try std.testing.expect(val == .string);
    try std.testing.expectEqualStrings("a\nb\tc\\d\"e", val.string);
}

test "parse string with unicode escape" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "\"\\u0041\"");
    defer val.deinit(gpa);
    try std.testing.expect(val == .string);
    try std.testing.expectEqualStrings("A", val.string);
}

test "parse string with unicode escape 2-byte" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "\"\\u00E9\"");
    defer val.deinit(gpa);
    try std.testing.expect(val == .string);
    try std.testing.expectEqualStrings("é", val.string);
}

test "parse empty array" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "[]");
    defer val.deinit(gpa);
    try std.testing.expect(val == .array);
    try std.testing.expectEqual(@as(usize, 0), val.array.items.len);
}

test "parse array of numbers" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "[1, 2, 3]");
    defer val.deinit(gpa);
    try std.testing.expect(val == .array);
    try std.testing.expectEqual(@as(usize, 3), val.array.items.len);
    try std.testing.expect(val.array.items[0] == .integer and val.array.items[0].integer == 1);
    try std.testing.expect(val.array.items[1] == .integer and val.array.items[1].integer == 2);
    try std.testing.expect(val.array.items[2] == .integer and val.array.items[2].integer == 3);
}

test "parse empty object" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "{}");
    defer val.deinit(gpa);
    try std.testing.expect(val == .object);
    try std.testing.expectEqual(@as(usize, 0), val.object.count());
}

test "parse simple object" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "{\"a\":1,\"b\":\"hi\"}");
    defer val.deinit(gpa);
    try std.testing.expect(val == .object);
    try std.testing.expectEqual(@as(usize, 2), val.object.count());
    const a = val.object.get("a").?;
    try std.testing.expect(a == .integer and a.integer == 1);
    const b = val.object.get("b").?;
    try std.testing.expect(b == .string);
    try std.testing.expectEqualStrings("hi", b.string);
}

test "parse nested structure" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa,
        \\{"user":{"name":"alice","scores":[100,95]},"active":true}
    );
    defer val.deinit(gpa);
    try std.testing.expect(val == .object);
    const user = val.object.get("user").?;
    try std.testing.expect(user == .object);
    const name = user.object.get("name").?;
    try std.testing.expect(name == .string);
    try std.testing.expectEqualStrings("alice", name.string);
    const scores = user.object.get("scores").?;
    try std.testing.expect(scores == .array);
    try std.testing.expectEqual(@as(usize, 2), scores.array.items.len);
    const active = val.object.get("active").?;
    try std.testing.expect(active == .boolean and active.boolean == true);
}

test "parse with whitespace" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "  { \"x\" : 42 }  ");
    defer val.deinit(gpa);
    try std.testing.expect(val == .object);
    const x = val.object.get("x").?;
    try std.testing.expect(x == .integer and x.integer == 42);
}

test "parse error on invalid" {
    const gpa = std.testing.allocator;
    const result = ops.parse(gpa, "{invalid}");
    try std.testing.expectError(ops.ParseError.InvalidJson, result);
}

test "parse error on empty" {
    const gpa = std.testing.allocator;
    const result = ops.parse(gpa, "");
    try std.testing.expectError(ops.ParseError.InvalidJson, result);
}

test "writeTo compact" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "{\"a\":1,\"b\":[2,3]}");
    defer val.deinit(gpa);
    const out = try serialize(gpa, val);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("{\"a\":1,\"b\":[2,3]}", out);
}

test "writeTo string escaping" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "\"a\\nb\"");
    defer val.deinit(gpa);
    const out = try serialize(gpa, val);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("\"a\\nb\"", out);
}

test "writeTo null and bool" {
    const gpa = std.testing.allocator;
    {
        const out = try serialize(gpa, .null);
        defer gpa.free(out);
        try std.testing.expectEqualStrings("null", out);
    }
    {
        const out = try serialize(gpa, .{ .boolean = true });
        defer gpa.free(out);
        try std.testing.expectEqualStrings("true", out);
    }
    {
        const out = try serialize(gpa, .{ .boolean = false });
        defer gpa.free(out);
        try std.testing.expectEqualStrings("false", out);
    }
}

test "writeTo integer" {
    const gpa = std.testing.allocator;
    const out = try serialize(gpa, .{ .integer = 42 });
    defer gpa.free(out);
    try std.testing.expectEqualStrings("42", out);
}

test "writeTo number" {
    const gpa = std.testing.allocator;
    const out = try serialize(gpa, .{ .number = 3.14 });
    defer gpa.free(out);
    try std.testing.expectEqualStrings("3.14", out);
}

test "writePretty object" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "{\"a\":1,\"b\":2}");
    defer val.deinit(gpa);
    const out = try serializePretty(gpa, val);
    defer gpa.free(out);
    try std.testing.expectEqualStrings(
        \\{
        \\  "a": 1,
        \\  "b": 2
        \\}
    , out);
}

test "writePretty nested" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "{\"a\":{\"b\":1}}");
    defer val.deinit(gpa);
    const out = try serializePretty(gpa, val);
    defer gpa.free(out);
    try std.testing.expectEqualStrings(
        \\{
        \\  "a": {
        \\    "b": 1
        \\  }
        \\}
    , out);
}

test "writePretty empty array" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "[]");
    defer val.deinit(gpa);
    const out = try serializePretty(gpa, val);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("[]", out);
}

test "writePretty empty object" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "{}");
    defer val.deinit(gpa);
    const out = try serializePretty(gpa, val);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("{}", out);
}

test "clone primitive" {
    const gpa = std.testing.allocator;
    const original = JsonValue{ .integer = 99 };
    var cloned = try original.clone(gpa);
    defer cloned.deinit(gpa);
    try std.testing.expect(cloned == .integer and cloned.integer == 99);
}

test "clone string" {
    const gpa = std.testing.allocator;
    var original = try ops.parse(gpa, "\"hello\"");
    defer original.deinit(gpa);
    var cloned = try original.clone(gpa);
    defer cloned.deinit(gpa);
    try std.testing.expect(cloned == .string);
    try std.testing.expectEqualStrings("hello", cloned.string);
}

test "clone deep" {
    const gpa = std.testing.allocator;
    var original = try ops.parse(gpa, "{\"a\":[1,2]}");
    defer original.deinit(gpa);
    var cloned = try original.clone(gpa);
    defer cloned.deinit(gpa);
    const out = try serialize(gpa, cloned);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("{\"a\":[1,2]}", out);
}

test "getTypeName" {
    var v_null: JsonValue = .null;
    try std.testing.expectEqualStrings("null", v_null.getTypeName());
    var v_bool: JsonValue = .{ .boolean = true };
    try std.testing.expectEqualStrings("boolean", v_bool.getTypeName());
    var v_int: JsonValue = .{ .integer = 1 };
    try std.testing.expectEqualStrings("number", v_int.getTypeName());
    var v_num: JsonValue = .{ .number = 1.0 };
    try std.testing.expectEqualStrings("number", v_num.getTypeName());
    var v_str: JsonValue = .{ .string = "a" };
    try std.testing.expectEqualStrings("string", v_str.getTypeName());
    var v_arr: JsonValue = .{ .array = .empty };
    try std.testing.expectEqualStrings("array", v_arr.getTypeName());
    var v_obj: JsonValue = .{ .object = .empty };
    try std.testing.expectEqualStrings("object", v_obj.getTypeName());
}

test "parsePath simple key" {
    const gpa = std.testing.allocator;
    var segs = try ops.parsePath(gpa, "name");
    defer segs.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), segs.items.len);
    try std.testing.expect(segs.items[0] == .key);
    try std.testing.expectEqualStrings("name", segs.items[0].key);
}

test "parsePath dot notation" {
    const gpa = std.testing.allocator;
    var segs = try ops.parsePath(gpa, "user.name");
    defer segs.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 2), segs.items.len);
    try std.testing.expectEqualStrings("user", segs.items[0].key);
    try std.testing.expectEqualStrings("name", segs.items[1].key);
}

test "parsePath with index" {
    const gpa = std.testing.allocator;
    var segs = try ops.parsePath(gpa, "items.0.name");
    defer segs.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 3), segs.items.len);
    try std.testing.expectEqualStrings("items", segs.items[0].key);
    try std.testing.expect(segs.items[1] == .index and segs.items[1].index == 0);
    try std.testing.expectEqualStrings("name", segs.items[2].key);
}

test "parsePath last index dash" {
    const gpa = std.testing.allocator;
    var segs = try ops.parsePath(gpa, "items.-");
    defer segs.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 2), segs.items.len);
    try std.testing.expectEqualStrings("items", segs.items[0].key);
    try std.testing.expect(segs.items[1] == .index and segs.items[1].index == std.math.maxInt(usize));
}

test "parsePath empty" {
    const gpa = std.testing.allocator;
    var segs = try ops.parsePath(gpa, "");
    defer segs.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 0), segs.items.len);
}

test "get simple key" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1,\"b\":\"hi\"}");
    defer root.deinit(gpa);
    var a = try ops.get(root, "a", gpa);
    defer a.deinit(gpa);
    try std.testing.expect(a == .integer and a.integer == 1);
    var b = try ops.get(root, "b", gpa);
    defer b.deinit(gpa);
    try std.testing.expect(b == .string);
    try std.testing.expectEqualStrings("hi", b.string);
}

test "get nested path" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"user\":{\"name\":\"alice\"}}");
    defer root.deinit(gpa);
    var name = try ops.get(root, "user.name", gpa);
    defer name.deinit(gpa);
    try std.testing.expect(name == .string);
    try std.testing.expectEqualStrings("alice", name.string);
}

test "get array index" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[10,20,30]");
    defer root.deinit(gpa);
    var val = try ops.get(root, "1", gpa);
    defer val.deinit(gpa);
    try std.testing.expect(val == .integer and val.integer == 20);
}

test "get last index" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[10,20,30]");
    defer root.deinit(gpa);
    var val = try ops.get(root, "-", gpa);
    defer val.deinit(gpa);
    try std.testing.expect(val == .integer and val.integer == 30);
}

test "get nested array" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"items\":[{\"x\":1},{\"x\":2}]}");
    defer root.deinit(gpa);
    var val = try ops.get(root, "items.1.x", gpa);
    defer val.deinit(gpa);
    try std.testing.expect(val == .integer and val.integer == 2);
}

test "get path not found" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1}");
    defer root.deinit(gpa);
    const result = ops.get(root, "z", gpa);
    try std.testing.expectError(ops.OpError.PathNotFound, result);
}

test "get invalid type" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[1,2,3]");
    defer root.deinit(gpa);
    const result = ops.get(root, "x", gpa);
    try std.testing.expectError(ops.OpError.InvalidType, result);
}

test "set simple key" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{}");
    defer root.deinit(gpa);
    const alice = try gpa.dupe(u8, "alice");
    try ops.set(&root, "name", .{ .string = alice }, gpa);
    const out = try serialize(gpa, root);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("{\"name\":\"alice\"}", out);
}

test "set overwrite" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1}");
    defer root.deinit(gpa);
    try ops.set(&root, "a", .{ .integer = 99 }, gpa);
    const a = root.object.get("a").?;
    try std.testing.expect(a == .integer and a.integer == 99);
}

test "set nested auto-create" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{}");
    defer root.deinit(gpa);
    const alice = try gpa.dupe(u8, "alice");
    try ops.set(&root, "user.profile.name", .{ .string = alice }, gpa);
    var name = try ops.get(root, "user.profile.name", gpa);
    defer name.deinit(gpa);
    try std.testing.expect(name == .string);
    try std.testing.expectEqualStrings("alice", name.string);
}

test "set on null root" {
    const gpa = std.testing.allocator;
    var root: JsonValue = .null;
    defer root.deinit(gpa);
    try ops.set(&root, "a", .{ .integer = 1 }, gpa);
    try std.testing.expect(root == .object);
    const a = root.object.get("a").?;
    try std.testing.expect(a == .integer and a.integer == 1);
}

test "set array element" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[10,20,30]");
    defer root.deinit(gpa);
    try ops.set(&root, "1", .{ .integer = 99 }, gpa);
    try std.testing.expect(root.array.items[1] == .integer and root.array.items[1].integer == 99);
}

test "del key" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1,\"b\":2,\"c\":3}");
    defer root.deinit(gpa);
    try ops.del(&root, "b", gpa);
    try std.testing.expectEqual(@as(usize, 2), root.object.count());
    try std.testing.expect(root.object.get("b") == null);
}

test "del nested" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"user\":{\"name\":\"alice\",\"age\":30}}");
    defer root.deinit(gpa);
    try ops.del(&root, "user.age", gpa);
    const user = root.object.get("user").?;
    try std.testing.expect(user.object.get("age") == null);
    try std.testing.expect(user.object.get("name") != null);
}

test "del array element" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[1,2,3]");
    defer root.deinit(gpa);
    try ops.del(&root, "1", gpa);
    try std.testing.expectEqual(@as(usize, 2), root.array.items.len);
    try std.testing.expect(root.array.items[0] == .integer and root.array.items[0].integer == 1);
    try std.testing.expect(root.array.items[1] == .integer and root.array.items[1].integer == 3);
}

test "del last index" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[1,2,3]");
    defer root.deinit(gpa);
    try ops.del(&root, "-", gpa);
    try std.testing.expectEqual(@as(usize, 2), root.array.items.len);
    try std.testing.expect(root.array.items[1] == .integer and root.array.items[1].integer == 2);
}

test "del path not found" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1}");
    defer root.deinit(gpa);
    const result = ops.del(&root, "z", gpa);
    try std.testing.expectError(ops.OpError.PathNotFound, result);
}

test "push to array" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[1,2]");
    defer root.deinit(gpa);
    try ops.push(&root, "", .{ .integer = 3 }, gpa);
    try std.testing.expectEqual(@as(usize, 3), root.array.items.len);
    try std.testing.expect(root.array.items[2] == .integer and root.array.items[2].integer == 3);
}

test "push to nested array" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"items\":[1]}");
    defer root.deinit(gpa);
    try ops.push(&root, "items", .{ .integer = 2 }, gpa);
    const items = root.object.get("items").?;
    try std.testing.expectEqual(@as(usize, 2), items.array.items.len);
}

test "push auto-create array" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{}");
    defer root.deinit(gpa);
    const tag_a = try gpa.dupe(u8, "a");
    try ops.push(&root, "tags", .{ .string = tag_a }, gpa);
    const tags = root.object.get("tags").?;
    try std.testing.expect(tags == .array);
    try std.testing.expectEqual(@as(usize, 1), tags.array.items.len);
    try std.testing.expectEqualStrings("a", tags.array.items[0].string);
}

test "push to null root" {
    const gpa = std.testing.allocator;
    var root: JsonValue = .null;
    defer root.deinit(gpa);
    try ops.push(&root, "", .{ .integer = 1 }, gpa);
    try std.testing.expect(root == .array);
    try std.testing.expectEqual(@as(usize, 1), root.array.items.len);
}

test "push invalid type" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1}");
    defer root.deinit(gpa);
    const result = ops.push(&root, "a", .{ .integer = 2 }, gpa);
    try std.testing.expectError(ops.OpError.InvalidType, result);
}

test "pop from array" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[1,2,3]");
    defer root.deinit(gpa);
    var popped = try ops.pop(&root, "", gpa);
    defer popped.deinit(gpa);
    try std.testing.expect(popped == .integer and popped.integer == 3);
    try std.testing.expectEqual(@as(usize, 2), root.array.items.len);
}

test "pop from nested array" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"items\":[1,2]}");
    defer root.deinit(gpa);
    var popped = try ops.pop(&root, "items", gpa);
    defer popped.deinit(gpa);
    try std.testing.expect(popped == .integer and popped.integer == 2);
}

test "pop empty array" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[]");
    defer root.deinit(gpa);
    const result = ops.pop(&root, "", gpa);
    try std.testing.expectError(ops.OpError.PathNotFound, result);
}

test "pick keys" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1,\"b\":2,\"c\":3,\"d\":4}");
    defer root.deinit(gpa);
    const keys = [_][]const u8{ "a", "c" };
    try ops.pick(&root, &keys, gpa);
    try std.testing.expectEqual(@as(usize, 2), root.object.count());
    try std.testing.expect(root.object.get("a") != null);
    try std.testing.expect(root.object.get("c") != null);
    try std.testing.expect(root.object.get("b") == null);
    try std.testing.expect(root.object.get("d") == null);
}

test "pick non-existent key" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1,\"b\":2}");
    defer root.deinit(gpa);
    const keys = [_][]const u8{ "a", "z" };
    try ops.pick(&root, &keys, gpa);
    try std.testing.expectEqual(@as(usize, 1), root.object.count());
    try std.testing.expect(root.object.get("a") != null);
}

test "pick on non-object" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[1,2,3]");
    defer root.deinit(gpa);
    const keys = [_][]const u8{"a"};
    const result = ops.pick(&root, &keys, gpa);
    try std.testing.expectError(ops.OpError.InvalidType, result);
}

test "omit keys" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1,\"b\":2,\"c\":3}");
    defer root.deinit(gpa);
    const keys = [_][]const u8{ "b", "c" };
    try ops.omit(&root, &keys, gpa);
    try std.testing.expectEqual(@as(usize, 1), root.object.count());
    try std.testing.expect(root.object.get("a") != null);
    try std.testing.expect(root.object.get("b") == null);
}

test "omit non-existent key" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1,\"b\":2}");
    defer root.deinit(gpa);
    const keys = [_][]const u8{"z"};
    try ops.omit(&root, &keys, gpa);
    try std.testing.expectEqual(@as(usize, 2), root.object.count());
}

test "omit on non-object" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[1,2,3]");
    defer root.deinit(gpa);
    const keys = [_][]const u8{"a"};
    const result = ops.omit(&root, &keys, gpa);
    try std.testing.expectError(ops.OpError.InvalidType, result);
}

test "inferType bool" {
    const t = ops.inferType("true");
    try std.testing.expect(t == .boolean and t.boolean == true);
    const f = ops.inferType("false");
    try std.testing.expect(f == .boolean and f.boolean == false);
}

test "inferType null" {
    const n = ops.inferType("null");
    try std.testing.expect(n == .null);
}

test "inferType integer" {
    const i = ops.inferType("42");
    try std.testing.expect(i == .integer and i.integer == 42);
}

test "inferType negative integer" {
    const i = ops.inferType("-7");
    try std.testing.expect(i == .integer and i.integer == -7);
}

test "inferType float" {
    const f = ops.inferType("3.14");
    try std.testing.expect(f == .number);
    try std.testing.expectApproxEqAbs(3.14, f.number, 1e-10);
}

test "inferType string fallback" {
    const s = ops.inferType("hello");
    try std.testing.expect(s == .string);
    try std.testing.expectEqualStrings("hello", s.string);
}

test "roundtrip parse -> serialize" {
    const gpa = std.testing.allocator;
    const inputs = [_][]const u8{
        "null",
        "true",
        "false",
        "42",
        "-3",
        "3.14",
        "\"hello\"",
        "[]",
        "[1,2,3]",
        "{}",
        "{\"a\":1}",
        "{\"a\":[1,2],\"b\":{\"c\":3}}",
    };
    for (inputs) |input| {
        var val = try ops.parse(gpa, input);
        defer val.deinit(gpa);
        const out = try serialize(gpa, val);
        defer gpa.free(out);
        try std.testing.expectEqualStrings(input, out);
    }
}

test "parse object with duplicate key" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "{\"a\":1,\"a\":2}");
    defer val.deinit(gpa);
    const a = val.object.get("a").?;
    try std.testing.expect(a == .integer and a.integer == 2);
}

test "set then get roundtrip" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{}");
    defer root.deinit(gpa);
    try ops.set(&root, "x", .{ .integer = 42 }, gpa);
    const hi = try gpa.dupe(u8, "hi");
    try ops.set(&root, "y", .{ .string = hi }, gpa);
    var x = try ops.get(root, "x", gpa);
    defer x.deinit(gpa);
    try std.testing.expect(x == .integer and x.integer == 42);
    var y = try ops.get(root, "y", gpa);
    defer y.deinit(gpa);
    try std.testing.expect(y == .string);
    try std.testing.expectEqualStrings("hi", y.string);
}

test "set deep auto-create then del" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{}");
    defer root.deinit(gpa);
    try ops.set(&root, "a.b.c", .{ .integer = 1 }, gpa);
    var val = try ops.get(root, "a.b.c", gpa);
    defer val.deinit(gpa);
    try std.testing.expect(val == .integer and val.integer == 1);
    try ops.del(&root, "a.b.c", gpa);
    const result = ops.get(root, "a.b.c", gpa);
    try std.testing.expectError(ops.OpError.PathNotFound, result);
}

test "push multiple then pop all" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[]");
    defer root.deinit(gpa);
    try ops.push(&root, "", .{ .integer = 1 }, gpa);
    try ops.push(&root, "", .{ .integer = 2 }, gpa);
    try ops.push(&root, "", .{ .integer = 3 }, gpa);
    try std.testing.expectEqual(@as(usize, 3), root.array.items.len);
    var p3 = try ops.pop(&root, "", gpa);
    defer p3.deinit(gpa);
    try std.testing.expect(p3 == .integer and p3.integer == 3);
    var p2 = try ops.pop(&root, "", gpa);
    defer p2.deinit(gpa);
    try std.testing.expect(p2 == .integer and p2.integer == 2);
    var p1 = try ops.pop(&root, "", gpa);
    defer p1.deinit(gpa);
    try std.testing.expect(p1 == .integer and p1.integer == 1);
    try std.testing.expectEqual(@as(usize, 0), root.array.items.len);
}

test "pick then omit" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1,\"b\":2,\"c\":3,\"d\":4}");
    defer root.deinit(gpa);
    const pick_keys = [_][]const u8{ "a", "b", "c" };
    try ops.pick(&root, &pick_keys, gpa);
    try std.testing.expectEqual(@as(usize, 3), root.object.count());
    const omit_keys = [_][]const u8{"b"};
    try ops.omit(&root, &omit_keys, gpa);
    try std.testing.expectEqual(@as(usize, 2), root.object.count());
    try std.testing.expect(root.object.get("a") != null);
    try std.testing.expect(root.object.get("c") != null);
}

test "parse mixed array" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "[1,\"two\",true,null,[3],{\"x\":4}]");
    defer val.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 6), val.array.items.len);
    try std.testing.expect(val.array.items[0] == .integer);
    try std.testing.expect(val.array.items[1] == .string);
    try std.testing.expect(val.array.items[2] == .boolean);
    try std.testing.expect(val.array.items[3] == .null);
    try std.testing.expect(val.array.items[4] == .array);
    try std.testing.expect(val.array.items[5] == .object);
}

test "get root empty path" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1}");
    defer root.deinit(gpa);
    var val = try ops.get(root, "", gpa);
    defer val.deinit(gpa);
    try std.testing.expect(val == .object);
    try std.testing.expectEqual(@as(usize, 1), val.object.count());
}

test "writeTo number whole float" {
    const gpa = std.testing.allocator;
    const out = try serialize(gpa, .{ .number = 5.0 });
    defer gpa.free(out);
    try std.testing.expectEqualStrings("5", out);
}

test "set multiple pairs via ops" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{}");
    defer root.deinit(gpa);
    try ops.set(&root, "a", .{ .integer = 1 }, gpa);
    try ops.set(&root, "b", .{ .integer = 2 }, gpa);
    try ops.set(&root, "c", .{ .integer = 3 }, gpa);
    const out = try serialize(gpa, root);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("{\"a\":1,\"b\":2,\"c\":3}", out);
}

test "push multiple values via ops" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{}");
    defer root.deinit(gpa);
    try ops.push(&root, "items", .{ .integer = 1 }, gpa);
    try ops.push(&root, "items", .{ .integer = 2 }, gpa);
    try ops.push(&root, "items", .{ .integer = 3 }, gpa);
    const out = try serialize(gpa, root);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("{\"items\":[1,2,3]}", out);
}

test "push multiple strings via ops" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"tags\":[]}");
    defer root.deinit(gpa);
    const a = try gpa.dupe(u8, "a");
    const b = try gpa.dupe(u8, "b");
    const c = try gpa.dupe(u8, "c");
    try ops.push(&root, "tags", .{ .string = a }, gpa);
    try ops.push(&root, "tags", .{ .string = b }, gpa);
    try ops.push(&root, "tags", .{ .string = c }, gpa);
    const out = try serialize(gpa, root);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("{\"tags\":[\"a\",\"b\",\"c\"]}", out);
}

test "parse zero" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "0");
    defer val.deinit(gpa);
    try std.testing.expect(val == .integer and val.integer == 0);
}

test "parse negative float" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "-2.5");
    defer val.deinit(gpa);
    try std.testing.expect(val == .number);
    try std.testing.expectApproxEqAbs(-2.5, val.number, 1e-10);
}

test "parse string with forward slash escape" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "\"a\\/b\"");
    defer val.deinit(gpa);
    try std.testing.expect(val == .string);
    try std.testing.expectEqualStrings("a/b", val.string);
}

test "parse string with backspace and formfeed" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "\"\\b\\f\"");
    defer val.deinit(gpa);
    try std.testing.expect(val == .string);
    try std.testing.expectEqualStrings(&[_]u8{ 0x08, 0x0c }, val.string);
}

test "parse nested arrays" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "[[1,2],[3,4]]");
    defer val.deinit(gpa);
    try std.testing.expect(val == .array);
    try std.testing.expectEqual(@as(usize, 2), val.array.items.len);
    try std.testing.expect(val.array.items[0] == .array);
    try std.testing.expectEqual(@as(usize, 2), val.array.items[0].array.items.len);
    try std.testing.expect(val.array.items[0].array.items[0] == .integer and val.array.items[0].array.items[0].integer == 1);
}

test "parse object with trailing comma rejected" {
    const gpa = std.testing.allocator;
    const result = ops.parse(gpa, "{\"a\":1,}");
    try std.testing.expectError(ops.ParseError.InvalidJson, result);
}

test "parse array with trailing comma rejected" {
    const gpa = std.testing.allocator;
    const result = ops.parse(gpa, "[1,]");
    try std.testing.expectError(ops.ParseError.InvalidJson, result);
}

test "parse incomplete string" {
    const gpa = std.testing.allocator;
    const result = ops.parse(gpa, "\"hello");
    try std.testing.expectError(ops.ParseError.InvalidJson, result);
}

test "parse incomplete escape" {
    const gpa = std.testing.allocator;
    const result = ops.parse(gpa, "\"\\u00\"");
    try std.testing.expectError(ops.ParseError.InvalidJson, result);
}

test "writeTo nested array" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "[[1,2],[3]]");
    defer val.deinit(gpa);
    const out = try serialize(gpa, val);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("[[1,2],[3]]", out);
}

test "writeTo control character" {
    const gpa = std.testing.allocator;
    const s = try gpa.dupe(u8, &[_]u8{0x01});
    var val: JsonValue = .{ .string = s };
    const out = try serialize(gpa, val);
    defer {
        gpa.free(out);
        val.deinit(gpa);
    }
    try std.testing.expectEqualStrings("\"\\u0001\"", out);
}

test "writeTo nan" {
    const gpa = std.testing.allocator;
    const out = try serialize(gpa, .{ .number = std.math.nan(f64) });
    defer gpa.free(out);
    try std.testing.expectEqualStrings("null", out);
}

test "writeTo infinity" {
    const gpa = std.testing.allocator;
    const out = try serialize(gpa, .{ .number = std.math.inf(f64) });
    defer gpa.free(out);
    try std.testing.expectEqualStrings("null", out);
}

test "writePretty array" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "[1,2,3]");
    defer val.deinit(gpa);
    const out = try serializePretty(gpa, val);
    defer gpa.free(out);
    try std.testing.expectEqualStrings(
        \\[
        \\  1,
        \\  2,
        \\  3
        \\]
    , out);
}

test "writePretty nested array in object" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "{\"x\":[1,2]}");
    defer val.deinit(gpa);
    const out = try serializePretty(gpa, val);
    defer gpa.free(out);
    try std.testing.expectEqualStrings(
        \\{
        \\  "x": [
        \\    1,
        \\    2
        \\  ]
        \\}
    , out);
}

test "clone null and bool" {
    const gpa = std.testing.allocator;
    var v_null: JsonValue = .null;
    var c_null = try v_null.clone(gpa);
    defer c_null.deinit(gpa);
    try std.testing.expect(c_null == .null);
    var v_bool: JsonValue = .{ .boolean = false };
    var c_bool = try v_bool.clone(gpa);
    defer c_bool.deinit(gpa);
    try std.testing.expect(c_bool == .boolean and c_bool.boolean == false);
}

test "clone number" {
    const gpa = std.testing.allocator;
    var v: JsonValue = .{ .number = 2.5 };
    var c = try v.clone(gpa);
    defer c.deinit(gpa);
    try std.testing.expect(c == .number);
    try std.testing.expectApproxEqAbs(2.5, c.number, 1e-10);
}

test "parsePath numeric index" {
    const gpa = std.testing.allocator;
    var segs = try ops.parsePath(gpa, "0");
    defer segs.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), segs.items.len);
    try std.testing.expect(segs.items[0] == .index and segs.items[0].index == 0);
}

test "parsePath multi level" {
    const gpa = std.testing.allocator;
    var segs = try ops.parsePath(gpa, "a.b.0.c.-");
    defer segs.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 5), segs.items.len);
    try std.testing.expectEqualStrings("a", segs.items[0].key);
    try std.testing.expectEqualStrings("b", segs.items[1].key);
    try std.testing.expect(segs.items[2] == .index and segs.items[2].index == 0);
    try std.testing.expectEqualStrings("c", segs.items[3].key);
    try std.testing.expect(segs.items[4] == .index and segs.items[4].index == std.math.maxInt(usize));
}

test "parsePath invalid numeric" {
    const gpa = std.testing.allocator;
    const result = ops.parsePath(gpa, "0abc");
    try std.testing.expectError(error.InvalidPath, result);
}

test "get from object key" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"x\":{\"y\":42}}");
    defer root.deinit(gpa);
    var val = try ops.get(root, "x.y", gpa);
    defer val.deinit(gpa);
    try std.testing.expect(val == .integer and val.integer == 42);
}

test "get array via dash" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"items\":[10,20,30]}");
    defer root.deinit(gpa);
    var val = try ops.get(root, "items.-", gpa);
    defer val.deinit(gpa);
    try std.testing.expect(val == .integer and val.integer == 30);
}

test "get returns clone" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":[1,2]}");
    defer root.deinit(gpa);
    var val = try ops.get(root, "a", gpa);
    defer val.deinit(gpa);
    try ops.push(&val, "", .{ .integer = 3 }, gpa);
    try std.testing.expectEqual(@as(usize, 3), val.array.items.len);
    try std.testing.expectEqual(@as(usize, 2), root.object.get("a").?.array.items.len);
}

test "set overwrite with different type" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1}");
    defer root.deinit(gpa);
    const hi = try gpa.dupe(u8, "hi");
    try ops.set(&root, "a", .{ .string = hi }, gpa);
    const a = root.object.get("a").?;
    try std.testing.expect(a == .string);
    try std.testing.expectEqualStrings("hi", a.string);
}

test "set deeply nested auto-create" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{}");
    defer root.deinit(gpa);
    try ops.set(&root, "a.b.c.d", .{ .integer = 99 }, gpa);
    var val = try ops.get(root, "a.b.c.d", gpa);
    defer val.deinit(gpa);
    try std.testing.expect(val == .integer and val.integer == 99);
}

test "set on null creates object then sets" {
    const gpa = std.testing.allocator;
    var root: JsonValue = .null;
    defer root.deinit(gpa);
    try ops.set(&root, "x.y", .{ .integer = 7 }, gpa);
    const out = try serialize(gpa, root);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("{\"x\":{\"y\":7}}", out);
}

test "set array index out of bounds" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[1,2]");
    defer root.deinit(gpa);
    const result = ops.set(&root, "5", .{ .integer = 9 }, gpa);
    try std.testing.expectError(ops.OpError.PathNotFound, result);
}

test "set on non-object non-null" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "\"hello\"");
    defer root.deinit(gpa);
    const result = ops.set(&root, "a", .{ .integer = 1 }, gpa);
    try std.testing.expectError(ops.OpError.InvalidType, result);
}

test "set empty path replaces root" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1}");
    defer root.deinit(gpa);
    try ops.set(&root, "", .{ .integer = 42 }, gpa);
    try std.testing.expect(root == .integer and root.integer == 42);
}

test "del only key leaves empty object" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1}");
    defer root.deinit(gpa);
    try ops.del(&root, "a", gpa);
    try std.testing.expectEqual(@as(usize, 0), root.object.count());
}

test "del empty path is no-op" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1}");
    defer root.deinit(gpa);
    try ops.del(&root, "", gpa);
    try std.testing.expectEqual(@as(usize, 1), root.object.count());
}

test "del on non-object" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[1,2,3]");
    defer root.deinit(gpa);
    const result = ops.del(&root, "x", gpa);
    try std.testing.expectError(ops.OpError.InvalidType, result);
}

test "del nested array element" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"items\":[1,2,3]}");
    defer root.deinit(gpa);
    try ops.del(&root, "items.1", gpa);
    const out = try serialize(gpa, root);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("{\"items\":[1,3]}", out);
}

test "push to existing nested array via index" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"matrix\":[[],[]]}");
    defer root.deinit(gpa);
    try ops.push(&root, "matrix.0", .{ .integer = 1 }, gpa);
    try ops.push(&root, "matrix.1", .{ .integer = 2 }, gpa);
    const out = try serialize(gpa, root);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("{\"matrix\":[[1],[2]]}", out);
}

test "push null to array" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[]");
    defer root.deinit(gpa);
    try ops.push(&root, "", .null, gpa);
    const out = try serialize(gpa, root);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("[null]", out);
}

test "push to null auto-creates array" {
    const gpa = std.testing.allocator;
    var root: JsonValue = .null;
    defer root.deinit(gpa);
    try ops.push(&root, "", .{ .integer = 1 }, gpa);
    const out = try serialize(gpa, root);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("[1]", out);
}

test "push on non-array non-object non-null" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "\"hello\"");
    defer root.deinit(gpa);
    const result = ops.push(&root, "", .{ .integer = 1 }, gpa);
    try std.testing.expectError(ops.OpError.InvalidType, result);
}

test "pop returns correct value" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[\"a\",\"b\",\"c\"]");
    defer root.deinit(gpa);
    var c = try ops.pop(&root, "", gpa);
    defer c.deinit(gpa);
    try std.testing.expect(c == .string);
    try std.testing.expectEqualStrings("c", c.string);
    var b = try ops.pop(&root, "", gpa);
    defer b.deinit(gpa);
    try std.testing.expect(b == .string);
    try std.testing.expectEqualStrings("b", b.string);
}

test "pop on non-array" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1}");
    defer root.deinit(gpa);
    const result = ops.pop(&root, "a", gpa);
    try std.testing.expectError(ops.OpError.InvalidType, result);
}

test "pop path not found" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"items\":[1]}");
    defer root.deinit(gpa);
    const result = ops.pop(&root, "nope", gpa);
    try std.testing.expectError(ops.OpError.PathNotFound, result);
}

test "pick preserves order and values" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1,\"b\":2,\"c\":3}");
    defer root.deinit(gpa);
    const keys = [_][]const u8{ "c", "a" };
    try ops.pick(&root, &keys, gpa);
    try std.testing.expectEqual(@as(usize, 2), root.object.count());
    try std.testing.expect(root.object.get("a") != null);
    try std.testing.expect(root.object.get("c") != null);
    try std.testing.expect(root.object.get("b") == null);
}

test "pick all keys" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1,\"b\":2}");
    defer root.deinit(gpa);
    const keys = [_][]const u8{ "a", "b" };
    try ops.pick(&root, &keys, gpa);
    try std.testing.expectEqual(@as(usize, 2), root.object.count());
}

test "omit all keys" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1,\"b\":2}");
    defer root.deinit(gpa);
    const keys = [_][]const u8{ "a", "b" };
    try ops.omit(&root, &keys, gpa);
    try std.testing.expectEqual(@as(usize, 0), root.object.count());
}

test "omit single key" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1,\"b\":2,\"c\":3}");
    defer root.deinit(gpa);
    const keys = [_][]const u8{"b"};
    try ops.omit(&root, &keys, gpa);
    try std.testing.expect(root.object.get("a") != null);
    try std.testing.expect(root.object.get("c") != null);
    try std.testing.expect(root.object.get("b") == null);
}

test "inferType bool case insensitive is not supported" {
    const t = ops.inferType("True");
    try std.testing.expect(t == .string);
}

test "inferType empty string" {
    const s = ops.inferType("");
    try std.testing.expect(s == .string);
    try std.testing.expectEqualStrings("", s.string);
}

test "inferType zero integer" {
    const i = ops.inferType("0");
    try std.testing.expect(i == .integer and i.integer == 0);
}

test "inferType float with exponent" {
    const f = ops.inferType("1.5e2");
    try std.testing.expect(f == .number);
    try std.testing.expectApproxEqAbs(150.0, f.number, 1e-10);
}

test "roundtrip complex nested" {
    const gpa = std.testing.allocator;
    const input = "{\"users\":[{\"name\":\"alice\",\"scores\":[100,95]},{\"name\":\"bob\",\"scores\":[80]}],\"active\":true,\"count\":2}";
    var val = try ops.parse(gpa, input);
    defer val.deinit(gpa);
    const out = try serialize(gpa, val);
    defer gpa.free(out);
    try std.testing.expectEqualStrings(input, out);
}

test "roundtrip pretty then parse" {
    const gpa = std.testing.allocator;
    var val = try ops.parse(gpa, "{\"a\":1,\"b\":[2,3]}");
    defer val.deinit(gpa);
    const pretty = try serializePretty(gpa, val);
    defer gpa.free(pretty);
    var val2 = try ops.parse(gpa, pretty);
    defer val2.deinit(gpa);
    const compact = try serialize(gpa, val2);
    defer gpa.free(compact);
    try std.testing.expectEqualStrings("{\"a\":1,\"b\":[2,3]}", compact);
}

test "set then del leaves clean object" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{}");
    defer root.deinit(gpa);
    try ops.set(&root, "x", .{ .integer = 1 }, gpa);
    try ops.set(&root, "y", .{ .integer = 2 }, gpa);
    try ops.del(&root, "x", gpa);
    const out = try serialize(gpa, root);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("{\"y\":2}", out);
}

test "push then pop preserves original" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[1,2]");
    defer root.deinit(gpa);
    try ops.push(&root, "", .{ .integer = 3 }, gpa);
    var popped = try ops.pop(&root, "", gpa);
    defer popped.deinit(gpa);
    const out = try serialize(gpa, root);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("[1,2]", out);
}

test "pick then serialize" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1,\"b\":2,\"c\":3}");
    defer root.deinit(gpa);
    const keys = [_][]const u8{ "a", "c" };
    try ops.pick(&root, &keys, gpa);
    const out = try serialize(gpa, root);
    defer gpa.free(out);
    try std.testing.expect(out.len > 0);
    try std.testing.expect(root.object.get("a") != null);
    try std.testing.expect(root.object.get("c") != null);
}

test "clone array with mixed types" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[1,\"two\",true,null,[3],{\"x\":4}]");
    defer root.deinit(gpa);
    var cloned = try root.clone(gpa);
    defer cloned.deinit(gpa);
    const out = try serialize(gpa, cloned);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("[1,\"two\",true,null,[3],{\"x\":4}]", out);
}

test "get type of nested values" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":{\"b\":1},\"c\":[1,2],\"d\":\"hi\",\"e\":true,\"f\":null}");
    defer root.deinit(gpa);
    var a = try ops.get(root, "a", gpa);
    defer a.deinit(gpa);
    try std.testing.expectEqualStrings("object", a.getTypeName());
    var b = try ops.get(root, "a.b", gpa);
    defer b.deinit(gpa);
    try std.testing.expectEqualStrings("number", b.getTypeName());
    var c = try ops.get(root, "c", gpa);
    defer c.deinit(gpa);
    try std.testing.expectEqualStrings("array", c.getTypeName());
    var d = try ops.get(root, "d", gpa);
    defer d.deinit(gpa);
    try std.testing.expectEqualStrings("string", d.getTypeName());
    var e = try ops.get(root, "e", gpa);
    defer e.deinit(gpa);
    try std.testing.expectEqualStrings("boolean", e.getTypeName());
    var f = try ops.get(root, "f", gpa);
    defer f.deinit(gpa);
    try std.testing.expectEqualStrings("null", f.getTypeName());
}

test "set array via dash index" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[10,20,30]");
    defer root.deinit(gpa);
    try ops.set(&root, "-", .{ .integer = 99 }, gpa);
    try std.testing.expect(root.array.items[2] == .integer and root.array.items[2].integer == 99);
}

test "set nested via array index" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[{\"x\":1},{\"x\":2}]");
    defer root.deinit(gpa);
    try ops.set(&root, "0.x", .{ .integer = 99 }, gpa);
    try std.testing.expect(root.array.items[0].object.get("x").?.integer == 99);
}

test "keys basic object" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1,\"b\":2,\"c\":3}");
    defer root.deinit(gpa);
    var owned = try ops.keys(root, "", gpa);
    defer {
        for (owned.items) |k| gpa.free(k);
        owned.deinit(gpa);
    }
    try std.testing.expectEqual(@as(usize, 3), owned.items.len);
    // Order is preserved (insertion-ordered map)
    try std.testing.expectEqualStrings("a", owned.items[0]);
    try std.testing.expectEqualStrings("b", owned.items[1]);
    try std.testing.expectEqualStrings("c", owned.items[2]);
}

test "keys nested object" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"outer\":{\"x\":1,\"y\":2}}");
    defer root.deinit(gpa);
    var owned = try ops.keys(root, "outer", gpa);
    defer {
        for (owned.items) |k| gpa.free(k);
        owned.deinit(gpa);
    }
    try std.testing.expectEqual(@as(usize, 2), owned.items.len);
}

test "keys path not found" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1}");
    defer root.deinit(gpa);
    const result = ops.keys(root, "missing", gpa);
    try std.testing.expectError(ops.OpError.PathNotFound, result);
}

test "keys on non-object returns InvalidType" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[1,2,3]");
    defer root.deinit(gpa);
    const result = ops.keys(root, "", gpa);
    try std.testing.expectError(ops.OpError.InvalidType, result);
}

test "has returns true for existing key" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1,\"b\":2}");
    defer root.deinit(gpa);
    try std.testing.expect(ops.has(root, "a", gpa));
    try std.testing.expect(ops.has(root, "b", gpa));
    try std.testing.expect(ops.has(root, "", gpa));
}

test "has returns false for missing key" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1}");
    defer root.deinit(gpa);
    try std.testing.expect(!ops.has(root, "missing", gpa));
    try std.testing.expect(!ops.has(root, "a.b", gpa));
}

test "has on array index in bounds" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[10,20,30]");
    defer root.deinit(gpa);
    try std.testing.expect(ops.has(root, "0", gpa));
    try std.testing.expect(ops.has(root, "2", gpa));
    try std.testing.expect(!ops.has(root, "5", gpa));
}

test "has on invalid path returns false" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1}");
    defer root.deinit(gpa);
    try std.testing.expect(!ops.has(root, "a..b", gpa));
}

test "length of array" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "[1,2,3,4,5]");
    defer root.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 5), try ops.length(root, "", gpa));
}

test "length of object" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1,\"b\":2,\"c\":3}");
    defer root.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 3), try ops.length(root, "", gpa));
}

test "length of string" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"s\":\"hello\"}");
    defer root.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 5), try ops.length(root, "s", gpa));
}

test "length of nested array" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"items\":[1,2,3]}");
    defer root.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 3), try ops.length(root, "items", gpa));
}

test "length path not found" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"a\":1}");
    defer root.deinit(gpa);
    try std.testing.expectError(ops.OpError.PathNotFound, ops.length(root, "missing", gpa));
}

test "length on number returns InvalidType" {
    const gpa = std.testing.allocator;
    var root = try ops.parse(gpa, "{\"n\":42}");
    defer root.deinit(gpa);
    try std.testing.expectError(ops.OpError.InvalidType, ops.length(root, "n", gpa));
}
