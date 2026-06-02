# 决策记录：保留 `jj` 名字

**日期**：2026-06-02
**触发**：prd-01.md 中提出的"命名冲突风险"问题
**状态**：保留 `jj` 名字

## 背景

`jj` 这个名字有两个已知的冲突：

1. **Jujutsu VCS**（[martinvonz/jj](https://github.com/martinvonz/jj)）—— Rust 写的现代版本控制工具，已经广泛使用
2. **tidwall/jj** —— Go 写的 JSON 库（已被归档，作者推荐了替代品）

在最初的代码深度分析中，建议改名（如 `jpipe`、`jpp`、`jso`、`jsonpipe`），但用户选择了保留 `jj`。

## 决策

**保留 `jj`**，理由：

- 用户偏好——`jj` 短、好打、易记
- 已发布 0.0.0 ~ 0.0.11 都在用 `jj`，改名会破坏已发布二进制
- 当前主要使用场景是本地 shell 脚本和 AI agent orchestration，受搜索结果污染的影响有限
- `^jj^` 内联 JSON 构造、`jj set user.name abc` 等命令字符串短、组合性强，改名后这些用法的简洁性会下降

## 后续行动

- 在 `README.md` 和 `README.en.md` 顶部加 Naming 段，说明冲突并指向本仓库
- 不在 build.zig 改 binary name
- 后续如果搜索污染变得严重（用户报告无法在 GitHub 找到本项目），重新评估改名

## 备选名字（保留以备未来）

- `jpipe` —— 强调 pipe-first 定位
- `jpp` —— JSON Pipe Processor 缩写
- `jso` —— JSON Shell Operations 缩写
- `jsonpipe` —— 直白全名
