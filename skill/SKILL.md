---
name: searxng-forge
description: 在用户自己的服务器或本机 Docker 上部署并深度调优 SearXNG——网络地基、引擎自校准、权重排序、agent 接入一站式 SOP。当用户想要自建搜索引擎、部署/调优 SearXNG、或抱怨自建搜索全是 CAPTCHA/没结果时使用。
---

# SearXNG Forge —— 自托管高质量搜索部署与调优 SOP

## 核心原则（先读）

1. **能探测的绝不问用户。** 出口 IP、是否在墙内、DNS 是否污染、Docker 有无、内存磁盘、装了哪些 agent——全部用 `scripts/probe.sh` 探测。只问探测不到的决策题。
2. **顺序不可乱：网络地基 → 安装 → 实测调优 → 验证固化 → agent 接入。** 引擎测试结果依赖网络就绪；网络没修好就去调引擎，会把网络问题误诊成引擎问题。
3. **系统级操作逐一授权。** 安装 Docker、安装 mihomo、修改 iptables、创建 systemd 服务——每次执行前用一句话向用户说明做什么、影响什么，获得确认再动。
4. **测试要克制。** 单引擎串行、每次间隔 ≥5 秒、绝不做不带 `engines=` 参数的全引擎查询——一次 90+ 引擎的广撒网会触发集体 CAPTCHA，把机器测出假阴性，恢复要几分钟到几小时。
5. **本文件中的引擎清单是快照，不是真理。** 上游 SearXNG 的引擎生态每月都在变（引擎增删、反爬升级）。凡标 `[快照 2026-10]` 的结论，执行时必须重新实测验证。沉淀的是方法，不是快照。
6. **诚实报告上限。** 出口 IP 信誉是资源问题不是配置问题。skill 的承诺是"在用户给定网络条件下的最优"，不是"装完就有谷歌"。最终报告必须包含这台机器的引擎现实清单。

## 阶段〇：探测与问答

### 探测（自动，无需授权，全部只读）

```bash
bash scripts/probe.sh
```

输出键值对：操作系统/架构、内存、磁盘、Docker 有无及版本、出口 IP、IP 归属（ASN/类型）、是否在 GFW 内、DNS 污染嫌疑、本机已装的 agent CLI（zcode/claude/codex 等）。

关键判定逻辑（脚本给原始证据，由你判断）：

- **是否在墙内**：直连 `http://www.google.com/generate_204` 超时或重置 → 墙内。**注意**：若 `proxy_env: none` 但两条出口路径 IP 相同且 DNS 证据全落 198.18.0.0/16 段 = 本机代理客户端开了 TUN 全局接管（网络层劫持），此时"墙内与否"和出口的探测结果都只反映代理出口，不可据以下结论——向用户确认本机代理模式，或建议在有裸网络环境的机器上部署。
- **DNS 污染嫌疑**：直接解析 `github.com` / `en.wikipedia.org` / `duckduckgo.com`，与"已知真实段"或"经代理的 DoH 查询"对照。落在 31.13.x.x（Facebook）、108.160.16x.x（Dropbox）、199.59.148.x（Twitter）等特征段 = 高置信污染。若墙内且暂无代理，标记"待有代理后复查"。
- **出口 IP 类型**：ASN 属于云厂商（AWS/阿里云/华为云/GCP/OVH/DO…）= 机房 IP，引擎信誉打折；家宽 ASN = 住宅 IP，信誉最好。

### 问答（只问四个，一次性问完）

1. **网络资源**：a) 有独享节点（vless/hysteria2/trojan 凭据）b) 有机场订阅链接 c) 已有本机代理端口（如 127.0.0.1:7890）d) 什么都没有 → 决定阶段二走哪条分支，也决定引擎上限。
2. **主要用途**：a) 给 agent 调 JSON API b) 人肉网页搜索 c) 两者 → 决定 formats、limiter、超时。
3. **中英文比例**：中文为主 / 英文为主 / 双语 → 决定默认引擎组合与验证用例。
4. **是否公网暴露**：仅本机/局域网使用，还是公网可访问 → 公网暴露必须加固（见阶段五）。

若探测发现 Docker 缺失、mihomo 需要安装等系统级操作，在此阶段末尾逐一请求授权。

## 阶段一：网络地基

目标：searxng 容器的出站请求走"干净的出口 + 不被污染的 DNS"。**按分支走，不越级。**

### 分支 A：Linux 服务器 + 有节点或订阅（墙内，效果上限最高）

装 mihomo（原生 systemd 服务，不用 docker——透明代理场景原生更稳）：

