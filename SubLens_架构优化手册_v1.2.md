# SubLens 架构优化手册（v1.2）

## Repository

-   Monorepo：
    -   mobile/
    -   backend/
    -   docs/
    -   shared/
    -   scripts/
    -   tests/
-   backend 建议分层：
    -   api/
    -   core/
    -   models/
    -   schemas/
    -   services/
    -   recognizer/
    -   adapters/

原则： - Recognizer 不依赖 Gmail，实现 Adapter 抽象。

## API

推荐： `GET /emails?limit=50&cursor=xxx&fields=id,subject,sender,date`

Email DTO：

``` json
{
  "id":"",
  "thread_id":"",
  "subject":"",
  "sender":"",
  "snippet":"",
  "received_at":"",
  "labels":[]
}
```

body 默认不返回。

## Recognizer Pipeline

``` text
Normalize
↓
Fingerprint
↓
Merchant Retrieval
↓
Rule Filter
↓
Feature Extraction
↓
AI Scoring
↓
Confidence Fusion
↓
Decision
```

Feature 包括： - merchant_domain - price - renewal_cycle - currency -
unsubscribe_url - invoice_keyword

## Confidence Engine

不要写死权重。

输出：

``` json
{
  "rule_score":0.92,
  "merchant_score":0.80,
  "ai_score":0.76,
  "final":0.88
}
```

后续可升级 Logistic Regression 或 XGBoost。

## Rule Engine

采用 YAML：

``` yaml
merchant: netflix
match:
  - sender:
      contains:
        - netflix.com
  - subject:
      regex:
        - receipt
renew: monthly
confidence: 0.93
```

## Scan

异步：

-   POST /scan
-   GET /scan/{job_id}

状态： - Pending - Running - Completed - Failed

## Database

``` text
Email
 ↓
Recognition
 ↓
Subscription
```

## Cache

预留 Redis： - OAuth Token - Merchant - Rule - Cursor

## Logging

统一记录： - request_id - user_id - scan_id - email_id - merchant -
confidence - latency

## AI

AI 只负责提取：

``` json
{
  "merchant":"Netflix",
  "renewal":"Monthly",
  "price":"19.99",
  "confidence":0.71
}
```

Decision Engine 负责最终决策。

## 商业模式

-   Free
-   Pro：¥9.9/月
-   Pro：¥99/年
-   （可选）Lifetime：¥199

## Sprint 1 冻结范围

  模块         方案
  ------------ --------------------------------
  Repository   Monorepo
  Backend      FastAPI 分层
  Gmail        OAuth2 + Cursor 分页
  Recognizer   Hybrid Pipeline
  Rule         YAML
  Scan         异步 Job
  Database     Email→Recognition→Subscription
  Cache        Redis（可预留）
  Logging      全链路
  Business     Free + Pro
