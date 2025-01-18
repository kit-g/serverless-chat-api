from dataclasses import dataclass
from datetime import datetime
from user import User


@dataclass
class Message:
    id: str
    body: str
    when: datetime
    room_id: str
    by: User
