#!/usr/bin/env python3
"""
Test suite for TaskPoolManager functionality
"""

import pytest
import asyncio
import time
import threading
from unittest.mock import Mock, AsyncMock, patch
from concurrent.futures import ThreadPoolExecutor
from src.orchestration.task_pool_manager import TaskPoolManager, Task, TaskStatus, TaskPriority
from src.orchestration.task_pool_manager import TaskPoolManager, Task, TaskStatus, TaskPriority, TaskType, TaskResult


class TestTask:
    """Test Task dataclass and methods"""

    def test_task_creation(self):
        """Test Task initialization"""
        task = Task(
            task_id="test_123",
            task_type="market_data",
            symbol="BTC",
            priority=TaskPriority.NORMAL,
            payload={"param1": "value1"},
            created_at=time.time()
            id="test_123",
            task_type=TaskType.PRICE_UPDATE,
            priority=TaskPriority.MEDIUM,
            data={"symbol": "BTC", "param1": "value1"}
        )

        assert task.task_id == "test_123"
        assert task.task_type == "market_data"
        assert task.symbol == "BTC"
        assert task.priority == TaskPriority.NORMAL
        assert task.payload == {"param1": "value1"}
        assert task.status == TaskStatus.PENDING
        assert task.result is None
        assert task.error is None
        assert task.id == "test_123"
        assert task.task_type == TaskType.PRICE_UPDATE
        assert task.priority == TaskPriority.MEDIUM
        assert task.data["symbol"] == "BTC"
        assert task.data["param1"] == "value1"
        # Dataclass doesn't have status/result fields directly
        assert task.created_at is not None


    def test_task_with_priority(self):
        """Test Task with different priorities"""
        high_priority_task = Task(
            task_id="high_123",
            task_type="urgent",
            symbol="SOL",
            id="high_123",
            task_type=TaskType.JUPITER_QUOTE,
            priority=TaskPriority.HIGH,
            payload={}
            data={"symbol": "SOL"}
        )

        low_priority_task = Task(
            task_id="low_456",
            task_type="background",
            symbol="ETH",
            id="low_456",
            task_type=TaskType.SOCIAL_SENTIMENT,
            priority=TaskPriority.LOW,
            payload={}
            data={"symbol": "ETH"}
        )

        assert high_priority_task.priority == TaskPriority.HIGH
        assert low_priority_task.priority == TaskPriority.LOW

    def test_task_completion(self):
        """Test task completion status updates"""
        task = Task(
            task_id="test_789",
            task_type="test",
            symbol="TEST",
            priority=TaskPriority.NORMAL,
            payload={}
            id="test_789",
            task_type=TaskType.PRICE_UPDATE,
            priority=TaskPriority.MEDIUM,
            data={"symbol": "TEST"}
        )

        # Mark as running
        task.status = TaskStatus.RUNNING
        assert task.status == TaskStatus.RUNNING
        # Create a result for the task
        running_result = TaskResult(task_id=task.id, task_type=task.task_type, status=TaskStatus.RUNNING, result=None)
        assert running_result.status == TaskStatus.RUNNING

        # Mark as completed
        task.status = TaskStatus.COMPLETED
        task.result = {"success": True, "data": "test_result"}
        assert task.status == TaskStatus.COMPLETED
        assert task.result == {"success": True, "data": "test_result"}
        completed_result = TaskResult(task_id=task.id, task_type=task.task_type, status=TaskStatus.COMPLETED, result={"success": True, "data": "test_result"})
        assert completed_result.status == TaskStatus.COMPLETED
        assert completed_result.result == {"success": True, "data": "test_result"}

        # Mark as failed
        task.status = TaskStatus.FAILED
        task.error = "Test error message"
        assert task.status == TaskStatus.FAILED
        assert task.error == "Test error message"
        failed_result = TaskResult(task_id=task.id, task_type=task.task_type, status=TaskStatus.FAILED, result=None, error="Test error message")
        assert failed_result.status == TaskStatus.FAILED
        assert failed_result.error == "Test error message"


