#[macro_use]
extern crate log;
extern crate env_logger;
extern crate futures;
#[macro_use]
extern crate tokio_core;
extern crate tokio_io;
extern crate trust_dns;
#[macro_use]
extern crate clap;

use std::thread;
use std::cell::RefCell;
//use std::io::{self, Read, Write};
//use std::net::{Shutdown, IpAddr};
use std::net::SocketAddr;
//use std::net::{SocketAddr, Ipv4Addr, Ipv6Addr, SocketAddrV4, SocketAddrV6};
use std::rc::Rc;
//use std::str;
use std::time::{Instant,Duration};
use std::io::ErrorKind::AddrNotAvailable;

use futures::{future,Future, Stream, Sink};
use futures::sync::oneshot;
use futures::sync::mpsc;
use futures::sync::mpsc::{Sender, Receiver};
use futures::stream::{SplitSink,SplitStream};
//use tokio_io::io::{read_exact, write_all, Window};
use tokio_core::net::{TcpListener, UdpSocket};
use tokio_core::reactor::{Core, Interval};
use trust_dns::client::ClientFuture;
use trust_dns::udp::UdpClientStream;

use socks::SocksClient;

mod message;
mod socks;
mod resolver;

fn main() {
    drop(env_logger::init());

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
    let buffer = Rc::new(RefCell::new(vec![0; 64 * 1024]));
    let handle = lp.handle();
    let listener = TcpListener::bind(&addr, &handle).unwrap();

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

    println!("Request");
    let resolver = resolver::xstart(&handle);
    thread::spawn(move ||{
        println!("Spawned");
        let res = resolver.query("127.0.0.1:8080".to_string());
        println!("Done");
        println!("{:?}",res);
        futures::done::<(), ()>(Ok(()))
    });

    println!("Next");
    let (fut_tx, fut_rx) = mpsc::channel::<(String,oneshot::Sender<(SocketAddr, u8)>)>(100);
    let resolver = fut_rx.for_each( |msg| {
        let (s,tx) = msg;
        // Translate the address in s into SocketAddr and Server
        let addr = s.parse::<SocketAddr>().unwrap();
        tx.send( (addr,0) ).unwrap();
        // The stream will stop on `Err`, so we need to return `Ok`.
        Ok(())
    });
    handle.spawn(resolver);

    println!("Send");
    let (res_tx, res_rx) = oneshot::channel::<(SocketAddr, u8)>();
    fut_tx.send( ("127.0.0.1:8080".to_string(),res_tx) ).wait().unwrap();
    println!("{:?}",lp.run(res_rx).unwrap());
    println!("Done");

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
    let initiator = Interval::new_at(Instant::now()+Duration::new(1,0),
                                  Duration::new(10,0),&handle).unwrap()
                        .for_each(|_| {
                            for ad in &peer_list {
                                println!("Send Init to {}",ad);
                                let thread_tx = tx.clone();
                                let buf: Vec<u8> = vec![0;10];
                                let msg = (ad.clone(),buf);
                                thread_tx.send(msg).wait().unwrap();
                            };
                            Ok(())
                        });

    let communicator = Interval::new_at(Instant::now()+Duration::new(1,0),
                                  Duration::new(1,0),&handle).unwrap()
                        .for_each(|_| {
                            for ad in &peer_list {
                                println!("Send Data to {}",ad);
                                let thread_tx = tx.clone();
                                let buf: Vec<u8> = vec![0;10];
                                let msg = (ad.clone(),buf);
                                thread_tx.send(msg).wait().unwrap();
                            };
                            Ok(())
                        });

    // This is the address of the DNS server we'll send queries to. If
    // external servers can't be used in your environment, you can substitue
    // your own.
    let dns = "8.8.8.8:53".parse().unwrap();
    let (stream, sender) = UdpClientStream::new(dns, handle.clone());
    let client = ClientFuture::new(stream, sender, handle.clone(), None);

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
    let clients = listener.incoming().map(move |(socket, addr)| {
        (SocksClient {
            buffer: buffer.clone(),
            dns: client.clone(),
            handle: handle.clone(),
        }.serve(socket), addr)
    });
    let handle = lp.handle();
    let server = clients.for_each(|(client, addr)| {
        handle.spawn(client.then(move |res| {
            match res {
                Ok((a, b)) => {
                    println!("proxied {}/{} bytes for {}", a, b, addr)
                }
                Err(e) => println!("error for {}: {}", addr, e),
            }
            future::ok(())
        }));
        Ok(())
    });

    //let server = server.join(udp_sender);
    //let server = udp_sender.join(server);
    let server = server.join(initiator);
    let server = server.join(communicator);

    // Now that we've got our server as a future ready to go, let's run it!
    //
    // This `run` method will return the resolution of the future itself, but
    // our `server` futures will resolve to `io::Result<()>`, so we just want to
    // assert that it didn't hit an error.
    lp.run(server).unwrap();
}

