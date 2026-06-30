#!/usr/bin/env python3
"""Convert Lean 4 NDJSON export files to rocq-lean-import's legacy format."""

from __future__ import annotations

import json
import os
import sys
from bisect import bisect_right
from pathlib import Path
from typing import Any, TextIO


BINDER_KIND = {
    "default": "#BD",
    "implicit": "#BI",
    "strictImplicit": "#BS",
    "instImplicit": "#BC",
}


class ConvertError(Exception):
    pass


class RejectExport(Exception):
    pass


class DenseIdMap:
    """Map NDJSON ids to dense legacy ids while keeping dense cases cheap."""

    def __init__(self, start: int) -> None:
        self.next_id = start
        self.starts: list[int] = []
        self.ranges: list[tuple[int, int, int]] = []
        self.aliases: dict[int, int] = {}

    def range_index(self, original: int) -> int | None:
        idx = bisect_right(self.starts, original) - 1
        if idx >= 0:
            start, end, _ = self.ranges[idx]
            if start <= original < end:
                return idx
        return None

    def is_defined(self, original: int) -> bool:
        return original in self.aliases or self.range_index(original) is not None

    def define(self, original: int) -> int:
        if self.is_defined(original):
            raise ConvertError(f"id {original} is defined twice")
        dense = self.next_id
        self.next_id += 1

        insert_at = bisect_right(self.starts, original)
        start = original
        end = original + 1
        dense_start = dense

        if insert_at > 0:
            prev_start, prev_end, prev_dense_start = self.ranges[insert_at - 1]
            if prev_end == start and prev_dense_start + (prev_end - prev_start) == dense_start:
                start = prev_start
                dense_start = prev_dense_start
                del self.ranges[insert_at - 1]
                del self.starts[insert_at - 1]
                insert_at -= 1

        if insert_at < len(self.ranges):
            next_start, next_end, next_dense_start = self.ranges[insert_at]
            if end == next_start and dense_start + (end - start) == next_dense_start:
                end = next_end
                del self.ranges[insert_at]
                del self.starts[insert_at]

        self.ranges.insert(insert_at, (start, end, dense_start))
        self.starts.insert(insert_at, start)
        return dense

    def alias(self, original: int, dense: int) -> None:
        if self.is_defined(original):
            raise ConvertError(f"id {original} is defined twice")
        self.aliases[original] = dense

    def get(self, original: int, what: str) -> int:
        alias = self.aliases.get(original)
        if alias is not None:
            return alias
        idx = self.range_index(original)
        if idx is None:
            raise ConvertError(f"{what} id {original} is referenced before it is defined")
        start, _, dense_start = self.ranges[idx]
        return dense_start + (original - start)


