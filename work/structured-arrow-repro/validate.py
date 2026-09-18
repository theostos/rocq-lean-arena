#!/usr/bin/env python3
"""Bounded, sequential checks against the patched main kernel."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts"))
import run_cslib_ndjson as direct
import run_chunked_import as chunks

KERNEL = ROOT / "_worktrees/rocq/compact-peano-view"
CHECKER = KERNEL / "_build/default/topbin/rocqworker.exe"


def main(generation=None, directory=None):
    if directory is None:
        directory = Path(tempfile.mkdtemp(prefix="patched-checks-", dir=HERE))
    else:
        directory = Path(directory).resolve()
        directory.mkdir(exist_ok=False)
    print(directory, flush=True)
    checks = [HERE / (name + ".v") for name in
              ("AliasedUnitProjection", "ArrowAlias", "AliasControls", "PrefixDirect", "PrefixMinimal")]
    checks += [KERNEL / "test-suite/success" / (name + ".v") for name in
               ("unit_like_projection", "compact_peano", "bounded_congruence",
                "congruence_probe_scope", "direct_unfolding_dependency", "eta_before_computation",
                "opaque_unit_record_eta", "projection_aliases", "projection_before_eta")]
    checks += [ROOT / "work/int8-conversion-repro" / (name + ".v") for name in
               ("OpaqueUnitRecord", "ProjectionBeforeEta", "ProjectionWrappers")]
    checks += [ROOT / "work/unit-projection-repro" / (name + ".v") for name in
               ("ModifyEq", "LinearMap")]
    checks += [ROOT / "work/int32-tdiv-repro/FinalBoundedProbesArithmetic.v"]
    checkpoints = ROOT / "work/mathlib-ndjson/checkpoints"
    foundation = ROOT / "work/mathlib-ndjson/foundation"
    module = "MathlibTo1000000"
    inputs = {str(path): chunks.sha(path) for path in
              [Path(__file__), CHECKER, *checks, direct.checking.IMPORTER / 'src/lean_import.cmxs']}
    if generation is not None:
        # The historical 1M artifact can be retired independently of these
        # fixtures. Reuse an explicitly supplied, sealed prefix containing it;
        # preserve all test statements and record the producer separately.
        generation = Path(generation).resolve(strict=True)
        checkpoints = generation / 'checkpoints'
        plan_path = checkpoints / 'plan.json'
        plan = chunks.load_plan(plan_path)
        profile = chunks.generation_toolchain(plan)
        chunk = plan['chunks'][0]
        if chunk['start'] != 1 or chunk['end'] < 1000001:
            raise ValueError('Expected an original-order prefix covering 1M')
        if chunks.verify_saved(checkpoints, chunk) is None:
            raise ValueError('Missing verified legacy fixture prefix')
        chunks.check_entries(profile['inputs'])
        module = chunk['module']
        foundation = Path(profile['foundation']).parent
        inputs.update(profile['inputs'])
        for path in (plan_path, checkpoints / (module + '.v'), checkpoints / (module + '.vo')):
            inputs[str(path)] = chunks.sha(path)
        chunks.save_json(directory / 'checkpoint.json', {
            'generation': str(generation), 'module': module,
            'producer_worker_sha256': profile['worker_sha256'],
            'consumer_worker_sha256': chunks.sha(CHECKER),
            'recheck_entire_prefix': False})
    inputs[str(foundation / 'Lean.vo')] = chunks.sha(foundation / 'Lean.vo')
    chunks.save_json(directory / 'inputs.json', inputs)
    env = direct.environment(3072)
    common = [str(CHECKER), "--kind=compile", "-coqlib", env["COQLIB"], "-q",
              "-bytecode-compiler", "no", "-R", str(direct.checking.STDLIB), "Stdlib",
              "-Q", str(checkpoints), "",
              "-Q", str(foundation), "LeanImport",
              "-I", str(direct.checking.IMPORTER / "src")]
    results = []
    for original in checks:
        stage = directory / str(len(results))
        stage.mkdir()
        source = stage / original.name
        shutil.copy2(original, source)
        if original.name in ('PrefixDirect.v', 'PrefixMinimal.v'):
            source.write_text(source.read_text().replace(
                'Require Import MathlibTo1000000.', 'Require Import ' + module + '.'))
        if original.name == "compact_peano.v":
            source.write_text(source.read_text().replace(
                "From Stdlib Require Import NArith.", "From Stdlib Require Import NArith.BinNat."))
        with (stage / "run.log").open("x") as log:
            result = subprocess.run(["bash", str(direct.checking.GUARD), "timeout", "120s",
                                     *common, "-Q", str(stage), "AliasTest", str(source)],
                                    cwd=original.parent, env=env, stdout=log, stderr=subprocess.STDOUT)
        results.append({"source": str(original), "exit_code": result.returncode,
                        "log": str(stage / "run.log")})
        print(original.name, result.returncode, flush=True)
        (directory / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        if result.returncode:
            print((stage / "run.log").read_text()[:4000], flush=True)
            return result.returncode
    chunks.check_entries(inputs)
    chunks.save_json(directory / 'passed.json', {
        'exit_code': 0, 'worker_sha256': chunks.sha(CHECKER),
        'tests': len(results), 'inputs': inputs, 'results': results})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
