
use std::io::{self,Write};
use std::net::{SocketAddr,IpAddr, Ipv4Addr, Ipv6Addr};
use std::rc::Rc;
use std::option::Option;
use std::time::Instant;

use futures::{Future, Async, Join};
use tokio_core::net::{TcpStream,TcpStreamNew};
use tokio_core::reactor::Handle;
use trust_dns_resolver::config::*;
use trust_dns_resolver;
use trust_dns_resolver::lookup_ip::LookupIpFuture;
use socksv5_future::*;
use csv;
use database::Database;
use country::{code2country,country_hash};
use transfer::Transfer;

enum RFState {
    Resolve(LookupIpFuture),
    NextIp,
    Connecting(TcpStreamNew),
    SendOK,
    InitiateTransfer,
    WaitTransfer(Join<Transfer,Transfer>)
}

pub struct ResolverFuture {
    handle: Handle,
    state: RFState,
    srr: Option<SocksRequestResponse>,
    source: Option<TcpStream>,
    destination: Option<TcpStream>,
    ips: Vec<IpAddr>
}

impl Future for ResolverFuture
{
    type Item = ();
    type Error = io::Error;

    fn poll(&mut self) -> Result<Async<Self::Item>, Self::Error> {
        println!("Poll");
        loop {
            self.state = match self.state {
                RFState::Resolve(ref mut fut) => {
                    for ip in try_ready!(fut.poll()).iter() {
                        self.ips.push(ip);
                    }
                    println!("{:?}",self.ips);
                    RFState::NextIp
                },
                RFState::NextIp => {
                    println!("NextIP");
                    if let Some(ip) = self.ips.pop() {
                        println!("{:?}",ip);
                        let sa = SocketAddr::new(ip,self.srr.as_ref().unwrap().port());
                        RFState::Connecting(TcpStream::connect(&sa,&self.handle))
                    }
                    else {
                        return Err(io::Error::new(io::ErrorKind::Other, "no (more) host ip"));
                    }
                }
                RFState::Connecting(ref mut fut) => {
                    match fut.poll() {
                        Ok(Async::Ready(destination)) => {
                            self.destination = Some(destination);
                            //self.start = Some(Instant::now());
                            RFState::SendOK
                        },
                        Ok(Async::NotReady) => return Ok(Async::NotReady),
                        Err(_e) => RFState::NextIp
                    }
                },
                RFState::SendOK => {
                    let mut source = self.source.as_ref().unwrap();
                    let write_ready = source.poll_write().is_ready();
                    if !write_ready {
                        return Ok(Async::NotReady)
                    }
                    let mut response = match self.srr {
                        Some(ref req) => req.clone(),
                        None => panic!()
                    };
                    response.bytes[1] = 0;
                    let m = try!(source.write(&response.bytes.to_vec()));
                    assert_eq!(response.bytes.len(), m);
                    RFState::InitiateTransfer
                },
                RFState::InitiateTransfer => {
                    let mut source = self.source.take().unwrap();
                    let mut destination = self.destination.take().unwrap();
                    let c1 = Rc::new(source);
                    let c2 = Rc::new(destination);

                    let half1 = Transfer::new(c1.clone(), c2.clone());
                    let half2 = Transfer::new(c2, c1);
                    RFState::WaitTransfer(half1.join(half2))
                }
                RFState::WaitTransfer(ref mut fut) => {
                    let transferred = try_ready!(fut.poll());
                    return Ok(Async::Ready(()));
                }
            };
        }
        println!("Should Not come here");
        Ok(Async::NotReady)
    }
}

pub struct Connecter {
    dbip_v4: Vec<(Ipv4Addr,Ipv4Addr,usize)>,
    resolver: trust_dns_resolver::ResolverFuture,
    handle: Handle,
    database: Rc<Database>
}

