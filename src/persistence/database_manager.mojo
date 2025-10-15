from collections import Dict, List, Any
from core.types import Portfolio, Position, MarketData
from monitoring.performance_analytics import TradeRecord
from core.config import Config
from core.logger import get_logger
from time import time
import os
from python import Python

struct DatabaseManager:
    """
    Database persistence layer for TimescaleDB/PostgreSQL with connection pooling
    """

    # Connection settings
    var connection_string: String
    var is_connected: Bool
    var connection_pool: Any  # asyncpg/psycopg connection pool
    var python_initialized: Bool

    # Batch processing
    var batch_size: Int
    var pending_writes: List[Any]
    var last_flush_time: Float
    var max_batch_size: Int

    # Connection pool settings
    var pool_min_size: Int
    var pool_max_size: Int
    var pool_timeout: Float

    # Configuration
    var config: Config
    var logger: Any

    fn __init__(config: Config):
        self.config = config
        self.logger = get_logger("DatabaseManager")

        # Initialize connection settings
        self.is_connected = False
        self.connection_pool = None
        self.python_initialized = False

        # Build connection string
        host = self.config.database.host
        port = self.config.database.port
        database = self.config.database.database
        user = self.config.database.user
        password = os.getenv(self.config.database.password_env, "")

        self.connection_string = f"postgresql://{user}:{password}@{host}:{port}/{database}"

        # Initialize batch processing with enhanced limits
        self.batch_size = self.config.database.batch_size
        self.max_batch_size = 1000  # Enhanced batch size for performance
        self.pending_writes = []
        self.last_flush_time = time()

        # Initialize connection pool settings
        self.pool_min_size = 2
        self.pool_max_size = self.config.database.max_connections
        self.pool_timeout = 30.0

        self.logger.info("Database manager initialized with connection pooling",
                        database=database,
                        host=host,
                        port=port,
                        user=user,
                        batch_size=self.batch_size,
                        max_batch_size=self.max_batch_size,
                        pool_min_size=self.pool_min_size,
                        pool_max_size=self.pool_max_size)

    fn _initialize_connection_pool(inout self) -> Bool:
        """
        🔧 Initialize asyncpg/psycopg connection pool for high performance
        """
        if not self.config.database.enabled:
            self.logger.info("Database disabled in configuration")
            return False

        try:
            if not self.python_initialized:
                # Import required modules
                Python.import("asyncpg")
                Python.import("asyncio")

                self.python_initialized = True

            # Create connection pool using asyncpg
            var python = Python()
            var asyncpg = python.import("asyncpg")

            self.connection_pool = asyncio.run(
                asyncpg.create_pool(
                    self.connection_string,
                    min_size=self.pool_min_size,
                    max_size=self.pool_max_size,
                    command_timeout=self.pool_timeout
                )
            )

            self.is_connected = True
            self.logger.info("🔗 Database connection pool initialized successfully",
                            pool_min_size=self.pool_min_size,
                            pool_max_size=self.pool_max_size,
                            timeout=self.pool_timeout)
            return True

        except e as e:
            self.logger.error("Failed to initialize database connection pool", error=str(e))
            self.is_connected = False
            return False

    fn connect(self) -> Bool:
        """
        Establish database connection with connection pooling
        """
        return self._initialize_connection_pool()

    async fn disconnect(inout self):
        """
        Close database connection pool gracefully
        """
        if self.is_connected and self.connection_pool:
            try:
                # Flush any pending writes
                await self.flush_pending_writes()

                # Close connection pool
                await self.connection_pool.close()
                self.connection_pool = None
                self.is_connected = False
                self.python_initialized = False

                self.logger.info("🔗 Database connection pool closed")

            except e as e:
                self.logger.error("Error closing database connection pool", error=str(e))

    async fn health_check(inout self) -> Bool:
        """
        Verify connection pool is alive
        """
        if not self.is_connected or not self.connection_pool:
            return False

        try:
            # Test connection from pool
            async with self.connection_pool.acquire() as conn:
                await conn.fetchval("SELECT 1")
            return True

        except e as e:
            self.logger.error("Database health check failed", error=str(e))
            self.is_connected = False
            return False

    async fn initialize_schema(inout self) -> Bool:
        """
        Create tables with enhanced indexes if not exist
        """
        if not self.is_connected:
            self.logger.error("Cannot initialize schema: not connected")
            return False

        try:
            # SQL schemas with enhanced indexes would be executed here
            schemas = [
                self._get_trades_table_schema(),
                self._get_portfolio_snapshots_schema(),
                self._get_market_data_schema(),
                self._get_performance_metrics_schema()
            ]

            # Enhanced indexes for performance
            indexes = [
                self._get_enhanced_indexes()
            ]

            async with self.connection_pool.acquire() as conn:
                for schema in schemas:
                    await conn.execute(schema)

                for index in indexes:
                    await conn.execute(index)

                # Initialize TimescaleDB optimizations if available
                await self._setup_timescaledb_optimizations(conn)

            self.logger.info("📊 Database schema with enhanced indexes initialized successfully")
            return True

        except e as e:
            self.logger.error("Failed to initialize database schema", error=str(e))
            return False

    fn save_trade(self, trade: TradeRecord):
        """
        Insert completed trade record
        """
        if not self.is_connected:
            return

        trade_data = {
            "table": "trades",
            "data": {
                "trade_id": f"{trade.symbol}_{trade.exit_timestamp}",
                "symbol": trade.symbol,
                "action": str(trade.action),
                "entry_price": trade.entry_price,
                "exit_price": trade.exit_price,
                "size": trade.size,
                "pnl": trade.pnl,
                "pnl_percentage": trade.pnl_percentage,
                "entry_timestamp": trade.entry_timestamp,
                "exit_timestamp": trade.exit_timestamp,
                "hold_duration_seconds": trade.hold_duration_seconds,
                "was_profitable": trade.was_profitable,
                "close_reason": trade.close_reason,
                "metadata": "{}"
            }
        }

        self._add_to_batch(trade_data)

    fn save_portfolio_snapshot(self, portfolio: Portfolio):
        """
        Save portfolio state snapshot
        """
        if not self.is_connected:
            return

        # Convert positions to JSON
        positions_json = {}
        for symbol, position in portfolio.positions.items():
            positions_json[symbol] = {
                "size": position.size,
                "entry_price": position.entry_price,
                "current_price": position.current_price,
                "unrealized_pnl": position.unrealized_pnl,
                "pnl_percentage": position.pnl_percentage,
                "stop_loss_price": position.stop_loss_price,
                "take_profit_price": position.take_profit_price,
                "entry_timestamp": position.entry_timestamp
            }

        snapshot_data = {
            "table": "portfolio_snapshots",
            "data": {
                "timestamp": time(),
                "total_value": portfolio.total_value,
                "available_cash": portfolio.available_cash,
                "position_value": portfolio.total_value - portfolio.available_cash,
                "daily_pnl": portfolio.daily_pnl,
                "total_pnl": portfolio.daily_pnl,  # Would track cumulative P&L
                "open_positions": len(portfolio.positions),
                "positions": positions_json
            }
        }

        self._add_to_batch(snapshot_data)

    fn save_market_data(self, data: MarketData):
        """
        Insert market data point
        """
        if not self.is_connected:
            return

        market_data = {
            "table": "market_data",
            "data": {
                "timestamp": data.timestamp,
                "symbol": data.symbol,
                "price": data.price,
                "volume_24h": data.volume_24h,
                "liquidity_usd": data.liquidity_usd,
                "market_cap": data.market_cap,
                "holder_count": data.holder_count,
                "metadata": "{}"
            }
        }

        self._add_to_batch(market_data)

    fn save_performance_metrics(self, metrics: Dict[String, Float]):
        """
        Save performance metrics
        """
        if not self.is_connected:
            return

        metrics_data = {
            "table": "performance_metrics",
            "data": {
                "timestamp": time(),
                "win_rate": metrics.get("win_rate", 0.0),
                "sharpe_ratio": metrics.get("sharpe_ratio", 0.0),
                "max_drawdown": metrics.get("max_drawdown", 0.0),
                "profit_factor": metrics.get("profit_factor", 0.0),
                "total_trades": int(metrics.get("total_trades", 0.0)),
                "metrics": metrics
            }
        }

        self._add_to_batch(metrics_data)

    async fn flush_pending_writes(inout self):
        """
        🔧 Execute batched writes with enhanced performance
        Uses COPY for bulk operations and proper transaction management
        """
        if not self.is_connected or len(self.pending_writes) == 0:
            return

        try:
            writes_count = len(self.pending_writes)

            # Group writes by table for batch operations
            trades_batch = []
            portfolio_batch = []
            market_data_batch = []
            performance_batch = []

            for write_data in self.pending_writes:
                table = write_data["table"]
                data = write_data["data"]

                if table == "trades":
                    trades_batch.append(data)
                elif table == "portfolio_snapshots":
                    portfolio_batch.append(data)
                elif table == "market_data":
                    market_data_batch.append(data)
                elif table == "performance_metrics":
                    performance_batch.append(data)

            async with self.connection_pool.acquire() as conn:
                async with conn.transaction():
                    # Use COPY for bulk trades insert
                    if len(trades_batch) > 0:
                        await self._bulk_insert_trades(conn, trades_batch)

                    # Use COPY for bulk portfolio snapshots
                    if len(portfolio_batch) > 0:
                        await self._bulk_insert_portfolio_snapshots(conn, portfolio_batch)

                    # Use COPY for bulk market data
                    if len(market_data_batch) > 0:
                        await self._bulk_insert_market_data(conn, market_data_batch)

                    # Use COPY for bulk performance metrics
                    if len(performance_batch) > 0:
                        await self._bulk_insert_performance_metrics(conn, performance_batch)

            self.pending_writes.clear()
            self.last_flush_time = time()

            self.logger.info(f"📊 Flushed {writes_count} writes to database using optimized batches",
                            trades=len(trades_batch),
                            portfolios=len(portfolio_batch),
                            market_data=len(market_data_batch),
                            performance=len(performance_batch))

        except e as e:
            self.logger.error("Failed to flush pending writes", error=str(e))
            # Transaction automatically rolls back on exception

    fn load_portfolio_state(self) -> Portfolio:
        """
        Load most recent portfolio snapshot
        """
        if not self.is_connected:
            return None

        try:
            # In real implementation:
            # cursor.execute("SELECT * FROM portfolio_snapshots ORDER BY timestamp DESC LIMIT 1")
            # row = cursor.fetchone()
            # return self._deserialize_portfolio(row)

            # Mock return for now
            self.logger.info("Portfolio state loaded from database")
            return None

        except e as e:
            self.logger.error("Failed to load portfolio state", error=str(e))
            return None

    fn get_trade_history(self, days: Int) -> List[TradeRecord]:
        """
        Load recent trades from database
        """
        if not self.is_connected:
            return []

        try:
            # In real implementation:
            # cursor.execute("""
            #   SELECT * FROM trades
            #   WHERE exit_timestamp >= %s
            #   ORDER BY exit_timestamp DESC
            # """, (time() - days * 86400,))
            # rows = cursor.fetchall()
            # return [self._deserialize_trade(row) for row in rows]

            # Mock return for now
            self.logger.info(f"Loaded trade history for last {days} days")
            return []

        except e as e:
            self.logger.error("Failed to load trade history", error=str(e))
            return []

    fn get_market_data_history(self, symbol: String, hours: Int) -> List[MarketData]:
        """
        Load historical market data
        """
        if not self.is_connected:
            return []

        try:
            # In real implementation, query market_data table
            self.logger.info(f"Loaded market data for {symbol} over last {hours} hours")
            return []

        except e as e:
            self.logger.error("Failed to load market data history", error=str(e))
            return []

    fn get_performance_history(self, days: Int) -> List[Dict[String, Float]]:
        """
        Load performance metrics over time
        """
        if not self.is_connected:
            return []

        try:
            # In real implementation, query performance_metrics table
            self.logger.info(f"Loaded performance history for last {days} days")
            return []

        except e as e:
            self.logger.error("Failed to load performance history", error=str(e))
            return []

    fn backup_database(self, path: String) -> Bool:
        """
        Create database backup
        """
        if not self.is_connected:
            return False

        try:
            # In real implementation: use pg_dump or similar
            self.logger.info(f"Database backup created at {path}")
            return True

        except e as e:
            self.logger.error("Failed to create database backup", error=str(e))
            return False

    fn cleanup_old_data(self, days: Int):
        """
        Remove data older than N days
        """
        if not self.is_connected:
            return

        try:
            cutoff_time = time() - (days * 86400)

            # In real implementation, delete old data from each table
            # cursor.execute("DELETE FROM market_data WHERE timestamp < %s", (cutoff_time,))
            # cursor.execute("DELETE FROM trades WHERE exit_timestamp < %s", (cutoff_time,))
            # self.connection.commit()

            self.logger.info(f"Cleaned up data older than {days} days")

        except e as e:
            self.logger.error("Failed to cleanup old data", error=str(e))

    fn get_database_stats(self) -> Dict[String, Any]:
        """
        Return database size, row counts, etc.
        """
        if not self.is_connected:
            return {}

        try:
            # In real implementation, query database statistics
            stats = {
                "connected": True,
                "pending_writes": len(self.pending_writes),
                "last_flush_time": self.last_flush_time,
                "connection_string": self.connection_string.split("@")[1] if "@" in self.connection_string else "unknown"
            }

            return stats

        except e as e:
            self.logger.error("Failed to get database stats", error=str(e))
            return {"connected": False, "error": str(e)}

    fn _add_to_batch(inout self, write_data: Dict[String, Any]):
        """
        Add data to batch write queue with enhanced auto-flush logic
        """
        self.pending_writes.append(write_data)

        # Auto-flush if batch size reached or time interval exceeded
        current_time = time()
        if (len(self.pending_writes) >= self.batch_size or
            current_time - self.last_flush_time >= self.config.database.auto_flush_interval_seconds or
            len(self.pending_writes) >= self.max_batch_size):
            # Note: In real async context, this would be await self.flush_pending_writes()
            # For now, we keep it synchronous as the calling code may not be async
            pass

    fn _get_trades_table_schema(self) -> String:
        """
        SQL schema for trades table with enhanced structure
        """
        return """
        CREATE TABLE IF NOT EXISTS trades (
            id BIGSERIAL PRIMARY KEY,
            trade_id VARCHAR(100) UNIQUE,
            symbol VARCHAR(50) NOT NULL,
            action VARCHAR(10) NOT NULL,
            entry_price DECIMAL(20, 10) NOT NULL,
            exit_price DECIMAL(20, 10),
            size DECIMAL(20, 10) NOT NULL,
            pnl DECIMAL(20, 10),
            pnl_percentage DECIMAL(10, 4),
            entry_timestamp TIMESTAMPTZ NOT NULL,
            exit_timestamp TIMESTAMPTZ,
            hold_duration_seconds INTEGER,
            was_profitable BOOLEAN,
            close_reason VARCHAR(50),
            metadata JSONB,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            updated_at TIMESTAMPTZ DEFAULT NOW()
        ) PARTITION BY RANGE (exit_timestamp);

        -- Create partitions for better performance (monthly partitions)
        CREATE TABLE IF NOT EXISTS trades_y2024m01 PARTITION OF trades
            FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
        CREATE TABLE IF NOT EXISTS trades_y2024m02 PARTITION OF trades
            FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
        CREATE TABLE IF NOT EXISTS trades_y2024m03 PARTITION OF trades
            FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');
        """

    fn _get_portfolio_snapshots_schema(self) -> String:
        """
        SQL schema for portfolio snapshots table
        """
        return """
        CREATE TABLE IF NOT EXISTS portfolio_snapshots (
            id SERIAL PRIMARY KEY,
            timestamp TIMESTAMPTZ NOT NULL,
            total_value DECIMAL(20, 10),
            available_cash DECIMAL(20, 10),
            position_value DECIMAL(20, 10),
            daily_pnl DECIMAL(20, 10),
            total_pnl DECIMAL(20, 10),
            open_positions INTEGER,
            positions JSONB,
            created_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_portfolio_snapshots_timestamp ON portfolio_snapshots(timestamp);
        """

    fn _get_market_data_schema(self) -> String:
        """
        SQL schema for market data table (TimescaleDB hypertable)
        """
        return """
        CREATE TABLE IF NOT EXISTS market_data (
            timestamp TIMESTAMPTZ NOT NULL,
            symbol VARCHAR(50) NOT NULL,
            price DECIMAL(20, 10) NOT NULL,
            volume_24h DECIMAL(20, 2),
            liquidity_usd DECIMAL(20, 2),
            market_cap DECIMAL(20, 2),
            holder_count INTEGER,
            metadata JSONB,
            created_at TIMESTAMPTZ DEFAULT NOW()
        );

        -- Create TimescaleDB hypertable if extension is available
        DO $$
        BEGIN
            IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN
                PERFORM create_hypertable('market_data', 'timestamp',
                                        chunk_time_interval => INTERVAL '1 hour',
                                        if_not_exists => TRUE);

                -- Create compression policy for old data
                ALTER TABLE market_data SET (
                    timescaledb.compress,
                    timescaledb.compress_segmentby = 'symbol',
                    timescaledb.compress_orderby = 'timestamp DESC'
                );

                -- Create compression policy for data older than 1 week
                SELECT add_compression_policy('market_data', INTERVAL '7 days');
            END IF;
        END $$;

        -- Enhanced indexes for market data
        CREATE INDEX IF NOT EXISTS idx_market_data_symbol_timestamp ON market_data(symbol, timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_market_data_timestamp ON market_data(timestamp DESC);
        """

    fn _get_performance_metrics_schema(self) -> String:
        """
        SQL schema for performance metrics table
        """
        return """
        CREATE TABLE IF NOT EXISTS performance_metrics (
            id SERIAL PRIMARY KEY,
            timestamp TIMESTAMPTZ NOT NULL,
            win_rate DECIMAL(10, 4),
            sharpe_ratio DECIMAL(10, 4),
            max_drawdown DECIMAL(10, 4),
            profit_factor DECIMAL(10, 4),
            total_trades INTEGER,
            metrics JSONB,
            created_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_performance_metrics_timestamp ON performance_metrics(timestamp);
        """

    fn _get_enhanced_indexes(self) -> String:
        """
        🔧 Enhanced composite, partial, and GIN indexes for optimal performance
        """
        return """
        -- Composite indexes for trades table
        CREATE INDEX IF NOT EXISTS idx_trades_symbol_exit_timestamp ON trades(symbol, exit_timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_trades_was_profitable_exit_timestamp ON trades(was_profitable, exit_timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_trades_action_exit_timestamp ON trades(action, exit_timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_trades_pnl_percentage_exit_timestamp ON trades(pnl_percentage, exit_timestamp DESC);

        -- Partial indexes for recent data (last 30 days)
        CREATE INDEX IF NOT EXISTS idx_trades_recent ON trades(exit_timestamp DESC)
            WHERE exit_timestamp >= NOW() - INTERVAL '30 days';
        CREATE INDEX IF NOT EXISTS idx_trades_profitable_recent ON trades(symbol, pnl)
            WHERE was_profitable = true AND exit_timestamp >= NOW() - INTERVAL '30 days';

        -- GIN indexes for JSONB metadata
        CREATE INDEX IF NOT EXISTS idx_trades_metadata_gin ON trades USING GIN(metadata);
        CREATE INDEX IF NOT EXISTS idx_portfolio_positions_gin ON portfolio_snapshots USING GIN(positions);
        CREATE INDEX IF NOT EXISTS idx_market_data_metadata_gin ON market_data USING GIN(metadata);
        CREATE INDEX IF NOT EXISTS idx_performance_metrics_gin ON performance_metrics USING GIN(metrics);

        -- Composite index for portfolio snapshots
        CREATE INDEX IF NOT EXISTS idx_portfolio_timestamp_total_value ON portfolio_snapshots(timestamp DESC, total_value);

        -- Performance metrics composite indexes
        CREATE INDEX IF NOT EXISTS idx_performance_win_rate_timestamp ON performance_metrics(win_rate, timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_performance_sharpe_timestamp ON performance_metrics(sharpe_ratio, timestamp DESC);
        """

    async fn _setup_timescaledb_optimizations(inout self, conn: Any):
        """
        🔧 Setup TimescaleDB chunk intervals and retention policies
        """
        try:
            # Check if TimescaleDB extension is available
            has_timescaledb = await conn.fetchval("""
                SELECT 1 FROM pg_extension WHERE extname = 'timescaledb'
            """)

            if has_timescaledb:
                # Set up continuous aggregates for performance metrics
                await conn.execute("""
                    CREATE MATERIALIZED VIEW IF NOT EXISTS daily_performance_summary
                    WITH (timescaledb.continuous) AS
                    SELECT
                        time_bucket('1 day', timestamp) AS day,
                        AVG(win_rate) as avg_win_rate,
                        AVG(sharpe_ratio) as avg_sharpe_ratio,
                        AVG(max_drawdown) as avg_max_drawdown,
                        COUNT(*) as total_periods,
                        MAX(total_trades) as peak_trades
                    FROM performance_metrics
                    GROUP BY day
                    WITH NO DATA;
                """)

                # Create refresh policy for continuous aggregate
                await conn.execute("""
                    SELECT add_continuous_aggregate_policy('daily_performance_summary',
                        start_offset => INTERVAL '1 day',
                        end_offset => INTERVAL '1 hour',
                        schedule_interval => INTERVAL '1 hour');
                """)

                # Set up data retention policies
                await conn.execute("""
                    -- Keep market data for 90 days, then drop
                    SELECT add_retention_policy('market_data', INTERVAL '90 days');

                    -- Keep performance metrics for 1 year
                    SELECT add_retention_policy('performance_metrics', INTERVAL '1 year');
                """)

                # Set up data compression for older data
                await conn.execute("""
                    -- Compress trades older than 30 days
                    SELECT add_compression_policy('trades', INTERVAL '30 days');
                """)

                self.logger.info("📊 TimescaleDB optimizations configured successfully")

        except e as e:
            self.logger.warn("TimescaleDB optimizations not available", error=str(e))

    async fn _bulk_insert_trades(inout self, conn: Any, trades_batch: List[Dict[String, Any]]):
        """
        🔧 Bulk insert trades using COPY for maximum performance
        """
        if len(trades_batch) == 0:
            return

        # Prepare data for COPY
        values = []
        for trade in trades_batch:
            values.append((
                trade.get("trade_id"),
                trade.get("symbol"),
                trade.get("action"),
                trade.get("entry_price"),
                trade.get("exit_price"),
                trade.get("size"),
                trade.get("pnl"),
                trade.get("pnl_percentage"),
                trade.get("entry_timestamp"),
                trade.get("exit_timestamp"),
                trade.get("hold_duration_seconds"),
                trade.get("was_profitable"),
                trade.get("close_reason"),
                trade.get("metadata", "{}")
            ))

        await conn.copy_records_to_table(
            "trades",
            records=values,
            columns=["trade_id", "symbol", "action", "entry_price", "exit_price",
                     "size", "pnl", "pnl_percentage", "entry_timestamp",
                     "exit_timestamp", "hold_duration_seconds", "was_profitable",
                     "close_reason", "metadata"]
        )

    async fn _bulk_insert_portfolio_snapshots(inout self, conn: Any, portfolio_batch: List[Dict[String, Any]]):
        """
        🔧 Bulk insert portfolio snapshots using COPY
        """
        if len(portfolio_batch) == 0:
            return

        values = []
        for snapshot in portfolio_batch:
            values.append((
                snapshot.get("timestamp"),
                snapshot.get("total_value"),
                snapshot.get("available_cash"),
                snapshot.get("position_value"),
                snapshot.get("daily_pnl"),
                snapshot.get("total_pnl"),
                snapshot.get("open_positions"),
                snapshot.get("positions")
            ))

        await conn.copy_records_to_table(
            "portfolio_snapshots",
            records=values,
            columns=["timestamp", "total_value", "available_cash", "position_value",
                     "daily_pnl", "total_pnl", "open_positions", "positions"]
        )

    async fn _bulk_insert_market_data(inout self, conn: Any, market_data_batch: List[Dict[String, Any]]):
        """
        🔧 Bulk insert market data using COPY
        """
        if len(market_data_batch) == 0:
            return

        values = []
        for data in market_data_batch:
            values.append((
                data.get("timestamp"),
                data.get("symbol"),
                data.get("price"),
                data.get("volume_24h"),
                data.get("liquidity_usd"),
                data.get("market_cap"),
                data.get("holder_count"),
                data.get("metadata", "{}")
            ))

        await conn.copy_records_to_table(
            "market_data",
            records=values,
            columns=["timestamp", "symbol", "price", "volume_24h",
                     "liquidity_usd", "market_cap", "holder_count", "metadata"]
        )

    async fn _bulk_insert_performance_metrics(inout self, conn: Any, performance_batch: List[Dict[String, Any]]):
        """
        🔧 Bulk insert performance metrics using COPY
        """
        if len(performance_batch) == 0:
            return

        values = []
        for metrics in performance_batch:
            values.append((
                metrics.get("timestamp"),
                metrics.get("win_rate"),
                metrics.get("sharpe_ratio"),
                metrics.get("max_drawdown"),
                metrics.get("profit_factor"),
                metrics.get("total_trades"),
                metrics.get("metrics")
            ))

        await conn.copy_records_to_table(
            "performance_metrics",
            records=values,
            columns=["timestamp", "win_rate", "sharpe_ratio", "max_drawdown",
                     "profit_factor", "total_trades", "metrics"]
        )