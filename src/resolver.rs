
use std::result::Result;
use std::net::SocketAddr;
use std::fmt::Debug;
use tokio_core::reactor::Handle;
use futures::{Future,Stream,Sink};
use futures::sync::oneshot;
use futures::sync::mpsc;

//type MsgReply<A,E> = oneshot::Receiver<Result<A,E>>;
type MsgRequest<Q,A,E> = (Q,oneshot::Sender<Result<A,E>>);
type FutRequest<Q,A,E> = mpsc::Sender<MsgRequest<Q,A,E>>;

//trait Responder {
//    // The type of value for the request
//    type RequestItem;
//
//    // The type of value for the reply
//    type ReplyItem;
//
//    fn run(handle: &Handle) -> FutRequest<Self::RequestItem>;
//
//    fn ask(
//}

pub struct Responder<Q,A,E> {
    fut_tx: FutRequest<Q,A,E>,
}

impl<Q:'static,A:'static,E:'static> Responder<Q,A,E> where E: Debug { 
    pub fn gen_start<F>(handle: &Handle,f:&'static F) -> Responder<Q,A,E>
        where 
            F : Fn(Q) -> Result<A,E>
    {
        let (fut_tx, fut_rx) = mpsc::channel::<MsgRequest<Q,A,E>>(100);
        let resolver = fut_rx.for_each(move |msg| {
            let (q,tx) : (Q,oneshot::Sender<Result<A,E>>) = msg;
            let a = f(q);
            let _res = tx.send(a);
            Ok(())
        });
        handle.spawn(resolver);
        Responder {
            fut_tx,
        }
    }

    pub fn query(&self,q: Q) -> Result<A,E> {
        let (res_tx, res_rx) = oneshot::channel::<Result<A,E>>();
        self.fut_tx.clone().send((q,res_tx)).wait().unwrap();
        let res = res_rx.wait().unwrap(); // ignore futures::Canceled
        res
    }
}

fn resolve(q: String) -> Result<(SocketAddr,u8),String> {
    Ok((q.parse::<SocketAddr>().unwrap(),0))
}

pub fn xstart(handle: &Handle) -> Responder<String,(SocketAddr,u8),String> {
    Responder::gen_start(&handle,&resolve)
}


//pub fn start(handle: &Handle) -> FutRequest<String,(SocketAddr,u8)> {
//    let (fut_tx, fut_rx) = mpsc::channel::<MsgRequest<String,(SocketAddr, u8)>>(100);
//    let resolver = fut_rx.for_each( |msg| {
//        let (s,tx) = msg;
        //// Translate the address in s into SocketAddr and Server
//        let addr = s.parse::<SocketAddr>().unwrap();
//        tx.send( Ok((addr,0)) ).unwrap();
//        // The stream will stop on `Err`, so we need to return `Ok`.
//        Ok(())
//    });
//    handle.spawn(resolver);
//    fut_tx
//}
   
//pub fn oresolve(address: String, fut_tx: &FutRequest<String,(SocketAddr,u8)>) -> MsgReply<(SocketAddr,u8)> {

//    println!("Send");
//    let (res_tx, res_rx) = oneshot::channel::<Result<(SocketAddr, u8),()>>();
//    let fut_tx = fut_tx.clone();
//    fut_tx.send( (address.to_string(),res_tx) ).wait().unwrap();
    //println!("{:?}",lp.run(res_rx).unwrap());
    //println!("Done");


    // This is the address of the DNS server we'll send queries to. If
    // external servers can't be used in your environment, you can substitue
    // your own.
    //let dns = "8.8.8.8:53".parse().unwrap();
    //let (stream, sender) = UdpClientStream::new(dns, handle.clone());
    //let client = ClientFuture::new(stream, sender, handle.clone(), None);
//    res_rx
//}

