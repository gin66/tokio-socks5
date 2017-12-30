
use std::result::Result;
use std::net::SocketAddr;
use std::fmt::Debug;
use tokio_core::reactor::Handle;
use futures::{Future,Stream,Sink};
use futures::sync::oneshot;
use futures::sync::mpsc;

type MsgRequest<Q,A,E> = (Q,oneshot::Sender<Result<A,E>>);
type FutRequest<Q,A,E> = mpsc::Sender<MsgRequest<Q,A,E>>;
type MsgReply<A,E> = oneshot::Receiver<Result<A,E>>;

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

#[derive(Debug)]
pub struct Responder<Q,A,E> {
    fut_tx: FutRequest<Q,A,E>,
    handle: Handle
}

impl<Q:'static,A:'static,E:'static> Responder<Q,A,E> where E: Debug { 
    pub fn gen_start<F>(handle: Handle,f:&'static F) -> Responder<Q,A,E>
        where 
            F : Fn((Q,oneshot::Sender<Result<A,E>>)) -> Result<(),()>
    {
        println!("Spawn/Create Responder...");
        let (fut_tx, fut_rx) = mpsc::channel::<MsgRequest<Q,A,E>>(100);
        handle.spawn(fut_rx.and_then(move |msg| f(msg)).for_each(|_|{Ok(())}));
        Responder {
            fut_tx,
            handle
        }
    }

    pub fn query(&self, q: Q) -> MsgReply<A,E> {
        println!("enter query");
        let (res_tx, res_rx) = oneshot::channel::<Result<A,E>>();
        println!("send query");
        let fut_tx = self.fut_tx.clone();
        self.handle.spawn(fut_tx.send((q,res_tx)).then( |_| { Ok(())}));
        res_rx
    }
}

impl<Q: 'static,A: 'static,E: 'static> Clone for Responder<Q,A,E> {
    fn clone(&self) -> Self {
        Responder { fut_tx: self.fut_tx.clone(), handle: self.handle.clone() }
    }
}

fn resolve(msg: (String,oneshot::Sender<Result<(SocketAddr,u8),String>>)) -> Result<(),()> { 
    println!("resolve");
    let (q,tx) = msg;
    let a = Ok((q.parse::<SocketAddr>().unwrap(),0));
    tx.send(a).unwrap();
    Ok(())
}

pub fn start(handle: Handle) -> Responder<String,(SocketAddr,u8),String> {
    Responder::gen_start(handle,&resolve)
}

