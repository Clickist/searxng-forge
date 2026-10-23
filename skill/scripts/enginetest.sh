#!/usr/bin/env bash
# searxng-forge 引擎自校准 —— 单引擎串行、强制间隔，绝不全引擎广撒网（会触发集体风控）。
# 用法: enginetest.sh <base_url> [en|zh]
set -u
BASE="${1:-http://127.0.0.1:8080}"
LANG_MODE="${2:-en}"
GAP=6   # 引擎间隔秒数，别低于 5

case "$LANG_MODE" in
  en)
    QUERY="openai%20gpt"
    LANGUAGE="en-US"
    ENGINES=(duckduckgo brave yep bing "google%20cse" wikipedia github npm arxiv mdn stackoverflow "duckduckgo%20news")
    ;;
  zh)
    QUERY="%E6%99%BA%E8%B0%B1AI%20GLM"
    LANGUAGE="zh-CN"
    ENGINES=(duckduckgo bing wikipedia "baidu%20kaifa" sogou "bing%20news" "duckduckgo%20news")
    ;;
  *) echo "usage: $0 <base_url> [en|zh]"; exit 1 ;;
esac

echo "# engine self-calibration: lang=$LANG_MODE base=$BASE gap=${GAP}s"
echo "# 判定标准见 SKILL.md 阶段三：>=5 相关结果=可用；CAPTCHA=IP 敌视或等待；持续超时=禁用；0 结果无报错=需手工对照"
echo

for e in "${ENGINES[@]}"; do
  label="${e//%20/ }"
  out=$(curl -s -m 30 "$BASE/search?q=$QUERY&format=json&language=$LANGUAGE&engines=$e" 2>/dev/null)
  if [ -z "$out" ]; then
    printf '%-18s EMPTY-RESPONSE\n' "$label"
  else
    printf '%s\n' "$out" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    rs=d.get("results",[])+d.get("infoboxes",[])
    ur=[]
    for x in d.get("unresponsive_engines",[]):
        n=x[0] if isinstance(x,list) else x.get("name")
        er=(x[1] if isinstance(x,list) else x.get("error")) or ""
        ur.append(f"{n}({str(er)[:28]})")
    top=(rs[0]["title"][:38] if rs else "-")
    print(f"{len(rs):>3} res | {top} | " + ("; ".join(ur) if ur else "ok"))
except Exception as ex:
    print("PARSE-FAIL", ex)
' | { read -r line; printf '%-18s %s\n' "$label" "$line"; }
  fi
  sleep "$GAP"
done

echo
echo "# next: bash $0 $BASE $([ "$LANG_MODE" = en ] && echo zh || echo en)  # 跑另一语言轮"
