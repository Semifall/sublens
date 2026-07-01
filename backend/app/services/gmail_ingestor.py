import httpx
from typing import List, Dict, Any, Optional, Tuple
from app.models.email import Email
import logging

logger = logging.getLogger(__name__)

class GmailIngestor:
    def __init__(self, access_token: Optional[str] = None):
        self.access_token = access_token
        self.headers = {"Authorization": f"Bearer {access_token}"} if access_token else {}
        self.base_url = "https://gmail.googleapis.com/gmail/v1/users/me"

    async def fetch_emails(self, limit: int = 50, cursor: Optional[str] = None) -> Tuple[List[Email], Optional[str]]:
        """
        Fetches email headers from Gmail API, or returns mock data if token is 'mock_token' or not provided.
        """
        if not self.access_token or self.access_token == "mock_token":
            return self._get_mock_emails(limit, cursor)

        # Real Gmail API implementation
        try:
            # Query only bills and receipts to minimize latency and token count
            # Keywords matching standard subscription receipt patterns
            query = "subject:(receipt OR invoice OR bill OR subscription OR renew OR payment OR charge OR 订阅 OR 账单 OR 自动续费 OR 扣款 OR 续订 OR 收据 OR 发票)"
            params = {
                "maxResults": limit,
                "q": query
            }
            if cursor:
                params["pageToken"] = cursor

            async with httpx.AsyncClient(timeout=10.0) as client:
                # 1. List messages
                list_res = await client.get(
                    f"{self.base_url}/messages",
                    headers=self.headers,
                    params=params
                )
                if list_res.status_code != 200:
                    logger.error(f"Gmail list messages failed: {list_res.text}")
                    return [], None

                list_data = list_res.json()
                messages = list_data.get("messages", [])
                next_page_token = list_data.get("nextPageToken")

                if not messages:
                    return [], None

                # 2. Batch fetch metadata
                emails = []
                for msg in messages:
                    msg_id = msg["id"]
                    # Fetch only headers and snippet (format=metadata)
                    msg_res = await client.get(
                        f"{self.base_url}/messages/{msg_id}",
                        headers=self.headers,
                        params={"format": "metadata", "metadataHeaders": ["Subject", "From", "Date"]}
                    )
                    if msg_res.status_code == 200:
                        msg_data = msg_res.json()
                        snippet = msg_data.get("snippet", "")
                        headers = msg_data.get("payload", {}).get("headers", [])
                        
                        subject = ""
                        sender = ""
                        date = ""
                        
                        for h in headers:
                            name = h.get("name", "").lower()
                            if name == "subject":
                                subject = h.get("value", "")
                            elif name == "from":
                                sender = h.get("value", "")
                            elif name == "date":
                                date = h.get("value", "")
                        
                        emails.append(Email(
                            id=msg_id,
                            subject=subject,
                            sender=sender,
                            snippet=snippet,
                            date=date
                        ))
                
                return emails, next_page_token

        except Exception as e:
            logger.error(f"Error fetching from Gmail API: {str(e)}")
            # Fail gracefully, could return empty list or fallback
            return [], None

    def _get_mock_emails(self, limit: int = 50, cursor: Optional[str] = None) -> Tuple[List[Email], Optional[str]]:
        """
        Generates realistic mock emails for local testing and developer validation.
        """
        all_mock_emails = [
            # Netflix - Active Monthly Subscription
            Email(
                id="msg_netflix_01",
                sender="Netflix <info@netflix.com>",
                subject="Your Netflix Invoice for June 2026",
                snippet="Thanks for watching. Your subscription auto-renewed on 2026-06-15. Amount charged: CNY 98.00. Payment method: Alipay.",
                date="Mon, 15 Jun 2026 08:00:00 +0800"
            ),
            Email(
                id="msg_netflix_02",
                sender="Netflix <info@netflix.com>",
                subject="Your Netflix Invoice for May 2026",
                snippet="Thanks for watching. Your subscription auto-renewed on 2026-05-15. Amount charged: CNY 98.00. Payment method: Alipay.",
                date="Fri, 15 May 2026 08:00:00 +0800"
            ),
            # Spotify - Active Monthly Subscription
            Email(
                id="msg_spotify_01",
                sender="Spotify <no-reply@spotify.com>",
                subject="Your Premium Family receipt",
                snippet="Spotify Premium Family. Billing date: 2026-06-20. Total: CNY 68.00. Payment will recur monthly unless cancelled.",
                date="Sat, 20 Jun 2026 12:30:00 +0800"
            ),
            Email(
                id="msg_spotify_02",
                sender="Spotify <no-reply@spotify.com>",
                subject="Your Premium Family receipt",
                snippet="Spotify Premium Family. Billing date: 2026-05-20. Total: CNY 68.00. Payment will recur monthly.",
                date="Wed, 20 May 2026 12:30:00 +0800"
            ),
            # Claude - Active Monthly USD Subscription
            Email(
                id="msg_claude_01",
                sender="Anthropic <support@anthropic.com>",
                subject="Claude Pro subscription payment receipt #108932",
                snippet="Receipt for your Claude Pro subscription. Paid: USD 20.00 on June 25, 2026. This subscription will automatically renew on July 25, 2026.",
                date="Thu, 25 Jun 2026 15:45:00 +0000"
            ),
            # ChatGPT - Active Monthly USD Subscription
            Email(
                id="msg_chatgpt_01",
                sender="OpenAI <billing@openai.com>",
                subject="Your OpenAI billing receipt for ChatGPT Plus",
                snippet="Your invoice for ChatGPT Plus subscription has been paid successfully. Amount: USD 20.00. Auto-renews on July 22, 2026.",
                date="Mon, 22 Jun 2026 10:10:00 +0000"
            ),
            # YouTube Premium - Active Monthly Subscription
            Email(
                id="msg_youtube_01",
                sender="Google <googlemyaccount-noreply@google.com>",
                subject="Your YouTube Premium subscription receipt",
                snippet="Thanks for your membership. Charged CNY 15.00 to your credit card on 2026-06-01. Manage your subscription at google.com/subscriptions.",
                date="Mon, 01 Jun 2026 09:00:00 +0800"
            ),
            # Non-subscription email: Welcome / Newsletter (Should be pruned/ignored)
            Email(
                id="msg_spam_01",
                sender="GitHub <noreply@github.com>",
                subject="Welcome to GitHub! Let's get started.",
                snippet="We're glad to have you on board. Start creating repositories or explore public code projects.",
                date="Wed, 17 Jun 2026 14:00:00 +0800"
            ),
            # Non-subscription email: Password reset (Should be pruned/ignored)
            Email(
                id="msg_spam_02",
                sender="Steam Support <noreply@steampowered.com>",
                subject="Your Steam account password reset request",
                snippet="Verification code: 89432. Use this code to reset your account password. If you didn't request this, ignore.",
                date="Tue, 23 Jun 2026 19:15:00 +0800"
            ),
            # Boundary case: One-time payment (Should not be marked as recurring subscription)
            Email(
                id="msg_onetime_01",
                sender="Steam <noreply@steampowered.com>",
                subject="Thank you for your Steam purchase!",
                snippet="You have purchased: Cyberpunk 2077 - CNY 298.00. One-time credit card charge. Subtotal: CNY 298.00.",
                date="Thu, 11 Jun 2026 21:00:00 +0800"
            ),
            # Boundary case: Trial activation email (Requires AI / Rule to identify trial)
            Email(
                id="msg_trial_01",
                sender="Setapp <no-reply@setapp.com>",
                subject="Your Setapp 7-day free trial has started!",
                snippet="Welcome to Setapp. Your free trial ends on July 5, 2026. After that, your chosen monthly plan of USD 9.99 will begin automatically.",
                date="Sun, 28 Jun 2026 08:30:00 +0000"
            )
        ]
        
        # Paginate mock data simple mockup
        start_idx = 0
        if cursor:
            try:
                start_idx = int(cursor)
            except ValueError:
                start_idx = 0
                
        sliced_emails = all_mock_emails[start_idx:start_idx + limit]
        next_cursor = None
        if start_idx + limit < len(all_mock_emails):
            next_cursor = str(start_idx + limit)
            
        return sliced_emails, next_cursor
