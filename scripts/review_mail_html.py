"""Bounded, inert HTML-to-quoted-text interpretation for saved mail evidence.

This is deliberately not a browser or HTML5 error-recovery implementation.
Only well-nested supported markup is accepted. No resource or URL is opened.
"""
from html.entities import html5
from html.parser import HTMLParser

MAX_HTML_CHARS = 1024 * 1024
MAX_HTML_EVENTS = 20000
MAX_HTML_DEPTH = 64
MAX_HTML_TEXT_BYTES = 1024 * 1024
MAX_LINK_CHARS = 2048
VOID = frozenset('area base br col embed hr img input link meta param source track wbr'.split())
BLOCK = frozenset('address article aside blockquote caption dd details div dl dt figcaption figure footer h1 h2 h3 h4 h5 h6 header main nav ol p pre section summary table tbody tfoot thead tr ul'.split())
INLINE = frozenset('a abbr b bdi bdo cite code del em i ins kbd mark q rp rt ruby s samp small span strong sub sup time u var'.split())
CONTAINERS = BLOCK | INLINE | frozenset('html body li td th'.split())
SUPPRESSED = frozenset('head script style template iframe object svg math canvas audio video form textarea select button noscript'.split())
INTERPRETATION = 'moonchat.static-html-text.v1'
LIMITATIONS = [
    'Static extracted text, not rendered appearance or verified sender identity.',
    'CSS, attributes, hidden and aria-hidden visibility, layout and reading order are not evaluated; hidden text can be included.',
    'Block/list/table separators are approximations; link targets are quoted strings, never opened.',
    'Scripts, styles, templates, embedded content and resources are omitted; no network or execution occurs.',
]


class HtmlTextError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise HtmlTextError(message)


class StaticMailParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.stack = []
        self.chunks = []
        self.text_bytes = 0
        self.events = 0
        self.omitted = {}

    def event(self):
        self.events += 1
        require(self.events <= MAX_HTML_EVENTS, 'HTML exceeds 20000 parser events')

    def omission(self, kind, reason):
        key = (kind, reason)
        self.omitted[key] = self.omitted.get(key, 0) + 1

    def suppressed(self):
        return bool(self.stack and self.stack[-1][1])

    def emit(self, text):
        self.text_bytes += len(text.encode('utf-8'))
        require(self.text_bytes <= MAX_HTML_TEXT_BYTES, 'HTML extracted text exceeds 1 MiB')
        self.chunks.append(text)

    def line(self):
        if self.chunks and not self.chunks[-1].endswith('\n'):
            self.emit('\n')

    def handle_starttag(self, tag, attrs):
        self.event()
        require(tag in CONTAINERS | VOID | SUPPRESSED or self.suppressed(),
                'unsupported HTML element: ' + tag)
        names = [key for key, _ in attrs]
        require(len(names) == len(set(names)), 'duplicate HTML attribute')
        suppressed = self.suppressed() or tag in SUPPRESSED
        href = None
        if tag in SUPPRESSED and not self.suppressed():
            self.omission(tag, 'element and its content excluded')
        if attrs and not suppressed:
            self.omission(tag, 'attributes ignored except quoted anchor href')
        if not suppressed:
            if tag in BLOCK or tag == 'li':
                self.line()
            if tag == 'li':
                self.emit('- ')
            if tag == 'br' or tag == 'hr':
                self.line()
            if tag in ('td', 'th') and self.chunks and not self.chunks[-1].endswith('\n'):
                self.emit(' | ')
            if tag == 'a':
                href = dict(attrs).get('href')
                if href is not None:
                    require(len(href) <= MAX_LINK_CHARS, 'HTML link exceeds 2048 characters')
                    require(not any(ord(c) < 32 or 0xD800 <= ord(c) <= 0xDFFF for c in href),
                            'unsupported control character in HTML link')
            if tag in VOID - {'br', 'hr', 'wbr'}:
                self.omission(tag, 'resource or void element omitted; nothing loaded')
        if tag not in VOID:
            self.stack.append((tag, suppressed, href))
            require(len(self.stack) <= MAX_HTML_DEPTH, 'HTML nesting exceeds depth 64')

    def handle_startendtag(self, tag, attrs):
        require(tag in VOID, 'self-closing non-void HTML element is unsupported')
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        self.event()
        require(self.stack and self.stack[-1][0] == tag, 'HTML tags must be explicitly closed and well nested: ' + tag)
        _, suppressed, href = self.stack.pop()
        if not suppressed:
            if href is not None:
                # Quoted JSON spelling makes control/quote boundaries explicit.
                import json
                self.emit(' [link target: ' + json.dumps(href, ensure_ascii=False) + ']')
            if tag in BLOCK or tag == 'li':
                self.line()

    def handle_data(self, data):
        self.event()
        if self.suppressed():
            return
        require('<' not in data, 'incomplete or unsupported HTML markup; encode literal less-than as &lt;')
        require(not any((ord(c) < 32 and c not in '\t\n\r') or 0xD800 <= ord(c) <= 0xDFFF for c in data),
                'unsupported control character in HTML text')
        if any(tag == 'pre' for tag, _, _ in self.stack):
            self.emit(data)
        else:
            # ASCII HTML whitespace only; retain nonbreaking spaces and Unicode.
            import re
            self.emit(re.sub(r'[ \t\r\n\f]+', ' ', data))

    def reference(self, text):
        self.event()
        if not self.suppressed():
            require(not any(ord(c) == 0 or 0xD800 <= ord(c) <= 0xDFFF or
                            (ord(c) < 32 and c not in '\t\n\r') for c in text),
                    'unsupported HTML character reference')
            self.emit(text)

    def handle_entityref(self, name):
        require(name + ';' in html5, 'unknown HTML named character reference: ' + name)
        self.reference(html5[name + ';'])

    def handle_charref(self, name):
        try:
            value = int(name[1:], 16) if name.startswith(('x', 'X')) else int(name, 10)
            self.reference(chr(value))
        except (ValueError, OverflowError) as error:
            raise HtmlTextError('invalid HTML numeric character reference') from error

    def handle_comment(self, data):
        self.event()
        self.omission('comment', 'comment excluded')

    def handle_decl(self, decl):
        self.event()
        require(decl.lower().split() == ['doctype', 'html'], 'only an inert HTML doctype is supported')
        self.omission('doctype', 'declaration ignored')

    def unknown_decl(self, data):
        raise HtmlTextError('unsupported HTML declaration')

    def handle_pi(self, data):
        raise HtmlTextError('HTML processing instructions are unsupported')


def extract_html_text(text):
    require(isinstance(text, str) and len(text) <= MAX_HTML_CHARS, 'HTML input exceeds 1 Mi characters')
    parser = StaticMailParser()
    try:
        parser.feed(text)
        parser.close()
    except (AssertionError, RecursionError) as error:
        raise HtmlTextError('unsupported or malformed HTML syntax') from error
    require(not parser.stack, 'HTML has unclosed elements')
    result = ''.join(parser.chunks).strip()
    return {'text': result, 'interpretation': INTERPRETATION,
            'omissions': [{'element': tag, 'reason': reason, 'count': count}
                          for (tag, reason), count in sorted(parser.omitted.items())],
            'limitations': list(LIMITATIONS), 'parser_events': parser.events}
