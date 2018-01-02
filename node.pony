use "logger"

class NodeBuilder
    let _ipdb: IpDB tag
    let _logger: Logger[String]
    let _id: U8
    var _name: String iso
    var _udp_addresses: Array[InetAddrPort ref] iso = recover Array[InetAddrPort ref] end
    var _tcp_addresses: Array[InetAddrPort ref] iso = recover Array[InetAddrPort ref] end

    new iso create(ipdb: IpDB tag, id: U8, name: String, logger: Logger[String]) =>
        _ipdb = ipdb
        _logger = logger
        _id = id
        _name = recover iso name.string() end

    fun ref static_udp(addr: InetAddrPort iso) =>
        _udp_addresses.push(consume addr)

    fun ref static_tcp(addr: InetAddrPort iso) =>
        _udp_addresses.push(consume addr)

    fun ref build() : Node tag =>
        let n = _name = recover "".string() end
        let t = _tcp_addresses = recover Array[InetAddrPort ref] end
        let u = _udp_addresses = recover Array[InetAddrPort ref] end
        Node(_ipdb,_logger, _id, consume n, consume t, consume u)

actor Node
    let _ipdb: IpDB tag
    let _logger: Logger[String]
    let _id: U8
    let _name: String
    let _static_udp: Array[InetAddrPort ref]
    let _static_tcp: Array[InetAddrPort ref]

    new create(ipdb: IpDB tag,
               logger: Logger[String],
               id: U8,
               name: String iso,
               static_tcp: Array[InetAddrPort ref] iso,
               static_udp: Array[InetAddrPort ref] iso
               ) =>
        _ipdb = ipdb
        _logger = logger
        _id = id
        _name = consume name
        _static_tcp = consume static_tcp
        _static_udp = consume static_udp


        _logger(Info) and _logger.log("Create node: " + _name + " with id " + _id.string())
        if (_static_tcp.size() + _static_udp.size()) > 0 then
            _logger(Info) and _logger.log("    Reachable via:")
            for ia in _static_tcp.values() do
                _logger(Info) and _logger.log("        TCP: " + ia.string())
                ipdb.locate(ia.u32())
                    .next[None](recover this~located_at() end)
            end
            for ia in _static_udp.values() do
                _logger(Info) and _logger.log("        UDP: " + ia.string())
                ipdb.locate(ia.u32())
                    .next[None](recover this~located_at() end)
            end
        end

    be located_at(country: String) =>
        _logger(Info) and _logger.log(_name + " is located in " + country.string())

