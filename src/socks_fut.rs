
use std::io;
use std::io::{Error, ErrorKind};
use tokio_io::io::{read_exact, write_all, ReadExact, WriteAll};
use tokio_core::net::{TcpStream};
use futures::*;
use futures::Async;
use bytes::BytesMut;
use bytes::BufMut;

#[allow(dead_code)]
mod v5 {
    pub const VERSION: u8 = 5;

    pub const METH_NO_AUTH: u8 = 0;
    pub const METH_GSSAPI: u8 = 1;
    pub const METH_USER_PASS: u8 = 2;
    pub const METH_NO_ACCEPTABLE_METHOD: u8 = 255;

    pub const CMD_CONNECT: u8 = 1;
    pub const CMD_BIND: u8 = 2;
    pub const CMD_UDP_ASSOCIATE: u8 = 3;

    pub const ATYP_IPV4: u8 = 1;
    pub const ATYP_IPV6: u8 = 4;
    pub const ATYP_DOMAIN: u8 = 3;

    // 6 Bytes+4 Bytes for IP
    pub const MIN_REQUEST_SIZE: usize = 6+4;
    // 6 Bytes+addr (1 Byte length + non terminated string)
    pub const MAX_REQUEST_SIZE: usize = 6+1+255;
}

enum ServerState {
    // as per RFC 1928, first read into buffer
    WaitClientAuthentication(ReadExact<TcpStream,Vec<u8>>),
    ReadAuthenticationMethods(ReadExact<TcpStream,Vec<u8>>),
    AnswerNoAuthentication(WriteAll<TcpStream,Vec<u8>>),
    WaitClientRequest(ReadExact<TcpStream,Vec<u8>>),
}

pub struct SocksHandshake {
    request: BytesMut,
    state: ServerState
}

pub fn socks_handshake(stream: TcpStream) -> SocksHandshake {
    SocksHandshake { 
        request: BytesMut::with_capacity(v5::MAX_REQUEST_SIZE),
        state: ServerState::WaitClientAuthentication(
            read_exact(stream,vec!(0u8;2))
        )
    }
}

pub enum Command {
    Connect = 1,
    Bind = 2,
    UdpAssociate = 3
}

pub enum Addr {
    IPV4(BytesMut,Vec<u8>,u16,Command),   // last parameter is port
    IPV6(BytesMut,Vec<u8>,u16,Command),
    DOMAIN(BytesMut,Vec<u8>,u16,Command)
}

impl Future for SocksHandshake {
    type Item = (TcpStream,Addr);
    type Error = io::Error;

    fn poll(&mut self) -> Result<Async<Self::Item>, io::Error> {
        use self::ServerState::*;

        loop {
            self.state = match self.state {
                WaitClientAuthentication(ref mut fut) => {
                    let (stream,buf) = try_ready!(fut.poll());
                    if (buf[0] != v5::VERSION) || (buf[1] == 0) {
                        return Err(Error::new(ErrorKind::Other, "Not Socks5 protocol"));
                    }
                    ReadAuthenticationMethods(
                        read_exact(stream,vec![0u8; buf[1] as usize])
                    )
                }
                ReadAuthenticationMethods(ref mut fut) => {
                    let (stream,buf) = try_ready!(fut.poll());
                    let answer = if buf.contains(&v5::METH_NO_AUTH) {
                            v5::METH_NO_AUTH
                        }
                        else {
                            v5::METH_NO_ACCEPTABLE_METHOD
                        };
                    AnswerNoAuthentication(
                        write_all(stream, vec![v5::VERSION, answer])
                    )
                }
                AnswerNoAuthentication(ref mut fut) => {
                    let (stream,buf) = try_ready!(fut.poll());
                    if buf[1] == v5::METH_NO_ACCEPTABLE_METHOD {
                        return Err(Error::new(ErrorKind::Other,
                                    "Only 'no authentication' supported"));
                    }
                    WaitClientRequest(
                        read_exact(stream,vec![0u8; v5::MIN_REQUEST_SIZE])
                    )
                }
                WaitClientRequest(ref mut fut) => {
                    let (stream,buf) = try_ready!(fut.poll());
                    self.request.put_slice(&buf);
                    if (self.request[0] != v5::VERSION) || (self.request[1] != 0) {
                        return Err(Error::new(ErrorKind::Other, "Not Socks5 protocol"))
                    };
                    let cmd = match self.request[1] {
                        v5::CMD_CONNECT => Command::Connect,
                        v5::CMD_BIND    => Command::Bind,
                        v5::CMD_UDP_ASSOCIATE => Command::UdpAssociate,
                        _ => return Err(Error::new(ErrorKind::Other, "Unknown socks command"))
                    };
                    let dst_len =
                        match self.request[3] {
                            v5::ATYP_IPV4   => 4,
                            v5::ATYP_IPV6   => 16,
                            v5::ATYP_DOMAIN => self.request[4]+1,
                            _ => return Err(Error::new(ErrorKind::Other, 
                                                        "Unknown address typ"))
                        };
                    let delta = (dst_len as usize) + 6 - self.request.len();
                    if delta > 0 {
                        WaitClientRequest(
                            read_exact(stream,vec![0u8; delta])
                        )
                    }
                    else {
                        let n = self.request.len();
                        let port = ((self.request[n-2] as u16) << 8) | (self.request[n-1] as u16);
                        let addr = match self.request[3] {
                            v5::ATYP_IPV4   => {
                                let ipv4 = self.request[4..8].to_vec();
                                Addr::IPV4(self.request.take(),ipv4,port,cmd)
                            },
                            v5::ATYP_IPV6   => {
                                let ipv6 = self.request[4..20].to_vec();
                                Addr::IPV6(self.request.take(),ipv6,port,cmd)
                            },
                            v5::ATYP_DOMAIN => {
                                let domlen = self.request[4] as usize;
                                let dom: Vec<u8> = self.request[5..(5+domlen)].to_vec();
                                Addr::DOMAIN(self.request.take(),dom,port,cmd)
                            },
                            _ =>
                                panic!("Memory mutation happened")
                        };
                        return Ok(Async::Ready(((stream,addr))));
                    }
                }
            }
        }
    }
}