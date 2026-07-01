# Project Constitution (项目宪法)

This document defines the core architecture, data schemas, design constraints, and developer rules for the **Sublens (Subscription Guard)** project. All development (including code changes made by AI agents) must strictly adhere to these rules.

---

## 1. Single Source of Truth (唯一真源)
*   **Backend API = Single Source of Truth**: The Backend API is the absolute source of truth for all business logic, statistics, status definitions, and subscription calculations.
*   **No UI Mock Business Data**: The mobile client or web frontend is NOT allowed to mock business calculations, monthly/yearly aggregation formulas, or subscription metrics. It must display only what is returned by the API.
*   **Recognizer Enclosure**: The `Recognizer` decision engine is a backend-only detail. It is never exposed directly to the UI; UI interacts solely through the scan job API endpoints.

## 2. Strict Restrictions (禁止行为 - AI 必须遵守)
*   **No Unapproved API Endpoints**: Do not add new API endpoints without explicit confirmation.
*   **No Unapproved Fields**: Do not add extra fields to database tables or API request/response schemas unless explicitly requested and confirmed.
*   **Frozen State Machines**: Do not alter the defined `Scan` lifecycle or `Subscription` lifecycle state machines.
*   **Frozen Data Structures**: Do not modify existing core entity shapes or models.

## 3. Forced Flow (强制结构)
All project flows, UI pathways, and services must align under this strict logical chain:
$$\text{Auth} \longrightarrow \text{Scan} \longrightarrow \text{Subscription} \longrightarrow \text{Detail}$$
Any new feature, check, or notification must be attached as a sub-component or hook on this explicit logical flow.

## 4. Data Structure Freeze (数据结构冻结)
The core `Subscription` entity is frozen to the following fields only. Do not add or change fields:
*   `id`: unique identifier (or null if pending local save)
*   `merchant`: name of the merchant service
*   `price`: Money object containing `amount` (float) and `currency` (string)
*   `status`: Subscription status string (`trial`, `active`, `price_changed`, `paused`, `cancelled`, `unknown`)
*   `confidence`: float score representing the confidence value (0.0 to 1.0)

## 5. UI Binding Rules (UI 绑定规则)
*   **Strict API Response Mapping**: The UI is a pure renderer of the API responses (`UI = API response mapping`).
*   **No Derived UI Logic**: The UI is forbidden from executing its own heuristic logic, parsing currency symbols, determining cycles, or calculating sums. Everything must be derived from the structured backend response.
