from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import unittest


ROOT = Path(__file__).parents[4]
SCRIPT = ROOT / ".apm/skills/session-friction-log/scripts/extract_claude_friction.py"
FIXTURE = Path(__file__).parent / "fixtures/claude-transcript.jsonl"


class ClaudeTranscriptExtractionTest(unittest.TestCase):
    def test_collects_user_prompt_denial_and_error(self):
        spec = spec_from_file_location("extract_claude_friction", SCRIPT)
        module = module_from_spec(spec)
        assert spec.loader is not None
        spec.loader.exec_module(module)

        data = module.collect(FIXTURE)

        self.assertEqual(
            [event["kind"] for event in data["events"]],
            ["user-prompt", "tool-denied", "tool-error"],
        )


if __name__ == "__main__":
    unittest.main()
