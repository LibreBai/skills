---
name: fnisg-web-local-debug
description: 本地用 docker 跑 FNISG 前端(Vue2,:8080)+后端(Flask,:8081)，直连真实后台网闸设备(MQTT 1883)。用户要在本地启动/访问 FNISG web、重启服务、排查接口、切换设备、切换系统类型(FNISG防火墙/FINGAPS网闸)时使用。设备固件/驱动问题、生产部署、不碰后端的纯静态前端预览不走本 skill。执行前需向用户确认代码路径、设备 IP、DevSN、系统类型。
---

# FNISG 本地 Web 联调（通用流程）

在一个 docker 容器里同时跑前端(Vue2 dev :8080) + 后端(Flask :8081)，宿主浏览器访问 `http://localhost:8080` 操作真实网闸设备。

链路：浏览器 → :8080(vue devServer,/api_1、/pfe 由 proxyTable 代理) → :8081(flask) → **直连设备 :1883**(控制侧 172.20.0.235 / 信息侧 172.20.0.236)

> **直连是标准路径**（2026-10-29 实测定稿，取代 2026-09-30 的「必须走隧道」结论——网络环境翻回来了）。直连成立需**两个前置**，缺一包就被设备丢（宿主/容器 TCP 全 timeout）：
> ① **broker 监听 0.0.0.0**：出厂只听 loopback，需在设备 fnisg_cli 容器里 patch（配方见「设备 1883 访问」节；235/236 已于 2026-10-29 patch，备份 `.bak-20261029`）
> ② **设备运行模式 = 学习/测试**（设备 web 上切）：正常模式下设备本地安全规则丢 1883（`local_service` 无 1883 → `acl_whitelist -j DROP`）；切学习/测试后 `run_mode_learning` 链出现 ACCEPT 规则即通
> 任一前置失效（设备重启丢 patch / 模式切回正常 / 网络再拦 1883）→ 退回 **SSH 隧道**方案（配方同样保留在「设备 1883 访问」节）。

> 这是**通用流程**。下面 `<...>` 是每个使用者不同的值，执行时先向用户确认或自动探测，不要假定。

---

## 第 0 步：向用户收集 4 样东西（缺一不可）

🔴 **CHECKPOINT·STOP**：4 样没确认齐不要进第 1 步——代码路径/设备 IP/DevSN/系统类型错一个，容器和链路全要返工。能自动探测的（如 `ls ~/Gitee/FNISG-*`）探完即算确认；探测不出的必须问用户。

用 AskUserQuestion 或直接问：

1. **两个项目的代码路径**（宿主绝对路径）
   - FNISG-vue 路径 → 挂载进容器 `/workspace/FNISG-vue`
   - FNISG-python 路径 → 挂载进容器 `/workspace/FNISG-python`
   - 不确定就探测：`ls ~/Gitee/FNISG-*` 或问用户
   - **本 skill 目录绝对路径** → 挂载进容器 `/workspace/skill`（后端依赖清单随 skill 走，见第 4 步；skill 自包含，不往业务仓库写任何文件）
2. **设备 MQTT IP**（网闸分控制侧/信息侧，各一个 broker）
   - 控制侧 IP → 启动 env `FNISG_MQTT_HOST`（信息侧 `FNISG_MQTT_INFO_HOST`），不改 config.py
   - （两侧可能是同一台设备的两个网口，也可能是两台）
   - **前提：直连两前置就绪**（broker patch 0.0.0.0 + 设备运行模式学习/测试，见「设备 1883 访问」节）；不满足就起 flask → paho reconnect 循环且不自愈，此时退回隧道方案
3. **DevSN**（设备序列号，见下方"DevSN 怎么取"。不知道就先跳到那节教用户取）
4. **系统类型**：跑 **FNISG(防火墙)** 还是 **FINGAPS(网闸)**——启动 env `FNISG_PRODUCT_TYPE`，见下方"切换系统类型"节。

## 第 1 步：启动容器（挂载代码 + 映射端口）

```bash
docker run -d --name <容器名,如 fnisg-dev> \
  -p 8080:8080 -p 8081:8081 \
  -v <FNISG-vue 绝对路径>:/workspace/FNISG-vue \
  -v <FNISG-python 绝对路径>:/workspace/FNISG-python \
  -v <本skill目录绝对路径>:/workspace/skill \
  -w /workspace \
  <基础镜像> sleep infinity
```

