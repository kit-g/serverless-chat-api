"""
This is a dummy API Gateway authorizer
that always returns the same user
"""

import json
import os
from dataclasses import asdict
from typing import Literal

from chatlib.user import User
from chatlib.errors import UserNotFoundError

region = os.environ['REGION']
account = os.environ['ACCOUNT']

Effect = Literal['Allow', 'Deny']


def policy(effect: Effect, api_id: str, stage: str) -> dict:
    return {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "execute-api:Invoke",
                "Effect": effect,
                "Resource": f"arn:aws:execute-api:{region}:{account}:{api_id}/{stage}/*"
            }
        ]
    }


def allow(api_id: str, stage: str) -> dict:
    return policy(
        'Allow',
        stage=stage,
        api_id=api_id
    )


def handler(event: dict, _):
    try:
        print(event)

        match event['requestContext']:
            case {'stage': stage, 'apiId': api_id}:
                user = User(id='1', name='JaneDoe')

                return {
                    "principalId": user.id,
                    "policyDocument": allow(stage=stage, api_id=api_id),
                    "context": {
                        "user": json.dumps(asdict(user)),
                    }
                }
    except (UserNotFoundError, BaseException, Exception) as e:
        message = f'Error: {type(e)}, {repr(e)}'
        print(message)
        raise Exception('Unauthorized')
