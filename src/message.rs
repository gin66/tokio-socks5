
use std::io;
use std::net::SocketAddr;
use tokio_core::net::UdpCodec;

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

