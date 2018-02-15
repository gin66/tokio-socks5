
use std::io::{self};
use std::net::{SocketAddr,IpAddr, Ipv4Addr, Ipv6Addr};
use std::rc::Rc;
use std::option::Option;

use futures::{Future, Async};
use tokio_core::net::{TcpStream,TcpStreamNew};
use tokio_core::reactor::Handle;
use trust_dns_resolver::config::*;
use trust_dns_resolver::ResolverFuture;
use trust_dns_resolver::lookup_ip::LookupIpFuture;
use socks_fut;
use csv;
use bytes::Bytes;

const COUNTRY: &str = "mmsmcmgbbssbmasccgmtgsggtmpsamncatclbgpmkmlsttngagisnpalckptkgnaimvcitla\
                       esknltfmdmusinilkecnfkrsvgdkhtvaumfieglrughnzmhkidjpgetreerwslvnuafjmzad\
                       zzwfomytdebarobthuyebliqaxkzbviobnebjocvuzbfrcdobhrsjeplucobirsopnocfbos\
                       dpkwcrbdsxpemogrczbwshprmwgfchbztoszpfmxgqcybqaotzsyphmqgycwbyaztwsepyme\
                       gwcubeaqvetjsrpwnrmrlykygucxbraw";
static SLOTS_I: &'static [usize] = &[12, 255, 3, 79, 286, 105, 5, 117, 308, 148, 39, 41, 0, 29, 228, 25, 270, 306,
                                     1, 18, 81, 65, 240, 254, 149, 140, 154, 7, 146, 222, 292, 186, 36, 192, 203,
                                     179, 167, 164, 11, 176, 213, 131, 260, 316, 8, 158, 162, 172, 234, 169, 276,
                                     246, 47, 6, 255, 97, 124, 242, 22, 113, 49, 150, 255, 109, 17, 61, 255, 37,
                                     256, 230, 20, 23, 312, 196, 288, 255, 272, 142, 71, 137, 48, 139, 63, 180,
                                     122, 54, 28, 255, 262, 255, 294, 155, 13, 32, 103, 255, 318, 168, 255, 278,
                                     33, 151, 255, 77, 19, 159, 255, 298, 59, 69, 24, 45, 248, 255, 255, 126, 255,
                                     44, 255, 101, 280, 53, 255, 264, 255, 226, 252, 123, 268, 141, 255, 217, 198,
                                     38, 208, 255, 255, 255, 238, 26, 58, 116, 62, 302, 30, 284, 177, 91, 46, 255,
                                     85, 145, 255, 75, 144, 255, 209, 52, 255, 304, 255, 88, 135, 60, 99, 119,
                                     255, 115, 118, 40, 74, 114, 57, 255, 93, 193, 255, 100, 160, 218, 255, 310,
                                     170, 132, 2, 51, 206, 255, 255, 300, 9, 43, 255, 95, 255, 224, 266, 250, 31,
                                     255, 15, 189, 255, 211, 16, 244, 67, 255, 56, 34, 4, 27, 10, 14, 215, 282,
                                     255, 21, 236, 83, 195, 73, 90, 201, 255, 255, 220, 255, 255, 290, 182, 274,
                                     314, 258, 232, 102, 255, 66, 255, 296, 255, 96, 255, 173, 152, 255, 255, 255,
                                     134, 121, 98, 255, 80, 255, 190, 183, 70, 35, 55, 255, 255, 255, 255, 255,
                                     165, 143, 87, 89, 255, 128, 255, 108, 255, 110, 42, 76, 199, 133, 255, 255,
                                     255, 255, 129, 72, 125, 106, 138, 92, 255, 78, 136, 147, 255, 127, 187, 255,
                                     112, 255, 255, 255, 255, 255, 104, 156, 255, 255, 255, 94, 82, 111, 255, 130,
                                     120, 107, 161, 184, 255, 255, 255, 255, 86, 64, 84, 174, 255, 166, 204, 50, 68];
static R: &'static [isize] = &[1, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
                               255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
                               255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
                               255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
                               255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
                               255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
                               255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
                               255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
                               255, 255, 255, 255, 65, -61, 33, 222, 175, 122, 255, 234, -69, 255, 137, 210, 255,
                               70, 80, 101, 7, -55, 9, 255, -36, 10, 255, 25, 200, 44, 183, 31, 145, 255, 190,
                               -100, 255, 16, -59, 255, 128, 255];

//   let _countries: String = "AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ "
//                            +"BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ "
//                            +"CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ "
//                            +"DE DJ DK DM DO DZ EC EE EG ER ES ET FI FJ FK FM FO FR "
//                            +"GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY "
//                            +"HK HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP "
//                            +"KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY "
//                            +"MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ "
//                            +"NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY "
//                            +"QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ "
//                            +"TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ "
//                            +"VA VC VE VG VI VN VU WF WS XK YE YT ZA ZM ZW ZZ ";
fn code2country(code: usize) -> String {
    COUNTRY[code..(code+2)].to_string()
}

fn country_hash(cn_code: &[u8;2]) -> Option<usize> {
    const T: usize = 178;
    const NEG_OFFSET: usize = 0;
    let x: usize = (((cn_code[0] as u16)<<8)+(cn_code[1] as u16)) as usize;
    if x < NEG_OFFSET {
        return None;
    };
    let val = x - NEG_OFFSET;
    let x = val % T;
    let y = val / T;
    let dr = R[y];
    if dr == 255 {
        return None;
    };
    let x = (x as isize) + dr;
    if x < 0 {
        return None;
    }
    let x = x as usize;
    if x >= SLOTS_I.len() {
        return None;
    }
    let code = SLOTS_I[x];
    if code == 255 {
        return None;
    }
    Some(code)
}

pub struct Connecter {
    dbip_v4: Vec<(Ipv4Addr,Ipv4Addr,usize)>,
    resolver: ResolverFuture,
    handle: Handle
}

impl Connecter {
    pub fn new(handle: Handle) -> Connecter {
        let resolver = ResolverFuture::new(ResolverConfig::default(),
                                        ResolverOpts::default(), 
                                        &handle);
        Connecter {
            dbip_v4: vec!(),
            resolver,
            handle
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
}

enum State {
    Resolve(LookupIpFuture),
    AnalyzeIps(Vec<IpAddr>),
    SelectProxy(Vec<usize>),
    Connecting(TcpStreamNew),
    WaitHandshake(socks_fut::SocksConnectHandshake)
}

pub struct ConnecterFuture {
    handle: Handle,
    state: State,
    connecter: Rc<Connecter>,
    request: Bytes
}

impl Connecter {
    pub fn resolve_connect(self: &Connecter,conn: Rc<Connecter>,
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
            request
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
                    let sa = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)), 40002);
                    State::Connecting(TcpStream::connect(&sa,&self.handle))
                },
                State::Connecting(ref mut fut) => {
                    let proxy = try_ready!(fut.poll());
                    State::WaitHandshake(socks_fut::socks_connect_handshake(proxy,self.request.clone()))
                },
                State::WaitHandshake(ref mut fut) => {
                    return fut.poll();
                }
            }
        }
    }
}