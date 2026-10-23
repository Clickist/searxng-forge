#!/usr/bin/env bash
# searxng-forge 质量基线 —— 小型黄金域名评测（success@5 + 引擎健康）。
# 方法：每个查询有一组"期望命中域名"（权威站点），检查 top-5 结果是否命中。
# 这不是学术 benchmark，是"这台机器此刻的检索质量"的可复现快照，用于调优前后对比与长期回归。
# 用法: benchmark.sh <base_url> [--quick]
set -u
BASE="${1:-http://127.0.0.1:8080}"
QUICK="${2:-}"
GAP=6

# 查询集：query|language|engines|期望域名(逗号分隔)
CASES=(
  "智谱AI GLM|zh-CN|duckduckgo,bing,wikipedia|zhipuai.cn,bigmodel.cn,zhihu.com,wikipedia.org"
  "英伟达 股价|zh-CN|duckduckgo,bing,yep|eastmoney.com,xueqiu.com,finance.sina.com.cn,investing.com,nasdaq.com"
  "NVDA stock price|en-US|duckduckgo,brave,yep|finance.yahoo.com,marketwatch.com,nasdaq.com,investing.com"
  "React useEffect cleanup|en-US|duckduckgo,google%20cse,mdn|react.dev,developer.mozilla.org"
  "docker compose healthcheck example|en-US|duckduckgo,google%20cse,stackoverflow|docs.docker.com,stackoverflow.com,github.com"
  "Attention Is All You Need paper|en-US|duckduckgo,arxiv|arxiv.org,neurips.cc,semanticscholar.org"
  "transformer 模型 原理|zh-CN|duckduckgo,bing,wikipedia|zhihu.com,wikipedia.org,juejin.cn,cnblogs.com"
  "python asyncio gather exception|en-US|duckduckgo,google%20cse,stackoverflow|docs.python.org,stackoverflow.com,realpython.com"
)
[ "$QUICK" = "--quick" ] && CASES=("React useEffect cleanup|en-US|duckduckgo,google%20cse,mdn|react.dev,developer.mozilla.org" "智谱AI GLM|zh-CN|duckduckgo,bing,wikipedia|zhipuai.cn,bigmodel.cn,zhihu.com,wikipedia.org")

total=0; hit=0; alive=0; dead=0
echo "# searxng-forge quality baseline  base=$BASE"
printf '%-34s %-4s %-6s %s\n' "QUERY" "S@5" "RES" "HIT-DOMAIN / UNRESPONSIVE"
echo "------------------------------------------------------------------"

for case in "${CASES[@]}"; do
  IFS='|' read -r q lang engines gold <<<"$case"
  qq=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$q")
  out=$(curl -s -m 30 "$BASE/search?q=$qq&format=json&language=$lang&engines=$engines" 2>/dev/null)
  if [ -z "$out" ]; then printf '%-34s %-4s\n' "${q:0:32}" "ERR"; dead=$((dead+1)); total=$((total+1)); sleep "$GAP"; continue; fi
  read -r s5 nres note < <(printf '%s' "$out" | python3 -c "
import json,sys
gols='''$gold'''.split(',')
gols=[g.strip() for g in gols]
try:
    d=json.load(sys.stdin)
    rs=d.get('results',[])+d.get('infoboxes',[])
    doms=[]
    for r in rs[:5]:
        u=r.get('url','') or r.get('id','')
        dom=u.split('/')[2] if '://' in u else u
        doms.append(dom.lower())
    hitany=[g for g in gols if any(g in x for x in doms)]
    ur=[(x[0] if isinstance(x,list) else x.get('name')) for x in d.get('unresponsive_engines',[])]
    note=(hitany[0] if hitany else '-') + (' | dead:' + ','.join(ur) if ur else '')
    print(('PASS' if hitany else 'MISS'), len(rs), note.replace(' ','_'))
except Exception as e:
    print('ERR', 0, str(e)[:40].replace(' ','_'))
")
  total=$((total+1))
  [ "$s5" = "PASS" ] && { hit=$((hit+1)); alive=$((alive+1)); } || dead=$((dead+1))
  printf '%-34s %-4s %-6s %s\n' "${q:0:32}" "$s5" "$nres" "$(echo "$note" | tr '_' ' ')"
  sleep "$GAP"
done

pct=$(( hit * 100 / total ))
echo "------------------------------------------------------------------"
echo "# success@5: ${hit}/${total} = ${pct}%   查询失败/未命中: ${dead}"
echo "# 提示: >=75% 健康; 50-75% 有引擎拖后腿(看 dead 标注); <50% 检查网络地基或重跑自校准"
