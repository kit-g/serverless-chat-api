import json
from typing import Any

from room import ChatRoom
from message import Message
from errors import ContentError


class ChatEvent:
    @property
    def type(self) -> str:
        return self.__class__.__name__

    def payload(self) -> dict | list[dict]:
        raise NotImplementedError

    def public(self) -> dict[str, Any]:
        return {
            'type': self.type,
            'payload': self.payload(),
        }

    def as_json(self) -> str:
        return json.dumps(self.public())


class GetRooms(ChatEvent):
    def __init__(self, rooms: list[ChatRoom]):
        self.rooms = rooms

    def payload(self) -> dict:
        return {'rooms': [each for each in self.rooms]}


class MessageSent(ChatEvent):
    def __init__(self, message: Message):
        self.message = message

    def payload(self) -> dict:
        return {'message': self.message}


class GetMessages(ChatEvent):
    def __init__(self, room_id: str, messages: list[Message]):
        self.messages = messages
        self.room_id = room_id

    def payload(self) -> dict:
        return {
            'roomId': self.room_id,
            'messages': [each for each in self.messages],
        }

    @classmethod
    def empty(cls, room_id: str):
        return cls(room_id=room_id, messages=[])


class ErrorEvent(ChatEvent):
    def __init__(self, error: ContentError | Exception):
        self.error = error

    @property
    def message(self) -> str:
        return self.error.message if hasattr(self.error, 'message') else f'{self.error}'

    def payload(self) -> dict:
        return {
            'error': self.error.__class__.__name__,
            'message': self.message,
        }


class RoomCreated(ChatEvent):
    def __init__(self, room: ChatRoom):
        self.room = room

    def payload(self) -> dict:
        return {
            'room': self.room
        }


class MessageDeleted(ChatEvent):
    def __init__(self, room_id: str, message_id: str):
        self.room_id = room_id
        self.message_id = message_id

    def payload(self) -> dict:
        return {
            'roomId': self.room_id,
            'messageId': self.message_id,
        }


class MessageEdited(MessageSent):
    pass
