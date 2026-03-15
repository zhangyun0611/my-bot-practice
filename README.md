# Task Manager — 机器人闭环练手项目

一个故意留了一些问题的简单任务管理工具，用来给三个 AI 机器人练手。

## 用法

```bash
# 添加任务
node src/app.js add "学习AI" high

# 列出任务
node src/app.js list

# 完成任务
node src/app.js done 1

# 删除任务
node src/app.js delete 1

# 搜索任务
node src/app.js search "学习"
```

## 机器人维护

这个项目由三个 AI 机器人自动维护：

- **审核机器人** — 每12小时扫描代码，发现问题提 Issue
- **修复机器人** — 读取 Issue，自动修复代码，提 PR
- **审查机器人** — 审查 PR，通过就合并，不通过就打回

脚本在 `_bots/` 目录下。
