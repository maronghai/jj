基于刚才重构 `load_tools()` 的实际痛点，按优先级：

## P0 — 解决当前阻塞
1. **`keys <path>`** — 列举对象 key。当前最痛点，让我被迫用 bash 正则切 JSON
2. **`has <path>` / `exists <path>`** — 检查路径是否存在（不带 stderr 错误），失败时返回 `false` 而非 exit 非零
3. **`length <path>` / `count <path>`** — 数组长度 / 对象 key 数量

## P1 — 日常用得上
4. **`values <path>`** — 对象 value 数组
5. **`contains <path> <value>`** — 数组/字符串包含检查
6. **`merge` 支持 stdin** — 当前只接受 `<file>`，无法 `echo … | jj merge`
7. **`first` / `last` / `nth <n>`** — 数组端点访问，省去 `jj get 0` 这种数字索引

## P2 — 数据变换
8. **`map <path> <expr>` / `filter <path> <expr>`** — 数组投影/筛选
9. **`flatten`** — 嵌套对象拍平
10. **`sort` / `uniq`** — 数组排序去重
11. **`slice <path> <start> [end]`** — 数组切片
12. **`str` / `num` / `bool`** — 显式类型转换（类似 `:=` 自动推断的反向操作）

## P3 — 锦上添花
13. **`patch` 风格的就地编辑**（RFC 6902 子集）
14. **`validate <schema.json>`** — JSON Schema 校验
15. **`--null-on-error`** — 全局开关，路径不存在时返回 `null` 而非报错
16. **`--indent N`** 给 `pretty`

---

**最关键的是 P0 三件套**：`keys` + `has` + `length`。加上它们，`load_tools()` 可以再砍掉 ~30 行，**完全**用 `jj` 拼装 OpenAI `tools` 数组，不再碰 bash 字符串切割。

需要我做下面哪件吗？
- **A. 起一个 `jj-plus` 包装脚本**（bash 拼 `jj`，缺命令时用 jq/awk/python 补）——今天就能用
- **B. 给 tidwall/jj 提 issue / draft PR**——长期方案
- **C. 写一份 `docs/jj-cookbook.md`**——把当前能用 `jj` 干的事系统化，给后面写工具的人参考