from pydantic import BaseModel, Field
from typing import List, Optional
from enum import Enum

class BillingCycle(str, Enum):
    MONTHLY = "monthly"
    YEARLY = "yearly"
    ONE_TIME = "one-time"
    UNKNOWN = "unknown"

class SubscriptionStatus(str, Enum):
    UNKNOWN = "unknown"
    DETECTED = "detected"
    ACTIVE = "active"
    PRICE_CHANGED = "price_changed"
    TRIAL = "trial"
    PAUSED = "paused"
    CANCELLED = "cancelled"

class Money(BaseModel):
    amount: float
    currency: str = "CNY"

class Subscription(BaseModel):
    id: Optional[str] = None
    merchant: str
    price: Money
    billing_cycle: BillingCycle
    confidence: float = Field(..., ge=0.0, le=1.0)
    emails_count: int = 1
    last_seen: str
    status: SubscriptionStatus = SubscriptionStatus.DETECTED

class SubscriptionListResponse(BaseModel):
    subscriptions: List[Subscription]
    monthly_cost: float
    yearly_cost: float
    subscription_count: int
