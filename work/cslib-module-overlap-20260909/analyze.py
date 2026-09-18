#!/usr/bin/env python3
"""Measure per-file export overlap from actual compiled ownership and certificates.

No kernel checks are run. Counts describe syntax/declaration duplication, not CPU.
Metadata.lean follows lean4export's traversal, including bundled inductives,
recursors, opaque bodies, quotient primitives and implicit literal dependencies.
"""
import argparse
from array import array
from collections import Counter, defaultdict
import csv
import hashlib
import json
import pickle
from pathlib import Path
import statistics
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SOURCE = ROOT / '_deps/lean-kernel-arena/_build/tests/work/cslib/src'
EXPORT = ROOT / '_deps/lean-kernel-arena/_build/tests/cslib.ndjson'
NONE = 0xffffffff


def log(message):
    print(f'{time.strftime("%H:%M:%S")} {message}', flush=True)


def load_metadata():
    with (HERE / 'metadata.jsonl').open() as f:
        header = json.loads(next(f))
        records = [json.loads(line) for line in f]
    assert len(records) == header['constants']
    keys = {row[0]: i for i, row in enumerate(records)}
    assert len(keys) == len(records)
    log(f'metadata: {len(records):,} constants, {len(header["modules"]):,} modules')
    return header, records, keys


def scan_export(records, keys):
    names = ['']
    children = [array('I') for _ in range(3)]
    roots = {}
    weights = [0] * len(records)
    digest = hashlib.sha256()
    tags = Counter()

    def declaration(decl, kind):
        key = names[decl['name']]
        idx = keys[key]
        assert idx not in roots, ('duplicate', records[idx][6])
        assert kind == records[idx][2], (kind, records[idx][2], records[idx][6])
        assert not records[idx][3]
        es = [decl['type']]
        if 'value' in decl:
            es.append(decl['value'])
        es.extend(rule['rhs'] for rule in decl.get('rules', []))
        roots[idx] = es
        weights[idx] = int(kind not in ('ctor', 'rec', 'quot') or records[idx][6] == 'Quot')

    with EXPORT.open('rb') as f:
        for line_number, line in enumerate(f, 1):
            digest.update(line)
            obj = json.loads(line)
            if 'ie' in obj:
                idx = obj['ie']
                assert idx == len(children[0]), ('nondense expression index', idx)
                if 'app' in obj:
                    d = obj['app']; edges = [d['fn'], d['arg']]
                elif 'lam' in obj or 'forallE' in obj:
                    d = obj.get('lam', obj.get('forallE')); edges = [d['type'], d['body']]
                elif 'letE' in obj:
                    d = obj['letE']; edges = [d['type'], d['value'], d['body']]
                elif 'proj' in obj:
                    edges = [obj['proj']['struct']]
                elif 'mdata' in obj:
                    edges = [obj['mdata']['expr']]
                else:
                    assert any(k in obj for k in ('bvar', 'sort', 'const', 'natVal', 'strVal')), obj
                    edges = []
                assert all(0 <= child < idx for child in edges), ('non-DAG expression', idx, edges)
                for k, a in enumerate(children):
                    a.append(edges[k] if k < len(edges) else NONE)
                tags['expressions'] += 1
            elif 'in' in obj:
                idx = obj['in']
                assert idx == len(names)
                if 'str' in obj:
                    d = obj['str']; s = d['str']
                    key = names[d['pre']] + 's' + str(len(s.encode())) + ':' + s
                else:
                    d = obj['num']; key = names[d['pre']] + 'n' + str(d['i']) + ':'
                names.append(key)
                tags['names'] += 1
            elif 'il' in obj:
                tags['levels'] += 1
            elif 'meta' in obj:
                export_meta = obj['meta']
            elif 'inductive' in obj:
                d = obj['inductive']
                for field, kind in [('types', 'inductive'), ('ctors', 'ctor'), ('recs', 'rec')]:
                    for decl in d[field]:
                        declaration(decl, kind)
                        tags[kind] += 1
            else:
                assert len(obj) == 1, obj.keys()
                kind, decl = next(iter(obj.items()))
                assert kind in ('def', 'thm', 'opaque', 'axiom', 'quot'), kind
                declaration(decl, kind)
                tags[kind] += 1
            if line_number % 2000000 == 0:
                log(f'scanned {line_number:,} lines; {len(roots):,} declarations')
    assert sum(weights) == 253649, ('unexpected full-import entry count', sum(weights))
    log(f'export scanned: {len(roots):,} named constants; {sum(weights):,} importer entries')
    return children, roots, weights, {
        'path': str(EXPORT), 'sha256': digest.hexdigest(), 'lines': line_number,
        'counts': dict(tags), 'metadata': export_meta,
        'importer_entries': sum(weights), 'named_constants': len(roots),
    }