class Converter:
    def __init__(self, out: TextIO) -> None:
        self.out = out
        self.names: dict[int, int] = {0: 0}
        self.raw_names: dict[int, dict[str, Any]] = {0: {"tag": "anon"}}
        self.levels: dict[int, int] = {0: 0}
        self.exprs: dict[int, int] = {}
        self.raw_levels: dict[int, dict[str, Any]] = {0: {"tag": "prop"}}
        self.raw_exprs: dict[int, dict[str, Any]] = {}
        self.declared_names: set[int] = set()
        self.next_name = 1
        self.next_level = 1
        self.next_expr = 0
        self.emitted_quot = False

    def emit(self, line: str) -> None:
        print(line, file=self.out)

    def name(self, idx: int) -> int:
        try:
            return self.names[idx]
        except KeyError as exc:
            raise ConvertError(f"name id {idx} is referenced before it is defined") from exc

    def level(self, idx: int) -> int:
        try:
            return self.levels[idx]
        except KeyError as exc:
            raise ConvertError(f"level id {idx} is referenced before it is defined") from exc

    def expr(self, idx: int) -> int:
        try:
            return self.exprs[idx]
        except KeyError as exc:
            raise ConvertError(f"expression id {idx} is referenced before it is defined") from exc

    def fresh_name(self, original: int) -> int:
        if original in self.names:
            raise ConvertError(f"name id {original} is defined twice")
        dense = self.next_name
        self.next_name += 1
        self.names[original] = dense
        return dense

    def fresh_level(self, original: int) -> int:
        if original in self.levels:
            raise ConvertError(f"level id {original} is defined twice")
        dense = self.next_level
        self.next_level += 1
        self.levels[original] = dense
        return dense

    def fresh_expr(self, original: int) -> int:
        if original in self.exprs:
            raise ConvertError(f"expression id {original} is defined twice")
        dense = self.next_expr
        self.next_expr += 1
        self.exprs[original] = dense
        return dense

    @staticmethod
    def atom(value: Any, what: str) -> str:
        text = str(value)
        if not text or any(ch.isspace() for ch in text):
            raise ConvertError(f"{what} cannot be represented in legacy export syntax: {text!r}")
        return text

    def convert_name(self, obj: dict[str, Any]) -> None:
        original = int(obj["in"])
        dense = self.fresh_name(original)
        if "str" in obj:
            data = obj["str"]
            self.raw_names[original] = {"tag": "str", "pre": int(data["pre"]), "str": str(data["str"])}
            self.emit(f"{dense} #NS {self.name(int(data['pre']))} {self.atom(data['str'], 'name component')}")
        elif "num" in obj:
            data = obj["num"]
            self.raw_names[original] = {"tag": "num", "pre": int(data["pre"]), "i": int(data["i"])}
            self.emit(f"{dense} #NI {self.name(int(data['pre']))} {self.atom(data['i'], 'numeric name component')}")
        else:
            raise ConvertError(f"unknown name object: {obj}")

    def convert_level(self, obj: dict[str, Any]) -> None:
        original = int(obj["il"])
        dense = self.fresh_level(original)
        if "succ" in obj:
            self.raw_levels[original] = {"tag": "succ", "level": int(obj["succ"])}
            self.emit(f"{dense} #US {self.level(int(obj['succ']))}")
        elif "max" in obj:
            a, b = obj["max"]
            self.raw_levels[original] = {"tag": "max", "left": int(a), "right": int(b)}
            self.emit(f"{dense} #UM {self.level(int(a))} {self.level(int(b))}")
        elif "imax" in obj:
            a, b = obj["imax"]
            self.raw_levels[original] = {"tag": "imax", "left": int(a), "right": int(b)}
            self.emit(f"{dense} #UIM {self.level(int(a))} {self.level(int(b))}")
        elif "param" in obj:
            self.raw_levels[original] = {"tag": "param", "name": int(obj["param"])}
            self.emit(f"{dense} #UP {self.name(int(obj['param']))}")
        else:
            raise ConvertError(f"unknown level object: {obj}")

    def binder(self, value: str) -> str:
        try:
            return BINDER_KIND[value]
        except KeyError as exc:
            raise ConvertError(f"unsupported binderInfo: {value}") from exc

    def convert_expr(self, obj: dict[str, Any]) -> None:
        original = int(obj["ie"])
        if "mdata" in obj:
            self.exprs[original] = self.expr(int(obj["mdata"]["expr"]))
            self.raw_exprs[original] = self.raw_expr(int(obj["mdata"]["expr"]))
            return

        dense = self.fresh_expr(original)
        if "bvar" in obj:
            self.raw_exprs[original] = {"tag": "bvar", "idx": int(obj["bvar"])}
            self.emit(f"{dense} #EV {int(obj['bvar'])}")
        elif "sort" in obj:
            self.raw_exprs[original] = {"tag": "sort", "level": int(obj["sort"])}
            self.emit(f"{dense} #ES {self.level(int(obj['sort']))}")
        elif "const" in obj:
            data = obj["const"]
            self.raw_exprs[original] = {
                "tag": "const",
                "name": int(data["name"]),
                "us": [int(level) for level in data.get("us", [])],
            }
            levels = " ".join(str(self.level(int(level))) for level in data.get("us", []))
            suffix = f" {levels}" if levels else ""
            self.emit(f"{dense} #EC {self.name(int(data['name']))}{suffix}")
        elif "app" in obj:
            data = obj["app"]
            self.raw_exprs[original] = {"tag": "app", "fn": int(data["fn"]), "arg": int(data["arg"])}
            self.emit(f"{dense} #EA {self.expr(int(data['fn']))} {self.expr(int(data['arg']))}")
        elif "letE" in obj:
            data = obj["letE"]
            self.raw_exprs[original] = {
                "tag": "letE",
                "name": int(data["name"]),
                "type": int(data["type"]),
                "value": int(data["value"]),
                "body": int(data["body"]),
            }
            self.emit(
                f"{dense} #EZ {self.name(int(data['name']))} {self.expr(int(data['type']))} "
                f"{self.expr(int(data['value']))} {self.expr(int(data['body']))}"
            )
        elif "lam" in obj:
            data = obj["lam"]
            self.raw_exprs[original] = {
                "tag": "lam",
                "name": int(data["name"]),
                "type": int(data["type"]),
                "body": int(data["body"]),
                "binderInfo": data["binderInfo"],
            }
            self.emit(
                f"{dense} #EL {self.binder(data['binderInfo'])} {self.name(int(data['name']))} "
                f"{self.expr(int(data['type']))} {self.expr(int(data['body']))}"
            )
        elif "forallE" in obj:
            data = obj["forallE"]
            self.raw_exprs[original] = {
                "tag": "forallE",
                "name": int(data["name"]),
                "type": int(data["type"]),
                "body": int(data["body"]),
                "binderInfo": data["binderInfo"],
            }
            self.emit(
                f"{dense} #EP {self.binder(data['binderInfo'])} {self.name(int(data['name']))} "
                f"{self.expr(int(data['type']))} {self.expr(int(data['body']))}"
            )
        elif "proj" in obj:
            data = obj["proj"]
            self.raw_exprs[original] = {
                "tag": "proj",
                "typeName": int(data["typeName"]),
                "idx": int(data["idx"]),
                "struct": int(data["struct"]),
            }
            self.emit(f"{dense} #EJ {self.name(int(data['typeName']))} {int(data['idx'])} {self.expr(int(data['struct']))}")
        elif "natVal" in obj:
            self.raw_exprs[original] = {"tag": "natVal", "value": str(obj["natVal"])}
            self.emit(f"{dense} #ELN {self.atom(obj['natVal'], 'natural literal')}")
        elif "strVal" in obj:
            self.raw_exprs[original] = {"tag": "strVal", "value": str(obj["strVal"])}
            payload = str(obj["strVal"]).encode("utf-8")
            bytes_hex = " ".join(f"{byte:02X}" for byte in payload)
            suffix = f" {bytes_hex}" if bytes_hex else ""
            self.emit(f"{dense} #ELS{suffix}")
        else:
            raise ConvertError(f"unknown expression object: {obj}")

    def raw_expr(self, idx: int) -> dict[str, Any]:
        try:
            return self.raw_exprs[idx]
        except KeyError as exc:
            raise ConvertError(f"expression id {idx} is referenced before it is defined") from exc

    def declare_name(self, name_id: int, what: str) -> None:
        if name_id in self.declared_names:
            raise RejectExport(f"duplicate declaration name for {what}: name id {name_id}")
        self.declared_names.add(name_id)

    def find_str_child_name(self, parent_id: int, component: str) -> int | None:
        for name_id, name in self.raw_names.items():
            if name.get("tag") == "str" and name.get("pre") == parent_id and name.get("str") == component:
                return name_id
        return None

    def final_body(self, expr_id: int) -> int:
        while self.raw_expr(expr_id)["tag"] == "forallE":
            expr_id = int(self.raw_expr(expr_id)["body"])
        return expr_id

    def app_head(self, expr_id: int) -> dict[str, Any]:
        expr = self.raw_expr(expr_id)
        while expr["tag"] == "app":
            expr = self.raw_expr(int(expr["fn"]))
        return expr

    def has_negative_occurrence(self, ind_name: int, expr_id: int, polarity: int = 1) -> bool:
        expr = self.raw_expr(expr_id)
        tag = expr["tag"]
        if tag == "const":
            return polarity < 0 and int(expr["name"]) == ind_name
        if tag == "app":
            return self.has_negative_occurrence(ind_name, int(expr["fn"]), polarity) or self.has_negative_occurrence(
                ind_name, int(expr["arg"]), polarity
            )
        if tag == "forallE":
            return self.has_negative_occurrence(ind_name, int(expr["type"]), -polarity) or self.has_negative_occurrence(
                ind_name, int(expr["body"]), polarity
            )
        if tag == "lam":
            return self.has_negative_occurrence(ind_name, int(expr["type"]), polarity) or self.has_negative_occurrence(
                ind_name, int(expr["body"]), polarity
            )
        if tag == "letE":
            return (
                self.has_negative_occurrence(ind_name, int(expr["type"]), polarity)
                or self.has_negative_occurrence(ind_name, int(expr["value"]), polarity)
                or self.has_negative_occurrence(ind_name, int(expr["body"]), polarity)
            )
        if tag == "proj":
            return self.has_negative_occurrence(ind_name, int(expr["struct"]), polarity)
        return False

    def validate_ctor_positivity(self, ind: dict[str, Any], ctor: dict[str, Any]) -> None:
        ind_name = int(ind["name"])
        expr_id = int(ctor["type"])
        skipped_params = int(ctor.get("numParams", ind.get("numParams", 0)))
        while self.raw_expr(expr_id)["tag"] == "forallE":
            expr = self.raw_expr(expr_id)
            binder_type = int(expr["type"])
            if skipped_params > 0:
                skipped_params -= 1
            elif self.has_negative_occurrence(ind_name, binder_type):
                raise RejectExport(
                    f"constructor {ctor['name']} has a negative occurrence of inductive {ind_name} "
                    "in a field type"
                )
            expr_id = int(expr["body"])

    def validate_ctor_result(self, ind: dict[str, Any], ctor: dict[str, Any]) -> None:
        body_id = self.final_body(int(ctor["type"]))
        head = self.app_head(body_id)
        ind_name = int(ind["name"])
        if head["tag"] != "const" or int(head["name"]) != ind_name:
            raise RejectExport(
                f"constructor {ctor['name']} result does not have inductive {ind_name} as its manifest head"
            )
        expected_levels = [int(param) for param in ind.get("levelParams", [])]
        actual_levels = [self.level_param_name(int(param)) for param in head.get("us", [])]
        if actual_levels != expected_levels:
            raise RejectExport(
                f"constructor {ctor['name']} result universe parameters {actual_levels} "
                f"do not match inductive {ind_name} parameters {expected_levels}"
            )

    def level_param_name(self, level_id: int) -> int | None:
        for original, dense in self.levels.items():
            if dense == level_id:
                raw_level_id = original
                break
        else:
            raise ConvertError(f"level id {level_id} is not defined")

        level = self.raw_levels.get(raw_level_id)
        if level is None:
            raise ConvertError(f"raw level id {raw_level_id} is not defined")
        if level["tag"] == "param":
            return int(level["name"])
        return None

    def level_params(self, decl: dict[str, Any]) -> list[str]:
        return [str(self.name(int(param))) for param in decl.get("levelParams", [])]

    def convert_definition(self, decl: dict[str, Any]) -> None:
        self.declare_name(int(decl["name"]), "definition")
        parts = [
            "#DEF",
            str(self.name(int(decl["name"]))),
            str(self.expr(int(decl["type"]))),
            str(self.expr(int(decl["value"]))),
            *self.level_params(decl),
        ]
        self.emit(" ".join(parts))

    def convert_axiom(self, decl: dict[str, Any]) -> None:
        self.declare_name(int(decl["name"]), "axiom")
        parts = [
            "#AX",
            str(self.name(int(decl["name"]))),
            str(self.expr(int(decl["type"]))),
            *self.level_params(decl),
        ]
        self.emit(" ".join(parts))

    def convert_theorem(self, decl: dict[str, Any]) -> None:
        if self.raw_expr(int(decl["type"]))["tag"] == "sort":
            raise RejectExport("theorem type is a universe, not a proposition")
        self.convert_definition(decl)

    def convert_quot(self, decl: dict[str, Any]) -> None:
        if decl.get("kind") == "type" and not self.emitted_quot:
            self.emit("#QUOT")
            self.emitted_quot = True

    def convert_inductive(self, group: dict[str, Any]) -> None:
        ctors_by_induct: dict[int, list[dict[str, Any]]] = {}
        for ctor in group.get("ctors", []):
            ctors_by_induct.setdefault(int(ctor["induct"]), []).append(ctor)

        for ind in group.get("types", []):
            self.declare_name(int(ind["name"]), "inductive type")
        for ctor in group.get("ctors", []):
            self.declare_name(int(ctor["name"]), "constructor")
        rec_names = {int(rec["name"]) for rec in group.get("recs", [])}
        for rec in group.get("recs", []):
            self.declare_name(int(rec["name"]), "recursor")
        for ind in group.get("types", []):
            canonical_rec = self.find_str_child_name(int(ind["name"]), "rec")
            if canonical_rec is not None and canonical_rec not in rec_names:
                if canonical_rec in self.declared_names:
                    raise RejectExport(
                        f"declaration uses canonical recursor name reserved for inductive {ind['name']}: "
                        f"name id {canonical_rec}"
                    )
                self.declared_names.add(canonical_rec)

        for ind in group.get("types", []):
            ind_name = int(ind["name"])
            ctors = [*ctors_by_induct.get(ind_name, [])]
            if ind.get("ctors"):
                order = {int(name): i for i, name in enumerate(ind["ctors"])}
                ctors.sort(key=lambda ctor: order.get(int(ctor["name"]), int(ctor.get("cidx", 0))))
            for ctor in ctors:
                self.validate_ctor_result(ind, ctor)
                self.validate_ctor_positivity(ind, ctor)
            parts = [
                "#IND",
                str(int(ind["numParams"])),
                str(self.name(ind_name)),
                str(self.expr(int(ind["type"]))),
                str(len(ctors)),
            ]
            for ctor in ctors:
                parts.extend([str(self.name(int(ctor["name"]))), str(self.expr(int(ctor["type"])))])
            parts.extend(self.level_params(ind))
            self.emit(" ".join(parts))

    def convert_decl(self, obj: dict[str, Any]) -> None:
        if "axiom" in obj:
            self.convert_axiom(obj["axiom"])
        elif "def" in obj:
            self.convert_definition(obj["def"])
        elif "thm" in obj:
            self.convert_theorem(obj["thm"])
        elif "opaque" in obj:
            self.convert_definition(obj["opaque"])
        elif "quot" in obj:
            self.convert_quot(obj["quot"])
        elif "inductive" in obj:
            self.convert_inductive(obj["inductive"])
        else:
            raise ConvertError(f"unknown declaration object: {obj}")

    def convert(self, obj: dict[str, Any]) -> None:
        if "meta" in obj:
            return
        if "in" in obj:
            self.convert_name(obj)
        elif "il" in obj:
            self.convert_level(obj)
        elif "ie" in obj:
            self.convert_expr(obj)
        else:
            self.convert_decl(obj)


