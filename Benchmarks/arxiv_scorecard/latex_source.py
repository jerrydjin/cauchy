"""Build a reader index from an arXiv paper's LaTeX source.

The e-print at ``https://arxiv.org/e-print/<id>`` is a tar.gz, a gzipped
``.tex`` file, or a PDF-only submission. This module unpacks it, reads a
pragmatic subset (the main file, ``\\input`` / ``\\include``, sections,
``\\newtheorem`` including shared counters, theorem environments, labels and
refs, ``\\cite`` with a ``.bbl`` or ``thebibliography``, and simple
``\\newcommand`` expansion), and places each item on a PDF page by matching
text.

Anything unrecognised, any failure, and any source that does not line up with
the PDF returns no index. The caller keeps the PDF heuristics. Items that
cannot be placed on a page are left out. This module never raises to its caller.
"""

from __future__ import annotations

import gzip
import io
import re
import tarfile
from dataclasses import dataclass, field
from pathlib import Path

from arxiv_id import ArxivId, detect
from cauchy_logic import (
    IndexedStatement,
    OutlineNode,
    PageSnapshot,
    StatementIndex,
    Structure,
    is_likely_table_of_contents,
)

CACHE = Path(__file__).resolve().parent / "cache" / "eprint"

_BOOK_CLASSES = {"book", "amsbook", "report", "memoir", "scrbook", "scrreprt"}

# Printed heads the reader already knows. The last word of the head is the kind.
_KINDS = {
    "theorem": "theorem",
    "thm": "theorem",
    "lemma": "lemma",
    "lem": "lemma",
    "proposition": "proposition",
    "prop": "proposition",
    "corollary": "corollary",
    "cor": "corollary",
    "definition": "definition",
    "def": "definition",
    "remark": "remark",
    "example": "example",
    "exercise": "exercise",
    "proof": "proof",
    "conjecture": "conjecture",
    "claim": "claim",
    "assumption": "assumption",
    "hypothesis": "hypothesis",
    "notation": "notation",
    "question": "question",
    "problem": "problem",
    "fact": "fact",
    "observation": "observation",
    "note": "note",
}
# Counters whose printed form we track. Anything else, including \\theta,
# is left alone.
_NUMBERED_COUNTERS = {
    "equation",
    "section",
    "subsection",
    "subsubsection",
    "chapter",
    "part",
} | set(_KINDS.values())

# Kinds that go into the statement index the scorecard compares.
_INDEX_KINDS = {
    "theorem",
    "lemma",
    "proposition",
    "corollary",
    "definition",
    "remark",
    "example",
    "exercise",
    "equation",
    "proof",
}
# Seeing one of these environments with no definition means the numbering
# lives in a class file this parser does not know. Fall back.
_THEOREM_ENVS = set(_KINDS) | {f"{name}*" for name in _KINDS}
_UNNUMBERED_KNOWN = {"proof", "proof*"}

_EQUATION_SINGLE = {"equation", "equation*", "multline", "multline*", "displaymath"}
_EQUATION_LINES = {
    "align",
    "align*",
    "gather",
    "gather*",
    "flalign",
    "flalign*",
    "alignat",
    "alignat*",
    "eqnarray",
    "eqnarray*",
}
_INNER_MATH = {
    "split",
    "aligned",
    "gathered",
    "alignedat",
    "cases",
    "dcases",
    "matrix",
    "pmatrix",
    "bmatrix",
    "vmatrix",
    "Vmatrix",
    "array",
    "subarray",
    "smallmatrix",
}
_VERBATIM_ENVS = {"verbatim", "verbatim*", "Verbatim", "Verbatim*", "lstlisting", "minted", "comment", "alltt"}
_CITE_COMMANDS = {
    "cite",
    "Cite",
    "citep",
    "citet",
    "citealp",
    "citealt",
    "citeauthor",
    "citeyear",
    "parencite",
    "Parencite",
    "textcite",
    "Textcite",
    "autocite",
    "Autocite",
    "footcite",
    "smartcite",
    "supercite",
}
_REF_COMMANDS = {"ref", "eqref", "cref", "Cref", "autoref", "Autoref"}
_PROTECTED = {
    "begin",
    "end",
    "section",
    "subsection",
    "subsubsection",
    "chapter",
    "part",
    "input",
    "include",
    "label",
    "ref",
    "eqref",
    "cite",
    "bibliography",
    "newcommand",
    "renewcommand",
    "providecommand",
    "newtheorem",
    "documentclass",
    "appendix",
}
_DECLARE_KEYS = {
    "style",
    "name",
    "title",
    "sibling",
    "numberlike",
    "numberwithin",
    "parent",
    "sharenumber",
    "unnumbered",
    "numbered",
    "refname",
    "Refname",
    "qed",
}
_FORMAT_COMMANDS = {"arabic", "Alph", "alph", "Roman", "roman"}
_ROMAN = (
    (1000, "M"),
    (900, "CM"),
    (500, "D"),
    (400, "CD"),
    (100, "C"),
    (90, "XC"),
    (50, "L"),
    (40, "XL"),
    (10, "X"),
    (9, "IX"),
    (5, "V"),
    (4, "IV"),
    (1, "I"),
)


class Unrecognised(Exception):
    """The source uses a construct this parser will not guess at."""


@dataclass
class Macro:
    name: str
    body: str
    required: int
    optional_default: str | None = None


@dataclass
class TheoremDef:
    env: str
    head: str
    kind: str
    shared: str | None
    parent: str | None
    starred: bool


@dataclass
class ParsedItem:
    role: str  # statement, equation, section
    kind: str
    number: str
    head: str
    title: str
    body: str
    level: int = 0
    page_index: int | None = None


@dataclass
class BibEntry:
    key: str
    label: str
    body: str


@dataclass
class ParsedSource:
    items: list[ParsedItem] = field(default_factory=list)
    labels: dict[str, tuple[str, str]] = field(default_factory=dict)
    refs: list[dict] = field(default_factory=list)
    citations: list[list[str]] = field(default_factory=list)
    bibliography: list[BibEntry] = field(default_factory=list)


@dataclass
class SourceIndex:
    statement_index: StatementIndex
    locator: Structure
    parsed: ParsedSource
    identifier: ArxivId
    located_statements: int
    omitted_statements: int
    located_sections: int
    omitted_sections: int


def build_source_index(
    pdf_path: str,
    extracted: dict,
    cache_dir: Path | None = None,
    fetcher=None,
) -> tuple[SourceIndex | None, str]:
    """Return ``(index, reason)``. ``index`` is None when the PDF path should be used."""
    try:
        metadata = extracted.get("metadata")
        if metadata is None:
            metadata = _pdf_metadata(pdf_path)
        first = ""
        pages = extracted.get("pages") or []
        if pages:
            first = pages[0].get("text") or ""
        found = detect(pdf_path, metadata, first)
        if found is None:
            return None, "no arXiv id"
        blob = fetcher(found) if fetcher is not None else _fetch(found, cache_dir or CACHE)
        files = unpack_eprint(blob)
        if files is None:
            return None, "pdf-only submission"
        parsed = parse_files(files, found)
        _map_items(parsed, extracted)
        if not _lines_up(parsed):
            return None, "source text does not line up with the PDF"
        index = StatementIndex()
        located_statements = 0
        omitted_statements = 0
        located_sections = 0
        omitted_sections = 0
        for item in parsed.items:
            if item.role == "section":
                if item.page_index is None:
                    omitted_sections += 1
                else:
                    located_sections += 1
                continue
            if item.page_index is None:
                omitted_statements += 1
                continue
            located_statements += 1
            if item.kind not in _INDEX_KINDS or not item.number:
                continue
            body = item.body.strip() or f"{item.head} {item.number}".strip()
            if not body:
                omitted_statements += 1
                located_statements -= 1
                continue
            name = item.title or None
            index.add(IndexedStatement(item.kind, item.number, item.page_index, body[:1600], name))
        if located_statements == 0 and omitted_statements == 0 and located_sections == 0:
            return None, "source had no indexable items"
        locator = _locator(parsed, extracted)
        return SourceIndex(
            statement_index=index,
            locator=locator,
            parsed=parsed,
            identifier=found,
            located_statements=located_statements,
            omitted_statements=omitted_statements,
            located_sections=located_sections,
            omitted_sections=omitted_sections,
        ), "latex"
    except Unrecognised as error:
        return None, f"unrecognised: {error}"
    except Exception as error:  # noqa: BLE001 — the PDF path is the fallback
        return None, f"failed: {error.__class__.__name__}: {error}"


def unpack_eprint(blob: bytes) -> dict[str, str] | None:
    """Map member name to text. None means the submission is a PDF."""
    if blob.startswith(b"%PDF"):
        return None
    data = blob
    if blob[:2] == b"\x1f\x8b":
        try:
            data = gzip.decompress(blob)
        except Exception as error:  # noqa: BLE001
            raise Unrecognised(f"gzip: {error.__class__.__name__}") from error
        if data.startswith(b"%PDF"):
            return None
    files = _tar_members(data)
    if files is None:
        files = _tar_members(blob)
    if files is not None:
        return files
    if _looks_like_tex(data):
        return {"main.tex": data.decode("utf-8", "replace")}
    raise Unrecognised("e-print is neither a TeX archive nor a PDF")


