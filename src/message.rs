
use std::io;
use std::net::SocketAddr;
use tokio_core::net::UdpCodec;

// The message header is watermarked and as such should be of length n*128 bits aka 16 Bytes
// and n >= 3.
pub struct MessageHeader { 
	// first 128 bit block
	pub magic: [u8; 8],
	pub index: u32,
	pub time_s: u32,

	// second 128 bit block
	pub key1: u64,			// key1/2 are used to crypt the payload with chacha20 and 128bit
	pub key2: u64,

	// third 128 bit block
	pub payload_len: u16,
	pub crc_payload: u16,
	pub origin_ms: u16,
	pub hop1_ms: u16,
	pub hop2_ms: u16,
	pub origin_id: u8,
	pub hop1_id: u8,
	pub hop2_id: u8,
	pub destination_id: u8,
	pub typ: u8,
	pub pad: u8,
}

pub struct MessageCodec {
    pub my_id:  u8, // This contains my own id. If UdpMessage matches, then payload will be decrypted.
    pub secret: u8  // Shared secret for encryption and decryption
}

// This should contain the encryption method for UdpMessages sent between peers and clients

impl UdpCodec for MessageCodec {
	type In = (SocketAddr, Vec<u8>);
	type Out = (SocketAddr, Vec<u8>);

	fn decode(&mut self, addr: &SocketAddr, buf: &[u8]) -> Result<Self::In, io::Error> {
		Ok((*addr, buf.to_vec()))
	}

	fn encode(&mut self, (addr, buf): Self::Out, into: &mut Vec<u8>) -> SocketAddr {
		into.extend(buf);
		addr
	}
}

