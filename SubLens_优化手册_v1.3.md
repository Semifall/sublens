# SubLens 优化手册 v1.3

## 一、Recognizer Pipeline

### 目标

采用 Hybrid Pipeline，但 Sprint 1 保持最小可运行版本（MVP）。

### Sprint 1

``` text
Normalize
↓
Fingerprint
↓
Rule Filter
↓
Prompt Builder
↓
LLM
↓
Decision
```

### Sprint 2

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

原则：

-   Fingerprint 负责候选商户识别
-   Rule Filter 负责硬过滤
-   AI 仅作为辅助评分器
-   Decision Engine 负责最终判定

------------------------------------------------------------------------

## 二、Confidence Fusion

### Sprint 1

采用可配置加权平均作为基线：

``` yaml
confidence:
  rule: 0.5
  fingerprint: 0.3
  ai: 0.2
```

计算：

``` text
final =
rule_score × 0.5 +
fingerprint_score × 0.3 +
ai_score × 0.2
```

### Sprint 2+

基于真实用户反馈升级为：

-   Logistic Regression
-   LightGBM
-   XGBoost

避免固定权重长期使用。

------------------------------------------------------------------------

## 三、Gmail Adapter

统一封装：

-   OAuth Refresh
-   Retry
-   Timeout
-   Exponential Backoff
-   Rate Limit
-   Error Mapping

建议异常：

-   GoogleAPIError
-   OAuthExpired
-   RateLimitError
-   NetworkTimeout

禁止业务层直接处理 Gmail SDK 异常。

------------------------------------------------------------------------

## 四、Database Schema

### Email

-   id
-   user_id
-   gmail_id
-   thread_id
-   sender
-   subject
-   snippet
-   received_at
-   created_at

### Recognition

-   id
-   email_id
-   merchant
-   price
-   currency
-   renewal
-   confidence
-   source
-   created_at

### Subscription

-   id
-   user_id
-   merchant
-   status
-   price
-   renewal
-   next_billing
-   confidence
-   created_at

建议索引：

-   gmail_id
-   user_id
-   merchant
-   next_billing

数据流：

``` text
Email
 ↓
Recognition
 ↓
Subscription
```

------------------------------------------------------------------------

## 五、移动端通信

推荐：

Flutter ↓ REST(JSON) ↓ FastAPI

原因：

-   简单
-   OpenAPI 自动生成 Client
-   Web 可复用
-   部署成熟

------------------------------------------------------------------------

## 六、补充设计

### 幂等性

-   scan_id
-   idempotency_key

避免重复扫描。

### 状态机

``` text
Detected
↓
Confirmed
↓
Active
↓
Canceled
```

### 可观测性

记录：

-   request_id
-   scan_id
-   latency
-   Gmail API Error Rate
-   AI Success Rate
-   Recognition Accuracy

------------------------------------------------------------------------

## Sprint 1 最终冻结范围

  模块         方案
  ------------ ------------------------------------
  Backend      FastAPI
  API          REST + Cursor 分页
  Gmail        OAuth2 + Adapter
  Recognizer   Hybrid MVP
  Confidence   可配置加权平均
  Database     Email → Recognition → Subscription
  Cache        预留 Redis
  Logging      全链路日志
  Scan         异步 Job
  Business     Free + Pro
