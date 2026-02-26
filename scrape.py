import urllib.request
import sys

url = sys.argv[1]
outfile = sys.argv[2]
req = urllib.request.Request(
    url, 
    data=None, 
    headers={
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
    }
)

try:
    with urllib.request.urlopen(req) as response:
        html = response.read()
        print(f"Success! Fetched {len(html)} bytes")
        with open(outfile, 'wb') as f:
            f.write(html)
except Exception as e:
    print(f"Error: {e}")
