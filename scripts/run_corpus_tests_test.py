import importlib.util
import tempfile
import unittest
from pathlib import Path


def load_runner():
    module_path = Path(__file__).with_name("run_corpus_tests.py")
    spec = importlib.util.spec_from_file_location("run_corpus_tests", module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CorpusRunnerTest(unittest.TestCase):
    def test_load_toml_1_0_paths_filters_by_kind(self):
        runner = load_runner()

        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            tests = repo / "tests"
            (tests / "valid").mkdir(parents=True)
            (tests / "invalid").mkdir()
            (tests / "valid" / "a.toml").write_text("a = 1\n", encoding="utf-8")
            (tests / "invalid" / "b.toml").write_text("= nope\n", encoding="utf-8")
            (tests / "files-toml-1.0.0").write_text(
                "\n".join(
                    [
                        "valid/a.toml",
                        "invalid/b.toml",
                        "valid/not-json.json",
                        "valid/missing.txt",
                    ]
                ),
                encoding="utf-8",
            )

            self.assertEqual(
                [Path("valid/a.toml")],
                runner.load_toml_1_0_paths(repo, "valid"),
            )
            self.assertEqual(
                [Path("invalid/b.toml")],
                runner.load_toml_1_0_paths(repo, "invalid"),
            )

    def test_gleam_test_name_is_lowercase_identifier(self):
        runner = load_runner()

        self.assertEqual(
            "invalid_key_bare_02_test",
            runner.gleam_test_name("invalid", "key/bare-02"),
        )


if __name__ == "__main__":
    unittest.main()
