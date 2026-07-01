import pytest
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend")))

from app.models.subscription import Email
from app.core.recognizer import HybridRecognizer

@pytest.fixture
def recognizer():
    return HybridRecognizer()

def test_normalize_text(recognizer):
    raw = "Your Netflix Invoice  \n for June 2026 "
    normalized = recognizer.normalize_text(raw)
    assert normalized == "your netflix invoice for june 2026"

def test_match_fingerprint(recognizer):
    email = Email(
        id="test_01",
        user_id="u123",
        gmail_id="g1",
        thread_id="t1",
        sender="Netflix <info@netflix.com>",
        subject="Your Netflix Invoice for June 2026",
        snippet="Thanks for watching. Auto-renewed.",
        received_at="2026-06-15",
        created_at="2026-06-15"
    )
    merchant_name, fp_score = recognizer.match_fingerprint(email)
    assert merchant_name == "Netflix"
    assert fp_score >= 0.85

def test_match_fingerprint_marketing_ignored(recognizer):
    email = Email(
        id="test_02",
        user_id="u123",
        gmail_id="g2",
        thread_id="t2",
        sender="Netflix <info@netflix.com>",
        subject="New shows coming in July!",
        snippet="Watch Stranger Things and more.",
        received_at="2026-06-28",
        created_at="2026-06-28"
    )
    merchant_name, fp_score = recognizer.match_fingerprint(email)
    # Confidence should be downgraded because subject keywords didn't match
    assert fp_score < 0.50

@pytest.mark.asyncio
async def test_recognize_subscription_netflix(recognizer):
    email = Email(
        id="test_netflix",
        user_id="u123",
        gmail_id="g_net",
        thread_id="t_net",
        sender="Netflix <info@netflix.com>",
        subject="Your Netflix Invoice for June 2026",
        snippet="Thanks for watching. Your subscription auto-renewed on 2026-06-15. Amount charged: USD 15.99.",
        received_at="2026-06-15",
        created_at="2026-06-15"
    )
    rec, sub = await recognizer.recognize(email)
    assert rec is not None
    assert rec.merchant == "Netflix"
    assert rec.price == 15.99
    assert sub is not None
    assert sub.merchant == "Netflix"
    assert sub.price == 15.99
    assert sub.status == "active"

@pytest.mark.asyncio
async def test_recognize_subscription_spotify(recognizer):
    email = Email(
        id="test_spotify",
        user_id="u123",
        gmail_id="g_spot",
        thread_id="t_spot",
        sender="Spotify <no-reply@spotify.com>",
        subject="Your Premium Family receipt",
        snippet="Spotify Premium Family. Total: USD 9.99. Payment will recur monthly.",
        received_at="2026-06-20",
        created_at="2026-06-20"
    )
    rec, sub = await recognizer.recognize(email)
    assert rec is not None
    assert rec.merchant == "Spotify"
    assert rec.price == 9.99
    assert sub is not None
    assert sub.merchant == "Spotify"
    assert sub.price == 9.99

@pytest.mark.asyncio
async def test_recognize_non_subscription(recognizer):
    email = Email(
        id="test_spam",
        user_id="u123",
        gmail_id="g_spam",
        thread_id="t_spam",
        sender="Steam Support <noreply@steampowered.com>",
        subject="Your Steam account password reset request",
        snippet="Verification code: 89432. Use this code to reset your account password.",
        received_at="2026-06-23",
        created_at="2026-06-23"
    )
    rec, sub = await recognizer.recognize(email)
    # Reset password should yield no subscription
    assert sub is None
