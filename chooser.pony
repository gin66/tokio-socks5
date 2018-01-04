use "logger"
use "promises"
use "collections"

primitive DirectConnection
type Resolve is (DirectConnection | (U8,Array[InetAddrPort val] val))

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
    let _ipdb:      IpDB
    let _requests:  Map[String,Promise[Resolve]]
    let _myID:      U8
    let _myCountry: String
    let _countries: String = "AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ "
                            +"BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ "
                            +"CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ "
                            +"DE DJ DK DM DO DZ EC EE EG ER ES ET FI FJ FK FM FO FR "
                            +"GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY "
                            +"HK HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP "
                            +"KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY "
                            +"MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ "
                            +"NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY "
                            +"QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ "
                            +"TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ "
                            +"VA VC VE VG VI VN VU WF WS XK YE YT ZA ZM ZW ZZ "

    new create(network: Network, ipdb: IpDB, 
               myID: U8, myCountry: String,
               logger: Logger[String]) =>
        _network   = network
        _ipdb      = ipdb
        _logger    = logger
        _requests  = Map[String,Promise[Resolve]]
        _myID      = myID
        _myCountry = myCountry

    be remove_promise(hstr: String) =>
        try 
            _requests.remove(hstr)?
        end

    be select_connection(dialer: Dialer,addr: InetAddrPort val) =>
        """
        select_connection should first decide on the node.
        In a second step the connection method to be determined.
        => For this the related node can be asked for the available methods.

        BTW: In case node goes down, that host to be removed from the _requests cache.
        In order to do so, the promise to be replaced by the result or only the node info.
        """
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
                    _requests.size().string() + " values in cache")
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
            | (let id: U8,let proxies: Array[InetAddrPort val] val) =>
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

            let last: String val = (try parts(parts.size()-1)? else "" end).upper()
            if (last.size() == 2) and _countries.contains(last + " ") then
                _network.select_node_by_country(last,"CN")
            end
            if _myCountry == last then
                _logger(Info) and _logger.log(hostname + " => DIRECT, because of country")
                p(DirectConnection)
                return
            end
            _logger(Info) and _logger.log(hostname + " => PROXY, no alternative in start_selection")
            try
                let proxy_addr = recover val InetAddrPort.create_from_host_port("127.0.0.1:40002")? end
                let proxies    = recover iso [proxy_addr] end
                let id = _myID // TODO !!!
                p((id,consume proxies))
            end
        else
            let ip = addr.u32()
            let prom = _ipdb.locate(ip)
            let me = recover this~selected_on_ip(p,ip) end
            _logger(Info) and _logger.log("Find out country for " + ip.string())
            prom.next[None]({(dest_country: String)(c=consume me) =>
                c(dest_country)
            })
        end

    be selected_on_ip(p:Promise[Resolve],ip: U32,dest_country: String) =>
        try
            _logger(Info) and _logger.log(ip.string() + " => country: " + dest_country)
            if _myCountry == dest_country then
                _logger(Info) and _logger.log(ip.string() + " => DIRECT, because of country")
                p(DirectConnection)
                return
            end

            _logger(Info) and _logger.log(ip.string() + " => PROXY, no alternative in selected_on_ip")
            let proxy_addr = recover val InetAddrPort.create_from_host_port("127.0.0.1:40002")? end
            let proxies    = recover iso [proxy_addr] end
            let id = _myID // TODO !!!
            p((id,consume proxies))
        end
