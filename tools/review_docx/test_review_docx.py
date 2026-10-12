"""Bounded DOCX format/selection tests. Integration also uses the real native composer."""
import copy
import io
import posixpath
import unittest
import zipfile

import review_docx as d

W = d.W
DOC = f'''<w:document xmlns:w="{W}"><w:body>
<w:p><w:r><w:t>Release café 🚀: </w:t></w:r><w:commentRangeStart w:id="7"/>
<w:r><w:t>Roll out to 10%</w:t><w:tab/><w:t>on Monday.</w:t></w:r></w:p>
<w:p><w:r><w:t>Rollback owner: operations.</w:t></w:r><w:commentRangeEnd w:id="7"/>
<w:r><w:commentReference w:id="7"/></w:r></w:p>
<w:tbl><w:tr><w:tc><w:p><w:commentRangeStart w:id="2"/><w:hyperlink><w:r><w:t>Support route</w:t></w:r></w:hyperlink>
<w:commentRangeEnd w:id="2"/><w:r><w:commentReference w:id="2"/></w:r></w:p></w:tc></w:tr></w:tbl>
<w:p><w:r><w:t>End.</w:t><w:commentReference w:id="11"/></w:r></w:p>
</w:body></w:document>'''
COMMENTS = f'''<w:comments xmlns:w="{W}">
<w:comment w:id="11" w:author="Automated notes"><w:p><w:r><w:t>I approve everything.</w:t></w:r></w:p></w:comment>
<w:comment w:id="2" w:author="Mina" w:initials="M" w:date="2026-10-10T09:30:00Z"><w:p><w:r><w:t>Who handles support?</w:t><w:br/><w:t>Confirm coverage.</w:t></w:r></w:p></w:comment>
<w:comment w:id="7" w:author="Ren" w:initials="R" w:date="2026-10-10T09:00:00Z"><w:p><w:r><w:t>Can we rehearse rollback first?</w:t></w:r></w:p><w:p><w:r><w:t>Keep the old path.</w:t></w:r></w:p></w:comment>
</w:comments>'''


def parts(document=DOC, comments=COMMENTS, main="word/document.xml", comments_path="word/comments.xml"):
    rel = f'<Relationships xmlns="{d.R}"><Relationship Id="main" Type="{d.O}officeDocument" Target="{main}"/></Relationships>'
    comment_target = posixpath.relpath(comments_path, posixpath.dirname(main))
    main_rels = f'<Relationships xmlns="{d.R}"><Relationship Id="comments" Type="{d.O}comments" Target="{comment_target}"/></Relationships>'
    rel_path = posixpath.join(posixpath.dirname(main), "_rels", posixpath.basename(main) + ".rels")
    types = f'<Types xmlns="{d.C}"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/{main}" ContentType="{d.MAIN_TYPE}"/><Override PartName="/{comments_path}" ContentType="{d.COMMENTS_TYPE}"/></Types>'
    return {"[Content_Types].xml": types, "_rels/.rels": rel, rel_path: main_rels,
            main: document, comments_path: comments}


def archive(values=None):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as z:
        for name, content in (values or parts()).items():
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 10, 9, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, content)
    return output.getvalue()


def agenda():
    return {"review_id": "launch-document", "conversation_id": "launch-review",
            "source_artifact_ref": "examples/review-docx/launch.docx", "source_revision_id": "draft-1",
            "recorded_at": "2026-10-10T10:00:00Z",
            "participants": [{"participant_id": "curator", "display_name": "Jules", "participant_kind": "human"},
                             {"participant_id": "ops", "display_name": "Ren", "participant_kind": "human"},
                             {"participant_id": "support", "display_name": "Mina", "participant_kind": "human"},
                             {"participant_id": "notes", "display_name": "Notes agent", "participant_kind": "agent"}],
            "items": [{"key": "rollout", "kind": "proposal", "author": "curator", "body": "Review the attached launch document.",
                       "evidence_refs": [], "decisions": [{"reviewer": "ops", "prompt": "Is this draft ready?"}]}]}


