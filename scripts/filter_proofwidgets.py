#!/usr/bin/env python3
"""Audit UI exclusions against every original type/proof; retain IDs and lines.

Only declaration records are replaced by blank lines (a parser no-op). Names,
levels, expression nodes, retained declarations and proofs remain byte-identical.
This deliberately does not remove shared support definitions. A dependency from
any retained declaration to an excluded declaration aborts publication.
"""
import argparse
from array import array
from collections import Counter
import hashlib
import json
from pathlib import Path
import os
import time

KINDS = ('axiom', 'def', 'thm', 'opaque', 'quot', 'inductive')


def save(path, obj):
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(obj, indent=2) + '\n')
    os.replace(tmp, path)


def named_members(kind, payload):
    return ([v for key in ('types', 'ctors', 'recs') for v in payload[key]]
            if kind == 'inductive' else [payload])


def references(obj):
    """Expression IDs referenced by a node or declaration, including rec rules."""
    if 'ie' in obj:
        if 'app' in obj: return [obj['app']['fn'], obj['app']['arg']]
        for k in ('lam', 'forallE', 'letE'):
            if k in obj: return [obj[k][x] for x in ('type','value','body') if x in obj[k]]
        if 'proj' in obj: return [obj['proj']['struct']]
        if 'mdata' in obj: return [obj['mdata']['expr']]
        if any(k in obj for k in ('bvar','sort','const','natVal','strVal')): return []
        raise ValueError('Unknown expression: '+str(obj)[:200])
    kind = next(k for k in KINDS if k in obj)
    return [e for v in named_members(kind, obj[kind]) for e in
            ([v[x] for x in ('type','value') if x in v] +
             [r['rhs'] for r in v.get('rules', [])])]


def filter_export(source, candidates, output, preserve_through=0):
    rows = [json.loads(s) for s in candidates.read_text().splitlines()]
    eligible = {'.'.join(r['parts']): r for r in rows}
    names = ['']; ui_ids = set(); witness = array('I')
    dropped = []; inherited = []; conflicts = []; counts = Counter()
    input_hash = hashlib.sha256(); output_hash = hashlib.sha256()
    prefix_hash = hashlib.sha256()
    started = time.monotonic(); total = 0
    partial = output.with_suffix('.partial')
    if output.exists() or partial.exists(): raise ValueError('Output already exists')
    with source.open('rb') as inp, partial.open('xb') as out:
        for total, raw in enumerate(inp, 1):
            input_hash.update(raw); replacement = raw
            obj = json.loads(raw)
            if 'in' in obj:
                part = obj.get('str', obj.get('num'))
                name = names[part['pre']]
                name = (name+'.' if name else '')+str(part.get('str',part.get('i')))
                idx = obj['in']
                if idx != len(names): raise ValueError('Non-dense name IDs')
                names.append(name)
                if name in eligible: ui_ids.add(idx)
            elif 'ie' in obj:
                idx = obj['ie']
                if idx != len(witness): raise ValueError('Non-dense expression IDs')
                refname = obj.get('const',{}).get('name', obj.get('proj',{}).get('typeName'))
                w = refname if refname in ui_ids else 0
                for e in references(obj):
                    if e >= idx: raise ValueError('Forward expression reference')
                    if not w: w = witness[e]
                witness.append(w)
            elif 'il' in obj or 'meta' in obj:
                pass
            else:
                kind = next(k for k in KINDS if k in obj)
                members = named_members(kind,obj[kind]); ids = [v['name'] for v in members]
                selected = [i in ui_ids for i in ids]
                counts[kind] += 1
                if any(selected) and not all(selected):
                    raise ValueError('Mixed UI/non-UI inductive block')
                if all(selected):
                    row = dict(line=total, kind=kind, names=[names[i] for i in ids],
                               modules=sorted({eligible[names[i]]['module'] for i in ids}),
                               original_sha256=hashlib.sha256(raw).hexdigest())
                    if total <= preserve_through: inherited.append(row)
                    else: dropped.append(row); replacement = b'\n'
                else:
                    touched = {witness[e] for e in references(obj)} - {0}
                    # Group membership is significant even without an expression edge.
                    for v in members:
                        touched.update(i for i in v.get('all',[]) if i in ui_ids)
                        if v.get('induct') in ui_ids: touched.add(v['induct'])
                    if touched:
                        conflicts.append(dict(line=total, names=[names[i] for i in ids],
                                              excluded_dependencies=[names[i] for i in sorted(touched)]))
            if total <= preserve_through:
                if replacement != raw: raise ValueError('Checkpoint prefix changed')
                prefix_hash.update(raw)
            out.write(replacement); output_hash.update(replacement)
            if total % 1_000_000 == 0:
                save(output.parent/'filter-status.json',dict(phase='auditing',record=total,
                     excluded_records=len(dropped),cross_boundary=len(conflicts),
                     seconds=round(time.monotonic()-started,1)))
    record = dict(format='mathlib-ui-scope-v1',source=str(source),source_sha256=input_hash.hexdigest(),
                  export=str(output),export_sha256=output_hash.hexdigest(),records=total,
                  preserve_through=preserve_through,excluded=dropped,inherited_ui=inherited,
                  identical_prefix_sha256=prefix_hash.hexdigest(),
                  conflicts=conflicts,counts=counts,seconds=time.monotonic()-started,
                  candidates_sha256=hashlib.sha256(candidates.read_bytes()).hexdigest(),
                  candidate_source=str(candidates),line_numbers_preserved=True,
                  retained_records_byte_identical=True,proofs_abstracted=0,
                  full_original_export_pass=False)
    save(output.parent/'scope-audit.json',record)
    if conflicts: raise ValueError(f'{len(conflicts)} retained declarations reference UI; see scope-audit.json')
    os.replace(partial,output)
    save(output.parent/'filter-status.json',dict(phase='complete',record=total,
         excluded_records=len(dropped),inherited_ui_records=len(inherited),seconds=record['seconds']))
    return record


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',type=Path,required=True)
    p.add_argument('--candidates',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--preserve-through',type=int,default=0)
    a=p.parse_args()
    filter_export(a.source.resolve(),a.candidates.resolve(),a.output.resolve(),a.preserve_through)