- **端口**：必须 `-p 8080:8080 -p 8081:8081`（8080 给浏览器；8081 只用于宿主 curl 排错，页面请求经 devServer 代理，不再直连）
- **基础镜像**：优先用已搭建好的镜像（含 python3.11+node14+依赖，见第 2 步判断）；没有就用 `debian:12`（系统自带 python3.11 免编译，见第 3 步首选路径；docker hub 被墙：`docker pull docker.1ms.run/library/debian`）

## 第 2 步：判断环境是否已就绪（决定要不要装东西）

进容器检查：
```bash
docker exec <容器名> sh -c '
  /usr/local/bin/python3.11 --version 2>&1;      # 要 3.11.x，不能是系统 3.14
  /usr/local/node/bin/node --version 2>&1;        # 要 v14.x
  /opt/fnisg-venv/bin/python -c "import flask" 2>&1 && echo "venv OK";
  test -x /workspace/FNISG-vue/node_modules/.bin/webpack-dev-server && echo "前端依赖 OK";
'
```
- **都有**（用已搭建镜像的情况）→ 跳到第 6 步
- **缺**（裸镜像；node_modules 挂载的是宿主目录，换仓库 checkout 就会缺）→ 按第 3、4 步搭建（debian:12 首选路径约 5 分钟；ubuntu 兜底 20-40 分钟）

## 第 3 步：装 python 3.11 + node 14（仅首次/裸镜像）

> **为什么不是系统 python**：ubuntu:latest 自带 python **3.14**，项目 tests 里有 `telnetlib`（3.13 起移出标准库）会直接炸，**选 3.11 稳**。node **14.17.1** 是实测经验值（与 node-sass 7 / ABI 83 匹配；package.json 的 engines 实际宽松 `>=6`，非项目锁定）。
>
> ⚠️ **本步所有命令都在容器内执行**：先 `docker exec -it <容器名> bash` 进容器再粘贴；在宿主直接跑 `sed -i`/`apt-get` 会真改宿主。

**首选路径（2026-10-26 实测，1 分钟，免编译）**：基础镜像直接用 **`debian:12`**（bookworm 系统 python 就是 **3.11.x**），换清华源后 apt 直装：

```bash
sed -i "s|deb.debian.org|mirrors.tuna.tsinghua.edu.cn|g; s|security.debian.org|mirrors.tuna.tsinghua.edu.cn|g" /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list 2>/dev/null
apt-get update && apt-get install -y ca-certificates curl xz-utils make g++ python3 python3-venv python3-pip
python3 --version        # → 3.11.x
ln -sf /usr/bin/python3 /usr/local/bin/python3.11   # 对齐第 2 步就绪检查的路径
python3 -m venv /opt/fnisg-venv
```

**兜底路径（只有 ubuntu:latest 可用时）**——apt 先换 **http 清华源**（https 会因没 ca-certificates 失败；ubuntu 的 sources 格式与 debian 不同，别照抄首选路径的 sed）：

```bash
sed -i 's|http://archive.ubuntu.com|http://mirrors.tuna.tsinghua.edu.cn|g; s|http://security.ubuntu.com|http://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list
apt-get update && apt-get install -y ca-certificates curl xz-utils
# python 3.11 编译依赖
apt install -y libssl-dev zlib1g-dev libffi-dev libsqlite3-dev libbz2-dev liblzma-dev libreadline-dev libncurses-dev
# 源码（华为云镜像）
curl -O https://mirrors.huaweicloud.com/python/3.11.9/Python-3.11.9.tgz
tar xzf Python-3.11.9.tgz && cd Python-3.11.9
./configure --prefix=/usr/local && make -j$(nproc) && make altinstall   # altinstall→python3.11
/usr/local/bin/python3.11 -m venv /opt/fnisg-venv
```

node 14.17.1（两种路径通用，npmmirror 二进制）：
```bash
curl -O https://cdn.npmmirror.com/binaries/node/v14.17.1/node-v14.17.1-linux-x64.tar.xz
tar xJf node-v14.17.1-linux-x64.tar.xz -C /usr/local && mv /usr/local/node-v14.17.1-linux-x64 /usr/local/node
```
搭建完建议 `docker commit` 成镜像（如 `<容器名>:py311`），以后秒起、不用重装。**commit 时机放在 dev 编译成功验证之后**——环境常有暗坑（如 node-sass binding 平台错位），固化半成品下次照样踩。

## 第 4 步：装项目依赖（仅首次）

> 本步命令均在**容器内**执行（`docker exec -it <容器名> bash` 进去后跑）；仅"重扫清单"的 grep 在宿主的仓库父目录下跑（该行已注明）。