def parse_latex(tex: str, extra_files: dict[str, str] | None = None) -> ParsedSource:
    """Parse one synthetic document. Used by tests and by ``parse_files``."""
    files = {"main.tex": tex}
    if extra_files:
        files.update(extra_files)
    return parse_files(files, None)


def parse_files(files: dict[str, str], arxiv_id: ArxivId | None) -> ParsedSource:
    cleaned = {name: _preprocess(text) for name, text in files.items() if "\x00" not in text[:2000]}
    main = _choose_main(cleaned, arxiv_id)
    inlined = _inline(cleaned[main], cleaned, {main}, main)
    bundle = _definition_sources(inlined, cleaned)
    macros: dict[str, Macro] = {}
    _scan_definitions(bundle, macros, {}, Counters(), include_macros=True, include_structure=False)
    expanded = _expand(inlined, macros)
    counters = Counters()
    counters.apply_class(_class_name(expanded))
    theorems: dict[str, TheoremDef] = {}
    # Heads and \\numberwithin are read after macro expansion so a head
    # written as a \\newcommand resolves before the counter is registered.
    _scan_definitions(
        _expand(bundle, macros),
        macros,
        theorems,
        counters,
        include_macros=False,
        include_structure=True,
    )
    # Drop definitions before expansion so a renewed length such as
    # \\arraystretch is not expanded inside its own definition.
    stripped = _strip_definitions(inlined)
    expanded = _expand(stripped, macros)
    body = _document_body(expanded)
    return _walk(body, theorems, counters)


# --- unpacking ----------------------------------------------------------------


def _looks_like_tex(data: bytes) -> bool:
    head = data[:8000]
    if b"\x00" in head:
        return False
    text = head.decode("utf-8", "replace")
    return "\\documentclass" in text or "\\begin{document}" in text


def _safe_name(name: str) -> str | None:
    cleaned = name.replace("\\", "/").lstrip("/")
    parts = [part for part in cleaned.split("/") if part not in {"", "."}]
    if not parts or any(part == ".." for part in parts):
        return None
    return "/".join(parts)


def _tar_members(data: bytes) -> dict[str, str] | None:
    try:
        archive = tarfile.open(fileobj=io.BytesIO(data), mode="r:*")
    except tarfile.TarError:
        return None
    files: dict[str, str] = {}
    try:
        for member in archive.getmembers():
            if not member.isfile() or member.size > 2_000_000:
                continue
            name = _safe_name(member.name)
            if name is None:
                continue
            suffix = Path(name).suffix.lower()
            if suffix not in {".tex", ".ltx", ".sty", ".cls", ".bbl"}:
                continue
            extracted = archive.extractfile(member)
            if extracted is None:
                continue
            payload = extracted.read()
            if b"\x00" in payload[:2000]:
                continue
            files[name] = payload.decode("utf-8", "replace")
    finally:
        archive.close()
    if not files:
        return None
    return files


def _pdf_metadata(path: str) -> dict:
    import pymupdf

    document = pymupdf.open(path)
    try:
        return dict(document.metadata or {})
    finally:
        document.close()


def _fetch(arxiv_id: ArxivId, cache_dir: Path) -> bytes:
    path = cache_dir / f"{arxiv_id.cache_key}.bin"
    if path.exists() and path.stat().st_size > 50:
        return path.read_bytes()
    # Imported lazily so tests can pass a fetcher and skip the network.
    from run import _get

    blob = _get(f"https://arxiv.org/e-print/{arxiv_id.fetch_id}", timeout=90)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(blob)
    return blob


# --- text ----------------------------------------------------------------------


def _preprocess(tex: str) -> str:
    return _strip_comments(_mask_verbatim(tex))


def _strip_comments(tex: str) -> str:
    out: list[str] = []
    index = 0
    length = len(tex)
    while index < length:
        char = tex[index]
        if char == "\\":
            out.append(char)
            index += 1
            if index < length:
                out.append(tex[index])
                index += 1
            continue
        if char == "%":
            while index < length and tex[index] != "\n":
                index += 1
            continue
        out.append(char)
        index += 1
    return "".join(out)


def _mask_verbatim(tex: str) -> str:
    out: list[str] = []
    index = 0
    length = len(tex)
    while index < length:
        if tex.startswith("\\verb", index) and not _command_continues(tex, index + 5):
            index = _skip_verb(tex, index)
            out.append(" ")
            continue
        begin = _begin_at(tex, index)
        if begin is not None and begin[0] in _VERBATIM_ENVS:
            end = tex.find(f"\\end{{{begin[0]}}}", begin[1])
            if end < 0:
                raise Unrecognised(f"unclosed {begin[0]}")
            out.append(" ")
            index = end + len(f"\\end{{{begin[0]}}}")
            continue
        out.append(tex[index])
        index += 1
    return "".join(out)


def _command_continues(tex: str, index: int) -> bool:
    return index < len(tex) and (tex[index].isalpha() or tex[index] == "@")


def _skip_verb(tex: str, index: int) -> int:
    cursor = index + 5
    if cursor < len(tex) and tex[cursor] == "*":
        cursor += 1
    if cursor >= len(tex):
        raise Unrecognised("unclosed verb")
    delimiter = tex[cursor]
    cursor += 1
    while cursor < len(tex) and tex[cursor] != delimiter:
        cursor += 1
    if cursor >= len(tex):
        raise Unrecognised("unclosed verb")
    return cursor + 1


def _begin_at(tex: str, index: int) -> tuple[str, int] | None:
    if not tex.startswith("\\begin", index) or _command_continues(tex, index + 6):
        return None
    cursor = _skip_space(tex, index + 6)
    group = _read_group(tex, cursor)
    if group is None:
        return None
    return group[0].strip(), group[1]


def _skip_space(tex: str, index: int) -> int:
    while index < len(tex) and tex[index] in " \t\r\n":
        index += 1
    return index


def _read_command(tex: str, index: int) -> tuple[str, int] | None:
    if index >= len(tex) or tex[index] != "\\":
        return None
    cursor = index + 1
    if cursor >= len(tex):
        return None
    if tex[cursor].isalpha() or tex[cursor] == "@":
        start = cursor
        cursor += 1
        while cursor < len(tex) and (tex[cursor].isalpha() or tex[cursor] == "@"):
            cursor += 1
        return tex[start:cursor], cursor
    return tex[cursor], cursor + 1


def _read_group(tex: str, index: int) -> tuple[str, int] | None:
    index = _skip_space(tex, index)
    if index >= len(tex) or tex[index] != "{":
        return None
    depth = 0
    cursor = index
    while cursor < len(tex):
        char = tex[cursor]
        if char == "\\":
            cursor += 2
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return tex[index + 1 : cursor], cursor + 1
        cursor += 1
    return None


def _read_optional(tex: str, index: int) -> tuple[str, int] | None:
    index = _skip_space(tex, index)
    if index >= len(tex) or tex[index] != "[":
        return None
    depth_brace = 0
    depth_bracket = 0
    cursor = index
    while cursor < len(tex):
        char = tex[cursor]
        if char == "\\":
            cursor += 2
            continue
        if char == "{":
            depth_brace += 1
        elif char == "}" and depth_brace:
            depth_brace -= 1
        elif char == "[" and depth_brace == 0:
            depth_bracket += 1
        elif char == "]" and depth_brace == 0:
            depth_bracket -= 1
            if depth_bracket == 0:
                return tex[index + 1 : cursor], cursor + 1
        cursor += 1
    return None


def _read_filename(tex: str, index: int) -> tuple[str, int]:
    index = _skip_space(tex, index)
    if index < len(tex) and tex[index] == "{":
        group = _read_group(tex, index)
        if group is None:
            raise Unrecognised("broken file name")
        return group[0].strip(), group[1]
    start = index
    while index < len(tex) and tex[index] not in " \t\r\n%{":
        if tex[index] == "\\":
            break
        index += 1
    if start == index:
        raise Unrecognised("missing file name")
    return tex[start:index].strip(), index


# --- files and definitions -----------------------------------------------------


def _choose_main(files: dict[str, str], arxiv_id: ArxivId | None) -> str:
    mains = [name for name, text in files.items() if "\\documentclass" in text]
    if not mains:
        raise Unrecognised("no documentclass")
    if len(mains) == 1:
        return mains[0]

    def depth(name: str) -> int:
        return name.count("/")

    shallow = [name for name in mains if depth(name) == min(depth(item) for item in mains)]
    if len(shallow) == 1:
        return shallow[0]
    if arxiv_id is not None:
        token = arxiv_id.identifier.replace("/", "_")
        named = [name for name in shallow if token in Path(name).name]
        if len(named) == 1:
            return named[0]
    preferred = [
        name
        for name in shallow
        if Path(name).stem.lower() in {"main", "paper", "manuscript", "article", "ms"}
    ]
    if len(preferred) == 1:
        return preferred[0]
    raise Unrecognised("multiple documentclass files")


def _resolve(token: str, files: dict[str, str], main: str) -> str | None:
    token = token.strip().strip("{}")
    if not token or token.startswith("/") or ".." in token.split("/"):
        return None
    directory = str(Path(main).parent)
    if directory == ".":
        directory = ""
    candidates = [token]
    if not Path(token).suffix:
        candidates.extend([token + ".tex", token + ".ltx", token + ".bbl", token + ".sty"])
    ordered: list[str] = []
    for candidate in candidates:
        if directory:
            ordered.append(f"{directory}/{candidate}")
        ordered.append(candidate)
    for candidate in ordered:
        if candidate in files:
            return candidate
    tail_matches = []
    for name in files:
        for candidate in candidates:
            if name == candidate or name.endswith("/" + candidate):
                tail_matches.append(name)
    unique = list(dict.fromkeys(tail_matches))
    if len(unique) == 1:
        return unique[0]
    if len(unique) > 1:
        raise Unrecognised(f"ambiguous input {token}")
    return None


