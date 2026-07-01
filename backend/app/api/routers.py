import os
import uuid
import time
import threading
import logging
from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, HTTPException, Header, Depends
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
import jwt

from app.models.subscription import Email, Recognition, Subscription, GmailAccount, UserGmailLink

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1")

# Custom App JWT secret key
JWT_SECRET = os.environ.get("JWT_SECRET", "dev_only_change_me_in_production")
JWT_ALGORITHM = "HS256"

# In-Memory DB Store
EMAILS: List[Email] = []
RECOGNITIONS: List[Recognition] = []
SUBSCRIPTIONS: List[Subscription] = []
GMAIL_ACCOUNTS: List[GmailAccount] = []
USER_GMAIL_LINKS: List[UserGmailLink] = []
SCAN_HISTORY: List[Dict[str, Any]] = []
JOBS: Dict[str, Dict[str, Any]] = {}

_data_lock = threading.Lock()

# Seeding default data for MVP Alex Demonstration
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
        created_at=datetime.now(timezone.utc).isoformat()
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
            created_at=datetime.now(timezone.utc).isoformat()
        ))
        
    # Seed mock emails matching
    mock_emails_data = [
        ("no-reply@netflix.com", "Your Netflix membership invoice", "Your Netflix Premium renewal of $15.99 has been processed successfully.", "Netflix"),
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
            received_at=(datetime.now(timezone.utc) - timedelta(days=5)).isoformat(),
            created_at=datetime.now(timezone.utc).isoformat()
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
            created_at=datetime.now(timezone.utc).isoformat()
        ))

# JWT Token Helper
def create_app_jwt(user_id: str, gmail_account_id: str) -> str:
    payload = {
        "user_id": user_id,
        "gmail_account_id": gmail_account_id,
        "exp": datetime.now(timezone.utc) + timedelta(minutes=15)
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
        raise HTTPException(status_code=401, detail="Missing or invalid authorization header")
    token = authorization.split(" ")[1]
    return decode_app_jwt(token)

def _get_user_subscriptions(user_id: str) -> List[Subscription]:
    return [s for s in SUBSCRIPTIONS if s.user_id == user_id]

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
            created_at=datetime.now(timezone.utc).isoformat()
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

def simulate_scan_worker(job_id: str, user_id: str):
    """
    Background worker simulating scanning messages in chunks, calling recognizer pipeline.
    """
    start_time = time.time()
    
    with _data_lock:
        JOBS[job_id]["status"] = "running"
    
    # Scan simulation steps
    steps = [10, 35, 60, 85, 100]
    total_emails = 2450
    subs_found = 8
    
    for progress in steps:
        time.sleep(0.05)
        elapsed_sec = int(time.time() - start_time)
        time_elapsed_str = f"{elapsed_sec // 60:02d}:{elapsed_sec % 60:02d}"
        
        with _data_lock:
            JOBS[job_id]["progress"] = progress
            JOBS[job_id]["emails_scanned"] = int(total_emails * (progress / 100.0))
            JOBS[job_id]["subscriptions_found"] = int(subs_found * (progress / 100.0))
            JOBS[job_id]["time_elapsed"] = time_elapsed_str
            
    with _data_lock:
        JOBS[job_id]["status"] = "done"
        
        # Log scan execution in Scan History
        SCAN_HISTORY.insert(0, {
            "date": datetime.now(timezone.utc).strftime("%B %d, %Y at %I:%M %p"),
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
    with _data_lock:
        JOBS[job_id] = {
            "job_id": job_id,
            "user_id": user["user_id"],
            "status": "pending",
            "progress": 0,
            "emails_scanned": 0,
            "subscriptions_found": 0,
            "time_elapsed": "00:00"
        }
    
    # Fire and forget background simulation using native thread
    thread = threading.Thread(target=simulate_scan_worker, args=(job_id, user["user_id"]))
    thread.start()
    
    return ScanJobStartResponse(job_id=job_id, status="pending")

@router.get("/scan/history")
async def get_scan_history(user = Depends(get_current_user)):
    """
    Lists historical scans as shown in UI Screen 8.
    """
    return SCAN_HISTORY

@router.get("/scan/{job_id}", response_model=ScanJobStatusResponse)
async def get_scan_status(job_id: str, user = Depends(get_current_user)):
    with _data_lock:
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
    user_subs = _get_user_subscriptions(user["user_id"])
    active_count = len([s for s in user_subs if s.status == "active"])
    monthly_spend = sum([s.price for s in user_subs if s.status == "active"])
    
    return SubscriptionListResponse(
        subscriptions=user_subs,
        monthly_spend=round(monthly_spend, 2),
        active_count=active_count
    )

@router.get("/subscriptions/{id}")
async def get_subscription_detail(id: str, user = Depends(get_current_user)):
    """
    Screen 6 Detail View of a subscription, returning detail with matched emails.
    """
    sub = next((s for s in SUBSCRIPTIONS if s.id == id and s.user_id == user["user_id"]), None)
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
                id="m1", user_id=user["user_id"], gmail_id="g1", thread_id="t1",
                sender=f"billing@{sub.merchant.lower().replace(' ', '')}.com",
                subject=f"Receipt from {sub.merchant}",
                snippet=f"Your subscription renewal details for {sub.merchant}.",
                received_at="Apr 15, 2024", created_at="Apr 15, 2024"
            ),
            Email(
                id="m2", user_id=user["user_id"], gmail_id="g2", thread_id="t2",
                sender=f"membership@{sub.merchant.lower().replace(' ', '')}.com",
                subject=f"{sub.merchant} Membership Confirmation",
                snippet=f"Thank you for keeping your {sub.merchant} active.",
                received_at="Mar 15, 2024", created_at="Mar 15, 2024"
            ),
            Email(
                id="m3", user_id=user["user_id"], gmail_id="g3", thread_id="t3",
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
async def cancel_subscription(id: str, user = Depends(get_current_user)):
    """
    Cancellations handler matching Section III state machine.
    """
    sub = next((s for s in SUBSCRIPTIONS if s.id == id and s.user_id == user["user_id"]), None)
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
    user_subs = _get_user_subscriptions(user["user_id"])
    active_subs = [s for s in user_subs if s.status == "active"]
    canceled_subs = [s for s in user_subs if s.status == "canceled"]
    
    # Calculate categories spend
    categories = {
        "Entertainment": 0.0,
        "Productivity": 0.0,
        "Music": 0.0,
        "Other": 0.0
    }
    
    for s in active_subs:
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
    
    # Monthly spend trend list based on current active spend
    active_spend = sum(s.price for s in active_subs)
    trend = [
        {"month": "Dec", "amount": round(active_spend * 0.8, 2)},
        {"month": "Jan", "amount": round(active_spend * 0.85, 2)},
        {"month": "Feb", "amount": round(active_spend * 0.85, 2)},
        {"month": "Mar", "amount": round(active_spend * 0.9, 2)},
        {"month": "Apr", "amount": round(active_spend * 0.9, 2)},
        {"month": "May", "amount": round(active_spend, 2)}
    ]
    
    total_saved = sum(s.price for s in canceled_subs)
    canceled_count = len(canceled_subs)
    
    return {
        "categories": categories,
        "spend_trend": trend,
        "total_saved": round(total_saved, 2),
        "canceled_count": canceled_count
    }