```bash
# 后端（venv pip，清华源）。依赖清单随本 skill 维护（skill 目录下 requirements.txt，
# 已挂载为 /workspace/skill/requirements.txt），不落在任何业务仓库里——skill 必须自包含。
# 上游 import 变化时重扫更新 skill 里的清单（宿主跑，人工剔标准库，import 名≠pip 名需映射）：
#   grep -rhoE '^(from|import) [a-z_0-9]+' FNISG-python --include='*.py' \
#     | awk '{print $2}' | cut -d. -f1 | sort -u
# （dateutil→python-dateutil、PIL→pillow、Crypto→pycryptodome；勿凭记忆抄——skill 旧清单
# 里的 Flask-SocketIO 实际未被 import。2026-10-26 实扫 12 包，仅 Flask、paho 锁版本）
/opt/fnisg-venv/bin/pip install -i https://pypi.tuna.tsinghua.edu.cn/simple -r /workspace/skill/requirements.txt
# 坑:pillow 在 py3.14 没预编译 wheel 要源码编译(需 libjpeg-dev zlib1g-dev libfreetype6-dev...),py3.11 有 wheel

# 前端（node 14 的 npm，淘宝源）
cd /workspace/FNISG-vue
npm config set registry https://registry.npmmirror.com/
npm install   # node-sass 等原生模块可能要 python3/make/g++ 兜底；sass_binary_site 设 npmmirror
```

## 第 5 步：联调参数（2026-09-29 起全 env 化，零文件改动）

**不再需要改任何业务文件**（config.py 的 mqtt/系统类型、vue 的 global.js 曾靠手改切换，现已全部改为 os.getenv + 页面地址推导）。参数一律走启动 env，落在未跟踪文件里（模板：FNISG-python `local.env.example`、FNISG-vue `dev.local.sh.example`；建不建实体文件都行，内联 env 同效）：

| 变量 | 标准值(直连连调) | 用途 |
|---|---|---|
| `FNISG_TO_TEST=1` | 必设 | 强制走本地联调配置块（Linux 容器必设，否则 flask 走生产块卡死） |
| `FNISG_DEV_SN=drive-scsi0` | 两台 235/236 都是这个 | MQTT topic 序列号，漏了接口全 10s 超时(`Resp//` 双斜杠) |
| `FNISG_MQTT_HOST=172.20.0.235` | 控制侧设备 IP | 直连 235:1883（隧道模式改 172.17.0.1） |
| `FNISG_MQTT_PORT=1883` | 设备 broker 端口 | （隧道模式改 18835） |
| `FNISG_MQTT_INFO_HOST=172.20.0.236` | 信息侧设备 IP | 直连 236:1883（隧道模式改 172.17.0.1） |
| `FNISG_MQTT_INFO_PORT=1883` | 同上 | （隧道模式改 18836） |
| `FNISG_PRODUCT_TYPE` | FINGAPS | `FNISG`(防火墙) \| `FINGAPS`(网闸) |
| `SIDE` | ctrl | `ctrl` \| `info`（单侧形态联调时用） |

- ⚠️ env 必须显式带全，别省：config.py 的默认值恰好也是 `172.20.0.235/236:1883`，但 DevSN 默认是占位串 `local-dev-sn`、`FNISG_TO_TEST` 不带必卡死——靠默认值等于埋雷，env 照抄第 6 步② 整串
- 前端代理目标（config/index.js proxyTable 读，写进 `npm run dev` 的启动环境）：`FNISG_API_TARGET`（默认 `http://127.0.0.1:8081`，容器内 flask 本机，不用设）、`FNISG_SUBAPP_TARGET`（默认 `http://127.0.0.1:8848`，wujie 子工程，不用可不设）
- `mqttInfo.py` DevSN 仍硬编码 `'drive-scsi0'`（`mqttInfo.py:262/265`，未 env 化）——**只在换信息侧设备且 SN 不同时**才需手改

> 两仓库各带 `.githooks/pre-commit` 守卫（python 拦 config.py 出现 188xx 端口字面量；vue 拦源码出现硬编码环境地址），启用：`git config core.hooksPath .githooks`。
> 排错时"工作区被还原"类问题已不存在——tracked 文件不再有本地差异，联调参数只看 env。

## 第 6 步：启动顺序（铁律）：先验设备 1883 可达 → 再 flask → 最后 dev

**顺序错了必出鬼**：设备 1883 不可达时起 flask → paho 落进无限重连循环（flask.log 刷 `reconnecting·······`，每轮 sleep(30)），期间所有发设备的接口全挂。代码上链路通了下一轮会自愈，但一轮 30s 起还容易被当卡死——**flask 起完后确认链路在，不通就修复（见「设备 1883 访问」节）并重启一次 flask**（标准操作见下方「重启 flask」小节）。

