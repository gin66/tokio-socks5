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
    let _conn:      TCPConnection tag
    let _conns:     Array[TCPConnection tag] = Array[TCPConnection tag]
    var _request:   Array[U8] iso
    var _connected: Bool = false
    var _count:     U8 = 0

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
        _request = consume socks_request
        _chooser.select_connection(this, consume addr)
    
    be select_timeout() =>
        let empty: Array[U8] iso = recover iso Array[U8]() end
        let data = _request = consume empty
        try 
            data(1)? = Socks5.reply_host_unreachable()
            _conn.write(consume data)
        end
        _conn.dispose()

    be connect_direct(addr: InetAddrPort val) =>
        _conn.mute()
        let empty: Array[U8] iso = recover iso Array[U8]() end
        let req = _request = consume empty
        let conn_peer = TCPConnection(_auth,
                            DirectForwardTCPConnectionNotify(_conn,
                                                             consume req,
                                                             _logger),
                                addr.host_str(),
                                addr.port_str()
                                where init_size=16384,max_size = 16384)
        _conn.set_notify(DirectForwardTCPConnectionNotify(conn_peer where logger = _logger))
        _conn.unmute()

    be connect_socks5_to(proxies: Array[InetAddrPort val] val) =>
        for addr in proxies.values() do
            let conn_peer = TCPConnection(_auth,
                            Socks5OutgoingTCPConnectionNotify(this,_logger),
                            addr.host_str(),
                            addr.port_str()
                            where init_size=16384,max_size = 16384)
            _count = _count + 1
        end

    be outgoing_socks_connection_succeeded(peer: TCPConnection) => 
        """
        Connection to a socks proxy has succeeded. Send him the original socks_request.
        All else is just protocol
        """
        _count = _count - 1
        if _connected then
            peer.dispose()
        else
            _connected = true
            _conn.mute()
            peer.mute()
            peer .set_notify(DirectForwardTCPConnectionNotify(_conn where logger = _logger))
            _conn.set_notify(DirectForwardTCPConnectionNotify(peer  where logger = _logger))
            _conn.unmute()
            peer.unmute()
            let empty: Array[U8] iso = recover iso Array[U8]() end
            let data = _request = consume empty
            peer.write(consume data)
        end

    be outgoing_socks_connection_failed(conn: TCPConnection) => 
        _count = _count - 1
        if (_count == 0) and not _connected then
            let empty: Array[U8] iso = recover iso Array[U8]() end
            let data = _request = consume empty
            try 
                data(1)? = Socks5.reply_conn_refused()
                _conn.write(consume data)
            end
            _conn.dispose()
        end