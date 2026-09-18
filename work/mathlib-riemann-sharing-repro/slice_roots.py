#!/usr/bin/env python3
"""Diagnostic dependency slice, with other theorem bodies replaced by assumptions."""
from array import array
from fnmatch import fnmatchcase
import json
import mmap
from pathlib import Path
import sys


def slice_export(source, destination, target, keep=(), *, stop_after_target=False, roots=()):
    keep = {target, *keep}
    tables = {kind: array("q") for kind in ("in", "il", "ie")}
    declarations = {}
    named_declarations = {}
    quotients = []
    with source.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
        def record(offset):
            return json.loads(data[offset:data.find(b"\n", offset)])

        def full_name(index):
            parts = []
            while index:
                obj = record(tables["in"][index])
                part = obj.get("str", obj.get("num"))
                parts.append(str(part.get("str", part.get("i"))))
                index = part["pre"]
            return ".".join(reversed(parts))

        target_offset = None
        while True:
            offset = data.tell()
            line = data.readline()
            if not line:
                break
            obj = json.loads(line)
            for kind, table in tables.items():
                if kind in obj:
                    index = obj[kind]
                    if index >= len(table):
                        table.extend([-1] * (index + 1 - len(table)))
                    if table[index] != -1:
                        raise ValueError("Duplicate index")
                    table[index] = offset
                    break
            else:
                if "meta" in obj:
                    continue
                kind, payload = next(iter(obj.items()))
                if kind == "inductive":
                    names = [v["name"] for key in ("types", "ctors", "recs") for v in payload[key]]
                else:
                    names = [payload["name"]]
                for name in names:
                    declarations[name] = offset
                    declaration_name = full_name(name)
                    named_declarations[declaration_name] = offset
                    if declaration_name == target:
                        target_offset = offset
                if kind == "quot":
                    quotients.append(offset)
                # A declaration's exported dependencies precede it. Focused
                # reproducers need not index the remainder of a large corpus.
                # Default remains the historical full-file scan.
                if stop_after_target and target_offset is not None:
                    break
        if target_offset is None:
            raise ValueError("Target not found")

        for via in sorted(pattern[4:] for pattern in keep if pattern.startswith("via:")):
            wanted = named_declarations[via]
            connected = {wanted: None}
            witnesses = array("q", [-1]) * len(tables["ie"])
            data.seek(0)
            while True:
                offset = data.tell()
                line = data.readline()
                if not line:
                    break
                obj = json.loads(line)
                refs = []
                if "ie" in obj:
                    if "const" in obj:
                        owner = declarations.get(obj["const"]["name"])
                        if owner in connected:
                            witnesses[obj["ie"]] = owner
                        continue
                    if "app" in obj:
                        refs = [obj["app"][key] for key in ("fn", "arg")]
                    elif "lam" in obj or "forallE" in obj or "letE" in obj:
                        payload = obj.get("lam", obj.get("forallE", obj.get("letE")))
                        refs = [payload[key] for key in ("body", "value", "type") if key in payload]
                    elif "proj" in obj:
                        refs = [obj["proj"]["struct"]]
                    elif "mdata" in obj:
                        refs = [obj["mdata"]["expr"]]
                elif "in" in obj or "il" in obj or "meta" in obj:
                    continue
                else:
                    kind, payload = next(iter(obj.items()))
                    if kind == "inductive":
                        for key in ("types", "ctors", "recs"):
                            for item in payload[key]:
                                refs.append(item["type"])
                                refs.extend(rule["rhs"] for rule in item.get("rules", []))
                    else:
                        refs = [payload[key] for key in ("value", "type") if key in payload]
                witness = next((witnesses[index] for index in refs if witnesses[index] >= 0), -1)
                if witness >= 0:
                    if "ie" in obj:
                        witnesses[obj["ie"]] = witness
                    elif offset != wanted:
                        connected[offset] = witness
            path = []
            offset = target_offset
            while offset is not None:
                kind, payload = next(iter(record(offset).items()))
                name_id = payload["types"][0]["name"] if kind == "inductive" else payload["name"]
                declaration_name = full_name(name_id)
                path.append(declaration_name)
                if kind == "thm":
                    keep.add(declaration_name)
                if offset not in connected:
                    raise ValueError(f"No dependency path from {declaration_name} to {via}")
                offset = connected[offset]
            print("Retaining proof path: " + " -> ".join(path), flush=True)
            del witnesses, connected

        selected = {0}
        pending = [target_offset, *(named_declarations[root] for root in roots)]
        replacements = {}

        def table_ref(kind, index):
            if not index and kind in ("in", "il"):
                return
            offset = tables[kind][index]
            if offset < 0:
                raise ValueError(f"Missing {kind} index {index}")
            pending.append(offset)

        def name(index):
            table_ref("in", index)

        def level(index):
            table_ref("il", index)

        def expr(index):
            table_ref("ie", index)

        def constant(index):
            name(index)
            if index not in declarations:
                raise ValueError("No declaration for " + full_name(index))
            pending.append(declarations[index])

        def common(payload):
            name(payload["name"])
            expr(payload["type"])
            for index in payload["levelParams"]:
                name(index)

        while pending:
            offset = pending.pop()
            if offset in selected:
                continue
            selected.add(offset)
            obj = record(offset)
            if "in" in obj:
                name(obj.get("str", obj.get("num"))["pre"])
            elif "il" in obj:
                if "succ" in obj:
                    level(obj["succ"])
                elif "param" in obj:
                    name(obj["param"])
                else:
                    for index in obj.get("max", obj.get("imax")):
                        level(index)
            elif "ie" in obj:
                if "sort" in obj:
                    level(obj["sort"])
                elif "const" in obj:
                    constant(obj["const"]["name"])
                    for index in obj["const"]["us"]:
                        level(index)
                elif "app" in obj:
                    expr(obj["app"]["fn"])
                    expr(obj["app"]["arg"])
                elif "lam" in obj or "forallE" in obj or "letE" in obj:
                    payload = obj.get("lam", obj.get("forallE", obj.get("letE")))
                    name(payload["name"])
                    expr(payload["type"])
                    expr(payload["body"])
                    if "value" in payload:
                        expr(payload["value"])
                elif "proj" in obj:
                    constant(obj["proj"]["typeName"])
                    expr(obj["proj"]["struct"])
                elif "mdata" in obj:
                    expr(obj["mdata"]["expr"])
                elif "natVal" in obj:
                    pending.append(named_declarations["Nat"])
                elif "strVal" in obj:
                    constructor = "String.ofList" if "String.ofList" in named_declarations else "String.mk"
                    pending.append(named_declarations[constructor])
            elif "inductive" in obj:
                for key in ("types", "ctors", "recs"):
                    for item in obj["inductive"][key]:
                        common(item)
                        for field in ("all", "ctors"):
                            for index in item.get(field, []):
                                name(index)
                        if "induct" in item:
                            name(item["induct"])
                        for rule in item.get("rules", []):
                            name(rule["ctor"])
                            expr(rule["rhs"])
            else:
                kind, payload = next(iter(obj.items()))
                common(payload)
                if kind == "quot":
                    pending.extend(quotients)
                elif kind == "thm" and not any(fnmatchcase(full_name(payload["name"]), pattern) for pattern in keep):
                    replacements[offset] = {"axiom": {
                        "name": payload["name"], "type": payload["type"],
                        "levelParams": payload["levelParams"], "isUnsafe": False}}
                else:
                    if "value" in payload:
                        expr(payload["value"])
                    for index in payload.get("all", []):
                        name(index)

        with destination.open("xb") as output:
            for offset in sorted(selected):
                if offset in replacements:
                    output.write(json.dumps(replacements[offset], separators=(",", ":")).encode() + b"\n")
                else:
                    output.write(data[offset:data.find(b"\n", offset) + 1])
        print(f"Selected {len(selected)} records; abstracted {len(replacements)} dependency proofs.")
        root_name_ids = {}
        for root in (target, *roots):
            obj = record(named_declarations[root])
            if "inductive" in obj:
                candidates = [item["name"] for key in ("types", "ctors", "recs")
                              for item in obj["inductive"][key]]
            else:
                candidates = [next(iter(obj.values()))["name"]]
            root_name_ids[root] = next(index for index in candidates if full_name(index) == root)
        return {"selected": len(selected), "abstracted": len(replacements),
                "root_name_ids": root_name_ids}



if __name__ == "__main__":
    slice_export(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], sys.argv[4:])
