"""Functional source-mapping and actual CLI checks, without native dependencies."""
import hashlib
from html.parser import HTMLParser
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import review_docx as d
import review_docx_packet as packet
from test_review_docx import DOC, COMMENTS, W, archive, parts


class PacketHTML(HTMLParser):
    def __init__(self, html):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.ids = []
        self.links = []
        self.tags = []
        self.source = []
        self.source_markers = {}
        self.marked = []
        self.comments = []
        self.feed(html)
        self.close()

    def handle_starttag(self, tag, attributes):
        attributes = dict(attributes)
        self.tags.append((tag, attributes))
        if "id" in attributes:
            self.ids.append(attributes["id"])
        if tag == "a":
            self.links.append(attributes["href"])
        if attributes.get("class") == "marker":
            self.source_markers[attributes["id"]] = len("".join(self.source))
        if tag not in ("meta", "br", "hr", "img", "input", "link"):
            self.stack.append((tag, attributes))

    def handle_endtag(self, tag):
        if not self.stack or self.stack[-1][0] != tag:
            raise AssertionError("Unbalanced HTML close: " + tag)
        self.stack.pop()

    def handle_data(self, text):
        if any(a.get("id") == "document-text" for _, a in self.stack):
            if not any(a.get("class") == "marker" for _, a in self.stack):
                self.source.append(text)
                marks = [a for tag, a in self.stack if tag == "mark"]
                if marks:
                    self.marked.append((text, marks[-1]))
        if any(a.get("class") == "comment-text" for _, a in self.stack):
            self.comments.append(text)


