//! Portfolio Manager as per docs/PORTFOLIO_MANAGER_DESIGN.md

use std::collections::{BinaryHeap, HashMap};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use anyhow::{Result, anyhow};

#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Strategy {
    Arbitrage,
    Sniper,
    Momentum,
    MarketMaking,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Priority {
    Low = 1,
    Medium = 2,
    High = 3,
    Critical = 4,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct CapitalRequest {
    pub strategy: Strategy,
    pub token_address: String,
    pub amount: u64, // Using u64 for lamports/smallest unit
    pub priority: Priority,
}

// Implement Ord and PartialOrd manually for BinaryHeap which is a max-heap.
// We want higher priority to be "greater".
impl Ord for CapitalRequest {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.priority.cmp(&other.priority)
    }
}

impl PartialOrd for CapitalRequest {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}


#[derive(Debug, Clone)]
pub struct CapitalReservation {
    pub reservation_id: u64,
    pub strategy: Strategy,
    pub token_address: String,
    pub amount: u64,
    pub expires_at: Instant,
}

pub struct PortfolioManager {
    total_capital: u64,
    allocated_capital: HashMap<u64, CapitalReservation>,
    request_queue: BinaryHeap<CapitalRequest>,
    next_reservation_id: u64,
    reservation_duration: Duration,
}

impl PortfolioManager {
    pub fn new(total_capital: u64, reservation_timeout_seconds: u64) -> Self {
        PortfolioManager {
            total_capital,
            allocated_capital: HashMap::new(),
            request_queue: BinaryHeap::new(),
            next_reservation_id: 1,
            reservation_duration: Duration::from_secs(reservation_timeout_seconds),
        }
    }

    pub fn get_available_capital(&self) -> u64 {
        let allocated: u64 = self.allocated_capital.values().map(|r| r.amount).sum();
        self.total_capital.saturating_sub(allocated)
    }

    pub fn request_capital(&mut self, request: CapitalRequest) {
        self.request_queue.push(request);
    }

    pub fn process_requests(&mut self) -> Vec<CapitalReservation> {
        self.cleanup_expired_reservations();

        let mut successful_reservations = Vec::new();
        let mut available_capital = self.get_available_capital();

        while let Some(request) = self.request_queue.pop() {
            if request.amount <= available_capital {
                available_capital -= request.amount;

                let reservation = CapitalReservation {
                    reservation_id: self.next_reservation_id,
                    strategy: request.strategy.clone(),
                    token_address: request.token_address.clone(),
                    amount: request.amount,
                    expires_at: Instant::now() + self.reservation_duration,
                };

                self.allocated_capital.insert(reservation.reservation_id, reservation.clone());
                successful_reservations.push(reservation);
                self.next_reservation_id += 1;
            } else {
                // Re-queue if not enough capital? For now, we just drop it.
                // In a real scenario, we might have a mechanism for pending requests.
                log::warn!("Could not allocate capital for request, not enough available. Dropping request.");
            }
        }
        successful_reservations
    }

    pub fn release_capital(&mut self, reservation_id: u64) -> Result<()> {
        if self.allocated_capital.remove(&reservation_id).is_some() {
            Ok(())
        } else {
            Err(anyhow!("Invalid reservation ID {}", reservation_id))
        }
    }

    fn cleanup_expired_reservations(&mut self) {
        let now = Instant::now();
        self.allocated_capital.retain(|_, reservation| reservation.expires_at > now);
    }

    // Methods for metrics
    pub fn get_total_capital(&self) -> u64 {
        self.total_capital
    }

    pub fn get_allocated_capital_amount(&self) -> u64 {
        self.allocated_capital.values().map(|r| r.amount).sum()
    }
}

// For thread-safety, it should be wrapped in Arc<Mutex<...>>
pub type SharedPortfolioManager = Arc<Mutex<PortfolioManager>>;


#[cfg(test)]
mod tests {
    use super::*;
    use std::thread;
    use std::time::Duration;

    #[test]
    fn test_request_and_process_capital() {
        let mut manager = PortfolioManager::new(10000, 30);
        let request = CapitalRequest {
            strategy: Strategy::Sniper,
            token_address: "TokenA".to_string(),
            amount: 5000,
            priority: Priority::High,
        };
        manager.request_capital(request);

        let reservations = manager.process_requests();
        assert_eq!(reservations.len(), 1);
        assert_eq!(reservations[0].amount, 5000);
        assert_eq!(manager.get_available_capital(), 5000);
        assert_eq!(manager.get_allocated_capital_amount(), 5000);
    }

