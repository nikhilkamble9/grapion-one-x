# //Added By Nikhil 18Nov26 21:23 For Application Settings
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field
from pathlib import Path  #Added By Nikhil 22Nov26 11:59 For .env path relative to the API folder

class Settings(BaseSettings):
    APP_NAME: str = "G.One.X API"
    APP_ENV: str = "development"
    APP_TIMEZONE: str = "Asia/Kolkata"
    DEBUG: bool = True

    DATABASE_URL: str
    DB_SCHEMA: str = "grapion_one_x"

    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    #Added By Nikhil 22Nov26 00:10 For Firebase Cloud Messaging (path relative to backend/)
    FIREBASE_CREDENTIALS_PATH: str = "firebase-service-account.json"

    model_config = SettingsConfigDict(
        #Modified By Nikhil 22Nov26 11:59 For .env found next to the API on any machine/server (real env vars still win). Old: env_file="D:\\Software Development\\Grapion Digital\\Code\\grapion-one-x\\backend\\.env",
        env_file=str(Path(__file__).resolve().parents[2] / ".env"),
        env_file_encoding="utf-8",
        extra="ignore"
    )

settings = Settings()