def _inline(tex: str, files: dict[str, str], stack: set[str], main: str) -> str:
    out: list[str] = []
    index = 0
    length = len(tex)
    while index < length:
        if tex[index] != "\\":
            out.append(tex[index])
            index += 1
            continue
        command = _read_command(tex, index)
        if command is None:
            out.append(tex[index])
            index += 1
            continue
        name, cursor = command
        if name == "endinput":
            break
        if name in {"input", "include"}:
            filename, cursor = _read_filename(tex, cursor)
            if filename.endswith(".bbl") or name == "include":
                resolved = _resolve(filename, files, main)
            else:
                resolved = _resolve(filename, files, main)
            if resolved is None and _optional_input(name, filename):
                index = cursor
                continue
            if resolved is None:
                raise Unrecognised(f"missing {name} {filename}")
            if resolved in stack:
                raise Unrecognised(f"input cycle at {filename}")
            out.append(_inline(files[resolved], files, stack | {resolved}, main))
            index = cursor
            continue
        if name == "InputIfFileExists":
            filename, cursor = _read_filename(tex, cursor)
            resolved = _resolve(filename, files, main)
            # The then-clause runs only when the file exists, and the file is input.
            then_group = _read_group(tex, cursor)
            else_group = _read_group(tex, then_group[1]) if then_group else None
            if resolved is None:
                if else_group is not None:
                    out.append(else_group[0])
                index = else_group[1] if else_group else cursor
                continue
            if resolved in stack:
                raise Unrecognised(f"input cycle at {filename}")
            if then_group is not None:
                out.append(then_group[0])
            out.append(_inline(files[resolved], files, stack | {resolved}, main))
            index = else_group[1] if else_group else (then_group[1] if then_group else cursor)
            continue
        if name == "bibliography":
            group = _read_group(tex, cursor)
            if group is None:
                raise Unrecognised("broken bibliography")
            for part in group[0].split(","):
                resolved = _resolve(part.strip() + ".bbl", files, main)
                if resolved is not None and resolved not in stack:
                    out.append(_inline(files[resolved], files, stack | {resolved}, main))
            index = group[1]
            continue
        out.append(tex[index:cursor])
        index = cursor
    return "".join(out)


def _optional_input(name: str, filename: str) -> bool:
    # Picture and generated-index inputs are not part of the reader index.
    suffix = Path(filename).suffix.lower()
    return suffix in {".pdf", ".png", ".jpg", ".jpeg", ".eps", ".ps"}


def _definition_sources(inlined: str, files: dict[str, str]) -> str:
    """Local class and style files named by the document, plus the document."""
    chunks = [inlined]
    seen: set[str] = set()
    for match in re.finditer(r"\\(?:documentclass|usepackage|RequirePackage)(?:\[[^\]]*\])?\{([^}]+)\}", inlined):
        for part in match.group(1).split(","):
            token = part.strip()
            if not token:
                continue
            for suffix in (".sty", ".cls", ""):
                name = token if token.endswith((".sty", ".cls")) else token + suffix
                resolved = None
                for candidate, _text in files.items():
                    if candidate == name or candidate.endswith("/" + name):
                        resolved = candidate
                        break
                if resolved is None or resolved in seen:
                    continue
                seen.add(resolved)
                text = files[resolved]
                if "\\ProvidesClass" in text[:400] and any(
                    klass in text[:400] for klass in ("{amsart}", "{amsbook}", "{article}", "{book}")
                ):
                    continue
                chunks.append(text)
                break
    return "\n".join(chunks)


def _strip_definitions(tex: str) -> str:
    """Remove theorem and macro definitions so the body walk does not re-read them."""
    out: list[str] = []
    index = 0
    length = len(tex)
    while index < length:
        if tex[index] != "\\":
            out.append(tex[index])
            index += 1
            continue
        command = _read_command(tex, index)
        if command is None:
            out.append(tex[index])
            index += 1
            continue
        name, cursor = command
        if name not in {"newcommand", "renewcommand", "providecommand", "newtheorem", "declaretheorem"}:
            out.append(tex[index:cursor])
            index = cursor
            continue
        try:
            if name in {"newcommand", "renewcommand", "providecommand"}:
                cursor = _read_macro(tex, cursor, {})
            elif name == "newtheorem":
                cursor = _read_newtheorem(tex, cursor, {}, Counters())
            else:
                cursor = _read_declaretheorem(tex, cursor, {}, Counters())
        except Unrecognised:
            out.append(tex[index:cursor])
            index = cursor
            continue
        index = cursor
    return "".join(out)


def _document_body(tex: str) -> str:
    begin = re.search(r"\\begin\{document\}", tex)
    end = re.search(r"\\end\{document\}", tex)
    if begin is None or end is None or end.start() < begin.end():
        raise Unrecognised("no document body")
    return tex[begin.end() : end.start()]


def _class_name(tex: str) -> str:
    found = re.search(r"\\documentclass(?:\[[^\]]*\])?\{([^}]+)\}", tex)
    if found is None:
        return ""
    return found.group(1).strip().split(",")[0].strip()


# --- counters ------------------------------------------------------------------


def _to_roman(number: int) -> str:
    if not 1 <= number <= 40:
        raise Unrecognised("roman numeral out of range")
    parts: list[str] = []
    value = number
    for amount, glyph in _ROMAN:
        while value >= amount:
            parts.append(glyph)
            value -= amount
    return "".join(parts)


class Counters:
    def __init__(self) -> None:
        self.value: dict[str, int] = {
            "chapter": 0,
            "section": 0,
            "subsection": 0,
            "subsubsection": 0,
            "equation": 0,
            "enumiv": 0,
        }
        self.parent: dict[str, str] = {
            "subsection": "section",
            "subsubsection": "subsection",
        }
        self.form: dict[str, list[tuple[str, str]]] = {
            "chapter": [("arabic", "chapter")],
            "section": [("arabic", "section")],
            "subsection": [("the", "section"), ("literal", "."), ("arabic", "subsection")],
            "subsubsection": [("the", "subsection"), ("literal", "."), ("arabic", "subsubsection")],
            "equation": [("arabic", "equation")],
        }
        self.alias: dict[str, str] = {}
        self.book = False
        self.appendix = False
        self.frontmatter = False

    def apply_class(self, name: str) -> None:
        klass = name.split("/")[-1]
        if klass in _BOOK_CLASSES:
            self.book = True
            self.parent["section"] = "chapter"
            self.form["section"] = [("the", "chapter"), ("literal", "."), ("arabic", "section")]
        # Equation numbering is not implied by the class. Authors who want
        # (1.1) write \\numberwithin or redefine \\theequation.

    def _within(self, child: str, parent: str) -> None:
        self.parent[child] = parent
        self.form[child] = [("the", parent), ("literal", "."), ("arabic", child)]
        self.value.setdefault(child, 0)
        self.value.setdefault(parent, 0)

    def target(self, name: str) -> str:
        seen = set()
        while name in self.alias:
            if name in seen:
                raise Unrecognised(f"cyclic counter {name}")
            seen.add(name)
            name = self.alias[name]
        return name

    def step(self, name: str) -> str:
        actual = self.target(name)
        self.value[actual] = self.value.get(actual, 0) + 1
        self._reset_children(actual)
        return actual

    def _reset_children(self, parent: str) -> None:
        for child, owner in list(self.parent.items()):
            if owner == parent and child != parent:
                self.value[child] = 0
                self._reset_children(child)

    def set_value(self, name: str, number: int) -> None:
        actual = self.target(name)
        self.value[actual] = number

    def format(self, name: str, stack: tuple[str, ...] = ()) -> str:
        actual = self.target(name)
        if actual in stack:
            raise Unrecognised(f"cyclic number format {actual}")
        spec = self.form.get(actual)
        if spec is None:
            return str(self.value.get(actual, 0))
        return self._render(spec, stack + (actual,))

    def _render(self, spec: list[tuple[str, str]], stack: tuple[str, ...]) -> str:
        parts: list[str] = []
        for kind, arg in spec:
            if kind == "literal":
                parts.append(arg)
                continue
            if kind == "the":
                parts.append(self.format(arg, stack))
                continue
            number = self.value.get(self.target(arg), 0)
            if kind == "arabic":
                parts.append(str(number))
            elif kind == "Alph":
                if not 1 <= number <= 26:
                    raise Unrecognised("alphabet counter out of range")
                parts.append(chr(ord("A") + number - 1))
            elif kind == "alph":
                if not 1 <= number <= 26:
                    raise Unrecognised("alphabet counter out of range")
                parts.append(chr(ord("a") + number - 1))
            elif kind == "Roman":
                parts.append(_to_roman(number))
            elif kind == "roman":
                parts.append(_to_roman(number).lower())
            else:
                raise Unrecognised(f"number format {kind}")
        return "".join(parts)

    def enter_appendix(self) -> None:
        self.appendix = True
        if self.book:
            self.form["chapter"] = [("Alph", "chapter")]
            self.value["chapter"] = 0
            self._reset_children("chapter")
        else:
            self.form["section"] = [("Alph", "section")]
            self.value["section"] = 0
            self._reset_children("section")


