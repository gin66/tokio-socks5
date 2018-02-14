
use std::io::{self};
use std::net::{SocketAddr,IpAddr, Ipv4Addr, Ipv6Addr};
use std::rc::Rc;

use futures::{Future, Poll, Async};
use tokio_core::net::{TcpStream,TcpStreamNew};
use tokio_core::reactor::Handle;
use trust_dns_resolver::ResolverFuture;
use trust_dns_resolver::lookup_ip::LookupIpFuture;
use socks_fut;

enum State {
    Resolve(LookupIpFuture),
    AnalyzeIps(Vec<IpAddr>),
    Connecting(TcpStreamNew),
    Done
}

pub struct Connecter {
    handle: Handle,
    state: State
}

pub fn resolve_connect(resolver: Rc<ResolverFuture>,
                       addr: &socks_fut::Addr,
                       handle: Handle) -> Connecter {
    let state = match *addr {
        socks_fut::Addr::DOMAIN(ref host) => {
            let mut host = host.to_vec();
            host.push(b'.');
            let host = String::from_utf8(host).unwrap();
            State::Resolve(resolver.lookup_ip(&host))
        },
        socks_fut::Addr::IP(ref ip) => {
            let ips = vec!(*ip);
            State::AnalyzeIps(ips)
        }
    };
    Connecter {
        handle: handle,
        state
    }
}

// The connector determines the best proxy based on
//   1. xxx.xxx.<COUNTRY CODE>
//   2. xxx.DOMAIN
//   3. country(IP)
//
impl Future for Connecter {
    type Item = TcpStream;
    type Error = io::Error;

    fn poll(&mut self) -> Result<Async<Self::Item>, io::Error> {

        loop {
            self.state = match self.state {
                State::Resolve(ref mut fut) => {
                    let lookup_ip = try_ready!(fut.poll());
                    let liter = lookup_ip.iter();
                    let mut ips = vec!();
                    for ip in liter {
                        ips.push(ip);
                    }
                    State::AnalyzeIps(ips)
                },
                State::AnalyzeIps(ref ips) => {
                    State::Done
                },
                State::Done => {
                    let sa = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)), 40002);
                    State::Connecting(TcpStream::connect(&sa,&self.handle))
                },
                State::Connecting(ref mut fut) => {
                    return fut.poll();
                }
            }
        }
    }
}