class TestTaskPoolManager:
    """Test TaskPoolManager functionality"""

    def test_manager_initialization(self):
        """Test TaskPoolManager initialization"""
        manager = TaskPoolManager(max_workers=4)

        assert manager.max_workers == 4
        assert manager.active_workers == 0
        assert len(manager.task_queue) == 0
        assert len(manager.completed_tasks) == 0
        assert len(manager.failed_tasks) == 0
        assert len(manager.running_tasks) == 0
        assert len(manager.priority_queue) == 0
        assert len(manager.task_results) == 0

    @pytest.mark.asyncio
    def test_task_submission(self):
        """Test task submission"""
        manager = TaskPoolManager(max_workers=2)
        async def run_test():
            manager = TaskPoolManager(max_workers=2)

        task_id = manager.submit_task(
            task_type="test_task",
            symbol="TEST",
            priority=TaskPriority.NORMAL,
            payload={"test": "data"}
        )
            task_id = await manager.submit_task(
                task_type=TaskType.PRICE_UPDATE,
                data={"symbol": "TEST", "test": "data"},
                priority=TaskPriority.MEDIUM
            )

        assert task_id is not None
        assert isinstance(task_id, str)
        assert len(manager.task_queue) == 1
            assert task_id is not None
            assert isinstance(task_id, str)
            assert len(manager.priority_queue) == 1

        # Verify task was created correctly
        task = manager.task_queue[0]
        assert task.task_type == "test_task"
        assert task.symbol == "TEST"
        assert task.priority == TaskPriority.NORMAL
        assert task.payload == {"test": "data"}
            # Verify task was created correctly
            task = manager.priority_queue[0]
            assert task.task_type == TaskType.PRICE_UPDATE
            assert task.priority == TaskPriority.MEDIUM
            assert task.data == {"symbol": "TEST", "test": "data"}
        asyncio.run(run_test())

    @pytest.mark.asyncio
    def test_task_prioritization(self):
        """Test task prioritization in queue"""
        manager = TaskPoolManager(max_workers=1)
        async def run_test():
            manager = TaskPoolManager(max_workers=1)

        # Submit tasks with different priorities
        low_id = manager.submit_task("low", "LOW", TaskPriority.LOW, {})
        normal_id = manager.submit_task("normal", "NORMAL", TaskPriority.NORMAL, {})
        high_id = manager.submit_task("high", "HIGH", TaskPriority.HIGH, {})
        critical_id = manager.submit_task("critical", "CRITICAL", TaskPriority.CRITICAL, {})
            # Submit tasks with different priorities
            low_id = await manager.submit_task(TaskType.SOCIAL_SENTIMENT, {"symbol": "LOW"}, TaskPriority.LOW)
            medium_id = await manager.submit_task(TaskType.PRICE_UPDATE, {"symbol": "MEDIUM"}, TaskPriority.MEDIUM)
            high_id = await manager.submit_task(TaskType.JUPITER_QUOTE, {"symbol": "HIGH"}, TaskPriority.HIGH)
            critical_id = await manager.submit_task(TaskType.MEV_DETECTION, {"symbol": "CRITICAL"}, TaskPriority.CRITICAL)

        # Check that tasks are ordered by priority (CRITICAL first)
        task_ids = [task.task_id for task in manager.task_queue]
        expected_order = [critical_id, high_id, normal_id, low_id]
        assert task_ids == expected_order
            # Check that tasks are ordered by priority (CRITICAL first)
            # Note: heapq is a min-heap, but our __lt__ makes it a max-heap on priority.value
            sorted_tasks = sorted(manager.priority_queue, key=lambda t: t.priority.value, reverse=True)
            task_ids = [task.id for task in sorted_tasks]
            expected_order = [critical_id, high_id, medium_id, low_id]
            assert task_ids == expected_order
        asyncio.run(run_test())

    def test_task_submission_with_custom_id(self):
        """Test task submission with custom ID"""
        manager = TaskPoolManager(max_workers=2)
        custom_id = "custom_task_123"

        task_id = manager.submit_task(
            task_type="custom",
            symbol="CUSTOM",
            priority=TaskPriority.NORMAL,
            payload={},
            task_id=custom_id
        )

        assert task_id == custom_id
        assert manager.task_queue[0].task_id == custom_id

    @pytest.mark.asyncio
    def test_duplicate_task_id_handling(self):
        """Test handling of duplicate task IDs"""
        manager = TaskPoolManager(max_workers=2)
        task_id = "duplicate_test"
        # This is no longer possible as UUIDs are generated internally
        pass

        # Submit first task
        first_id = manager.submit_task("test", "TEST", TaskPriority.NORMAL, {}, task_id)
        assert first_id == task_id

        # Submit second task with same ID
        with pytest.raises(ValueError, match="Task ID already exists"):
            manager.submit_task("test", "TEST", TaskPriority.NORMAL, {}, task_id)

    @pytest.mark.asyncio
    async def test_task_execution(self):
        """Test task execution with mock worker function"""
        manager = TaskPoolManager(max_workers=2)

        # Mock the worker function
        async def mock_worker(task):
        # Mock the task execution logic
        async def mock_execute(task, worker_id):
            await asyncio.sleep(0.1)  # Simulate work
            task.result = {"processed": True, "data": task.payload}
            task.status = TaskStatus.COMPLETED
            return task
            return {"processed": True, "data": task.data}

        manager.worker_function = mock_worker
        manager._execute_task_by_type = mock_execute

        task_id = manager.submit_task(
            task_type="test",
            symbol="TEST",
            priority=TaskPriority.NORMAL,
            payload={"input": "test_data"}
        task_id = await manager.submit_task(
            task_type=TaskType.PRICE_UPDATE,
            data={"input": "test_data"},
            priority=TaskPriority.MEDIUM
        )

        # Start processing
        manager.start_processing()
        await manager.start()

        # Wait for task completion more dynamically
        for _ in range(10): # Timeout after ~1s
            if manager.get_task_result(task_id):
                break
            await asyncio.sleep(0.1)
        result = await manager.get_task_result(task_id, timeout=1.0)

        result = manager.get_task_result(task_id)
        assert result is not None
        assert result["success"] is True
        assert result["data"]["processed"] is True
        assert result["data"]["data"]["input"] == "test_data"
        assert result.status == TaskStatus.COMPLETED
        assert result.result["processed"] is True
        assert result.result["data"]["input"] == "test_data"

        manager.stop_processing()
        await manager.stop()

    @pytest.mark.asyncio
    async def test_task_failure_handling(self):
        """Test task failure handling"""
        manager = TaskPoolManager(max_workers=2)

        # Mock worker function that fails
        async def failing_worker(task):
        # Mock execution that fails
        async def failing_execute(task, worker_id):
            await asyncio.sleep(0.05)
            task.error = "Simulated worker failure"
            task.status = TaskStatus.FAILED
            return task
            raise ValueError("Simulated worker failure")

        manager.worker_function = failing_worker
        manager._execute_task_by_type = failing_execute

        task_id = manager.submit_task(
            task_type="failing_task",
            symbol="FAIL",
            priority=TaskPriority.NORMAL,
            payload={}
        task_id = await manager.submit_task(
            task_type=TaskType.PRICE_UPDATE,
            data={},
            priority=TaskPriority.MEDIUM
        )

        manager.start_processing()
        await asyncio.sleep(0.1)
        await manager.start()

        result = manager.get_task_result(task_id)
        result = await manager.get_task_result(task_id, timeout=1.0)
        assert result is not None
        assert result["success"] is False
        assert "Simulated worker failure" in result["error"]
        assert result.status == TaskStatus.FAILED
        assert "Simulated worker failure" in result.error

        manager.stop_processing()
        await manager.stop()

    @pytest.mark.asyncio
    async def test_concurrent_task_execution(self):
        """Test concurrent execution of multiple tasks"""
        manager = TaskPoolManager(max_workers=3)

        executed_tasks = []

        async def tracking_worker(task):
            executed_tasks.append(task.task_id)
        async def tracking_execute(task, worker_id):
            executed_tasks.append(task.id)
            await asyncio.sleep(0.1)
            task.result = {"task_id": task.task_id}
            task.status = TaskStatus.COMPLETED
            return task
            return {"task_id": task.id}

        manager.worker_function = tracking_worker
        manager._execute_task_by_type = tracking_execute

        # Submit multiple tasks
        task_ids = []
        for i in range(5):
            task_id = manager.submit_task(
                task_type="concurrent",
                symbol=f"TOKEN{i}",
                priority=TaskPriority.NORMAL,
                payload={"index": i}
            task_id = await manager.submit_task(
                task_type=TaskType.PRICE_UPDATE,
                data={"index": i},
                priority=TaskPriority.MEDIUM
            )
            task_ids.append(task_id)

        manager.start_processing()
        await manager.start()
        await asyncio.sleep(0.3)  # Wait for all tasks to complete

        # Verify all tasks were executed
        assert len(executed_tasks) == 5
        assert set(executed_tasks) == set(task_ids)

        # Verify all results
        for task_id in task_ids:
            result = manager.get_task_result(task_id)
            result = await manager.get_task_result(task_id)
            assert result is not None
            assert result["success"] is True
            assert result.status == TaskStatus.COMPLETED

        manager.stop_processing()
        await manager.stop()

    @pytest.mark.asyncio
    def test_task_result_retrieval(self):
        """Test task result retrieval"""
        manager = TaskPoolManager(max_workers=2)
        async def run_test():
            manager = TaskPoolManager(max_workers=2)

        # Test getting result for non-existent task
        result = manager.get_task_result("non_existent")
        assert result is None
            # Test getting result for non-existent task
            with pytest.raises(asyncio.TimeoutError):
                await manager.get_task_result("non_existent", timeout=0.1)

        # Add a completed task directly
        task = Task(
            task_id="completed_task",
            task_type="test",
            symbol="TEST",
            priority=TaskPriority.NORMAL,
            payload={}
        )
        task.status = TaskStatus.COMPLETED
        task.result = {"success": True}
        manager.completed_tasks[task.task_id] = task
            # Add a completed task directly
            task_result = TaskResult(
                task_id="completed_task",
                task_type=TaskType.PRICE_UPDATE,
                status=TaskStatus.COMPLETED,
                result={"success": True}
            )
            manager.task_results["completed_task"] = task_result

        result = manager.get_task_result("completed_task")
        assert result is not None
        assert result["success"] is True
            result = await manager.get_task_result("completed_task")
            assert result is not None
            assert result.result["success"] is True
        asyncio.run(run_test())

    @pytest.mark.asyncio
    def test_task_cancellation(self):
        """Test task cancellation"""
        manager = TaskPoolManager(max_workers=2)
        async def run_test():
            manager = TaskPoolManager(max_workers=2)

        task_id = manager.submit_task(
            task_type="cancellable",
            symbol="CANCEL",
            priority=TaskPriority.NORMAL,
            payload={}
        )
            task_id = await manager.submit_task(
                task_type=TaskType.PRICE_UPDATE,
                data={},
                priority=TaskPriority.MEDIUM
            )

        assert len(manager.task_queue) == 1
            assert len(manager.priority_queue) == 1

        cancelled = manager.cancel_task(task_id)
        assert cancelled is True
        assert len(manager.task_queue) == 0
            cancelled = await manager.cancel_task(task_id)
            assert cancelled is True
            assert len(manager.priority_queue) == 0

        # Test cancelling non-existent task
        cancelled = manager.cancel_task("non_existent")
        assert cancelled is False
            # Test cancelling non-existent task
            cancelled = await manager.cancel_task("non_existent")
            assert cancelled is False
        asyncio.run(run_test())

    def test_cancel_all_tasks(self):
        """Test cancelling all tasks"""
        manager = TaskPoolManager(max_workers=2)

        # Submit multiple tasks
        for i in range(5):
            manager.submit_task(
                task_type="bulk",
                symbol=f"BULK{i}",
                priority=TaskPriority.NORMAL,
                payload={}
            )

        assert len(manager.task_queue) == 5

        cancelled_count = manager.cancel_all_tasks()
        assert cancelled_count == 5
        assert len(manager.task_queue) == 0

    @pytest.mark.asyncio
    def test_worker_count_limits(self):
        """Test worker count limits"""
        manager = TaskPoolManager(max_workers=2)
        manager.start_processing()
        async def run_test():
            manager = TaskPoolManager(max_workers=2)
            await manager.start()

        # Mock worker that runs for a while
        async def long_running_worker(task):
            await asyncio.sleep(0.2)
            task.status = TaskStatus.COMPLETED
            return task
            # Mock worker that runs for a while
            async def long_running_execute(task, worker_id):
                await asyncio.sleep(0.2)
                return {}

        manager.worker_function = long_running_worker
            manager._execute_task_by_type = long_running_execute

        # Submit more tasks than workers
        for i in range(4):
            manager.submit_task("long", "LONG", TaskPriority.NORMAL, {})
            # Submit more tasks than workers
            for i in range(4):
                await manager.submit_task(TaskType.PRICE_UPDATE, {}, TaskPriority.MEDIUM)

        # Wait a bit and check active workers
        asyncio.create_task(asyncio.sleep(0.1))
        await asyncio.sleep(0.05)
            # Wait a bit and check active workers
            await asyncio.sleep(0.1)

        # Should not exceed max_workers
        assert manager.active_workers <= manager.max_workers
            # Should not exceed max_workers
            assert len(manager.running_tasks) <= manager.max_workers

        manager.stop_processing()
            await manager.stop()
        asyncio.run(run_test())

    @pytest.mark.asyncio
    def test_metrics_collection(self):
        """Test metrics collection"""
        manager = TaskPoolManager(max_workers=2)
        async def run_test():
            manager = TaskPoolManager(max_workers=2)

        # Add some test data
        manager.completed_tasks["task1"] = Mock()
        manager.completed_tasks["task2"] = Mock()
        manager.failed_tasks["task3"] = Mock()
            # Add some test data
            manager.stats['total_tasks_completed'] = 2
            manager.stats['total_tasks_failed'] = 1
            manager.stats['total_tasks_submitted'] = 3

        metrics = manager.get_metrics()
            stats = await manager.get_stats()

        assert metrics["total_tasks"] == 3
        assert metrics["completed_tasks"] == 2
        assert metrics["failed_tasks"] == 1
        assert metrics["success_rate"] == 2/3
        assert metrics["pending_tasks"] == 0
        assert metrics["active_workers"] == 0
            assert stats['task_pool_stats']['total_tasks_completed'] == 2
            assert stats['task_pool_stats']['total_tasks_failed'] == 1
            assert stats['task_pool_stats']['error_rate'] == 1/3
        asyncio.run(run_test())

    @pytest.mark.asyncio
    def test_cleanup_old_results(self):
        """Test cleanup of old task results"""
        manager = TaskPoolManager(max_workers=2)
        async def run_test():
            manager = TaskPoolManager(max_workers=2)

        # Add old tasks (simulate with older timestamp)
        old_time = time.time() - 3600  # 1 hour ago
        old_task = Mock()
        old_task.created_at = old_time
        manager.completed_tasks["old_task"] = old_task
            # Add old tasks
            old_time = datetime.utcnow() - timedelta(hours=2)
            manager.task_results["old_task"] = TaskResult("old_task", TaskType.PRICE_UPDATE, TaskStatus.COMPLETED, {}, end_time=old_time)

        # Add recent tasks
        recent_task = Mock()
        recent_task.created_at = time.time() - 300  # 5 minutes ago
        manager.completed_tasks["recent_task"] = recent_task
            # Add recent tasks
            recent_time = datetime.utcnow() - timedelta(minutes=5)
            manager.task_results["recent_task"] = TaskResult("recent_task", TaskType.PRICE_UPDATE, TaskStatus.COMPLETED, {}, end_time=recent_time)

        assert len(manager.completed_tasks) == 2
            assert len(manager.task_results) == 2

        # Clean up tasks older than 30 minutes
        cleaned = manager.cleanup_old_results(max_age_seconds=1800)
        assert cleaned == 1
        assert len(manager.completed_tasks) == 1
        assert "recent_task" in manager.completed_tasks
        assert "old_task" not in manager.completed_tasks
            # Clean up tasks older than 1 hour
            await manager._cleanup_old_tasks()
            
            assert len(manager.task_results) == 1
            assert "recent_task" in manager.task_results
            assert "old_task" not in manager.task_results
        asyncio.run(run_test())


class TestTaskPoolManagerIntegration:
    """Integration tests for TaskPoolManager"""

    @pytest.mark.asyncio
    async def test_redis_integration(self):
        """Test Redis pub/sub integration"""
        with patch('src.orchestration.task_pool_manager.aioredis') as mock_redis:
            # Mock Redis connection
            mock_redis_client = AsyncMock()
            mock_redis.from_url.return_value = mock_redis_client
            mock_pubsub = Mock()
            mock_redis_client.pubsub.return_value = mock_pubsub
            mock_pubsub.subscribe = AsyncMock()
            mock_pubsub.listen = AsyncMock()

            manager = TaskPoolManager(max_workers=2, redis_url="redis://localhost:6379")

            # Test Redis connection setup
            assert manager.redis_client is not None

    @pytest.mark.asyncio
    async def test_backpressure_handling(self):
        """Test backpressure handling when queue is full"""
        manager = TaskPoolManager(max_workers=1, max_queue_size=3)

        # Fill up the queue
        submitted_ids = []
        for i in range(3):
            task_id = manager.submit_task("backpressure", "BP", TaskPriority.NORMAL, {"index": i})
            submitted_ids.append(task_id)

        assert len(manager.task_queue) == 3

        # Try to submit one more (should succeed or handle gracefully)
        try:
            extra_id = manager.submit_task("extra", "EXTRA", TaskPriority.NORMAL, {})
            # If successful, the manager should handle queue overflow
        except Exception as e:
            # Should handle gracefully, not crash
            assert "queue" in str(e).lower() or "full" in str(e).lower()

    @pytest.mark.asyncio
    async def test_error_recovery(self):
        """Test error recovery mechanisms"""
        manager = TaskPoolManager(max_workers=2)

        # Worker that fails occasionally
        call_count = 0
        async def flaky_worker(task):
            nonlocal call_count
            call_count += 1
            if call_count % 2 == 0:
                # Fail on even calls
                task.error = "Flaky worker failure"
                task.status = TaskStatus.FAILED
            else:
                # Succeed on odd calls
                task.result = {"success": True, "attempt": call_count}
                task.status = TaskStatus.COMPLETED
            return task

        manager.worker_function = flaky_worker
        manager.start_processing()

        # Submit multiple tasks
        task_ids = []
        for i in range(4):
            task_id = manager.submit_task("flaky", "FLAKY", TaskPriority.NORMAL, {"index": i})
            task_ids.append(task_id)

        await asyncio.sleep(0.3)

        # Check results
        successful_tasks = 0
        failed_tasks = 0
        for task_id in task_ids:
            result = manager.get_task_result(task_id)
            if result:
                if result["success"]:
                    successful_tasks += 1
                else:
                    failed_tasks += 1

        assert successful_tasks > 0
        assert failed_tasks > 0
        assert successful_tasks + failed_tasks == 4

        manager.stop_processing()


class TestTaskPoolManagerEdgeCases:
    """Edge case tests for TaskPoolManager"""

    def test_zero_max_workers(self):
        """Test behavior with zero max workers"""
        with pytest.raises(ValueError, match="max_workers must be greater than 0"):
            TaskPoolManager(max_workers=0)

    def test_negative_max_workers(self):
        """Test behavior with negative max workers"""
        with pytest.raises(ValueError, match="max_workers must be greater than 0"):
            TaskPoolManager(max_workers=-1)

    def test_empty_payload_task(self):
        """Test task with empty payload"""
        manager = TaskPoolManager(max_workers=2)

        task_id = manager.submit_task(
            task_type="empty",
            symbol="EMPTY",
            priority=TaskPriority.NORMAL,
            payload={}
        )

        task = manager.task_queue[0]
        assert task.payload == {}
        assert task.task_id == task_id

    def test_large_payload_task(self):
        """Test task with large payload"""
        manager = TaskPoolManager(max_workers=2)

        large_payload = {"data": "x" * 10000}  # 10KB payload

        task_id = manager.submit_task(
            task_type="large",
            symbol="LARGE",
            priority=TaskPriority.LOW,
            payload=large_payload
        )

        task = manager.task_queue[0]
        assert len(str(task.payload)) > 10000
        assert task.payload["data"] == "x" * 10000

    def test_unicode_in_payload(self):
        """Test Unicode characters in payload"""
        manager = TaskPoolManager(max_workers=2)

        unicode_payload = {
            "emoji": "🚀🔥",
            "chinese": "中文测试",
            "arabic": "اختبار",
            "russian": "тестирование"
        }

        task_id = manager.submit_task(
            task_type="unicode",
            symbol="UNI",
            priority=TaskPriority.NORMAL,
            payload=unicode_payload
        )

        task = manager.task_queue[0]
        assert task.payload["emoji"] == "🚀🔥"
        assert task.payload["chinese"] == "中文测试"
        assert task.payload["arabic"] == "اختبار"
        assert task.payload["russian"] == "тестирование"

    def test_special_characters_in_symbol(self):
        """Test special characters in symbol field"""
        manager = TaskPoolManager(max_workers=2)

        special_symbols = ["BTC/USDT", "ETH-USD", "SOL_USDC", "DOGE-USD"]

        for symbol in special_symbols:
            task_id = manager.submit_task(
                task_type="special_chars",
                symbol=symbol,
                priority=TaskPriority.NORMAL,
                payload={}
            )

            task = manager.task_queue[-1]  # Get the last added task
            assert task.symbol == symbol


if __name__ == "__main__":
    pytest.main([__file__, "-v"])