def _parse_format(body: str) -> list[tuple[str, str]]:
    spec: list[tuple[str, str]] = []
    index = 0
    while index < len(body):
        if body[index].isspace():
            index += 1
            continue
        if body[index] != "\\":
            start = index
            while index < len(body) and body[index] != "\\":
                index += 1
            spec.append(("literal", body[start:index]))
            continue
        command = _read_command(body, index)
        if command is None:
            raise Unrecognised("broken number format")
        name, index = command
        if name in _FORMAT_COMMANDS:
            group = _read_group(body, index)
            if group is None:
                raise Unrecognised(f"\\{name} needs a counter")
            spec.append((name, group[0].strip()))
            index = group[1]
            continue
        if name.startswith("the") and len(name) > 3:
            spec.append(("the", name[3:]))
            continue
        raise Unrecognised(f"number format \\{name}")
    if not spec:
        raise Unrecognised("empty number format")
    return spec


# --- definition scan -----------------------------------------------------------


def _kind_of_head(head: str) -> str:
    """Map a printed head to a reader kind.

    ``Main Theorem`` is a theorem. A head this parser has not seen before,
    such as an addendum, keeps its own kind so the shared counter still
    advances, and is left out of the statement index.
    """
    words = re.findall(r"[A-Za-z]+", _plain(head))
    if not words:
        raise Unrecognised(f"theorem head {head!r}")
    return _KINDS.get(words[-1].lower(), words[-1].lower())


def _scan_definitions(
    tex: str,
    macros: dict[str, Macro],
    theorems: dict[str, TheoremDef],
    counters: Counters,
    include_macros: bool,
    include_structure: bool = False,
) -> None:
    index = 0
    length = len(tex)
    while index < length:
        if tex[index] != "\\":
            index += 1
            continue
        command = _read_command(tex, index)
        if command is None:
            index += 1
            continue
        name, cursor = command
        if name in {"newcommand", "renewcommand", "providecommand"}:
            formatted = _maybe_number_format(tex, cursor, counters) if include_structure else None
            if formatted is not None:
                cursor = formatted
            elif include_macros:
                cursor = _read_macro(tex, cursor, macros)
            else:
                # A definition body is a template. Reading \newtheorem inside it
                # would treat #1 as an environment name.
                cursor = _skip_macro_definition(tex, cursor, name)
        elif include_structure and name == "newtheorem":
            cursor = _read_newtheorem(tex, cursor, theorems, counters)
        elif include_structure and name == "declaretheorem":
            cursor = _read_declaretheorem(tex, cursor, theorems, counters)
        elif include_structure and name in {"numberwithin", "counterwithin"}:
            cursor = _read_within(tex, cursor, counters)
        elif include_structure and name == "@addtoreset":
            cursor = _read_addtoreset(tex, cursor, counters)
        elif include_structure and name == "newenvironment":
            cursor = _read_newenvironment(tex, cursor, theorems, counters)
        index = cursor


def _maybe_number_format(tex: str, index: int, counters: Counters) -> int | None:
    """Return the index after a ``\\renewcommand{\\theequation}{...}``, or None.

    Both ``\\theequation`` and ``{\\theequation}`` are accepted. A redefinition
    of an ordinary macro returns None and leaves the caller at the same index.
    """
    cursor = index
    if cursor < len(tex) and tex[cursor] == "*":
        cursor += 1
    cursor = _skip_space(tex, cursor)
    if cursor >= len(tex):
        return None
    if tex[cursor] == "{":
        wrapped = _read_group(tex, cursor)
        if wrapped is None or not wrapped[0].strip().startswith("\\"):
            return None
        command = _read_command(wrapped[0].strip(), 0)
        if command is None:
            return None
        name, after = command
        if wrapped[0].strip()[after:].strip():
            return None
        cursor = wrapped[1]
    elif tex[cursor] == "\\":
        command = _read_command(tex, cursor)
        if command is None:
            return None
        name, cursor = command
    else:
        return None
    if not name.startswith("the") or not name[3:].isalpha():
        return None
    counter = name[3:]
    # \\theta is not \\the<counter>. Leave ordinary macros for the macro reader.
    if counter not in _NUMBERED_COUNTERS and counter not in counters.form and counter not in counters.value:
        return None
    group = _read_group(tex, cursor)
    if group is None:
        raise Unrecognised(f"broken \\the{counter}")
    if not group[0].strip():
        return group[1]
    counters.form[counter] = _parse_format(group[0])
    return group[1]


def _read_macro(tex: str, index: int, macros: dict[str, Macro]) -> int:
    if index < len(tex) and tex[index] == "*":
        index += 1
    index = _skip_space(tex, index)
    if index < len(tex) and tex[index] == "\\":
        command = _read_command(tex, index)
        if command is None:
            raise Unrecognised("broken newcommand")
        name, index = command
    else:
        group = _read_group(tex, index)
        if group is None:
            raise Unrecognised("broken newcommand")
        inner = group[0].strip()
        # \newcommand{{\foo}} wraps the control sequence in a second pair of braces.
        while inner.startswith("{"):
            nested = _read_group(inner, 0)
            if nested is None or nested[1] != len(inner):
                break
            inner = nested[0].strip()
        if not inner.startswith("\\"):
            raise Unrecognised("broken newcommand")
        command = _read_command(inner, 0)
        if command is None:
            raise Unrecognised("broken newcommand")
        name = command[0]
        index = group[1]
    if name in _PROTECTED:
        raise Unrecognised(f"redefined \\{name}")
    # \\theequation is a counter format. \\theoremwrap is an ordinary macro:
    # the "the" prefix only counts when the rest is a counter we number.
    if name.startswith("the") and name[3:] in _NUMBERED_COUNTERS:
        body = _read_group(tex, _skip_optional_default(tex, index))
        if body is None:
            raise Unrecognised("broken newcommand")
        return body[1]
    optional_count = _read_optional(tex, index)
    required = 0
    default = None
    if optional_count is not None:
        index = optional_count[1]
        if not optional_count[0].strip().isdigit():
            raise Unrecognised("newcommand argument count")
        required = int(optional_count[0].strip())
        if required > 2:
            # Leave a complicated macro unexpanded rather than guessing.
            group = _read_group(tex, _skip_optional_default(tex, index))
            if group is None:
                raise Unrecognised("broken newcommand")
            return group[1]
        default_group = _read_optional(tex, index)
        if default_group is not None:
            default = default_group[0]
            index = default_group[1]
            required -= 1
    body = _read_group(tex, index)
    if body is None:
        # \renewcommand\:\colon stores a single token and no brace group.
        index = _skip_space(tex, index)
        if index < len(tex) and tex[index] == "\\":
            command = _read_command(tex, index)
            if command is None:
                raise Unrecognised("broken newcommand")
            token = tex[index : command[1]]
            index = command[1]
        elif index < len(tex) and not tex[index].isspace():
            token = tex[index]
            index += 1
        else:
            raise Unrecognised("broken newcommand")
        if name.isalpha() and required <= 2:
            macros[name] = Macro(name, token, required, default)
        return index
    if name.isalpha() and required <= 2:
        macros[name] = Macro(name, body[0], required, default)
    return body[1]


def _skip_optional_default(tex: str, index: int) -> int:
    default_group = _read_optional(tex, index)
    if default_group is None:
        return index
    return default_group[1]


def _read_newenvironment(tex: str, index: int, theorems: dict[str, TheoremDef], counters: Counters) -> int:
    """A custom environment that steps one counter is a theorem environment.

    ``\\newenvironment{remark}{\\refstepcounter{equation}...}{}`` prints a
    remark on the equation counter. Environments that do not step a counter
    are skipped. Argument-taking definitions are skipped rather than guessed.
    """
    if index < len(tex) and tex[index] == "*":
        index += 1
    name_group = _read_group(tex, index)
    if name_group is None:
        raise Unrecognised("broken newenvironment")
    env = name_group[0].strip()
    index = name_group[1]
    count = _read_optional(tex, index)
    nargs = 0
    if count is not None:
        index = count[1]
        if count[0].strip().isdigit():
            nargs = int(count[0].strip())
        default = _read_optional(tex, index)
        if default is not None:
            index = default[1]
    begin = _read_group(tex, index)
    end = _read_group(tex, begin[1]) if begin else None
    if begin is None or end is None:
        raise Unrecognised("broken newenvironment")
    if nargs or env in theorems:
        return end[1]
    steps = re.findall(r"\\(?:refstepcounter|stepcounter)\{([A-Za-z@]+)\}", begin[0])
    if len(steps) != 1:
        return end[1]
    counter = steps[0]
    if counter not in _NUMBERED_COUNTERS and counter not in counters.form and counter not in counters.value:
        return end[1]
    bold = re.search(r"\\(?:textbf|emph|textsc|textit)\{([A-Za-z][^}]*)\}", begin[0])
    head = bold.group(1) if bold else env[:1].upper() + env[1:]
    try:
        _register_theorem(theorems, counters, env, head, counter, None, False)
    except Unrecognised:
        return end[1]
    return end[1]