class StreamingConverter(Converter):
    """Memory-light converter for large exports.

    This keeps dense ID remapping but deliberately skips the raw-expression
    validations used for small tutorial tests.
    """

    def __init__(self, out: TextIO) -> None:
        self.out = out
        self.names = DenseIdMap(start=1)
        self.levels = DenseIdMap(start=1)
        self.exprs = DenseIdMap(start=0)
        self.declared_names: set[int] = set()
        self.emitted_quot = False

    def name(self, idx: int) -> int:
        if idx == 0:
            return 0
        return self.names.get(idx, "name")

    def level(self, idx: int) -> int:
        if idx == 0:
            return 0
        return self.levels.get(idx, "level")

    def expr(self, idx: int) -> int:
        return self.exprs.get(idx, "expression")

    def convert_name(self, obj: dict[str, Any]) -> None:
        original = int(obj["in"])
        dense = self.names.define(original)
        if "str" in obj:
            data = obj["str"]
            self.emit(f"{dense} #NS {self.name(int(data['pre']))} {self.atom(data['str'], 'name component')}")
        elif "num" in obj:
            data = obj["num"]
            self.emit(f"{dense} #NI {self.name(int(data['pre']))} {self.atom(data['i'], 'numeric name component')}")
        else:
            raise ConvertError(f"unknown name object: {obj}")

    def convert_level(self, obj: dict[str, Any]) -> None:
        original = int(obj["il"])
        dense = self.levels.define(original)
        if "succ" in obj:
            self.emit(f"{dense} #US {self.level(int(obj['succ']))}")
        elif "max" in obj:
            a, b = obj["max"]
            self.emit(f"{dense} #UM {self.level(int(a))} {self.level(int(b))}")
        elif "imax" in obj:
            a, b = obj["imax"]
            self.emit(f"{dense} #UIM {self.level(int(a))} {self.level(int(b))}")
        elif "param" in obj:
            self.emit(f"{dense} #UP {self.name(int(obj['param']))}")
        else:
            raise ConvertError(f"unknown level object: {obj}")

    def convert_expr(self, obj: dict[str, Any]) -> None:
        original = int(obj["ie"])
        if "mdata" in obj:
            self.exprs.alias(original, self.expr(int(obj["mdata"]["expr"])))
            return

        dense = self.exprs.define(original)
        if "bvar" in obj:
            self.emit(f"{dense} #EV {int(obj['bvar'])}")
        elif "sort" in obj:
            self.emit(f"{dense} #ES {self.level(int(obj['sort']))}")
        elif "const" in obj:
            data = obj["const"]
            levels = " ".join(str(self.level(int(level))) for level in data.get("us", []))
            suffix = f" {levels}" if levels else ""
            self.emit(f"{dense} #EC {self.name(int(data['name']))}{suffix}")
        elif "app" in obj:
            data = obj["app"]
            self.emit(f"{dense} #EA {self.expr(int(data['fn']))} {self.expr(int(data['arg']))}")
        elif "letE" in obj:
            data = obj["letE"]
            self.emit(
                f"{dense} #EZ {self.name(int(data['name']))} {self.expr(int(data['type']))} "
                f"{self.expr(int(data['value']))} {self.expr(int(data['body']))}"
            )
        elif "lam" in obj:
            data = obj["lam"]
            self.emit(
                f"{dense} #EL {self.binder(data['binderInfo'])} {self.name(int(data['name']))} "
                f"{self.expr(int(data['type']))} {self.expr(int(data['body']))}"
            )
        elif "forallE" in obj:
            data = obj["forallE"]
            self.emit(
                f"{dense} #EP {self.binder(data['binderInfo'])} {self.name(int(data['name']))} "
                f"{self.expr(int(data['type']))} {self.expr(int(data['body']))}"
            )
        elif "proj" in obj:
            data = obj["proj"]
            self.emit(f"{dense} #EJ {self.name(int(data['typeName']))} {int(data['idx'])} {self.expr(int(data['struct']))}")
        elif "natVal" in obj:
            self.emit(f"{dense} #ELN {self.atom(obj['natVal'], 'natural literal')}")
        elif "strVal" in obj:
            payload = str(obj["strVal"]).encode("utf-8")
            bytes_hex = " ".join(f"{byte:02X}" for byte in payload)
            suffix = f" {bytes_hex}" if bytes_hex else ""
            self.emit(f"{dense} #ELS{suffix}")
        else:
            raise ConvertError(f"unknown expression object: {obj}")

    def convert_inductive(self, group: dict[str, Any]) -> None:
        ctors_by_induct: dict[int, list[dict[str, Any]]] = {}
        for ctor in group.get("ctors", []):
            ctors_by_induct.setdefault(int(ctor["induct"]), []).append(ctor)

        for ind in group.get("types", []):
            self.declare_name(int(ind["name"]), "inductive type")
        for ctor in group.get("ctors", []):
            self.declare_name(int(ctor["name"]), "constructor")
        for rec in group.get("recs", []):
            self.declare_name(int(rec["name"]), "recursor")

        for ind in group.get("types", []):
            ind_name = int(ind["name"])
            ctors = [*ctors_by_induct.get(ind_name, [])]
            if ind.get("ctors"):
                order = {int(name): i for i, name in enumerate(ind["ctors"])}
                ctors.sort(key=lambda ctor: order.get(int(ctor["name"]), int(ctor.get("cidx", 0))))
            parts = [
                "#IND",
                str(int(ind["numParams"])),
                str(self.name(ind_name)),
                str(self.expr(int(ind["type"]))),
                str(len(ctors)),
            ]
            for ctor in ctors:
                parts.extend([str(self.name(int(ctor["name"]))), str(self.expr(int(ctor["type"])))])
            parts.extend(self.level_params(ind))
            self.emit(" ".join(parts))

    def convert_theorem(self, decl: dict[str, Any]) -> None:
        self.convert_definition(decl)