**① 验直连可达**（两台都验，容器内 venv python 探 TCP）：
```bash
docker exec <容器名> /opt/fnisg-venv/bin/python -c "
import socket
for ip in ['172.20.0.235','172.20.0.236']:
    s=socket.socket(); s.settimeout(3)
    try: s.connect((ip,1883)); print(ip,'OK')
    except Exception as e: print(ip,'不通:',e)
    finally: s.close()"
# 不通 → 按「设备 1883 访问」节三要素查：broker patch → 运行模式 → 网络层；都不行退回隧道：
#   ss -tln | grep -q ':18835' || sshpass -p 'huacon@2019' ssh -f -N -o StrictHostKeyChecking=no -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
#     -L 0.0.0.0:18835:127.0.0.1:1883 root@172.20.0.235   # 控制侧（信息侧同理 18836→236）
#   走隧道时 flask env 的 HOST/PORT 对应改 172.17.0.1:18835 / 172.17.0.1:18836
```

**② flask（必须 `docker exec -d`，不能用 setsid in exec——会 defunct 退出）**：
```bash
docker exec -d <容器名> sh -c 'cd /workspace/FNISG-python && FNISG_TO_TEST=1 FNISG_DEV_SN=drive-scsi0 FNISG_MQTT_HOST=172.20.0.235 FNISG_MQTT_PORT=1883 FNISG_MQTT_INFO_HOST=172.20.0.236 FNISG_MQTT_INFO_PORT=1883 FNISG_PRODUCT_TYPE=FINGAPS /opt/fnisg-venv/bin/python -m flask --app app run --host 0.0.0.0 --port 8081 > /tmp/flask.log 2>&1'
```

**③ dev**：
```bash
docker exec -d <容器名> sh -c 'cd /workspace/FNISG-vue && /usr/local/node/bin/npm run dev > /tmp/dev.log 2>&1'
```

**④ 信息侧功能首次使用前，跑对侧 SN 通道探测**（一键脚本，见下方「对侧 DevSN 通道」节）——漏了信息侧接口一律报「对侧DevSN未获取，信息侧请求未发送」。

- **env 缺一不可**：漏 `FNISG_TO_TEST=1` → flask 走设备分支卡死；漏 `FNISG_DEV_SN` → MQTT topic SN 空串（`Resp//` 双斜杠），接口全 10s 超时。示例串里 `FNISG_PRODUCT_TYPE=FINGAPS` 按第 0 步确认的类型写（防火墙场景写 `FNISG`）
- **MQTT 健康判据 = flask.log 出现 2 行「已连接mqtt」**（双 broker 各一）。**oem 接口 200 不代表 MQTT 通**——oem 是本地接口不碰设备
- flask 绑定速度：新版分支已去掉 connect() 成功后 sleep(30) 白等（055b71c），实测 ~5-30s；老分支 60-75s。以 `curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8081/member/getOemInfo` 返回 200 为准，别按固定秒数死等
- **杀 flask 的坑**：最小镜像**没有 pkill**，且 `pkill -f` 模式串会匹配到包装 sh 自己 → 自杀。一律走下方「重启 flask 标准操作」① 的 /proc 遍历杀法（模式串带 `[n]` 字符类防自匹配），杀与验证分两个 exec
- 日志 `/tmp/flask.log`、`/tmp/dev.log`；dev 首次编译 30-90s，有缓存 5s

### 重启 flask 标准操作（切系统类型/修链路/更新垫片后都走这两步）

🔴 **CHECKPOINT**：重启会踢掉所有已登录的浏览器会话（要重新登录），切系统类型还会整站换形态。动手前确认当下没人正在这套环境里操作；替别人维护时先打声招呼。

```bash
# ① 杀（单独 exec；模式串用 pytho[n] 字符类打断，防 wrapper 自匹配——最小镜像无 pkill）
docker exec <容器名> sh -c 'for p in /proc/[0-9]*/cmdline; do c=$(tr "\0" " " <"$p" 2>/dev/null); case "$c" in *venv/bin/pytho[n]*) kill $(basename $(dirname "$p")) 2>/dev/null;; esac; done'
# ② 确认已停（另开 exec）
docker exec <容器名> sh -c 'curl -s -o /dev/null --max-time 2 http://localhost:8081/ && echo "仍占用" || echo "已停止"'
# ③ 启（照抄第 6 步② 的整条 docker exec -d 命令，env 按当前系统类型带全）
```

## 第 7 步：验证 + 访问

