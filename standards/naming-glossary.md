# 命名术语表

## 变更记录

| 日期 | 版本 | 修改人 | 说明 |
|------|------|--------|------|
| 2026-10-21 | 1.0 | Nick | 初稿定稿：经 7 轮多代理审核，65 条修复项全部闭环 |

适用：所有公共字段、业务概念命名与枚举取值必须先查本表（见 naming-standard.md NAME-01）；未收录的概念先在本表登记标准名，再写代码。
优先级：本表为硬约束，标准名一经登记即全工程统一使用，调用方不得绕过本表另造同义名。
维护：一行一个概念，各列填全；"禁用同义词"列供评审与全文检索用；标准名与枚举值一律全小写英文，中文词仅用于日志文案与界面显示，不作接口取值。

## 1. 字段与概念命名

| 概念 | 标准名 | 类型/单位 | 禁用同义词 |
|------|--------|----------|-----------|
| 策略唯一标识 | `policy_id` | string/uint32（以工程实际统一其一） | rule_id、policy_no、id |
| 启用开关 | `is_enabled` | bool | enabled、enable、open、switch |
| 超时时长 | `timeout_ms` | uint32/ms | timeout、timeout_sec、time_out |
| 设备运行状态 | `device_status` | string（取值见第 2 节 running/stopped） | deviceState、state、status |
| 权限持有 | `has_permission` | bool | has_perm、permission |
| 连接计数 | `conn_count` | uint32/条 | connections、conn_num |
| 吞吐率 | `throughput_mbps` | float/Mbps | throughput |
| 对象唯一标识 | `object_id` | string/uint32（以工程实际统一其一） | obj_id、id、objectID |
| 操作对象类型 | `object_type` | string（如 policy/address/service/time） | obj_type、target_type、obj_class |
| 管理操作类型 | `operation_type` | 枚举（取值见第 2 节） | operation、action、op_type |
| 策略名称 | `policy_name` | string（长度约束见 field-constraint.md 参数表） | name、policyName、policy_title |
| 对象名称 | `object_name` | string（长度约束见 field-constraint.md 参数表） | obj_name、name |
| 用户名 | `username` | string（约束见 field-constraint.md 参数表） | user_name、login_name、account |
| 操作用户 | `operator` | string（用户名） | user、admin_name、operator_name |
| 操作结果 | `operation_result` | 枚举（取值见第 2 节 success/failure） | result、status、outcome |
| 操作来源 | `source_ip` | string（IPv4/IPv6 或 console） | origin_ip、client_ip、source |
| 请求标识 | `request_id` | string（工程生成的请求唯一标识） | trace_id、flow_id、seq_id |
| 匹配动作 | `match_action` | 枚举（取值见第 2 节 allow/deny/drop） | action、act、handle_action |
| 源地址 | `src_ip` | string（IPv4/IPv6，报文字段） | sourceAddress、s_addr（source_ip 已登记为「操作来源」标准名，仅报文类字段不得使用，见操作来源行） |
| 目的地址 | `dst_ip` | string（IPv4/IPv6，报文字段） | dest_ip、destination_ip、d_addr |
| 协议 | `protocol` | string（如 tcp/udp/icmp） | proto |
| 端口 | `port` | uint16 | port_num、port_id |
| ICMP 类型 | `icmp_type` | uint8 | type |
| ICMP 代码 | `icmp_code` | uint8 | code |
| 设备启停动作 | `start_stop_action` | 枚举（取值见第 2 节 start/stop） | power_action、switch_action、run_action |

## 2. 枚举值统一

同一语义全工程只用一套词；"状态"与"动作"分开登记。bool 类型字段取值即 `true`/`false`，无需登记；本节只登记字符串枚举。开关语义优先用 bool 字段（`is_enabled` = true/false），仅当需要多状态或协议约束时才用字符串枚举。

| 语义 | 适用字段 | 标准取值 | 禁用取值 |
|------|---------|---------|---------|
| 启用/禁用（配置项是否生效） | 启用类字符串枚举字段 | `enabled` / `disabled` | on、off、open、close、1、0 |
| 运行/停止（进程、服务的实际状态） | `*_status` 类字段 | `running` / `stopped` | start、stop、active、normal、正常、停止 |
| 启动/停止（设备启停的下发动作） | 设备启停控制字段（`start_stop_action` 类） | `start` / `stop` | run、halt、begin、open、close |
| 管理操作（增删改查/登录登出/导入导出/下发，用于操作日志与审计） | `operation_type` | `create` / `update` / `delete` / `query` / `login` / `logout` / `import` / `export` / `deploy` | add、edit、del、remove、search、sign_in、sign_out、download、upload、push |
| 成功/失败（管理操作结果） | `operation_result` | `success` / `failure` | ok、fail、succeed、error、成功、失败 |
| 放行/拒绝/丢弃（策略匹配执行动作） | `match_action` | `allow` / `deny` / `drop`（如有「拒绝并回包」动作，先在此登记 `reject` 再使用） | permit、forbid、accept、block |

未采用 `on`/`off`：如后续确有物理开关量（如继电器输出）等场景需要，先在此登记一行将其合法化，再使用。

## 完成前自检

- [ ] 新概念已先在本表登记标准名再使用（naming-standard.md NAME-01）
- [ ] 新增行各列填全，标准名与枚举值均为全小写英文
- [ ] 禁用同义词/禁用取值已同步登记，且不与本行标准名/标准取值重叠
- [ ] 中文词仅用于界面显示与日志文案，未作接口取值
