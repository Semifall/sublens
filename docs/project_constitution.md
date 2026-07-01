# Project Constitution (项目宪法)

本文件定义了 **Sublens (Subscription Guard)** 项目的核心架构、数据结构模型、设计约束和开发规范。所有后续开发（包括 AI 助手及人工编码）都必须严格遵守这些规则。

---

## 1. 唯一真源（Single Source of Truth）
*   **Backend API = 唯一数据源**：后端 API 是所有业务逻辑、数值计算、状态界定和订阅统计的绝对真源。
*   **UI 禁绝 mock 业务数据**：前端（Flutter App 或 Web）不允许在本地模拟月度/年度聚合、价格换算等业务数据，必须直接展示 API 返回的结果。
*   **决策引擎封装**：`Recognizer` 模块是后端的内部实现细节，绝对不允许直接暴露给 UI。UI 只能通过 Scan 扫描任务状态机接口进行间接交互。

## 2. 禁止行为（AI 必须遵守）
*   ❌ **不允许新增 API**：未经确认，严禁随意增加新的 API 接口。
*   ❌ **不允许新增字段**：未经确认，严禁修改 API 请求/响应模型或本地数据库字段。
*   ❌ **不允许修改状态机**：严禁更改已有的 `Scan` 扫描状态机和 `Subscription` 订阅状态机生命周期。
*   ❌ **不允许改变数据结构**：严禁更改已锁定的核心实体模型。

## 3. 强制结构
项目的所有交互、页面流转和核心服务必须挂在以下链路上：
$$\text{Auth (登录)} \longrightarrow \text{Scan (扫描)} \longrightarrow \text{Subscription (订阅列表)} \longrightarrow \text{Detail (详情)} $$
任何新增功能（如价格提醒、降级指引等）必须作为此链路的子模块或生命周期钩子进行挂接。

## 4. 数据结构冻结
核心 `Subscription` 实体的数据结构冻结为以下字段，严禁增删：
1.  `id`：唯一标识符
2.  `merchant`：商家名称
3.  `price`：包含 `amount`（数值）和 `currency`（币种）的 Money 对象
4.  `status`：订阅状态 (`detected`, `confirmed`, `active`, `cancelled`, `unknown`)
5.  `confidence`：置信度得分 (0.0 - 1.0)
6.  `last_seen_email_id`：最新识别的账单邮件 ID
7.  `history`：贡献该订阅的所有 Email 对象列表（交易历史追溯链）

## 5. UI 绑定规则
*   **UI = API response mapping**：前端的角色是 API 响应的纯渲染层。
*   **禁止 UI 自己推导逻辑**：UI 不得在本地进行复杂的逻辑推导、汇总金额、推测周期或手动匹配货币符号，一切以 API 响应提供的结构化数据为准。
