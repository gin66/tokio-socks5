
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
            F : Fn((Q,oneshot::Sender<Result<A,E>>)) -> Result<(),()>
    {
        let (fut_tx, fut_rx) = mpsc::channel::<MsgRequest<Q,A,E>>(100);
        let resolver = fut_rx.for_each(move |msg| f(msg));
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

fn resolve(msg: (String,oneshot::Sender<Result<(SocketAddr,u8),String>>)) -> Result<(),()> {
    let (q,tx) = msg;
    let a = Ok((q.parse::<SocketAddr>().unwrap(),0));
    let _res = tx.send(a);
    Ok(())
}

pub fn start(handle: &Handle) -> Responder<String,(SocketAddr,u8),String> {
    Responder::gen_start(&handle,&resolve)
}

