import httpx
import random
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
        Randomized values simulate a dynamic inbox scanner.
        """
        # 1. Base required subscriptions (always present, but prices slightly vary)
        netflix_price = 98.0 + random.randint(-10, 10)
        spotify_price = 68.0 + random.randint(-5, 5)
        claude_price = 20.0 + random.randint(-2, 2)
        chatgpt_price = 20.0 + random.randint(-2, 2)
        youtube_price = 15.0 + random.randint(-2, 2)
        
        all_mock_emails = [
            # Netflix
            Email(
                id="msg_netflix_01",
                sender="Netflix <info@netflix.com>",
                subject="Your Netflix Invoice for June 2026",
                snippet=f"Thanks for watching. Your subscription auto-renewed on 2026-06-15. Amount charged: CNY {netflix_price:.2f}. Payment method: Alipay.",
                date="Mon, 15 Jun 2026 08:00:00 +0800"
            ),
            # Spotify
            Email(
                id="msg_spotify_01",
                sender="Spotify <no-reply@spotify.com>",
                subject="Your Premium Family receipt",
                snippet=f"Spotify Premium Family. Billing date: 2026-06-20. Total: CNY {spotify_price:.2f}. Payment will recur monthly.",
                date="Sat, 20 Jun 2026 12:30:00 +0800"
            ),
            # Claude
            Email(
                id="msg_claude_01",
                sender="Anthropic <support@anthropic.com>",
                subject="Claude Pro subscription payment receipt #108932",
                snippet=f"Receipt for your Claude Pro subscription. Paid: USD {claude_price:.2f} on June 25, 2026. Auto-renews July 25.",
                date="Thu, 25 Jun 2026 15:45:00 +0000"
            ),
            # ChatGPT
            Email(
                id="msg_chatgpt_01",
                sender="OpenAI <billing@openai.com>",
                subject="Your OpenAI billing receipt for ChatGPT Plus",
                snippet=f"Your invoice for ChatGPT Plus subscription has been paid successfully. Amount: USD {chatgpt_price:.2f}. Auto-renews on July 22.",
                date="Mon, 22 Jun 2026 10:10:00 +0000"
            ),
            # YouTube Premium
            Email(
                id="msg_youtube_01",
                sender="Google <googlemyaccount-noreply@google.com>",
                subject="Your YouTube Premium subscription receipt",
                snippet=f"Thanks for your membership. Charged CNY {youtube_price:.2f} to your credit card on 2026-06-01.",
                date="Mon, 01 Jun 2026 09:00:00 +0800"
            ),
            # Non-subscription email (ignored)
            Email(
                id="msg_spam_01",
                sender="GitHub <noreply@github.com>",
                subject="Welcome to GitHub! Let's get started.",
                snippet="We're glad to have you on board. Start creating repositories or explore public code projects.",
                date="Wed, 17 Jun 2026 14:00:00 +0800"
            ),
            # Boundary case: One-time payment (ignored)
            Email(
                id="msg_onetime_01",
                sender="Steam <noreply@steampowered.com>",
                subject="Thank you for your Steam purchase!",
                snippet="You have purchased: Cyberpunk 2077 - CNY 298.00. One-time credit card charge.",
                date="Thu, 11 Jun 2026 21:00:00 +0800"
            ),
        ]

        # 2. Dynamic optional subscriptions (random chance to appear per scan)
        
        # Adobe Creative Cloud (60% chance)
        if random.random() < 0.6:
            adobe_price = 320.0 + random.randint(-20, 40)
            all_mock_emails.append(Email(
                id="msg_adobe_01",
                sender="Adobe Billing <invoice@adobe.com>",
                subject="Your Adobe Creative Cloud invoice is ready",
                snippet=f"Your monthly subscription of Adobe Creative Cloud has renewed. Charged: CNY {adobe_price:.2f}.",
                date="Sun, 14 Jun 2026 11:00:00 +0800"
            ))

        # Notion Personal Pro (50% chance)
        if random.random() < 0.5:
            notion_price = 8.0 + random.randint(0, 4)
            all_mock_emails.append(Email(
                id="msg_notion_01",
                sender="Notion <billing@notion.so>",
                subject="Notion Invoice for Personal Pro Plan",
                snippet=f"Thank you for choosing Notion. Your Personal Pro plan was renewed. Amount: USD {notion_price:.2f}.",
                date="Fri, 12 Jun 2026 07:30:00 +0000"
            ))

        # GitHub Copilot (60% chance)
        if random.random() < 0.6:
            copilot_price = 10.0 if random.random() < 0.7 else 19.0
            all_mock_emails.append(Email(
                id="msg_copilot_01",
                sender="GitHub <billing@github.com>",
                subject="Your GitHub Copilot payment receipt",
                snippet=f"Thanks for using GitHub Copilot! We successfully processed your monthly charge of USD {copilot_price:.2f}.",
                date="Thu, 18 Jun 2026 16:20:00 +0800"
            ))

        # Midjourney (40% chance)
        if random.random() < 0.4:
            midjourney_price = 30.0 if random.random() < 0.8 else 60.0
            all_mock_emails.append(Email(
                id="msg_midjourney_01",
                sender="Midjourney Billing <billing@midjourney.com>",
                subject="Receipt for your Midjourney Subscription",
                snippet=f"Payment for Midjourney Basic/Standard Plan has been processed. Total paid: USD {midjourney_price:.2f}.",
                date="Wed, 10 Jun 2026 09:15:00 +0000"
            ))

        # 3. Handle simple pagination
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