1. 下载 mihomo 二进制（github release，按架构）到 `/usr/local/bin/mihomo`。
2. 创建 `mihomo` 用户；配置 `/etc/mihomo/config.yaml`。骨架：

```yaml
mixed-port: 7890
redir-port: 7893
allow-lan: true
bind-address: '*'
mode: rule
log-level: info
external-controller: '127.0.0.1:9090'
unified-delay: true
tcp-concurrent: true
profile:
    store-selected: true
    store-fake-ip: true
sniffer:
    enable: true
    override-destination: true        # 关键：按 SNI 域名重新解析拨号，绕开污染 IP
    sniff:
        TLS: { ports: [443] }
        HTTP: { ports: [80] }
    skip-domain: ['+.lan', '+.local']
dns:
    enable: true
    listen: 172.17.0.1:53             # 关键：给 docker 容器专用的 fake-ip DNS
    ipv6: false
    enhanced-mode: fake-ip
    fake-ip-range: 198.18.0.1/16
    respect-rules: true
    default-nameserver: [223.5.5.5, 119.29.29.29]
    proxy-server-nameserver: [223.5.5.5, 119.29.29.29]
    nameserver: [223.5.5.5, 119.29.29.29]
    fallback: [tls://1.1.1.1, tls://8.8.8.8]   # 关键：DoT 走 TCP；UDP DNS 过代理不稳
    fallback-filter:
        geoip: true
        geoip-code: CN
        ipcidr: [240.0.0.0/4]
proxies: []          # 用户的节点（凭据直接写）或引用 proxy-providers（订阅）
proxy-groups: []     # 出口分组。注意：如果用户不要求，分组里不要放 DIRECT 选项
rules:
    - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
    - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
    - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
    - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
    - IP-CIDR,<节点服务器IP>/32,DIRECT,no-resolve   # 防回环
    - GEOIP,CN,DIRECT
    - MATCH,<出口分组名>
```

3. 透明代理 iptables（保存为 `/usr/local/sbin/mihomo-transparent.sh`，做成 systemd oneshot 服务）：

```bash
#!/bin/sh
set -eu
MIHOMO_UID="$(id -u mihomo)"
iptables -t nat -N MIHOMO_OUTPUT 2>/dev/null || true
iptables -t nat -F MIHOMO_OUTPUT
iptables -t nat -N MIHOMO_DOCKER 2>/dev/null || true
iptables -t nat -F MIHOMO_DOCKER
# mihomo 自身出站不走代理（防回环）
iptables -t nat -A MIHOMO_OUTPUT -p tcp -m owner --uid-owner "$MIHOMO_UID" -j RETURN
# 内网/保留段直连
for cidr in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
  iptables -t nat -A MIHOMO_OUTPUT -d "$cidr" -j RETURN
  iptables -t nat -A MIHOMO_DOCKER -d "$cidr" -j RETURN
done
iptables -t nat -A MIHOMO_OUTPUT -p tcp -j REDIRECT --to-ports 7893
iptables -t nat -A MIHOMO_DOCKER -p tcp -j REDIRECT --to-ports 7893
iptables -t nat -D OUTPUT -p tcp -j MIHOMO_OUTPUT 2>/dev/null || true
iptables -t nat -I OUTPUT 1 -p tcp -j MIHOMO_OUTPUT
iptables -t nat -D PREROUTING -i docker0 -p tcp -j MIHOMO_DOCKER 2>/dev/null || true
iptables -t nat -I PREROUTING 1 -i docker0 -p tcp -j MIHOMO_DOCKER
```

4. searxng 容器启动时加 **`--dns 172.17.0.1`**（吃 mihomo 的 fake-ip DNS，DNS 污染和超时从根上消失）。
5. 验证：`curl -x http://127.0.0.1:7890 https://api.ipify.org` 应返回节点出口 IP；`curl -x http://127.0.0.1:7890 -o /dev/null -w "%{http_code} %{time_total}" https://www.google.com` 应 200 且 <3s；国内站直连应 <1s。

### 分支 B：macOS / 桌面机 / 不方便动 iptables

不做透明代理。mihomo（或用户已有代理客户端）只提供本地端口，searxng 显式走代理——在 settings.yml：

```yaml
outgoing:
  proxies:
    all://:
      - http://host.docker.internal:7890
```

（Linux 宿主机上写 `http://172.17.0.1:7890`。）DNS 由代理客户端远端解析（CONNECT 隧道带域名），天然无污染问题。

### 分支 C：海外服务器裸连

