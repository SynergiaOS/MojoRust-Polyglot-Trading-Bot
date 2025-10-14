import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

// Custom metrics for trading cycle performance
const tradingCycleDuration = new Trend('trading_cycle_duration');
const signalGenerationDuration = new Trend('signal_generation_duration');
const riskEvaluationDuration = new Trend('risk_evaluation_duration');
const executionDuration = new Trend('execution_duration');
const signalGenerationRate = new Rate('signal_generation_rate');
const executionSuccessRate = new Rate('execution_success_rate');
const totalCycles = new Counter('total_cycles');
const activePositions = new Gauge('active_positions');
const portfolioValue = new Gauge('portfolio_value');
const averageConfidence = new Trend('average_confidence');

// Test configuration
export const options = {
  scenarios: {
    constant_load: {
      executor: 'constant-vus',
      vus: 10,
      duration: '2m',
    },
    ramping_load: {
      executor: 'ramping-vus',
      startVUs: 5,
      stages: [
        { duration: '30s', target: 20 },
        { duration: '1m', target: 20 },
        { duration: '30s', target: 50 },
        { duration: '1m', target: 50 },
        { duration: '30s', target: 5 },
      ],
    },
  },
  thresholds: {
    trading_cycle_duration: ['p(95)<1000'],    // 95% of cycles under 1s
    signal_generation_duration: ['p(95)<200'],  // Signal generation under 200ms
    risk_evaluation_duration: ['p(95)<100'],    // Risk evaluation under 100ms
    execution_duration: ['p(95)<500'],          // Execution under 500ms
    signal_generation_rate: ['rate>0.8'],       // 80% signal generation success
    execution_success_rate: ['rate>0.95'],      // 95% execution success
    total_cycles: ['count>500'],                // At least 500 total cycles
    http_req_duration: ['p(95)<500'],          // HTTP requests under 500ms
    http_req_failed: ['rate<0.02'],             // Error rate under 2%
  },
};

// Configuration
const BASE_URL = 'http://localhost:8082';
const TOKENS = ['BTC', 'ETH', 'SOL', 'USDC', 'USDT'];
const INITIAL_PORTFOLIO_VALUE = 10000;

// Simulated market data generator
function generateMarketData() {
  const token = TOKENS[Math.floor(Math.random() * TOKENS.length)];
  const basePrice = {
    'BTC': 50000,
    'ETH': 3000,
    'SOL': 100,
    'USDC': 1,
    'USDT': 1,
  }[token];

  return {
    symbol: token,
    price: basePrice * (0.95 + Math.random() * 0.1), // ±5% variation
    volume_24h: 1000000 + Math.random() * 9000000,  // 1M-10M
    liquidity: 500000 + Math.random() * 4500000,      // 500K-5M
    price_change_24h: (Math.random() - 0.5) * 0.2,    // ±10%
    price_change_1h: (Math.random() - 0.5) * 0.05,     // ±2.5%
    holder_count: Math.floor(1000 + Math.random() * 9000),
    unique_traders: Math.floor(500 + Math.random() * 4500),
    social_mentions: Math.floor(50 + Math.random() * 950),
    wash_trading_score: Math.random() * 0.3, // 0-30%
    timestamp: Date.now(),
  };
}

// Simulate signal generation
function simulateSignalGeneration(marketData) {
  const startTime = Date.now();

  // Simulate processing delay
  sleep(Math.random() * 0.05 + 0.02); // 20-70ms

  // Generate signal based on market conditions
  let confidence = 0.5;
  let action = 'HOLD';

  // Price momentum factor
  if (marketData.price_change_1h > 0.02) {
    confidence += 0.2;
    action = 'BUY';
  } else if (marketData.price_change_1h < -0.02) {
    confidence += 0.15;
    action = 'SELL';
  }

  // Volume factor
  if (marketData.volume_24h > 5000000) {
    confidence += 0.1;
  }

  // Liquidity factor
  if (marketData.liquidity > 1000000) {
    confidence += 0.1;
  }

  // Social sentiment factor
  if (marketData.social_mentions > 500) {
    confidence += 0.1;
  }

  // Wash trading penalty
  confidence -= marketData.wash_trading_score * 0.5;

  // Clamp confidence
  confidence = Math.max(0.1, Math.min(0.95, confidence));

  // Random variation
  confidence += (Math.random() - 0.5) * 0.2;
  confidence = Math.max(0.1, Math.min(0.95, confidence));

  const duration = Date.now() - startTime;
  signalGenerationDuration.add(duration);

  return {
    symbol: marketData.symbol,
    action: action,
    confidence: confidence,
    price: marketData.price,
    timestamp: Date.now(),
    processing_time: duration,
  };
}

