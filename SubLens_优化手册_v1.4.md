# SubLens 优化手册 v1.4（最终 Sprint 1 冻结版）

## 一、Recognizer Pipeline（Sprint 1）

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

说明： - Feature Extraction 暂不引入 - Merchant Retrieval 延后到 Sprint
2 - AI 仅作为辅助分类器

------------------------------------------------------------------------

## 二、Prompt Builder（关键新增）

### 输入结构（必须固定）

``` json
{
  "subject": "",
  "sender": "",
  "snippet": "",
  "body_excerpt": "",
  "headers": [],
  "gmail_labels": []
}
```

### Prompt 模板

You are a subscription detection system.

Extract: - merchant - is_subscription (yes/no) - renewal type
(monthly/yearly/one-time/unknown) - price - confidence (0-1)

------------------------------------------------------------------------

## 三、Subscription 状态机（补全 Unknown）

``` text
Unknown
  ↓
Detected
  ↓
Confirmed
  ↓
Active
  ↓
Canceled
```

说明： - Unknown：AI 不确定 / confidence \< threshold -
Detected：可能订阅但未确认 - Confirmed：规则或用户确认 -
Active：生效订阅 - Canceled：取消

------------------------------------------------------------------------

## 四、Confidence Fusion（Sprint 1）

采用可配置权重：

``` yaml
confidence:
  rule: 0.5
  fingerprint: 0.3
  ai: 0.2
```

计算：

final = rule \* 0.5 + fingerprint \* 0.3 + ai \* 0.2

Sprint 2 再升级 ML 模型（Logistic / XGBoost）。

------------------------------------------------------------------------

## 五、Gmail Adapter（必须工业级）

统一封装：

-   OAuth Refresh
-   Retry
-   Timeout
-   Rate Limit Handling
-   Exponential Backoff

异常标准化：

-   GoogleAPIError
-   OAuthExpired
-   RateLimitError
-   NetworkTimeout

禁止业务层直接调用 Gmail SDK。

------------------------------------------------------------------------

## 六、Auth（OAuth + JWT 分离）

### Flow

Google OAuth → Backend → Store Tokens → Issue JWT → Mobile

### Token体系

-   Google OAuth Token：访问 Gmail
-   App JWT：访问系统

### JWT

``` json
{
  "user_id": "",
  "gmail_account_id": "",
  "exp": 1234567890
}
```

推荐： - JWT：15 min - Refresh Token：30 days

------------------------------------------------------------------------

## 七、Scan 异步 Job（禁止 BackgroundTasks）

### 推荐实现

Sprint 1： - Redis Queue (RQ)

Sprint 2： - Celery + Redis

### Job结构

``` json
{
  "job_id": "",
  "user_id": "",
  "status": "pending|running|done|failed",
  "progress": 0
}
```

------------------------------------------------------------------------

## 八、Database Schema（必须冻结）

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

### GmailAccount（新增）

-   id
-   email
-   oauth_provider
-   created_at

### user_gmail_link（新增）

-   user_id
-   gmail_account_id

------------------------------------------------------------------------

## 九、多用户隔离模型

结构：

User ↓ User_Gmail_Link ↓ GmailAccount ↓ Emails

说明： - 一个 Gmail 可绑定多个用户 - 支持家庭 / 企业 / 测试账号

------------------------------------------------------------------------

## 十、移动端通信

推荐：

Flutter → REST(JSON) → FastAPI

原因： - 简单 - 可生成 OpenAPI Client - 易扩展

------------------------------------------------------------------------

## 十一、可观测性（最小要求）

记录：

-   request_id
-   scan_id
-   email_id
-   latency
-   confidence
-   error_type

------------------------------------------------------------------------

## 十二、Sprint 1 冻结范围

  模块         方案
  ------------ ------------------------------------
  Backend      FastAPI
  API          REST + Cursor
  Gmail        OAuth2 + Adapter
  Recognizer   Hybrid MVP
  Prompt       固定结构
  Confidence   可配置加权
  Scan         RQ
  Database     Email → Recognition → Subscription
  Auth         JWT + OAuth 分离
  Multi-user   GmailAccount + Link Table
  Logging      基础链路
  Business     Free + Pro
