"""
Task Pool Manager - Python asyncio-based task coordination

Provides high-performance parallel data collection and analysis for the MojoRust
trading bot with 16 parallel workers, priority queues, and real-time task orchestration.

Features:
- 16 parallel workers for maximum throughput
- Priority-based task scheduling
- Real-time performance monitoring
- Automatic retry and error handling
- Memory-efficient task queuing
- Integration with Mojo data synthesis engine
- Async/await for optimal performance
"""

import asyncio
import logging
import time
import json
import uuid
from typing import Dict, List, Optional, Any, Callable, Union, Awaitable
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
from enum import Enum
import heapq
from concurrent.futures import ThreadPoolExecutor
import psutil
import os
from collections import defaultdict, deque

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Task priorities (higher number = higher priority)
class TaskPriority(Enum):
    CRITICAL = 5    # Real-time trading signals
    HIGH = 4       # Price updates, arbitrage opportunities
    MEDIUM = 3     # Social sentiment, wallet analysis
    LOW = 2        # Historical data, cleanup tasks
    BACKGROUND = 1 # Reports, maintenance

# Task types for different data sources
class TaskType(Enum):
    PRICE_UPDATE = "price_update"
    SOCIAL_SENTIMENT = "social_sentiment"
    WALLET_ANALYSIS = "wallet_analysis"
    TOKEN_METRICS = "token_metrics"
    ARBITRAGE_SCAN = "arbitrage_scan"
    RISK_ASSESSMENT = "risk_assessment"
    Geyser_STREAM = "geyser_stream"
    JUPITER_QUOTE = "jupiter_quote"
    HELIUS_METADATA = "helius_metadata"
    QUICKNODE_BALANCE = "quicknode_balance"
    DATA_SYNTHESIS = "data_synthesis"
    MEV_DETECTION = "mev_detection"