无需代理。检查 DNS 无污染（大概率干净）。重点转向机房 IP 信誉预期管理：云厂商 ASN 会被 google/bing 区别对待，引擎现实以 ddg/brave/API 型为主（见附录）。可选：若用户后续找到干净住宅 IP 或代理，可随时升级到分支 A/B。

### 分支 D：墙内且无任何代理资源

诚实告知上限：海外引擎基本不可用（连不上 + DNS 污染），只剩中文引擎（且 baidu/sogou 对自动化客户端 CAPTCHA 频繁）。给出两条路：a) 降低预期继续装（只有 bing 中文/百度开发等少数可用）b) 先搞代理资源再来。不要替用户决定，把现实摆清楚。

## 阶段二：安装 SearXNG

（Docker 缺失时：先取得授权再装。Linux 用 `curl -fsSL https://get.docker.com | sh`；macOS 引导装 Docker Desktop 或 OrbStack，无法静默装。）

```bash
docker run -d --name searxng \
  --restart unless-stopped \
  -p 8080:8080 \
  -v /opt/searxng:/etc/searxng \
  searxng/searxng:latest
# 分支 A 追加:  --dns 172.17.0.1
```

初始 `/opt/searxng/settings.yml`：

```yaml
use_default_settings: true
server:
  secret_key: "<openssl rand -hex 32 生成>"
  bind_address: "0.0.0.0"
  port: 8080
  limiter: false          # 公网暴露必须改 true 并配 limiter
search:
  formats: [html, json]   # agent 用途必须有 json
outgoing:
  useragent_suffix: "(self-hosted; contact: <用户邮箱>)"   # 无条件加，见附录 Wikimedia 政策
  request_timeout: 10.0
  max_request_timeout: 15.0
```

验证：`curl http://127.0.0.1:8080/` 返回 200，日志无 YAML 错误。

**镜像版本原则：引擎大面积异常时，第一反应是升级镜像（`docker pull` + 重建容器），不是改配置。** 上游持续在修引擎（TLS 指纹、解析 XPath、curl_cffi 模拟），2026 年 DDG 封锁的官方解法就是镜像升级。

## 阶段三：实测调优（自校准）

这一步生成**这台机器自己的**引擎清单。用 `scripts/enginetest.sh`（自带间隔节流）：

```bash
bash scripts/enginetest.sh http://127.0.0.1:8080 en   # 英文轮
bash scripts/enginetest.sh http://127.0.0.1:8080 zh   # 中文轮
```

对每个引擎判定：

- **可用**（≥5 条且首条与查询相关）→ 保持/启用，按下方权重表配 weight。
- **CAPTCHA / too many requests** → 若是首轮测试就出现，说明该引擎对此出口 IP 天然敌视 → 禁用；若是轰炸后出现 → 等 10 分钟重测一次再定。
- **timeout 持续** → 两轮都超时 → 禁用。偶发一次 → 保留。
- **0 结果且无报错** → 危险信号，二选一验证：容器内手工请求同一 URL（`curl_cffi` 模拟 chrome）看是引擎放毒（HTTP 正常但内容无关/空壳）还是解析失效（手工正常、引擎为 0）。前者禁用或 weight 0.5，后者升级镜像再看。

调优动作（写入 settings.yml 的 `engines:` 覆盖段，注意 `use_default_settings: true` 模式下按 name 合并）：

1. **weight 权重**（影响结果排序的分数倍率，`/config` 端点不显示此字段，验证需查引擎对象或看排序效果）：
   - `weight: 2` → 实测稳定的权威 API 型引擎：wikipedia、wikidata、github、npm、arxiv、mdn、stackoverflow、docker hub、semantic scholar、pubmed 等
   - `weight: 0.5` → 能出结果但质量不稳/有放毒史的（实测判定）
   - 默认 1 → 主力通用引擎（ddg、brave 等），让它们靠相关度自然竞争
2. **wikidata 单独 `timeout: 8`**（上游默认 3 秒，经代理链路不够）。
3. **已确认死亡的引擎显式 `disabled: true`**（保持 /config 清单与档案文档一致）。
4. settings 里引用了上游已移除的引擎名会在启动时报错（如某时期的 presearch/mojeek）——发现启动错误就清理对应条目。
5. 改完 `docker restart searxng`，重跑一轮 enginetest 复核。

## 阶段四：验证与固化