```bash
curl -sf -o /dev/null http://localhost:8080/                            # 前端 → 200
curl -s -X POST http://localhost:8080/api_1/member/getSystemType        # 经代理 → {"status":0,...,"type":"fingaps","gap_type":"BOTH_SIDE","side":"ctrl"}
docker exec <容器名> grep -ac "已连接mqtt" /tmp/flask.log               # → 2 才算 MQTT 就绪（-a：日志混设备推送二进制字节，不加会被当 binary 截断）
```
都正常 → 浏览器开 **`http://localhost:8080`**（改代码不生效就 Ctrl+Shift+R 强刷）。web 登录 **admin / hc@20190**（235/236 设备侧 web 同）。

首次搭环境走通后，回头把第 3 步末尾说的 `docker commit` 做掉（把踩过的坑一起固化成镜像）。

## 对侧 DevSN 通道（信息侧接口前置检查，2026-10-26 实测定稿）

**现象**：信息侧接口一律报 `对侧DevSN未获取，信息侧请求未发送`（FNISG-python `common/mqtt.py:430`），flask.log 有 `获取对侧DevSN失败` 或 `对侧DevSN未获取, 跳过信息侧请求`。
**根因**：信息侧组 MQTT topic 需**对侧设备**的 SN，真机机制 = `fetch_peer_sn()` 用 rclone over SSH 读对侧 `/run/udev/data/b8:0` 提取磁盘序列号；本地容器无 rclone（2026-09-30 时容器到设备 22 也不通，故用垫片顶替；2026-10-29 复测容器→设备 22 已通——网络环境会翻，垫片方案保留沿用，少依赖）。
**修复**：宿主核实对侧真实 SN 后给容器装 rclone 垫片（仅容器文件系统，不碰仓库）——已固化为一键脚本：

```bash
bash <本skill目录>/scripts/check_peer_sn.sh [对侧IP] [SSH密码] [容器名]
# 默认 172.20.0.236 / huacon@2019 / fnisg-dev
```

- 脚本前置：宿主需有 `sshpass` 和 `docker`（没有 sshpass 时会报「读不到对侧SN」——先装 sshpass 再怀疑密码）；退出码 0=通路 OK/已修复、1=失败（对侧不可达/容器异常）

- 脚本流程：宿主 SSH 直读对侧 SN（权威值）→ 容器内按 `mqtt.py` 原样管道探测 → 不通装垫片 → 校验输出一致 → 检查 flask 缓存状态
- 装完**重启 flask** 最干净：`fetch_peer_sn` 有 60s 限频 + 进程内空值缓存，不重启最多等 1 分钟；重启后浏览器需重新登录
- 判据：flask.log 出现 `PeerSN: <SN>` 后信息侧接口可用，之后走进程内缓存不再探测
- 235/236 实测：两台 VM 盘序列号同为 `drive-scsi0`（QEMU drive-scsi0）；垫片返回值以脚本当次从真机读取为准，非假定

---

## DevSN 怎么取（连新设备必读）
DevSN = 设备系统盘 `/dev/sda` 的序列号（`ID_SERIAL_SHORT`），原代码用 udevadm 取。

**① 登录设备执行**（最准）：
```bash
udevadm info --query=property --name=/dev/sda | grep ID_SERIAL_SHORT   # 等号后即 DevSN
```
**② 不登录，监听 broker 看**（直连，topic 第 4 段是 SN）：
```bash
docker exec <容器名> /opt/fnisg-venv/bin/python -c "
import paho.mqtt.client as mqtt,time
c=mqtt.Client(client_id='sn_probe'); c.connect('172.20.0.235',1883,60)
c.on_message=lambda cl,u,m: print(m.topic)
c.subscribe('HC/PFE/PushUp/#'); c.loop_start(); time.sleep(15)"
# HC/PFE/PushUp/<SN>/<ClientId>/IF/<模块> → split('/')[3] 取 SN
```

## 切换系统类型：FNISG(防火墙) vs FINGAPS(网闸)

**唯一开关**是启动 env `FNISG_PRODUCT_TYPE`（测试块和生产块同读这一个变量），二选一：

```bash
FNISG_PRODUCT_TYPE=FNISG    # 防火墙(FNISG)
FNISG_PRODUCT_TYPE=FINGAPS  # 网闸(FINGAPS,默认)
```

改完**只重启 flask**，前端不动（不 rebuild、不改 vue 任何代码）。

