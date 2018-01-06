use "logger"
use "promises"
use "collections"

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
    let _forbidden: Map[String,String] = Map[String,String]
    let _myID:      U8
    let _myCountry: String
    var _conn_count:U32 = 0
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
        _conn_count = _conn_count+1
        _logger(Info) and _logger.log(_conn_count.string() + ": select path for destination " + addr.string())
        let p: Promise[Resolve] = (
            let hstr: String val = addr.host_str()
            try
                let pold = _requests(hstr)?
                _logger(Fine) and _logger.log("Use cached value for " + addr.string()) // must be here
                pold
            else
                let pnew = Promise[Resolve]
                _requests(hstr) = pnew
                _logger(Fine) and _logger.log("Have " + 
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
            | let nodes: Array[Node tag] val =>
                dialer.connect_socks5_to(nodes)
            end
            r
        },{()? =>
            dialer.select_timeout()
            error 
        })

    be add_forbidden(key: String, forbidden:String) =>
        _logger(Fine) and _logger.log("add forbidden " + key + ": " + forbidden)
        _forbidden.update(key,forbidden)
    
    fun forbidden_by_hostname(hostname: String,domain: String): String =>
        _forbidden.get_or_else(hostname,_forbidden.get_or_else(domain,""))

    be start_selection(p:Promise[Resolve],addr: InetAddrPort val) =>
        _logger(Fine) and _logger.log("select path for destination " + addr.string())
        if addr.has_real_name then
            let hostname = addr.host_str()
            let parts = hostname.split(".")
            let pn = parts.size()
            let domain = (try "." + parts(pn-2)? + "." + parts(pn-1)? else hostname end)

            let last: String val = (try parts(pn-1)? else "" end).upper()
            if _myCountry == last then
                _logger(Fine) and _logger.log(hostname + " => DIRECT, because of country from hostname")
                p(DirectConnection)
                return
            end

            let forbidden = forbidden_by_hostname(hostname.string(),domain)
            _logger(Fine) and _logger.log(hostname + " => forbidden countries: " + forbidden)
            if (last.size() == 2) and _countries.contains(last + " ") then
                _network.select_node_by_countries(p,_myID,_myCountry,last,forbidden)
            else
                // Need to resolve hostname to ip(s)
                let pdns = _network.dns_resolve(addr)
                let me2 = recover this~_convert_ips_to_country(p,forbidden) end
                pdns.next[None]({ (ips:Array[U32] val)(call=consume me2) =>
                    call(ips) 
                })
            end
        else
            _convert_ips_to_country(p,"",[addr.u32()])
        end

    be _convert_ips_to_country(p:Promise[Resolve],forbidden:String,ips: Array[U32] val) =>
        let prom = _ipdb.locate(ips)
        for ip in ips.values() do
            _logger(Fine) and _logger.log("Find out country for " + ip.string())
        end
        prom.next[None]({(dest_countries: String) =>
            """
            At this point the destination has been mapped to a comma separated list of countries.
            Eventually some countries are forbidden as derived from hostname analysis.
            The complex process to select the node is delegated to the network
            """
            _logger(Fine) and _logger.log("Destination countries: " + dest_countries)
            _network.select_node_by_countries(p,_myID,_myCountry,forbidden,dest_countries)
        })

    be successful_connection(addr: InetAddrPort val,node: Node) =>
        let hstr: String val = addr.host_str()
        let pnew = Promise[Resolve]
        _requests(hstr) = pnew
        pnew([node])
