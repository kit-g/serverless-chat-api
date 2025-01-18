import json

from chatlib.errors import NotFoundError, ContentError


def _respond(body: dict, status=200) -> dict:
    return {
        'statusCode': status,
        'body': json.dumps(body)
    }


def _handler(event: dict) -> tuple[dict, int] | dict:
    print(event)

    try:
        match event:
            case {
                'httpMethod': verb,
                'body': j,
                'path': path,
            } if j:
                match (verb, path.split('/')):
                    case ('POST', ['', 'rooms']):
                        return {
                            'message': 'Room was created'
                        }
                    case ('POST', ['', 'rooms', room_id, 'messages']):
                        return {
                            'message': f'Room {room_id} was sent a message to'
                        }
                    case ('PUT', ['', 'rooms', room_id, 'messages', message_id]):
                        return {
                            'message': f'Message {message_id} in room {room_id} was edited'
                        }
                    case ('DELETE', ['', 'rooms', room_id, 'messages', message_id]):
                        return {
                            'message': f'Message {message_id} in room {room_id} was deleted'
                        }
            case {
                'httpMethod': verb,
                'path': path,
                'queryStringParameters': _,
            }:
                match (verb, path.split('/')):
                    case ('GET', ['', 'rooms']):
                        return {
                            'message': 'That\'s a Get Rooms request'
                        }
                    case ('GET', ['', 'rooms', room_id]):
                        return {
                            'message': f'That\'s a Get Room {room_id} request'
                        }
                    case ('GET', ['', 'rooms', room_id, 'messages']):
                        return {
                            'message': f'That\'s a Get Messages in room {room_id} request'
                        }

    except BaseException as error:
        message = f'Main {error.__class__.__name__} error: {error}'
        print(message)
        return {'error': str(error)}, 500


def handler(event: dict, _):
    match _handler(event):
        case body, status:
            return {
                'statusCode': status,
                'body': json.dumps(body),
            }
        case body:
            return {
                'statusCode': 200,
                'body': json.dumps(body),
            }
