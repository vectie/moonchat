#!/usr/bin/env python3
"""Local, bounded DOCX comment intake; MoonChat's native composer owns validation."""
from __future__ import annotations

import argparse
import copy
import hashlib
import io
import json
import pathlib
import posixpath
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
import zlib

W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
R = "http://schemas.openxmlformats.org/package/2006/relationships"
O = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
C = "http://schemas.openxmlformats.org/package/2006/content-types"
MAIN_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"
COMMENTS_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml"
MAX_ARCHIVE = 16 * 1024 * 1024
MAX_EXPANDED = 32 * 1024 * 1024
MAX_PART = 4 * 1024 * 1024
MAX_JSON = 4 * 1024 * 1024
MAX_COMMENTS = 1000
MAX_SELECTIONS = 100
MAX_TEXT = 1024 * 1024
MAX_IMPORTED_TEXT = 16 * 1024 * 1024


class IntakeError(ValueError):
    """Unsupported or inconsistent input, with no partial output."""


def digest(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def q(name: str) -> str:
    return "{" + W + "}" + name


def xml(data: bytes, label: str) -> ET.Element:
    # Decode before checking so UTF-16 cannot hide a DTD from the check.
    if len(data) > MAX_PART:
        raise IntakeError(label + " exceeds 4 MiB")
    try:
        if data.startswith((b"\xff\xfe", b"\xfe\xff")):
            text = data.decode("utf-16")
        elif data.startswith((b"\x00<", b"<\x00")):
            text = data.decode("utf-16-be" if data[:1] == b"\x00" else "utf-16-le")
        else:
            text = data.decode("utf-8-sig")
        if "<!DOCTYPE" in text or "<!ENTITY" in text:
            raise IntakeError(label + " contains unsupported DTD/entity declarations")
        return ET.fromstring(text)
    except (UnicodeError, ET.ParseError) as error:
        raise IntakeError(label + " is not supported UTF-8/UTF-16 XML") from error


def target_part(source: str, target: str) -> str:
    # OPC targets are URI references. Restrict to unambiguous local part names.
    if not target or any(c in target for c in "\\%?#:\x00"):
        raise IntakeError("unsupported internal relationship target")
    path = posixpath.normpath(posixpath.join(posixpath.dirname(source), target))
    if target.startswith("/"):
        path = posixpath.normpath(target)[1:]
    if path in ("", ".", "..") or path.startswith("../"):
        raise IntakeError("relationship target escapes the package")
    return path


def relationships(data: bytes) -> list[ET.Element]:
    root = xml(data, "relationships")
    if root.tag != "{" + R + "}Relationships":
        raise IntakeError("unsupported relationships namespace")
    entries = list(root)
    ids = [item.get("Id") for item in entries]
    if any(item.tag != "{" + R + "}Relationship" for item in entries) or any(
        not value for value in ids
    ) or len(set(ids)) != len(ids):
        raise IntakeError("invalid or duplicate relationship identities")
    return entries


def single_target(entries: list[ET.Element], kind: str, source: str) -> str:
    matches = [item for item in entries if item.get("Type") == O + kind]
    if len(matches) != 1:
        raise IntakeError("exactly one " + kind + " relationship is required")
    item = matches[0]
    if item.get("TargetMode", "Internal") != "Internal":
        raise IntakeError(kind + " relationship must be internal; nothing is fetched")
    return target_part(source, item.get("Target", ""))


def comment_id(element: ET.Element) -> str:
    value = element.get(q("id"), "")
    if not re.fullmatch(r"0|[1-9][0-9]{0,9}", value):
        raise IntakeError("comment IDs must be canonical nonnegative decimal strings")
    return value


def check_markup(root: ET.Element, label: str) -> None:
    unsupported = {
        "ins", "del", "moveFrom", "moveTo", "altChunk", "txbxContent",
        "instrText", "fldSimple", "fldChar", "sym", "delText", "drawing",
        "pict", "object", "footnoteReference", "endnoteReference",
    }
    unsupported_tags = {q(name) for name in unsupported}
    for element in root.iter():
        if element.tag.startswith("{http://schemas.openxmlformats.org/officeDocument/2006/math}"):
            raise IntakeError(label + ": unsupported equation text")
        if element.tag in unsupported_tags:
            name = element.tag.split("}")[-1]
            raise IntakeError(label + ": unsupported " + name + "; use plain, resolved text")
        if element.tag == "{http://schemas.openxmlformats.org/markup-compatibility/2006}AlternateContent":
            raise IntakeError(label + ": unsupported alternate content")


def text_events(root: ET.Element):
    """Document-order logical text, preserving run spaces, tabs and break markers."""
    # Iterative traversal avoids recursion depth failures on otherwise bounded XML.
    stack = [(root, False)]
    while stack:
        node, leaving = stack.pop()
        if leaving:
            if node.tag == q("p"):
                yield "text", "\n"
            continue
        if node.tag == q("t"):
            yield "text", node.text or ""
        elif node.tag == q("tab"):
            yield "text", "\t"
        elif node.tag in (q("br"), q("cr")):
            yield "text", "\n"
        elif node.tag == q("noBreakHyphen"):
            yield "text", "\u2011"
        elif node.tag == q("softHyphen"):
            yield "text", "\u00ad"
        elif node.tag in (q("commentRangeStart"), q("commentRangeEnd"), q("commentReference")):
            yield node.tag.split("}")[-1], comment_id(node)
        stack.append((node, True))
        stack.extend((child, False) for child in reversed(node))


def _read_docx(data: bytes, *, quote_limit: int | None = None) -> tuple[dict, str]:
    """Read once, retaining logical text; packet excerpts may be bounded separately."""
    if len(data) > MAX_ARCHIVE:
        raise IntakeError("DOCX exceeds 16 MiB")
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            infos = archive.infolist()
            names = [item.filename for item in infos]
            if len(infos) > 2048 or len(names) != len(set(names)):
                raise IntakeError("DOCX has duplicate members or exceeds 2048 members")
            if sum(item.file_size for item in infos) > MAX_EXPANDED:
                raise IntakeError("DOCX expanded members exceed 32 MiB")
            for item in infos:
                if item.flag_bits & 1:
                    raise IntakeError("encrypted DOCX members are unsupported")
                if item.filename.startswith("/") or "\\" in item.filename or ".." in item.filename.split("/"):
                    raise IntakeError("DOCX member names must be relative package paths")

            def read(name: str) -> bytes:
                try:
                    info = archive.getinfo(name)
                except KeyError as error:
                    raise IntakeError("required DOCX part is missing: " + name) from error
                if info.file_size > MAX_PART:
                    raise IntakeError(name + " exceeds 4 MiB")
                with archive.open(info) as handle:
                    value = handle.read(MAX_PART + 1)
                if len(value) > MAX_PART:
                    raise IntakeError(name + " exceeds 4 MiB")
                return value

            main = single_target(relationships(read("_rels/.rels")), "officeDocument", "")
            rel_path = posixpath.join(posixpath.dirname(main), "_rels", posixpath.basename(main) + ".rels")
            rels = relationships(read(rel_path))
            # Classic annotations are not a faithful rendering of resolved/threaded comments.
            if any((item.get("Type", "").split("/")[-1].startswith("comments") and
                    item.get("Type") != O + "comments") for item in rels):
                raise IntakeError("extended/threaded comments are unsupported; use a classic-comment export")
            comments = single_target(rels, "comments", main)
            types = xml(read("[Content_Types].xml"), "content types")
            if types.tag != "{" + C + "}Types":
                raise IntakeError("unsupported content-types namespace")
            overrides = {}
            for child in types:
                if child.tag == "{" + C + "}Override":
                    name = child.get("PartName", "")
                    if name in overrides:
                        raise IntakeError("duplicate part content type")
                    overrides[name] = child.get("ContentType")
            if overrides.get("/" + main) != MAIN_TYPE or overrides.get("/" + comments) != COMMENTS_TYPE:
                raise IntakeError("requires non-macro DOCX main and classic comments content types")
            main_bytes, comment_bytes = read(main), read(comments)
    except (zipfile.BadZipFile, RuntimeError, NotImplementedError, OSError, zlib.error) as error:
        raise IntakeError("DOCX ZIP is invalid or uses unsupported compression") from error

    document = xml(main_bytes, "document")
    root = xml(comment_bytes, "comments")
    if document.tag != q("document") or root.tag != q("comments"):
        raise IntakeError("requires transitional WordprocessingML document/comments")
    bodies = document.findall(q("body"))
    if len(bodies) != 1:
        raise IntakeError("document must have exactly one body")
    body = bodies[0]
    check_markup(body, "document")
    check_markup(root, "comments")
    comments_by_id = {}
    for element in root:
        if element.tag != q("comment"):
            raise IntakeError("unsupported comments child")
        identity = comment_id(element)
        if identity in comments_by_id:
            raise IntakeError("duplicate comment ID")
        events = list(text_events(element))
        if any(kind != "text" for kind, _ in events):
            raise IntakeError("nested comment anchors are unsupported")
        text = "".join(value for _, value in events).removesuffix("\n")
        if not text.strip():
            raise IntakeError("comment text must not be empty")
        comments_by_id[identity] = {
            "comment_id": identity,
            "author": element.get(q("author"), ""),
            "initials": element.get(q("initials"), ""),
            "date": element.get(q("date"), ""),
            "text": text,
        }
    if not 1 <= len(comments_by_id) <= MAX_COMMENTS:
        raise IntakeError("DOCX must contain 1–1000 comments")

    chunks, starts, ends, references = [], {}, {}, {}
    position = 0
    for kind, value in text_events(body):
        if kind == "text":
            chunks.append(value)
            position += len(value)
            if position > MAX_TEXT:
                raise IntakeError("document logical text exceeds 1,048,576 Unicode characters")
        else:
            if value not in comments_by_id:
                raise IntakeError("document references an unknown comment ID")
            mapping = {"commentRangeStart": starts, "commentRangeEnd": ends, "commentReference": references}[kind]
            if value in mapping:
                raise IntakeError("duplicate " + kind + " for a comment")
            mapping[value] = position
            if kind == "commentRangeEnd" and (value not in starts or starts[value] > position):
                raise IntakeError("comment range ends before its start")
    if set(starts) != set(ends) or set(references) != set(comments_by_id):
        raise IntakeError("every comment needs one main-body reference and complete or absent range markers")
    full_text = "".join(chunks)
    output = []
    for identity, reference in references.items():
        value = dict(comments_by_id[identity])
        ranged = identity in starts
        if ranged and reference < ends[identity]:
            raise IntakeError("comment reference precedes its range end")
        begin, end = (starts[identity], ends[identity]) if ranged else (reference, reference)
        quote_end = end if quote_limit is None else min(end, begin + quote_limit)
        value.update({"anchor_kind": "range" if ranged else "point", "start_offset": begin,
                      "end_offset": end, "quote": full_text[begin:quote_end]})
        output.append(value)
    return {"format": "moonchat.docx-catalog.v1", "document_digest": digest(data),
            "document_part": main, "comments_part": comments,
            "document_xml_digest": digest(main_bytes), "comments_xml_digest": digest(comment_bytes),
            "offset_unit": "Unicode code points in logical document text; end exclusive",
            "comments": output}, full_text


def catalog_docx(data: bytes) -> dict:
    """Read classic main-body Word comments without extracting files or fetching URLs."""
    catalog, _ = _read_docx(data)
    return catalog


def packet_docx(data: bytes) -> str:
    """Render source-linked HTML through the same parser as comment import."""
    from review_docx_packet import MAX_QUOTE_PREVIEW, PacketError, render_packet
    catalog, document_text = _read_docx(data, quote_limit=MAX_QUOTE_PREVIEW)
    try:
        return render_packet(catalog, document_text)
    except PacketError as error:
        raise IntakeError(str(error)) from error


def load_json(data: bytes) -> dict:
    if len(data) > MAX_JSON:
        raise IntakeError("JSON input exceeds 4 MiB")

    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise IntakeError("JSON contains a duplicate key")
            result[key] = value
        return result

    try:
        value = json.loads(data.decode("utf-8-sig"), object_pairs_hook=pairs,
                           parse_constant=lambda _: (_ for _ in ()).throw(IntakeError("invalid JSON number")))
    except (UnicodeError, json.JSONDecodeError, RecursionError) as error:
        raise IntakeError("input is not supported JSON") from error
    if not isinstance(value, dict):
        raise IntakeError("JSON input must be an object")
    return value


def required_text(value: dict, key: str) -> str:
    text = value.get(key)
    if not isinstance(text, str) or not text.strip():
        raise IntakeError("requires nonempty string: " + key)
    return text


def import_comments(agenda: dict, plan: dict, catalog: dict) -> dict:
    """Build a detached candidate. Only compile_candidate makes it a validated output."""
    if set(plan) != {"format", "document_digest", "comments"} or plan.get("format") != "moonchat.docx-review.v1":
        raise IntakeError("plan requires moonchat.docx-review.v1 and its exact fields")
    if plan.get("document_digest") != catalog["document_digest"]:
        raise IntakeError("plan digest does not match the exact DOCX bytes; catalog again")
    choices = plan.get("comments")
    if not isinstance(choices, list) or not 1 <= len(choices) <= MAX_SELECTIONS:
        raise IntakeError("select 1–100 comments")
    result = copy.deepcopy(agenda)
    if not isinstance(result.get("items"), list):
        raise IntakeError("agenda items must be an array")
    source_ref = required_text(result, "source_artifact_ref")
    comments = {item["comment_id"]: item for item in catalog["comments"]}
    selected, keys = set(), set()
    for item in result["items"]:
        if not isinstance(item, dict) or not isinstance(item.get("key"), str):
            raise IntakeError("existing agenda item is invalid")
        keys.add(item["key"])
    fields = {"comment_id", "key", "kind", "author", "note", "decisions"}
    participants = result.get("participants")
    if not isinstance(participants, list):
        raise IntakeError("agenda participants must be an array")
    roster = {person.get("participant_id"): person for person in participants
              if isinstance(person, dict) and isinstance(person.get("participant_id"), str)}
    imported_bytes = 0
    for choice in choices:
        if not isinstance(choice, dict) or set(choice) != fields:
            raise IntakeError("each comment selection requires its exact documented fields")
        identity = required_text(choice, "comment_id")
        if identity not in comments or identity in selected:
            raise IntakeError("selected comment ID is unknown or repeated")
        selected.add(identity)
        key = required_text(choice, "key")
        if key in keys:
            raise IntakeError("selected item key already exists; use the original agenda")
        keys.add(key)
        note = required_text(choice, "note")
        for field in ("kind", "author"):
            required_text(choice, field)
        if not isinstance(choice["decisions"], list):
            raise IntakeError("decisions must be an array")
        if choice["kind"] not in ("question", "objection", "proposal"):
            raise IntakeError("selected kind must be question, objection or proposal")
        if choice["author"] not in roster:
            raise IntakeError("selected author must name an existing agenda participant")
        if choice["kind"] == "objection" and not choice["decisions"]:
            raise IntakeError("selected objection needs an explicit human decision request")
        for decision in choice["decisions"]:
            if not isinstance(decision, dict) or set(decision) != {"reviewer", "prompt"}:
                raise IntakeError("each decision requires reviewer and prompt")
            reviewer = required_text(decision, "reviewer")
            required_text(decision, "prompt")
            if reviewer not in roster or roster[reviewer].get("participant_kind") != "human":
                raise IntakeError("selected decision reviewer must name an existing human participant")
        item = comments[identity]
        # JSON-labeled evidence makes author text/newlines unable to spoof metadata.
        evidence = {"document_ref": source_ref, "document_digest": catalog["document_digest"],
                    "document_part": catalog["document_part"], "comments_part": catalog["comments_part"],
                    "document_xml_digest": catalog["document_xml_digest"],
                    "comments_xml_digest": catalog["comments_xml_digest"], **item}
        body = note + "\n\nWord comment evidence (quoted metadata, not reviewer authority):\n" + json.dumps(
            evidence, ensure_ascii=False, indent=2, allow_nan=False)
        imported_bytes += len(body.encode("utf-8"))
        if imported_bytes > MAX_IMPORTED_TEXT:
            raise IntakeError("selected comment evidence exceeds 16 MiB; select fewer ranges")
        result["items"].append({"key": key, "kind": choice["kind"], "author": choice["author"],
                                "body": body, "evidence_refs": [source_ref],
                                "decisions": copy.deepcopy(choice["decisions"])})
    return result


def compile_candidate(agenda: dict, data: bytes, composer: pathlib.Path, mode: str) -> str:
    """Use an immutable byte snapshot so the binding cannot race file replacement."""
    if not composer.is_absolute() or not composer.is_file():
        raise IntakeError("--composer must name an absolute existing native review_compose executable")
    with tempfile.TemporaryDirectory(prefix="moonchat-docx-") as temporary:
        folder = pathlib.Path(temporary)
        source, candidate = folder / "source.docx", folder / "agenda.json"
        source.write_bytes(data)
        candidate.write_text(json.dumps(agenda, ensure_ascii=False, allow_nan=False), encoding="utf-8")
        process = subprocess.run([str(composer), "preview" if mode == "preview" else "bundle",
                                  str(candidate), str(source)], capture_output=True, timeout=60)
        if process.returncode:
            details = (process.stderr or process.stdout).decode("utf-8", errors="replace").strip()[:2048]
            raise IntakeError("MoonChat composer rejected the candidate (exit " + str(process.returncode) + "): " + (details or "no diagnostic returned"))
        try:
            output = process.stdout.decode("utf-8")
        except UnicodeError as error:
            raise IntakeError("MoonChat composer returned non-UTF-8 output") from error
        if mode == "agenda":
            # Composer has validated the same candidate and exact source snapshot.
            return json.dumps(agenda, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
        return output


def bounded_read(path: pathlib.Path, maximum: int) -> bytes:
    with path.open("rb") as handle:
        data = handle.read(maximum + 1)
    if len(data) > maximum:
        raise IntakeError("input file exceeds its documented byte limit")
    return data


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Import classic Word comments into an editable, pending MoonChat review. Output is stdout only; redirect to new paths.")
    sub = parser.add_subparsers(dest="mode", required=True)
    catalog = sub.add_parser("catalog", help="inspect comment IDs, metadata and anchored document text")
    catalog.add_argument("document", type=pathlib.Path)
    packet = sub.add_parser("packet", help="read all comments beside linked logical document text in offline HTML")
    packet.add_argument("document", type=pathlib.Path)
    for mode in ("compare", "compare-packet"):
        command = sub.add_parser(mode, help="compare two explicit DOCX revisions without carrying approval forward")
        command.add_argument("before", type=pathlib.Path)
        command.add_argument("document", type=pathlib.Path, help="the later DOCX revision")
    for mode in ("replan-draft", "replan"):
        command = sub.add_parser(mode, help="explicitly carry selected discussion onto a new DOCX scope; no decisions transferred")
        command.add_argument("agenda", type=pathlib.Path, help="pre-import agenda for the new revision")
        command.add_argument("before", type=pathlib.Path)
        command.add_argument("document", type=pathlib.Path, help="the later DOCX revision")
        command.add_argument("plan", type=pathlib.Path, help="original selection plan bound to the before DOCX")
        if mode == "replan":
            command.add_argument("recipe", type=pathlib.Path, help="completed replan draft with explicit choices")
    planning = sub.add_parser("plan-packet", help="read proposed agenda decisions beside exact DOCX passages; draft only")
    planning.add_argument("agenda", type=pathlib.Path)
    planning.add_argument("document", type=pathlib.Path)
    planning.add_argument("plan", type=pathlib.Path)
    for mode in ("agenda", "preview", "bundle"):
        command = sub.add_parser(mode, help="select comments and validate through the existing native MoonChat composer")
        command.add_argument("agenda", type=pathlib.Path)
        command.add_argument("document", type=pathlib.Path)
        command.add_argument("plan", type=pathlib.Path)
        command.add_argument("--composer", type=pathlib.Path, required=True)
    args = parser.parse_args(argv)
    try:
        data = bounded_read(args.document, MAX_ARCHIVE)
        if args.mode in ("replan-draft", "replan"):
            from review_docx_replan import draft_replan, apply_replan
            inputs = (bounded_read(args.agenda, MAX_JSON), bounded_read(args.before, MAX_ARCHIVE),
                      data, bounded_read(args.plan, MAX_JSON))
            result = (draft_replan(*inputs) if args.mode == "replan-draft" else
                      apply_replan(*inputs, bounded_read(args.recipe, MAX_JSON)))
            output = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
            if len(output.encode("utf-8")) > MAX_JSON:
                raise IntakeError("replan output exceeds the 4 MiB input limit; no partial output emitted")
            sys.stdout.write(output)
            return 0
        if args.mode in ("compare", "compare-packet"):
            from review_docx_compare import compare_docx, render_comparison
            before = bounded_read(args.before, MAX_ARCHIVE)
            report = compare_docx(before, data)
            result = (render_comparison(report) if args.mode == "compare-packet" else
                      json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
            if len(result.encode("utf-8")) > 32 * 1024 * 1024:
                raise IntakeError("DOCX comparison exceeds 32 MiB; no partial output emitted")
            sys.stdout.write(result)
            return 0
        if args.mode == "plan-packet":
            from review_docx_plan import planning_packet
            result = planning_packet(bounded_read(args.agenda, MAX_JSON), data,
                                     bounded_read(args.plan, MAX_JSON))
            sys.stdout.write(result)
            return 0
        if args.mode == "packet":
            sys.stdout.write(packet_docx(data))
            return 0
        catalog = catalog_docx(data)
        if args.mode == "catalog":
            result = json.dumps(catalog, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
        else:
            agenda = import_comments(load_json(bounded_read(args.agenda, MAX_JSON)),
                                     load_json(bounded_read(args.plan, MAX_JSON)), catalog)
            result = compile_candidate(agenda, data, args.composer, args.mode)
        sys.stdout.write(result)
        return 0
    except (IntakeError, OSError, subprocess.TimeoutExpired, RecursionError) as error:
        if isinstance(error, IntakeError):
            message = str(error)
        elif isinstance(error, subprocess.TimeoutExpired):
            message = "MoonChat composer timed out"
        elif isinstance(error, RecursionError):
            message = "input nesting is too deep"
        else:
            message = "could not read input or execute composer"
        print("review_docx: " + message, file=sys.stderr)
        return 1


if __name__ == "__main__":
    # Companion modules share this parser and its error class in actual CLI runs.
    sys.modules["review_docx"] = sys.modules[__name__]
    raise SystemExit(main())