    #[test]
    fn test_priority_queue_ordering() {
        let mut manager = PortfolioManager::new(10000, 30);
        let req_low = CapitalRequest { strategy: Strategy::Momentum, token_address: "TokenC".to_string(), amount: 1000, priority: Priority::Low };
        let req_high = CapitalRequest { strategy: Strategy::Sniper, token_address: "TokenA".to_string(), amount: 5000, priority: Priority::High };
        let req_critical = CapitalRequest { strategy: Strategy::Arbitrage, token_address: "TokenB".to_string(), amount: 4000, priority: Priority::Critical };

        manager.request_capital(req_low);
        manager.request_capital(req_high);
        manager.request_capital(req_critical);

        // With 10000 capital, critical (4000) and high (5000) should be allocated. Low (1000) should also be allocated.
        let reservations = manager.process_requests();
        assert_eq!(reservations.len(), 3);

        // Check that they were processed in priority order
        assert!(reservations.iter().any(|r| r.strategy == Strategy::Arbitrage));
        assert!(reservations.iter().any(|r| r.strategy == Strategy::Sniper));
        assert!(reservations.iter().any(|r| r.strategy == Strategy::Momentum));

        assert_eq!(manager.get_available_capital(), 0);
    }
    
    #[test]
    fn test_insufficient_capital() {
        let mut manager = PortfolioManager::new(8000, 30);
        let req_high = CapitalRequest { strategy: Strategy::Sniper, token_address: "TokenA".to_string(), amount: 5000, priority: Priority::High };
        let req_critical = CapitalRequest { strategy: Strategy::Arbitrage, token_address: "TokenB".to_string(), amount: 4000, priority: Priority::Critical };

        manager.request_capital(req_high);
        manager.request_capital(req_critical);

        // Critical (4000) should be processed first and succeed. High (5000) should fail.
        let reservations = manager.process_requests();
        assert_eq!(reservations.len(), 1);
        assert_eq!(reservations[0].strategy, Strategy::Arbitrage);
        assert_eq!(manager.get_available_capital(), 4000);
    }

    #[test]
    fn test_release_capital() {
        let mut manager = PortfolioManager::new(10000, 30);
        let request = CapitalRequest { strategy: Strategy::Sniper, token_address: "TokenA".to_string(), amount: 5000, priority: Priority::High };
        manager.request_capital(request);

        let reservations = manager.process_requests();
        let reservation_id = reservations[0].reservation_id;

        assert_eq!(manager.get_available_capital(), 5000);
        
        manager.release_capital(reservation_id).unwrap();
        
        assert_eq!(manager.get_available_capital(), 10000);
        assert_eq!(manager.get_allocated_capital_amount(), 0);
    }

    #[test]
    fn test_reservation_timeout() {
        let mut manager = PortfolioManager::new(10000, 1); // 1 second timeout
        let request = CapitalRequest { strategy: Strategy::Sniper, token_address: "TokenA".to_string(), amount: 5000, priority: Priority::High };
        manager.request_capital(request);

        let reservations = manager.process_requests();
        assert_eq!(reservations.len(), 1);
        assert_eq!(manager.get_available_capital(), 5000);

        thread::sleep(Duration::from_secs(2));

        manager.cleanup_expired_reservations();
        assert_eq!(manager.get_available_capital(), 10000);
        assert_eq!(manager.get_allocated_capital_amount(), 0);
    }

    #[test]
    fn test_concurrent_access() {
        let manager = Arc::new(Mutex::new(PortfolioManager::new(50000, 5)));
        let mut handles = vec![];

        for i in 0..10 {
            let manager_clone = Arc::clone(&manager);
            let handle = thread::spawn(move || {
                let priority = match i % 4 {
                    0 => Priority::Low,
                    1 => Priority::Medium,
                    2 => Priority::High,
                    _ => Priority::Critical,
                };
                let request = CapitalRequest {
                    strategy: Strategy::Sniper,
                    token_address: format!("Token{}", i),
                    amount: 1000,
                    priority,
                };
                let mut guard = manager_clone.lock().unwrap();
                guard.request_capital(request);
            });
            handles.push(handle);
        }

        for handle in handles {
            handle.join().unwrap();
        }

        let mut guard = manager.lock().unwrap();
        assert_eq!(guard.request_queue.len(), 10);
        let reservations = guard.process_requests();
        assert_eq!(reservations.len(), 10);
        assert_eq!(guard.get_available_capital(), 40000);
    }
}
