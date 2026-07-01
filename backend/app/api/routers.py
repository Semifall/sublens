import time
import uuid
import jwt
import logging
import asyncio
from datetime import datetime, timedelta
from fastapi import APIRouter, HTTPException, Query, Header, Depends
from pydantic import BaseModel
from typing import List, Dict, Any, Optional

from app.models.subscription import Email, Recognition, Subscription, GmailAccount, UserGmailLink
from app.core.recognizer import HybridRecognizer

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1")

# Custom App JWT secret key
JWT_SECRET = "sublens_secret_key_sprint_1"
JWT_ALGORITHM = "HS256"

# In-Memory DB Store
EMAILS: List[Email] = []
RECOGNITIONS: List[Recognition] = []
SUBSCRIPTIONS: List[Subscription] = []
GMAIL_ACCOUNTS: List[GmailAccount] = []
USER_GMAIL_LINKS: List[UserGmailLink] = []
SCAN_HISTORY: List[Dict[str, Any]] = []
JOBS: Dict[str, Dict[str, Any]] = {}

# Seeding default data for MVP Alex Demonstration
def seed_mock_data():
    uid = "u123"
    gmail_acc_id = "gm_alex"
    
    # Check if already seeded
    if len(GMAIL_ACCOUNTS) > 0:
        return
        
    GMAIL_ACCOUNTS.append(GmailAccount(
        id=gmail_acc_id,
        email="alex@gmail.com",
        oauth_provider="google",
        created_at=datetime.utcnow().isoformat()
    ))
    USER_GMAIL_LINKS.append(UserGmailLink(
        user_id=uid,
        gmail_account_id=gmail_acc_id
    ))
    
    # Add initial subscriptions
    initial_subs = [
        ("Netflix", 15.99, "monthly", "2026-07-15", "active"),
        ("Spotify", 9.99, "monthly", "2026-07-20", "active"),
        ("Adobe Creative Cloud", 52.99, "monthly", "2026-07-10", "active"),
        ("Disney+", 7.99, "monthly", "2026-07-12", "active"),
        ("Amazon Prime", 14.99, "monthly", "2026-07-18", "canceled"),
        ("Notion", 8.00, "monthly", "2026-07-25", "active"),
        ("YouTube Premium", 13.99, "monthly", "2026-07-28", "canceled"),
        ("Medium Membership", 5.00, "monthly", "2026-07-22", "active"),
    ]
    
    for name, price, cycle, next_b, status in initial_subs:
        SUBSCRIPTIONS.append(Subscription(
            id=f"sub_{uuid.uuid4().hex[:8]}",
            user_id=uid,
            merchant=name,
            status=status,
            price=price,
            renewal=cycle,
            next_billing=next_b,
            confidence=0.92 if status == "active" else 0.85,
            created_at=datetime.utcnow().isoformat()
        ))
        
    # Seed mock emails matching
    mock_emails_data = [
        ("no-reply@netflix.com", "Your Netflix membership invoice", "Your Spotify Premium renewal of $15.99 was processed on Netflix.", "Netflix"),
        ("billing@spotify.com", "Your Spotify Premium Invoice", "Spotify billing receipt: Spotify membership invoice totaling $9.99.", "Spotify"),
        ("accounts@adobe.com", "Your Adobe Creative Cloud Invoice details", "Adobe membership renewal update. Adobe Creative Cloud charge $52.99.", "Adobe Creative Cloud"),
    ]
    for sender, subject, snippet, merch in mock_emails_data:
        email_id = f"msg_{uuid.uuid4().hex[:8]}"
        EMAILS.append(Email(
            id=email_id,
            user_id=uid,
            gmail_id=f"g_{email_id}",
            thread_id=f"t_{email_id}",
            sender=sender,
            subject=subject,
            snippet=snippet,
            received_at=(datetime.utcnow() - timedelta(days=5)).isoformat(),
            created_at=datetime.utcnow().isoformat()
        ))
        RECOGNITIONS.append(Recognition(
            id=f"rec_{email_id}",
            email_id=email_id,
            merchant=merch,
            price=15.99 if "netflix" in sender else (9.99 if "spotify" in sender else 52.99),
            currency="USD",
            renewal="monthly",
            confidence=0.92,
            source="hybrid",
            created_at=datetime.utcnow().isoformat()
        ))

seed_mock_data()

# JWT Token Helper
def create_app_jwt(user_id: str, gmail_account_id: str) -> str:
    payload = {
        "user_id": user_id,
        "gmail_account_id": gmail_account_id,
        "exp": datetime.utcnow() + timedelta(minutes=15)
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)

def decode_app_jwt(token: str) -> Dict[str, Any]:
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="App JWT token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid App JWT token")

def get_current_user(authorization: Optional[str] = Header(None)) -> Dict[str, Any]:
    if not authorization or not authorization.startswith("Bearer "):
        # For development ease, fall back to default u123
        return {"user_id": "u123", "gmail_account_id": "gm_alex"}
    token = authorization.split(" ")[1]
    return decode_app_jwt(token)