def closure(seeds, records):
    seen = set(seeds)
    todo = list(seen)
    while todo:
        idx = todo.pop()
        for dep in records[idx][5]:
            if not records[dep][3] and dep not in seen:
                seen.add(dep)
                todo.append(dep)
    return seen


def make_groups(header, records, exported, weights):
    modules = header['modules']
    by_module = defaultdict(list)
    for idx in exported:
        mid = records[idx][1]
        assert mid is not None, ('missing module owner', records[idx][6])
        by_module[modules[mid]].append(idx)
    source_modules = sorted('Cslib.' + '.'.join(p.relative_to(SOURCE / 'Cslib').with_suffix('').parts)
                            for p in (SOURCE / 'Cslib').rglob('*.lean'))
    assert set(source_modules) <= set(modules), 'some source modules are not in the full Cslib environment'
    groups = []
    masks = [0] * len(records)

    def add_group(scenario, module, seeds):
        reach = closure(seeds, records)
        missing = reach - exported
        assert not missing, ('dependencies absent from certificate', module,
                             [records[i][6] for i in sorted(missing)[:20]])
        bit = 1 << len(groups)
        for idx in reach:
            masks[idx] |= bit
        own = sum(weights[i] for i in by_module.get(module, []))
        groups.append({'scenario': scenario, 'module': module, 'own_entries': own,
                       'root_constants': len(seeds), 'reachable_constants': len(reach),
                       'entries': sum(weights[i] for i in reach),
                       'cslib_entries': sum(weights[i] for i in reach
                          if modules[records[i][1]].startswith('Cslib.')),
                       'kind_counts': dict(Counter(records[i][2] for i in reach if weights[i]))})
        if len(groups) % 10 == 0:
            log(f'computed {len(groups)} groups ({scenario})')

    # Include every exported declaration owned by each source file, including helpers.
    for module in source_modules:
        if by_module[module]:
            add_group('owned_declarations', module, by_module[module])
    owned_mask = (1 << len(groups)) - 1
    not_covered = [i for i in exported if not masks[i]]
    if not_covered:
        add_group('remainder_for_full_coverage', '(remaining full-export declarations)', not_covered)

    # Model ordinary lean4export Module: all non-internal environment declarations.
    imports = dict(json.loads((HERE / 'modules.json').read_text()))
    def ancestors(module):
        seen = {module}; todo = [module]
        while todo:
            for parent in imports[todo.pop()]:
                if parent not in seen:
                    seen.add(parent); todo.append(parent)
        return seen
    for module in source_modules:
        if by_module[module]:
            seeds = [i for parent in ancestors(module) for i in by_module[parent]
                     if not records[i][4]]
            add_group('whole_module_environment', module, seeds)
    return groups, masks, {
        'source_files': len(source_modules),
        'files_with_exported_declarations': sum(bool(by_module[m]) for m in source_modules),
        'files_without_exported_declarations': [m for m in source_modules if not by_module[m]],
        'own_cslib_entries': sum(weights[i] for m in source_modules for i in by_module[m]),
        'owned_group_mask': owned_mask,
    }


