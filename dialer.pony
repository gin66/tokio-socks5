use "net"
use "logger"

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
                    Exchange of two identical messages \x05\x01\x00
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

    Unclear is, which solution is better: one actor and many structs vs many actors.
    """
    let _logger:  Logger[String]
    let _auth:    AmbientAuth val
    let _conn:    TCPConnection tag
    let _conns:   Array[TCPConnection tag] = Array[TCPConnection tag]
    let _addr:    InetAddrPort iso
    var _request: Array[U8] iso

    new create(auth: AmbientAuth val,
               conn: TCPConnection tag,
               addr: InetAddrPort iso,
               socks_request: Array[U8] iso,
               logger: Logger[String]) =>
        _auth    = auth
        _logger  = logger
        _addr    = consume addr
        _conn    = conn
        _request = consume socks_request

        _logger(Info) and _logger.log("Called connect_to "+_addr.string())
        connect_direct()
        try
            let proxy_addr = InetAddrPort.create_from_host_port("127.0.0.1:40005")?
            //connect_socks5_to(conn,consume proxy_addr,consume socks_request)
        end

    be connect_direct() =>
        _conn.mute()
        let empty: Array[U8] iso = recover iso Array[U8]() end
        let req = _request = consume empty
        let conn_peer = TCPConnection(_auth,
                            DirectForwardTCPConnectionNotify(_conn,
                                                             consume req,
                                                             _logger),
                                _addr.host_str(),
                                _addr.port_str()
                                where init_size=16384,max_size = 16384)
        _conn.set_notify(DirectForwardTCPConnectionNotify(conn_peer where logger = _logger))
        _conn.unmute()

    be connect_socks5_to(conn: TCPConnection tag,
            addr: InetAddrPort iso,
            socks_request: Array[U8] iso) =>
        _conn.mute()
        let conn_peer = TCPConnection(_auth,
                            Socks5ForwardTCPConnectionNotify(_conn,true,
                                consume socks_request,
                                _logger),
                                _addr.host_str(),
                                _addr.port_str()
                                where init_size=16384,max_size = 16384)
        _conn.set_notify(DirectForwardTCPConnectionNotify(conn_peer where logger = _logger))
        _conn.unmute()

    be resolve() =>
        None
    