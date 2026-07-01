import os
import re
import yaml
import json
import httpx
import logging
from typing import Dict, Any, Optional, Tuple
from app.models.subscription import Email, Subscription, Recognition

logger = logging.getLogger(__name__)

class HybridRecognizer:
    def __init__(self, rules_path: Optional[str] = None, prompts_path: Optional[str] = None):
        base_dir = os.path.dirname(os.path.abspath(__file__))
        if not rules_path:
            rules_path = os.path.abspath(os.path.join(base_dir, "..", "..", "..", "shared", "merchant_rules", "rules.yaml"))
        if not prompts_path:
            prompts_path = os.path.abspath(os.path.join(base_dir, "..", "..", "..", "shared", "prompts", "subscription_parsing.txt"))
            
        self.rules_path = rules_path
        self.prompts_path = prompts_path
        self.rules = self._load_rules()
        
        # DeepSeek API Setup
        self.api_key = os.environ.get("DEEPSEEK_API_KEY")
        self.api_url = "https://api.deepseek.com/v1/chat/completions"

    def _load_rules(self) -> Dict[str, Any]:
        try:
            if os.path.exists(self.rules_path):
                with open(self.rules_path, "r", encoding="utf-8") as f:
                    return yaml.safe_load(f)
        except Exception as e:
            logger.error(f"Failed to load rules: {e}")
        return {"merchants": [], "general_keywords": {"positive": {}, "negative": {}}}

    # Step 1: Normalize
    def normalize_text(self, text: str) -> str:
        if not text:
            return ""
        text = text.lower()
        text = re.sub(r"\s+", " ", text)
        return text.strip()

    # Step 2: Fingerprint matching
    def match_fingerprint(self, email: Email) -> Tuple[Optional[str], float]:
        sender_lower = email.sender.lower()
        domain_match = re.search(r"@([\w\.-]+)", sender_lower)
        if not domain_match:
            return None, 0.0
            
        sender_domain = domain_match.group(1)
        for merchant in self.rules.get("merchants", []):
            for domain in merchant.get("domains", []):
                if sender_domain == domain or sender_domain.endswith("." + domain):
                    # Check subject keywords
                    normalized_subject = self.normalize_text(email.subject)
                    for kw in merchant.get("subject_keywords", []):
                        if kw.lower() in normalized_subject:
                            return merchant.get("name"), merchant.get("confidence", 0.9)
                    return merchant.get("name"), 0.40 # domain match only
        return None, 0.0

    # Step 3: Rule Filter
    def compute_rule_score(self, email: Email) -> float:
        score = 0.5
        normalized_subject = self.normalize_text(email.subject)
        normalized_snippet = self.normalize_text(email.snippet)
        combined_text = f"{normalized_subject} {normalized_snippet}"
        
        general_rules = self.rules.get("general_keywords", {})
        for kw, weight in general_rules.get("positive", {}).items():
            if kw.lower() in combined_text:
                score += weight
        for kw, weight in general_rules.get("negative", {}).items():
            if kw.lower() in combined_text:
                score += weight
        return max(0.0, min(1.0, score))

    # Step 4: Prompt Builder
    def build_ai_prompt(self, email: Email) -> str:
        # Fixed input structure required by v1.4
        input_data = {
            "subject": email.subject,
            "sender": email.sender,
            "snippet": email.snippet,
            "body_excerpt": email.snippet, # Using snippet for body excerpt in Sprint 1
            "headers": [
                {"name": "From", "value": email.sender},
                {"name": "Subject", "value": email.subject}
            ],
            "gmail_labels": ["INBOX", "CATEGORY_UPDATES"]
        }
        
        # Required prompt template
        template = (
            "You are a subscription detection system.\n\n"
            "Extract: - merchant - is_subscription (yes/no) - renewal type "
            "(monthly/yearly/one-time/unknown) - price - confidence (0-1)\n\n"
            f"Input JSON:\n{json.dumps(input_data, indent=2)}\n"
            "Respond strictly in JSON with keys: merchant, is_subscription, renewal, price, confidence."
        )
        return template

    # Step 5: LLM
    async def call_llm(self, prompt: str, email: Email) -> Dict[str, Any]:
        if not self.api_key:
            return self._mock_llm_response(email)
            
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                res = await client.post(
                    self.api_url,
                    headers={
                        "Authorization": f"Bearer {self.api_key}",
                        "Content-Type": "application/json"
                    },
                    json={
                        "model": "deepseek-chat",
                        "messages": [
                            {"role": "system", "content": "You are a precise JSON response generator."},
                            {"role": "user", "content": prompt}
                        ],
                        "temperature": 0.0,
                        "response_format": {"type": "json_object"}
                    }
                )
                if res.status_code == 200:
                    data = res.json()
                    content = data["choices"][0]["message"]["content"]
                    return json.loads(content)
        except Exception as e:
            logger.error(f"DeepSeek LLM call failed: {e}")
            
        return self._mock_llm_response(email)

    def _mock_llm_response(self, email: Email) -> Dict[str, Any]:
        combined = (email.subject + " " + email.snippet).lower()
        if "netflix" in combined:
            return {"merchant": "Netflix", "is_subscription": "yes", "renewal": "monthly", "price": 15.99, "confidence": 0.95}
        elif "spotify" in combined:
            return {"merchant": "Spotify", "is_subscription": "yes", "renewal": "monthly", "price": 9.99, "confidence": 0.95}
        elif "adobe" in combined:
            return {"merchant": "Adobe Creative Cloud", "is_subscription": "yes", "renewal": "monthly", "price": 52.99, "confidence": 0.95}
        elif "disney" in combined:
            return {"merchant": "Disney+", "is_subscription": "yes", "renewal": "monthly", "price": 7.99, "confidence": 0.90}
        elif "amazon" in combined:
            return {"merchant": "Amazon Prime", "is_subscription": "yes", "renewal": "monthly", "price": 14.99, "confidence": 0.90}
        elif "notion" in combined:
            return {"merchant": "Notion", "is_subscription": "yes", "renewal": "monthly", "price": 8.00, "confidence": 0.88}
        elif "youtube" in combined:
            return {"merchant": "YouTube Premium", "is_subscription": "yes", "renewal": "monthly", "price": 13.99, "confidence": 0.92}
        elif "medium" in combined:
            return {"merchant": "Medium Membership", "is_subscription": "yes", "renewal": "monthly", "price": 5.00, "confidence": 0.85}
        return {"merchant": "Unknown Service", "is_subscription": "no", "renewal": "unknown", "price": 0.0, "confidence": 0.10}

    # Step 6: Confidence Fusion
    def fuse_confidence(self, rule_score: float, fp_score: float, ai_score: float) -> float:
        # Configuration weights: final = rule * 0.5 + fingerprint * 0.3 + ai * 0.2
        return round(rule_score * 0.5 + fp_score * 0.3 + ai_score * 0.2, 2)

    # Step 7: Decision Maker
    async def recognize(self, email: Email) -> Tuple[Optional[Recognition], Optional[Subscription]]:
        # Pipeline execution
        # 1. Normalize
        norm_subject = self.normalize_text(email.subject)
        
        # 2. Fingerprint
        merchant_name_fp, fp_score = self.match_fingerprint(email)
        
        # 3. Rule Filter
        rule_score = self.compute_rule_score(email)
        
        # 4. Prompt Builder & 5. LLM
        prompt = self.build_ai_prompt(email)
        ai_res = await self.call_llm(prompt, email)
        
        ai_is_sub = ai_res.get("is_subscription", "no") == "yes"
        ai_score = ai_res.get("confidence", 0.0) if ai_is_sub else 0.1
        
        # 6. Confidence Fusion
        final_confidence = self.fuse_confidence(rule_score, fp_score, ai_score)
        
        # 7. Decision (Unknown -> Detected -> Confirmed -> Active -> Canceled)
        if final_confidence < 0.35:
            status = "unknown"
        elif final_confidence < 0.60:
            status = "detected"
        elif final_confidence < 0.80:
            status = "confirmed"
        else:
            status = "active"
            
        merchant = ai_res.get("merchant") or merchant_name_fp or "Unknown Service"
        price = ai_res.get("price") or 0.0
        renewal = ai_res.get("renewal") or "monthly"
        
        # Check cancellation indicators
        if "cancel" in norm_subject or "unsubscribe" in norm_subject or "refund" in norm_subject:
            status = "canceled"
            
        recognition = Recognition(
            id=f"rec_{email.id}",
            email_id=email.id,
            merchant=merchant,
            price=price,
            currency="USD",
            renewal=renewal,
            confidence=final_confidence,
            source="hybrid",
            created_at=email.created_at
        )
        
        subscription = None
        if status != "unknown":
            # Map next billing date to next month for mock simplicity
            next_billing = "2026-08-01"
            subscription = Subscription(
                id=f"sub_{email.id}",
                user_id=email.user_id,
                merchant=merchant,
                status=status,
                price=price,
                renewal=renewal,
                next_billing=next_billing,
                confidence=final_confidence,
                created_at=email.created_at
            )
            
        return recognition, subscription