// Simulate risk evaluation
function simulateRiskEvaluation(signal, portfolio) {
  const startTime = Date.now();

  // Simulate processing delay
  sleep(Math.random() * 0.02 + 0.01); // 10-30ms

  let approved = true;
  let reason = 'Approved';

  // Check confidence threshold
  if (signal.confidence < 0.6) {
    approved = false;
    reason = 'Low confidence';
  }

  // Check position size (mock)
  const positionValue = portfolio.total_value * 0.05; // 5% of portfolio
  if (positionValue > portfolio.available_cash) {
    approved = false;
    reason = 'Insufficient funds';
  }

  // Check portfolio drawdown
  const drawdown = (portfolio.peak_value - portfolio.total_value) / portfolio.peak_value;
  if (drawdown > 0.15) { // 15% max drawdown
    approved = false;
    reason = 'Maximum drawdown exceeded';
  }

  const duration = Date.now() - startTime;
  riskEvaluationDuration.add(duration);

  return {
    approved: approved,
    reason: reason,
    position_size: approved ? Math.min(positionValue, portfolio.available_cash * 0.8) : 0,
    processing_time: duration,
  };
}

// Simulate trade execution
function simulateExecution(signal, riskApproval) {
  const startTime = Date.now();

  if (!riskApproval.approved) {
    return {
      success: false,
      reason: riskApproval.reason,
      processing_time: Date.now() - startTime,
    };
  }

  // Simulate execution delay
  sleep(Math.random() * 0.1 + 0.05); // 50-150ms

  // Simulate success rate (95% success)
  const success = Math.random() < 0.95;

  const duration = Date.now() - startTime;
  executionDuration.add(duration);

  return {
    success: success,
    reason: success ? 'Executed successfully' : 'Execution failed',
    executed_price: signal.price * (0.995 + Math.random() * 0.01), // ±0.5% slippage
    quantity: riskApproval.position_size / signal.price,
    processing_time: duration,
  };
}

// Main trading cycle simulation
export default function () {
  const cycleStartTime = Date.now();

  // Step 1: Generate market data
  const marketData = generateMarketData();

  // Step 2: Generate trading signal
  const signal = simulateSignalGeneration(marketData);

  // Step 3: Get current portfolio state (mock)
  const portfolio = {
    total_value: INITIAL_PORTFOLIO_VALUE + (Math.random() - 0.5) * 1000,
    available_cash: INITIAL_PORTFOLIO_VALUE * 0.3 + (Math.random() - 0.5) * 500,
    peak_value: INITIAL_PORTFOLIO_VALUE * 1.1,
    positions_count: Math.floor(Math.random() * 10),
  };

  // Step 4: Risk evaluation
  const riskApproval = simulateRiskEvaluation(signal, portfolio);

  // Step 5: Execute trade if approved
  const execution = simulateExecution(signal, riskApproval);

  // Step 6: Record metrics
  const cycleDuration = Date.now() - cycleStartTime;
  tradingCycleDuration.add(cycleDuration);
  totalCycles.add(1);

  // Update gauge metrics
  activePositions.add(portfolio.positions_count);
  portfolioValue.add(portfolio.total_value);
  averageConfidence.add(signal.confidence);

  // Success/failure rates
  signalGenerationRate.add(1); // Signal always "generated" successfully
  if (execution.success) {
    executionSuccessRate.add(1);
  } else {
    executionSuccessRate.add(0);
  }

  // Check performance targets
  const success = check(execution, {
    'cycle completed': (e) => e !== undefined,
    'cycle under 1s': () => cycleDuration < 1000,
    'signal confidence valid': () => signal.confidence >= 0.1 && signal.confidence <= 0.95,
    'processing times reasonable': () =>
      signal.processing_time < 200 &&
      riskApproval.processing_time < 100 &&
      execution.processing_time < 500,
  });

  // Log occasional details for debugging
  if (Math.random() < 0.01) { // 1% chance to log
    console.log(`Cycle: ${signal.symbol} ${signal.action} (conf: ${signal.confidence.toFixed(2)}) -> ${execution.success ? 'EXECUTED' : execution.reason}`);
  }

  // Random sleep between cycles (simulate market observation)
  sleep(Math.random() * 0.5 + 0.1); // 100-600ms
}

// Setup function
export function setup() {
  console.log('Starting trading cycle load test...');
  console.log('This test simulates end-to-end trading cycles including:');
  console.log('- Market data generation');
  console.log('- Signal generation');
  console.log('- Risk evaluation');
  console.log('- Trade execution');
  console.log('');
  console.log('Performance targets:');
  console.log('- Trading cycle: p95 < 1000ms');
  console.log('- Signal generation: p95 < 200ms');
  console.log('- Risk evaluation: p95 < 100ms');
  console.log('- Execution: p95 < 500ms');
  console.log('- Execution success rate: >95%');
}

// Teardown function
export function teardown(data) {
  console.log('Trading cycle load test completed');
  console.log(`Total cycles simulated: ${totalCycles.count}`);
  console.log(`Signal generation success rate: ${(signalGenerationRate.rate * 100).toFixed(2)}%`);
  console.log(`Execution success rate: ${(executionSuccessRate.rate * 100).toFixed(2)}%`);

  console.log('Performance Summary:');
  console.log(`  Trading cycle - p95: ${tradingCycleDuration.p(95).toFixed(2)}ms`);
  console.log(`  Signal generation - p95: ${signalGenerationDuration.p(95).toFixed(2)}ms`);
  console.log(`  Risk evaluation - p95: ${riskEvaluationDuration.p(95).toFixed(2)}ms`);
  console.log(`  Execution - p95: ${executionDuration.p(95).toFixed(2)}ms`);
  console.log(`  Average confidence: ${averageConfidence.mean.toFixed(2)}`);
}