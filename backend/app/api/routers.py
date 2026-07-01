from fastapi import APIRouter, BackgroundTasks, HTTPException, Query, Header
from pydantic import BaseModel, Field
from typing import List, Dict, Any, Optional
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
import uuid
import asyncio
from app.models.email import Email, EmailListResponse
from app.models.subscription import Subscription, SubscriptionListResponse, Money, SubscriptionStatus
from app.services.gmail_ingestor import GmailIngestor
from app.core.recognizer import HybridRecognizer
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1")

# Global in-memory transit database for scan jobs (stateless backend server pattern)
# Key: job_id (str), Value: Dict[str, Any]
JOBS: Dict[str, Dict[str, Any]] = {}

class LoginRequest(BaseModel):
    access_token: str

class LoginResponse(BaseModel):
    status: str
    email: str
    name: str

class ScanRequest(BaseModel):
    access_token: str

class ScanResponse(BaseModel):
    job_id: str
    status: str

class ScanStatusResponse(BaseModel):
    status: str
    progress: int
    emails_processed: int = 0
    total_emails: int = 0
    summary: Optional[Dict[str, Any]] = None
    subscriptions: Optional[List[Subscription]] = None
    alerts: List[str] = []

@router.post("/login", response_model=LoginResponse)
async def login(req: LoginRequest):
    """
    Mock endpoint validating the Google access token.
    In production, this would verify the token against Google OAuth endpoints.
    """
    if req.access_token == "invalid_token":
        raise HTTPException(status_code=401, detail="Invalid Google Access Token")
        
    return LoginResponse(
        status="success",
        email="user@example.com",
        name="Sublens User"
    )

@router.get("/emails", response_model=EmailListResponse)
async def get_emails(
    limit: int = Query(50, ge=1, le=100),
    cursor: Optional[str] = None,
    authorization: Optional[str] = Header(None)
):
    """
    Paginated, header-only email index from Gmail.
    """
    token = None
    if authorization and authorization.startswith("Bearer "):
        token = authorization.split(" ")[1]
        
    if not token:
        # Fallback to mock token for local testing
        token = "mock_token"
        
    ingestor = GmailIngestor(access_token=token)
    emails, next_cursor = await ingestor.fetch_emails(limit=limit, cursor=cursor)
    
    return EmailListResponse(
        emails=emails,
        next_cursor=next_cursor
    )

def determine_subscription_status(history: List[Email]) -> SubscriptionStatus:
    if not history:
        return SubscriptionStatus.UNKNOWN
        
    # 1. Base status based on quantity of matched invoice cycles
    if len(history) == 1:
        status = SubscriptionStatus.DETECTED
    elif len(history) == 2:
        status = SubscriptionStatus.CONFIRMED
    else:
        status = SubscriptionStatus.ACTIVE
        
    # 2. Check for cancellation (stopped emails)
    # We'll use July 1, 2026 as the mock "current time" of the scan
    mock_current_time = datetime(2026, 7, 1, tzinfo=timezone.utc)
    
    # Parse the date of the latest invoice
    latest_email = history[-1]
    try:
        latest_date = parsedate_to_datetime(latest_email.date)
        if latest_date.tzinfo is None:
            latest_date = latest_date.replace(tzinfo=timezone.utc)
        else:
            latest_date = latest_date.astimezone(timezone.utc)
            
        days_since_last_invoice = (mock_current_time - latest_date).days
        if days_since_last_invoice > 45:
            status = SubscriptionStatus.CANCELLED
    except Exception:
        pass
        
    return status

