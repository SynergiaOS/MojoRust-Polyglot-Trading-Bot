//! Hash utilities and Merkle tree implementation
//!
//! Provides various hashing algorithms and Merkle tree construction
//! for data integrity verification and proof generation.

use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256, Sha512};
use std::collections::HashMap;

/// Hash algorithms supported
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HashAlgorithm {
    Sha256,
    Sha512,
}

/// Hash utilities for different algorithms
pub struct HashUtils;

impl HashUtils {
    /// Hash data using SHA-256
    pub fn sha256(data: &[u8]) -> Vec<u8> {
        let mut hasher = Sha256::new();
        hasher.update(data);
        hasher.finalize().to_vec()
    }

    /// Hash data using SHA-512
    pub fn sha512(data: &[u8]) -> Vec<u8> {
        let mut hasher = Sha512::new();
        hasher.update(data);
        hasher.finalize().to_vec()
    }

    /// Hash data using specified algorithm
    pub fn hash(data: &[u8], algorithm: HashAlgorithm) -> Vec<u8> {
        match algorithm {
            HashAlgorithm::Sha256 => Self::sha256(data),
            HashAlgorithm::Sha512 => Self::sha512(data),
        }
    }

    /// Hash multiple data items by concatenating
    pub fn hash_multiple(data_items: &[&[u8]]) -> Vec<u8> {
        let mut hasher = Sha256::new();
        for item in data_items {
            hasher.update(item);
        }
        hasher.finalize().to_vec()
    }

    /// Hash a string
    pub fn hash_string(s: &str) -> Vec<u8> {
        Self::sha256(s.as_bytes())
    }

    /// Create hash from number
    pub fn hash_number(num: u64) -> Vec<u8> {
        Self::sha256(&num.to_be_bytes())
    }

    /// Create double hash (hash of hash)
    pub fn double_hash(data: &[u8]) -> Vec<u8> {
        let first_hash = Self::sha256(data);
        Self::sha256(&first_hash)
    }

    /// Hash with salt
    pub fn hash_with_salt(data: &[u8], salt: &[u8]) -> Vec<u8> {
        Self::hash_multiple(&[salt, data])
    }

    /// Create HMAC
    pub fn hmac_sha256(data: &[u8], key: &[u8]) -> Vec<u8> {
        use hmac::{Hmac, Mac};
        type HmacSha256 = Hmac<Sha256>;

        let mut mac = HmacSha256::new_from_slice(key)
            .expect("HMAC can take key of any size");
        mac.update(data);
        mac.finalize().into_bytes().to_vec()
    }

    /// Verify HMAC
    pub fn verify_hmac_sha256(data: &[u8], key: &[u8], expected: &[u8]) -> bool {
        match Self::hmac_sha256(data, key) {
            computed => constant_time_eq::constant_time_eq(&computed, expected),
        }
    }

    /// Generate hash-based message authentication code
    pub fn generate_hmac(data: &[u8], secret: &[u8]) -> String {
        let hmac = Self::hmac_sha256(data, secret);
        hex::encode(hmac)
    }

    /// Create hash chain
    pub fn hash_chain(initial: &[u8], count: usize) -> Vec<u8> {
        let mut current = initial.to_vec();
        for _ in 0..count {
            current = Self::sha256(&current);
        }
        current
    }

    /// Merkle tree implementation
    pub fn create_merkle_tree(data_items: &[Vec<u8>]) -> MerkleTree {
        MerkleTree::build(data_items)
    }

    /// Create commitment hash (salted hash for commitment schemes)
    pub fn create_commitment(data: &[u8], salt: Option<&[u8]>) -> Vec<u8> {
        match salt {
            Some(s) => Self::hash_with_salt(data, s),
            None => Self::sha256(data),
        }
    }

    /// Verify commitment
    pub fn verify_commitment(data: &[u8], salt: Option<&[u8]>, commitment: &[u8]) -> bool {
        let computed = Self::create_commitment(data, salt);
        constant_time_eq::constant_time_eq(&computed, commitment)
    }
}

/// Merkle tree for data integrity verification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MerkleTree {
    pub root: Vec<u8>,
    leaves: Vec<Vec<u8>>,
    tree: Vec<Vec<Vec<u8>>>,
}

impl MerkleTree {
    /// Build a Merkle tree from data items
    pub fn build(data_items: &[Vec<u8>]) -> Self {
        if data_items.is_empty() {
            return Self {
                root: vec![],
                leaves: vec![],
                tree: vec![],
            };
        }

        // Hash all leaves
        let leaves: Vec<Vec<u8>> = data_items.iter()
            .map(|item| HashUtils::sha256(item))
            .collect();

        let mut tree = vec![leaves.clone()];
        let mut current_level = leaves.clone();

        // Build tree levels until we have a single root
        while current_level.len() > 1 {
            let mut next_level = Vec::new();

            // Pair up and hash
            for chunk in current_level.chunks(2) {
                if chunk.len() == 2 {
                    // Hash pair
                    let combined = HashUtils::hash_multiple(&[&chunk[0], &chunk[1]]);
                    next_level.push(combined);
                } else {
                    // Odd number, duplicate the last element
                    let combined = HashUtils::hash_multiple(&[&chunk[0], &chunk[0]]);
                    next_level.push(combined);
                }
            }

            tree.push(next_level.clone());
            current_level = next_level;
        }

        let root = current_level.into_iter().next().unwrap_or_default();

        Self {
            root,
            leaves,
            tree,
        }
    }

