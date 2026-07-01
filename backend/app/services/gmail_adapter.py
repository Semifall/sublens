import time
import random
import logging
from typing import Dict, Any, List

logger = logging.getLogger(__name__)

# Standardized exceptions
class GmailAdapterError(Exception):
    """Base exception for Gmail Adapter"""
    pass

class GoogleAPIError(GmailAdapterError):
    """Raised when Google API returns a non-200 error code or invalid structure"""
    pass

class OAuthExpired(GmailAdapterError):
    """Raised when the OAuth token is expired and cannot be refreshed"""
    pass

class RateLimitError(GmailAdapterError):
    """Raised when hitting Google's rate limits (HTTP 429)"""
    pass

class NetworkTimeout(GmailAdapterError):
    """Raised when connection/read times out"""
    pass

class GmailAdapter:
    def __init__(self, client_id: str = "mock_client", client_secret: str = "mock_secret", refresh_token: str = "mock_refresh"):
        self.client_id = client_id
        self.client_secret = client_secret
        self.refresh_token = refresh_token
        self.access_token = "mock_access_token"
        self.token_expiry = time.time() + 3600

    def refresh_oauth_token(self) -> str:
        """
        Simulates OAuth token refresh with retry and timeout checks.
        """
        logger.info("Attempting to refresh Google OAuth token...")
        # Simulate rate-limiting or random API network failure for robustness demonstration
        if random.random() < 0.05:
            raise RateLimitError("Rate limit exceeded on OAuth token server.")
        
        self.access_token = f"refreshed_token_{int(time.time())}"
        self.token_expiry = time.time() + 900 # 15 minutes App JWT matching, but token active 1 hour
        logger.info(f"Token successfully refreshed: {self.access_token}")
        return self.access_token

    def execute_api_call_with_retry(self, operation_name: str, params: Dict[str, Any], max_retries: int = 3) -> Dict[str, Any]:
        """
        统一封装 API 调用，实现：
        - OAuth Refresh
        - Retry
        - Timeout
        - Rate Limit Handling
        - Exponential Backoff
        """
        # Ensure token is fresh
        if time.time() >= self.token_expiry:
            try:
                self.refresh_oauth_token()
            except Exception as e:
                raise OAuthExpired(f"OAuth refresh failed: {e}")

        backoff = 0.5
        for attempt in range(1, max_retries + 1):
            try:
                # Simulate timeout behavior
                if params.get("simulate_timeout", False):
                    raise NetworkTimeout("Connection timed out to googleapis.com")

                # Simulate rate limiting
                if params.get("simulate_rate_limit", False):
                    raise RateLimitError("API quota limits reached")

                # Mock execution
                logger.info(f"Executing Google API call {operation_name} (Attempt {attempt})...")
                
                # Default mock success responses
                if operation_name == "list_messages":
                    return {
                        "messages": [
                            {"id": "msg_01", "threadId": "th_01"},
                            {"id": "msg_02", "threadId": "th_02"}
                        ],
                        "resultSizeEstimate": 2
                    }
                elif operation_name == "get_message":
                    msg_id = params.get("id", "msg_01")
                    return {
                        "id": msg_id,
                        "threadId": f"th_{msg_id.split('_')[-1]}",
                        "labelIds": ["INBOX", "CATEGORY_UPDATES"],
                        "snippet": "Your subscription invoice for Spotify Premium of $9.99 is ready.",
                        "payload": {
                            "headers": [
                                {"name": "From", "value": "no-reply@spotify.com"},
                                {"name": "Subject", "value": "Your Spotify Invoice"}
                            ]
                        }
                    }
                
                return {"status": "success"}

            except RateLimitError as re:
                if attempt == max_retries:
                    raise re
                sleep_time = backoff * (2 ** (attempt - 1)) + random.uniform(0, 0.1)
                logger.warning(f"RateLimitError encountered. Backing off for {sleep_time:.2f}s...")
                time.sleep(sleep_time)
            except NetworkTimeout as nt:
                if attempt == max_retries:
                    raise nt
                sleep_time = backoff * (2 ** (attempt - 1))
                logger.warning(f"NetworkTimeout encountered. Retrying in {sleep_time:.2f}s...")
                time.sleep(sleep_time)
            except Exception as e:
                raise GoogleAPIError(f"Unexpected API structure exception: {e}")

        raise GoogleAPIError("Failed all execution attempts.")
