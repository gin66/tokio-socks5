use "net"
use "logger"
use "collections"

actor Dialer
    """
    The dialer is created by the Socks5 Notifier of an incoming connection.
    Depending on further selection, the dialer will even establish
    a direct outgoing connection or a connection to a selected node.
    This connection can either using one of defined socks5-proxy from 
    the ini-file or using the encrypted UDP/TCP channel.

    In all cases the Socks5 Notifier of the incoming connection will be replaced.
    Ideally only with the DirectForwardTCPConnectionNotify.

    The difference between direct outgoing connection and socks5-proxy is:
            1. The socks5-proxy has to perform the initial socks5 greeting:
                    Send message \x05\x01\x00 and expect message \x05\x00
            2. The Socks5 request from the incoming connection can then be sent:
                    a) direct connection: send back to client
                       What ever comes first:
                            OK reply          => on connect
                            Connection Reject => on connection fail
                    b) proxy connection: unmodified via the outgoing channel
                       This connection is already established, thus only inject
                       the socks message to be sent to the outside
            3. Afterwards both connections are just transparent forwarding 
               taking throttling from the TCPConnection into consideration.
               => Ideally identical Notifier
    
    Consequently the idea is to have one Socks5-Client Notifier for the greeting as #1
    and then use only the DirectForwardTCPConnectionNotifier. The needed messages
    as per #2 can be ejected by the dialer into the tcp stream.

    In case of two proxies to the same node, actually both socks5-proxies can be
    connected in step #1. In case both are dead, then failover to UDP/TCP channel
    to be done.
    """
    let _auth:      AmbientAuth val
    let _chooser:   Chooser
    let _logger:    Logger[String]
    let _addr:      InetAddrPort val
    let _conn:      TCPConnection tag
    let _conns:     Array[TCPConnection tag] = Array[TCPConnection tag]
    var _request:   Array[U8] iso
    var _node_i:    USize = 0
    var _nodes:     Array[Node tag] val = recover Array[Node tag] end
    var _route_id:  USize = USize.max_value()

    new create(auth: AmbientAuth val,
               chooser: Chooser,
               conn: TCPConnection tag,
               addr: InetAddrPort iso,
               socks_request: Array[U8] iso,
               logger: Logger[String]) =>
        _auth    = auth
        _chooser = chooser
        _logger  = logger
        _conn    = conn
        _addr    = consume addr
        _request = consume socks_request
        _chooser.select_connection(this, _addr)

    be roundtrip_ms(data_round_trip_ms: U64) =>
        _logger(Info) and _logger.log("Data roundtrip in ms:" + data_round_trip_ms.string())
        try 
            let node = _nodes(_node_i)?
            _chooser.successful_connection(_addr,node)
            node.record_roundtrip_ms(_route_id,data_round_trip_ms)
        end

    be select_timeout() =>
        let empty: Array[U8] iso = recover iso Array[U8]() end
        let data = _request = consume empty
        try 
            data(1)? = Socks5.reply_host_unreachable()
            _conn.write(consume data)
        end
        _conn.dispose()

    be connect_direct() =>
        _conn.mute()
        let empty: Array[U8] iso = recover iso Array[U8]() end
        let req = _request = consume empty
        let conn_peer = TCPConnection(_auth,
                            DirectForwardTCPConnectionNotify(this,
                                                             _conn,
                                                            false,
                                                             consume req,
                                                             _logger),
                                _addr.host_str(),
                                _addr.port_str()
                                where init_size=16384,max_size = 16384)
        _conn.set_notify(DirectForwardTCPConnectionNotify(
                            this,conn_peer,true where logger = _logger))
        _conn.unmute()

    fun ref try_next_node() =>
        try
            let node = _nodes(_node_i)?
            node.provide_connection_to_you(this,_conn)
        else
            let empty: Array[U8] iso = recover iso Array[U8]() end
            let data = _request = consume empty
            try 
                data(1)? = Socks5.reply_conn_refused()
                _conn.write(consume data)
            end
            _conn.dispose()
        end

    be connect_socks5_to(nodes: Array[Node tag] val) =>
        _logger(Info) and _logger.log("called connect_socks5_to")
        _nodes = nodes
        try_next_node()

    be outgoing_socks_connection_succeeded(peer: TCPConnection) => 
        """
        Connection to a socks proxy has succeeded. Send him the original socks_request.
        All else is just protocol
        """
        _logger(Info) and _logger.log("Outgoing socks connection succeeded")
        _conn.set_notify(DirectForwardTCPConnectionNotify(
                                this,peer,true  where logger = _logger))
        let x = recover Array[U8](_request.size()) end
        for i in Range(0,_request.size()) do
            x.push(try _request(i)? else 0 end)
        end
        peer.write(consume x)
        _logger(Info) and _logger.log("Sent request to socks proxy")

    be outgoing_socks_connection_established(route_id:USize,
                                             conn_ms: U64,
                                             auth_ms: U64,
                                             established_ms: U64) => 
        _logger(Info) and _logger.log("Timing till connect/auth/complete: "
                                     +       conn_ms.string()
                                     + "/" + auth_ms.string()
                                     + "/" + established_ms.string()
                                     + " ms")
        try 
            let node = _nodes(_node_i)?
            node.record_established_connection(_route_id,conn_ms,auth_ms,established_ms)
        end

    be outgoing_socks_connection_failed(route_id:USize,conn: TCPConnection) => 
        _logger(Info) and _logger.log("Outgoing socks connection failed")
        try_next_node()
        _route_id = route_id
        try 
            let node = _nodes(_node_i)?
            node.record_failed_connection(_route_id)
        end
