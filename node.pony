use "logger"

class NodeBuilder
    let _network: Network
    let _ipdb: IpDB tag
    let _logger: Logger[String]
    let _id: U8
    let _self: Bool
    var _name: String iso
    var _country: String = "ZZ"
    var _udp_addresses: Array[InetAddrPort ref] iso = recover Array[InetAddrPort ref] end
    var _tcp_addresses: Array[InetAddrPort ref] iso = recover Array[InetAddrPort ref] end

    new iso create(network: Network, ipdb: IpDB tag, id: U8, self: Bool, name: String, logger: Logger[String]) =>
        _network = network
        _ipdb = ipdb
        _logger = logger
        _id = id
        _self = self
        _name = recover iso name.string() end

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
        Node(_network, _ipdb,_logger, _id, _self, consume n, consume t, consume u, _country)

actor Node
    let _network: Network
    let _ipdb: IpDB tag
    let _logger: Logger[String]
    let _id: U8
    let _self: Bool
    let _name: String
    let _static_udp : Array[InetAddrPort ref]
    let _static_tcp : Array[InetAddrPort ref]
    var _country: String = "ZZ"
    // This node is reachable via client accessible socks proxy
    let _socks_proxy: Array[InetAddrPort ref] = Array[InetAddrPort ref]

    new create(network: Network,
               ipdb: IpDB tag,
               logger: Logger[String],
               id: U8,
               self: Bool,
               name: String iso,
               static_tcp: Array[InetAddrPort ref] iso,
               static_udp: Array[InetAddrPort ref] iso,
               country: String) =>
        _ipdb = ipdb
        _logger = logger
        _network = network
        _id = id
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
                _ipdb.locate(ia.u32())
                    .next[None](recover this~located_at() end)
            end
            for ia in _static_udp.values() do
                _logger(Info) and _logger.log("        UDP: " + ia.string())
                _ipdb.locate(ia.u32())
                    .next[None](recover this~located_at() end)
            end
            for ia in _socks_proxy.values() do
                _logger(Info) and _logger.log("        SOCKS: " + ia.string())
                _ipdb.locate(ia.u32())
                    .next[None](recover this~located_at() end)
            end
        end

    be located_at(country: String) =>
        if _country != country then
            if _country != "ZZ" then
                _logger(Error) and _logger.log("??? OLD LOCATION " + _country.string())
            else
                _logger(Info) and _logger.log(_name + " is located in " + country.string())
            end
            _country = country
            _network.country_of_node(_id,_country)
        end

    be add_socks_proxy(ia: InetAddrPort iso) =>
        _socks_proxy.push(consume ia)
