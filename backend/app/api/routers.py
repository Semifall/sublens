from fastapi import APIRouter, BackgroundTasks, HTTPException, Query, Header
from pydantic import BaseModel, Field
from typing import List, Dict, Any, Optional
import uuid
import asyncio
from app.models.email import EmailListResponse
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
                # Keep the highest confidence and preserve trial status if present
                sub.confidence = max(existing.confidence, sub.confidence)
                if existing.status == SubscriptionStatus.TRIAL and sub.status == SubscriptionStatus.DETECTED:
                    sub.status = SubscriptionStatus.TRIAL
                
                sub.history = combined_history
            aggregated[merchant_key] = sub

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

        JOBS[job_id]["subscriptions"] = subs_list
        JOBS[job_id]["summary"] = {
            "monthly_cost": round(monthly_total, 2),
            "yearly_cost": round(yearly_total, 2),
            "subscription_count": len(subs_list)
        }
        JOBS[job_id]["status"] = "completed"
        JOBS[job_id]["progress"] = 100
        logger.info(f"Scan job {job_id} finished successfully. Found {len(subs_list)} subscriptions.")

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
        "summary": None
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
        total_emails=job.get("total_emails", 0)
    )
    
    if job["status"] == "completed":
        res.subscriptions = job.get("subscriptions")
        res.summary = job.get("summary")
        
    return res
