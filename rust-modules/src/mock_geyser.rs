//! Mock Geyser gRPC Client Implementation
//!
//! This module provides a mock implementation of the Solana Geyser gRPC client
//! for development and testing purposes when the real client is not available.

use std::collections::HashMap;
use std::pin::Pin;
use std::task::{Context, Poll};
use std::time::Duration;

use futures::Stream;
use prost::Message;
use tonic::{Request, Response, Status, Streaming};

// Mock proto definitions that mirror the real Geyser proto
pub mod proto {
    use serde::{Deserialize, Serialize};

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct SubscribeRequest {
        #[prost(map = "string, message", tag = "1")]
        pub accounts: HashMap<String, AccountsSelector>,
        #[prost(map = "string, message", tag = "2")]
        pub transactions: HashMap<String, TransactionsSelector>,
        #[prost(map = "string, message", tag = "3")]
        pub blocks: HashMap<String, BlocksMetaSelector>,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct AccountsSelector {
        #[prost(string, repeated, tag = "1")]
        pub owner: Vec<String>,
        #[prost(string, repeated, tag = "2")]
        pub account: Vec<String>,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct TransactionsSelector {
        #[prost(string, repeated, tag = "1")]
        pub signatures: Vec<String>,
        #[prost(bool, optional, tag = "2")]
        pub vote: Option<bool>,
        #[prost(bool, optional, tag = "3")]
        pub failed: Option<bool>,
        #[prost(string, repeated, tag = "4")]
        pub account_include: Vec<String>,
        #[prost(string, repeated, tag = "5")]
        pub account_exclude: Vec<String>,
        #[prost(bool, optional, tag = "6")]
        pub include_all_versioned_txs: Option<bool>,
        #[prost(bool, optional, tag = "7")]
        pub include_entries: Option<bool>,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct BlocksMetaSelector {
        #[prost(bool, optional, tag = "1")]
        pub include_transactions: Option<bool>,
        #[prost(bool, optional, tag = "2")]
        pub include_accounts: Option<bool>,
        #[prost(bool, optional, tag = "3")]
        pub include_entries: Option<bool>,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct SubscribeUpdate {
        #[prost(oneof = "subscribe_update::UpdateOneof", tags = "1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11")]
        pub update_oneof: Option<subscribe_update::UpdateOneof>,
    }

    pub mod subscribe_update {
        use super::*;

        #[derive(Clone, Debug, PartialEq, Oneof)]
        pub enum UpdateOneof {
            #[prost(message, tag = "1")]
            Account(AccountUpdate),
            #[prost(message, tag = "2")]
            Transaction(TransactionUpdate),
            #[prost(message, tag = "3")]
            Block(BlockUpdate),
            #[prost(message, tag = "4")]
            Slot(SlotUpdate),
            #[prost(message, tag = "5")]
            TransactionStatus(TransactionStatusUpdate),
            #[prost(message, tag = "6")]
            Entry(EntryUpdate),
            #[prost(message, tag = "7")]
            BlockMeta(BlockMetaUpdate),
            #[prost(message, tag = "8")]
            Ping(Ping),
            #[prost(message, tag = "9")]
            Pong(Pong),
            #[prost(message, tag = "10")]
            SlotStatus(SlotStatusUpdate),
            #[prost(message, tag = "11")]
            AccountInfo(AccountInfoUpdate),
        }
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct AccountUpdate {
        #[prost(bytes, tag = "1")]
        pub pubkey: Vec<u8>,
        #[prost(uint64, tag = "2")]
        pub lamports: u64,
        #[prost(uint64, tag = "3")]
        pub owner: Vec<u8>,
        #[prost(bool, tag = "4")]
        pub executable: bool,
        #[prost(uint64, tag = "5")]
        pub rent_epoch: u64,
        #[prost(bytes, tag = "6")]
        pub data: Vec<u8>,
        #[prost(bool, tag = "7")]
        pub write_version_is_set: bool,
        #[prost(uint64, tag = "8")]
        pub write_version: u64,
        #[prost(uint64, tag = "9")]
        pub slot: u64,
        #[prost(bool, optional, tag = "10")]
        pub is_startup: Option<bool>,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct TransactionUpdate {
        #[prost(bytes, tag = "1")]
        pub signature: Vec<u8>,
        #[prost(int64, tag = "2")]
        pub slot: i64,
        #[prost(message, optional, tag = "3")]
        pub transaction: Option<Transaction>,
        #[prost(message, optional, tag = "4")]
        pub meta: Option<TransactionStatusMeta>,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct Transaction {
        #[prost(message, optional, tag = "1")]
        pub message: Option<Message>,
        #[prost(message, repeated, tag = "2")]
        pub signatures: Vec<Signature>,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct Message {
        #[prost(bytes, repeated, tag = "1")]
        pub account_keys: Vec<Vec<u8>>,
        #[prost(int64, repeated, tag = "2")]
        pub recent_blockhash: Vec<i64>,
        #[prost(bytes, repeated, tag = "3")]
        pub instructions: Vec<CompiledInstruction>,
        #[prost(message, optional, tag = "4")]
        pub address_table_lookups: Option<MessageAddressTableLookup>,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct CompiledInstruction {
        #[prost(uint32, tag = "1")]
        pub program_id_index: u32,
        #[prost(bytes, tag = "2")]
        pub accounts: Vec<u8>,
        #[prost(bytes, tag = "3")]
        pub data: Vec<u8>,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct MessageAddressTableLookup {
        #[prost(bytes, tag = "1")]
        pub account_key: Vec<u8>,
        #[prost(bytes, repeated, tag = "2")]
        pub writable_indexes: Vec<u8>,
        #[prost(bytes, repeated, tag = "3")]
        pub readonly_indexes: Vec<u8>,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct Signature {
        #[prost(bytes, tag = "1")]
        pub signature: Vec<u8>,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct TransactionStatusMeta {
        #[prost(uint64, repeated, tag = "1")]
        pub pre_balances: Vec<u64>,
        #[prost(uint64, repeated, tag = "2")]
        pub post_balances: Vec<u64>,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct BlockUpdate {
        #[prost(uint64, tag = "1")]
        pub slot: u64,
        #[prost(uint64, tag = "2")]
        pub parent_slot: u64,
        #[prost(bytes, tag = "3")]
        pub blockhash: Vec<u8>,
        #[prost(message, repeated, tag = "4")]
        pub rewards: Vec<Reward>,
        #[prost(uint64, tag = "5")]
        pub block_time: Option<u64>,
        #[prost(uint64, tag = "6")]
        pub block_height: Option<u64>,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct Reward {
        #[prost(bytes, tag = "1")]
        pub pubkey: Vec<u8>,
        #[prost(int64, tag = "2")]
        pub lamports: i64,
        #[prost(uint64, tag = "3")]
        pub post_balance: u64,
        #[prost(uint32, tag = "4")]
        pub reward_type: u32,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct SlotUpdate {
        #[prost(uint64, tag = "1")]
        pub slot: u64,
        #[prost(message, optional, tag = "2")]
        pub parent: Option<SlotUpdateParent>,
        #[prost(string, tag = "3")]
        pub status: String,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct SlotUpdateParent {
        #[prost(uint64, tag = "1")]
        pub slot: u64,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct TransactionStatusUpdate {
        #[prost(bytes, tag = "1")]
        pub signature: Vec<u8>,
        #[prost(uint64, tag = "2")]
        pub slot: u64,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct EntryUpdate {
        #[prost(uint64, tag = "1")]
        pub slot: u64,
        #[prost(uint32, tag = "2")]
        pub index: u32,
        #[prost(uint32, tag = "3")]
        pub num_hashes: u32,
        #[prost(bytes, tag = "4")]
        pub hash: Vec<u8>,
        #[prost(bool, repeated, tag = "5")]
        pub executed_transaction_count: Vec<bool>,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct BlockMetaUpdate {
        #[prost(uint64, tag = "1")]
        pub slot: u64,
        #[prost(bytes, tag = "2")]
        pub parent_blockhash: Vec<u8>,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct Ping {
        #[prost(uint64, tag = "1")]
        pub id: u64,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct Pong {
        #[prost(uint64, tag = "1")]
        pub id: u64,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct SlotStatusUpdate {
        #[prost(uint64, tag = "1")]
        pub slot: u64,
        #[prost(string, tag = "2")]
        pub status: String,
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct AccountInfoUpdate {
        #[prost(bytes, tag = "1")]
        pub pubkey: Vec<u8>,
        #[prost(uint64, tag = "2")]
        pub slot: u64,
    }

    pub use prost::Oneof;

    pub mod subscribe_request {
        pub type AccountsSelector = super::AccountsSelector;
        pub type TransactionsSelector = super::TransactionsSelector;
        pub use super::CommitmentLevel;
    }

    #[derive(Clone, Debug, PartialEq, Message)]
    pub struct CommitmentLevel {
        #[prost(string, tag = "1")]
        pub commitment: String,
    }

    pub mod geyser_client {
        use super::*;
        use tonic::client::Grpc;

        #[derive(Debug, Clone)]
        pub struct GeyserClient<T> {
            inner: T,
        }

        impl<T: Grpc> GeyserClient<T> {
            pub fn new(inner: T) -> Self {
                Self { inner }
            }

            pub async fn subscribe(
                &mut self,
                request: Request<SubscribeRequest>,
            ) -> Result<Response<Streaming<SubscribeUpdate>>, Status> {
                // Mock implementation - will be overridden in mock client
                Err(Status::unimplemented("Mock client"))
            }
        }

        impl<T: Grpc> Service<Request<SubscribeRequest>> for GeyserClient<T> {
            type Response = Response<Streaming<SubscribeUpdate>>;
            type Error = Status;
            type Future = Pin<Box<dyn std::future::Future<Output = Result<Self::Response, Self::Error>> + Send>>;

            fn poll_ready(&mut self, _cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
                Poll::Ready(Ok(()))
            }

            fn call(&mut self, request: Request<SubscribeRequest>) -> Self::Future {
                Box::pin(async move {
                    self.subscribe(request).await
                })
            }
        }

        use tonic::server::NamedService;
        use tonic::transport::Service;

        impl<T: Grpc> NamedService for GeyserClient<T> {
            const NAME: &'static str = "geyser.Geyser";
        }
    }
}

// Re-export types for compatibility
pub use proto::{
    AccountUpdate as GeyserAccountUpdate,
    TransactionUpdate as GeyserTransactionUpdate,
    SubscribeRequest,
    SubscribeUpdate,
};

/// Mock Geyser gRPC client
#[derive(Debug, Clone)]
pub struct GeyserGrpcClient {
    endpoint: String,
}

impl GeyserGrpcClient {
    /// Create a new mock Geyser gRPC client
    pub async fn connect(
        endpoint: String,
        _x_token: Option<String>,
        _tls_config: Option<tonic::transport::ClientTlsConfig>,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        tracing::info!("Creating mock Geyser gRPC client for endpoint: {}", endpoint);

        Ok(Self { endpoint })
    }

    /// Subscribe to Geyser updates (mock implementation)
    pub async fn subscribe(
        &mut self,
        _request: SubscribeRequest,
    ) -> Result<Response<Streaming<SubscribeUpdate>>, Status> {
        tracing::warn!("Mock Geyser client - returning empty stream");

        // Return an empty stream that immediately ends
        let (tx, rx) = tokio::sync::mpsc::channel(1);
        drop(tx); // Close the channel immediately

        Ok(Response::new(tokio_stream::wrappers::ReceiverStream::new(rx)))
    }
}

/// Helper function to create mock data for testing
pub fn create_mock_transaction_update() -> TransactionUpdate {
    use prost::Message;

    TransactionUpdate {
        signature: vec![1u8; 64],
        slot: 12345,
        transaction: Some(proto::Transaction {
            message: Some(proto::Message {
                account_keys: vec![
                    vec![2u8; 32], // Program ID
                    vec![3u8; 32], // Token mint
                ],
                recent_blockhash: vec![4],
                instructions: vec![proto::CompiledInstruction {
                    program_id_index: 0,
                    accounts: vec![1],
                    data: vec![5, 6, 7],
                }],
                address_table_lookups: None,
            }),
            signatures: vec![proto::Signature {
                signature: vec![8u8; 64],
            }],
        }),
        meta: Some(proto::TransactionStatusMeta {
            pre_balances: vec![1000000000, 2000000000],
            post_balances: vec![900000000, 2100000000],
        }),
    }
}

/// Helper function to create mock account update for testing
pub fn create_mock_account_update() -> AccountUpdate {
    AccountUpdate {
        pubkey: vec![1u8; 32],
        lamports: 1000000000,
        owner: vec![2u8; 32],
        executable: false,
        rent_epoch: 0,
        data: vec![3, 4, 5],
        write_version_is_set: true,
        write_version: 1,
        slot: 12345,
        is_startup: Some(false),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mock_client_creation() {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let client = rt.block_on(async {
            GeyserGrpcClient::connect(
                "http://localhost:10000".to_string(),
                None,
                None,
            ).await
        });

        assert!(client.is_ok());
    }

    #[test]
    fn test_mock_transaction_update() {
        let tx_update = create_mock_transaction_update();
        assert_eq!(tx_update.slot, 12345);
        assert!(tx_update.transaction.is_some());
    }

    #[test]
    fn test_mock_account_update() {
        let account_update = create_mock_account_update();
        assert_eq!(account_update.slot, 12345);
        assert_eq!(account_update.lamports, 1000000000);
    }
}