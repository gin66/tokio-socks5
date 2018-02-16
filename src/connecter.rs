
use std::io::{self,Write};
use std::net::{SocketAddr,IpAddr, Ipv4Addr, Ipv6Addr};
use std::rc::Rc;
use std::option::Option;
use std::time::Instant;

use futures::{Future, Async};
use tokio_core::net::{TcpStream,TcpStreamNew};
use tokio_core::reactor::Handle;
use trust_dns_resolver::config::*;
use trust_dns_resolver::ResolverFuture;
use trust_dns_resolver::lookup_ip::LookupIpFuture;
use socks_fut;
use csv;
use bytes::Bytes;
use database::Database;
use country::{code2country,country_hash};

pub struct Connecter {
    dbip_v4: Vec<(Ipv4Addr,Ipv4Addr,usize)>,
    resolver: ResolverFuture,
    handle: Handle,
    database: Rc<Database>
}

impl Connecter {
    pub fn new(handle: Handle,database: Rc<Database>) -> Connecter {
        let resolver = ResolverFuture::new(ResolverConfig::default(),
                                        ResolverOpts::default(), 
                                        &handle);
        Connecter {
            dbip_v4: vec!(),
            resolver,
            handle,
            database
        }
    }

    pub fn read_dbip(&mut self) {
        println!("Read dbip...");
        let mut rdr = csv::Reader::from_path("dbip-country-2017-12.csv").unwrap();
        for result in rdr.records() {
            match result {
                Err(err) => (),
                Ok(record) => {
                    if let (Some(ip_from),Some(ip_to),Some(country)) = (record.get(0),record.get(1),record.get(2)) {
                        let lcountry = country.to_lowercase();
                        let cb = lcountry.as_bytes();
                        let code = country_hash(&[cb[0],cb[1]]);
                        let ipv4_from = ip_from.parse::<Ipv4Addr>();
                        let ipv4_to   = ip_to.parse::<Ipv4Addr>();
                        if let (Ok(ipv4_from),Ok(ipv4_to),Some(code)) = (ipv4_from,ipv4_to,code) {
                            self.dbip_v4.push( (ipv4_from,ipv4_to,code) );
                            //println!("{:?}-{:?}: {}/{:?}", ip_from, ip_to, country, code);
                            continue
                        };
                        let ipv6_from = ip_from.parse::<Ipv6Addr>();
                        let ipv6_to   = ip_to.parse::<Ipv6Addr>();
                        if let (Ok(ipv6_from),Ok(ipv6_to),Some(code)) = (ipv6_from,ipv6_to,code) {
                            continue
                        }
                        else {
                            println!("Unreadable record: {:?}",record)
                        }
                    }
                }
            }
        }
        println!("Read finished");
    }

    fn determine_country(&self,ip: &IpAddr) -> Option<usize> {
        match ip {
            &IpAddr::V4(ref ipv4) => {
                let mut i: usize = 0;
                let mut j: usize = self.dbip_v4.len()-1;
                while i < j {
                    //println!("{} {}",i,j);
                    let k: usize = (i+j)/2;
                    let (ip_from,ip_to,code) = self.dbip_v4[k];
                    if ip_from > *ipv4 {
                        j = k-1
                    }
                    else if ip_to < *ipv4 {
                        i = k+1
                    }
                    else {
                        return Some(code)
                    }
                }
                let (ip_from,ip_to,code) = self.dbip_v4[j];
                if (ip_from <= *ipv4) && (ip_to >= *ipv4) {
                    return Some(code)
                }
                None
            },
            &IpAddr::V6(ref ipv6) => None
        }
    }

    fn select_proxy(self: &Connecter, codes: &Vec<usize>) -> Vec<SocketAddr> {
        let mut id_list: Vec<u8> = vec!();
        for cx in codes {
            if let Some(ref xid_list) = self.database.country_to_nodes[*cx as usize] {
                for id in xid_list {
                    if ! id_list.contains(id) {
                        id_list.push(*id)
                    }
                }
            }
        }
        let mut sa_list: Vec<SocketAddr> = vec!();
        for id in id_list {
            if let Some(ref proxies) = self.database.proxy_to[id as usize] {
                for sa in proxies {
                    sa_list.push(sa.clone())
                }
            }
        }
        //println!("{:?}",sa_list);
        //let sa = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)), 40002);
        //sa
        return sa_list
    }
}

