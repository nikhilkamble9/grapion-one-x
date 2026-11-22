# //Added By Nikhil 18Nov26 21:28 For Auth Schemas
from pydantic import BaseModel, EmailStr, Field
from typing import Optional
import uuid

class UserRegisterRequest(BaseModel):
    first_name: str = Field(..., min_length=1, max_length=100)
    last_name: str = Field(..., min_length=1, max_length=100)
    email: EmailStr
    username: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=6, max_length=128)
    country_code: str = Field(default="IN", max_length=10)
    dial_code: str = Field(default="+91", max_length=10)
    mobile_number: str = Field(..., min_length=4, max_length=20)

class UserLoginRequest(BaseModel):
    username_or_email: str
    password: str

class VerifyUsernameRequest(BaseModel):
    username: str

class VerifyMobileRequest(BaseModel):
    username: str
    mobile_number: str

class ResetPasswordRequest(BaseModel):
    username: str
    mobile_number: str
    new_password: str = Field(..., min_length=6, max_length=128)

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: dict

#Added By Nikhil 21Nov26 22:36 For profile settings (current password required) START
class UpdateProfileRequest(BaseModel):
    current_password: str = Field(..., min_length=1, max_length=128)
    first_name: str = Field(..., min_length=1, max_length=100)
    last_name: str = Field(..., min_length=1, max_length=100)
    email: EmailStr
    country_code: str = Field(..., min_length=2, max_length=10)
    dial_code: str = Field(..., min_length=2, max_length=10)
    mobile_number: str = Field(..., min_length=4, max_length=20)

class ChangePasswordRequest(BaseModel):
    current_password: str = Field(..., min_length=1, max_length=128)
    new_password: str = Field(..., min_length=6, max_length=128)
#Added By Nikhil 21Nov26 22:36 For profile settings (current password required) END
