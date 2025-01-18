from typing import Iterable


class ContentError(BaseException):
    def __init__(self, message: str):
        self.message = message
        super().__init__(message)


class NotFoundError(ContentError):
    pass


class UserNotFoundError(NotFoundError):
    def __init__(self):
        super(UserNotFoundError, self).__init__('No such user found')


class MessageNotFound(NotFoundError):
    def __init__(self):
        super(MessageNotFound, self).__init__('No such message found')


class ConnectionParsingFailed(NotFoundError):
    def __init__(self):
        super(ConnectionParsingFailed, self).__init__('Could not infer websocket connection from the API Gateway event')


class IncorrectSignature(ContentError):
    def __init__(self, attrs: Iterable[tuple[str, type]]):
        joined = ', '.join(f'{each[0]}: {each[1].__name__}' for each in attrs)
        message = f'The following attributes are expected: {joined}'
        super(IncorrectSignature, self).__init__(message)


class ProgrammingError(BaseException):
    def __init__(self, message: str):
        self.message = message
        super().__init__(message)


class MissingDependency(ProgrammingError):
    def __init__(self, dependency_name: str):
        message = f'{dependency_name} is not installed'
        super().__init__(message)
