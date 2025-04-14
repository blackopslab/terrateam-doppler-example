import json
import os
import urllib3

def lambda_handler(event, context):
    api_key = os.environ['MOCK_API_KEY']
    api_url = os.environ['MOCK_API_URL']
    
    http = urllib3.PoolManager()
    response = http.request(
        'GET',
        api_url,
        headers={'X-Api-Key': api_key}
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Called mock API',
            'response': json.loads(response.data.decode('utf-8'))
        })
    }