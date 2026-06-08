import msal, pyodbc, struct, os
from dotenv import load_dotenv

load_dotenv()

result = msal.ConfidentialClientApplication(
    os.environ['AZURE_CLIENT_ID'],
    authority=f"https://login.microsoftonline.com/{os.environ['TENANT_ID']}",
    client_credential=os.environ['AZURE_CLIENT_SECRET'],
).acquire_token_for_client(scopes=['https://database.windows.net//.default'])

print("Token:", result.get('token_type'), result.get('expires_in'))

if 'access_token' not in result:
    print("FAILED:", result)
else:
    print("Token acquired, attempting SQL connection...")
    token = result['access_token']
    token_bytes = token.encode('utf-16-le')
    token_struct = struct.pack(f'<I{len(token_bytes)}s', len(token_bytes), token_bytes)
    conn_str = (
        f"Driver={{ODBC Driver 18 for SQL Server}};"
        f"Server={os.environ['FABRIC_SERVER']},1433;"
        f"Database={os.environ.get('FABRIC_DB', 'WH_Dentally')};"
        f"Encrypt=yes;TrustServerCertificate=no;"
    )
    conn = pyodbc.connect(conn_str, attrs_before={1256: token_struct})
    print("Connected!")
    conn.close()
