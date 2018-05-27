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
extern crate csv;
extern crate socksv5_future;
extern crate termion;
extern crate tui;
extern crate tui_logger;

use std::io;
use std::str::FromStr;
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
use std::{thread, time};
use std::sync;

use log::LevelFilter;
use futures::{Future, Stream, Sink};
use futures::sync::mpsc;
use futures::sync::mpsc::{Sender, Receiver};
use futures::stream::{SplitSink,SplitStream};
use tokio_core::net::{TcpListener, UdpSocket};
use tokio_core::reactor::{Core, Interval};
use ini::Ini;
use socksv5_future::socks_handshake;
use termion::event;
use termion::event::Key;
use termion::input::TermRead;
use tui::Terminal;
use tui::layout::{Direction, Group, Rect, Size};
use tui::style::{Color, Style, Modifier};
use tui::backend::MouseBackend;
use tui::buffer::Buffer;
use tui::widgets::{Axis, BarChart, Block, Borders, Chart, Dataset, Gauge, Item, List, Marker,
                   Paragraph, Row, SelectableList, Sparkline, Table, Tabs, Widget};
use tui_logger::*;

mod message;
mod transfer;
mod country;
mod connecter;
mod database;

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

#[derive(Debug)]
enum Event {
    Input(event::Event),
    Tick,
    Quit
}

struct TuiApp {
    size: Rect,
    state: Vec<TuiWidgetState>,
    dispatcher: Rc<RefCell<Dispatcher<event::Event>>>,
    selected_tab: Rc<RefCell<usize>>
}

