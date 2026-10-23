#!/usr/bin/env bash
# searxng-forge 环境探测器 —— 只读采集，不做任何变更。判断逻辑见 SKILL.md 阶段〇。
set -u
say() { printf '%s\n' "$*"; }

say "== system =="
say "os: $(uname -s) $(uname -r) $(uname -m)"
[ -f /etc/os-release ] && . /etc/os-release && say "distro: ${PRETTY_NAME:-unknown}"
mem_mb=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null || sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1048576)}')
say "memory_mb: ${mem_mb:-unknown}"
disk_free_gb=$(df -Pk / 2>/dev/null | awk 'NR==2{print int($4/1048576)}')
say "disk_root_free_gb: ${disk_free_gb:-unknown}"

say "== docker =="
if command -v docker >/dev/null 2>&1; then
  say "docker: yes ($(docker --version 2>/dev/null))"
  say "docker_daemon: $(docker info >/dev/null 2>&1 && echo running || echo stopped)"
else
  say "docker: no"
fi

say "== proxy environment =="
# 本机 shell 的代理变量会污染所有后续探测，必须先采集
for v in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy; do
  eval "val=\${$v:-}"
  [ -n "$val" ] && say "proxy_env: $v=$val"
done
[ -z "${http_proxy:-}${https_proxy:-}${HTTP_PROXY:-}${HTTPS_PROXY:-}${ALL_PROXY:-}${all_proxy:-}" ] && say "proxy_env: none"

say "== egress (two paths) =="
# 路径1：默认（受代理变量影响的真实日常路径）；路径2：--noproxy 直连（本机裸网络）
egress_env=$(curl -s -m 8 https://api.ipify.org 2>/dev/null || echo "")
egress_direct=$(curl -s -m 8 --noproxy '*' https://api.ipify.org 2>/dev/null || echo "")
say "egress_ip_default_path: ${egress_env:-unreachable}"
say "egress_ip_direct_path: ${egress_direct:-unreachable}"
for ip in "$egress_env" "$egress_direct"; do
  [ -z "$ip" ] && continue
  [ "$ip" = "unreachable" ] && continue
  ipinfo=$(curl -s -m 8 "http://ipinfo.io/${ip}/json" 2>/dev/null)
  say "ipinfo ${ip}: ${ipinfo:-unavailable}"
done

say "== gfw check (direct path) =="
# 判断墙内与否必须用直连路径；代理路径的结论只代表代理出口
gfw_code=$(curl -s -m 6 --noproxy '*' -o /dev/null -w "%{http_code}" http://www.google.com/generate_204 2>/dev/null)
if [ "$gfw_code" = "204" ]; then say "gfw_direct: outside (google reachable directly)"; else say "gfw_direct: likely inside (direct google http_code=${gfw_code:-timeout})"; fi

say "== dns pollution evidence =="
# 只采集证据：系统解析器对三个高风险域名的 A 记录。
# 注意：若本机代理客户端开了 fake-ip/TUN 模式，会全部落在 198.18.0.0/16 段——
# 这说明 DNS 已被本机代理接管（对 searxng 部署是好消息），不是污染。特征段判断见 SKILL.md。
for d in github.com en.wikipedia.org duckduckgo.com; do
  ip=$(getent ahostsv4 "$d" 2>/dev/null | awk 'NR==1{print $1}')
  [ -z "$ip" ] && ip=$(python3 -c "import socket;print(socket.gethostbyname('$d'))" 2>/dev/null || echo "")
  say "dns ${d}: ${ip:-resolve-failed}"
done

say "== local agents =="
for c in zcode claude codex gemini cursor; do
  command -v "$c" >/dev/null 2>&1 && say "agent_cli: ${c} ($(command -v $c))"
done
[ -d "$HOME/.zcode" ] && say "agent_dir: ~/.zcode exists"
[ -d "$HOME/.claude" ] && say "agent_dir: ~/.claude exists"
[ -d "$HOME/.codex" ] && say "agent_dir: ~/.codex exists"

say "== probe done =="