def _read_newtheorem(tex: str, index: int, theorems: dict[str, TheoremDef], counters: Counters) -> int:
    starred = index < len(tex) and tex[index] == "*"
    if starred:
        index += 1
    env_group = _read_group(tex, index)
    if env_group is None:
        raise Unrecognised("broken newtheorem")
    env = env_group[0].strip()
    index = env_group[1]
    shared_group = _read_optional(tex, index)
    shared = None
    parent = None
    if shared_group is not None:
        shared = shared_group[0].strip()
        index = shared_group[1]
        head_group = _read_group(tex, index)
        if head_group is None:
            raise Unrecognised("broken newtheorem")
        head = head_group[0]
        index = head_group[1]
    else:
        head_group = _read_group(tex, index)
        if head_group is None:
            raise Unrecognised("broken newtheorem")
        head = head_group[0]
        index = head_group[1]
        parent_group = _read_optional(tex, index)
        if parent_group is not None:
            parent = parent_group[0].strip()
            index = parent_group[1]
    _register_theorem(theorems, counters, env, head, shared, parent, starred)
    return index


def _split_keys(text: str) -> dict[str, str]:
    parts: list[str] = []
    buf: list[str] = []
    depth_brace = 0
    depth_bracket = 0
    index = 0
    while index < len(text):
        char = text[index]
        if char == "\\":
            buf.append(char)
            if index + 1 < len(text):
                buf.append(text[index + 1])
            index += 2
            continue
        if char == "{":
            depth_brace += 1
        elif char == "}" and depth_brace:
            depth_brace -= 1
        elif char == "[" and depth_brace == 0:
            depth_bracket += 1
        elif char == "]" and depth_bracket and depth_brace == 0:
            depth_bracket -= 1
        if char == "," and depth_brace == 0 and depth_bracket == 0:
            parts.append("".join(buf))
            buf = []
            index += 1
            continue
        buf.append(char)
        index += 1
    if buf:
        parts.append("".join(buf))
    keys: dict[str, str] = {}
    for part in parts:
        if not part.strip():
            continue
        if "=" not in part:
            raise Unrecognised(f"theorem key {part.strip()}")
        key, value = part.split("=", 1)
        key = key.strip()
        if key not in _DECLARE_KEYS:
            raise Unrecognised(f"theorem key {key}")
        keys[key] = value.strip()
    return keys


def _read_declaretheorem(tex: str, index: int, theorems: dict[str, TheoremDef], counters: Counters) -> int:
    starred = index < len(tex) and tex[index] == "*"
    if starred:
        index += 1
    optional = _read_optional(tex, index)
    keys: dict[str, str] = {}
    if optional is not None:
        keys = _split_keys(optional[0])
        index = optional[1]
    env_group = _read_group(tex, index)
    if env_group is None:
        raise Unrecognised("broken declaretheorem")
    env = env_group[0].strip()
    head = keys.get("name") or keys.get("title") or env[:1].upper() + env[1:]
    shared = keys.get("sibling") or keys.get("numberlike") or keys.get("sharenumber")
    parent = keys.get("numberwithin") or keys.get("parent")
    numbered = keys.get("numbered", "yes").lower()
    unnumbered = starred or "unnumbered" in keys or numbered in {"no", "false", "unless unique"}
    _register_theorem(theorems, counters, env, head, shared, parent, unnumbered)
    return env_group[1]


def _register_theorem(
    theorems: dict[str, TheoremDef],
    counters: Counters,
    env: str,
    head: str,
    shared: str | None,
    parent: str | None,
    starred: bool,
) -> None:
    plain_head = _plain(head) or head.strip()
    kind = _kind_of_head(plain_head)
    definition = TheoremDef(env, plain_head, kind, shared, parent, starred)
    previous = theorems.get(env)
    if previous is not None and previous != definition:
        raise Unrecognised(f"conflicting theorem definition for {env}")
    theorems[env] = definition
    if starred:
        return
    if shared:
        counters.alias[env] = counters.target(shared)
        return
    counters.value.setdefault(env, 0)
    if parent:
        counters._within(env, parent)
    else:
        counters.form[env] = [("arabic", env)]


def _read_within(tex: str, index: int, counters: Counters) -> int:
    # \counterwithin[format]{counter}{parent} and \numberwithin{counter}{parent}
    optional = _read_optional(tex, index)
    if optional is not None:
        index = optional[1]
        if optional[0].strip():
            # A custom format on counterwithin is the same language as \thecounter.
            custom = _parse_format(optional[0])
        else:
            custom = None
    else:
        custom = None
    child = _read_group(tex, index)
    parent = _read_group(tex, child[1]) if child else None
    if child is None or parent is None:
        raise Unrecognised("broken numberwithin")
    child_name = child[0].strip()
    parent_name = parent[0].strip()
    counters._within(child_name, parent_name)
    if custom is not None:
        counters.form[child_name] = custom
    return parent[1]


def _read_addtoreset(tex: str, index: int, counters: Counters) -> int:
    child = _read_group(tex, index)
    parent = _read_group(tex, child[1]) if child else None
    if child is None or parent is None:
        raise Unrecognised("broken addtoreset")
    counters.parent[child[0].strip()] = parent[0].strip()
    counters.value.setdefault(child[0].strip(), 0)
    return parent[1]


# --- expansion -----------------------------------------------------------------


def _skip_macro_definition(tex: str, index: int, name: str) -> int:
    """Index after a macro or environment definition. ``index`` follows the name."""
    if index < len(tex) and tex[index] == "*":
        index += 1
    index = _skip_space(tex, index)
    if name in {"newenvironment", "renewenvironment"}:
        group = _read_group(tex, index)
        if group is None:
            raise Unrecognised(f"broken {name}")
        index = group[1]
        bodies = 2
    else:
        if index < len(tex) and tex[index] == "\\":
            command = _read_command(tex, index)
            if command is None:
                raise Unrecognised(f"broken {name}")
            index = command[1]
        else:
            group = _read_group(tex, index)
            if group is None:
                raise Unrecognised(f"broken {name}")
            index = group[1]
        bodies = 1
    for _ in range(2):
        index = _skip_space(tex, index)
        optional = _read_optional(tex, index)
        if optional is None:
            break
        index = optional[1]
    for slot in range(bodies):
        index = _skip_space(tex, index)
        group = _read_group(tex, index)
        if group is not None:
            index = group[1]
            continue
        # \renewcommand\:\colon has a one-token body and no braces.
        if bodies == 1 and slot == 0 and index < len(tex) and not tex[index].isspace():
            if tex[index] == "\\":
                command = _read_command(tex, index)
                if command is None:
                    raise Unrecognised(f"broken {name}")
                return command[1]
            return index + 1
        raise Unrecognised(f"broken {name}")
    return index


def _expand(tex: str, macros: dict[str, Macro]) -> str:
    return _expand_from(tex, macros, frozenset())


def _expand_from(tex: str, macros: dict[str, Macro], stack: frozenset[str]) -> str:
    if len(stack) > 12:
        return tex
    out: list[str] = []
    index = 0
    length = len(tex)
    while index < length:
        if tex[index] != "\\":
            out.append(tex[index])
            index += 1
            continue
        command = _read_command(tex, index)
        if command is None:
            out.append(tex[index])
            index += 1
            continue
        name, cursor = command
        if name in {"newcommand", "renewcommand", "providecommand", "newenvironment", "renewenvironment"}:
            # Copy the definition through unchanged. Expanding it would read
            # the parameter text ``[2]`` as the two arguments of the macro.
            end = _skip_macro_definition(tex, cursor, name)
            out.append(tex[index:end])
            index = end
            continue
        if name in {"newtheorem", "declaretheorem"}:
            # Keep the command so the structure scan still sees it, and expand
            # a head written as a macro.
            out.append(tex[index:cursor])
            index = cursor
            continue
        macro = macros.get(name)
        if macro is None or name in stack:
            out.append(tex[index:cursor])
            index = cursor
            continue
        parsed = _read_macro_args(tex, cursor, macro)
        if parsed is None:
            out.append(tex[index:cursor])
            index = cursor
            continue
        args, cursor = parsed
        replacement = _apply_macro(macro, args)
        out.append(_expand_from(replacement, macros, stack | {name}))
        index = cursor
    return "".join(out)


def _read_macro_args(tex: str, index: int, macro: Macro) -> tuple[list[str], int] | None:
    args: list[str] = []
    if macro.optional_default is not None:
        optional = _read_optional(tex, index)
        if optional is None:
            args.append(macro.optional_default)
        else:
            args.append(optional[0])
            index = optional[1]
    for _ in range(macro.required):
        index = _skip_space(tex, index)
        if index >= len(tex):
            return None
        if tex[index] == "{":
            group = _read_group(tex, index)
            if group is None:
                return None
            args.append(group[0])
            index = group[1]
            continue
        if tex[index] == "\\":
            command = _read_command(tex, index)
            if command is None:
                return None
            args.append(tex[index : command[1]])
            index = command[1]
            continue
        args.append(tex[index])
        index += 1
    return args, index


def _apply_macro(macro: Macro, args: list[str]) -> str:
    def replace(match: re.Match[str]) -> str:
        number = int(match.group(1)) - 1
        if number < 0 or number >= len(args):
            return match.group(0)
        return args[number]

    return re.sub(r"#(\d)", replace, macro.body)