    /// Get the Merkle root
    pub fn root(&self) -> &[u8] {
        &self.root
    }

    /// Get the number of leaves
    pub fn leaf_count(&self) -> usize {
        self.leaves.len()
    }

    /// Generate Merkle proof for a leaf
    pub fn generate_proof(&self, leaf_index: usize) -> Result<MerkleProof> {
        if leaf_index >= self.leaves.len() {
            return Err(anyhow!("Leaf index out of bounds"));
        }

        let mut proof = Vec::new();
        let mut current_index = leaf_index;

        // Walk up the tree, collecting sibling hashes
        for (level, nodes) in self.tree.iter().enumerate() {
            if level == self.tree.len() - 1 {
                break; // Reached root
            }

            let sibling_index = if current_index % 2 == 0 {
                current_index + 1
            } else {
                current_index - 1
            };

            let sibling_hash = if sibling_index < nodes.len() {
                nodes[sibling_index].clone()
            } else {
                // For odd number of nodes, duplicate the last one
                nodes[current_index].clone()
            };

            proof.push(MerkleProofNode {
                hash: sibling_hash,
                is_left: current_index % 2 != 0, // True if sibling is on the left
            });

            current_index /= 2;
        }

        Ok(MerkleProof {
            leaf_hash: self.leaves[leaf_index].clone(),
            proof,
            leaf_index,
        })
    }

    /// Verify Merkle proof
    pub fn verify_proof(&self, proof: &MerkleProof) -> bool {
        self.verify_proof_with_root(proof, &self.root)
    }

    /// Verify Merkle proof with given root
    pub fn verify_proof_with_root(&self, proof: &MerkleProof, root: &[u8]) -> bool {
        let mut current_hash = proof.leaf_hash.clone();

        for node in &proof.proof {
            current_hash = if node.is_left {
                HashUtils::hash_multiple(&[&node.hash, &current_hash])
            } else {
                HashUtils::hash_multiple(&[&current_hash, &node.hash])
            };
        }

        constant_time_eq::constant_time_eq(&current_hash, root)
    }

    /// Get leaf at index
    pub fn get_leaf(&self, index: usize) -> Option<&[u8]> {
        self.leaves.get(index).map(|leaf| leaf.as_slice())
    }

    /// Check if data item is a leaf in the tree
    pub fn contains_leaf(&self, data: &[u8]) -> Option<usize> {
        let hash = HashUtils::sha256(data);
        self.leaves.iter().position(|leaf| leaf == &hash)
    }

    /// Get tree depth
    pub fn depth(&self) -> usize {
        self.tree.len()
    }
}

/// Merkle proof structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MerkleProof {
    pub leaf_hash: Vec<u8>,
    pub proof: Vec<MerkleProofNode>,
    pub leaf_index: usize,
}

/// Individual Merkle proof node
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MerkleProofNode {
    pub hash: Vec<u8>,
    pub is_left: bool, // True if this hash is on the left side
}

impl MerkleProof {
    /// Create empty proof
    pub fn empty() -> Self {
        Self {
            leaf_hash: vec![],
            proof: vec![],
            leaf_index: 0,
        }
    }

    /// Serialize proof to hex
    pub fn to_hex(&self) -> String {
        hex::encode(bincode::serialize(self).unwrap())
    }

    /// Deserialize proof from hex
    pub fn from_hex(hex_str: &str) -> Result<Self> {
        let bytes = hex::decode(hex_str)?;
        let proof: MerkleProof = bincode::deserialize(&bytes)?;
        Ok(proof)
    }

    /// Get proof size in bytes
    pub fn size(&self) -> usize {
        bincode::serialize(self).unwrap().len()
    }
}

/// Rolling hash for streaming data
pub struct RollingHash {
    window_size: usize,
    window: Vec<u8>,
    current_hash: Vec<u8>,
}

impl RollingHash {
    /// Create new rolling hash
    pub fn new(window_size: usize) -> Self {
        Self {
            window_size,
            window: Vec::with_capacity(window_size),
            current_hash: vec![0; 32],
        }
    }

    /// Add byte to rolling hash
    pub fn update(&mut self, byte: u8) {
        if self.window.len() >= self.window_size {
            // Remove oldest byte
            self.window.remove(0);
        }
        self.window.push(byte);
        self.recalculate_hash();
    }