1. zh/en 各一条**综合查询**（带 `engines=` 指定 3-5 个引擎）：结果 ≥15 条、首条相关、`unresponsive_engines` 为空或只有已知禁用项。
2. **质量基线**：`bash scripts/benchmark.sh <base_url>`——8 个中英文真实查询的黄金域名命中评测（success@5）。≥75% 健康；50-75% 看 dead 标注哪个引擎拖后腿；<50% 回头检查网络地基。跑完把分数记进档案文档，作为这台机器的基线（出口变更/大升级后重跑对比）。注意黄金域名集有主观性（如中文技术内容 CSDN 是否算命中），MISS 时先看 top-5 实际域名再下结论。
3. `curl http://127.0.0.1:8080/stats/errors` 全绿或错误率个位数。
4. 在 `/opt/searxng/`（或对应卷目录）生成这台机器的档案文档：可用引擎清单（含实测日期）、推荐 engines 组合（中/英/学术/开发/新闻分场景）、已知风险引擎、`/stats` 观测方法、质量基线分数。模板参考 `scripts/profiles-template.md`。
5. 若公网暴露：`limiter: true`、配置反向代理 + botdetection（limiter.toml）、base_url 改公网地址。局域网/本机使用保持现状。

## 阶段五：接入 agent（MCP / skill）

searxng 的 JSON API 是免鉴权 HTTP 接口，接入原理 = 让 agent 能 GET `http://<host>:8080/search?q=..&format=json&language=..&engines=..`。按用户实际用的 agent 走（探测不到就问）：

- **ZCode / Claude Code 类（skill 体系）**：写一个小 skill 封装 curl 调用 + 档案文档里的引擎组合，装进用户的 skills 目录。
- **MCP 体系**：可用社区的 searxng MCP server（npm `mcp-searxng` 等，装前现场确认其维护状态），或用通用 fetch 桥注册 search 端点。配置文件格式变动快，现场按该 agent 当下的文档生成，本 skill 不固化格式。
- **任意程序**：直接 HTTP 调用，把档案文档作为使用说明书交付。

关键交接内容：必须把"带 `engines=` 参数查询、不要广撒网、结果同时看 `results` 和 `infoboxes`（wikipedia 类引擎的产出在后者）、检查 `unresponsive_engines`"写进接入说明。

## 附录一：引擎现实快照 [快照 2026-10，执行时必须重测]

- **机房 IP 友好**：duckduckgo（升级到 curl_cffi 镜像后）、brave、yep、wikipedia/wikidata（需 UA 后缀）、github（未认证 60 次/时）、npm、arxiv、mdn、stackoverflow、docker hub、bing（中文市场基本正常，英文市场对机房 IP 偶发"垃圾 SERP"）。
- **机房 IP 敌视/需住宅 IP**：google 主引擎（上游已默认禁用，wml 端点 403）、startpage/mojeek（上游因 Anubis 工作量证明直接 inactive）、qwant、presearch、reuters（拒机房 IP）、baidu（对自动化客户端必 CAPTCHA）、360search（必超时）。
- **google 替代**：`google cse` 引擎（免钥公共端点，时好时坏，实测决定去留）。

## 附录二：故障定性手册

| 症状 | 定性 | 处置 |
|---|---|---|
| 引擎 CAPTCHA/429 | 出口 IP 被该引擎标记 | 首轮即中→禁用；轰炸后出现→等待 10 分钟重测 |
| 200 但 0 结果无报错 | 软封锁"放毒"（喂空壳页）或上游解析失效 | 容器内手工 curl_cffi 对照（见阶段三），放毒→禁用，解析→升级镜像 |
| 结构正常但内容完全无关（本地商业页等） | 垃圾 SERP 放毒（bing 对机房 IP 的典型行为） | weight 0.5 或禁用，同组合加兜底引擎 |
| 大面积引擎同时挂 | 出口 IP 信誉崩了或 DNS 污染回归 | 查 `/stats/errors`、查 DNS 分支是否生效、等待或换出口 |
| 重启后一查询又被封 | 引擎侧封锁按 IP 记忆，重启只清本地挂起计时器 | 等待（180s~1h）或换出口，别反复重启 |
| wikipedia 403/429 | Wikimedia 拒绝机房 IP 上模拟浏览器的 UA | 确保 `useragent_suffix` 带联系方式（wikipedia 引擎用 searxng_useragent） |
| github 频繁 429 | 未认证 API 限 60 次/时 | 低频使用或配 token |

## 附录三：方法出处

本 SOP 提炼自一次完整的实机调优（armbian/2GB/Docker/墙内/自建 SG 节点，2026-10）与社区经验（SSDNodes "SearXNG engines to enable and disable on a VPS" 等）。核心增量：GFW 环境的 DNS fake-ip 地基、Wikimedia UA 政策、垃圾 SERP 定性、低频自校准流程。
