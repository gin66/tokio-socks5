#[macro_use]
extern crate log;
extern crate env_logger;
#[macro_use]
extern crate futures;
#[macro_use]
extern crate tokio_core;
extern crate tokio_io;
extern crate tokio_timer;
extern crate trust_dns_resolver;
#[macro_use]
extern crate clap;
extern crate ini;
extern crate bytes;
extern crate csv;

use std::cell::RefCell;
//use std::io::{self, Read, Write};
//use std::net::{Shutdown, IpAddr};
use std::net::{SocketAddr};
//use std::net::{SocketAddr, Ipv4Addr, Ipv6Addr, SocketAddrV4, SocketAddrV6};
//use std::sync::{Arc,Mutex};
//use std::str;
use std::time::{Instant,Duration};
use std::io::ErrorKind::AddrNotAvailable;
use std::rc::Rc;
use futures::{Future, Stream, Sink};
use futures::sync::mpsc;
use futures::sync::mpsc::{Sender, Receiver};
use futures::stream::{SplitSink,SplitStream};
//use tokio_io::io::{read_exact, write_all, Window};
use tokio_core::net::{TcpListener, UdpSocket};
use tokio_core::reactor::{Core, Interval};
use trust_dns_resolver::ResolverFuture;
use trust_dns_resolver::config::*;
use ini::Ini;

mod message;
mod transfer;
mod socks_fut;
mod resolver;
mod connecter;

//
// The following streams/futures are executed:
// 1.) UDP sender
//     It pulls the next message to be sent.
//     In chain to this are:
//      - Transmission rate limiter
//      - select:
//            1.) messages to sent
//            2.) messages to be forwarded
//            3.) network messages
// 2.) For each client connection a TCP sender
//     It pulls the next message to be sent.    

