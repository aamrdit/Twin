import json
from mangum import Mangum
from server import app

asgi_handler = Mangum(app)

def handler(event, context):
    print("EVENT RECEIVED:")
    print(json.dumps(event, indent=2))
    return asgi_handler(event, context)