def use_streaming_converter(src: Path) -> bool:
    mode = os.environ.get("ROCQLKA_NDJSON_STREAM", "auto").strip().lower()
    if mode in {"1", "true", "yes", "always", "on"}:
        return True
    if mode in {"0", "false", "no", "never", "off"}:
        return False
    if mode != "auto":
        raise ConvertError(f"unsupported ROCQLKA_NDJSON_STREAM value: {mode!r}")
    threshold = int(os.environ.get("ROCQLKA_NDJSON_STREAM_THRESHOLD", str(512 * 1024 * 1024)))
    return src.stat().st_size >= threshold


def convert_file(src: Path, dst: Path) -> None:
    with src.open("r", encoding="utf-8") as inp, dst.open("w", encoding="utf-8") as out:
        streaming = use_streaming_converter(src)
        if streaming:
            print("using streaming NDJSON conversion", file=sys.stderr)
        converter: Converter = StreamingConverter(out) if streaming else Converter(out)
        for line_no, line in enumerate(inp, 1):
            stripped = line.strip()
            if not stripped:
                continue
            try:
                obj = json.loads(stripped)
                if not isinstance(obj, dict):
                    raise ConvertError("top-level JSON value is not an object")
                converter.convert(obj)
            except RejectExport:
                raise
            except (json.JSONDecodeError, ConvertError, KeyError, TypeError, ValueError) as exc:
                raise ConvertError(f"{src}:{line_no}: {exc}") from exc


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: ndjson_to_lean_export.py INPUT.ndjson OUTPUT", file=sys.stderr)
        return 2
    try:
        convert_file(Path(argv[1]), Path(argv[2]))
    except RejectExport as exc:
        print(f"reject: {exc}", file=sys.stderr)
        return 10
    except ConvertError as exc:
        print(exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
