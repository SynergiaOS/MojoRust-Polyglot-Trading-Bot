//! Rate limiting and DoS protection utilities
//!
//! Provides various rate limiting algorithms to prevent abuse and
//! protect against denial of service attacks.

use anyhow::{anyhow, Result};
use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// Rate limiting strategies
#[derive(Debug, Clone)]
pub enum RateLimitStrategy {
    TokenBucket,
    SlidingWindow,
    FixedWindow,
    LeakyBucket,
}

/// Main rate limiter
pub struct RateLimiter {
    strategies: HashMap<String, RateLimitStrategy>,
    limits: Arc<Mutex<HashMap<String, RateLimit>>>,
}

impl RateLimiter {
    /// Create new rate limiter
    pub fn new() -> Result<Self> {
        Ok(Self {
            strategies: HashMap::new(),
            limits: Arc::new(Mutex::new(HashMap::new())),
        })
    }

    /// Add rate limit for a client/endpoint
    pub fn add_limit(&mut self, key: &str, strategy: RateLimitStrategy, max_requests: u32, window: Duration) {
        self.strategies.insert(key.to_string(), strategy.clone());

        let rate_limit = RateLimit {
            max_requests,
            window,
            strategy,
            state: RateLimitState::new(),
        };

        self.limits.lock().unwrap().insert(key.to_string(), rate_limit);
    }

    /// Check if request is allowed
    pub fn check_limit(&self, key: &str, identifier: &str) -> Result<bool> {
        let mut limits = self.limits.lock().unwrap();

        if let Some(rate_limit) = limits.get_mut(key) {
            let full_key = format!("{}:{}", key, identifier);

            // Check if we have a per-identifier limit, otherwise use the main limit
            if !limits.contains_key(&full_key) {
                limits.insert(full_key.clone(), rate_limit.clone());
            }

            let limit = limits.get_mut(&full_key).unwrap();
            self.check_rate_limit(limit)
        } else {
            Ok(true) // No limit configured
        }
    }

    /// Reset rate limit for a key
    pub fn reset_limit(&self, key: &str) -> Result<()> {
        let mut limits = self.limits.lock().unwrap();

        if let Some(rate_limit) = limits.get_mut(key) {
            rate_limit.state = RateLimitState::new();
        }

        Ok(())
    }

    /// Get current usage statistics
    pub fn get_usage_stats(&self, key: &str) -> Option<RateLimitStats> {
        let limits = self.limits.lock().unwrap();

        limits.get(key).map(|rate_limit| {
            let current_requests = match &rate_limit.state {
                RateLimitState::TokenBucket { tokens, .. } => rate_limit.max_requests - (*tokens as u32),
                RateLimitState::SlidingWindow { requests, .. } => requests.len() as u32,
                RateLimitState::FixedWindow { requests, .. } => *requests,
                RateLimitState::LeakyBucket { queue, .. } => queue.len() as u32,
            };

            RateLimitStats {
                current_requests,
                max_requests: rate_limit.max_requests,
                window: rate_limit.window,
                reset_time: self.get_reset_time(rate_limit),
            }
        })
    }

    /// Get number of active rate limits
    pub fn get_active_limits(&self) -> usize {
        self.limits.lock().unwrap().len()
    }

    /// Clean up expired rate limits
    pub fn cleanup_expired(&self) {
        let mut limits = self.limits.lock().unwrap();
        let now = Instant::now();

        limits.retain(|_, rate_limit| {
            match &rate_limit.state {
                RateLimitState::SlidingWindow { requests, .. } => {
                    if let Some(&oldest) = requests.front() {
                        now.duration_since(oldest) < rate_limit.window
                    } else {
                        true
                    }
                }
                RateLimitState::FixedWindow { window_start, .. } => {
                    now.duration_since(*window_start) < rate_limit.window
                }
                _ => true,
            }
        });
    }

    fn check_rate_limit(&self, rate_limit: &mut RateLimit) -> Result<bool> {
        let now = Instant::now();

        match rate_limit.strategy {
            RateLimitStrategy::TokenBucket => {
                self.check_token_bucket(rate_limit, now)
            }
            RateLimitStrategy::SlidingWindow => {
                self.check_sliding_window(rate_limit, now)
            }
            RateLimitStrategy::FixedWindow => {
                self.check_fixed_window(rate_limit, now)
            }
            RateLimitStrategy::LeakyBucket => {
                self.check_leaky_bucket(rate_limit, now)
            }
        }
    }

    fn check_token_bucket(&self, rate_limit: &mut RateLimit, now: Instant) -> Result<bool> {
        if let RateLimitState::TokenBucket { tokens, last_refill } = &mut rate_limit.state {
            let time_passed = now.duration_since(*last_refill);
            let tokens_to_add = (time_passed.as_secs_f64() / rate_limit.window.as_secs_f64())
                * rate_limit.max_requests as f64;

            *tokens = (*tokens + tokens_to_add).min(rate_limit.max_requests as f64);
            *last_refill = now;

            if *tokens >= 1.0 {
                *tokens -= 1.0;
                Ok(true)
            } else {
                Ok(false)
            }
        } else {
            Err(anyhow!("Invalid rate limit state for token bucket"))
        }
    }