impl Connecter {
    pub fn new(handle: Handle,database: Rc<Database>) -> Connecter {
        let resolver = trust_dns_resolver::ResolverFuture::new(ResolverConfig::default(),
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
                Err(_err) => (),
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

    pub fn lookup_transfer(self: &Connecter, source: TcpStream, srr: SocksRequestResponse) -> ResolverFuture {
        let (ips,state) = match srr.ipaddr() {
                Some(ip) => (vec![ip],RFState::NextIp),
                None => { 
                    let mut host = srr.hostname().unwrap().to_vec();
                    host.push(b'.');
                    let host = String::from_utf8(host).unwrap();    
                    (vec![],RFState::Resolve(self.resolver.lookup_ip(&host)))
                } 
            };
        ResolverFuture {
            handle: self.handle.clone(),
            srr: Some(srr),
            state,
            source: Some(source),
            destination: None,
            ips
        }
    }
}

enum State {
    WaitSocksHandshake(SocksHandshake),
    Resolve(LookupIpFuture),
    AnalyzeIps(Vec<IpAddr>),
    SelectProxy(Vec<usize>),
    NextProxy,
    Connecting(TcpStreamNew),
    WaitHandshake(SocksConnectHandshake),
    WaitTransfer(Join<Transfer,Transfer>)
}

pub struct ConnecterFuture {
    handle: Handle,
    state: State,
    connecter: Rc<Connecter>,
    request: Option<SocksRequestResponse>,
    source: Option<TcpStream>,
    start: Option<Instant>,
    sa_list: Option<Vec<SocketAddr>>
}

impl Connecter {
    pub fn resolve_connect_transfer(self: &Connecter,conn: Rc<Connecter>,
                        source: TcpStream) -> ConnecterFuture {
        let state = State::WaitSocksHandshake(
            socks_handshake(source)
        );
        ConnecterFuture {
            handle: self.handle.clone(),
            connecter: conn,
            request: None,
            state: state,
            source: None,
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
    type Item = ();
    type Error = io::Error;

    fn poll(&mut self) -> Result<Async<Self::Item>, io::Error> {
        loop {
            self.state = match self.state {
                State::WaitSocksHandshake(ref mut fut) => {
                    let (source,request) = try_ready!(fut.poll());
                    self.source = Some(source);
                    let ip_res  = request.ipaddr();
                    let host_res = request.hostname();
                    self.request = Some(request.clone());
                    match ip_res {
                        Some(ip) => {
                            let ips = vec!(ip);
                            State::AnalyzeIps(ips)
                        },
                        None => {
                            match host_res {
                                Some(ref host) => {
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
                                            State::Resolve(self.connecter.resolver.lookup_ip(&host))
                                        },
                                        Some(code) => {
                                            println!("found country code {}",code2country(code));
                                            let codes: Vec<usize> = vec!(code);
                                            State::SelectProxy(codes)
                                        }
                                    }
                                },
                                None => panic!()
                            }
                        }
                    }
                }
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
                    let sa_list = self.connecter.select_proxy(codes);
                    self.sa_list = Some(sa_list);
                    println!("{:?}",self.sa_list);
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
                    match fut.poll() {
                        Ok(Async::Ready(proxy)) => {
                            self.start = Some(Instant::now());
                            let request = match self.request {
                                Some(ref req) => req.clone(),
                                None => panic!()
                            };
                            State::WaitHandshake(socks_connect_handshake(proxy,request))
                        },
                        Ok(Async::NotReady) => return Ok(Async::NotReady),
                        Err(_e) => State::NextProxy
                    }
                },
                State::WaitHandshake(ref mut fut) => {
                    // Trick from Transfer: Make sure we can write the response !
                    // => This avoids storing the response somewhere.
                    match self.source {
                        Some(ref source) => {
                            let write_ready = source.poll_write().is_ready();
                            if !write_ready {
                                return Ok(Async::NotReady)
                            }
                        },
                        None => ()
                    };
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
                    let source = self.source.take();
                    let mut source = source.unwrap();
                    let m = try!(source.write(&response.bytes.to_vec()));
                    assert_eq!(response.bytes.len(), m);

                    let c1 = Rc::new(source);
                    let c2 = Rc::new(stream);

                    let half1 = Transfer::new(c1.clone(), c2.clone());
                    let half2 = Transfer::new(c2, c1);
                    State::WaitTransfer(half1.join(half2))
                },
                State::WaitTransfer(ref mut fut) => {
                    let transferred = try_ready!(fut.poll());
                    return Ok(Async::Ready(()));
                }
            }
        }
    }
}