**为什么只改这一处就够**（其余全自动跟随）：
- `config.py` 末尾 `menu_name` 按 `system_type` 自动选 `static/menu_FNISG.json` 或 `static/menu_FINGAPS.json`（两个文件都得在 static/ 下，别删）
- 后端 `common/view.py` 的 `isGapSystem()` 据它决定网闸分支；`common/registerApi.py` 的 `proxy_url()` 仅在 **FINGAPS + BOTH_SIDE + 请求带 side=info** 时把 dp_log/report_log/mgmt_log/connectivity/package/log/serviceLog 等转发到信息侧
- 前端**自动跟随后端**：登录页调 `getSystemType`，后端据 `system_type` 返回 `{'type':'fingaps'}`(网闸) 或 `{'type':'nisg'}`(防火墙)，vue 据此切 HomeFingaps/HomeFnisg、菜单、登录页样式、`getDeviceInfo().type`

**注意**：
- 网闸(FINGAPS) 才走 `gap_type=BOTH_SIDE`/`side=ctrl` 那套信息侧代理逻辑；防火墙(FNISG) 无此概念。
- 切过去后若首页/菜单空白，先确认 `static/` 下有对应的 `menu_*.json`（某些分支早期只支持一族，可能缺文件）。
- 系统类型和「设备 IP / DevSN」是**两回事**：换设备改 IP+SN，换产品改 system_type，可独立切换。

## 切换到另一组设备
新设备先做直连两前置（broker patch 0.0.0.0 + 运行模式学习/测试，见「设备 1883 访问」节；网络拦 1883 时改起隧道）→ 改启动 env（`FNISG_MQTT_HOST/PORT`、`FNISG_MQTT_INFO_HOST/PORT`、`FNISG_DEV_SN`）→ 重启 flask（dev 不用动，零文件改动）。新设备 SN 若不是 drive-scsi0，信息侧才需改 `mqttInfo.py:262/265` 的 `DevSN`（控制侧走 env）。

## 设备 1883 访问：直连三要素与隧道 fallback（2026-10-29 更新）

**直连三要素（缺一就是 timeout，按序排查）**：
1. **broker 监听 0.0.0.0**：脚本 `/fnisg/core/shell/fnisg_external_broker.sh`（设备 fnisg_cli 容器内，`-r-xr-xr-x`，root 可 chmod 后改）。逻辑=模板 `/fnisg/third_party/etc/mosquitto/mosquitto_extern.conf` sed 出运行时 `/run/fnisg/mosquitto_extern.conf`，**改模板 conf 无效**（会被脚本重写）。patch 配方（2026-10-29 已做，备份 `.bak-20261029`）：控制侧 235 改 16 行 `local listen_ip="0.0.0.0"`；信息侧 236 改 19 行 `listen_ip="0.0.0.0"` + 20 行 `extra_ip=""`（防 0.0.0.0 与 127.0.0.1 双绑定 EADDRINUSE；`$GAP_INFO_IP` 变量行用行号整行替换 `sed -i '19s/.*/.../'` 避开三层转义）→ `s6-svc -r /run/service/fnisg_external_broker` + `s6-svc -r /run/service/fnisg_auth`（auth 桥必须跟着重启）。判据：`grep -nE "^listener" /run/fnisg/mosquitto_extern.conf` 出现 `listener 1883 0.0.0.0`，且 `/proc/net/tcp` 有 `00000000:075B`。**设备重启/重铺镜像丢 patch**，先 `grep -n "listen_ip" <脚本>` 看 0.0.0.0 还在不在。
2. **设备运行模式 = 学习/测试**（设备 web 上切，admin/hc@20190）：正常模式下设备本地安全规则丢 1883——`local_service` 白名单只有 53/123 等，INPUT 链末尾 `acl_whitelist -j DROP`。判据：`iptables -L run_mode_learning -n` 链内有 ACCEPT 规则=在学习/测试；链空=不在（别再走设备 iptables 手工放行的老路，切模式即可）。
3. **网络路径放行 1883**：前两要素都在还不通，才是网络层拦截（2026-09-30 曾只放行 22/443；2026-10-29 复测已放行，宿主/容器直测 22 与 1883 均通——网络环境会翻，判断套路：宿主 python socket 探 `ConnectionRefused`=到了没监听 vs `timeout`=路径丢包）。

**直连模式 env**：flask `FNISG_MQTT_HOST=172.20.0.235/236、PORT=1883`，容器直出设备 CONNACK rc=0（2026-10-29 实测）。

**隧道 fallback**（网络拦 1883 或不便切运行模式时才用）：宿主 `sshpass -p 'huacon@2019' ssh -f -N -o StrictHostKeyChecking=no -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -L 0.0.0.0:18835:127.0.0.1:1883 root@172.20.0.235`（信息侧 18836→236；分端口查，缺哪条补哪条——只查"任一在听"会漏掉半开隧道）。flask env 改 `172.17.0.1:18835/18836`（容器经 docker0 网关访问宿主隧道）。隧道是宿主进程，WSL 重启/被杀就断；排错先 `ss -tln | grep 1883`。