    fn check_sliding_window(&self, rate_limit: &mut RateLimit, now: Instant) -> Result<bool> {
        if let RateLimitState::SlidingWindow { requests } = &mut rate_limit.state {
            // Remove old requests outside the window
            while let Some(&front) = requests.front() {
                if now.duration_since(front) >= rate_limit.window {
                    requests.pop_front();
                } else {
                    break;
                }
            }

            if requests.len() < rate_limit.max_requests as usize {
                requests.push_back(now);
                Ok(true)
            } else {
                Ok(false)
            }
        } else {
            Err(anyhow!("Invalid rate limit state for sliding window"))
        }
    }

    fn check_fixed_window(&self, rate_limit: &mut RateLimit, now: Instant) -> Result<bool> {
        if let RateLimitState::FixedWindow { requests, window_start } = &mut rate_limit.state {
            if now.duration_since(*window_start) >= rate_limit.window {
                *requests = 0;
                *window_start = now;
            }

            if *requests < rate_limit.max_requests {
                *requests += 1;
                Ok(true)
            } else {
                Ok(false)
            }
        } else {
            Err(anyhow!("Invalid rate limit state for fixed window"))
        }
    }

    fn check_leaky_bucket(&self, rate_limit: &mut RateLimit, now: Instant) -> Result<bool> {
        if let RateLimitState::LeakyBucket { queue, last_leak } = &mut rate_limit.state {
            let time_passed = now.duration_since(*last_leak);
            let leak_rate = rate_limit.window.as_secs_f64() / rate_limit.max_requests as f64;
            let leaks = (time_passed.as_secs_f64() / leak_rate) as usize;

            for _ in 0..leaks.min(queue.len()) {
                queue.pop_front();
            }

            *last_leak = now;

            if queue.len() < rate_limit.max_requests as usize {
                queue.push_back(now);
                Ok(true)
            } else {
                Ok(false)
            }
        } else {
            Err(anyhow!("Invalid rate limit state for leaky bucket"))
        }
    }

    fn get_reset_time(&self, rate_limit: &RateLimit) -> Option<Instant> {
        let now = Instant::now();

        match &rate_limit.state {
            RateLimitState::TokenBucket { tokens, .. } => {
                if *tokens >= 1.0 {
                    None
                } else {
                    Some(now + Duration::from_secs_f64((1.0 - tokens) /
                        (rate_limit.max_requests as f64 / rate_limit.window.as_secs_f64())))
                }
            }
            RateLimitState::SlidingWindow { requests, .. } => {
                if let Some(&oldest) = requests.front() {
                    Some(oldest + rate_limit.window)
                } else {
                    None
                }
            }
            RateLimitState::FixedWindow { window_start, .. } => {
                Some(*window_start + rate_limit.window)
            }
            RateLimitState::LeakyBucket { queue, .. } => {
                if queue.is_empty() {
                    None
                } else {
                    let leak_rate = rate_limit.window.as_secs_f64() / rate_limit.max_requests as f64;
                    Some(now + Duration::from_secs_f64(queue.len() as f64 * leak_rate))
                }
            }
        }
    }
}

/// Rate limit configuration
#[derive(Debug, Clone)]
pub struct RateLimit {
    pub max_requests: u32,
    pub window: Duration,
    pub strategy: RateLimitStrategy,
    pub state: RateLimitState,
}

/// Rate limit state
#[derive(Debug, Clone)]
pub enum RateLimitState {
    TokenBucket {
        tokens: f64,
        last_refill: Instant,
    },
    SlidingWindow {
        requests: VecDeque<Instant>,
    },
    FixedWindow {
        requests: u32,
        window_start: Instant,
    },
    LeakyBucket {
        queue: VecDeque<Instant>,
        last_leak: Instant,
    },
}

impl RateLimitState {
    fn new() -> Self {
        Self::TokenBucket {
            tokens: 0.0,
            last_refill: Instant::now(),
        }
    }
}

/// Rate limit statistics
#[derive(Debug, Clone)]
pub struct RateLimitStats {
    pub current_requests: u32,
    pub max_requests: u32,
    pub window: Duration,
    pub reset_time: Option<Instant>,
}

/// Token bucket rate limiter
pub struct TokenBucket {
    capacity: u32,
    refill_rate: u32,
    tokens: f64,
    last_refill: Instant,
}

impl TokenBucket {
    /// Create new token bucket
    pub fn new(capacity: u32, refill_rate: u32) -> Self {
        Self {
            capacity,
            refill_rate,
            tokens: capacity as f64,
            last_refill: Instant::now(),
        }
    }

    /// Try to consume a token
    pub fn try_consume(&mut self) -> bool {
        self.refill_tokens();

        if self.tokens >= 1.0 {
            self.tokens -= 1.0;
            true
        } else {
            false
        }
    }

    /// Try to consume multiple tokens
    pub fn try_consume_multiple(&mut self, amount: u32) -> bool {
        self.refill_tokens();

        if self.tokens >= amount as f64 {
            self.tokens -= amount as f64;
            true
        } else {
            false
        }
    }

