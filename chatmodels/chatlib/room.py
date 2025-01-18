from dataclasses import dataclass
from datetime import datetime

from user import User


@dataclass
class ChatRoom:
    id: str
    name: str = None
    avatar: str = None


@dataclass
class RoomUserAssociation:
    user: User
    room: ChatRoom
    joined_at: datetime
    name: str = None
    avatar: str = None