> **对业务仓库改动的总声明**：本 skill 对 FNISG-python / FNISG-vue 的一切改动（排错里的本地补丁、本地生成的清单等）都是**联调临时改动**——保持未跟踪、不提交上游；要转正须满足仓库 standards/ 规范并走正式流程。

## 已知限制
**需要设备执行命令的接口会失败**：`getLanguageInfo`/`login` 等发 `HC/PFE/Req/<SN>/...` 到设备，若设备命令处理 daemon 不响应 → flask `send_message` 超时后返回规整错误 `{'status': -1, 'msg': '命令执行超时，请稍后重试'}`（不再抛 NoneType 500）。这是**设备侧**（broker/推送在线但命令处理不工作），不是这套环境的问题。oem/getSystemType/getPublicKey 等本地接口正常。

## 排错
> flask.log 混有设备推送的二进制字节：`grep` 一律加 `-a`，否则报 binary file matches 并截断输出（本节所有「搜 flask.log」判据同理）。

- **信息侧接口全报 `对侧DevSN未获取，信息侧请求未发送`**：先甄别是不是现症——该报错只在 `fetch_peer_sn` 探测当次失败时产生且必留痕（成功 `PeerSN: <SN>`/失败 `获取对侧DevSN失败`），`grep -a` 当下日志看有无新记录；容器重建/垫片重装前的旧报错不算，垫片在位即自愈。确属现症再跑 `scripts/check_peer_sn.sh`（见「对侧 DevSN 通道」节）装垫片 + 重启 flask。
- **dev 编译失败 `Missing binding .../node-sass/vendor/linux-x64-83/binding.node`**：npm install 抓错平台的 node-sass 预编译二进制（vendor 里是 darwin-x64-* 等）。修：按 `node_modules/node-sass/package.json` 的版本手动补正确 binding：`curl -sfL https://npmmirror.com/mirrors/node-sass/v<版本>/linux-x64-83_binding.node -o node_modules/node-sass/vendor/linux-x64-83/binding.node`，再用 `node -e "require('.../node-sass').renderSync({data:'a{b:c}'})"` 自测后重启 dev。chromedriver 装失败同理无害（仅 e2e 用）。
- **容器内脚本跑一半 `Bad substitution`/假结果**：容器 `sh` 是 **dash**，禁一切 bash-ism——`${var:0:n}`、`[[ ]]`、数组、`/dev/tcp`（见下方 `/dev/tcp` 条）全不可用。复杂文本处理宁可 `awk`/`tr`，或宿主 bash 处理完再 `docker exec` 传入。
- **容器里 `pkill: command not found`**：最小镜像没装 procps（pkill/ps 全无）。杀进程一律用「重启 flask 标准操作」① 的 /proc 遍历杀法（把 `pytho[n]` 关键字换成目标关键字即可）；case 模式串务必带 `[n]` 式字符类打断自匹配（wrapper 命令行含关键字会把自己杀掉、后续命令不执行，exit 143），杀与验证分两个 exec。
- **`npm install ... | tail; echo $?` 显示 0 但实际失败**：`$?` 是管道最后一个命令（tail）的退出码。判断装没装成：看输出有无 `npm ERR!` + `node_modules/.bin/webpack-dev-server` 是否存在。
- **页面打不开/转圈**：curl 两端口看 200；BASE_URL 由页面地址自动推导，不受文件影响——API 全挂先看 `/tmp/dev.log` 里 proxyTable 是否生效（`FNISG_API_TARGET` 指对没），再 Ctrl+Shift+R 强刷清旧 bundle。
- **oem 等全 500**：`registerApi.py` 的 `ip=` 被还原成 `request.headers["X-Real-IP"]` 硬取 → 改回 `request.headers.get("X-Real-IP") or config.config['mqtt_host']`，重启 flask。
- **直连 1883 全部 timeout**：按「设备 1883 访问」节三要素按序查：broker patch 0.0.0.0 在不在（`grep listen_ip`）→ 运行模式是否学习/测试（`run_mode_learning` 链空=不在）→ 网络层（refused=没监听 / timeout=丢包）；都不行退回隧道。
- **flask 起不来/绑不上 :8081**：①漏 `FNISG_TO_TEST=1`（走生产块卡死，flask.log 0 字节）；②**设备 1883 不可达**（patch 丢/模式不在学习测试/隧道断）→ flask.log 刷 `reconnecting·······` 或 `MQTT重新连接失败: [Errno 111] Connection refused`——先修链路（见「设备 1883 访问」节）**再重启 flask**（走「重启 flask 标准操作」）；③还在 import（Threads 已到 4 就快了）→ 再等。老镜像（未修 sleep30）链路不通时是 import 阶段死循环 sleep(30)，特征 flask.log 0 字节 + wchan=nanosleep。
- **运行中所有下发接口 500 + 日志 `The client is not currently connected`**：设备 1883 链路断了（直连查三要素，隧道模式查 `ss -tln | grep 1883`）。链路恢复后重启 flask 立即恢复（不重启要等 paho 下轮 30s 重试；走「重启 flask 标准操作」）。
- **接口全 10s 超时**：flask.log 搜 `Resp//`（双斜杠）→ DevSN 空串，漏 `FNISG_DEV_SN`。
- **某接口 NoneType/500**：`send_message` 返回 None → 设备没回 Resp（见已知限制）。
- **登录类接口 500 + 日志反复「MQTT连接断开」**：paho 被装成 2.x（代码按 1.x 写，2.x 的包被设备判 malformed 踢掉）。修：`docker exec <容器> /opt/fnisg-venv/bin/pip install 'paho-mqtt<2'`；判据=设备 `docker logs fnisg_cli | grep malformed`。
- **测端口别用容器内 `/dev/tcp`**：容器 `sh` 是 dash 不支持，通不通都报失败（假阴性）。用 venv python socket，或宿主 bash `/dev/tcp`。
- **dev 编译失败 `Module not found: Can't resolve '@/pages/network/dnsHosts/...'`**（整站崩，不是告警）：2026-10-27 核查两个远端分支的 router 与文件现状均不复现（疑为历史上某次本地 checkout 混搭的一次性现象）。遇到时按缺什么补什么：`git checkout origin/develop -- <缺失目录>`（dnsHosts 页面在 origin/develop 上齐全）。
- **极老本地 checkout py3.11 起不来**（两处上游均已修复：d37ddf1 修 config.py 嵌套同引号 f-string、b4559d0 修 `custom_groups/view.py` 的 `from flaskr import request`）：如仍遇到，外层 f-string 改单引号、`from flaskr import request`→`from flask import request`，先 py_compile 全仓扫定位；本地补、不提交。
- **第 1 步 `docker run` 失败**：端口被占 → `ss -tln | grep -E '808[01]'`，换宿主侧端口（如 `-p 18080:8080`，浏览器改访问 18080）；容器名已存在 → `docker ps -a` 查后 `docker start` 复用或 `docker rm` 重建。
- **dev 编译完就退出**：启动方式错了，必须 `docker exec -d`。
- **复杂脚本进容器**：`docker exec -i <容器> sh -s <<'EOF' ... EOF`（**别忘 `-i`**，否则 stdin 不传、静默无输出）。
- **pip 装 pillow 失败**：py3.14 没预编译 wheel → 换 py3.11。
- 进容器：`docker exec -it <容器名> bash`