# Auth Request Payload
class GoogleAuthRequest(BaseModel):
    google_oauth_token: str
    email: str
    name: str

class GoogleAuthResponse(BaseModel):
    jwt_token: str
    refresh_token: str
    email: str
    name: str

@router.post("/auth/google", response_model=GoogleAuthResponse)
async def auth_google(req: GoogleAuthRequest):
    """
    Exchanges a Google OAuth Token for an App JWT token and refresh token.
    Stores tokens and link tables as per Section VI & IX.
    """
    if req.google_oauth_token == "invalid_token":
        raise HTTPException(status_code=400, detail="Invalid Google OAuth token")
        
    user_id = "u123"
    gmail_id = f"gm_{req.email.split('@')[0]}"
    
    # Store Google account
    existing = [g for g in GMAIL_ACCOUNTS if g.email == req.email]
    if not existing:
        GMAIL_ACCOUNTS.append(GmailAccount(
            id=gmail_id,
            email=req.email,
            oauth_provider="google",
            created_at=datetime.utcnow().isoformat()
        ))
        USER_GMAIL_LINKS.append(UserGmailLink(
            user_id=user_id,
            gmail_account_id=gmail_id
        ))
    else:
        gmail_id = existing[0].id
        
    jwt_token = create_app_jwt(user_id, gmail_id)
    refresh_token = f"ref_{uuid.uuid4().hex}" # 30 days mock refresh
    
    return GoogleAuthResponse(
        jwt_token=jwt_token,
        refresh_token=refresh_token,
        email=req.email,
        name=req.name
    )

# Scan Job Endpoints
class ScanJobStartResponse(BaseModel):
    job_id: str
    status: str

class ScanJobStatusResponse(BaseModel):
    job_id: str
    status: str
    progress: int
    emails_scanned: int
    subscriptions_found: int
    time_elapsed: str

import threading

def simulate_scan_worker(job_id: str, user_id: str):
    """
    Background worker simulating scanning messages in chunks, calling recognizer pipeline.
    """
    JOBS[job_id]["status"] = "running"
    
    # Scan simulation steps
    steps = [10, 35, 60, 85, 100]
    total_emails = 2450
    subs_found = 8
    
    for progress in steps:
        time.sleep(0.02)
        JOBS[job_id]["progress"] = progress
        JOBS[job_id]["emails_scanned"] = int(total_emails * (progress / 100.0))
        JOBS[job_id]["subscriptions_found"] = int(subs_found * (progress / 100.0))
        
    JOBS[job_id]["status"] = "done"
    
    # Log scan execution in Scan History (Section VII & Prototype Screen 8)
    SCAN_HISTORY.insert(0, {
        "date": datetime.utcnow().strftime("%B %d, %Y at %I:%M %p"),
        "emails_scanned": total_emails,
        "subscriptions_found": subs_found,
        "status": "Completed"
    })

@router.post("/scan", response_model=ScanJobStartResponse)
async def start_scan(user = Depends(get_current_user)):
    """
    Triggers an asynchronous scan job.
    """
    job_id = f"job_{uuid.uuid4().hex[:8]}"
    JOBS[job_id] = {
        "job_id": job_id,
        "user_id": user["user_id"],
        "status": "pending",
        "progress": 0,
        "emails_scanned": 0,
        "subscriptions_found": 0,
        "time_elapsed": "01:32"
    }
    
    # Fire and forget background simulation using native thread
    thread = threading.Thread(target=simulate_scan_worker, args=(job_id, user["user_id"]))
    thread.start()
    
    return ScanJobStartResponse(job_id=job_id, status="pending")

@router.get("/scan/history")
async def get_scan_history():
    """
    Lists historical scans as shown in UI Screen 8.
    """
    if len(SCAN_HISTORY) == 0:
        return [
            {"date": "May 5, 2024 at 9:30 AM", "emails_scanned": 2450, "subscriptions_found": 8, "status": "Completed"},
            {"date": "Apr 28, 2024 at 8:15 AM", "emails_scanned": 2120, "subscriptions_found": 7, "status": "Completed"},
            {"date": "Apr 21, 2024 at 9:00 AM", "emails_scanned": 1960, "subscriptions_found": 6, "status": "Completed"},
            {"date": "Apr 14, 2024 at 10:30 AM", "emails_scanned": 1760, "subscriptions_found": 5, "status": "Completed"},
            {"date": "Apr 7, 2024 at 9:45 AM", "emails_scanned": 1200, "subscriptions_found": 3, "status": "Canceled"}
        ]
    return SCAN_HISTORY