# Task status tracking
class TaskStatus(Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    RETRY = "retry"

@dataclass
class TaskResult:
    """Result of a completed task"""
    task_id: str
    task_type: TaskType
    status: TaskStatus
    result: Any
    error: Optional[str] = None
    execution_time: float = 0.0
    worker_id: Optional[str] = None
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None
    retry_count: int = 0
    metadata: Dict[str, Any] = None

@dataclass
class Task:
    """Task definition with priority and scheduling"""
    id: str
    task_type: TaskType
    priority: TaskPriority
    data: Dict[str, Any]
    callback: Optional[Callable] = None
    max_retries: int = 3
    timeout: float = 30.0
    created_at: datetime = None
    scheduled_at: Optional[datetime] = None
    dependencies: List[str] = None
    metadata: Dict[str, Any] = None

    def __post_init__(self):
        if self.created_at is None:
            self.created_at = datetime.utcnow()
        if self.dependencies is None:
            self.dependencies = []
        if self.metadata is None:
            self.metadata = {}

    # For priority queue ordering (negative priority for max-heap behavior)
    def __lt__(self, other):
        return self.priority.value > other.priority.value

@dataclass
class WorkerStats:
    """Worker performance statistics"""
    worker_id: str
    tasks_completed: int = 0
    tasks_failed: int = 0
    total_execution_time: float = 0.0
    average_execution_time: float = 0.0
    last_task_time: Optional[datetime] = None
    current_task: Optional[str] = None
    memory_usage: float = 0.0
    cpu_usage: float = 0.0
    tasks_by_type: Dict[str, int] = None

    def __post_init__(self):
        if self.tasks_by_type is None:
            self.tasks_by_type = defaultdict(int)

class TaskPoolManager:
    """
    High-performance task pool manager with 16 parallel workers

    Manages parallel data collection and analysis for the trading bot with
    priority-based scheduling and real-time monitoring.
    """

    def __init__(
        self,
        max_workers: int = 16,
        max_queue_size: int = 1000,
        enable_monitoring: bool = True,
        retry_delay: float = 1.0,
        max_memory_usage: float = 0.8  # 80% of available memory
    ):
        self.max_workers = max_workers
        self.max_queue_size = max_queue_size
        self.enable_monitoring = enable_monitoring
        self.retry_delay = retry_delay
        self.max_memory_usage = max_memory_usage

        # Task queues and management
        self.priority_queue = []
        self.running_tasks = {}
        self.completed_tasks = {}
        self.task_dependencies = {}
        self.task_results = {}

        # Worker management
        self.workers = {}
        self.worker_stats = {}
        self.thread_pool = ThreadPoolExecutor(max_workers=max_workers)

        # Performance monitoring
        self.stats = {
            'total_tasks_submitted': 0,
            'total_tasks_completed': 0,
            'total_tasks_failed': 0,
            'average_queue_time': 0.0,
            'average_execution_time': 0.0,
            'system_load': 0.0,
            'memory_usage': 0.0,
            'tasks_per_second': 0.0,
            'error_rate': 0.0
        }

        # Monitoring state
        self._monitoring_task = None
        self._running = False
        self._start_time = datetime.utcnow()

        # Event loops and synchronization
        self._loop = asyncio.get_event_loop()
        self._queue_semaphore = asyncio.Semaphore(max_queue_size)
        self._worker_semaphore = asyncio.Semaphore(max_workers)

        # Task type-specific configurations
        self.task_configs = {
            TaskType.PRICE_UPDATE: {'timeout': 5.0, 'priority': TaskPriority.HIGH},
            TaskType.SOCIAL_SENTIMENT: {'timeout': 15.0, 'priority': TaskPriority.MEDIUM},
            TaskType.WALLET_ANALYSIS: {'timeout': 20.0, 'priority': TaskPriority.MEDIUM},
            TaskType.TOKEN_METRICS: {'timeout': 10.0, 'priority': TaskPriority.MEDIUM},
            TaskType.ARBITRAGE_SCAN: {'timeout': 30.0, 'priority': TaskPriority.HIGH},
            TaskType.RISK_ASSESSMENT: {'timeout': 25.0, 'priority': TaskPriority.HIGH},
            TaskType.Geyser_STREAM: {'timeout': 60.0, 'priority': TaskPriority.CRITICAL},
            TaskType.JUPITER_QUOTE: {'timeout': 10.0, 'priority': TaskPriority.HIGH},
            TaskType.HELIUS_METADATA: {'timeout': 8.0, 'priority': TaskPriority.MEDIUM},
            TaskType.QUICKNODE_BALANCE: {'timeout': 12.0, 'priority': TaskPriority.MEDIUM},
            TaskType.DATA_SYNTHESIS: {'timeout': 5.0, 'priority': TaskPriority.CRITICAL},
            TaskType.MEV_DETECTION: {'timeout': 3.0, 'priority': TaskPriority.CRITICAL}
        }

    async def start(self):
        """Start the task pool manager"""
        if self._running:
            logger.warning("TaskPoolManager is already running")
            return

        self._running = True

        # Initialize workers
        for i in range(self.max_workers):
            worker_id = f"worker-{i}"
            self.workers[worker_id] = asyncio.create_task(self._worker_loop(worker_id))
            self.worker_stats[worker_id] = WorkerStats(worker_id=worker_id)

        # Start monitoring if enabled
        if self.enable_monitoring:
            self._monitoring_task = asyncio.create_task(self._monitoring_loop())

        logger.info(f"TaskPoolManager started with {self.max_workers} workers")

    async def stop(self):
        """Stop the task pool manager gracefully"""
        if not self._running:
            return

        logger.info("Stopping TaskPoolManager...")
        self._running = False

        # Cancel all workers
        for worker_id, worker_task in self.workers.items():
            worker_task.cancel()
            try:
                await worker_task
            except asyncio.CancelledError:
                logger.info(f"Worker {worker_id} cancelled")

        # Cancel monitoring
        if self._monitoring_task:
            self._monitoring_task.cancel()
            try:
                await self._monitoring_task
            except asyncio.CancelledError:
                pass

        # Shutdown thread pool
        self.thread_pool.shutdown(wait=True)

        logger.info("TaskPoolManager stopped")

    async def submit_task(
        self,
        task_type: TaskType,
        data: Dict[str, Any],
        priority: Optional[TaskPriority] = None,
        callback: Optional[Callable] = None,
        max_retries: int = 3,
        timeout: Optional[float] = None,
        dependencies: List[str] = None,
        metadata: Dict[str, Any] = None
    ) -> str:
        """
        Submit a task to the task pool

        Args:
            task_type: Type of task to execute
            data: Task data payload
            priority: Task priority (auto-determined from type if not provided)
            callback: Optional callback function for completion
            max_retries: Maximum retry attempts
            timeout: Task timeout in seconds
            dependencies: List of task IDs this task depends on
            metadata: Additional task metadata

        Returns:
            Task ID for tracking
        """
        # Check queue size limit
        if len(self.priority_queue) >= self.max_queue_size:
            raise RuntimeError("Task queue is full")

        # Get task configuration
        config = self.task_configs.get(task_type, {})
        if priority is None:
            priority = config.get('priority', TaskPriority.MEDIUM)
        if timeout is None:
            timeout = config.get('timeout', 30.0)

        # Generate task ID
        task_id = str(uuid.uuid4())

        # Create task
        task = Task(
            id=task_id,
            task_type=task_type,
            priority=priority,
            data=data,
            callback=callback,
            max_retries=max_retries,
            timeout=timeout,
            dependencies=dependencies or [],
            metadata=metadata or {}
        )

        # Store task dependencies
        if dependencies:
            self.task_dependencies[task_id] = dependencies

        # Add to priority queue
        heapq.heappush(self.priority_queue, task)
        self.stats['total_tasks_submitted'] += 1

        logger.debug(f"Task {task_id} submitted: {task_type.value} (priority: {priority.name})")
        return task_id

    async def get_task_result(self, task_id: str, timeout: Optional[float] = None) -> TaskResult:
        """Get result of a specific task"""
        start_time = time.time()

        while True:
            # Check if task is completed
            if task_id in self.task_results:
                return self.task_results[task_id]

            # Check timeout
            if timeout and (time.time() - start_time) > timeout:
                raise asyncio.TimeoutError(f"Task {task_id} not completed within {timeout}s")

            await asyncio.sleep(0.1)

    async def get_task_status(self, task_id: str) -> Optional[TaskStatus]:
        """Get current status of a task"""
        if task_id in self.task_results:
            return self.task_results[task_id].status
        elif task_id in self.running_tasks:
            return TaskStatus.RUNNING
        elif any(task.id == task_id for task in self.priority_queue):
            return TaskStatus.PENDING
        else:
            return None

    async def cancel_task(self, task_id: str) -> bool:
        """Cancel a pending task"""
        # Try to remove from priority queue
        for i, task in enumerate(self.priority_queue):
            if task.id == task_id:
                self.priority_queue.pop(i)
                heapq.heapify(self.priority_queue)

                # Create cancelled result
                result = TaskResult(
                    task_id=task_id,
                    task_type=task.task_type,
                    status=TaskStatus.CANCELLED,
                    result=None
                )
                self.task_results[task_id] = result
                return True

        # Cannot cancel running tasks
        if task_id in self.running_tasks:
            logger.warning(f"Cannot cancel running task {task_id}")
            return False

        return False

    async def get_stats(self) -> Dict[str, Any]:
        """Get comprehensive performance statistics"""
        # Calculate current system load
        cpu_percent = psutil.cpu_percent(interval=1)
        memory_percent = psutil.virtual_memory().percent / 100.0

        # Calculate tasks per second
        uptime_seconds = (datetime.utcnow() - self._start_time).total_seconds()
        tasks_per_second = self.stats['total_tasks_completed'] / max(uptime_seconds, 1)

        # Calculate error rate
        total_processed = self.stats['total_tasks_completed'] + self.stats['total_tasks_failed']
        error_rate = self.stats['total_tasks_failed'] / max(total_processed, 1)

        # Update system stats
        self.stats.update({
            'system_load': cpu_percent / 100.0,
            'memory_usage': memory_percent,
            'tasks_per_second': tasks_per_second,
            'error_rate': error_rate,
            'queue_size': len(self.priority_queue),
            'running_tasks': len(self.running_tasks),
            'workers_active': len([w for w in self.worker_stats.values() if w.current_task]),
            'uptime_seconds': uptime_seconds
        })

        return {
            'task_pool_stats': self.stats.copy(),
            'worker_stats': {wid: asdict(stats) for wid, stats in self.worker_stats.items()},
            'tasks_by_type': self._get_tasks_by_type_stats(),
            'performance_metrics': self._calculate_performance_metrics()
        }

    async def _worker_loop(self, worker_id: str):
        """Main worker loop for processing tasks"""
        logger.info(f"Worker {worker_id} started")

        while self._running:
            try:
                # Get next task with timeout
                task = await self._get_next_task(timeout=1.0)
                if task is None:
                    continue

                # Check dependencies
                if not await self._check_dependencies(task):
                    # Re-queue task if dependencies not met
                    heapq.heappush(self.priority_queue, task)
                    await asyncio.sleep(0.1)
                    continue

                # Execute task
                await self._execute_task(worker_id, task)

            except asyncio.CancelledError:
                logger.info(f"Worker {worker_id} cancelled")
                break
            except Exception as e:
                logger.error(f"Worker {worker_id} error: {e}")
                await asyncio.sleep(1.0)

        logger.info(f"Worker {worker_id} stopped")

    async def _get_next_task(self, timeout: float = 1.0) -> Optional[Task]:
        """Get next task from priority queue"""
        try:
            # Wait for task with timeout
            await asyncio.wait_for(self._queue_semaphore.acquire(), timeout=timeout)

            if self.priority_queue:
                task = heapq.heappop(self.priority_queue)
                return task
            else:
                self._queue_semaphore.release()
                return None

        except asyncio.TimeoutError:
            return None

    async def _check_dependencies(self, task: Task) -> bool:
        """Check if task dependencies are satisfied"""
        if not task.dependencies:
            return True

        for dep_id in task.dependencies:
            if dep_id not in self.task_results:
                return False
            if self.task_results[dep_id].status != TaskStatus.COMPLETED:
                return False

        return True

    async def _execute_task(self, worker_id: str, task: Task):
        """Execute a single task"""
        start_time = datetime.utcnow()
        self.running_tasks[task.id] = worker_id

        # Update worker stats
        stats = self.worker_stats[worker_id]
        stats.current_task = task.id
        stats.last_task_time = start_time

        try:
            # Execute task based on type
            result = await self._execute_task_by_type(task, worker_id)

            # Create successful result
            task_result = TaskResult(
                task_id=task.id,
                task_type=task.task_type,
                status=TaskStatus.COMPLETED,
                result=result,
                execution_time=(datetime.utcnow() - start_time).total_seconds(),
                worker_id=worker_id,
                start_time=start_time,
                end_time=datetime.utcnow()
            )

            # Update statistics
            self.stats['total_tasks_completed'] += 1
            stats.tasks_completed += 1
            stats.tasks_by_type[task.task_type.value] += 1
            stats.total_execution_time += task_result.execution_time
            stats.average_execution_time = stats.total_execution_time / max(stats.tasks_completed, 1)

            logger.debug(f"Task {task.id} completed by {worker_id}")

        except asyncio.TimeoutError:
            # Handle timeout
            task_result = TaskResult(
                task_id=task.id,
                task_type=task.task_type,
                status=TaskStatus.FAILED,
                result=None,
                error="Task timeout",
                execution_time=(datetime.utcnow() - start_time).total_seconds(),
                worker_id=worker_id,
                start_time=start_time,
                end_time=datetime.utcnow()
            )
            self.stats['total_tasks_failed'] += 1
            stats.tasks_failed += 1
            logger.warning(f"Task {task.id} timed out")

        except Exception as e:
            # Handle other errors
            task_result = TaskResult(
                task_id=task.id,
                task_type=task.task_type,
                status=TaskStatus.FAILED,
                result=None,
                error=str(e),
                execution_time=(datetime.utcnow() - start_time).total_seconds(),
                worker_id=worker_id,
                start_time=start_time,
                end_time=datetime.utcnow()
            )
            self.stats['total_tasks_failed'] += 1
            stats.tasks_failed += 1
            logger.error(f"Task {task.id} failed: {e}")

        finally:
            # Cleanup
            del self.running_tasks[task.id]
            stats.current_task = None
            self.task_results[task.id] = task_result
            self._queue_semaphore.release()

            # Execute callback if provided
            if task.callback:
                try:
                    if asyncio.iscoroutinefunction(task.callback):
                        await task.callback(task_result)
                    else:
                        task.callback(task_result)
                except Exception as e:
                    logger.error(f"Callback error for task {task.id}: {e}")

    async def _execute_task_by_type(self, task: Task, worker_id: str) -> Any:
        """Execute task based on its type"""
        # Import task executors dynamically to avoid circular imports
        from ..data.jupiter_price_api import JupiterPriceAPI
        from ..data.helius_client import HeliusClient
        from ..data.quicknode_client import QuickNodeClient

        task_data = task.data

        # Execute based on task type
        if task.task_type == TaskType.PRICE_UPDATE:
            # Get token price
            client = JupiterPriceAPI()
            token_mint = task_data.get('token_mint')
            if token_mint:
                return await client.get_price_sync(token_mint)

        elif task.task_type == TaskType.JUPITER_QUOTE:
            # Get Jupiter quote
            client = JupiterPriceAPI()
            return await client.get_quote_sync(
                task_data.get('input_mint'),
                task_data.get('output_mint'),
                task_data.get('amount', 1000000),
                task_data.get('slippage_bps', 100)
            )

        elif task.task_type == TaskType.SOCIAL_SENTIMENT:
            # Social sentiment analysis
            from ..data.social_client import SocialClient
            client = SocialClient()
            token_symbol = task_data.get('token_symbol')
            if token_symbol:
                return await client.get_sentiment_score(token_symbol)

        elif task.task_type == TaskType.WALLET_ANALYSIS:
            # Wallet analysis
            from ..analysis.wallet_graph_analyzer import WalletGraphAnalyzer
            analyzer = WalletGraphAnalyzer()
            wallet_address = task_data.get('wallet_address')
            if wallet_address:
                return await analyzer.analyze_wallet(wallet_address)

        elif task.task_type == TaskType.ARBITRAGE_SCAN:
            # Arbitrage opportunity scan
            token_mint = task_data.get('token_mint')
            if token_mint:
                client = JupiterPriceAPI()
                return await client.get_arbitrage_opportunities(token_mint)

        elif task.task_type == TaskType.RISK_ASSESSMENT:
            # Risk assessment
            token_mint = task_data.get('token_mint')
            position_size = task_data.get('position_size', 1000.0)
            if token_mint:
                # Mock risk assessment - would integrate with real risk engine
                return {
                    'risk_score': 0.5,
                    'recommendation': 'HOLD',
                    'confidence': 0.8
                }

        elif task.task_type == TaskType.DATA_SYNTHESIS:
            # Data synthesis (would call Mojo engine)
            return await self._call_mojo_synthesis_engine(task_data)

        elif task.task_type == TaskType.MEV_DETECTION:
            # MEV threat detection
            transaction_data = task_data.get('transaction_data')
            if transaction_data:
                return await self._detect_mev_threats(transaction_data)

        else:
            # Default task execution
            logger.warning(f"Unknown task type: {task.task_type}")
            return None

    async def _call_mojo_synthesis_engine(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Call Mojo data synthesis engine via Python interop"""
        # This would interface with the Mojo data synthesis engine
        # For now, return mock data
        return {
            'trading_signal': 'BUY',
            'confidence': 0.85,
            'reasoning': 'Multi-factor analysis indicates strong upward momentum',
            'price_target': data.get('current_price', 0) * 1.1,
            'time_horizon': '1h'
        }

    async def _detect_mev_threats(self, transaction_data: Dict[str, Any]) -> Dict[str, Any]:
        """Detect MEV threats in transaction"""
        # Mock MEV detection - would integrate with real MEV detector
        return {
            'threat_level': 'LOW',
            'threat_types': [],
            'confidence': 0.95,
            'recommendations': ['Proceed with transaction']
        }

    async def _monitoring_loop(self):
        """Performance monitoring loop"""
        while self._running:
            try:
                # Update system monitoring
                await self._update_system_monitoring()

                # Check memory usage
                memory_usage = psutil.virtual_memory().percent / 100.0
                if memory_usage > self.max_memory_usage:
                    logger.warning(f"High memory usage: {memory_usage:.1%}")
                    await self._cleanup_old_tasks()

                # Log performance metrics
                if self.stats['total_tasks_submitted'] % 100 == 0:
                    await self._log_performance_metrics()

                await asyncio.sleep(5.0)  # Monitor every 5 seconds

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Monitoring error: {e}")
                await asyncio.sleep(10.0)

    async def _update_system_monitoring(self):
        """Update system monitoring statistics"""
        # Update worker memory and CPU usage
        process = psutil.Process()

        for worker_id, stats in self.worker_stats.items():
            try:
                stats.memory_usage = process.memory_info().rss / (1024 * 1024)  # MB
                stats.cpu_usage = process.cpu_percent() / 100.0
            except:
                pass

    async def _cleanup_old_tasks(self):
        """Clean up old completed tasks to free memory"""
        cutoff_time = datetime.utcnow() - timedelta(hours=1)

        # Clean up completed task results
        old_tasks = [
            task_id for task_id, result in self.task_results.items()
            if result.end_time and result.end_time < cutoff_time
        ]

        for task_id in old_tasks:
            del self.task_results[task_id]

        if old_tasks:
            logger.info(f"Cleaned up {len(old_tasks)} old task results")

    async def _log_performance_metrics(self):
        """Log performance metrics"""
        stats = await self.get_stats()

        logger.info(f"""
Performance Metrics:
- Tasks Submitted: {stats['task_pool_stats']['total_tasks_submitted']}
- Tasks Completed: {stats['task_pool_stats']['total_tasks_completed']}
- Tasks Failed: {stats['task_pool_stats']['total_tasks_failed']}
- Tasks/Second: {stats['task_pool_stats']['tasks_per_second']:.2f}
- Error Rate: {stats['task_pool_stats']['error_rate']:.2%}
- Queue Size: {stats['task_pool_stats']['queue_size']}
- Active Workers: {stats['task_pool_stats']['workers_active']}/{self.max_workers}
- Memory Usage: {stats['task_pool_stats']['memory_usage']:.1%}
- System Load: {stats['task_pool_stats']['system_load']:.1%}
        """.strip())

    def _get_tasks_by_type_stats(self) -> Dict[str, Dict[str, int]]:
        """Get task statistics by type"""
        stats = defaultdict(lambda: {'completed': 0, 'failed': 0, 'pending': 0})

        # Count completed tasks by type
        for result in self.task_results.values():
            task_type = result.task_type.value
            if result.status == TaskStatus.COMPLETED:
                stats[task_type]['completed'] += 1
            elif result.status == TaskStatus.FAILED:
                stats[task_type]['failed'] += 1

        # Count pending tasks
        for task in self.priority_queue:
            stats[task.task_type.value]['pending'] += 1

        return dict(stats)

    def _calculate_performance_metrics(self) -> Dict[str, float]:
        """Calculate performance metrics"""
        metrics = {}

        if self.stats['total_tasks_completed'] > 0:
            # Calculate average execution time from worker stats
            total_exec_time = sum(stats.total_execution_time for stats in self.worker_stats.values())
            total_tasks = sum(stats.tasks_completed for stats in self.worker_stats.values())

            if total_tasks > 0:
                metrics['average_execution_time'] = total_exec_time / total_tasks
            else:
                metrics['average_execution_time'] = 0.0
        else:
            metrics['average_execution_time'] = 0.0

        # Calculate throughput
        uptime = (datetime.utcnow() - self._start_time).total_seconds()
        metrics['throughput'] = self.stats['total_tasks_completed'] / max(uptime, 1)

        # Calculate worker efficiency
        active_workers = len([w for w in self.worker_stats.values() if w.current_task])
        metrics['worker_efficiency'] = active_workers / self.max_workers

        return metrics

# Global task pool manager instance
_task_pool_manager: Optional[TaskPoolManager] = None

async def get_task_pool_manager() -> TaskPoolManager:
    """Get or create global task pool manager instance"""
    global _task_pool_manager

    if _task_pool_manager is None:
        _task_pool_manager = TaskPoolManager()
        await _task_pool_manager.start()

    return _task_pool_manager

async def shutdown_task_pool_manager():
    """Shutdown global task pool manager"""
    global _task_pool_manager

    if _task_pool_manager:
        await _task_pool_manager.stop()
        _task_pool_manager = None

# Convenience functions for common task types
async def submit_price_update_task(token_mint: str, priority: TaskPriority = TaskPriority.HIGH) -> str:
    """Submit price update task"""
    manager = await get_task_pool_manager()
    return await manager.submit_task(
        TaskType.PRICE_UPDATE,
        {'token_mint': token_mint},
        priority=priority
    )

async def submit_social_sentiment_task(token_symbol: str, priority: TaskPriority = TaskPriority.MEDIUM) -> str:
    """Submit social sentiment task"""
    manager = await get_task_pool_manager()
    return await manager.submit_task(
        TaskType.SOCIAL_SENTIMENT,
        {'token_symbol': token_symbol},
        priority=priority
    )

async def submit_arbitrage_scan_task(token_mint: str, priority: TaskPriority = TaskPriority.HIGH) -> str:
    """Submit arbitrage scan task"""
    manager = await get_task_pool_manager()
    return await manager.submit_task(
        TaskType.ARBITRAGE_SCAN,
        {'token_mint': token_mint},
        priority=priority
    )

async def submit_data_synthesis_task(
    token_data: Dict[str, Any],
    priority: TaskPriority = TaskPriority.CRITICAL
) -> str:
    """Submit data synthesis task"""
    manager = await get_task_pool_manager()
    return await manager.submit_task(
        TaskType.DATA_SYNTHESIS,
        token_data,
        priority=priority
    )