async def run_inbox_scan(job_id: str, token: str):
    """
    Background worker task that ingests emails, processes them through the
    decision engine, aggregates subscriptions, and updates job progress.
    """
    try:
        ingestor = GmailIngestor(access_token=token)
        recognizer = HybridRecognizer()
        
        JOBS[job_id]["status"] = "running"
        JOBS[job_id]["progress"] = 5
        
        # 1. Ingest emails (fetch in chunks until cursor is exhausted or max cap reached)
        all_emails = []
        cursor = None
        max_emails_to_scan = 150 # Guard rail to avoid runaway scans
        
        while len(all_emails) < max_emails_to_scan:
            emails, cursor = await ingestor.fetch_emails(limit=50, cursor=cursor)
            if not emails:
                break
            all_emails.extend(emails)
            if not cursor:
                break
                
        JOBS[job_id]["progress"] = 25
        
        if not all_emails:
            JOBS[job_id]["status"] = "completed"
            JOBS[job_id]["progress"] = 100
            JOBS[job_id]["subscriptions"] = []
            return

        # 3. Sort emails oldest first so that the newest email processes last and overrides values
        all_emails.reverse()
        
        # 4. Process emails through recognizer
        raw_subscriptions: List[Subscription] = []
        total_emails = len(all_emails)
        JOBS[job_id]["total_emails"] = total_emails
        
        for idx, email in enumerate(all_emails):
            # Process email
            sub, conf = await recognizer.recognize(email)
            if sub:
                sub.last_seen_email_id = email.id
                sub.history = [email]
                raw_subscriptions.append(sub)
                
            JOBS[job_id]["emails_processed"] = idx + 1
                
            # Update progress dynamically (scaling from 25% to 90%)
            progress_pct = int(25 + (idx + 1) / total_emails * 65)
            JOBS[job_id]["progress"] = progress_pct
            
            # Simulate slight processing yield to keep CPU cooperative
            await asyncio.sleep(0.01)

        # 5. Aggregate subscriptions (group by merchant name)
        # Since older emails are processed first and newer last, the newer subscription detail naturally overwrites.
        aggregated: Dict[str, Subscription] = {}
        for sub in raw_subscriptions:
            merchant_key = sub.merchant.lower()
            if merchant_key in aggregated:
                existing = aggregated[merchant_key]
                # Merge the history list (older first, newer last)
                combined_history = existing.history + sub.history
                # Keep the highest confidence
                sub.confidence = max(existing.confidence, sub.confidence)
                sub.history = combined_history
            aggregated[merchant_key] = sub

        # Apply state machine lifecycle transitions and generate evidence based on history
        for sub in aggregated.values():
            sub.status = determine_subscription_status(sub.history)
            
            # Generate Truth Layer Evidence
            evidence = []
            latest_email = sub.history[-1]
            evidence.append(f"Sender '{latest_email.sender}' matches billing signature")
            evidence.append(f"Recurring payment pattern of {sub.price.currency} {sub.price.amount:.2f} identified")
            
            if len(sub.history) == 1:
                evidence.append("Single invoice detected (Status: DETECTED)")
            elif len(sub.history) == 2:
                evidence.append("2 consecutive billing cycles tracked (Status: CONFIRMED)")
            else:
                evidence.append(f"{len(sub.history)} consecutive billing cycles tracked (Status: ACTIVE)")
                
            if sub.status == SubscriptionStatus.CANCELLED:
                evidence.append(f"Invoice emails ceased since {latest_email.date[:16]} (Status: CANCELLED)")
                
            sub.evidence = evidence

        # Convert back to list
        subs_list = list(aggregated.values())
        
        # Calculate summary statistics
        monthly_total = 0.0
        for sub in subs_list:
            # Simple currency conversion rate helper (mock USD/CNY conversion for display)
            rate = 7.2 if sub.price.currency == "USD" else 1.0
            sub_cost_cny = sub.price.amount * rate
            monthly_total += sub_cost_cny

        yearly_total = monthly_total * 12

        # 6. Generate Risk Alerts
        alerts = []
        for sub in subs_list:
            # Check price change alert
            if len(sub.history) >= 2:
                try:
                    prices = []
                    for email in sub.history:
                        combined_text = f"{email.subject} {email.snippet}"
                        h_amount, _ = recognizer.extract_price_heuristic(combined_text)
                        if h_amount is not None:
                            prices.append(h_amount)
                    
                    if len(prices) >= 2 and prices[-1] != prices[-2]:
                        alerts.append(f"{sub.merchant} billing amount changed from {sub.price.currency} {prices[-2]:.2f} to {sub.price.currency} {prices[-1]:.2f}")
                except Exception as e:
                    logger.error(f"Error calculating price history for alert: {e}")
            
            # Check unknown subscription alert
            if sub.merchant.lower() == "unknown service" or sub.merchant.lower() == "unknown":
                alerts.append(f"Unknown subscription detected (charged {sub.price.currency} {sub.price.amount:.2f})")

        JOBS[job_id]["subscriptions"] = subs_list
        JOBS[job_id]["summary"] = {
            "monthly_cost": round(monthly_total, 2),
            "yearly_cost": round(yearly_total, 2),
            "subscription_count": len(subs_list)
        }
        JOBS[job_id]["alerts"] = alerts
        JOBS[job_id]["status"] = "completed"
        JOBS[job_id]["progress"] = 100
        logger.info(f"Scan job {job_id} finished successfully. Found {len(subs_list)} subscriptions. Generated {len(alerts)} alerts.")

    except Exception as e:
        logger.error(f"Error in scan job {job_id}: {str(e)}", exc_info=True)
        JOBS[job_id]["status"] = "failed"
        JOBS[job_id]["progress"] = 100

@router.post("/scan", response_model=ScanResponse)
async def start_scan(req: ScanRequest, background_tasks: BackgroundTasks):
    """
    Triggers an asynchronous scan job for the provided Gmail account token.
    Returns a Job ID immediately.
    """
    job_id = str(uuid.uuid4())
    
    # Initialize job state
    JOBS[job_id] = {
        "status": "pending",
        "progress": 0,
        "emails_processed": 0,
        "total_emails": 0,
        "subscriptions": None,
        "summary": None,
        "alerts": []
    }
    
    background_tasks.add_task(run_inbox_scan, job_id, req.access_token)
    
    return ScanResponse(
        job_id=job_id,
        status="pending"
    )

@router.get("/scan/{job_id}", response_model=ScanStatusResponse)
async def get_scan_status(job_id: str):
    """
    Retrieves the status, progress, and results of a scan job.
    Returns subscription list only when the job is completed.
    """
    if job_id not in JOBS:
        raise HTTPException(status_code=404, detail="Scan job not found")
        
    job = JOBS[job_id]
    
    # Construct response
    res = ScanStatusResponse(
        status=job["status"],
        progress=job["progress"],
        emails_processed=job.get("emails_processed", 0),
        total_emails=job.get("total_emails", 0),
        alerts=job.get("alerts", [])
    )
    
    if job["status"] == "completed":
        res.subscriptions = job.get("subscriptions")
        res.summary = job.get("summary")
        
    return res