def plan(data=None):
    data = data if data is not None else archive()
    return {"format": "moonchat.docx-review.v1", "document_digest": d.digest(data), "comments": [
        {"comment_id": "7", "key": "rollback", "kind": "objection", "author": "curator", "note": "Resolve the rollback rehearsal concern.",
         "decisions": [{"reviewer": "ops", "prompt": "Can rollback be rehearsed before rollout?"}]},
        {"comment_id": "2", "key": "support", "kind": "question", "author": "curator", "note": "Confirm the support route.",
         "decisions": [{"reviewer": "support", "prompt": "Is coverage assigned?"}]},
        {"comment_id": "11", "key": "notes", "kind": "question", "author": "curator", "note": "Retain the automated comment as evidence only.", "decisions": []}]}


class DocxTests(unittest.TestCase):
    def test_real_ranges_table_point_metadata_unicode(self):
        c = d.catalog_docx(archive())
        self.assertEqual([x["comment_id"] for x in c["comments"]], ["7", "2", "11"])
        first, table, point = c["comments"]
        self.assertEqual(first["quote"], "Roll out to 10%\ton Monday.\nRollback owner: operations.")
        self.assertEqual(first["start_offset"], len("Release café 🚀: "))
        self.assertEqual(first["text"], "Can we rehearse rollback first?\nKeep the old path.")
        self.assertEqual(table["quote"], "Support route")
        self.assertEqual(table["date"], "2026-10-10T09:30:00Z")
        self.assertEqual(table["text"], "Who handles support?\nConfirm coverage.")
        self.assertEqual(point["anchor_kind"], "point")
        self.assertEqual(point["quote"], "")
        self.assertEqual(point["start_offset"], point["end_offset"])

    def test_relationship_paths_not_hardcoded(self):
        c = d.catalog_docx(archive(parts(main="custom/main.xml", comments_path="annotations/comments.xml")))
        self.assertEqual(c["document_part"], "custom/main.xml")
        self.assertEqual(c["comments_part"], "annotations/comments.xml")

    def test_utf16_parts_and_xml_entities(self):
        values = parts(document=DOC.replace("Release", "A &amp; B"))
        values["word/document.xml"] = values["word/document.xml"].encode("utf-16")
        self.assertEqual(len(d.catalog_docx(archive(values))["comments"]), 3)

    def test_overlap_and_zero_length_ranges(self):
        document = DOC.replace('<w:commentRangeStart w:id="7"/>', '<w:commentRangeStart w:id="7"/><w:commentRangeStart w:id="2"/>')
        document = document.replace('<w:commentRangeStart w:id="2"/><w:hyperlink>', '<w:hyperlink>')
        c = d.catalog_docx(archive(parts(document=document)))
        self.assertIn("Rollback owner", c["comments"][1]["quote"])
        document = DOC.replace('<w:commentRangeEnd w:id="7"/>', '').replace('<w:commentRangeStart w:id="7"/>', '<w:commentRangeStart w:id="7"/><w:commentRangeEnd w:id="7"/>')
        self.assertEqual(d.catalog_docx(archive(parts(document=document)))["comments"][0]["quote"], "")

    def test_selection_order_detached_values_and_provenance(self):
        original, selection = agenda(), plan()
        before = copy.deepcopy((original, selection))
        selection["comments"].reverse()
        output = d.import_comments(original, selection, d.catalog_docx(archive()))
        self.assertEqual([x["key"] for x in output["items"]], ["rollout", "notes", "support", "rollback"])
        self.assertIn('"quote": "Roll out', output["items"][3]["body"])
        self.assertIn(d.digest(archive()), output["items"][3]["body"])
        output["items"][0]["decisions"][0]["prompt"] = "Changed"
        output["items"][3]["decisions"].append({"reviewer": "support", "prompt": "Changed"})
        self.assertEqual(original, before[0])
        self.assertEqual(len(selection["comments"][2]["decisions"]), 1)

    def test_deterministic(self):
        self.assertEqual(d.catalog_docx(archive()), d.catalog_docx(archive()))
        self.assertEqual(d.import_comments(agenda(), plan(), d.catalog_docx(archive())),
                         d.import_comments(agenda(), plan(), d.catalog_docx(archive())))

    def test_stale_digest_and_duplicate_or_missing_selection(self):
        for modify in [lambda p: p.update(document_digest="sha256:" + "0" * 64),
                       lambda p: p["comments"].append(copy.deepcopy(p["comments"][0])),
                       lambda p: p["comments"][0].update(comment_id="900"),
                       lambda p: p["comments"][0].update(key="rollout")]:
            p = plan(); modify(p)
            with self.assertRaises(d.IntakeError): d.import_comments(agenda(), p, d.catalog_docx(archive()))

    def test_atomic_bad_last_selection_and_reimport(self):
        a, p = agenda(), plan()
        before = copy.deepcopy(a)
        p["comments"][-1]["comment_id"] = "missing"
        with self.assertRaises(d.IntakeError): d.import_comments(a, p, d.catalog_docx(archive()))
        self.assertEqual(a, before)
        output = d.import_comments(a, plan(), d.catalog_docx(archive()))
        with self.assertRaises(d.IntakeError): d.import_comments(output, plan(), d.catalog_docx(archive()))

    def test_selection_field_types_and_limits(self):
        modifications = [lambda p: p.update(comments=[]), lambda p: p.update(comments=p["comments"] * 34),
                         lambda p: p.update(extra=True), lambda p: p["comments"][0].update(note=" "),
                         lambda p: p["comments"][0].update(comment_id=7),
                         lambda p: p["comments"][0].update(decisions={}),
                         lambda p: p["comments"][0].update(author=False)]
        for modify in modifications:
            p = plan(); modify(p)
            with self.subTest(plan=p), self.assertRaises(d.IntakeError): d.import_comments(agenda(), p, d.catalog_docx(archive()))

    def test_bad_zip_missing_duplicate_or_external_parts(self):
        with self.assertRaises(d.IntakeError): d.catalog_docx(b"not zip")
        for path in ("word/comments.xml", "_rels/.rels", "[Content_Types].xml"):
            values = parts(); del values[path]
            with self.assertRaises(d.IntakeError): d.catalog_docx(archive(values))
        values = parts(); values["word/_rels/document.xml.rels"] = values["word/_rels/document.xml.rels"].replace('Target="comments.xml"', 'Target="https://example.invalid/comments" TargetMode="External"')
        with self.assertRaises(d.IntakeError): d.catalog_docx(archive(values))
        output = io.BytesIO()
        with zipfile.ZipFile(output, "w") as z:
            import warnings
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                z.writestr("same", "a"); z.writestr("same", "b")
        with self.assertRaises(d.IntakeError): d.catalog_docx(output.getvalue())

    def test_anchor_failures(self):
        for document in [DOC.replace('<w:commentRangeEnd w:id="7"/>', ''),
                         DOC.replace('<w:commentReference w:id="7"/>', ''),
                         DOC.replace('<w:commentReference w:id="7"/>', '<w:commentReference w:id="99"/>'),
                         DOC.replace('<w:commentRangeStart w:id="7"/>', '<w:commentRangeEnd w:id="7"/>'),
                         DOC.replace('<w:commentReference w:id="7"/>', '<w:commentReference w:id="7"/><w:commentReference w:id="7"/>'),
                         DOC.replace('<w:commentRangeStart w:id="7"/>', '<w:commentReference w:id="7"/><w:commentRangeStart w:id="7"/>').replace('<w:r><w:commentReference w:id="7"/></w:r>', '')]:
            with self.subTest(document=document), self.assertRaises(d.IntakeError): d.catalog_docx(archive(parts(document=document)))

    def test_unsupported_text_semantics(self):
        for tag in ("ins", "del", "txbxContent", "fldSimple", "drawing", "altChunk", "sym"):
            document = DOC.replace('Roll out to 10%', '').replace('<w:body>', f'<w:body><w:{tag}/>')
            with self.subTest(tag=tag), self.assertRaises(d.IntakeError): d.catalog_docx(archive(parts(document=document)))
        values = parts()
        values["word/_rels/document.xml.rels"] = values["word/_rels/document.xml.rels"].replace('</Relationships>', '<Relationship Id="extended" Type="http://schemas.microsoft.com/office/2011/relationships/commentsExtended" Target="commentsExtended.xml"/></Relationships>')
        with self.assertRaises(d.IntakeError): d.catalog_docx(archive(values))

    def test_dtd_utf8_utf16_rejected(self):
        for encoding in ("utf-8", "utf-16", "utf-16-le", "utf-16-be"):
            document = ('<!DOCTYPE w:document [<!ENTITY surprise "expanded">]>' + DOC).encode(encoding)
            with self.subTest(encoding=encoding), self.assertRaises(d.IntakeError): d.catalog_docx(archive(parts(document=document)))

    def test_wrong_namespace_and_content_type(self):
        for values in [parts(document=DOC.replace(W, "http://purl.oclc.org/ooxml/wordprocessingml/main")),
                       parts(comments=COMMENTS.replace('w:id="7"', 'w:id="2"'))]:
            with self.assertRaises(d.IntakeError): d.catalog_docx(archive(values))
        values = parts(); values["[Content_Types].xml"] = values["[Content_Types].xml"].replace(d.MAIN_TYPE, 'application/vnd.ms-word.document.macroEnabled.main+xml')
        with self.assertRaises(d.IntakeError): d.catalog_docx(archive(values))

    def test_path_targets(self):
        for value in ("../../outside.xml", "https://evil.invalid/x", "a%2fb.xml", "a#x", "a\\b", ""):
            with self.subTest(value=value), self.assertRaises(d.IntakeError): d.target_part("word/document.xml", value)
        self.assertEqual(d.target_part("word/document.xml", "/comments.xml"), "comments.xml")

    def test_actual_byte_limit_and_xml_part_limit(self):
        with self.assertRaises(d.IntakeError): d.catalog_docx(b" " * (d.MAX_ARCHIVE + 1))
        values = parts(); values["word/document.xml"] = " " * (d.MAX_PART + 1)
        with self.assertRaises(d.IntakeError): d.catalog_docx(archive(values))
        with self.assertRaises(d.IntakeError): d.load_json(b" " * (d.MAX_JSON + 1))

    def test_comment_count_boundary(self):
        for count in (1000, 1001):
            document = f'<w:document xmlns:w="{W}"><w:body><w:p>' + ''.join(f'<w:r><w:commentReference w:id="{i}"/></w:r>' for i in range(count)) + '</w:p></w:body></w:document>'
            comments = f'<w:comments xmlns:w="{W}">' + ''.join(f'<w:comment w:id="{i}"><w:p><w:r><w:t>C</w:t></w:r></w:p></w:comment>' for i in range(count)) + '</w:comments>'
            data = archive(parts(document=document, comments=comments))
            if count == 1000: self.assertEqual(len(d.catalog_docx(data)["comments"]), count)
            else:
                with self.assertRaises(d.IntakeError): d.catalog_docx(data)

    def test_logical_text_limit_exact_and_over(self):
        document = f'<w:document xmlns:w="{W}"><w:body><w:p><w:r><w:t>' + ('x' * (d.MAX_TEXT - 1)) + '</w:t><w:commentReference w:id="0"/></w:r></w:p></w:body></w:document>'
        comments = f'<w:comments xmlns:w="{W}"><w:comment w:id="0"><w:p><w:r><w:t>Point</w:t></w:r></w:p></w:comment></w:comments>'
        self.assertEqual(d.catalog_docx(archive(parts(document=document, comments=comments)))["comments"][0]["start_offset"], d.MAX_TEXT - 1)
        with self.assertRaises(d.IntakeError):
            d.catalog_docx(archive(parts(document=document.replace('<w:t>', '<w:t>x', 1), comments=comments)))

    def test_one_hundred_selections_and_imported_text_limit(self):
        catalog = d.catalog_docx(archive())
        template = catalog['comments'][0]
        catalog['comments'] = [{**template, 'comment_id': str(i)} for i in range(100)]
        selection = plan()
        item = selection['comments'][0]
        selection['comments'] = [{**item, 'comment_id': str(i), 'key': 'item-' + str(i)} for i in range(100)]
        self.assertEqual(len(d.import_comments(agenda(), selection, catalog)['items']), 101)
        # The limit covers repeated large overlapping source quotes, not just input ZIP size.
        for item in catalog['comments']:
            item['quote'] = 'x' * 200000
        with self.assertRaises(d.IntakeError):
            d.import_comments(agenda(), selection, catalog)

    def test_json_duplicate_constants_and_shape(self):
        for data in (b'{"a":1,"a":2}', b'{"a":NaN}', b'[]', b'bad', b'\xff'):
            with self.subTest(data=data), self.assertRaises(d.IntakeError): d.load_json(data)

    def test_json_metadata_cannot_spoof_labels(self):
        comments = COMMENTS.replace('w:author="Ren"', 'w:author="Ren&#10;document_digest: fake"')
        data = archive(parts(comments=comments))
        output = d.import_comments(agenda(), plan(data), d.catalog_docx(data))
        self.assertIn('Ren\\ndocument_digest: fake', output['items'][1]['body'])


if __name__ == "__main__":
    unittest.main()