fn main() {
    init_logger(LevelFilter::Trace).unwrap();
    set_default_level(LevelFilter::Trace);
    set_hot_buffer_depth(10000);
    move_events();

    set_level_for_target("tui_logger::dispatcher", LevelFilter::Error);
    set_level_for_target("tui::terminal", LevelFilter::Error);
    set_level_for_target("tui::backend::termion", LevelFilter::Error);
    set_level_for_target("hyper::buffer", LevelFilter::Warn);
    set_level_for_target("hyper::header", LevelFilter::Warn);
    set_level_for_target("hyper::http::h1", LevelFilter::Warn);
    set_level_for_target("hyper::client::connect", LevelFilter::Warn);
    set_level_for_target("hyper::client::dns", LevelFilter::Warn);
    set_level_for_target("hyper::client::pool", LevelFilter::Warn);
    set_level_for_target("hyper::proto", LevelFilter::Warn);
    set_level_for_target("hyper::proto::h1::conn", LevelFilter::Warn);
    set_level_for_target("hyper::proto::h1::dispatch", LevelFilter::Warn);
    set_level_for_target("hyper::proto::h1::decode", LevelFilter::Warn);
    set_level_for_target("hyper::proto::h1::encode", LevelFilter::Warn);
    set_level_for_target("hyper::proto::h1::io", LevelFilter::Warn);
    set_level_for_target("hyper::proto::h1::role", LevelFilter::Warn);
    set_level_for_target("mio::poll", LevelFilter::Warn);
    set_level_for_target("mio::sys::unix::kqueue", LevelFilter::Warn);
    set_level_for_target("reqwest::async_impl::response", LevelFilter::Warn);
    set_level_for_target("tokio_core::reactor", LevelFilter::Warn);
    set_level_for_target("tokio_core::reactor::timeout_token", LevelFilter::Warn);
    set_level_for_target("tokio_reactor", LevelFilter::Warn);
    set_level_for_target("tokio_reactor::background", LevelFilter::Warn);
    set_level_for_target("tokio_threadpool::builder", LevelFilter::Warn);
    set_level_for_target("tokio_threadpool::pool", LevelFilter::Warn);

    let matches = clap_app!(uservpn_socks5 =>
        (version: crate_version!())
        (author: "Jochen Kiemes <jochen@kiemes.de>")
        (about: "Multi-server multi-client vpn")
        (@arg CONFIG: -c --config +takes_value   "Sets a custom config file")
        (@arg debug:  -d ...                     "Sets the level of debugging information")
        (@arg listen: -l --listen +takes_value   "Listening addresses for peers <ip:port,...>")
        (@arg peers:  -p --peers  +takes_value   "List of known peer servers <ip:port,...>")
        (@arg id: -i --id +takes_value +required "Unique ID of this instance <id>=0..255")
    ).get_matches();

    let mut database = database::Database::new();

    let config_file = matches.value_of("config").unwrap_or("config.ini");
    let config = Ini::load_from_file(config_file).unwrap();
    if let Err(s) = Rc::get_mut(&mut database).unwrap().read_from_ini(config) {
        error!("{}",s);
        return
    };

    let node_id = matches.value_of("id").unwrap();
    let node_id = u8::from_str(&node_id).unwrap();

    let mut peer_list: Vec<SocketAddr> = Vec::new();
    if let Some(peers) = matches.value_of("peers") {
        for ad in peers.split(",") {
            let a = ad.clone();
            match ad.parse::<SocketAddr>() {
                Ok(x)  => peer_list.push(x),
                Err(x) => error!("Ignore peer <{}> => {}",a,x),
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
                Err(x) => error!("Ignore listen address <{}> => {}",a,x),
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

    let mut connecter = connecter::Connecter::new(handle.clone(),database.clone());
    connecter.read_dbip();

    if false {
        let my_id = 1;
        let secret = 1;
        let mut udp_sinks:   Vec<SplitSink<tokio_core::net::UdpFramed<message::MessageCodec>>> = vec![]; 
        let mut udp_streams: Vec<SplitStream<tokio_core::net::UdpFramed<message::MessageCodec>>> = vec![]; 
        for ad in listen_list {
            info!("Listening for peer udp connections on {}", ad);
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
        info!("number of listen sockets = {}",udp_sinks.len());
        let counter: Vec<usize> = vec![0];
        let counter = RefCell::new(counter);
        let udp_sender = rx.for_each(move |msg| {
            let mut counter = counter.borrow_mut();
            info!("{:?}",counter);
            let mut cnt = counter[0];
            cnt = if cnt == udp_sinks.len()-1 {
                0
            } else { cnt + 1 };
            counter[0] = cnt;

            let res = udp_sinks[cnt].poll_complete();
            match res {
                Ok(_)  => info!("poll_complete is ok"),
                Err(e) => {
                    match e.kind() {
                        AddrNotAvailable => panic!("Peer listen address like 127.0.0.1 does not work"),
                        _ => info!("{:?}",e)
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
                                        info!("Send Init to {}",ad);
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
                                        info!("Send Data to {}",ad);
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
    }

    if let Some(ref node) = database.nodes[node_id as usize] {
        // Construct a future representing our server. This future processes all
        // incoming connections and spawns a new task for each client which will do
        // the proxy work.
        //
        // This essentially means that for all incoming connections, those received
        // from `listener`, we'll create an instance of `Client` and convert it to a
        // future representing the completion of handling that client. This future
        // itself is then *spawned* onto the event loop to ensure that it can
        // progress concurrently with all other connections.
        let connecter = Rc::new(connecter);
        if let Some(addr) = node.socks5_listen_port {
            info!("Listening for socks5 proxy connections on {:?}", addr);
            let handle2 = handle.clone();
            let conn2 = connecter.clone();
            let listener = TcpListener::bind(&addr, &handle2).unwrap();
            let server = listener.incoming().for_each(move |(socket, _addr)| {
                handle2.spawn(
                    conn2.resolve_connect_transfer(conn2.clone(),socket)
                        .then( |res| { 
                            match res {
                                Ok(_)  => info!("both connected"),
                                Err(e) => error!("{:?}",e)
                            };
                            Ok(())
                        })
                );
                Ok(())
            })
            .then( |_| { Ok(())});
            handle.spawn(server)
        }

        if let Some(ref vec_addr) = node.socks_server_ports {
            for addr in vec_addr {
                debug!("Listening for socks5 connections on {:?}", addr);
                let handle2 = handle.clone();
                let conn2 = connecter.clone();
                let listener = TcpListener::bind(&addr, &handle2).unwrap();
                let server = listener.incoming().for_each(move |(socket, _addr)| {
                    let c = conn2.clone();
                    handle2.spawn(
                        socks_handshake(socket)
                            .and_then(move |(stream,srr)| {
                                c.lookup_transfer(stream, srr)
                                 .then(|res| { 
                                    match res {
                                        Ok(_)  => {
                                            debug!("Done");
                                        },
                                        Err(e) => error!("{:?}",e)
                                    };
                                    Ok(())
                                })
                            })
                        .then( |_| { Ok(())})
                    );
                    Ok(())
                })
                .then( |_| { Ok(())});
                handle.spawn(server)
            }
        }
    }

    let backend = MouseBackend::new().unwrap();
    let mut terminal = Terminal::new(backend).unwrap();
    terminal.clear().unwrap();
    terminal.hide_cursor().unwrap();

    //app.state.set_default_level(LevelFilter::Error);

    let (tx, rx) = sync::mpsc::channel();
    let input_tx = tx.clone();
    let timer_tx = tx.clone();

    let (quit_tx, quit_rx) = futures::sync::oneshot::channel::<bool>();

    thread::spawn(move || {
            let one_second = time::Duration::from_millis(1_000);
            loop {
                thread::sleep(one_second);
                if timer_tx.send(Event::Tick).is_err() {
                    break;
                }
            }
        });
    thread::spawn(move || {
            let stdin = io::stdin();
            for c in stdin.events() {
                let evt = c.unwrap();
                if evt == event::Event::Key(event::Key::Char('q')) {
                    input_tx.send(Event::Quit).unwrap();
                    break;
                }
                else {
                    input_tx.send(Event::Input(evt)).unwrap();
                }
            }
        });

    thread::spawn(move || {
        let mut app = TuiApp {
            size: terminal.size().unwrap(),
            state: vec![],
            dispatcher: Rc::new(RefCell::new(Dispatcher::<event::Event>::new())),
            selected_tab: Rc::new(RefCell::new(0))
        };
        loop {
            move_events();
        
            let evt = rx.recv().unwrap();
            trace!("{:?}",evt);
            let mut redraw = false;
            match evt {
                Event::Input(input) =>  {
                    if app.dispatcher.borrow_mut().dispatch(&input) {
                        redraw = true;
                    }
                    else if input == event::Event::Key(event::Key::Char('q')) {
                    }
                },
                Event::Tick => redraw = true,
                Event::Quit => {
                    quit_tx.send(true).unwrap();
                    drop(rx);
                    break;
                }
            }
            if redraw {
                let size = terminal.size().unwrap();
                if size != app.size {
                    terminal.resize(size).unwrap();
                    app.size = size;
                }
                draw(&mut terminal, &mut app).unwrap();
            }
        }
        terminal.show_cursor().unwrap();
        terminal.clear().unwrap();
    });

    lp.run(quit_rx);

    move_events();
}

fn draw(t: &mut Terminal<MouseBackend>, app: &mut TuiApp) -> Result<(), io::Error> {
    let tabs = vec!["ALL","Tab4","Tab5","Tab6"];
    let sel = *app.selected_tab.borrow();

    // add commands to dispatcher
    let sel_tab = if sel+1 < tabs.len() { sel+1 } else { 0 };
    let sel_stab = if sel > 0 { sel-1 } else { tabs.len()-1 };
    let v_sel = app.selected_tab.clone();
    app.dispatcher.borrow_mut().add_listener(
        move |evt| {
            if &event::Event::Unsupported(vec![27,91,90]) == evt {
                *v_sel.borrow_mut() = sel_stab;
                true 
            }
            else if &event::Event::Key(Key::Char('\t')) == evt {
                *v_sel.borrow_mut() = sel_tab;
                true 
            }
            else {
                false
            }
        });
    Group::default()
        .direction(Direction::Vertical)
        .sizes(&[Size::Fixed(3), Size::Min(10)])
        .render(t, &app.size.clone(), |t, chunks| {
            Tabs::default()
                .block(Block::default()
                        .borders(Borders::ALL))
                .titles(&tabs)
                .highlight_style(Style::default().modifier(Modifier::Invert))
                .select(sel)
                .render(t, &chunks[0]);
            match tabs[sel] {
                _ => {
                    while app.state.len() <= sel {
                        app.state.push(TuiWidgetState::new());
                    }
                    TuiLoggerSmartWidget::default()
                        .style_error(Style::default().fg(Color::Red))
                        .style_warn(Style::default().fg(Color::Yellow))
                        .style_info(Style::default().fg(Color::Blue))
                        .style_debug(Style::default().fg(Color::Green))
                        .style_trace(Style::default().fg(Color::Magenta))
                        .state(&app.state[sel])
                        .dispatcher(app.dispatcher.clone())
                        .render(t, &chunks[1]);
                }
            }
        });
    try!(t.draw());
    Ok(())
}
