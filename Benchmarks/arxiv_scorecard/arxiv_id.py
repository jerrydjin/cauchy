"""Find the arXiv id of a PDF the reader opened.

The id is read from the first-page margin stamp, the document metadata, or
the file name. New-style ids (``2610.04096``) and old-style ids
(``math.AG/0601001``, ``hep-th/9901001``) are both accepted, with an optional
``vN`` suffix. Nothing here is specific to one paper.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path


_ARCHIVES = (
    "astro-ph",
    "cond-mat",
    "gr-qc",
    "hep-ex",
    "hep-lat",
    "hep-ph",
    "hep-th",
    "math-ph",
    "nlin",
    "nucl-ex",
    "nucl-th",
    "physics",
    "quant-ph",
    "math",
    "cs",
    "q-bio",
    "q-fin",
    "stat",
    "econ",
    "eess",
)
_ARCHIVE = "(?:" + "|".join(sorted(_ARCHIVES, key=len, reverse=True)) + ")"
_NEW = r"\d{4}\.\d{4,5}"
_OLD = rf"{_ARCHIVE}(?:\.[A-Za-z][A-Za-z0-9-]*)?/\d{{7}}"
_OLD_FILE = rf"{_ARCHIVE}(?:\.[A-Za-z][A-Za-z0-9-]*)?[_/]\d{{7}}"
_VERSION = r"v\d+"

# The margin stamp looks like "arXiv:2610.04096v2 [math.CT] 5 Oct 2026".
_STAMP = re.compile(
    rf"(?i)\barxiv:\s*({_NEW}|{_OLD})({_VERSION})?\b"
)
_FILENAME = re.compile(
    rf"(?i)(?:^|[^A-Za-z0-9.])({_NEW}|{_OLD_FILE})({_VERSION})?(?![0-9A-Za-z])"
)
_LOOSE = re.compile(rf"(?i)\b({_NEW}|{_OLD})({_VERSION})?\b")


@dataclass(frozen=True)
class ArxivId:
    """An id without its version, plus the version when one was printed."""

    identifier: str
    version: str | None
    source: str

    @property
    def fetch_id(self) -> str:
        return self.identifier + (self.version or "")

    @property
    def cache_key(self) -> str:
        return self.fetch_id.replace("/", "_")


def _clean_version(raw: str | None) -> str | None:
    if not raw:
        return None
    return raw.lower()


def _normalize(raw: str) -> str:
    """Old-style file names use an underscore where the id uses a slash."""
    if "/" not in raw and "_" in raw:
        head, tail = raw.rsplit("_", 1)
        if re.fullmatch(r"\d{7}", tail):
            return f"{head}/{tail}"
    return raw


def _make(match: re.Match[str], source: str) -> ArxivId:
    return ArxivId(_normalize(match.group(1)), _clean_version(match.group(2)), source)


def from_filename(path: str) -> ArxivId | None:
    found = _FILENAME.search(Path(path).name)
    if found is None:
        return None
    return _make(found, "filename")


def from_stamp(first_page_text: str) -> ArxivId | None:
    """The stamp is in the top margin, so only the start of the page is read.

    A later ``arXiv:`` in the abstract is a citation of a different paper.
    When several stamps sit in the margin, the one followed by a category
    bracket is the one arXiv paints.
    """
    if not first_page_text:
        return None
    head = first_page_text[:1500]
    matches = list(_STAMP.finditer(head))
    if not matches:
        return None

    def rank(match: re.Match[str]) -> tuple[int, int]:
        tail = head[match.end() : match.end() + 24].lstrip()
        bracket = 0 if tail.startswith("[") else 1
        return (bracket, match.start())

    return _make(min(matches, key=rank), "stamp")


def from_metadata(metadata: dict | None) -> ArxivId | None:
    if not metadata:
        return None
    chunks = [value for value in metadata.values() if isinstance(value, str) and value.strip()]
    if not chunks:
        return None
    blob = "\n".join(chunks)
    stamped = _STAMP.search(blob)
    if stamped is not None:
        return _make(stamped, "metadata")
    loose = _LOOSE.search(blob)
    if loose is None:
        return None
    return _make(loose, "metadata")


def _with_version(preferred: ArxivId, other: ArxivId | None) -> ArxivId:
    if other is None or other.identifier != preferred.identifier:
        return preferred
    if preferred.version is None and other.version is not None:
        return ArxivId(preferred.identifier, other.version, preferred.source)
    return preferred


def detect(path: str, metadata: dict | None, first_page_text: str) -> ArxivId | None:
    """Prefer the margin stamp, then metadata, then the file name.

    The stamp is the id printed on the PDF the user opened. A version suffix
    from another source is kept when it names the same id and the winner
    itself has none.
    """
    stamp = from_stamp(first_page_text)
    meta = from_metadata(metadata)
    named = from_filename(path)
    if stamp is not None:
        agreed = _with_version(stamp, meta)
        return _with_version(agreed, named)
    if meta is not None:
        return _with_version(meta, named)
    return named
