import pytest
import sys
import os

# Adjust path to import backend app
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend")))

from app.models.email import Email
from app.core.recognizer import HybridRecognizer
from app.models.subscription import SubscriptionStatus, BillingCycle

@pytest.fixture
def recognizer():
    return HybridRecognizer()

def test_normalize_text(recognizer):
    raw = "Your Netflix Invoice  \n for June 2026 "
    normalized = recognizer.normalize_text(raw)
    assert normalized == "your netflix invoice for june 2026"

def test_extract_price_heuristic(recognizer):
    # Test CNY prefix
    amount, currency = recognizer.extract_price_heuristic("Your Netflix bill: CNY 98.00. Payment method: Alipay.")
    assert amount == 98.00
    assert currency == "CNY"
    
    # Test USD prefix
    amount, currency = recognizer.extract_price_heuristic("Claude Pro invoice for June. Paid USD 20.00.")
    assert amount == 20.00
    assert currency == "USD"
    
    # Test symbol prefix
    amount, currency = recognizer.extract_price_heuristic("Premium renewal: $15.99 monthly.")
    assert amount == 15.99
    assert currency == "USD"

    # Test symbol suffix/no decimal
    amount, currency = recognizer.extract_price_heuristic("Spotify Premium charged 68元 to account.")
    assert amount == 68.0
    assert currency == "CNY"

def test_match_fingerprint(recognizer):
    email = Email(
        id="test_01",
        sender="Netflix <info@netflix.com>",
        subject="Your Netflix Invoice for June 2026",
        snippet="Thanks for watching. Auto-renewed.",
        date="2026-06-15"
    )
    merchant_cfg, fp_score = recognizer.match_fingerprint(email)
    assert merchant_cfg is not None
    assert merchant_cfg["name"] == "Netflix"
    assert fp_score >= 0.85

def test_match_fingerprint_marketing_ignored(recognizer):
    # Sender is Netflix but subject has no receipt keywords
    email = Email(
        id="test_02",
        sender="Netflix <info@netflix.com>",
        subject="New shows coming in July!",
        snippet="Watch Stranger Things and more.",
        date="2026-06-28"
    )
    merchant_cfg, fp_score = recognizer.match_fingerprint(email)
    assert merchant_cfg is not None
    # Confidence should be downgraded because subject keywords didn't match
    assert fp_score < 0.50

@pytest.mark.asyncio
async def test_recognize_subscription_netflix(recognizer):
    email = Email(
        id="test_netflix",
        sender="Netflix <info@netflix.com>",
        subject="Your Netflix Invoice for June 2026",
        snippet="Thanks for watching. Your subscription auto-renewed on 2026-06-15. Amount charged: CNY 98.00.",
        date="2026-06-15"
    )
    sub, score = await recognizer.recognize(email)
    assert sub is not None
    assert sub.merchant == "Netflix"
    assert sub.price.amount == 98.0
    assert sub.price.currency == "CNY"
    assert sub.billing_cycle == BillingCycle.MONTHLY
    assert sub.status == SubscriptionStatus.DETECTED

@pytest.mark.asyncio
async def test_recognize_subscription_spotify(recognizer):
    email = Email(
        id="test_spotify",
        sender="Spotify <no-reply@spotify.com>",
        subject="Your Premium Family receipt",
        snippet="Spotify Premium Family. Total: CNY 68.00. Payment will recur monthly.",
        date="2026-06-20"
    )
    sub, score = await recognizer.recognize(email)
    assert sub is not None
    assert sub.merchant == "Spotify"
    assert sub.price.amount == 68.0
    assert sub.billing_cycle == BillingCycle.MONTHLY

@pytest.mark.asyncio
async def test_recognize_non_subscription(recognizer):
    email = Email(
        id="test_spam",
        sender="Steam Support <noreply@steampowered.com>",
        subject="Your Steam account password reset request",
        snippet="Verification code: 89432. Use this code to reset your account password.",
        date="2026-06-23"
    )
    sub, score = await recognizer.recognize(email)
    # Reset password should be classified as negative score and not a subscription
    assert sub is None
