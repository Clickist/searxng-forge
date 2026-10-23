# SearXNG 搜索档案 —— <主机名/位置>（实测 <日期>）

> 本文档由 searxng-forge 自校准流程生成，反映**这台机器当前网络条件**下的引擎现实。
> 引擎生态会变，隔一两个月或出口变更后重跑自校准刷新本文。

Base URL: http://<host>:8080/search
调用必带 `format=json` + `language` + `engines=`（**不带 engines= 的查询会打全部 90+ 引擎，触发集体风控**）。

## 本机引擎现实

- 稳定可用：
- 可用但有风险（放毒史/偶发）：
- 已禁用及原因：
- 健康观测：`/stats`（页面）、`/stats/errors`（JSON）

## 场景组合（按实测结果填写）

| 场景 | engines 组合 | 备注 |
|---|---|---|
| 中文综合 | duckduckgo,bing,wikipedia | |
| 英文综合 | duckduckgo,brave,yep | |
| 学术 | arxiv,semantic scholar,pubmed | |
| 开发 | github,npm,mdn,stackoverflow | |
| 新闻 | bing news,duckduckgo news,brave.news | |

## 调用注意

- wikipedia/wikidata 的结果在 `infoboxes` 字段（实体卡片），与 `results` 合并消费。
- 每次响应检查 `unresponsive_engines`，失败的引擎降级处理，别硬等。
- 引擎突然集体失败 → 先看 `/stats/errors`，多半是出口 IP 信誉，等 10 分钟再试，不要连发。