def _plain(tex: str) -> str:
    text = tex
    text = re.sub(
        r"\\(?:mathrm|mathbf|mathit|mathsf|mathtt|text|textbf|textit|emph|operatorname|mathbb|mathcal)\{([^{}]*)\}",
        r"\1",
        text,
    )
    text = re.sub(r"\\[a-zA-Z@]+\*?", " ", text)
    text = text.replace("~", " ")
    text = re.sub(r"[{}$_^&\\\\]", " ", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


# --- walk ----------------------------------------------------------------------


@dataclass
class _EqRow:
    tag: str | None = None
    notag: bool = False
    labels: list[str] = field(default_factory=list)
    body: list[str] = field(default_factory=list)


@dataclass
class _OpenEnv:
    name: str
    kind: str  # theorem, equation, subequations, other, bibliography
    depth: int
    item: ParsedItem | None = None
    row: _EqRow | None = None
    multi: bool = False
    starred: bool = False
    inner: bool = False


def _walk(body: str, theorems: dict[str, TheoremDef], counters: Counters) -> ParsedSource:
    parsed = ParsedSource()
    walker = _Walker(body, theorems, counters, parsed)
    walker.run()
    return parsed


class _Walker:
    def __init__(self, tex: str, theorems: dict[str, TheoremDef], counters: Counters, parsed: ParsedSource) -> None:
        self.tex = tex
        self.theorems = theorems
        self.counters = counters
        self.parsed = parsed
        self.index = 0
        self.stack: list[_OpenEnv] = []
        self.section_item: ParsedItem | None = None
        self.bib_counter = 0
        self.current_bib: BibEntry | None = None
        self.subeq_parent: str | None = None
        self.subeq_letter = 0
        self.swapnumbers = False

    def run(self) -> None:
        length = len(self.tex)
        while self.index < length:
            char = self.tex[self.index]
            if char != "\\":
                self._text(char)
                self.index += 1
                continue
            command = _read_command(self.tex, self.index)
            if command is None:
                self.index += 1
                continue
            name, cursor = command
            self.index = cursor
            self._command(name)
        for ref in self.parsed.refs:
            if ref["target"] is None:
                ref["target"] = self.parsed.labels.get(ref["label"])

    def _text(self, char: str) -> None:
        env = self._equation_env()
        if env is not None and env.row is not None:
            env.row.body.append(char)
        for env in reversed(self.stack):
            if env.kind == "theorem" and env.item is not None:
                if len(env.item.body) < 1200:
                    env.item.body += char
                return

    def _command(self, name: str) -> None:
        if name in {"begin"}:
            self._begin()
            return
        if name == "end":
            self._end()
            return
        if name in {"section", "subsection", "subsubsection", "chapter"}:
            self._section(name)
            return
        if name == "appendix":
            self.counters.enter_appendix()
            return
        if name == "appendices":
            self.counters.enter_appendix()
            return
        if name == "frontmatter":
            self.counters.frontmatter = True
            return
        if name == "mainmatter":
            self.counters.frontmatter = False
            self.counters.value["chapter"] = 0
            self.counters.value["section"] = 0
            return
        if name == "swapnumbers":
            self.swapnumbers = True
            return
        if name == "label":
            self._label()
            return
        if name in _REF_COMMANDS:
            self._ref(name)
            return
        if name in _CITE_COMMANDS:
            self._cite(name)
            return
        if name in {"tag", "notag", "nonumber"}:
            self._equation_mark(name)
            return
        if name in {"\\", "cr"} or name == "\\":
            self._linebreak()
            return
        if name in {"newcommand", "renewcommand", "providecommand", "newtheorem", "declaretheorem"}:
            # Definitions are removed before the walk. A leftover that this
            # reader cannot parse is skipped rather than failing the paper.
            return
        if name in {"numberwithin", "counterwithin"}:
            self.index = _read_within(self.tex, self.index, self.counters)
            return
        if name == "setcounter":
            self._set_counter(add=False)
            return
        if name == "addtocounter":
            self._set_counter(add=True)
            return
        if name in {"input", "include"}:
            raise Unrecognised(f"unresolved \\{name}")
        if name == "[":
            self._display(True)
            return
        if name == "]":
            self._display(False)
            return
        if name == "bibitem":
            self._bibitem()
            return
        # ``\\`` arrives as a command whose name is ``\`` because the reader
        # returns the single symbol after the first backslash.
        if name == "\\":
            self._linebreak()

    def _begin(self) -> None:
        group = _read_group(self.tex, self.index)
        if group is None:
            raise Unrecognised("broken begin")
        self.index = group[1]
        env = group[0].strip()
        if env in {"appendices"}:
            self.counters.enter_appendix()
            self.stack.append(_OpenEnv(env, "other", len(self.stack)))
            return
        if env in _VERBATIM_ENVS:
            raise Unrecognised(f"verbatim reached the walker ({env})")
        if env == "thebibliography":
            self._skip_group_optional()
            self.stack.append(_OpenEnv(env, "bibliography", len(self.stack)))
            return
        if env == "subequations":
            if self.subeq_parent is not None:
                raise Unrecognised("nested subequations")
            self.counters.step("equation")
            self.subeq_parent = self.counters.format("equation")
            self.subeq_letter = 0
            self.stack.append(_OpenEnv(env, "subequations", len(self.stack)))
            return
        if env == "restatable" or env == "restatable*":
            self._restatable(env.endswith("*"))
            return
        if env in _EQUATION_SINGLE or env in _EQUATION_LINES or env in _INNER_MATH:
            self._begin_math(env)
            return
        if env in self.theorems or env.endswith("*") and env[:-1] in self.theorems:
            self._begin_theorem(env)
            return
        bare = env[:-1] if env.endswith("*") else env
        if bare in _THEOREM_ENVS or env in _THEOREM_ENVS:
            if bare in _UNNUMBERED_KNOWN or env in _UNNUMBERED_KNOWN:
                self.stack.append(_OpenEnv(env, "other", len(self.stack)))
                return
            raise Unrecognised(f"undefined theorem environment {env}")
        # alignat takes a column-count argument. Other environments may too.
        if env in {"alignat", "alignat*"}:
            group = _read_group(self.tex, self.index)
            if group is not None:
                self.index = group[1]
        else:
            # Consume a single optional argument so ``[ht]`` is not body text,
            # but only for environments that are not theorems (already handled).
            optional = _read_optional(self.tex, self.index)
            if optional is not None and self._short_optional(optional[0]):
                self.index = optional[1]
        self.stack.append(_OpenEnv(env, "other", len(self.stack)))

    def _short_optional(self, text: str) -> bool:
        return len(text) <= 40 and "\\begin" not in text

    def _skip_group_optional(self) -> None:
        group = _read_group(self.tex, self.index)
        if group is not None:
            self.index = group[1]

    def _end(self) -> None:
        group = _read_group(self.tex, self.index)
        if group is None:
            raise Unrecognised("broken end")
        self.index = group[1]
        name = group[0].strip()
        if not self.stack:
            raise Unrecognised(f"extra end {name}")
        env = self.stack[-1]
        if env.name != name and not (env.name == "display" and name == "display"):
            # A mismatch means the subset lost track of the document.
            raise Unrecognised(f"end {name} closed {env.name}")
        if env.kind == "equation":
            self._close_row(env, final=True)
        if env.kind == "subequations":
            self.subeq_parent = None
            self.subeq_letter = 0
        if env.kind == "bibliography":
            self._finish_bib()
        self.stack.pop()

    def _begin_math(self, env: str) -> None:
        if env in {"alignat", "alignat*"}:
            group = _read_group(self.tex, self.index)
            if group is None:
                raise Unrecognised("alignat needs a column count")
            self.index = group[1]
        starred = env.endswith("*") or env == "displaymath"
        multi = env in _EQUATION_LINES
        inner = env in _INNER_MATH
        row = None if inner else _EqRow()
        self.stack.append(
            _OpenEnv(env, "equation", len(self.stack), row=row, multi=multi, starred=starred, inner=inner)
        )

    def _display(self, opening: bool) -> None:
        if opening:
            self.stack.append(_OpenEnv("display", "equation", len(self.stack), row=_EqRow(), starred=True))
            return
        if not self.stack or self.stack[-1].name != "display":
            raise Unrecognised("unbalanced display math")
        env = self.stack.pop()
        self._close_row(env, final=True)

    def _begin_theorem(self, env_name: str) -> None:
        starred = env_name.endswith("*")
        key = env_name[:-1] if starred and env_name not in self.theorems else env_name
        definition = self.theorems.get(key) or self.theorems.get(env_name)
        if definition is None:
            raise Unrecognised(f"undefined theorem environment {env_name}")
        optional = _read_optional(self.tex, self.index)
        title = ""
        if optional is not None:
            title = _plain(optional[0])
            self.index = optional[1]
        number = ""
        if not starred and not definition.starred:
            counter = definition.shared or definition.env
            self.counters.step(counter)
            number = self.counters.format(counter)
        item = ParsedItem("statement", definition.kind, number, definition.head, title, "")
        self.parsed.items.append(item)
        self.stack.append(_OpenEnv(env_name, "theorem", len(self.stack), item=item))

    def _restatable(self, starred: bool) -> None:
        optional = _read_optional(self.tex, self.index)
        title = _plain(optional[0]) if optional else ""
        if optional is not None:
            self.index = optional[1]
        env_group = _read_group(self.tex, self.index)
        command_group = _read_group(self.tex, env_group[1]) if env_group else None
        if env_group is None or command_group is None:
            raise Unrecognised("broken restatable")
        self.index = command_group[1]
        env_name = env_group[0].strip()
        definition = self.theorems.get(env_name)
        if definition is None:
            raise Unrecognised(f"undefined theorem environment {env_name}")
        number = ""
        if not starred and not definition.starred:
            counter = definition.shared or definition.env
            self.counters.step(counter)
            number = self.counters.format(counter)
        item = ParsedItem("statement", definition.kind, number, definition.head, title, "")
        self.parsed.items.append(item)
        self.stack.append(_OpenEnv("restatable" + ("*" if starred else ""), "theorem", len(self.stack), item=item))

    def _section(self, command: str) -> None:
        starred = self.index < len(self.tex) and self.tex[self.index] == "*"
        if starred:
            self.index += 1
        short = _read_optional(self.tex, self.index)
        if short is not None:
            self.index = short[1]
        group = _read_group(self.tex, self.index)
        if group is None:
            raise Unrecognised(f"broken {command}")
        self.index = group[1]
        title = _plain(group[0])
        level = {"chapter": 0, "section": 1, "subsection": 2, "subsubsection": 3}[command]
        number = ""
        if not starred and not (command == "chapter" and self.counters.frontmatter):
            counter = {"chapter": "chapter", "section": "section", "subsection": "subsection", "subsubsection": "subsubsection"}[
                command
            ]
            self.counters.step(counter)
            number = self.counters.format(counter)
        item = ParsedItem("section", "section", number, command, title, "", level)
        self.parsed.items.append(item)
        self.section_item = item

    def _label(self) -> None:
        group = _read_group(self.tex, self.index)
        if group is None:
            raise Unrecognised("broken label")
        self.index = group[1]
        label = group[0].strip()
        if not label:
            return
        env = self._owning_env()
        if env is None:
            if self.section_item is not None and self.section_item.number:
                self.parsed.labels[label] = ("section", self.section_item.number)
            return
        if env.kind == "theorem" and env.item is not None and env.item.number:
            self.parsed.labels[label] = (env.item.kind, env.item.number)
            return
        if env.kind == "equation" and env.row is not None:
            env.row.labels.append(label)

    def _owning_env(self) -> _OpenEnv | None:
        for env in reversed(self.stack):
            if env.kind in {"theorem", "equation"} and not env.inner:
                return env
        return None

    def _equation_env(self) -> _OpenEnv | None:
        for env in reversed(self.stack):
            if env.kind == "equation" and not env.inner:
                return env
            if env.inner:
                return None
        return None

    def _ref(self, command: str) -> None:
        # cleveref accepts a star and optional words before the label.
        if self.index < len(self.tex) and self.tex[self.index] == "*":
            self.index += 1
        optional = _read_optional(self.tex, self.index)
        if optional is not None:
            self.index = optional[1]
        group = _read_group(self.tex, self.index)
        if group is None:
            raise Unrecognised(f"broken {command}")
        self.index = group[1]
        for label in [part.strip() for part in group[0].split(",") if part.strip()]:
            target = self.parsed.labels.get(label)
            self.parsed.refs.append({"command": command, "label": label, "target": target})

    def _cite(self, command: str) -> None:
        if self.index < len(self.tex) and self.tex[self.index] == "*":
            self.index += 1
        for _ in range(2):
            optional = _read_optional(self.tex, self.index)
            if optional is None:
                break
            self.index = optional[1]
        group = _read_group(self.tex, self.index)
        if group is None:
            raise Unrecognised(f"broken {command}")
        self.index = group[1]
        keys = [part.strip() for part in group[0].split(",") if part.strip()]
        if keys:
            self.parsed.citations.append(keys)

    def _equation_mark(self, name: str) -> None:
        env = self._equation_env()
        if name == "tag":
            starred = self.index < len(self.tex) and self.tex[self.index] == "*"
            if starred:
                self.index += 1
            group = _read_group(self.tex, self.index)
            if group is None:
                raise Unrecognised("broken tag")
            self.index = group[1]
            if env is not None and env.row is not None and not starred:
                env.row.tag = _plain(group[0])
            return
        if env is not None and env.row is not None:
            env.row.notag = True

    def _linebreak(self) -> None:
        if self.index < len(self.tex) and self.tex[self.index] == "*":
            self.index += 1
        optional = _read_optional(self.tex, self.index)
        if optional is not None:
            self.index = optional[1]
        env = self._equation_env()
        if env is None or not env.multi or env.row is None:
            return
        # A line break inside a nested brace group is not a new equation.
        if self._inside_group():
            return
        self._close_row(env, final=False)
        env.row = _EqRow()

    def _inside_group(self) -> bool:
        # Brace depth above the equation body. Count from the start of the
        # current equation body's raw text is expensive; a running depth is
        # kept by scanning back only across the open row, which is short.
        env = self._equation_env()
        if env is None or env.row is None:
            return False
        text = "".join(env.row.body)
        depth = 0
        index = 0
        while index < len(text):
            char = text[index]
            if char == "\\":
                index += 2
                continue
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
            index += 1
        return depth > 0

    def _close_row(self, env: _OpenEnv, final: bool) -> None:
        row = env.row
        if row is None:
            return
        number = ""
        if row.tag:
            number = row.tag
        elif row.notag or env.starred or env.inner:
            number = ""
        elif self.subeq_parent is not None:
            self.subeq_letter += 1
            if self.subeq_letter > 26:
                raise Unrecognised("too many equations in subequations")
            number = f"{self.subeq_parent}{chr(ord('a') + self.subeq_letter - 1)}"
        else:
            self.counters.step("equation")
            number = self.counters.format("equation")
        body = _plain("".join(row.body))
        if number and _number_ok(number):
            item = ParsedItem("equation", "equation", number, "equation", "", body)
            self.parsed.items.append(item)
            for label in row.labels:
                self.parsed.labels[label] = ("equation", number)
        elif row.labels and not number:
            # A label on an unnumbered row is not a numbered statement.
            pass
        if not final:
            return
        env.row = None

    def _set_counter(self, add: bool) -> None:
        name_group = _read_group(self.tex, self.index)
        value_group = _read_group(self.tex, name_group[1]) if name_group else None
        if name_group is None or value_group is None:
            raise Unrecognised("broken setcounter")
        self.index = value_group[1]
        name = name_group[0].strip()
        raw = value_group[0].strip()
        if name not in {"section", "subsection", "subsubsection", "chapter", "equation"} and name not in self.counters.value:
            return
        if not re.fullmatch(r"-?\d+", raw):
            raise Unrecognised(f"non-numeric setcounter {name}")
        number = int(raw)
        if add:
            current = self.counters.value.get(self.counters.target(name), 0)
            self.counters.set_value(name, current + number)
        else:
            self.counters.set_value(name, number)

    def _bibitem(self) -> None:
        if not any(env.kind == "bibliography" for env in self.stack):
            return
        self._finish_bib()
        optional = _read_optional(self.tex, self.index)
        label = ""
        if optional is not None:
            label = _plain(optional[0])
            self.index = optional[1]
        group = _read_group(self.tex, self.index)
        if group is None:
            raise Unrecognised("broken bibitem")
        self.index = group[1]
        self.bib_counter += 1
        if not label:
            label = str(self.bib_counter)
        self.current_bib = BibEntry(group[0].strip(), label, "")
        self.parsed.bibliography.append(self.current_bib)

    def _finish_bib(self) -> None:
        self.current_bib = None


def _number_ok(number: str) -> bool:
    return re.fullmatch(r"[A-Za-z]?(?:\d+(?:\.\d+)*|\d+)[a-z]?", number) is not None or re.fullmatch(
        r"[A-Z](?:\.\d+)+", number
    ) is not None


# --- page mapping --------------------------------------------------------------


@dataclass
class _Hit:
    page_index: int
    start: int
    end: int


def _map_items(parsed: ParsedSource, extracted: dict) -> None:
    pages = extracted.get("pages") or []
    outline = extracted.get("outline") or []
    for item in parsed.items:
        if item.role == "section":
            item.page_index = _map_section(pages, outline, item)
    _place_statements(pages, [item for item in parsed.items if item.role == "statement"])
    _place_equations(pages, [item for item in parsed.items if item.role == "equation"])


def _place_statements(pages: list[dict], items: list[ParsedItem]) -> None:
    hits_for = {id(item): _statement_hits(pages, item) for item in items}

    def score(item: ParsedItem, hit: _Hit) -> int:
        return _statement_score(pages, item.body, hit)

    _place_numbered(items, hits_for, score, threshold=2)


def _place_equations(pages: list[dict], items: list[ParsedItem]) -> None:
    hits_for = {id(item): _equation_hits(pages, item.number) for item in items}

    def score(item: ParsedItem, hit: _Hit) -> int:
        return _equation_score(pages, item.body, hit)

    _place_numbered(items, hits_for, score, threshold=2)


def _place_numbered(
    items: list[ParsedItem],
    hits_for: dict[int, list[_Hit]],
    score,
    threshold: int,
) -> None:
    """Place each numbered item. A tie that still names one page is kept.

    The source text next to the item (the statement, or the formula beside
    its label) breaks a repeated number. Source order then drops an occurrence
    that sits outside its neighbours. A number that still names two pages is
    left unlocated.
    """
    anchor: dict[int, tuple[int, int]] = {}
    for item in items:
        hits = hits_for.get(id(item)) or []
        pages = {hit.page_index for hit in hits}
        if len(pages) == 1:
            best = max(hits, key=lambda hit: (score(item, hit), -hit.start))
            _remember(item, best, anchor)
            continue
        ranked = sorted(((score(item, hit), hit) for hit in hits), key=lambda pair: pair[0], reverse=True)
        if ranked and ranked[0][0] >= threshold and (len(ranked) == 1 or ranked[0][0] > ranked[1][0]):
            _remember(item, ranked[0][1], anchor)

    changed = True
    while changed:
        changed = False
        for index, item in enumerate(items):
            if item.page_index is not None:
                continue
            hits = hits_for.get(id(item)) or []
            if not hits:
                continue
            top = max(score(item, hit) for hit in hits)
            pool = [hit for hit in hits if score(item, hit) == top]
            allowed = [hit for hit in pool if _inside_neighbours(hit, items, index, anchor)]
            pages = {hit.page_index for hit in allowed}
            if len(pages) == 1 and allowed:
                best = max(allowed, key=lambda hit: (score(item, hit), -hit.start))
                _remember(item, best, anchor)
                changed = True


def _remember(item: ParsedItem, hit: _Hit, anchor: dict[int, tuple[int, int]]) -> None:
    item.page_index = hit.page_index
    anchor[id(item)] = (hit.page_index, hit.start)


def _inside_neighbours(
    hit: _Hit,
    items: list[ParsedItem],
    index: int,
    anchor: dict[int, tuple[int, int]],
) -> bool:
    """Source order is reading order. An occurrence past the next placed item is not this one."""
    previous = next((anchor[id(items[cursor])] for cursor in range(index - 1, -1, -1) if id(items[cursor]) in anchor), None)
    following = next((anchor[id(items[cursor])] for cursor in range(index + 1, len(items)) if id(items[cursor]) in anchor), None)
    here = (hit.page_index, hit.start)
    if previous is not None and here <= previous:
        return False
    if following is not None and here >= following:
        return False
    return True


def _page_text(pages: list[dict], page_index: int) -> str:
    for page in pages:
        if page.get("page_index") == page_index:
            return page.get("text") or ""
    return ""


def _statement_hits(pages: list[dict], item: ParsedItem) -> list[_Hit]:
    if not item.number:
        return []
    head = re.escape(item.head)
    number = re.escape(item.number)
    primary = re.compile(rf"(?im)^[ \t]*{head}\s*{number}(?!\.\d)(?!\d)")
    swapped = re.compile(rf"(?im)^[ \t]*{number}(?!\.\d)(?!\d)\.?\s*{head}\b")
    loose = re.compile(rf"(?i)\b{head}\s*{number}(?!\.\d)(?!\d)")
    hits = _pattern_hits(pages, primary)
    if not hits:
        hits = _pattern_hits(pages, swapped)
    if not hits:
        hits = _pattern_hits(pages, loose)
    return hits


def _pattern_hits(pages: list[dict], pattern: re.Pattern[str]) -> list[_Hit]:
    hits: list[_Hit] = []
    for page in pages:
        text = page.get("text") or ""
        if is_likely_table_of_contents(text):
            continue
        for match in pattern.finditer(text):
            hits.append(_Hit(page["page_index"], match.start(), match.end()))
    return hits


def _statement_score(pages: list[dict], body: str, hit: _Hit) -> int:
    """Words of the statement, in the text just after the heading.

    The label sits at the start of the environment, so a later mention of the
    same number does not carry those words.
    """
    words = [word.lower() for word in re.findall(r"[A-Za-z]{4,}", body)][:8]
    if len(words) < 2:
        return 0
    text = _page_text(pages, hit.page_index)
    window = text[hit.end : hit.end + 400].lower()
    return sum(1 for word in words if word in window)


def _equation_hits(pages: list[dict], number: str) -> list[_Hit]:
    if not number:
        return []
    pattern = re.compile(rf"\({re.escape(number)}\)(?!\d)")
    hits: list[_Hit] = []
    for page in pages:
        text = page.get("text") or ""
        if is_likely_table_of_contents(text):
            continue
        spans = page.get("span_x") or {}
        keys = sorted(spans)
        two_column = bool(page.get("two_column"))
        for match in pattern.finditer(text):
            if _equation_label(text, match.start(), match.end(), spans, keys, two_column):
                hits.append(_Hit(page["page_index"], match.start(), match.end()))
    return hits


def _equation_score(pages: list[dict], body: str, hit: _Hit) -> int:
    """The formula printed beside the tag, not a later citation of the number."""
    text = _page_text(pages, hit.page_index)
    window = _equation_window(text, hit.start, hit.end)
    compact_body = re.sub(r"[^a-z0-9]+", "", body.lower())
    compact_window = re.sub(r"[^a-z0-9]+", "", window.lower())
    if len(compact_body) >= 4 and compact_body in compact_window:
        return 3
    words = [word.lower() for word in re.findall(r"[A-Za-z]{4,}", body)][:8]
    if len(words) < 2:
        return 0
    lowered = window.lower()
    return sum(1 for word in words if word in lowered)


def _equation_window(text: str, start: int, end: int) -> str:
    line_start = text.rfind("\n", 0, start) + 1
    previous = text.rfind("\n", 0, max(0, line_start - 1)) + 1
    earlier = text.rfind("\n", 0, max(0, previous - 1)) + 1
    line_end = text.find("\n", end)
    if line_end < 0:
        line_end = len(text)
    return text[earlier:line_end]


def _equation_label(
    text: str,
    start: int,
    end: int,
    spans: dict[int, float],
    keys: list[int],
    two_column: bool,
) -> bool:
    line_start = text.rfind("\n", 0, start) + 1
    line_end = text.find("\n", end)
    if line_end < 0:
        line_end = len(text)
    line = text[line_start:line_end].strip()
    label = text[start:end]
    if line == label:
        return True
    prior = [key for key in keys if key <= start]
    x_pos = spans[prior[-1]] if prior else None
    trailing = text[end:line_end].strip()
    if trailing:
        return False
    if x_pos is None:
        return False
    if x_pos >= 0.72:
        return True
    return two_column and x_pos >= 0.40


def _map_section(pages: list[dict], outline: list, item: ParsedItem) -> int | None:
    if not item.number or not item.title:
        return None
    words = re.findall(r"[A-Za-z]{3,}", item.title)
    number = re.escape(item.number)
    pattern = re.compile(
        rf"(?i)^[ \t]*(?:§\s*|section\s+|appendix\s+)?{number}(?!\.\d)(?!\d)\b"
    )
    hits: list[int] = []
    for page in pages:
        text = page.get("text") or ""
        if is_likely_table_of_contents(text):
            continue
        lines = text.split("\n")
        for line_index, raw in enumerate(lines):
            line = raw.strip()
            if not pattern.search(line):
                continue
            window = " ".join(lines[line_index : line_index + 2])
            if words and not all(word.lower() in window.lower() for word in words[:2]):
                continue
            if len(line) > 220:
                continue
            hits.append(page["page_index"])
            break
    unique = list(dict.fromkeys(hits))
    if len(unique) == 1:
        return unique[0]
    outlined = _outline_section(outline, item)
    if outlined is None:
        return None
    if not unique or outlined in unique:
        return outlined
    return None


def _outline_section(nodes: list, item: ParsedItem) -> int | None:
    wanted = re.sub(r"[^a-z0-9]+", " ", item.title.lower()).strip()
    if len(wanted) < 8:
        return None
    found: list[int] = []

    def walk(children: list) -> None:
        for node in children:
            title = re.sub(r"[^a-z0-9]+", " ", (node.title or "").lower()).strip()
            title = re.sub(r"^(?:\d+\s+)+", "", title).strip()
            number = _explicit_outline_number(node.title or "")
            number_ok = number is None or number == item.number
            if node.page_index >= 0 and number_ok and (title == wanted or title.startswith(wanted) or wanted.startswith(title)):
                if len(title) >= 8:
                    found.append(node.page_index)
            walk(node.children)

    walk(nodes)
    unique = list(dict.fromkeys(found))
    if len(unique) == 1:
        return unique[0]
    return None


def _explicit_outline_number(title: str) -> str | None:
    found = re.match(r"^\s*(\d+(?:\.\d+)*)(?:\s|\.|$)", title.strip())
    if found is None:
        return None
    return found.group(1)


def _lines_up(parsed: ParsedSource) -> bool:
    numbered = [item for item in parsed.items if item.number]
    if len(numbered) < 2:
        return False
    located = [item for item in numbered if item.page_index is not None]
    return len(located) / len(numbered) >= 0.5


def _locator(parsed: ParsedSource, extracted: dict) -> Structure:
    roots: list[OutlineNode] = []
    stack: list[tuple[int, OutlineNode]] = []
    for item in parsed.items:
        if item.role != "section" or item.page_index is None or not item.number:
            continue
        title = f"{item.number}. {item.title}".strip()
        node = OutlineNode(title=title, page_index=item.page_index)
        while stack and stack[-1][0] >= item.level:
            stack.pop()
        if stack:
            stack[-1][1].children.append(node)
        else:
            roots.append(node)
        stack.append((item.level, node))
    pages = [
        PageSnapshot(page["page_index"], page["text"])
        for page in extracted.get("pages") or []
        if (page.get("text") or "").strip()
    ]
    return Structure(outline=roots, pages=pages, page_count=extracted.get("page_count") or len(pages))
