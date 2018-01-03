use "logger"
use "promises"
use "collections"

primitive DirectConnection
type Resolve is (DirectConnection | Array[InetAddrPort val] val)

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
    let _logger :   Logger[String]
    let _network:   Network
    let _requests:  Map[String,Promise[Resolve]]
    let _myCountry: String

    new create(network: Network, myCountry: String, logger: Logger[String]) =>
        _network   = network
        _logger    = logger
        _requests  = Map[String,Promise[Resolve]]
        _myCountry = myCountry

    be remove_promise(hstr: String) =>
        try 
            _requests.remove(hstr)?
        end

    be select_connection(dialer: Dialer,addr: InetAddrPort val) =>
        _logger(Info) and _logger.log("select path for destination " + addr.string())
        let p: Promise[Resolve] = (
            let hstr: String val = addr.host_str()
            try
                let pold = _requests(hstr)?
                _logger(Info) and _logger.log("Use cached value for " + addr.string())
                pold
            else
                let pnew = Promise[Resolve]
                _requests(hstr) = pnew
                _logger(Info) and _logger.log("Have " + 
                    _requests.size().string() + " cached values")
                pnew.timeout(5_000_000_000) // MAGIC NUMBER
                let me = recover tag this end
                pnew.next[Resolve]({(r:Resolve) =>
                    // Use Map as cache for previous results. Not sure, if good or bad
                    // In general this is quite elegant :-)
                    //me.remove_promise(hstr)
                    r
                },{()? =>
                    me.remove_promise(hstr)
                    error 
                })
                start_selection(pnew,addr)
                pnew
            end)

        p.next[Resolve]({(r:Resolve) => 
            match r
            | DirectConnection =>
                dialer.connect_direct()
            | let proxies: Array[InetAddrPort val] val =>
                dialer.connect_socks5_to(proxies)
            end
            r
        },{()? =>
            dialer.select_timeout()
            error 
        })

    be start_selection(p:Promise[Resolve],addr: InetAddrPort val) =>
        _logger(Info) and _logger.log("select path for destination " + addr.string())
        if addr.has_real_name then
            let hostname = addr.host_str()
            let parts = hostname.split(".")
            let country  = _myCountry.lower()

            _logger(Info) and _logger.log(country + " " + addr.string())
            try
                if country == parts(parts.size()-1)? then
                    _logger(Info) and _logger.log(hostname + " => DIRECT, because of country")
                    p(DirectConnection)
                    return
                else   
                    _logger(Info) and _logger.log(hostname + " => " + parts(parts.size()-1)?)
                end
            end
        else
            let ip = addr.u32()
        end


        try
            let proxy_addr = recover val InetAddrPort.create_from_host_port("127.0.0.1:40002")? end
            let proxies    = recover iso [proxy_addr] end
            p(consume proxies)
        end
