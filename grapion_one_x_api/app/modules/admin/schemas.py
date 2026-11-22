# //Added By Nikhil 18Nov26 21:32 For Admin Schemas
from pydantic import BaseModel, Field
from typing import Optional

class ApprovePaymentRequest(BaseModel):
    payment_method: str = Field(..., pattern="^(cash|upi|card)$")
    payer_upi_id: Optional[str] = None
    utr_last_digits: Optional[str] = None
    cardholder_name: Optional[str] = None
    card_last_four: Optional[str] = Field(None, max_length=4)

class RejectRequest(BaseModel):
    reason: str = Field(..., min_length=2, max_length=255)


#Added By Nikhil 21Nov26 22:44 For cancellation review START
class ApproveCancellationRequest(BaseModel):
    refund_method: str = Field(..., pattern="^(cash|upi|card|bank)$")
    refund_reference: Optional[str] = Field(None, max_length=50)  # last digits only — never full card/UTR
    note: Optional[str] = Field(None, max_length=500)

class RejectCancellationRequest(BaseModel):
    note: str = Field(..., min_length=2, max_length=500)
#Added By Nikhil 21Nov26 22:44 For cancellation review END
