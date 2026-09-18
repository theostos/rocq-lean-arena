"""Offline dependency scheduler model. It never runs or approves a proof check.

Costs and memory are supplied by the caller. Unit-cost experiments measure graph
structure, not expected Rocq runtime. Edges list each task's prerequisites.
"""
from dataclasses import dataclass
import heapq
import math


@dataclass(frozen=True)
class Task:
    dependencies: tuple[int, ...]
    cost: float
    memory: float = 1.0
    order: int = 0


class Model:
    def __init__(self, tasks):
        self.tasks = tasks
        n = len(tasks)
        self.children = [[] for _ in tasks]
        self.indegree = []
        for i, task in enumerate(tasks):
            if not math.isfinite(task.cost) or task.cost < 0:
                raise ValueError('cost must be finite and nonnegative')
            if not math.isfinite(task.memory) or task.memory <= 0:
                raise ValueError('memory must be finite and positive')
            if len(set(task.dependencies)) != len(task.dependencies):
                raise ValueError('duplicate dependency')
            self.indegree.append(len(task.dependencies))
            for dep in task.dependencies:
                if not 0 <= dep < n:
                    raise ValueError('unknown dependency')
                self.children[dep].append(i)
        waiting = self.indegree.copy()
        ready = [(tasks[i].order, i) for i, d in enumerate(waiting) if not d]
        heapq.heapify(ready)
        self.topological = []
        while ready:
            _, i = heapq.heappop(ready)
            self.topological.append(i)
            for child in self.children[i]:
                waiting[child] -= 1
                if not waiting[child]: heapq.heappush(ready, (tasks[child].order, child))
        if len(self.topological) != n:
            raise ValueError('cycle in task graph')
        self.rank = [0.0] * n
        for i in reversed(self.topological):
            self.rank[i] = tasks[i].cost + max((self.rank[j] for j in self.children[i]), default=0)
        self.total = sum(t.cost for t in tasks)
        self.critical_path = max(self.rank, default=0)

    def simulate(self, workers, memory_budget=None, record=False):
        if workers < 1: raise ValueError('need at least one worker')
        budget = float(workers) if memory_budget is None else memory_budget
        if not math.isfinite(budget) or budget <= 0: raise ValueError('invalid memory budget')
        if any(t.memory > budget for t in self.tasks):
            raise ValueError('a task exceeds the total memory budget')
        waiting = self.indegree.copy()
        ready = [(-self.rank[i], self.tasks[i].order, i)
                 for i, d in enumerate(waiting) if not d]
        heapq.heapify(ready)
        running = []
        now = used = peak = 0.0
        completed = 0
        trace = []
        while ready or running:
            deferred = []
            while ready and len(running) < workers:
                item = heapq.heappop(ready)
                i = item[2]; task = self.tasks[i]
                if used + task.memory > budget:
                    deferred.append(item)
                    continue
                used += task.memory
                peak = max(peak, used)
                heapq.heappush(running, (now + task.cost, i))
                if record: trace.append({'task': i, 'start': now, 'end': now + task.cost})
            for item in deferred: heapq.heappush(ready, item)
            if not running:
                raise ValueError('no admissible task: resource model cannot progress')
            now = running[0][0]
            finished = []
            while running and running[0][0] == now:
                _, i = heapq.heappop(running)
                used -= self.tasks[i].memory
                completed += 1
                finished.append(i)
            # All simultaneous completions become visible before selecting more work.
            for i in finished:
                for child in self.children[i]:
                    waiting[child] -= 1
                    if not waiting[child]:
                        heapq.heappush(ready, (-self.rank[child], self.tasks[child].order, child))
        assert completed == len(self.tasks)
        assert now + 1e-8 >= max(self.critical_path, self.total / workers)
        return {'workers': workers, 'model_makespan': now,
                'model_speedup': self.total / now if now else 1.0,
                'model_utilization': self.total / (workers * now) if now else 1.0,
                'peak_reserved_memory_units': peak,
                **({'trace': trace} if record else {})}


def coarsen(tasks, groups):
    """Group costs/edges and refuse cycles; assign one memory unit per batch.

    This structural model does not estimate a combined dependency environment's
    RSS from the memory footprints of individual tasks.
    """
    if len(groups) != len(tasks): raise ValueError('group map must cover every task')
    labels = sorted(set(groups))
    ids = {label: i for i, label in enumerate(labels)}
    owners = [ids[x] for x in groups]
    costs = [0.0] * len(labels)
    orders = [math.inf] * len(labels)
    deps = [set() for _ in labels]
    for i, task in enumerate(tasks):
        owner = owners[i]
        costs[owner] += task.cost
        orders[owner] = min(orders[owner], task.order)
        for dep in task.dependencies:
            if owners[dep] != owner: deps[owner].add(owners[dep])
    result = [Task(tuple(sorted(ds)), costs[i], order=orders[i]) for i, ds in enumerate(deps)]
    Model(result)  # A->B->A is not a legal pair of compiled task artifacts.
    return result


def antichain_groups(model, capacity):
    """Deterministic size-limited batches within dependency-depth antichains.

    Exact inter-batch dependencies remain; there is no barrier between layers.
    Capacity uses caller cost units, not an assumed number of seconds.
    """
    if capacity <= 0: raise ValueError('capacity must be positive')
    depths = [0] * len(model.tasks)
    layers = {}
    for i in model.topological:
        depths[i] = max((depths[j] + 1 for j in model.tasks[i].dependencies), default=0)
        layers.setdefault(depths[i], []).append(i)
    groups = [-1] * len(model.tasks)
    group = -1
    for layer in sorted(layers):
        used = capacity
        for i in sorted(layers[layer], key=lambda j: model.tasks[j].order):
            if used >= capacity or used + model.tasks[i].cost > capacity:
                group += 1; used = 0
            groups[i] = group
            used += model.tasks[i].cost
    return groups
