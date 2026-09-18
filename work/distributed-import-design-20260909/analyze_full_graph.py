#!/usr/bin/env python3
"""Structural experiments on the entire pinned Arena certificate.

Uses the earlier offline Lean metadata only as a design dataset. Production
scheduling MUST extract its graph from the supplied certificate, without Lean.
This script loads our own locally generated pickle cache; never use arbitrary
untrusted pickle inputs. No compiler, proof checker, or subprocess is launched.
"""
from array import array
import gc
import hashlib
import json
from pathlib import Path
import pickle
import time

from scheduler_model import Model, Task, antichain_groups, coarsen

HERE = Path(__file__).resolve().parent
DATA = HERE.parent / 'cslib-module-overlap-20260909'


def log(message): print(time.strftime('%H:%M:%S'), message, flush=True)


def load_graph():
    with (DATA / 'parsed.pickle').open('rb') as f:
        signature, parsed = pickle.load(f)
    children, roots, weights, info = parsed
    source_stat = Path(info['path']).stat()
    with (DATA / 'metadata.jsonl').open('rb') as f:
        metadata_hash = hashlib.file_digest(f, 'sha256').hexdigest()
    assert signature == (source_stat.st_size, source_stat.st_mtime_ns, metadata_hash), \
        'input changed; regenerate the overlap analysis cache'
    assert info['importer_entries'] == sum(weights) == 253649
    assert len(roots) == info['named_constants'] == 262983
    del children, parsed
    n = len(weights)
    selected = bytearray(n)
    source_order = array('I', [n]) * n
    introduced = array('I', [0]) * n
    maximum = -1
    originals = list(roots)
    for order, (idx, exprs) in enumerate(roots.items()):
        selected[idx] = 1
        source_order[idx] = order
        end = max(exprs)
        introduced[idx] = max(0, end - maximum)
        maximum = max(maximum, end)
    assert maximum + 1 == info['counts']['expressions']
    assert sum(introduced) == maximum + 1
    del roots
    gc.collect()
    offsets = array('I', [0])
    edges = array('I')
    owners = array('i', [-1]) * n
    names = [''] * n
    unsafe = bytearray(n)
    omitted = set()
    with (DATA / 'metadata.jsonl').open() as f:
        header = json.loads(next(f))
        assert header['constants'] == n
        for i, line in enumerate(f):
            row = json.loads(line)
            unsafe[i] = row[3]
            if selected[i]:
                owners[i] = row[1]
                names[i] = row[6]
                for dep in row[5]:
                    if selected[dep]: edges.append(dep)
                    else: omitted.add(dep)
            offsets.append(len(edges))
    assert i + 1 == n
    assert all(unsafe[d] for d in omitted), 'unexpected missing safe dependency'
    log(f'graph: {len(originals):,} named constants, {len(edges):,} direct edges')
    return originals, weights, introduced, source_order, offsets, edges, owners, names, header, info, metadata_hash


def components(originals, offsets, edges, label='declaration'):
    """Iterative Kosaraju: cycles are condensed only for this offline model.

    A production importer may only accept the mutual constructs supported by
    its input format/kernel; arbitrary proof cycles must not be approved.
    """
    n = len(offsets) - 1
    seen = bytearray(n)
    finished = array('I')
    for root in originals:
        if seen[root]: continue
        seen[root] = 1
        stack = [(root, offsets[root])]
        while stack:
            v, pos = stack[-1]
            if pos < offsets[v + 1]:
                stack[-1] = (v, pos + 1)
                w = edges[pos]
                if not seen[w]:
                    seen[w] = 1
                    stack.append((w, offsets[w]))
            else:
                finished.append(v); stack.pop()
    counts = array('I', [0]) * n
    for w in edges: counts[w] += 1
    reverse_offsets = array('I', [0])
    for c in counts: reverse_offsets.append(reverse_offsets[-1] + c)
    reverse_edges = array('I', [0]) * len(edges)
    positions = reverse_offsets[:-1]
    for v in originals:
        for pos in range(offsets[v], offsets[v + 1]):
            w = edges[pos]
            reverse_edges[positions[w]] = v
            positions[w] += 1
    component = array('i', [-1]) * n
    sizes = []
    for root in reversed(finished):
        if component[root] >= 0: continue
        cid = len(sizes)
        component[root] = cid
        todo = [root]; size = 0
        while todo:
            v = todo.pop(); size += 1
            for pos in range(reverse_offsets[v], reverse_offsets[v + 1]):
                w = reverse_edges[pos]
                if component[w] < 0:
                    component[w] = cid; todo.append(w)
        sizes.append(size)
    assert sum(sizes) == len(originals)
    log(f'condensed {label} graph: {len(sizes):,} components; largest has {max(sizes)} nodes')
    return component, sizes


