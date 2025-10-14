import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const healthCheckDuration = new Trend('health_check_duration');
const readyCheckDuration = new Trend('ready_check_duration');
const metricsCheckDuration = new Trend('metrics_check_duration');
const totalRequests = new Counter('total_requests');
const errorRate = new Rate('errors');

// Test configuration
export const options = {
  stages: [
    { duration: '30s', target: 10 },   // Ramp up to 10 VUs
    { duration: '1m', target: 10 },    // Stay at 10 VUs
    { duration: '30s', target: 50 },   // Ramp up to 50 VUs
    { duration: '2m', target: 50 },    // Stay at 50 VUs
    { duration: '30s', target: 100 },  // Ramp up to 100 VUs
    { duration: '2m', target: 100 },   // Stay at 100 VUs
    { duration: '30s', target: 0 },    // Ramp down to 0 VUs
  ],
  thresholds: {
    http_req_duration: ['p(95)<200'],     // 95% of requests under 200ms
    http_req_failed: ['rate<0.01'],       // Error rate under 1%
    errors: ['rate<0.01'],                 // Custom error rate under 1%
    health_check_duration: ['p(95)<100'],  // Health checks under 100ms
    ready_check_duration: ['p(95)<150'],   // Ready checks under 150ms
    metrics_check_duration: ['p(95)<300'], // Metrics checks under 300ms
    total_requests: ['count>1000'],        // At least 1000 total requests
  },
};

// Base URL for API endpoints
const BASE_URL = 'http://localhost:8082';

// Test data
const endpoints = [
  { path: '/health', weight: 70, name: 'health' },      // 70% health checks
  { path: '/ready', weight: 20, name: 'ready' },        // 20% ready checks
  { path: '/metrics', weight: 10, name: 'metrics' },    // 10% metrics checks
];

// Choose endpoint based on weights
function chooseEndpoint() {
  const totalWeight = endpoints.reduce((sum, ep) => sum + ep.weight, 0);
  let random = Math.random() * totalWeight;

  for (const endpoint of endpoints) {
    random -= endpoint.weight;
    if (random <= 0) {
      return endpoint;
    }
  }
  return endpoints[0]; // fallback
}

// Main test function
export default function () {
  const endpoint = chooseEndpoint();
  const url = `${BASE_URL}${endpoint.path}`;
  const startTime = Date.now();

  let response;
  let success = false;

  try {
    // Make HTTP request
    response = http.get(url, {
      timeout: '5s',
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'k6-load-test/1.0',
      },
    });

    // Record custom metrics
    const duration = Date.now() - startTime;

    switch (endpoint.name) {
      case 'health':
        healthCheckDuration.add(duration);
        break;
      case 'ready':
        readyCheckDuration.add(duration);
        break;
      case 'metrics':
        metricsCheckDuration.add(duration);
        break;
    }

    totalRequests.add(1);

    // Validate response
    success = check(response, {
      'status is 200': (r) => r.status === 200,
      'response time < 500ms': (r) => r.timings.duration < 500,
      'response body not empty': (r) => r.body.length > 0,
      'content-type is json': (r) => r.headers['Content-Type'].includes('application/json'),
    });

    // Additional checks based on endpoint
    if (success && response.status === 200) {
      try {
        const body = JSON.parse(response.body);

        switch (endpoint.name) {
          case 'health':
            success = check(body, {
              'health status exists': (b) => b.status !== undefined,
              'health status is healthy': (b) => b.status === 'healthy',
              'timestamp exists': (b) => b.timestamp !== undefined,
            });
            break;

          case 'ready':
            success = check(body, {
              'ready status exists': (b) => b.ready !== undefined,
              'ready is true': (b) => b.ready === true,
              'components exist': (b) => b.components !== undefined,
            });
            break;

          case 'metrics':
            success = check(body, {
              'metrics object exists': (b) => typeof b === 'object',
              'has performance metrics': (b) => b.performance !== undefined,
              'has system metrics': (b) => b.system !== undefined,
            });
            break;
        }
      } catch (e) {
        console.error(`Failed to parse JSON response from ${endpoint.path}:`, e);
        success = false;
      }
    }

  } catch (error) {
    console.error(`Request to ${endpoint.path} failed:`, error);
    success = false;
  }

  // Record error rate
  if (!success) {
    errorRate.add(1);
  }

  // Small sleep between requests
  sleep(Math.random() * 0.1 + 0.05); // 50-150ms random sleep
}

// Setup function
export function setup() {
  console.log('Starting API load test...');
  console.log(`Target URL: ${BASE_URL}`);
  console.log('Test will make requests to /health, /ready, and /metrics endpoints');
}

// Teardown function
export function teardown(data) {
  console.log('API load test completed');
  console.log(`Total requests made: ${totalRequests.count}`);
  console.log(`Error rate: ${(errorRate.rate * 100).toFixed(2)}%`);

  // Log performance metrics
  console.log('Performance Summary:');
  console.log(`  Health check - p95: ${healthCheckDuration.p(95).toFixed(2)}ms`);
  console.log(`  Ready check - p95: ${readyCheckDuration.p(95).toFixed(2)}ms`);
  console.log(`  Metrics check - p95: ${metricsCheckDuration.p(95).toFixed(2)}ms`);
}