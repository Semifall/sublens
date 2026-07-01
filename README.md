# SubLens

**Know every subscription. Save every dollar.**

A lightweight app that scans your email, detects recurring charges, and gives you a clear dashboard of all your subscriptions — with cancellation guidance and renewal alerts.

---

## Why?

You're probably paying for subscriptions you forgot about. SubLens finds them automatically so you can cut the dead weight.

## Features

| Feature | Status |
|---------|--------|
| Google / Apple Login | MVP |
| Gmail / Outlook scan | MVP |
| Subscription detection (ML + rule-based) | Planned |
| Dashboard with recurring charges | Planned |
| Renewal date tracking & alerts | Planned |
| One-click cancellation links | Planned |
| Monthly spend breakdown | Planned |

## Tech Stack

| Layer | Tech |
|-------|------|
| Frontend | Flutter (iOS, Android, Web) |
| Backend | Python (FastAPI) |
| Auth | Firebase / Google OAuth |
| Email Parsing | IMAP + regex / NLP |
| Data | SQLite / PostgreSQL |

## Quick Start

```bash
# Clone
git clone https://github.com/Semifall/sublens.git
cd sublens

# Run Flutter app
cd flutter/
flutter pub get
flutter run

# Run backend
cd ../backend/
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload
```

## Roadmap

- **Sprint 1** — Auth + Gmail scan + basic detection
- **Sprint 2** — Dashboard + renewal alerts
- **Sprint 3** — Cancellation assistant + spend analytics
- **Sprint 4** — Multi-account, export, sharing

## Screenshots

_Screenshots coming soon._

## License

MIT

## Contributing

Pull requests welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

Built with ❤️ by [Semifall](https://github.com/Semifall)