def main():
    originals, weights, introduced, order, offsets, edges, owners, names, header, info, metadata_hash = load_graph()
    component, sizes = components(originals, offsets, edges)
    n = len(sizes)
    deps = [set() for _ in sizes]
    entry_cost = [0] * n
    expression_cost = [0] * n
    first = [len(weights)] * n
    representative = [''] * n
    module_sets = [set() for _ in sizes]
    module_witnesses = {}
    for v in originals:
        cid = component[v]
        entry_cost[cid] += weights[v]
        expression_cost[cid] += weights[v] + introduced[v]
        module_sets[cid].add(owners[v])
        if order[v] < first[cid]:
            first[cid] = order[v]; representative[cid] = names[v]
        for pos in range(offsets[v], offsets[v + 1]):
            target = edges[pos]
            dep = component[target]
            if dep != cid: deps[cid].add(dep)
            if owners[v] != owners[target]:
                module_witnesses.setdefault((owners[v], owners[target]), (names[v], names[target]))
    assert all(len(m) == 1 for m in module_sets), 'a component spans source modules'
    modules = [next(iter(m)) for m in module_sets]
    del module_sets, originals, offsets, edges, order, owners, names, weights, introduced, component
    dependency_lists = [tuple(sorted(ds)) for ds in deps]
    del deps
    gc.collect()
    base = [Task(ds, entry_cost[i], order=first[i]) for i, ds in enumerate(dependency_lists)]
    atom_model = Model(base)
    policies = {'atomic_components': list(range(n))}
    # File ownership is a coarsening, not necessarily a valid compilation DAG.
    module_labels = sorted(set(modules))
    module_ids = {m: i for i, m in enumerate(module_labels)}
    module_deps = [set() for _ in module_labels]
    for i, ds in enumerate(dependency_lists):
        for dep in ds:
            if modules[i] != modules[dep]:
                module_deps[module_ids[modules[i]]].add(module_ids[modules[dep]])
    module_offsets = array('I', [0]); module_edges = array('I')
    for ds in module_deps:
        module_edges.extend(sorted(ds)); module_offsets.append(len(module_edges))
    module_components, module_sizes = components(
        range(len(module_labels)), module_offsets, module_edges, label='file ownership')
    cyclic_groups = []
    for cid, size in enumerate(module_sizes):
        if size <= 1: continue
        labels = {module_labels[i] for i, c in enumerate(module_components) if c == cid}
        cyclic_groups.append({
            'modules': [header['modules'][m] if m >= 0 else '<no source module>' for m in sorted(labels)],
            'witness_edges': [{'from': header['modules'][a], 'to': header['modules'][b],
                               'declaration': pair[0], 'requires': pair[1]}
                              for (a, b), pair in module_witnesses.items() if a in labels and b in labels]})
    if cyclic_groups:
        log(f'file ownership creates {len(cyclic_groups)} cyclic groups; merging those groups for comparison')
        policies['file_ownership_cycles_merged'] = [module_components[module_ids[m]] for m in modules]
    else:
        policies['file_ownership'] = modules
    del module_witnesses, module_deps, module_offsets, module_edges
    # The chronological policy uses exact dependencies, not a forced previous-chunk edge.
    policies['topological_chunks_256'] = [0] * n
    used = 256; group = -1
    for i in atom_model.topological:
        if used >= 256:
            group += 1; used = 0
        policies['topological_chunks_256'][i] = group
        used += base[i].cost
    for capacity in (32, 128, 512):
        policies[f'antichains_{capacity}'] = antichain_groups(atom_model, capacity)
    result = {'kind': 'offline structural simulation, not a Rocq speed benchmark',
        'input': info, 'named_constants': sum(sizes), 'atomic_components': n,
        'nontrivial_components': sum(s > 1 for s in sizes),
        'largest_component_constants': max(sizes),
        'zero_entry_components': sum(c == 0 for c in entry_cost),
        'source_modules_with_exported_constants': len(module_labels),
        'metadata_sha256': metadata_hash,
        'file_ownership_cycles': cyclic_groups,
        'timings_available': False, 'memory_model': 'one abstract unit per task; actual RSS not modeled',
        'cost_models': {}}
    for cost_label, costs in [('entry_count', entry_cost),
                              ('entry_plus_first_introduced_expression_nodes', expression_cost)]:
        atoms = [Task(ds, costs[i], order=first[i]) for i, ds in enumerate(dependency_lists)]
        rows = []
        for policy, labels in policies.items():
            tasks = atoms if policy == 'atomic_components' else coarsen(atoms, labels)
            model = Model(tasks)
            row = {'policy': policy, 'tasks': len(tasks), 'total_cost_units': model.total,
                'critical_path_cost_units': model.critical_path,
                'infinite_worker_speedup_bound': model.total / model.critical_path,
                'simulations': [model.simulate(p) for p in (2, 4, 8, 16)]}
            rows.append(row)
            log(f'{cost_label} / {policy}: {len(tasks):,} tasks; '
                f'4-worker model speedup {row["simulations"][1]["model_speedup"]:.3f}')
            del model
        result['cost_models'][cost_label] = rows
    (HERE / 'simulation.json').write_text(json.dumps(result, indent=2) + '\n')
    log('wrote simulation.json')


if __name__ == '__main__': main()
