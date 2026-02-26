import sys
from html.parser import HTMLParser

class MyHTMLParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_item = False
        self.item_html = ""
        self.items_found = 0

    def handle_starttag(self, tag, attrs):
        attrs_dict = dict(attrs)
        class_str = attrs_dict.get('class', '')
        
        # Madara / common themes use page-item-detail or similar
        if 'page-item-detail' in class_str or 'item' in class_str or 'manga-item' in class_str or 'bsx' in class_str:
            if not self.in_item and self.items_found < 3:
                self.in_item = True
                self.item_html += f"<{tag} {' '.join(k+'='+'\"'+v+'\"' for k,v in attrs_dict.items())}>\n"
        
        if self.in_item:
            self.item_html += f"<{tag} {' '.join(k+'='+'\"'+(v or '')+'\"' for k,v in attrs_dict.items())}>\n"

    def handle_endtag(self, tag):
        if self.in_item:
            self.item_html += f"</{tag}>\n"
            # very naive, just to grab a chunk
            if len(self.item_html) > 500:
                print("--- ITEM START ---")
                print(self.item_html)
                print("--- ITEM END ---\n")
                self.in_item = False
                self.item_html = ""
                self.items_found += 1

parser = MyHTMLParser()
with open(sys.argv[1], 'r', encoding='utf-8', errors='ignore') as f:
    parser.feed(f.read())
