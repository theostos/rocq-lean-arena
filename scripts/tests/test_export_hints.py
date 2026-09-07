"""Small converter tests; no Lean or Rocq process is started."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "converter", ROOT / "checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py")
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)


class HintTests(unittest.TestCase):
    def conversion(self, kind, hints=None, cls=converter.Converter):
        instance = cls.__new__(cls)
        lines = []
        instance.declare_name = Mock()
        instance.name = lambda n: n
        instance.expr = lambda n: n
        instance.raw_expr = lambda n: {"tag": "const"}
        instance.level_params = lambda decl: []
        instance.emit = lines.append
        decl = {"name": 1, "type": 2, "value": 3}
        if hints is not None:
            decl["hints"] = hints
        instance.convert_decl({kind: decl})
        return lines

    def test_definition_hints(self):
        for hint, marker in [(None, "#DEF"), ("abbrev", "#ABBREV"),
                             ("opaque", "#HINT_OPAQUE"),
                             ({"regular": 0}, "#REGULAR 0"),
                             ({"regular": 17}, "#REGULAR 17")]:
            with self.subTest(hint=hint):
                self.assertEqual(self.conversion("def", hint), [f"{marker} 1 2 3"])

    def test_opacity_is_not_a_hint(self):
        for cls in (converter.Converter, converter.StreamingConverter):
            self.assertEqual(self.conversion("opaque", "abbrev", cls), ["#OPAQUE 1 2 3"])
            self.assertEqual(self.conversion("thm", "abbrev", cls), ["#HINT_OPAQUE 1 2 3"])

    def test_invalid_hints(self):
        for hint in ("bad", [], {"regular": True}, {"regular": -1},
                     {"regular": "3"}, {"regular": 2, "other": 1}):
            with self.subTest(hint=hint), self.assertRaises(converter.ConvertError):
                self.conversion("def", hint)


if __name__ == "__main__":
    unittest.main()
