# bespoke-skills

自研 skills：契合个人开发流程的调用方 skill。与 playbook 各阶段的阶段 skill（待建）相互独立，不绑定开发阶段，按需直接调用。

## 收录标准

- **自研原创**：为本仓库工作流量身写的，非外来搜集件（外来件进 awesome-skills/）。
- **实测定稿**：主流程经过真实环境完整跑通，关键结论带实测日期；排错条目须为实际踩过的坑，不许臆写。
- **自包含**：不往业务仓库写任何临时文件；随附资产（脚本/依赖清单等）都在 skill 目录内。
- **脚本配套**：含 scripts/ 时必须写明参数、宿主依赖、退出码，并在 SKILL.md 侧声明。
- **命名合规**：目录名 == frontmatter `name`，kebab-case（见 [standards/naming-standard.md](../standards/naming-standard.md)）。

## 登记方式

每个 skill 一个子目录，并在下表登记：

| 字段 | 说明 |
|------|------|
| 收录日期 | YYYY-MM-DD |
| 面向产品/环境 | 适用产品与实测环境 |
| 实测状态 | 主流程最近一次完整验证的日期与结果 |

## 当前收录

| skill | 用途 | 收录日期 | 面向环境 | 实测状态 |
|-------|------|---------|---------|---------|
| [fnisg-web-local-debug](fnisg-web-local-debug/) | 本地 docker 起 FNISG 前后端，经 SSH 隧道联调真实网闸设备 | 2026-10-27 | FINGAPS 网闸 235/236 实验网 | 2026-10-26 全链路走通（容器→隧道→flask→dev→真机 MQTT） |
