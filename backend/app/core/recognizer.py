import os
import re
import yaml
import json
import httpx
import logging
from typing import Dict, Any, Optional, Tuple
from app.models.email import Email
from app.models.subscription import Subscription, Money, BillingCycle, SubscriptionStatus

logger = logging.getLogger(__name__)

class HybridRecognizer:
    def __init__(self, rules_path: Optional[str] = None, prompts_path: Optional[str] = None):
        # Resolve paths relative to this file if not specified
        base_dir = os.path.dirname(os.path.abspath(__file__))
        
        if not rules_path:
            rules_path = os.path.abspath(os.path.join(base_dir, "..", "..", "..", "shared", "merchant_rules", "rules.yaml"))
        if not prompts_path:
            prompts_path = os.path.abspath(os.path.join(base_dir, "..", "..", "..", "shared", "prompts", "subscription_parsing.txt"))
            
        self.rules_path = rules_path
        self.prompts_path = prompts_path
        self.rules = self._load_rules()
        self.prompt_template = self._load_prompt_template()
        
        # DeepSeek API Setup
        self.api_key = os.environ.get("DEEPSEEK_API_KEY")
        self.api_url = "https://api.deepseek.com/v1/chat/completions"

    def _load_rules(self) -> Dict[str, Any]:
        try:
            if os.path.exists(self.rules_path):
                with open(self.rules_path, "r", encoding="utf-8") as f:
                    return yaml.safe_load(f)
            logger.warning(f"Rules file not found at {self.rules_path}. Using empty rules.")
        except Exception as e:
            logger.error(f"Failed to load rules from {self.rules_path}: {e}")
        return {"merchants": [], "general_keywords": {"positive": {}, "negative": {}}}

    def _load_prompt_template(self) -> str:
        try:
            if os.path.exists(self.prompts_path):
                with open(self.prompts_path, "r", encoding="utf-8") as f:
                    return f.read()
            logger.warning(f"Prompt template file not found at {self.prompts_path}.")
        except Exception as e:
            logger.error(f"Failed to load prompt template from {self.prompts_path}: {e}")
        return ""

    def normalize_text(self, text: str) -> str:
        """
        Cleans and normalizes email subject/snippet text to lowercase,
        removing excessive whitespace and special characters.
        """
        if not text:
            return ""
        text = text.lower()
        # Replace newlines/tabs with space
        text = re.sub(r"\s+", " ", text)
        return text.strip()

    def extract_price_heuristic(self, text: str) -> Tuple[Optional[float], str]:
        """
        Extracts price and currency from text using heuristic regex.
        Returns (amount, currency).
        """
        # Currency mappings
        currency_symbols = {
            "$": "USD",
            "￥": "CNY",
            "¥": "CNY",
            "€": "EUR",
            "£": "GBP",
            "cny": "CNY",
            "usd": "USD",
            "eur": "EUR",
            "gbp": "GBP"
        }
        
        # Regex to find currency symbols and amounts: e.g. $15.99, CNY 98.00, ￥68
        pattern = r"(cny|usd|eur|gbp|￥|¥|\$)\s*(\d+(?:\.\d{2})?)|(\d+(?:\.\d{2})?)\s*(cny|usd|eur|gbp|元)"
        matches = re.findall(pattern, text, re.IGNORECASE)
        
        if matches:
            # Check the first match
            match = matches[0]
            if match[0]: # Prefix currency match: ($)(15.99)
                symbol = match[0].lower()
                amount_str = match[1]
            else: # Suffix currency match: (15.99)(cny)
                amount_str = match[2]
                symbol = match[3].lower() if match[3] else "元"
            
            try:
                amount = float(amount_str)
                currency = currency_symbols.get(symbol, "CNY")
                if symbol == "元":
                    currency = "CNY"
                return amount, currency
            except ValueError:
                pass
                
        return None, "CNY"

    def match_fingerprint(self, email: Email) -> Tuple[Optional[Dict[str, Any]], float]:
        """
        Matches email sender domain against known merchants in rules.yaml.
        Returns (matched_merchant_dict, fingerprint_confidence).
        """
        sender_lower = email.sender.lower()
        
        # Extract domain from email sender: e.g. "Netflix <info@netflix.com>" -> "netflix.com"
        domain_match = re.search(r"@([\w\.-]+)", sender_lower)
        if not domain_match:
            return None, 0.0
        
        sender_domain = domain_match.group(1)
        
        for merchant in self.rules.get("merchants", []):
            for domain in merchant.get("domains", []):
                # Match domain exactly or as subdomain
                if sender_domain == domain or sender_domain.endswith("." + domain):
                    # Domain matched. Check keywords in subject to avoid match on marketing emails.
                    normalized_subject = self.normalize_text(email.subject)
                    keyword_match = False
                    for kw in merchant.get("subject_keywords", []):
                        if kw.lower() in normalized_subject:
                            keyword_match = True
                            break
                    
                    if keyword_match:
                        # High confidence for matched domain and subject keywords
                        return merchant, merchant.get("confidence", 0.90)
                    else:
                        # Medium confidence for domain match without receipt keywords
                        return merchant, 0.40
                        
        return None, 0.0

    def compute_rule_score(self, email: Email) -> float:
        """
        Calculates a heuristic score based on positive and negative keywords.
        Returns a score in range [0.0, 1.0].
        """
        score = 0.5 # Start neutral
        normalized_subject = self.normalize_text(email.subject)
        normalized_snippet = self.normalize_text(email.snippet)
        combined_text = f"{normalized_subject} {normalized_snippet}"
        
        general_rules = self.rules.get("general_keywords", {})
        
        # Add weights for positive keywords
        for kw, weight in general_rules.get("positive", {}).items():
            if kw.lower() in combined_text:
                score += weight
                
        # Subtract weights for negative keywords
        for kw, weight in general_rules.get("negative", {}).items():
            if kw.lower() in combined_text:
                score += weight # weights are negative in yaml
                
        return max(0.0, min(1.0, score))

    async def call_deepseek_ai(self, email: Email) -> Dict[str, Any]:
        """
        Calls DeepSeek API to extract subscription details.
        Falls back to rule heuristics if API key is missing or call fails.
        """
        if not self.api_key:
            logger.info("DeepSeek API Key not found. Falling back to mock AI response.")
            return self._mock_ai_response(email)
            
        prompt = self.prompt_template
        prompt = prompt.replace("{{sender}}", email.sender)
        prompt = prompt.replace("{{subject}}", email.subject)
        prompt = prompt.replace("{{snippet}}", email.snippet)
        
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
                else:
                    logger.error(f"DeepSeek API call failed: {res.status_code} - {res.text}")
        except Exception as e:
            logger.error(f"DeepSeek API exception: {e}")
            
        return self._mock_ai_response(email)

    def _mock_ai_response(self, email: Email) -> Dict[str, Any]:
        """
        Fallback parser that simulates LLM output when API is offline.
        """
        normalized_subject = self.normalize_text(email.subject)
        normalized_snippet = self.normalize_text(email.snippet)
        combined = f"{normalized_subject} {normalized_snippet}"
        
        # Netflix
        if "netflix" in combined:
            amount, curr = self.extract_price_heuristic(combined)
            return {
                "is_subscription": True,
                "confidence": 0.95,
                "merchant": "Netflix",
                "price": amount or 98.0,
                "currency": curr,
                "billing_cycle": "monthly"
            }
        # Spotify
        elif "spotify" in combined:
            amount, curr = self.extract_price_heuristic(combined)
            return {
                "is_subscription": True,
                "confidence": 0.95,
                "merchant": "Spotify",
                "price": amount or 68.0,
                "currency": curr,
                "billing_cycle": "monthly"
            }
        # Claude
        elif "claude" in combined:
            amount, curr = self.extract_price_heuristic(combined)
            return {
                "is_subscription": True,
                "confidence": 0.95,
                "merchant": "Claude",
                "price": amount or 20.0,
                "currency": curr or "USD",
                "billing_cycle": "monthly"
            }
        # ChatGPT
        elif "chatgpt" in combined or "openai" in combined:
            amount, curr = self.extract_price_heuristic(combined)
            return {
                "is_subscription": True,
                "confidence": 0.95,
                "merchant": "ChatGPT",
                "price": amount or 20.0,
                "currency": curr or "USD",
                "billing_cycle": "monthly"
            }
        # Setapp / Trials
        elif "setapp" in combined:
            amount, curr = self.extract_price_heuristic(combined)
            return {
                "is_subscription": True,
                "confidence": 0.85,
                "merchant": "Setapp",
                "price": amount or 9.99,
                "currency": curr or "USD",
                "billing_cycle": "monthly"
            }
        
        # Unknown/Spam
        return {
            "is_subscription": False,
            "confidence": 0.10,
            "merchant": None,
            "price": None,
            "currency": None,
            "billing_cycle": "unknown"
        }

    async def recognize(self, email: Email) -> Tuple[Optional[Subscription], float]:
        """
        Executes the Hybrid Decision Engine logic:
        1. Match Fingerprint
        2. Compute Rule Score
        3. Skip AI if confidence is very clear
        4. Call AI Router (DeepSeek) if ambiguous
        5. Merge scores and return Subscription model (or None)
        """
        # Step 1: Match Fingerprint
        merchant_cfg, fp_score = self.match_fingerprint(email)
        
        # Step 2: Compute Rule Score
        rule_score = self.compute_rule_score(email)
        
        # Calculate combined baseline confidence before AI
        # If fingerprint matched successfully, baseline is high. Otherwise it's based on keywords.
        if fp_score >= 0.85:
            baseline_score = fp_score
        else:
            # Blend fingerprint score and rule score
            baseline_score = 0.3 * fp_score + 0.7 * rule_score
            
        logger.info(f"Email ID {email.id}: baseline_score={baseline_score:.2f} (fp={fp_score:.2f}, rule={rule_score:.2f})")
        
        # Step 3: Check if Ambiguous. If baseline is very high or very low, skip AI
        # Clear subscription: > 0.80
        # Clear non-subscription: < 0.35
        # Ambiguous range: [0.35, 0.80]
        ai_score = 0.0
        ai_result = {}
        ai_called = False
        
        if 0.35 <= baseline_score <= 0.80:
            logger.info(f"Email ID {email.id} is ambiguous ({baseline_score:.2f}). Calling AI Router.")
            ai_result = await self.call_deepseek_ai(email)
            ai_called = True
            ai_is_sub = ai_result.get("is_subscription", False)
            ai_conf = ai_result.get("confidence", 0.5)
            # If AI says it is a subscription, use its confidence. Otherwise invert it.
            ai_score = ai_conf if ai_is_sub else (1.0 - ai_conf)
            
        # Step 4: Confidence Merge
        if ai_called:
            # 60% rules, 30% fingerprint, 10% AI
            final_score = 0.6 * rule_score + 0.3 * fp_score + 0.1 * ai_score
            is_subscription = ai_result.get("is_subscription", False) if ai_score > 0.5 else (final_score > 0.65)
        else:
            # Without AI, 70% rules, 30% fingerprint
            final_score = 0.7 * rule_score + 0.3 * fp_score
            is_subscription = final_score > 0.65
            
        logger.info(f"Email ID {email.id}: final_score={final_score:.2f}, is_subscription={is_subscription}")
        
        if not is_subscription:
            return None, final_score
            
        # Step 5: Construct Subscription Object
        merchant_name = "Unknown"
        category = "Other"
        billing_cycle = BillingCycle.MONTHLY
        
        # Derive merchant information
        if merchant_cfg:
            merchant_name = merchant_cfg.get("name", "Unknown")
            category = merchant_cfg.get("category", "Other")
            billing_cycle = BillingCycle(merchant_cfg.get("billing_cycle", "monthly"))
        elif ai_called and ai_result.get("merchant"):
            merchant_name = ai_result.get("merchant")
            billing_cycle = BillingCycle(ai_result.get("billing_cycle", "monthly"))
            
        # Parse price and currency
        price_amount = None
        price_currency = "CNY"
        
        if ai_called and ai_result.get("price") is not None:
            price_amount = ai_result.get("price")
            price_currency = ai_result.get("currency") or "CNY"
        else:
            # Use regex heuristic
            combined_text = f"{email.subject} {email.snippet}"
            h_amount, h_curr = self.extract_price_heuristic(combined_text)
            if h_amount is not None:
                price_amount = h_amount
                price_currency = h_curr
                
        # Handle trial status
        status = SubscriptionStatus.DETECTED
        combined_text_norm = self.normalize_text(f"{email.subject} {email.snippet}")
        if "trial" in combined_text_norm or "试用" in combined_text_norm:
            status = SubscriptionStatus.TRIAL
            
        # Default price if parsing failed
        if price_amount is None:
            price_amount = 0.0
            
        sub = Subscription(
            merchant=merchant_name,
            price=Money(amount=price_amount, currency=price_currency),
            billing_cycle=billing_cycle,
            confidence=final_score,
            emails_count=1,
            last_seen=email.date,
            status=status
        )
        
        return sub, final_score
