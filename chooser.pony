use "logger"
use "promises"
use "collections"

type Resolve is (InetAddrPort val | Array[InetAddrPort val] val)

actor Chooser
    """
    The Chooser shall select the best path for the system.
    A path is determined by node and route.

    Available nodes are:
    - Client itself
    - Static nodes from secure net
    - Dynamic nodes from secure net
    - Socks proxy hosts

    Available routes:
    - Direct connection
    - Socks proxy
    - (later) encrypted TCP/UDP channel

    The Chooser is single actor in the system.
    Rationale:
    If two connections are established to same destination, the determination
    need to be done only once.
    """
    let _logger :  Logger[String]
    let _network:  Network
    let _requests: Map[String,Promise[Resolve]]

    new create(network: Network, logger: Logger[String]) =>
        _network  = network
        _logger   = logger
        _requests = Map[String,Promise[Resolve]]

    be select_connection(dialer: Dialer,addr: InetAddrPort iso) =>
        _logger(Info) and _logger.log("Chooser: select path for destination " + addr.string())
        let p: Promise[Resolve] = (
            let hstr: String val = addr.host_str()
            try
                _requests(hstr)?
            else
                let pnew = Promise[Resolve]
                _requests(hstr) = pnew
                pnew.timeout(5_000_000_000) // MAGIC NUMBER
                start_selection(pnew,consume addr)
                pnew
            end)

        p.next[Resolve]({(r:Resolve) => 
            match r
            | let addr: InetAddrPort val =>
                dialer.connect_direct(addr)
            | let proxies: Array[InetAddrPort val] val =>
                dialer.connect_socks5_to(proxies)
            end
            r
        },{()? =>
            dialer.select_timeout()
            error 
        })

    be start_selection(p:Promise[Resolve],addr: InetAddrPort val) =>
        if addr.has_real_name then
            _logger(Info) and _logger.log("Chooser: select path for destination " + addr.string())
        end

        p(addr)

        try
            let proxy_addr = recover val InetAddrPort.create_from_host_port("127.0.0.1:40005")? end
            let proxies    = recover iso [proxy_addr] end
            //dialer.connect_socks5_to(consume proxies)
        end