def count_expressions(children, roots, decl_masks):
    masks = [0] * len(children[0])
    for idx, exprs in roots.items():
        mask = decl_masks[idx]
        for e in exprs:
            masks[e] |= mask
    histogram = Counter()
    a, b, c = children
    for idx in range(len(masks) - 1, -1, -1):
        mask = masks[idx]
        histogram[mask] += 1
        if mask:
            if a[idx] != NONE: masks[a[idx]] |= mask
            if b[idx] != NONE: masks[b[idx]] |= mask
            if c[idx] != NONE: masks[c[idx]] |= mask
        if idx % 2000000 == 0:
            log(f'expression propagation: {idx:,} nodes remaining')
    return histogram


def summarize(groups, entry_hist, expr_hist, full_entries):
    for i, group in enumerate(groups):
        bit = 1 << i
        group['expression_nodes'] = sum(n for mask, n in expr_hist.items() if mask & bit)
        assert group['entries'] == sum(n for mask, n in entry_hist.items() if mask & bit)
    result = {}
    cases = {
        'owned_declarations': {'owned_declarations'},
        'owned_plus_full_remainder': {'owned_declarations', 'remainder_for_full_coverage'},
        'whole_module_environment': {'whole_module_environment'},
    }
    for case, scenarios in cases.items():
        chosen = [i for i, g in enumerate(groups) if g['scenario'] in scenarios]
        selector = sum(1 << i for i in chosen)
        metrics = {'groups': len(chosen)}
        for label, hist in [('entries', entry_hist), ('expression_nodes', expr_hist)]:
            multiplicities = Counter()
            for mask, n in hist.items():
                copies = (mask & selector).bit_count()
                if copies: multiplicities[copies] += n
            unique = sum(multiplicities.values())
            total = sum(k * v for k, v in multiplicities.items())
            metrics[label] = {'unique': unique, 'sum_across_groups': total,
                'extra_copies': total - unique, 'duplication_factor': total / unique,
                'duplicate_share': (total - unique) / total,
                'multiplicity_histogram': dict(sorted(multiplicities.items()))}
        sizes = [groups[i]['entries'] for i in chosen]
        metrics['entries_per_group'] = {'min': min(sizes), 'median': statistics.median(sizes),
                                      'max': max(sizes)}
        metrics['covers_full_import_entries'] = metrics['entries']['unique'] == full_entries
        result[case] = metrics
    return result


def main():
    header, records, keys = load_metadata()
    cache = HERE / 'parsed.pickle'
    signature = (EXPORT.stat().st_size, EXPORT.stat().st_mtime_ns,
                 hashlib.sha256((HERE / 'metadata.jsonl').read_bytes()).hexdigest())
    if cache.exists():
        with cache.open('rb') as f:
            saved_signature, parsed = pickle.load(f)
        assert saved_signature == signature, 'input changed; remove the local parsed cache'
        children, roots, weights, export_info = parsed
        log('loaded local parsed certificate cache')
    else:
        children, roots, weights, export_info = scan_export(records, keys)
        with cache.open('wb') as f:
            pickle.dump((signature, (children, roots, weights, export_info)), f, protocol=5)
    groups, masks, source_info = make_groups(header, records, set(roots), weights)
    entry_hist = Counter()
    for idx in roots:
        if weights[idx]: entry_hist[masks[idx]] += 1
    # Save declaration-only results before the more expensive expression pass.
    (HERE / 'groups.declarations.json').write_text(json.dumps(groups, indent=2) + '\n')
    expr_hist = count_expressions(children, roots, masks)
    results = summarize(groups, entry_hist, expr_hist, sum(weights))
    summary = {'export': export_info, 'source': source_info, 'scenarios': results}
    (HERE / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    (HERE / 'groups.json').write_text(json.dumps(groups, indent=2) + '\n')
    with (HERE / 'groups.csv').open('w') as out:
        fields = ['scenario', 'module', 'own_entries', 'root_constants', 'reachable_constants',
                  'entries', 'cslib_entries', 'expression_nodes']
        writer = csv.DictWriter(out, fieldnames=fields, extrasaction='ignore')
        writer.writeheader(); writer.writerows(groups)
    log(json.dumps({k: {m: v[m] for m in ('groups', 'entries', 'expression_nodes', 'entries_per_group')}
                    for k, v in results.items()}, indent=2))


if __name__ == '__main__':
    main()
