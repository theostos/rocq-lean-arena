import unittest
from array import array
from contextlib import redirect_stdout
from io import StringIO
from analyze_full_graph import components
from scheduler_model import Model, Task, antichain_groups, coarsen


class SchedulerTests(unittest.TestCase):
    def test_diamond_and_dependency_order(self):
        m = Model([Task((), 10), Task((0,), 20), Task((0,), 30), Task((1, 2), 5)])
        self.assertEqual(m.simulate(1)['model_makespan'], 65)
        result = m.simulate(2, record=True)
        self.assertEqual(result['model_makespan'], 45)
        times = {x['task']: x for x in result['trace']}
        for i, t in enumerate(m.tasks):
            for dep in t.dependencies: self.assertGreaterEqual(times[i]['start'], times[dep]['end'])

    def test_memory_backfill_and_reservation(self):
        m = Model([Task((), 10, 6), Task((), 9, 6), Task((), 3, 2)])
        r = m.simulate(2, memory_budget=8, record=True)
        times = {x['task']: x for x in r['trace']}
        self.assertEqual(times[2]['start'], 0)
        self.assertEqual(times[1]['start'], 10)
        self.assertEqual(r['peak_reserved_memory_units'], 8)
        self.assertEqual(r['model_makespan'], 19)

    def test_memory_refusal_and_zero_cost_dependencies(self):
        with self.assertRaises(ValueError): Model([Task((), 1, 9)]).simulate(2, 8)
        m = Model([Task((), 0), Task((0,), 0), Task((1,), 4)])
        self.assertEqual(m.simulate(4)['model_makespan'], 4)

    def test_invalid_graphs(self):
        for tasks in ([Task((1,), 1), Task((0,), 1)], [Task((2,), 1)],
                      [Task((), 1), Task((0, 0), 1)], [Task((), -1)]):
            with self.assertRaises(ValueError): Model(tasks)

    def test_coarsening_refuses_new_cycle(self):
        tasks = [Task((), 1), Task((0,), 1), Task((1,), 1)]
        with self.assertRaises(ValueError): coarsen(tasks, [0, 1, 0])

    def test_coarsening_preserves_original_order_outside_dense_task_ids(self):
        tasks = [Task((), 1, order=100), Task((), 1, order=200)]
        grouped = coarsen(tasks, [0, 1])
        self.assertEqual([task.order for task in grouped], [100, 200])

    def test_components_keep_cycle_with_its_family_only(self):
        # 0 <-> 1, 2 -> 1, 3 -> 2, 3 -> 4, 4 -> 3; 5 is isolated.
        with redirect_stdout(StringIO()):
            ids, sizes = components(range(6), array('I', [0, 1, 2, 3, 5, 6, 6]),
                                    array('I', [1, 0, 1, 2, 4, 3]))
        self.assertEqual(sorted(sizes), [1, 1, 2, 2])
        self.assertEqual(ids[0], ids[1])
        self.assertEqual(ids[3], ids[4])
        self.assertEqual(len({ids[0], ids[2], ids[3], ids[5]}), 4)

    def test_antichain_batching_keeps_all_work_and_acyclicity(self):
        tasks = [Task((), 2), Task((), 3), Task((0,), 7), Task((1,), 1), Task((2, 3), 5)]
        grouped = Model(coarsen(tasks, antichain_groups(Model(tasks), 5)))
        self.assertEqual(grouped.total, 18)
        self.assertEqual(grouped.simulate(1)['model_makespan'], 18)


if __name__ == '__main__': unittest.main()
