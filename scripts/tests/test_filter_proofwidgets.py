import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('scope_filter',Path(__file__).parents[1]/'filter_proofwidgets.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


class FilterTests(unittest.TestCase):
    def fixture(self, folder, extra=()):
        rows=[{'meta':{'format':{'version':'3.1.0'}}},
              {'in':1,'str':{'pre':0,'str':'Widget'}},
              {'in':2,'str':{'pre':0,'str':'Math'}},
              {'ie':0,'sort':0},
              {'axiom':{'name':1,'type':0}},
              *extra,
              {'axiom':{'name':2,'type':0}}]
        source=folder/'in.ndjson';source.write_text(''.join(json.dumps(r)+'\n' for r in rows))
        candidates=folder/'candidates.jsonl'
        candidates.write_text(json.dumps({'parts':['Widget'],'module':'ProofWidgets.Test'})+'\n')
        return source,candidates,folder/'out.ndjson'

    def run_case(self, extra=(), preserve=0):
        with tempfile.TemporaryDirectory() as tmp:
            args=self.fixture(Path(tmp),extra)
            report=m.filter_export(*args,preserve)
            original=args[0].read_bytes().splitlines(keepends=True)
            filtered=args[2].read_bytes().splitlines(keepends=True)
            self.assertEqual(len(original),len(filtered))
            for i,(before,after) in enumerate(zip(original,filtered),1):
                self.assertEqual(after, b'\n' if i==5 and preserve<5 else before)
            return report

    def test_preserves_every_other_byte_and_position(self):
        r=self.run_case();self.assertEqual([d['line'] for d in r['excluded']],[5])

    def test_preserves_checkpoint_prefix(self):
        r=self.run_case(preserve=5);self.assertEqual(r['excluded'],[])
        self.assertEqual(len(r['inherited_ui']),1)

    def reject(self, extra):
        with tempfile.TemporaryDirectory() as tmp:
            args=self.fixture(Path(tmp),extra)
            with self.assertRaisesRegex(ValueError,'retained declarations reference UI'):
                m.filter_export(*args)
            self.assertFalse(args[2].exists())

    def test_rejects_reference_in_original_proof(self):
        self.reject([{'ie':1,'const':{'name':1,'us':[]}},
                     {'thm':{'name':2,'type':0,'value':1}}])

    def test_rejects_projection_type_even_without_constant(self):
        self.reject([{'ie':1,'proj':{'typeName':1,'idx':0,'struct':0}},
                     {'def':{'name':2,'type':0,'value':1}}])

    def test_rejects_deep_expression_reference(self):
        self.reject([{'ie':1,'const':{'name':1,'us':[]}},
                     {'ie':2,'app':{'fn':0,'arg':1}},
                     {'ie':3,'lam':{'type':0,'body':2}},
                     {'thm':{'name':2,'type':0,'value':3}}])

    def test_rejects_recursor_rule_reference(self):
        self.reject([{'ie':1,'const':{'name':1,'us':[]}},
                     {'inductive':{'types':[{'name':2,'type':0}], 'ctors':[],
                                   'recs':[{'name':2,'type':0,'rules':[{'rhs':1}]}]}}])

    def test_rejects_mixed_mutual_block(self):
        with tempfile.TemporaryDirectory() as tmp:
            args=self.fixture(Path(tmp),[{'inductive':{'types':[{'name':1,'type':0},
                {'name':2,'type':0}],'ctors':[],'recs':[]}}])
            with self.assertRaisesRegex(ValueError,'Mixed UI/non-UI'):m.filter_export(*args)

    def test_rejects_unknown_expression(self):
        with self.assertRaisesRegex(ValueError,'Unknown expression'):
            m.references({'ie':1,'futureExpression':{}})


if __name__=='__main__':unittest.main()
