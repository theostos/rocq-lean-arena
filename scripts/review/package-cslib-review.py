"""Construct review refs through temporary Git indices; never edit live trees."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path('/home/theo/Documents/github/rocq-lean-typechecker')

def run(args, *, cwd=None, data=None, env=None):
    return subprocess.check_output(args, cwd=cwd, input=data, env=env)

def replace(text, old, new):
    assert text.count(old) == 1, (old[:140], text.count(old))
    return text.replace(old, new, 1)

def between(text, start, end):
    a = text.index(start)
    return text[a:text.index(end, a)]

def region(text, start, end, replacement):
    return replace(text, between(text, start, end), replacement)

class Repo:
    def __init__(self, path, new_paths):
        self.path = ROOT / path
        self.base = self.git('rev-parse', 'HEAD').strip().decode()
        self.original_status = self.git('status', '--porcelain=v1', '-uno')
        self.names = self.git('diff', '--name-only', 'HEAD').decode().splitlines()
        self.names += new_paths
        self.base_files = {p: self.read(self.base, p) for p in self.names}
        self.final = {p: (self.path / p).read_bytes() if (self.path / p).exists() else None
                      for p in self.names}
        self.steps = []
        self.head = self.base
        self.snapshot = self.commit('snapshot/cslib-20260907', self.final,
                                    'Snapshot the cslib experimental sources', parent=self.base)
        self.head = self.base
        self.files = dict(self.base_files)

    def git(self, *args, data=None, env=None):
        return run(['git', *args], cwd=self.path, data=data, env=env)

    def read(self, ref, path):
        result = subprocess.run(['git', 'show', f'{ref}:{path}'], cwd=self.path,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        return result.stdout if result.returncode == 0 else None

    def text(self, path, final=True):
        return (self.final if final else self.base_files)[path].decode()

    def take(self, *paths):
        for p in paths:
            self.files[p] = self.final[p]

    def put(self, path, text):
        self.files[path] = text.encode()

    def commit(self, branch, files, message, *, parent=None):
        parent = parent or self.head
        ref = 'refs/heads/' + branch
        with tempfile.TemporaryDirectory(prefix='cslib-review-index-') as scratch:
            env = dict(os.environ, GIT_INDEX_FILE=str(Path(scratch) / 'index'))
            self.git('read-tree', parent, env=env)
            for p, content in files.items():
                if content is None:
                    self.git('update-index', '--force-remove', '--', p, env=env)
                else:
                    oid = self.git('hash-object', '-w', '--stdin', data=content).strip().decode()
                    mode = '100755' if (self.path / p).exists() and os.access(self.path / p, os.X_OK) else '100644'
                    self.git('update-index', '--add', '--cacheinfo', f'{mode},{oid},{p}', env=env)
            tree = self.git('write-tree', env=env).strip().decode()
            # Reruns may only reuse exactly the same tree and parent.
            found = subprocess.run(['git', 'rev-parse', '--verify', ref], cwd=self.path,
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            if found.returncode == 0:
                oid = found.stdout.strip().decode()
                if (self.git('rev-parse', oid + '^{tree}').strip().decode() == tree and
                    self.git('rev-parse', oid + '^').strip().decode() == parent):
                    return oid
                assert os.environ.get('CSLIB_REVIEW_RECUT') == '1' and branch.startswith('review/'), branch
                assert self.git('show', '-s', '--format=%s', oid).decode().strip() == message, branch
                assert f'branch {ref}\n' not in self.git('worktree', 'list', '--porcelain').decode(), branch
                new = self.git('commit-tree', tree, '-p', parent, '-m', message).strip().decode()
                self.git('update-ref', ref, new, oid)
                return new
            oid = self.git('commit-tree', tree, '-p', parent, '-m', message).strip().decode()
            self.git('update-ref', ref, oid, '0' * 40)
            return oid

    def step(self, topic, title, body, tests='Not rebuilt at this split head. Earlier checks cover the combined experimental sources, not this intermediate branch.'):
        branch = 'review/' + topic
        base = self.steps[-1]['branch'] if self.steps else self.base
        doc = f'# {title}\n\nBase: `{base}`. Compare against this base, not upstream.\n\n{body}\n\n## Validation\n\n{tests}\n\nThis is an experimental review branch, not a claim of a complete cslib check.\n'
        self.files['REVIEW.md'] = doc.encode()
        oid = self.commit(branch, self.files, title)
        self.steps.append(dict(branch=branch, base=base, commit=oid, title=title))
        self.head = oid
        print(json.dumps(self.steps[-1]), flush=True)

    def hunks(self, path, predicate):
        """Apply selected original-to-snapshot zero-context hunks to original bytes."""
        diff = self.git('diff', '--no-ext-diff', '--unified=0', self.base, self.snapshot, '--', path).decode()
        lines = self.text(path, final=False).splitlines(keepends=True)
        edits = []
        for match in re.finditer(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@[^\n]*\n', diff, re.M):
            start, count = int(match[1]), int(match[2] or 1)
            end = diff.find('\n@@ ', match.end())
            body = diff[match.end():end if end != -1 else len(diff)]
            if predicate(start, count, body):
                old = [l[1:] for l in body.splitlines(keepends=True) if l.startswith('-')]
                new = [l[1:] for l in body.splitlines(keepends=True) if l.startswith('+')]
                # A boundary located before the newline must retain that newline.
                if new and not new[-1].endswith('\n'): new[-1] += '\n'
                if old and not old[-1].endswith('\n'): old[-1] += '\n'
                index = start - 1 if count else start
                assert lines[index:index+count] == old, (path, start)
                edits.append((index, count, new))
        for index, count, new in reversed(edits):
            lines[index:index+count] = new
        return ''.join(lines)

    def verify(self):
        for path, data in self.final.items():
            assert self.read(self.head, path) == data, ('not restored', path)
            live = (self.path / path).read_bytes() if (self.path / path).exists() else None
            assert live == data, ('live source changed', path)
        assert self.git('status', '--porcelain=v1', '-uno') == self.original_status
        print(json.dumps({'repo': str(self.path), 'snapshot': self.snapshot,
                          'source_equivalence': True, 'live_worktree_unchanged': True}), flush=True)

def kernel():
    r = Repo('_worktrees/rocq/compact-peano-view', [
        'test-suite/success/compact_peano.v', 'test-suite/success/unit_like_projection.v',
        'test-suite/unit-tests/kernel/constant_deps.ml',
        'test-suite/unit-tests/kernel/closure_inspection.ml'])
    r.take('kernel/environ.ml', 'test-suite/unit-tests/kernel/constant_deps.ml')
    r.step('dependency-cache', 'Bound dependency-query storage',
           'Cache direct definition edges and bounded reachability answers instead of transitive closures. Scan shared bodies once per physical node. This addresses dependency-cache growth during the cslib import; optional scalar diagnostics remain with the cache.')
    r.take('kernel/hConstr.ml', 'kernel/vars.ml')
    r.step('term-sharing', 'Preserve DAG sharing during kernel term traversals',
           'Memoize hash-consing and universe traversals by physical term and, where needed, binder context. Large imported proof DAGs otherwise repeat the same traversal. These are traversal changes, not additional conversion equations.')
    registry = ['checker/mod_checking.ml', 'checker/values.ml', 'kernel/mod_subst.ml',
                'kernel/primred.ml', 'kernel/primred.mli', 'kernel/retroknowledge.ml',
                'kernel/retroknowledge.mli', 'kernel/safe_typing.mli',
                'library/global.ml', 'library/global.mli', 'vernac/vernacentries.ml']
    r.take(*registry)
    r.put('kernel/safe_typing.ml', r.hunks('kernel/safe_typing.ml', lambda n, *_: n >= 1924))
    r.step('reduction-registrations', 'Validate and persist experimental reduction registrations',
           'Add checked registrations for Peano naturals, arithmetic operations and unit-like inductives. Validate operation equations with compact arithmetic disabled, and carry registrations through modules and the checker. This is the registration layer; the following branches implement the evaluator and unit conversion. Unit eta changes definitional equality and needs separate soundness review.')
    r.take('kernel/cClosure.ml', 'kernel/cClosure.mli', 'kernel/inferCumulativity.ml',
           'test-suite/unit-tests/kernel/closure_inspection.ml')
    compact_conversion = r.hunks('kernel/conversion.ml', lambda n, *_: n in (307, 654))
    r.put('kernel/conversion.ml', compact_conversion)
    r.put('test-suite/success/compact_peano.v',
          region(r.text('test-suite/success/compact_peano.v'),
                 'Inductive EtaUnit@', 'Inductive BadNat', ''))
    r.step('compact-peano', 'Evaluate registered Peano arithmetic using compact closures',
           'Keep large Peano values compact inside reduction and expose zero/successor only when elimination needs it. Includes a read-only substitution inspection used to recognize eligible closed operations without copying or reducing their arguments. Motivating imports include Int32.toInt_lt and Int32.ofInt_tdiv. No new source-term constructor is added; the registered definitions remain the specification. Arithmetic/registration controls are in compact_peano.v; closure_inspection.ml tests the read-only substitution view.')
    final = r.text('kernel/conversion.ml')
    unit = compact_conversion
    unit = replace(unit, '  cnv_typ : bool; (* true if the input terms were well-typed *)\n',
                   '  cnv_typ : bool; (* true if the input terms were well-typed *)\n  cnv_rel_types : fconstr option Range.t;\n')
    unit = region(unit, 'let push_relevance infos r =', 'let identity_of_ctx',
                  between(final, 'let rec direct_inductive typ =', 'let constructor_relevance_mask') +
                  between(final, 'let rel_type infos n =', 'let identity_of_ctx'))
    helpers = (between(final, 'let is_registered_unit_like env ind =',
                       'let matches_registered_compact_peano_operation') +
               between(final, 'let flex_result_inductive', 'let diagnostic_conversion_calls'))
    unit = replace(unit, 'let rec ccnv cv_pb', helpers + 'let rec ccnv cv_pb')
    rel = between(final, '    | (FRel n, FRel m) ->', '    (* 2 constants,')
    rel = region(rel, '        let trace_rel stage =', '        let original_n', '')
    rel = re.sub(r'^\s*let \(\) = trace_rel [^\n]*\n', '', rel, flags=re.M)
    unit = region(unit, '    | (FRel n, FRel m) ->', '    (* 2 constants,', rel)
    unit = replace(unit,
        '       with NotConvertible | NotConvertibleTrace _ ->\n        let r1 =',
        '       with NotConvertible | NotConvertibleTrace _ ->\n        if same_unit_like_flexes infos lft1 v1 fl1 lft2 v2 fl2 then cuniv\n        else\n        let r1 =')
    unit = replace(unit, '    | (FProj (p1,r1,c1), FProj (p2, r2, c2)) ->',
                   between(final, '    | (FProj (p1, r1, c1), FConstruct',
                           '    | (FProj (p1,r1,c1), FProj (p2, r2, c2)) ->') +
                   '    | (FProj (p1,r1,c1), FProj (p2, r2, c2)) ->')
    unit = region(unit, '    (* only one constant, defined var or defined rel *)',
                  '    (* Inductive types:',
                  between(final, '    (* only one constant, defined var or defined rel *)',
                          '    (* Inductive types:'))
    unit = region(unit, '    (* Eta expansion of records *)', '    | (FFix',
                  between(final, '    (* Eta expansion of records *)', '    | (FFix'))
    # Carry binder types alongside their relevance for neutral unit eta.
    for old, new in [
        ('let infos = push_relevance infos na1 in', 'let infos = push_relevance ~typ:(Some ty1) infos na1 in'),
        ('let infos = push_relevance infos x1 in', 'let infos = push_relevance ~typ:(Some ty1) infos x1 in'),
        ('let infos = push_relevance infos x2 in', 'let infos = push_relevance ~typ:(Some ty2) infos x2 in')]:
        unit = unit.replace(old, new)
    unit = unit.replace('cnv_typ = typed;', 'cnv_typ = typed; cnv_rel_types = Range.empty;')
    unit = unit.replace('cnv_typ = true;', 'cnv_typ = true; cnv_rel_types = Range.empty;')
    unit = replace(unit, 'ccnv CONV l2r (push_relevance infos x1)',
                   'ccnv CONV l2r (push_relevance ~typ:(Some ty1) infos x1)')
    unit = replace(unit, 'ccnv cv_pb l2r (push_relevance infos x1)',
                   'ccnv cv_pb l2r (push_relevance ~typ:(Some c1) infos x1)')
    unit = unit.replace('(x1,_ty1,bd1)', '(x1,ty1,bd1)')
    unit = unit.replace('(x2,_ty2,bd2)', '(x2,ty2,bd2)')
    r.put('kernel/conversion.ml', unit)
    r.take('pretyping/inductiveops.ml', 'tactics/indrec.ml',
           'test-suite/success/compact_peano.v', 'test-suite/success/unit_like_projection.v')
    r.step('unit-eta', 'Support conversion for registered unit-like inductives',
           'Recognize neutral inhabitants of registered unindexed single-constructor types without runtime-relevant fields, including supported unit-valued projections. This addresses FinLoop totality and LawfulMonadStateOf.modify_eq. Projection parameter substitution stays lazy: reifying an erased proof parameter caused the LinearMap.exists_ne_zero_of_sSup_eq assertion. Dependent projection types are conservatively excluded from the unit query. This is a change to definitional equality, not merely an unfolding heuristic.')
    r.take('kernel/conversion.ml')
    r.step('conversion-strategies', 'Guide conversion through dependencies and shared projections',
           'Prefer useful dependency/constructor unfolding, try projection congruence, respect constructor-field relevance and memoize successful typed comparisons with their lift/context. Motivating imports include Int32.toBitVec_not, Std.DHashMap.Internal.Raw₀.Const.insertManyIfNewUnit_cons and Lean.Widget.MsgEmbed._sizeOf_2_eq. Includes the experimental strategy switches and tracing embedded in conversion; these still need cleanup and kernel-expert review. The unit-eta rules are in the base branch.')
    r.take(*r.names)
    r.step('kernel-diagnostics', 'Preserve the remaining kernel experiment diagnostics',
           'Reproduce the exact experimental source snapshot, including opt-in type/error traces and the ROCQ_DIAGNOSTIC_IGNORE_VO_DIGEST escape hatch. The digest bypass is diagnostic-only and must not be enabled for a checking result or proposed as a production fix. This branch is for reproducing the experiment, not an upstream PR.')
    r.verify()
    return r

def importer():
    fixtures = ['dependent_sprop_projection', 'nested_below', 'nested_mixed_fields',
                'nested_record_tree_cases', 'nullary_unit_scheme']
    r = Repo('_worktrees/rocq-lean-import/compact-peano-importer-current',
             [p for name in fixtures for p in
              (f'dumps/{name}', f'dumps/{name}.lean', f'tests/{name}.v')])
    final = r.text('src/lean.ml')
    selected = set()
    features = set()

    def select(start, end=None):
        selected.update(range(start, (end if end is not None else start) + 1))

    def add_fixture(name):
        r.take(f'dumps/{name}', f'dumps/{name}.lean', f'tests/{name}.v')
        project = r.files['tests/_CoqProject'].decode()
        r.put('tests/_CoqProject', project + f'{name}.v\n')

    def clean_declaration():
        d = between(final, 'and declare_def {', 'and declare_ax {')
        d = region(d, '  let diagnostic_selected key =',
                   '  let ref, algs, delay_power_unfolding =', '')
        d = region(d, '      let () =\n        if diagnostic_selected "LEAN_IMPORT_DUMP_LEAN_AST"',
                   '      let uconv, body = to_constr', '')
        d = region(d, '      let () =\n        if diagnostic_selected "LEAN_IMPORT_DUMP_ROCQ_AST"',
                   '      let univs, algs = univ_entry', '')
        d = region(d, '      let () =\n        if Option.has_some (Sys.getenv_opt "LEAN_IMPORT_DUMP_INFERRED_TYPE")',
                   '      let ref =', '')
        d = region(d, '      let ref =', '      (ref, algs, false)',
                   '      let ref =\n        quickdef ~opaque:kernel_opaque ~name:(name_for n i)\n          ~types:(Some ty) ~univs body\n      in\n')
        d = re.sub(r'^\s*let \(\) = trace_declaration(?:_stage)? [^\n]*\n', '', d, flags=re.M)
        if 'modern' not in features:
            d = replace(d, '           | Nat_isValidChar\n           | UInt32_toNat\n           | UInt32_isValidChar ) as predeclared)',
                        '           | Nat_isValidChar ) as predeclared)')
        if 'hints' not in features:
            d = replace(d, '; hint; kernel_opaque }', '; }')
            d = replace(d, 'quickdef ~opaque:kernel_opaque', 'quickdef')
            legacy = between(d, '    | LegacyHint ->\n', '  in\n  let () = add_declared')
            d = region(d, '    if kernel_opaque then ()', '  in\n  let () = add_declared',
                       legacy.removeprefix('    | LegacyHint ->\n'))
        return d

    def render():
        s = r.hunks('src/lean.ml', lambda n, *_: n in selected)
        if 'owners' in features:
            s = replace(s, '    entries := entriesv;\n',
                '    entries := entriesv;\n    constructor_owners := N.Map.fold\n      (fun _ entry owners -> match entry with\n        | Ind ind -> index_constructors ind owners\n        | Def _ | Ax _ | Quot _ -> owners)\n      entriesv N.Map.empty;\n')
        if 'compact' in features:
            s = region(s, 'let unfold_head_once env term =', 'let rec to_constr =', '')
            s = replace(s,
                '        to_constr env b_expr >>= fun b ->\n        get_uconv >>= fun uconv ->\n        let b =\n          with_env_evm env uconv\n            (fun env evd () -> maybe_transport_application env evd a b)\n            ()\n        in\n',
                '        to_constr env b_expr >>= fun b ->\n')
            s = region(s, 'and declare_def {', 'and declare_ax {', clean_declaration())
        if 'hints' in features:
            s = region(s, 'let quickdef ', 'type extended_level',
                       between(final, 'let quickdef ', 'type extended_level'))
        if 'unit' in features:
            register = between(final, 'let register_existing_unit_like () =', 'let import ~from ~until f =')
            s = replace(s, 'let import ~from ~until f =\n',
                        register + 'let import ~from ~until f =\n  register_existing_unit_like ();\n')
        if 'cache' in features:
            s = region(s, 'let rec to_constr =', 'and instantiate ',
                       between(final, 'let intern_translation_declaration', 'and instantiate '))
        if 'checkpoint' in features:
            s = s[:s.index('let pstate = Summary.ref')] + final[final.index('let pstate = Summary.ref'):]
        r.put('src/lean.ml', s)

    select(4500, 4619)
    selected.discard(4600)  # optional exception tracing belongs to the snapshot tail
    render()
    r.step('strict-import-errors', 'Report stopped imports and enforce declaration timeouts',
           'Do not print Done after stopping on an error; fail mode propagates the failure. Apply the line timeout to deferred declarations as well as parsing. This addresses the partial cslib runs that appeared successful after stopping near Lean.Meta.DiscrTree.Trie.casesOn.')

    features.add('owners')
    for n in (1044, 3495, 4469, 4474): select(n)
    render()
    r.files['dumps/constructor_owner.lean'] = (ROOT / 'work/cslib-v2/constructor-owner-repro/ConstructorOwner.lean').read_bytes()
    r.files['dumps/constructor_owner'] = (ROOT / 'work/cslib-v2/constructor-owner-repro/ConstructorOwner.lean-export').read_bytes()
    r.put('tests/constructor_owner.v', 'From LeanImport Require Import Lean.\nSet Lean Error Mode "Fail".\nLean Import "../dumps/constructor_owner".\nCheck repro : Token.\nFail Check (repro : Nat).\n')
    r.put('tests/_CoqProject', r.files['tests/_CoqProject'].decode() + 'constructor_owner.v\n')
    r.step('constructor-owners', 'Instantiate an inductive before a requested constructor',
           'Index constructors by their owning Lean inductive and rebuild the index when loading a checkpoint. Box.mk can be requested before the matching Box universe instance; previously it was looked up as a standalone declaration. The real cslib failure was Lean.Server.Watchdog.eraseFileWorker, missing Lean.JsonRpc.ResponseError.mk. Includes the 74-line Lean export.')

    select(97); select(1377, 1413); select(3802)
    render(); add_fixture('dependent_sprop_projection')
    r.step('dependent-projections', 'Preserve dependent field types and proof-only records',
           'Construct fallback projection types in the correct local telescope and compute relevance in that context. Keep primitive projections for Type-valued records containing only proof fields, without assuming such records have eta. This extends the earlier projection-relevance PR; the focused fixture contains a proof field whose type depends on an earlier field.')

    select(167); select(1458, 2613); select(3949)
    render()
    for name in ('nested_below', 'nested_record_tree_cases', 'nested_mixed_fields'): add_fixture(name)
    r.step('nested-fix-match', 'Build nested recursor adapters with structural fix and match',
           'Replace the All/AllForall-based folding path with direct structural recursion through List, Array, Option, Prod and eligible records, including mutual blocks and auxiliary recursors. This addresses Lean.Meta.DiscrTree.Trie.casesOn. The branch is the incremental replacement on the integrated old stack, not another copy of the old nested-containers PR.')

    features.add('compact')
    for n in (1201, 1245, 1247, 2620, 2696, 3263, 3392, 3415): select(n)
    render()
    r.put('src/Lean.v', r.hunks('src/Lean.v', lambda n, *_: 97 <= n <= 723))
    removed = [p for p in r.names if r.final[p] is None]
    r.take(*removed, 'tests/compact_nat.v', 'tests/core.v')
    project = r.files['tests/_CoqProject'].decode()
    for p in removed:
        if p.startswith('tests/'): project = project.replace(p.removeprefix('tests/') + '\n', '')
    r.put('tests/_CoqProject', project)
    r.step('compact-kernel-integration', 'Use compact kernel arithmetic instead of proof transports',
           'Register the generic Lean Nat encoding and operations with the experimental kernel. Keep large literals compact and remove the proof-certificate/application-transport path it replaces. Register checked division and modulus workers when they are declared. Motivating failures include Int32.toInt_lt and Int32.ofInt_tdiv. Requires the Rocq review stack; this is not a stock-Rocq PR.')

    features.add('modern')
    select(943); select(1019)
    render(); r.take('src/Lean.v')
    r.step('modern-core-foundation', 'Align the foundation with modern UInt32 and character computations',
           'Extend the already integrated UInt32/Char layout with their toNat/validity predeclarations and update the foundation character computations and stdlib imports. This is the later foundation delta, not a replacement for pr/uint32-modern-dump or pr/string-of-list. The imported core fixture exercises Char.ofNatAux and its dependent proof. Requires the compact arithmetic branch below it.')

    features.add('hints')
    select(4167)
    render(); r.take('src/leanExpr.mli')
    r.put('src/leanParse.ml', r.hunks('src/leanParse.ml', lambda n, *_: 133 <= n <= 145))
    r.step('reducibility-hints', 'Preserve Lean reducibility hints and genuine opacity',
           'Read abbreviation, regular-height and opaque-hint export records, and install persistent Rocq strategies. Keep an opaque reducibility hint distinct from a genuinely opaque declaration. This supplies the conversion ordering used on large cslib dependencies such as Int32.toBitVec_not; it does not itself implement a new conversion rule. The NDJSON exporter must preserve the same metadata.')

    features.add('unit')
    for n in (131, 367, 3616, 3938): select(n)
    render(); add_fixture('nullary_unit_scheme')
    r.step('nullary-unit-schemes', 'Register unit-like inductives and simplify their nullary schemes',
           'Register eligible unit-like types, including types restored from a checkpoint. For a nullary constructor, check the branch-only eliminator against the generated dependent scheme type. This fixes Cslib.Automata.NA.FinAcc.instTotalSumUnitFinLoopOfNonemptyElemStart. Constructors with fields and indexed types retain ordinary schemes. Requires the experimental kernel unit-eta rule.')

    features.add('cache')
    for a, b in ((456, 466), (729, 732), (763, 763)): select(a, b)
    render()
    r.step('translation-sharing', 'Cache translation by expression and binder context',
           'Reuse translations of shared Lean expression nodes, with context/depth information for open terms and separate caches for context-independent fragments. Memoize relevance inspection and canonicalize binder contexts. Large exported proof DAGs otherwise repeat translation work. Optional cache validation compares cached results with fresh translations; this is an importer optimization, not proof replacement.')

    features.add('checkpoint')
    render(); r.take('src/leanParse.ml', 'src/leanParse.mli')
    r.files['tests/unit/checkpoint.ml'] = (ROOT / 'work/cslib-v2/test_indexed_checkpoint.ml').read_bytes()
    r.files['tests/unit/chunked_parse.ml'] = (ROOT / 'work/cslib-v2/test_chunked_parse.ml').read_bytes()
    r.put('tests/unit/README.md', '''# Parser-only regressions

Run in a Rocq development environment with `ocamlfind` and `rocq-runtime.vernac`:

```sh
bash tests/unit/run.sh
```

This compiles only the parser and runs small OCaml fixtures. It does not start
a Rocq worker, import cslib or test kernel conversion.
''')
    r.put('tests/unit/run.sh', '''#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source_dir=$(cd -- "$test_dir/../../src" && pwd -P)
scratch=$(mktemp -d -t lean-parser-tests.XXXXXXXX)
trap 'rm -r -- "$scratch"' EXIT
compiler=(ocamlfind ocamlc -rectypes -thread -package rocq-runtime.vernac -I "$scratch")
for module in leanName leanExpr leanParse; do
  "${compiler[@]}" -c "$source_dir/$module.mli" -o "$scratch/$module.cmi"
  if [[ -f $source_dir/$module.ml ]]; then
    "${compiler[@]}" -c "$source_dir/$module.ml" -o "$scratch/$module.cmo"
  fi
done
for test in chunked_parse checkpoint; do
  "${compiler[@]}" -c "$test_dir/$test.ml" -o "$scratch/$test.cmo"
  "${compiler[@]}" -linkpkg "$scratch/leanName.cmo" "$scratch/leanParse.cmo" \\
    "$scratch/$test.cmo" -o "$scratch/$test.exe"
  "$scratch/$test.exe"
done
''')
    r.step('indexed-checkpoints', 'Store parser graphs in chunked indices and indexed checkpoints',
           'Use persistent chunks for parser tables and serialize expression edges as integer references. Pack ancestor state and restore it lazily, preserving entry/parser sharing and supported legacy formats. This addresses checkpoint memory peaks in the multi-million-line cslib run. Tests cover DAG aliases, metadata, append persistence and malformed indexed data. Atomic promotion and resource guards live in the arena repository.')

    r.take(*r.names)
    # Extra owner regression remains registered in addition to the snapshot fixtures.
    r.put('tests/_CoqProject', r.text('tests/_CoqProject') + 'constructor_owner.v\n')
    r.step('importer-diagnostics', 'Preserve the remaining importer experiment diagnostics',
           'Restore the exact runtime source snapshot, including opt-in declaration/AST/timing diagnostics and its README. All implementation topics are in the preceding branches. This branch is the reproducibility tail, not an additional upstream PR. The small constructor-owner fixture and parser unit tests are retained as review additions.')
    # Runtime sources must match; the additional registered review fixture is intentional.
    expected_project = r.final['tests/_CoqProject']
    r.final['tests/_CoqProject'] = r.files['tests/_CoqProject']
    for path, data in r.final.items():
        assert r.read(r.head, path) == data, ('importer final differs', path)
        expected_live = expected_project if path == 'tests/_CoqProject' else data
        live = (r.path / path).read_bytes() if (r.path / path).exists() else None
        assert live == expected_live, ('importer live changed', path)
    assert r.git('status', '--porcelain=v1', '-uno') == r.original_status
    print(json.dumps({'repo': str(r.path), 'snapshot': r.snapshot,
                      'runtime_source_equivalence': True, 'live_worktree_unchanged': True}), flush=True)
    return r

def arena():
    guards = ['checkers/rocq-lean-import/scripts/build-internal.sh',
              'checkers/rocq-lean-import/scripts/run-internal.sh',
              'checkers/rocq-lean-import/scripts/run-memory-guarded.sh',
              'scripts/tests/test_rocq_resource_safety.py',
              'scripts/tests/test_guard_service_owner.py',
              'scripts/tests/test_guard_proc_liveness.py',
              'work/run-memory-guarded.sh']
    checkpoints = ['work/run-checkpoint-atomic.sh',
                   'work/cslib-full-fresh/run-checkpointed.sh',
                   'work/unit-projection-repro/resume-cslib.sh',
                   'work/unit-projection-repro/check-toolchain.sh',
                   'scripts/audit_rocq_full_pass.py',
                   'scripts/tests/test_full_pass_audit.py']
    r = Repo('.', guards + checkpoints + ['docs/review-map.md'])
    converter_path = 'checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py'
    r.files[converter_path] = (ROOT / '_deps/lean-kernel-arena' / converter_path).read_bytes()
    r.files['scripts/tests/test_export_hints.py'] = Path('/tmp/test_export_hints.py').read_bytes()
    r.step('export-hints', 'Preserve Lean reducibility metadata in the arena converter',
           'Emit abbreviation, regular-height, opaque-hint and genuinely opaque records. This is the exporter counterpart to importer review/reducibility-hints. Copies the converter used by the current experiment out of the dependency checkout, with small marker/validation tests.')
    r.take(*guards, 'checkers/rocq-lean-import/scripts/build.sh',
           'checkers/rocq-lean-import/scripts/run.sh', 'scripts/run_rocq_frontier.py')
    r.step('guarded-runs', 'Guard checker entry points and serialize heavyweight jobs',
           'Route checker builds/runs and frontier probes through a single user-wide cgroup memory guard. Test process liveness, service ownership and wrapper cleanup with fake commands, not a live Rocq workload. This addresses the earlier concurrent-worker and out-of-memory incidents.')
    r.take(*checkpoints)
    r.step('atomic-checkpoints', 'Promote checkpoints atomically and audit full-pass evidence',
           'Keep the last good .vo until its guarded replacement succeeds. Record source/toolchain hashes, require expected EOF and a successful save, and keep fresh-process reload as a separate gate. Includes the exact experimental launchers under work/: those pin local binaries/checkpoints and are not portable fresh-install instructions.')
    r.take('docs/review-map.md', 'rocq-lean-import-pr-stack.md')
    readme = r.text('README.md', final=False)
    readme = replace(readme, 'Rocq check the result.\n',
                     'Rocq check the result.\n\nFor developers: the [cslib review map](docs/review-map.md) links each importer,\nkernel and runner change to its branch, topic diff and validation status.\n')
    r.put('README.md', readme)
    # Keep the packaging/checking recipes for auditing this one-time extraction.
    r.files['scripts/review/package-cslib-review.py'] = Path('/tmp/package-cslib-review.py').read_bytes()
    r.files['scripts/review/check-cslib-review.py'] = Path('/tmp/check-cslib-review.py').read_bytes()
    r.put('scripts/review/README.md', '''# Extraction record

These are the one-time scripts used to cut the September 7 review branches.
They are retained as an audit record, not as a supported build command: paths
and source-hunk coordinates refer to the captured local worktrees. Re-running
requires that exact input. Do not run them in an unrelated checkout.

`package-cslib-review.py` uses temporary Git indices and checks runtime-source
equivalence; it does not switch or modify the active implementation worktrees.
`check-cslib-review.py` performs sequential OCaml source checks against the
already built experimental interfaces, not full Rocq builds.
''')
    # Record source identities and predecessor refs, without recording large binaries.
    repositories = {}
    for name, path, remote in [
        ('kernel', ROOT / '_worktrees/rocq/compact-peano-view', 'https://github.com/theostos/rocq'),
        ('importer', ROOT / '_worktrees/rocq-lean-import/compact-peano-importer-current', 'https://github.com/theostos/rocq-lean-import')]:
        def git(*args): return run(['git', *args], cwd=path).decode().strip()
        refs = git('for-each-ref', '--format=%(refname:short)', 'refs/heads/review/').splitlines()
        entries = []
        for ref in refs:
            parent = git('rev-parse', ref + '^')
            parent_names = [other for other in refs if git('rev-parse', other) == parent]
            entries.append({'branch': ref, 'commit': git('rev-parse', ref),
                            'base': parent_names[0] if parent_names else parent})
        repositories[name] = {'url': remote, 'snapshot': git('rev-parse', 'snapshot/cslib-20260907'),
                              'branches': entries}
    manifest = {'date': '2026-09-07', 'repositories': repositories,
                'arena': {'url': 'https://github.com/theostos/rocq-lean-arena', 'branches': r.steps},
                'validation': {'runtime_sources_match_snapshots': True,
                               'implementation_worktrees_unchanged': True,
                               'ocaml_parsing': 'passed for changed sources in both stacks',
                               'ocaml_typing': 'importer lean.ml/leanParse.ml at each head and extracted kernel conversion variants; against built experimental interfaces',
                               'arena_unit_tests': '42 passed from the review tree, including exporter hints; mock-only, no Rocq workload',
                               'parser_unit_tests': 'chunked indexes and indexed checkpoints passed from review/indexed-checkpoints',
                               'clean_branch_builds': 'not run while full import is active',
                               'full_cslib_pass': 'not established'}}
    r.put('docs/review-stack.json', json.dumps(manifest, indent=2) + '\n')
    r.step('cslib-review-map', 'Map the cslib experiment to review branches and their evidence',
           'Link each importer/kernel/pipeline topic to its focused branch diff, retain earlier PR links, distinguish superseded implementations and record validation limits. Runtime sources, pinned runners and ongoing experiments are untouched.')
    assert r.git('status', '--porcelain=v1', '-uno') == r.original_status
    return r

if __name__ == '__main__':
    import sys
    if len(sys.argv) == 1 or sys.argv[1] == 'kernel': kernel()
    elif sys.argv[1] == 'importer': importer()
    elif sys.argv[1] == 'arena': arena()
