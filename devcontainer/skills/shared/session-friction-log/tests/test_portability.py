from pathlib import Path
import unittest


ROOT = Path(__file__).parents[4]
SHARED_FILES = [
    ROOT / ".apm/skills/session-friction-log/SKILL.md",
    ROOT / ".apm/skills/session-friction-log/references/log-format.md",
    ROOT / "docs/agent-friction-log.md",
]


class SharedContentPortabilityTest(unittest.TestCase):
    def test_shared_content_has_no_agent_specific_required_paths(self):
        shared = "\n".join(path.read_text(encoding="utf-8") for path in SHARED_FILES)

        self.assertNotIn("~/.claude/projects", shared)
        self.assertNotIn("auto memory", shared)
        self.assertNotIn("update-config", shared)
        self.assertNotIn("apm compile", shared)
        self.assertNotIn("apm install", shared)


if __name__ == "__main__":
    unittest.main()