fn main() {
    drop(env_logger::init());

    let i = Ini::load_from_file("config.ini").unwrap();
    for (sec, prop) in i.iter() {
        println!("Section: {:?}", *sec);
        for (k, v) in prop.iter() {
            println!("{}:{}", *k, *v);
        }
    }

    let matches = clap_app!(uservpn_socks5 =>
        (version: crate_version!())
        (author: "Jochen Kiemes <jochen@kiemes.de>")
        (about: "Multi-server multi-client vpn")
        (@arg CONFIG: -c --config +takes_value   "Sets a custom config file")
        (@arg debug:  -d ...                     "Sets the level of debugging information")
        (@arg socks:  -s --socks  +takes_value   "Listening address of socks-server <ip:port>")
        (@arg listen: -l --listen +takes_value   "Listening addresses for peers <ip:port,...>")
        (@arg peers:  -p --peers  +takes_value   "List of known peer servers <ip:port,...>")
        (@arg id: -i --id +takes_value +required "Unique ID of this instance <id>=0..255")
    ).get_matches();

    let addr = matches.value_of("socks").unwrap_or("127.0.0.1:8080");
    let addr = addr.parse::<SocketAddr>().unwrap();

    let mut peer_list: Vec<SocketAddr> = Vec::new();
    if let Some(peers) = matches.value_of("peers") {
        for ad in peers.split(",") {
            let a = ad.clone();
            match ad.parse::<SocketAddr>() {
                Ok(x)  => peer_list.push(x),
                Err(x) => println!("Ignore peer <{}> => {}",a,x),
            }
        }
    }
    info!("{:?}",peer_list);

    let mut listen_list: Vec<SocketAddr> = Vec::new();
    if let Some(listen) = matches.value_of("listen") {
        for ad in listen.split(",") {
            let a = ad.clone();
            match ad.parse::<SocketAddr>() {
                Ok(x)  => listen_list.push(x),
                Err(x) => println!("Ignore listen address <{}> => {}",a,x),
            }
        }
    }
    info!("{:?}",listen_list);

    // Initialize the various data structures we're going to use in our server.
    // Here we create the event loop, the global buffer that all threads will
    // read/write into, and the bound TCP listener itself.
    let mut lp = Core::new().unwrap();
    //let buffer = Rc::new(RefCell::new(vec![0; 64 * 1024]));
    let handle = lp.handle();
    let listener = TcpListener::bind(&addr, &handle).unwrap();

    let mut conn = connecter::Connecter::new(handle.clone());
    conn.read_dbip();

    let my_id = 1;
    let secret = 1;
    let mut udp_sinks:   Vec<SplitSink<tokio_core::net::UdpFramed<message::MessageCodec>>> = vec![]; 
    let mut udp_streams: Vec<SplitStream<tokio_core::net::UdpFramed<message::MessageCodec>>> = vec![]; 
    for ad in listen_list {
        println!("Listening for peer udp connections on {}", ad);
        let comm_udp = UdpSocket::bind(&ad,&handle).unwrap();
        let (udp_sink,udp_stream) = comm_udp.framed(message::MessageCodec {my_id,secret}).split();
        udp_sinks.push(udp_sink);
        udp_streams.push(udp_stream);
    }

    // The udp_sender is connected to a mspc, which receives messages compatible to MessageCodec.
    //
    // If several udp sockets are available, then use round robin for sending.
    //
    let (tx, rx): (Sender<(SocketAddr, Vec<u8>)>,Receiver<(SocketAddr, Vec<u8>)>) = mpsc::channel(100);
    println!("number of listen sockets = {}",udp_sinks.len());
    let counter: Vec<usize> = vec![0];
    let counter = RefCell::new(counter);
    let udp_sender = rx.for_each(move |msg| {
        let mut counter = counter.borrow_mut();
        println!("{:?}",counter);
        let mut cnt = counter[0];
        cnt = if cnt == udp_sinks.len()-1 {
            0
        } else { cnt + 1 };
        counter[0] = cnt;

        let res = udp_sinks[cnt].poll_complete();
        match res {
            Ok(_)  => println!("poll_complete is ok"),
            Err(e) => {
                match e.kind() {
                    AddrNotAvailable => panic!("Peer listen address like 127.0.0.1 does not work"),
                    _ => println!("{:?}",e)
                }
            }
        };
        let _res = udp_sinks[cnt].start_send(msg).unwrap();
        // The stream will stop on `Err`, so we need to return `Ok`.
        Ok(())
    });
    handle.spawn(udp_sender);

    // The duty of the initiator is trying to connect to the peers 
    // unless connection is established. 
    // Connect means to send a Hello message with info about self.
    //
    // Implementation is a periodic task, which basically should do:
    //      1. Iterate through the list of static peers.
    //      2. Check (who) if the peer is already connected
    //      3. If peer is not connected, initiate sending Hello message
    //
    // initiator helds a future to be waited for
    if false {
        let peer_list2 = peer_list.clone();
        let tx2 = tx.clone();
        let handle2 = handle.clone();
        let initiator = Interval::new_at(Instant::now()+Duration::new(1,0),
                                    Duration::new(10,0),&handle).unwrap()
                            .for_each(move |_| {
                                for ad in &peer_list2 {
                                    println!("Send Init to {}",ad);
                                    let thread_tx = tx2.clone();
                                    let buf: Vec<u8> = vec![0;10];
                                    let msg = (ad.clone(),buf);
                                    handle2.spawn(thread_tx.send(msg)
                                                    .then( |_| { Ok(())}));
                                };
                                Ok(())
                            })
                            .then( |_| { Ok(())});
        handle.spawn(initiator);
    }

    if false {
        let handle2 = handle.clone();
        let communicator = Interval::new_at(Instant::now()+Duration::new(1,0),
                                    Duration::new(1,0),&handle).unwrap()
                            .for_each(move |_| {
                                for ad in &peer_list {
                                    println!("Send Data to {}",ad);
                                    let thread_tx = tx.clone();
                                    let buf: Vec<u8> = vec![0;10];
                                    let msg = (ad.clone(),buf);
                                    handle2.spawn(thread_tx.send(msg)
                                                    .then( |_| { Ok(())}));
                                };
                                Ok(())
                            })
                            .then( |_| { Ok(())});
        handle.spawn(communicator);
    }

    // Construct a future representing our server. This future processes all
    // incoming connections and spawns a new task for each client which will do
    // the proxy work.
    //
    // This essentially means that for all incoming connections, those received
    // from `listener`, we'll create an instance of `Client` and convert it to a
    // future representing the completion of handling that client. This future
    // itself is then *spawned* onto the event loop to ensure that it can
    // progress concurrently with all other connections.
    println!("Listening for socks5 proxy connections on {}", addr);
    let handle = lp.handle();
    let conn = Rc::new(conn);
    let server = listener.incoming().for_each(|(socket, _addr)| {
        let conn2 = conn.clone();
        handle.spawn(
            socks_fut::socks_handshake(socket)
                .and_then(move |(source,addr,request,_port,_cmd)| {
                    println!("select best proxy for destination");
                    conn2.resolve_connect(&addr)
                        .and_then(|dest| {
                            socks_fut::socks_connect_handshake(dest,request)
                        })
                        .and_then(|dest|{
                            let c1 = Rc::new(source);
                            let c2 = Rc::new(dest);

                            let half1 = transfer::Transfer::new(c1.clone(), c2.clone());
                            let half2 = transfer::Transfer::new(c2, c1);
                            half1.join(half2)
                        })
                })
                .then( |res| { 
                    match res {
                        Ok(_)  => println!("both connected"),
                        Err(e) => println!("{:?}",e)
                    };
                    Ok(())
                })
        );
        Ok(())
    });

    // Now that we've got our server as a future ready to go, let's run it!
    //
    // This `run` method will return the resolution of the future itself, but
    // our `server` futures will resolve to `io::Result<()>`, so we just want to
    // assert that it didn't hit an error.
    lp.run(server).unwrap();
}

