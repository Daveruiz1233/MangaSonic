import re

def parse(filename):
    with open(filename, 'r', encoding='utf-8', errors='ignore') as f:
        html = f.read()
    print(f"--- Analyzing {filename} ---")
    
    # Simple regex to find blocks that look like manga lists
    # Manhuatop: usually "manga-item" or "page-item-detail"
    # Asura: usually NextJS JSON data or specific class names
    
    # Let's just find the first few <a> tags that contain an <img>
    matches = re.findall(r'<a[^>]+href="([^"]+)"[^>]*>.*?<img[^>]+(?:src|data-src|data-lazy-src)="([^"]+)"[^>]*>.*?</a>', html, re.DOTALL | re.IGNORECASE)
    
    count = 0
    for match in matches:
        url, img = match
        if count < 5:
            print(f"URL: {url}\nIMG: {img}\n")
            count += 1
            
parse("manhuatop.html")
parse("asuracomic.html")
parse("manhuaplus.html")
