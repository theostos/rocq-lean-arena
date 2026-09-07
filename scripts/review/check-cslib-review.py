"""Small, sequential OCaml checks in scratch directories; no Rocq workers."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile

spec = importlib.util.spec_from_file_location('package', '/tmp/package-cslib-review.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)
root = package.ROOT
compiler = '/home/theo/.opam/rocq93_native/bin/ocamlfind'
kernel_build = root / '_worktrees/rocq/compact-peano-view/_build/default'
kernel_includes = [arg for path in sorted(kernel_build.glob('*/.*.objs/byte'))
                   for arg in ('-I', str(path))]

def git(repo, *args):
    return subprocess.check_output(['git', *args], cwd=repo)

def compile_one(scratch, name, content, typing=False, extra=()):
    path = scratch / name
    path.write_bytes(content)
    args = [compiler, 'ocamlc', '-rectypes', '-thread', '-package', 'rocq-runtime.vernac',
            '-I', str(scratch), *kernel_includes, *extra]
    if typing != 'interface': args += ['-stop-after', 'typing' if typing else 'parsing']
    args += ['-c', str(path)]
    result = subprocess.run(args, cwd=scratch, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        print('\n'.join(line for line in result.stdout.decode().splitlines()
                        if not line.startswith('findlib: [WARNING]')), flush=True)
        raise SystemExit(result.returncode)

with tempfile.TemporaryDirectory(prefix='cslib-review-check-') as temp:
    scratch = Path(temp)
    for rel in ('_worktrees/rocq/compact-peano-view',
                '_worktrees/rocq-lean-import/compact-peano-importer-current'):
        repo = root / rel
        refs = git(repo, 'for-each-ref', '--format=%(refname:short)', 'refs/heads/review/').decode().splitlines()
        for ref in refs:
            changed = git(repo, 'diff-tree', '--no-commit-id', '--name-only', '-r', ref).decode().splitlines()
            for name in changed:
                if name.endswith(('.ml', '.mli')):
                    compile_one(scratch, Path(name).name, git(repo, 'show', f'{ref}:{name}'))
            print(f'PARSE PASS {repo.name} {ref}', flush=True)
    repo = root / '_worktrees/rocq/compact-peano-view'
    for ref in ('review/compact-peano', 'review/unit-eta', 'review/conversion-strategies'):
        compile_one(scratch, 'conversion.ml', git(repo, 'show', f'{ref}:kernel/conversion.ml'), typing=True)
        print(f'TYPE PASS (built experimental interfaces) {ref} conversion.ml', flush=True)
    repo = root / '_worktrees/rocq-lean-import/compact-peano-importer-current'
    for ref in git(repo, 'for-each-ref', '--format=%(refname:short)', 'refs/heads/review/').decode().splitlines():
        with tempfile.TemporaryDirectory(prefix='cslib-review-importer-') as import_temp:
            dest = Path(import_temp)
            for name in ('leanName.mli', 'leanExpr.mli', 'leanParse.mli'):
                compile_one(dest, name, git(repo, 'show', f'{ref}:src/{name}'), typing='interface')
            for name in ('lean.ml', 'leanParse.ml'):
                compile_one(dest, name, git(repo, 'show', f'{ref}:src/{name}'), typing=True)
            print(f'TYPE PASS (built experimental interfaces) {ref} lean.ml, leanParse.ml', flush=True)
