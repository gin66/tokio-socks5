use "net"
use "logger"

primitive DirectConnection
primitive SocksConnection
primitive TCPUDPchannel

type Connection is (  DirectConnection | TCPUDPchannel | SocksConnection)

class RouteInfo
    let connection: Connection
    let socks:             (None|InetAddrPort val)
    var sum_round_trip_ms: U64  = 0
    var nr_connections:    U32  = 0
    var down:              Bool = false
    var down_count:        U32  = 0
    
    new trn create(connection': Connection, socks': (None|InetAddrPort iso) = None) =>
        connection = connection'
        if socks' is None then
            socks = None
        else 
            socks = consume socks'
        end

class NodeBuilder
    let _network: Network
    let _auth:    AmbientAuth val
    let _ipdb:    IpDB tag
    let _logger:  Logger[String]
    let _id: U8
    let _self: Bool
    var _name: String iso
    var _country: String = "ZZ"
    var _udp_addresses: Array[InetAddrPort ref] iso = recover Array[InetAddrPort ref] end
    var _tcp_addresses: Array[InetAddrPort ref] iso = recover Array[InetAddrPort ref] end

    new iso create(network: Network, auth: AmbientAuth, ipdb: IpDB tag, id: U8, 
                   self: Bool, name: String, logger: Logger[String]) =>
        _network = network
        _auth    = auth
        _ipdb    = ipdb
        _logger  = logger
        _id      = id
        _self    = self
        _name    = recover iso name.string() end

    fun ref static_udp(addr: InetAddrPort iso) =>
        _udp_addresses.push(consume addr)

    fun ref static_tcp(addr: InetAddrPort iso) =>
        _tcp_addresses.push(consume addr)

    fun ref set_country(country: String) =>
        _country = country

    fun ref build() : Node tag =>
        let n = _name = recover "".string() end
        let t = _tcp_addresses = recover Array[InetAddrPort ref] end
        let u = _udp_addresses = recover Array[InetAddrPort ref] end
        Node(_network, _auth, _ipdb,_logger, _id, _self, consume n, consume t, consume u, _country)

actor Node
    """
    For socks proxy: Node provides a prepared TCPConnection
    """
    let _network: Network
    let _auth:    AmbientAuth val
    let _ipdb:    IpDB tag
    let _logger:  Logger[String]
    let _id: U8
    let _self: Bool
    let _name: String
    let _static_udp : Array[InetAddrPort ref]
    let _static_tcp : Array[InetAddrPort ref]
    var _country: String = "ZZ"
    // This node is reachable via client accessible socks proxy
    let _routes: Array[RouteInfo trn] = Array[RouteInfo trn]
    var connection_count: USize = 0

    new create(network: Network,
               auth: AmbientAuth,
               ipdb: IpDB tag,
               logger: Logger[String],
               id: U8,
               self: Bool,
               name: String iso,
               static_tcp: Array[InetAddrPort ref] iso,
               static_udp: Array[InetAddrPort ref] iso,
               country: String) =>
        _network = network
        _auth    = auth
        _ipdb    = ipdb
        _logger  = logger
        _id   = id
        _self = self
        _name = consume name
        _static_tcp = consume static_tcp
        _static_udp = consume static_udp
        _country = country

        _logger(Info) and _logger.log("Create node: " + _name + " with id " + _id.string())

    be display() =>
        if (_static_tcp.size() + _static_udp.size()) > 0 then
            _logger(Info) and _logger.log("    Reachable via:")
            for ia in _static_tcp.values() do
                _logger(Info) and _logger.log("        TCP: " + ia.string())
                _ipdb.locate([ia.u32()])
                    .next[None](recover this~located_at() end)
            end
            for ia in _static_udp.values() do
                _logger(Info) and _logger.log("        UDP: " + ia.string())
                _ipdb.locate([ia.u32()])
                    .next[None](recover this~located_at() end)
            end
            for route in _routes.values() do
                match route.connection
                | SocksConnection => _logger(Info) and _logger.log("        SOCKS: " + route.socks.string())
                | DirectConnection => _logger(Info) and _logger.log("        DIRECT")
                | TCPUDPchannel => _logger(Info) and _logger.log("        TCPUDP channel")
                end
            end
        end

    be located_at(country: String) =>
        if _country != country then
            if _country != "ZZ" then
                _logger(Error) and _logger.log(_name + ": OLD LOCATION is " + _country.string()
                      + ", new location is " + country.string() )
            else
                _logger(Info) and _logger.log(_name + " is located in " + country.string())
            end
            _country = country
            _network.country_of_node(_id,_country)
        end

    be add_socks_proxy(ia: InetAddrPort iso) =>
        let conn = SocksConnection
        let ri = recover iso RouteInfo(consume conn,consume ia) end
        _routes.push(consume ri)

    be provide_connection_to_you(dialer: Dialer,conn: TCPConnection) =>
        _logger(Info) and _logger.log("Provide connection to "+_name)
        connection_count = connection_count + 1
        let i = connection_count % _routes.size()
        try
            let route = _routes(i)?
            match route.connection
            | SocksConnection =>
                match route.socks
                |   let ia:InetAddrPort val =>
                    TCPConnection(_auth,
                        Socks5OutgoingTCPConnectionNotify(dialer,conn,_logger),
                        ia.host_str(),
                        ia.port_str()
                        where init_size=16384,max_size = 16384)
                end
            end
        end