    /// Add multiple bytes
    pub fn extend(&mut self, data: &[u8]) {
        for &byte in data {
            self.update(byte);
        }
    }

    /// Get current hash
    pub fn hash(&self) -> &[u8] {
        &self.current_hash
    }

    /// Reset rolling hash
    pub fn reset(&mut self) {
        self.window.clear();
        self.current_hash = vec![0; 32];
    }

    fn recalculate_hash(&mut self) {
        if !self.window.is_empty() {
            self.current_hash = HashUtils::sha256(&self.window);
        }
    }
}

/// Bloom filter for approximate set membership
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BloomFilter {
    bit_array: Vec<bool>,
    hash_count: usize,
    size: usize,
}

impl BloomFilter {
    /// Create new bloom filter
    pub fn new(size: usize, hash_count: usize) -> Self {
        Self {
            bit_array: vec![false; size],
            hash_count,
            size,
        }
    }

    /// Add item to bloom filter
    pub fn add(&mut self, item: &[u8]) {
        for i in 0..self.hash_count {
            let hash = HashUtils::hash_with_salt(item, &i.to_be_bytes());
            let index = (hash[0] as usize) % self.size;
            self.bit_array[index] = true;
        }
    }

    /// Check if item might be in bloom filter
    pub fn might_contain(&self, item: &[u8]) -> bool {
        for i in 0..self.hash_count {
            let hash = HashUtils::hash_with_salt(item, &i.to_be_bytes());
            let index = (hash[0] as usize) % self.size;
            if !self.bit_array[index] {
                return false;
            }
        }
        true
    }

    /// Get current false positive rate estimate
    pub fn false_positive_rate(&self) -> f64 {
        let ones = self.bit_array.iter().filter(|&&x| x).count();
        let ratio = ones as f64 / self.size as f64;
        ratio.powi(self.hash_count as i32)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_utils() {
        let data = b"test data";
        let hash1 = HashUtils::sha256(data);
        let hash2 = HashUtils::sha256(data);

        assert_eq!(hash1, hash2);
        assert_eq!(hash1.len(), 32); // SHA-256 produces 32 bytes
    }

    #[test]
    fn test_merkle_tree() {
        let data = vec![
            b"data1".to_vec(),
            b"data2".to_vec(),
            b"data3".to_vec(),
            b"data4".to_vec(),
        ];

        let tree = MerkleTree::build(&data);
        assert_eq!(tree.leaf_count(), 4);
        assert!(!tree.root().is_empty());

        // Generate and verify proof
        let proof = tree.generate_proof(0).unwrap();
        assert!(tree.verify_proof(&proof));
    }

    #[test]
    fn test_merkle_tree_single_item() {
        let data = vec![b"single item".to_vec()];
        let tree = MerkleTree::build(&data);

        let proof = tree.generate_proof(0).unwrap();
        assert!(tree.verify_proof(&proof));
    }

    #[test]
    fn test_merkle_tree_empty() {
        let data: Vec<Vec<u8>> = vec![];
        let tree = MerkleTree::build(&data);

        assert_eq!(tree.leaf_count(), 0);
        assert!(tree.root().is_empty());
    }

    #[test]
    fn test_hmac() {
        let data = b"test data";
        let key = b"secret key";

        let hmac = HashUtils::hmac_sha256(data, key);
        assert!(!HashUtils::verify_hmac_sha256(data, b"wrong key", &hmac));
        assert!(HashUtils::verify_hmac_sha256(data, key, &hmac));
    }

    #[test]
    fn test_commitment() {
        let data = b"secret data";
        let salt = b"random salt";

        let commitment = HashUtils::create_commitment(data, Some(salt));
        assert!(HashUtils::verify_commitment(data, Some(salt), &commitment));
        assert!(!HashUtils::verify_commitment(data, Some(b"wrong salt"), &commitment));
    }

    #[test]
    fn test_rolling_hash() {
        let mut roller = RollingHash::new(3);

        roller.update(b'a');
        roller.update(b'b');
        roller.update(b'c');

        let hash1 = roller.hash();

        roller.update(b'd'); // Should remove 'a' and add 'd'

        let hash2 = roller.hash();
        assert_ne!(hash1, hash2);
    }

    #[test]
    fn test_bloom_filter() {
        let mut filter = BloomFilter::new(100, 3);

        filter.add(b"item1");
        filter.add(b"item2");

        assert!(filter.might_contain(b"item1"));
        assert!(filter.might_contain(b"item2"));
        assert!(!filter.might_contain(b"item3")); // Probably false
    }

    #[test]
    fn test_hash_chain() {
        let initial = b"initial value";
        let chain = HashUtils::hash_chain(initial, 3);

        // Verify chain length
        let mut expected = HashUtils::sha256(initial);
        expected = HashUtils::sha256(&expected);
        expected = HashUtils::sha256(&expected);

        assert_eq!(chain, expected);
    }
}