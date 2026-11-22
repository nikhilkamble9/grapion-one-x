# //Added By Nikhil 18Nov26 21:34 For Main Application Entrypoint
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.modules.auth.router import router as auth_router
from app.modules.subscriptions.router import router as subscriptions_router
from app.modules.admin.router import router as admin_router
from app.modules.subscriptions.cancellations import router as cancellations_router  #Added By Nikhil 21Nov26 22:44 For cancellations
from app.modules.workspaces.router import router as workspaces_router  #Added By Nikhil 21Nov26 23:30 For roles & businesses
from app.modules.notifications.router import router as notifications_router  #Added By Nikhil 22Nov26 00:10 For bell + push
from app.modules.superadmin.router import router as superadmin_router  #Added By Nikhil 22Nov26 01:22 For super admin pages
from app.modules.gym.router import router as gym_router  #Added By Nikhil 22Nov26 08:41 For Grapion Gym owner API
from app.modules.gym.jobs import router as jobs_router  #Added By Nikhil 22Nov26 18:05 For forgot-check-out reminders
from app.modules.meta.router import router as meta_router  #Added By Nikhil 21Nov26 21:00 For country list endpoint

app = FastAPI(
    title=settings.APP_NAME,
    description="Backend API for G.One.X Multi-Vertical Business Suite",
    version="1.0.0",
    docs_url="/docs" if settings.DEBUG else None,
    redoc_url=None
)

# CORS Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include Modular Routers
app.include_router(auth_router, prefix="/api/v1")
app.include_router(subscriptions_router, prefix="/api/v1")
app.include_router(admin_router, prefix="/api/v1")
app.include_router(meta_router, prefix="/api/v1")  #Added By Nikhil 21Nov26 21:00 For country list endpoint
app.include_router(cancellations_router, prefix="/api/v1")  #Added By Nikhil 21Nov26 22:44 For cancellations
app.include_router(workspaces_router, prefix="/api/v1")  #Added By Nikhil 21Nov26 23:30 For roles & businesses
app.include_router(notifications_router, prefix="/api/v1")  #Added By Nikhil 22Nov26 00:10 For bell + push
app.include_router(superadmin_router, prefix="/api/v1")  #Added By Nikhil 22Nov26 01:22 For super admin pages
app.include_router(gym_router, prefix="/api/v1")  #Added By Nikhil 22Nov26 08:41 For Grapion Gym owner API
app.include_router(jobs_router, prefix="/api/v1")  #Added By Nikhil 22Nov26 18:05 For forgot-check-out reminders

@app.get("/health", tags=["Health"])
async def health_check():
    return {
        "status": "healthy",
        "app": settings.APP_NAME,
        "environment": settings.APP_ENV,
        "timezone": settings.APP_TIMEZONE
    }
