#!/bin/bash
# ---------------------------------------------------------------------------
# check_peer_sn.sh — fnisg-web-local-debug 对侧 DevSN 通道探测/修复
#
# 背景: 信息侧请求组 MQTT topic 需要对侧设备 DevSN(FNISG-python common/mqtt.py
# fetch_peer_sn), 真机机制 = rclone over SSH 读对侧 /run/udev/data/b8:0。
# 本地容器无 rclone、且容器网络到设备 22 端口不通(与 MQTT 同一网络现实)
# → 信息侧接口一律报「对侧DevSN未获取，信息侧请求未发送」。
#
# 本脚本流程:
#   ① 宿主 SSH 直读对侧真实 SN(权威值, 不假定)
#   ② 容器内按代码原样管道探测现有通路
#   ③ 不通则安装 rclone 垫片(仅容器文件系统, 不碰仓库)
#   ④ 校验垫片输出 == 真实 SN, 并检查 flask 缓存状态
#
# 用法: ./check_peer_sn.sh [对侧IP] [SSH密码] [容器名]
#       默认 172.20.0.236 / huacon@2019 / fnisg-dev (依赖宿主 sshpass)
# 退出码: 0=通路OK或已修复, 1=失败(对侧不可达/容器异常)
# ---------------------------------------------------------------------------
set -u
PEER_IP="${1:-172.20.0.236}"
PASS="${2:-huacon@2019}"
CTR="${3:-fnisg-dev}"

# udev 文本 -> SN, 与 mqtt.py fetch_peer_sn 的提取逻辑逐字一致
extract_sn() {
  awk -F= '/^E:ID_SERIAL=/{g=$2} /^E:ID_SERIAL_SHORT=/{s=$2} END{if(s!="")print s; else print g}'
}

echo "① 宿主直读对侧真实SN: ssh root@${PEER_IP} ..."
REAL_SN=$(sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 \
  "root@${PEER_IP}" \
  "cat /run/udev/data/b8:0 /run/udev/data/b179:0 2>/dev/null" 2>/dev/null | extract_sn)
if [ -z "${REAL_SN:-}" ]; then
  echo "❌ 读不到对侧SN: 检查宿主→${PEER_IP}:22 可达性与密码"; exit 1
fi
echo "   对侧真实SN = ${REAL_SN}"

# 容器内按代码原样命令探测(mqtt.py 的 rclone 管道)
probe_ctr() {
  docker exec "$CTR" sh -c \
    'rclone --config /etc/fnisg/rclone/rclone.conf cat peer:/run/udev/data/b8:0 2>/dev/null' 2>/dev/null \
    | extract_sn
}

echo "② 探测容器内通路(代码原样命令)..."
CUR_SN=$(probe_ctr)
if [ "${CUR_SN:-}" = "$REAL_SN" ]; then
  echo "✅ 容器内对侧SN通路正常: ${CUR_SN}"
else
  echo "   通路不通(容器返回: '${CUR_SN:-空}') → ③ 安装rclone垫片..."
  # 传值用 docker exec -e 环境变量而非位置参数: 容器 sh 是 dash, `sh -s a b` 的
  # $1 是 a(bash 语义是 $0), 曾把字面量 'shim' 写进垫片(2026-10-27 重建实测抓到)
  docker exec -i -e PEER_SN_VAL="${REAL_SN}" "$CTR" sh <<'SHIM' || { echo "❌ 垫片安装失败"; exit 1; }
cat > /usr/local/bin/rclone <<INNER
#!/bin/sh
# fnisg-web-local-debug 联调桩(scripts/check_peer_sn.sh 安装):
# 容器无到对侧设备的SSH路由, 模拟 rclone cat 对侧 udev 文件。
# SN 来源: 安装当次宿主 SSH 从真机核实, 非假定值。
echo 'E:ID_SERIAL=peer'
echo "E:ID_SERIAL_SHORT=${PEER_SN_VAL}"
INNER
chmod +x /usr/local/bin/rclone
SHIM
  CUR_SN=$(probe_ctr)
  if [ "${CUR_SN:-}" = "$REAL_SN" ]; then
    echo "✅ 垫片已装, 容器内通路输出: ${CUR_SN}"
  else
    echo "❌ 垫片后仍不匹配: '${CUR_SN:-空}'"; exit 1
  fi
fi

echo "④ flask 侧检查:"
FLASK_UP=$(docker exec "$CTR" sh -c \
  'for p in /proc/[0-9]*/cmdline; do c=$(tr "\0" " " <"$p" 2>/dev/null); case "$c" in *venv/bin/pytho[n]*) exit 0;; esac; done; exit 1' 2>/dev/null \
  && echo yes || echo no)
if [ "$FLASK_UP" = "yes" ]; then
  if docker exec "$CTR" grep -q "PeerSN: ${REAL_SN}" /tmp/flask.log 2>/dev/null; then
    echo "✅ flask 已缓存 PeerSN: ${REAL_SN}, 信息侧接口可用"
  else
    echo "⚠️  flask 在跑但尚未缓存 PeerSN —— 重启 flask 后首次信息侧请求生效:"
    echo "    (fetch_peer_sn 有 60s 限频, 不重启最多等 1 分钟也行, 重启最干净)"
    echo "    按 SKILL.md 第6步② 重启 flask, 然后浏览器重登录"
  fi
else
  echo "ℹ️  flask 未运行; 按 SKILL.md 第6步启动后首次信息侧请求自动生效"
fi
exit 0
