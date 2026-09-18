import unittest
from analyze import extract, kernel_events, TARGET


class AnalysisTests(unittest.TestCase):
    def test_target_and_stack(self):
        phases, entries, stacks = extract(f'''[declare start] {TARGET} instance 0 cpu=1.000 heap_words=10 major=0
[declare after body] {TARGET} instance 0 cpu=1.250 heap_words=10 major=0
[conversion entry] 42 cpu=1.300 major=0 typed=true relevance=true projection=false dependency=true A/2 <> B/2
[timeout stack] signal=SIGALRM wall=500
#0  camlConversion__ccnv_1 ()
#1  camlTypeops__execute_1 ()
[timeout stack end] stopped_seconds=0.002
''')
        self.assertEqual(phases[-1]['phase'], 'after body')
        self.assertEqual(entries[-1]['call'], 42)
        self.assertEqual(len(stacks[0]['frames']), 2)
        self.assertEqual(stacks[0]['stopped_seconds'], .002)

    def test_profile_nested_events(self):
        checks = kernel_events([
            {'ph': 'B', 'name': 'process', 'ts': 0},
            {'ph': 'B', 'name': 'Typeops.execute', 'ts': 1000},
            {'ph': 'B', 'name': 'HConstr.of_constr', 'ts': 2000},
            {'ph': 'E', 'name': 'HConstr.of_constr', 'ts': 3000},
            {'ph': 'E', 'name': 'Typeops.execute', 'ts': 2001000,
             'args': {'subtimes': {'Conversion': '1s, 1 call'}}},
            {'ph': 'E', 'name': 'process', 'ts': 2002000}])
        self.assertEqual(checks[0]['wall_seconds'], 2)
        self.assertEqual(checks[0]['args']['subtimes']['Conversion'], '1s, 1 call')

    def test_incomplete_stacks_are_not_counted(self):
        self.assertEqual(extract('[timeout stack] signal=SIGUSR1\n#0 frame\n')[2], [])


if __name__ == '__main__':
    unittest.main()