enum State {
    Resolve(LookupIpFuture),
    AnalyzeIps(Vec<IpAddr>),
    SelectProxy(Vec<usize>),
    NextProxy,
    Connecting(TcpStreamNew),
    WaitHandshake(socks_fut::SocksConnectHandshake)
}

pub struct ConnecterFuture {
    handle: Handle,
    state: State,
    connecter: Rc<Connecter>,
    request: Bytes,
    source: Rc<TcpStream>,
    start: Option<Instant>,
    sa_list: Option<Vec<SocketAddr>>
}

impl Connecter {
    pub fn resolve_connect(self: &Connecter,conn: Rc<Connecter>,
                        source: Rc<TcpStream>,
                        addr: &socks_fut::Addr,
                        request: Bytes) -> ConnecterFuture {
        let state = match *addr {
            socks_fut::Addr::DOMAIN(ref host) => {
                let hlen = host.len();
                let ccode = if (hlen > 4) && (host[hlen-3] == b'.') {
                        // possible country code
                        country_hash(&[host[hlen-2],host[hlen-1]])
                    }
                    else {
                        None
                    };
                match ccode {
                    None => {
                        let mut host = host.to_vec();
                        host.push(b'.');
                        let host = String::from_utf8(host).unwrap();
                        State::Resolve(self.resolver.lookup_ip(&host))
                    },
                    Some(code) => {
                        println!("found country code {}",code2country(code));
                        let codes: Vec<usize> = vec!(code);
                        State::SelectProxy(codes)
                    }
                }
            },
            socks_fut::Addr::IP(ref ip) => {
                let ips = vec!(*ip);
                State::AnalyzeIps(ips)
            }
        };
        ConnecterFuture {
            handle: self.handle.clone(),
            state,
            connecter: conn,
            request,
            source,
            start: None,
            sa_list: None
        }
    }
}

// The connector determines the best proxy based on country.
// Country is derived based on:
//   1. xxx.xxx.<COUNTRY CODE>
//   2. xxx.DOMAIN => loop up
//   3. country(IP)
//
impl Future for ConnecterFuture {
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
                    let mut codes: Vec<usize> = vec!();
                    for ip in ips {
                        let code = self.connecter.determine_country(ip);
                        match code {
                            Some(code) => {
                                if !(codes.contains(&code)) {
                                    codes.push(code);
                                };
                                println!("IP {:?} -> {:?}",ip,code2country(code))
                            },
                            None => 
                                println!("IP {:?} -> unknown country",ip)
                        }
                    };
                    State::SelectProxy(codes)
                },
                State::SelectProxy(ref codes) => {
                    let mut sa_list = self.connecter.select_proxy(codes);
                    self.sa_list = Some(sa_list);
                    State::NextProxy
                }
                State::NextProxy => {
                    match self.sa_list {
                        Some(ref mut sa_list) => {
                            let sa = sa_list.pop();
                            match sa {
                                Some(ref sa) => {
                                    println!("Use proxy @ {:?}",*sa);
                                    State::Connecting(TcpStream::connect(&sa,&self.handle))
                                },
                                None =>
                                    return Err(io::Error::new(io::ErrorKind::Other, "no (more) proxy"))
                            }
                        },
                        None => 
                            return Err(io::Error::new(io::ErrorKind::Other, "weird: no proxy list"))
                    }
                },
                State::Connecting(ref mut fut) => {
                    let proxy = try_ready!(fut.poll());
                    self.start = Some(Instant::now());
                    State::WaitHandshake(socks_fut::socks_connect_handshake(proxy,self.request.clone()))
                },
                State::WaitHandshake(ref mut fut) => {
                    // Trick from Transfer: Make sure we can write the response !
                    // => This avoids storing the response somewhere.
                    let write_ready = self.source.poll_write().is_ready();
                    if !write_ready {
                        return Ok(Async::NotReady)
                    }
                    let (stream,response) = try_ready!(fut.poll());
                    let dt = match self.start {
                        Some(start) => {
                            let dt = start.elapsed();
                            let millis = (dt.as_secs()*1000)+((dt.subsec_nanos()/1_000_000) as u64);
                            Some(millis)
                        },
                        None => None
                    };
                    println!("Time for connection {:?} ms",dt);
                    // Here can measure the round trip until remote socks server
                    // reports success - still that server can cheat for connect to final destination.
                    let m = try!((&*self.source).write(&response.to_vec()));
                    assert_eq!(response.len(), m);
                    return Ok(Async::Ready(stream));
                }
            }
        }
    }
}