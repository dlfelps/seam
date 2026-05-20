"""Shared fixtures for the Seam benchmark acceptance tests.

These tests are run cumulatively after each feature step. They are deliberately written
against the public surface described in spec.md and the feature prompts. They monkeypatch
low-level filesystem primitives only where unavoidable (the retry test), and document why.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

# Make ./src importable when pytest is invoked from the project root.
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))


SAMPLE_XML = """\
<document>
  <id>doc-001</id>
  <title>First post</title>
  <body>Hello world.</body>
  <timestamp>2026-05-19T12:00:00Z</timestamp>
</document>
"""

SAMPLE_JSON = """\
{
  "id": "doc-002",
  "title": "Second post",
  "body": "From JSON.",
  "timestamp": "2026-05-19T13:00:00Z"
}
"""

MALFORMED_XML = "<document><id>broken</id"


@pytest.fixture
def xml_file(tmp_path: Path) -> Path:
    p = tmp_path / "doc.xml"
    p.write_text(SAMPLE_XML)
    return p


@pytest.fixture
def json_file(tmp_path: Path) -> Path:
    p = tmp_path / "doc.json"
    p.write_text(SAMPLE_JSON)
    return p


@pytest.fixture
def malformed_xml_file(tmp_path: Path) -> Path:
    p = tmp_path / "broken.xml"
    p.write_text(MALFORMED_XML)
    return p


@pytest.fixture
def store_root(tmp_path: Path) -> str:
    root = tmp_path / "store"
    root.mkdir()
    return str(root)