## 不要做（反例速查）
- 别用容器内 `/dev/tcp` 测端口（dash 不支持，假阴性）→ venv python socket 或宿主 bash
- 别在容器里 `pkill -f`（无 procps + wrapper 自匹配自杀）→ 走「重启 flask 标准操作」①
- 别把首选路径（debian）的 apt sed 照抄到 ubuntu（sources 格式不同；ubuntu 先 http 源装 ca-certificates）
- 别改设备上 mosquitto 模板 conf（会被 broker 脚本重写）→ patch 运行时脚本
- 别按固定秒数死等 flask 起来 → 以 `curl 200` / `已连接mqtt`=2 为准
- 别凭记忆抄后端依赖清单 → 按 import 重扫（历史清单混进过未被 import 的包）
- 业务仓库里的联调临时改动别提交上游（保持未跟踪，转正走正式流程）
- 别直连设备 `IP:1883`（现网络只放行 22/443；直连写法仅在网络放行 1883 时用）

## 镜像源速查（国内）
- docker 镜像：`docker pull docker.1ms.run/library/<img>`（hub 被墙）
- apt：`http://mirrors.tuna.tsinghua.edu.cn/ubuntu`（先 http 装 ca-certificates 再 https）
- python 源码：`https://mirrors.huaweicloud.com/python/3.11.9/Python-3.11.9.tgz`
- node 二进制：`https://cdn.npmmirror.com/binaries/node/v14.17.1/node-v14.17.1-linux-x64.tar.xz`
- npm/pip：`https://registry.npmmirror.com/` / `https://pypi.tuna.tsinghua.edu.cn/simple`