@router.get("/scan/{job_id}", response_model=ScanJobStatusResponse)
async def get_scan_status(job_id: str):
    if job_id not in JOBS:
        raise HTTPException(status_code=404, detail="Scan job not found")
    job = JOBS[job_id]
    return ScanJobStatusResponse(
        job_id=job["job_id"],
        status=job["status"],
        progress=job["progress"],
        emails_scanned=job["emails_scanned"],
        subscriptions_found=job["subscriptions_found"],
        time_elapsed=job["time_elapsed"]
    )

# Subscription CRUD REST API
class SubscriptionListResponse(BaseModel):
    subscriptions: List[Subscription]
    monthly_spend: float
    active_count: int

@router.get("/subscriptions", response_model=SubscriptionListResponse)
async def list_subscriptions(user = Depends(get_current_user)):
    """
    Retrieves subscriptions, calculates totals as shown in Screen 3 & 5.
    """
    user_subs = [s for s in SUBSCRIPTIONS if s.user_id == user["user_id"]]
    active_count = len([s for s in user_subs if s.status == "active"])
    monthly_spend = sum([s.price for s in user_subs if s.status == "active"])
    
    return SubscriptionListResponse(
        subscriptions=user_subs,
        monthly_spend=round(monthly_spend, 2),
        active_count=active_count
    )

@router.get("/subscriptions/{id}")
async def get_subscription_detail(id: str):
    """
    Screen 6 Detail View of a subscription, returning detail with matched emails.
    """
    sub = next((s for s in SUBSCRIPTIONS if s.id == id), None)
    if not sub:
        raise HTTPException(status_code=404, detail="Subscription not found")
        
    # Get matched emails and recognitions
    matched_recs = [r for r in RECOGNITIONS if r.merchant.lower() in sub.merchant.lower()]
    email_ids = [r.email_id for r in matched_recs]
    matched_emails = [e for e in EMAILS if e.id in email_ids]
    
    if len(matched_emails) == 0:
        # Fallback to general Netflix emails for mockup completeness
        matched_emails = [
            Email(
                id="m1", user_id="u123", gmail_id="g1", thread_id="t1",
                sender=f"billing@{sub.merchant.lower().replace(' ', '')}.com",
                subject=f"Receipt from {sub.merchant}",
                snippet=f"Your subscription renewal details for {sub.merchant}.",
                received_at="Apr 15, 2024", created_at="Apr 15, 2024"
            ),
            Email(
                id="m2", user_id="u123", gmail_id="g2", thread_id="t2",
                sender=f"membership@{sub.merchant.lower().replace(' ', '')}.com",
                subject=f"{sub.merchant} Membership Confirmation",
                snippet=f"Thank you for keeping your {sub.merchant} active.",
                received_at="Mar 15, 2024", created_at="Mar 15, 2024"
            ),
            Email(
                id="m3", user_id="u123", gmail_id="g3", thread_id="t3",
                sender=f"billing@{sub.merchant.lower().replace(' ', '')}.com",
                subject=f"Your {sub.merchant} Invoice",
                snippet="Invoice details are now ready inside your inbox.",
                received_at="Feb 15, 2024", created_at="Feb 15, 2024"
            )
        ]
        
    return {
        "subscription": sub,
        "emails": matched_emails
    }

@router.post("/subscriptions/{id}/cancel")
async def cancel_subscription(id: str):
    """
    Cancellations handler matching Section III state machine.
    """
    sub = next((s for s in SUBSCRIPTIONS if s.id == id), None)
    if not sub:
        raise HTTPException(status_code=404, detail="Subscription not found")
        
    sub.status = "canceled"
    return {"status": "success", "subscription": sub}

# Insights Endpoint
@router.get("/insights")
async def get_insights(user = Depends(get_current_user)):
    """
    Aggregates data for prototype Screen 9.
    """
    user_subs = [s for s in SUBSCRIPTIONS if s.user_id == user["user_id"] and s.status == "active"]
    
    # Calculate categories spend
    categories = {
        "Entertainment": 0.0,
        "Productivity": 0.0,
        "Music": 0.0,
        "Other": 0.0
    }
    
    for s in user_subs:
        m = s.merchant.lower()
        if "netflix" in m or "disney" in m or "youtube" in m:
            categories["Entertainment"] += s.price
        elif "adobe" in m or "notion" in m:
            categories["Productivity"] += s.price
        elif "spotify" in m:
            categories["Music"] += s.price
        else:
            categories["Other"] += s.price
            
    # Round category figures
    categories = {k: round(v, 2) for k, v in categories.items()}
    
    # Monthly spend trend list
    trend = [
        {"month": "Dec", "amount": 112.50},
        {"month": "Jan", "amount": 120.00},
        {"month": "Feb", "amount": 120.00},
        {"month": "Mar", "amount": 134.48},
        {"month": "Apr", "amount": 134.48},
        {"month": "May", "amount": 142.47}
    ]
    
    return {
        "categories": categories,
        "spend_trend": trend,
        "total_saved": 24.50,
        "canceled_count": 2
    }
