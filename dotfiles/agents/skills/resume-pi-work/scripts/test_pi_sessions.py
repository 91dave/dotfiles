#!/usr/bin/env python3
"""Tests for the pi session reader.

Run with:  python3 -m unittest discover -s <this directory>
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import extract_pi_session as extract  # noqa: E402
import list_pi_sessions as lister  # noqa: E402
import pi_session as pi  # noqa: E402

CWD = "/mnt/c/Code/quartex-services/qtms-publication"


def header(**overrides):
    entry = {
        "type": "session",
        "version": 3,
        "id": "01a004b2-40f6-70c7-818a-d7ce36f870fc",
        "timestamp": "2026-08-15T09:13:06.038Z",
        "cwd": CWD,
    }
    entry.update(overrides)
    return entry


def message(entry_id, parent, role, content, **message_fields):
    payload = {"role": role, "content": content, "timestamp": 1}
    payload.update(message_fields)
    return {
        "type": "message",
        "id": entry_id,
        "parentId": parent,
        "timestamp": "2026-08-15T09:13:07.000Z",
        "message": payload,
    }


def write_session(directory: Path, entries, name="2026-08-15T09-13-06-038Z_01a004b2-40f6-70c7-818a-d7ce36f870fc.jsonl"):
    folder = directory / pi.encode_cwd(CWD)
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / name
    path.write_text("\n".join(json.dumps(e) for e in entries) + "\n", encoding="utf-8")
    return path


class TempSessionRoot(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self._previous = os.environ.get("PI_CODING_AGENT_SESSION_DIR")
        os.environ["PI_CODING_AGENT_SESSION_DIR"] = str(self.root)
        self.addCleanup(self._restore)

    def _restore(self):
        if self._previous is None:
            os.environ.pop("PI_CODING_AGENT_SESSION_DIR", None)
        else:
            os.environ["PI_CODING_AGENT_SESSION_DIR"] = self._previous
        self._tmp.cleanup()


class EncodeCwdTests(unittest.TestCase):
    def test_encodes_separators_and_wraps(self):
        self.assertEqual(pi.encode_cwd("/mnt/c/Code/foo"), "--mnt-c-Code-foo--")

    def test_literal_hyphens_survive_and_are_not_reversible(self):
        encoded = pi.encode_cwd(CWD)
        self.assertEqual(encoded, "--mnt-c-Code-quartex-services-qtms-publication--")
        self.assertEqual(encoded.count("-") - 4, 6)


class BranchTests(unittest.TestCase):
    def test_abandoned_branch_is_excluded(self):
        entries = [
            message("aaaaaaaa", None, "user", [{"type": "text", "text": "first"}]),
            message("bbbbbbbb", "aaaaaaaa", "assistant", [{"type": "text", "text": "reply"}]),
            message("cccccccc", "bbbbbbbb", "user", [{"type": "text", "text": "approach A"}]),
            message("dddddddd", "bbbbbbbb", "user", [{"type": "text", "text": "approach B"}]),
        ]
        branch = pi.active_branch(entries)
        self.assertEqual([e["id"] for e in branch], ["aaaaaaaa", "bbbbbbbb", "dddddddd"])

    def test_cycle_does_not_hang(self):
        entries = [
            {"type": "message", "id": "aaaa", "parentId": "bbbb", "message": {"role": "user", "content": "x"}},
            {"type": "message", "id": "bbbb", "parentId": "aaaa", "message": {"role": "user", "content": "y"}},
        ]
        self.assertEqual(len(pi.active_branch(entries)), 2)


class CompactionTests(unittest.TestCase):
    def _branch(self, compaction):
        return [
            message("aaaaaaaa", None, "user", "old"),
            message("bbbbbbbb", "aaaaaaaa", "user", "kept"),
            compaction,
            message("dddddddd", "cccccccc", "user", "after"),
        ]

    def test_retained_tail_drops_everything_before(self):
        compaction = {
            "type": "compaction",
            "id": "cccccccc",
            "parentId": "bbbbbbbb",
            "summary": "handover",
            "retainedTail": [{"role": "user", "content": "latest"}],
        }
        kept = pi.apply_compaction(self._branch(compaction))
        self.assertEqual([e["id"] for e in kept], ["cccccccc", "dddddddd"])

    def test_first_kept_entry_id_rewinds_to_that_entry(self):
        compaction = {
            "type": "compaction",
            "id": "cccccccc",
            "parentId": "bbbbbbbb",
            "summary": "handover",
            "firstKeptEntryId": "bbbbbbbb",
        }
        kept = pi.apply_compaction(self._branch(compaction))
        self.assertEqual([e["id"] for e in kept], ["bbbbbbbb", "cccccccc", "dddddddd"])

    def test_no_compaction_is_a_passthrough(self):
        branch = [message("aaaaaaaa", None, "user", "only")]
        self.assertEqual(pi.apply_compaction(branch), branch)


class ContentTests(unittest.TestCase):
    def test_string_content_is_read(self):
        self.assertEqual(pi.text_of("plain string"), "plain string")

    def test_block_list_content_is_joined(self):
        content = [{"type": "text", "text": "a"}, {"type": "thinking", "thinking": "z"}, {"type": "text", "text": "b"}]
        self.assertEqual(pi.text_of(content), "a\nb")

    def test_unknown_content_shape_is_empty(self):
        self.assertEqual(pi.text_of(None), "")


class LoadTests(TempSessionRoot):
    def test_blank_and_corrupt_lines_are_skipped(self):
        folder = self.root / pi.encode_cwd(CWD)
        folder.mkdir(parents=True)
        path = folder / "2026-08-15T09-13-06-038Z_01a004b2.jsonl"
        path.write_text(
            json.dumps(header())
            + "\n\nnot json at all\n"
            + json.dumps(message("aaaaaaaa", None, "user", "hello"))
            + "\n",
            encoding="utf-8",
        )
        session = pi.load(path)
        self.assertEqual(session.cwd, CWD)
        self.assertEqual(session.first_prompt(), "hello")

    def test_session_info_name_beats_first_prompt(self):
        path = write_session(
            self.root,
            [
                header(),
                message("aaaaaaaa", None, "user", "do the thing"),
                {"type": "session_info", "id": "bbbbbbbb", "parentId": "aaaaaaaa", "name": "Refactor auth"},
            ],
        )
        session = pi.load(path)
        self.assertEqual(session.title(), "Refactor auth")

    def test_last_model_and_thinking_level_win(self):
        path = write_session(
            self.root,
            [
                header(),
                {"type": "model_change", "id": "aaaaaaaa", "parentId": None, "modelId": "old-model"},
                {"type": "thinking_level_change", "id": "bbbbbbbb", "parentId": "aaaaaaaa", "thinkingLevel": "low"},
                {"type": "model_change", "id": "cccccccc", "parentId": "bbbbbbbb", "modelId": "new-model"},
                {"type": "thinking_level_change", "id": "dddddddd", "parentId": "cccccccc", "thinkingLevel": "high"},
            ],
        )
        session = pi.load(path)
        self.assertEqual(session.model, "new-model")
        self.assertEqual(session.thinking_level, "high")

    def test_bash_execution_is_kept_as_its_own_role(self):
        path = write_session(
            self.root,
            [
                header(),
                {
                    "type": "message",
                    "id": "aaaaaaaa",
                    "parentId": None,
                    "message": {"role": "bashExecution", "command": "az login", "output": "ok", "exitCode": 0},
                },
            ],
        )
        session = pi.load(path)
        self.assertEqual(len(session.messages("bashExecution")), 1)


class WrittenPathTests(unittest.TestCase):
    def _session(self, calls):
        entries = [message("aaaaaaaa", None, "assistant", calls)]
        return pi.Session(path=Path("x.jsonl"), header=header(), entries=entries)

    def test_edit_and_write_paths_are_deduped_in_order(self):
        session = self._session(
            [
                {"type": "toolCall", "id": "1", "name": "write", "arguments": {"path": "/a", "content": "x"}},
                {"type": "toolCall", "id": "2", "name": "edit", "arguments": {"path": "/b", "edits": []}},
                {"type": "toolCall", "id": "3", "name": "edit", "arguments": {"path": "/a", "edits": []}},
            ]
        )
        self.assertEqual(pi.written_paths(session), ["/a", "/b"])

    def test_edit_without_a_path_is_tolerated(self):
        session = self._session([{"type": "toolCall", "id": "1", "name": "edit", "arguments": {"edits": []}}])
        self.assertEqual(pi.written_paths(session), [])

    def test_read_calls_are_not_counted_as_changes(self):
        session = self._session([{"type": "toolCall", "id": "1", "name": "read", "arguments": {"path": "/a"}}])
        self.assertEqual(pi.written_paths(session), [])


class FinishStateTests(unittest.TestCase):
    def _session(self, entries):
        return pi.Session(path=Path("x.jsonl"), header=header(), entries=entries)

    def test_clean_finish(self):
        session = self._session(
            [message("aaaaaaaa", None, "assistant", [{"type": "text", "text": "done"}], stopReason="stop")]
        )
        self.assertEqual(pi.finish_state(session)["state"], "complete")

    def test_error_message_signals_a_dead_session(self):
        session = self._session(
            [
                message(
                    "aaaaaaaa",
                    None,
                    "assistant",
                    [{"type": "text", "text": "partial"}],
                    stopReason="error",
                    errorMessage="budget exhausted",
                )
            ]
        )
        ending = pi.finish_state(session)
        self.assertEqual(ending["state"], "error")
        self.assertEqual(ending["error_message"], "budget exhausted")

    def test_tool_call_without_a_result_is_interrupted(self):
        session = self._session(
            [
                message(
                    "aaaaaaaa",
                    None,
                    "assistant",
                    [{"type": "toolCall", "id": "toolu_1", "name": "bash", "arguments": {"command": "curl x"}}],
                    stopReason="toolUse",
                )
            ]
        )
        ending = pi.finish_state(session)
        self.assertEqual(ending["state"], "interrupted")
        self.assertEqual(ending["dangling_tool"], "bash")

    def test_matched_result_is_not_dangling(self):
        session = self._session(
            [
                message(
                    "aaaaaaaa",
                    None,
                    "assistant",
                    [{"type": "toolCall", "id": "toolu_1", "name": "bash", "arguments": {}}],
                    stopReason="toolUse",
                ),
                message("bbbbbbbb", "aaaaaaaa", "toolResult", [{"type": "text", "text": "ok"}], toolCallId="toolu_1"),
                message("cccccccc", "bbbbbbbb", "assistant", [{"type": "text", "text": "done"}], stopReason="stop"),
            ]
        )
        self.assertIsNone(pi.finish_state(session)["dangling_tool"])


class ExtractTests(TempSessionRoot):
    def test_brief_omits_tool_output_and_surfaces_intent(self):
        path = write_session(
            self.root,
            [
                header(),
                message("aaaaaaaa", None, "user", [{"type": "text", "text": "fix the retry"}]),
                message(
                    "bbbbbbbb",
                    "aaaaaaaa",
                    "assistant",
                    [
                        {"type": "thinking", "thinking": "secret reasoning", "thinkingSignature": "x" * 400},
                        {"type": "toolCall", "id": "toolu_1", "name": "edit", "arguments": {"path": "/src/a.ts"}},
                    ],
                    stopReason="toolUse",
                ),
                message(
                    "cccccccc",
                    "bbbbbbbb",
                    "toolResult",
                    [{"type": "text", "text": "ENORMOUS TOOL OUTPUT"}],
                    toolCallId="toolu_1",
                    toolName="edit",
                    isError=False,
                    details={"diff": "@@ -1 +1 @@\n-a\n+b", "truncation": {"content": "SHOULD NOT APPEAR"}},
                ),
                message("dddddddd", "cccccccc", "assistant", [{"type": "text", "text": "Done."}], stopReason="stop"),
            ],
        )
        brief = extract.render(extract.collect(pi.load(path), tail=20), full=False)
        self.assertIn("fix the retry", brief)
        self.assertIn("/src/a.ts", brief)
        self.assertIn("+b", brief)
        self.assertNotIn("ENORMOUS TOOL OUTPUT", brief)
        self.assertNotIn("SHOULD NOT APPEAR", brief)
        self.assertNotIn("secret reasoning", brief)

    def test_null_subagent_result_is_tolerated(self):
        path = write_session(
            self.root,
            [
                header(),
                message(
                    "aaaaaaaa",
                    None,
                    "toolResult",
                    [{"type": "text", "text": "x"}],
                    toolCallId="toolu_1",
                    toolName="subagent",
                    details={"results": [None, {"agent": "explorer", "task": "look", "stopReason": "stop"}]},
                ),
            ],
        )
        data = extract.collect(pi.load(path), tail=20)
        self.assertEqual([a["agent"] for a in data["subagents"]], ["explorer"])

    def test_missing_session_reference_is_an_error(self):
        self.assertEqual(extract.main(["does-not-exist"]), 1)


class DemoteHeadingsTests(unittest.TestCase):
    def test_quoted_headings_sit_below_the_briefs_own(self):
        self.assertEqual(extract.demote_headings("## Goal"), "##### Goal")

    def test_headings_inside_code_fences_are_left_alone(self):
        text = "# real\n```sh\n# a shell comment\n```"
        self.assertEqual(extract.demote_headings(text).splitlines()[2], "# a shell comment")

    def test_level_is_capped_at_six(self):
        self.assertEqual(extract.demote_headings("##### deep"), "###### deep")

    def test_prose_is_untouched(self):
        self.assertEqual(extract.demote_headings("plain line"), "plain line")


class OneLineTests(unittest.TestCase):
    def test_newlines_and_runs_of_space_collapse(self):
        self.assertEqual(extract.one_line("429 quota exceeded\n\n", 100), "429 quota exceeded")

    def test_limit_is_applied(self):
        self.assertEqual(extract.one_line("abcdef", 3), "abc")


class ListTests(TempSessionRoot):
    def setUp(self):
        super().setUp()
        self.path = write_session(
            self.root,
            [
                header(),
                message("aaaaaaaa", None, "user", [{"type": "text", "text": "investigate the ingest retry"}]),
                message("bbbbbbbb", "aaaaaaaa", "assistant", [{"type": "text", "text": "ok"}], stopReason="stop"),
            ],
        )

    def test_folder_scoped_listing_finds_the_session(self):
        rows = [lister.summarise(p) for p in lister.candidate_files(Path(CWD))]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["title"], "investigate the ingest retry")
        self.assertEqual(rows[0]["state"], "complete")

    def test_subdirectory_sessions_are_in_scope(self):
        self.assertTrue(lister.under(CWD + "/src", Path(CWD)))
        self.assertTrue(lister.under(CWD, Path(CWD)))
        self.assertFalse(lister.under("/mnt/c/Code/other", Path(CWD)))

    def test_sibling_folder_with_a_shared_prefix_is_rejected_by_cwd(self):
        self.assertFalse(lister.under(CWD + "-legacy", Path(CWD)))

    def test_match_finds_text_in_the_transcript(self):
        self.assertTrue(lister.mentions(self.path, "INGEST retry"))
        self.assertFalse(lister.mentions(self.path, "kubernetes"))


if __name__ == "__main__":
    unittest.main()