    /// Get current token count
    pub fn available_tokens(&self) -> u32 {
        self.tokens as u32
    }

    /// Get time until next token is available
    pub fn time_until_next_token(&self) -> Duration {
        if self.tokens >= 1.0 {
            Duration::ZERO
        } else {
            let tokens_needed = 1.0 - self.tokens;
            let time_per_token = 1.0 / self.refill_rate as f64;
            Duration::from_secs_f64(tokens_needed * time_per_token)
        }
    }

    fn refill_tokens(&mut self) {
        let now = Instant::now();
        let time_passed = now.duration_since(self.last_refill);
        let tokens_to_add = (time_passed.as_secs_f64() * self.refill_rate as f64) / 1.0;

        self.tokens = (self.tokens + tokens_to_add).min(self.capacity as f64);
        self.last_refill = now;
    }
}

/// Sliding window rate limiter
pub struct SlidingWindow {
    max_requests: u32,
    window: Duration,
    requests: VecDeque<Instant>,
}

impl SlidingWindow {
    /// Create new sliding window
    pub fn new(max_requests: u32, window: Duration) -> Self {
        Self {
            max_requests,
            window,
            requests: VecDeque::new(),
        }
    }

    /// Try to make a request
    pub fn try_request(&mut self) -> bool {
        let now = Instant::now();

        // Remove old requests
        while let Some(&front) = self.requests.front() {
            if now.duration_since(front) >= self.window {
                self.requests.pop_front();
            } else {
                break;
            }
        }

        if self.requests.len() < self.max_requests as usize {
            self.requests.push_back(now);
            true
        } else {
            false
        }
    }

    /// Get current request count
    pub fn current_requests(&self) -> u32 {
        self.requests.len() as u32
    }

    /// Get time until next request is allowed
    pub fn time_until_next_request(&self) -> Option<Duration> {
        if self.requests.len() < self.max_requests as usize {
            None
        } else if let Some(&oldest) = self.requests.front() {
            let reset_time = oldest + self.window;
            let now = Instant::now();

            if reset_time > now {
                Some(reset_time - now)
            } else {
                None
            }
        } else {
            None
        }
    }
}

impl Default for RateLimiter {
    fn default() -> Self {
        Self::new().unwrap()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::thread;

    #[test]
    fn test_token_bucket() {
        let mut bucket = TokenBucket::new(10, 5); // 10 tokens, 5 per second refill

        // Should be able to consume 10 tokens immediately
        for _ in 0..10 {
            assert!(bucket.try_consume());
        }

        // Should not be able to consume more
        assert!(!bucket.try_consume());

        // Should have 0 tokens available
        assert_eq!(bucket.available_tokens(), 0);
    }

    #[test]
    fn test_sliding_window() {
        let mut window = SlidingWindow::new(5, Duration::from_secs(1));

        // Should be able to make 5 requests
        for _ in 0..5 {
            assert!(window.try_request());
        }

        // Should not be able to make more
        assert!(!window.try_request());

        assert_eq!(window.current_requests(), 5);
    }

    #[test]
    fn test_rate_limiter() {
        let mut limiter = RateLimiter::new().unwrap();

        // Add a limit of 10 requests per second
        limiter.add_limit(
            "test_endpoint",
            RateLimitStrategy::TokenBucket,
            10,
            Duration::from_secs(1),
        );

        // Should allow requests up to the limit
        for i in 0..10 {
            assert!(limiter.check_limit("test_endpoint", &format!("client_{}", i)).unwrap());
        }

        // Next request should be rate limited
        assert!(!limiter.check_limit("test_endpoint", "client_11").unwrap());
    }

    #[test]
    fn test_multiple_strategies() {
        let mut limiter = RateLimiter::new().unwrap();

        // Add different strategies for different endpoints
        limiter.add_limit(
            "api_1",
            RateLimitStrategy::TokenBucket,
            10,
            Duration::from_secs(1),
        );

        limiter.add_limit(
            "api_2",
            RateLimitStrategy::SlidingWindow,
            5,
            Duration::from_secs(1),
        );

        // Both should work independently
        assert!(limiter.check_limit("api_1", "client").unwrap());
        assert!(limiter.check_limit("api_2", "client").unwrap());

        // Check stats
        let stats1 = limiter.get_usage_stats("api_1");
        let stats2 = limiter.get_usage_stats("api_2");

        assert!(stats1.is_some());
        assert!(stats2.is_some());
    }

    #[test]
    fn test_cleanup_expired() {
        let mut limiter = RateLimiter::new().unwrap();

        limiter.add_limit(
            "test",
            RateLimitStrategy::SlidingWindow,
            5,
            Duration::from_millis(10),
        );

        // Use the limit
        assert!(limiter.check_limit("test", "client").unwrap());

        // Wait for expiration
        thread::sleep(Duration::from_millis(20));

        // Cleanup
        limiter.cleanup_expired();

        // Should still work after cleanup
        assert!(limiter.check_limit("test", "client").unwrap());
    }
}