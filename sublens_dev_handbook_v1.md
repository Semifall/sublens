# SubLens 开发手册（v1.0）

> Know every subscription. Save every dollar.

---

## 0. 项目本质

SubLens 是一个通过 Gmail 自动识别订阅支出的系统。

---

## 1. MVP 定义

### 目标
30 秒告诉用户一年订阅花费。

### 不做
- Feed
- AI Insight
- OCR
- 多邮箱
- 自动取消
- 推送
- Web 端

### 只做
- Google 登录
- Gmail 读取
- 订阅识别
- Dashboard

---

## 2. 架构

Flutter App → FastAPI Backend → Gmail API → Recognizer → Subscription JSON → UI

---

## 3. 仓库结构

sublens/
- mobile/
- backend/
- docs/
- shared/
  - merchant_rules/
  - prompts/
- scripts/
- README.md

---

## 4. Sprint 1

### 目标
读取 Gmail 邮件

### API
GET /emails

### 返回
{
  "emails": [
    {
      "subject": "Your Netflix receipt",
      "sender": "netflix@mail.com",
      "date": "2026-07-01"
    }
  ]
}

### 成功标准
- Google 登录
- Gmail 读取
- 邮件列表展示

---

## 5. Sprint 2

识别订阅：

Normalize → Fingerprint → Merchant → Rule → Confidence

输出：
{
  "merchant": "Netflix",
  "is_subscription": true,
  "confidence": 0.95,
  "cycle": "monthly"
}

---

## 6. Sprint 3

AI 只用于：
- unknown merchant
- low confidence
- conflict

---

## 7. Sprint 4

Dashboard + 上线

---

## 8. Recognizer

Email → Normalize → Fingerprint → Rule → AI → Confidence → Subscription

---

## 9. 数据模型

Subscription:
- merchant
- amount
- cycle
- confidence
- last_seen

Email:
- subject
- sender
- fingerprint

Scan:
- status
- progress

---

## 10. API

POST /login
GET /emails
POST /scan
GET /subscriptions
GET /subscription/{id}

---

## 11. 技术约束

- Backend stateless
- No email stored server
- AI cost < ¥0.05/user
- Codebase < 15k lines

---

## 12. 商业模型

Free:
- 1 scan/year

Pro:
- unlimited scans
- AI insights
- report

价格：¥49–¥99 一次性

---

## 13. 开发顺序

1. Repo
2. Gmail OAuth
3. Email fetch
4. Flutter login
5. Rule engine
6. Subscription detection
7. Dashboard
8. AI
9. Release
