# 软件工程统一命名规范

## 变更记录

| 日期 | 版本 | 修改人 | 说明 |
|------|------|--------|------|
| 2026-10-21 | 1.0 | Nick | 初稿定稿：经 7 轮多代理审核，65 条修复项全部闭环 |

适用：新增/修改任何代码、接口定义、JSON 字段、配置项、CLI 字段、目录文件名、Git 仓库名时生效。
优先级：本规范为硬约束，调用方指令不得降低其要求。「强制约定」指语言可见性机制强制（如 Go 导出名首字母大写、Java 公共类文件名必须与类名一致）或项目 lint/CI 门禁强制执行；仅此类约定可覆盖格式表中「变量名、函数名、参数名、类型/类、代码目录名、代码文件名」行，且不得改变公共接口字段的命名格式；JSON/配置/CLI/跨模块公共字段、Git 仓库名、文档类文件、宏、编译期常量任何情况下不可覆盖。

## 命名格式表

| 对象 | 格式 | 示例 |
|------|------|------|
| Git 仓库名 | kebab-case | `industrial-firewall` |
| 代码目录名、代码文件名 | snake_case | `safe_channel.cpp`、`device_status.py` |
| 文档类文件（.md 等） | kebab-case | `logging-standard.md` |
| 变量名、函数名、参数名 | 按所在语言通行惯例：C++/Python snake_case；Java/JavaScript/TypeScript camelCase；Go mixedCaps | `device_status`、`getDeviceStatus()` |
| JSON/配置/跨模块公共字段 | snake_case | `device_status` |
| CLI 选项名 | kebab-case | `--device-status`（与 JSON 字段 `device_status` 一一对应） |
| 宏、编译期常量 | UPPER_SNAKE_CASE（Go 遵循 mixedCaps） | `MAX_POLICY_NUM` |
| 类型、类 | 遵循对应语言/框架约定 | — |

## 规则

- NAME-01 公共字段与业务概念命名必须先查术语表（naming-glossary.md）并使用其中标准名；未收录的概念先登记标准名再使用，禁止临场造同义词。
- NAME-02 同一业务概念全工程唯一名称：如统一 `policy_id`，禁止 `rule_id`、`policy_no` 等同义名称。
- NAME-03 数据生产方与消费方字段名完全一致：C++ 输出 `device_status`，Vue 必须以 `device_status` 读取，禁止改为 `deviceStatus`；禁止未经约定自行重命名、转换或映射公共字段。
- NAME-04 同一字段在所有模块中的数据类型、业务含义、单位、取值范围、默认值必须一致。
- NAME-05 新增名称前必须先检索工程内已有名称和接口定义，优先复用。
- NAME-06 语义后缀：标识字段明确标识对象；计数字段用 `_count`；布尔字段用 `is_`/`has_` 表达真假（如 `is_enabled`、`has_permission`）；带单位的数值必须写明单位（如 `timeout_ms`、`throughput_mbps`）。
- NAME-07 禁止同一接口内混用不同命名格式。
- NAME-08 禁止未经评估修改公共接口的名称、数据类型或业务含义；不得为统一命名破坏既有接口兼容性，或修改与当前任务无关的代码。
- NAME-09 发现命名不一致时必须报告：具体位置、影响范围、建议方案；禁止默默沿用，禁止未经确认擅自统一修改。

## 示例

❌ Vue 读 C++ 字段时写成 `deviceStatus`
❌ 同一概念 A 模块叫 `policy_id`，B 模块叫 `rule_id`
❌ `timeout`（无单位）、`flag`（布尔无语义）
✅ `timeout_ms`、`is_enabled`、`conn_count`

## 完成前自检

- [ ] 新名称已查术语表；未收录概念已先登记（NAME-01）
- [ ] 同一概念全工程同名，无禁用同义词（NAME-02）；新名称已先检索复用（NAME-05）；同一接口内命名格式未混用（NAME-07）
- [ ] 改动的公共字段在所有生产方、消费方、数据转换层、接口定义、测试中同步（NAME-03/04）
- [ ] 布尔、计数、带单位数值的语义后缀正确（NAME-06）
- [ ] 未擅自修改公共接口名称/类型/含义，未破坏兼容性，未改与任务无关的代码（NAME-08）
- [ ] 发现命名不一致时：已报告具体位置、影响范围与建议方案（NAME-09）
