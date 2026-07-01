from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api.routers import router as api_router
import uvicorn

app = FastAPI(
    title="Sublens Backend API",
    description="Stateless scanner backend for Subscription Guard (Sublens)",
    version="1.0.0"
)

# Configure CORS for local development and app integration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # Open for MVP development, restrict in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Root status check
@app.get("/")
async def root():
    return {
        "app": "Sublens Backend API",
        "status": "healthy",
        "version": "1.0.0"
    }

# Include API Router
app.include_router(api_router)

if __name__ == "__main__":
    uvicorn.run("main:app", host="127.0.0.1", port=8000, reload=True)