class PacketTests(unittest.TestCase):
    def parse(self, data=None):
        html = d.packet_docx(archive() if data is None else data)
        parsed = PacketHTML(html)
        self.assertEqual(parsed.stack, [])
        self.assertEqual(len(parsed.ids), len(set(parsed.ids)))
        self.assertTrue(all(link.startswith("#") and link[1:] in parsed.ids for link in parsed.links))
        return html, parsed

    def test_complete_source_comments_digest_and_two_way_links(self):
        data = archive()
        html, parsed = self.parse(data)
        expected = "Release café 🚀: Roll out to 10%\ton Monday.\nRollback owner: operations.\nSupport route\nEnd.\n"
        self.assertEqual("".join(parsed.source), expected)
        catalog = d.catalog_docx(data)
        for item in catalog["comments"]:
            identity = item["comment_id"]
            self.assertEqual(parsed.source_markers["source-" + identity], item["start_offset"])
            self.assertIn("#source-" + identity, parsed.links)
            self.assertIn("#comment-" + identity, parsed.links)
            self.assertIn(item["text"], parsed.comments)
        self.assertIn(d.digest(data), html)
        self.assertIn("Evidence only.", html)
        self.assertIn("not human decision receipts", html)
        self.assertIn("3 comments", html)
        self.assertIn("point anchor", html)
        self.assertEqual("".join(text for text, _ in parsed.marked),
                         catalog["comments"][0]["quote"] + catalog["comments"][1]["quote"])

    def test_crossing_ranges_split_without_duplicating_text(self):
        document = DOC.replace('<w:commentRangeStart w:id="7"/>', '<w:commentRangeStart w:id="7"/><w:commentRangeStart w:id="2"/>')
        document = document.replace('<w:commentRangeStart w:id="2"/><w:hyperlink>', '<w:hyperlink>')
        _, parsed = self.parse(archive(parts(document=document)))
        self.assertEqual("".join(parsed.source), "".join(self.parse()[1].source))
        self.assertTrue(any(a.get("class") == "overlap" for _, a in parsed.marked))
        self.assertEqual(parsed.source_markers["source-7"], parsed.source_markers["source-2"])

    def test_point_and_empty_range_do_not_select_neighboring_text(self):
        document = DOC.replace('<w:commentRangeEnd w:id="7"/>', '').replace('<w:commentRangeStart w:id="7"/>', '<w:commentRangeStart w:id="7"/><w:commentRangeEnd w:id="7"/>')
        html, parsed = self.parse(archive(parts(document=document)))
        self.assertIn("empty range", html)
        self.assertIn("point anchor", html)
        self.assertEqual("".join(text for text, _ in parsed.marked), "Support route")

    def test_nested_ranges_are_well_formed(self):
        document = DOC.replace('<w:commentRangeStart w:id="7"/>', '<w:commentRangeStart w:id="7"/><w:commentRangeStart w:id="2"/>')
        document = document.replace('<w:commentRangeStart w:id="2"/><w:hyperlink>', '<w:hyperlink>')
        document = document.replace('<w:commentRangeEnd w:id="2"/>', '').replace('<w:commentRangeEnd w:id="7"/>', '<w:commentRangeEnd w:id="2"/><w:commentRangeEnd w:id="7"/>')
        self.parse(archive(parts(document=document)))

    def test_all_unsafe_text_is_inert_and_only_fragment_links_exist(self):
        attack = '&lt;script&gt;alert(1)&lt;/script&gt;&amp;&quot;'
        document = DOC.replace("Release café 🚀: ", attack)
        comments = COMMENTS.replace('w:author="Ren"', 'w:author="' + attack + '"').replace("Keep the old path.", attack)
        html, parsed = self.parse(archive(parts(document=document, comments=comments)))
        self.assertIn('<script>alert(1)</script>&"', "".join(parsed.source))
        self.assertNotIn("<script>", html)
        self.assertNotIn("<iframe", html)
        self.assertTrue(all(tag not in ("script", "iframe", "object", "form", "img") for tag, _ in parsed.tags))
        self.assertTrue(all(not any(key.startswith("on") or key in ("src", "srcdoc") for key in attrs)
                            for _, attrs in parsed.tags))
        policies = [attrs["content"] for tag, attrs in parsed.tags if tag == "meta" and attrs.get("http-equiv") == "Content-Security-Policy"]
        self.assertEqual(len(policies), 1)
        self.assertIn("default-src 'none'", policies[0])

    def test_leading_newline_is_preserved_in_html_pre(self):
        document = DOC.replace("Release café 🚀: ", "&#10;Release café 🚀: ")
        html, parsed = self.parse(archive(parts(document=document)))
        self.assertTrue("".join(parsed.source).startswith("\nRelease"))
        self.assertIn('<pre id="document-text"><span></span>\n', html)

    def test_long_passage_full_source_and_explicit_bounded_excerpt(self):
        document = DOC.replace("Roll out to 10%", "界" * 2200)
        data = archive(parts(document=document))
        html, parsed = self.parse(data)
        self.assertIn("界" * 2200, "".join(parsed.source))
        self.assertIn("Excerpt stops after 2000 characters", html)
        item = d.catalog_docx(data)["comments"][0]
        omitted = item["end_offset"] - item["start_offset"] - 2000
        self.assertIn(str(omitted) + " more remain", html)
        # Reading a packet has not truncated the public catalog contract.
        self.assertEqual(len(item["quote"]), item["end_offset"] - item["start_offset"])

    def test_limit_rejects_without_returning_partial_html(self):
        with patch.object(packet, "MAX_PACKET_BYTES", 64):
            with self.assertRaisesRegex(d.IntakeError, "exceeds 32 MiB"):
                d.packet_docx(archive())

    def test_custom_parts_utf16_and_boundary_markers(self):
        document = DOC.replace('<w:r><w:t>Release', '<w:commentRangeStart w:id="2"/><w:r><w:t>Release')
        document = document.replace('<w:commentRangeStart w:id="2"/><w:hyperlink>', '<w:hyperlink>')
        values = parts(document=document, main="custom/main.xml", comments_path="notes/comments.xml")
        values["custom/main.xml"] = values["custom/main.xml"].encode("utf-16")
        html, parsed = self.parse(archive(values))
        self.assertEqual(parsed.source_markers["source-2"], 0)
        self.assertIn("custom/main.xml", html)
        self.assertIn("notes/comments.xml", html)

    def test_missing_metadata_is_explicit(self):
        comments = COMMENTS.replace(' w:author="Ren" w:initials="R" w:date="2026-10-10T09:00:00Z"', '')
        html, _ = self.parse(archive(parts(comments=comments)))
        self.assertIn("Author not recorded", html)
        self.assertIn("Not recorded", html)

    def test_render_is_deterministic_and_does_not_alter_input(self):
        data = archive()
        before = hashlib.sha256(data).digest()
        self.assertEqual(d.packet_docx(data), d.packet_docx(data))
        self.assertEqual(hashlib.sha256(data).digest(), before)

    def test_retained_catalog_contract_matches_preexisting_example(self):
        example = pathlib.Path(d.__file__).resolve().parents[2] / "examples" / "review-docx"
        self.assertEqual(d.catalog_docx((example / "launch.docx").read_bytes()),
                         json.loads((example / "catalog.json").read_text()))

    def test_same_boundary_range_end_start_and_eof_point(self):
        document = f'''<w:document xmlns:w="{W}"><w:body>
<w:commentRangeStart w:id="7"/><w:r><w:t>A</w:t></w:r><w:commentRangeEnd w:id="7"/>
<w:r><w:commentReference w:id="7"/></w:r><w:commentRangeStart w:id="2"/>
<w:r><w:t>🚀B</w:t></w:r><w:commentRangeEnd w:id="2"/>
<w:r><w:commentReference w:id="2"/><w:commentReference w:id="11"/></w:r>
</w:body></w:document>'''
        _, parsed = self.parse(archive(parts(document=document)))
        self.assertEqual("".join(parsed.source), "A🚀B")
        self.assertEqual(parsed.source_markers, {"source-7": 0, "source-2": 1, "source-11": 3})
        self.assertFalse(any(a.get("class") == "overlap" for _, a in parsed.marked))

    def test_leading_comment_and_quote_newlines_preserved(self):
        document = DOC.replace("Roll out to 10%", "&#10;Roll out to 10%")
        comments = COMMENTS.replace("Can we rehearse", "&#10;Can we rehearse")
        html, parsed = self.parse(archive(parts(document=document, comments=comments)))
        self.assertIn('<pre class="comment-text"><span></span>\nCan we rehearse', html)
        self.assertIn('<pre class="quote"><span></span>\nRoll out', html)
        self.assertTrue(any(text.startswith("\nCan we rehearse") for text in parsed.comments))

    def test_xml_carriage_return_references_survive_html_parsing(self):
        document = DOC.replace("Release café 🚀: ", "Release&#13;&#10;café 🚀: ")
        comments = COMMENTS.replace("Can we rehearse", "Can we&#13;rehearse")
        html, parsed = self.parse(archive(parts(document=document, comments=comments)))
        self.assertIn("Release\r\ncafé", "".join(parsed.source))
        self.assertTrue(any("we\rrehearse" in text for text in parsed.comments))
        self.assertNotIn("\r", html)
        self.assertIn("&#13;", html)

    def test_actual_cli_rejects_large_render_without_partial_output(self):
        # All input XML remains within existing bounds, but HTML escaping plus
        # 1,000 repeated range excerpts would exceed the new 32 MiB output cap.
        starts = ''.join(f'<w:commentRangeStart w:id="{i}"/>' for i in range(1000))
        ends = ''.join(f'<w:commentRangeEnd w:id="{i}"/><w:r><w:commentReference w:id="{i}"/></w:r>' for i in range(1000))
        document = f'<w:document xmlns:w="{W}"><w:body><w:p>' + starts + '<w:r><w:t>' + "'" * (512 * 1024) + '</w:t></w:r>' + ends + '</w:p></w:body></w:document>'
        comments = f'<w:comments xmlns:w="{W}">' + ''.join(
            f'<w:comment w:id="{i}"><w:p><w:r><w:t>' + "'" * 3500 + '</w:t></w:r></w:p></w:comment>'
            for i in range(1000)) + '</w:comments>'
        self.assertLess(len(document.encode()), d.MAX_PART)
        self.assertLess(len(comments.encode()), d.MAX_PART)
        with tempfile.TemporaryDirectory() as folder:
            source = pathlib.Path(folder) / "large-render.docx"
            source.write_bytes(archive(parts(document=document, comments=comments)))
            result = subprocess.run([sys.executable, "-B", str(pathlib.Path(d.__file__).resolve()),
                                     "packet", str(source)], capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, b"")
            self.assertIn(b"exceeds 32 MiB", result.stderr)
            self.assertNotIn(b"Traceback", result.stderr)

    def test_actual_cli_packet_catalog_and_failure_atomicity(self):
        script = pathlib.Path(d.__file__).resolve()
        with tempfile.TemporaryDirectory() as folder:
            source = pathlib.Path(folder) / "launch with space.docx"
            source.write_bytes(archive())
            original = source.read_bytes()
            outputs = []
            for _ in range(2):
                result = subprocess.run([sys.executable, "-B", str(script), "packet", str(source)], capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, b"")
                self.parse(source.read_bytes())
                outputs.append(result.stdout)
            self.assertEqual(outputs[0], outputs[1])
            self.assertEqual(outputs[0].decode(), d.packet_docx(original))
            self.assertEqual(source.read_bytes(), original)
            # Existing real CLI catalog still produces the same public data.
            result = subprocess.run([sys.executable, "-B", str(script), "catalog", str(source)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(d.load_json(result.stdout), d.catalog_docx(original))
            for invalid in (b"bad zip", archive(parts(document=DOC.replace('<w:body>', '<w:body><w:ins/>')))):
                source.write_bytes(invalid)
                result = subprocess.run([sys.executable, "-B", str(script), "packet", str(source)], capture_output=True)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, b"")
                self.assertIn(b"review_docx:", result.stderr)
                self.assertNotIn(b"Traceback", result.stderr)
                self.assertEqual(source.read_bytes(), invalid)


if __name__ == "__main__":
    unittest.main()
