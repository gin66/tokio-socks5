use "net"
use "logger"

actor Dialer
    let _logger: Logger[String]
    let _auth: AmbientAuth val

    new create(auth: AmbientAuth val,
               logger: Logger[String]) =>
        _auth   = auth
        _logger = logger

    be connect_to(conn: TCPConnection tag,
            addr: InetAddrPort iso,
            socks_request: Array[U8] iso) =>
        _logger(Info) and _logger.log("Called connect_to "+addr.string())
        //connect_direct_to(conn,consume addr,consume socks_request)
        try
            let proxy_addr = InetAddrPort.create_from_host_port("127.0.0.1:40005")?
            connect_socks5_to(conn,consume proxy_addr,consume socks_request)
        end

    be connect_direct_to(conn: TCPConnection tag,
            addr: InetAddrPort iso,
            socks_request: Array[U8] iso) =>
        conn.mute()
        let conn_peer = TCPConnection(_auth,
                            DirectForwardTCPConnectionNotify(conn,
                                consume socks_request,
                                _logger),
                                addr.host_str(),
                                addr.port_str()
                                where init_size=16384,max_size = 16384)
        let empty: Array[U8] iso = recover iso Array[U8]() end
        conn.set_notify(DirectForwardTCPConnectionNotify(conn_peer,consume empty,_logger))
        conn.unmute()

    be connect_socks5_to(conn: TCPConnection tag,
            addr: InetAddrPort iso,
            socks_request: Array[U8] iso) =>
        conn.mute()
        let conn_peer = TCPConnection(_auth,
                            Socks5ForwardTCPConnectionNotify(conn,true,
                                consume socks_request,
                                _logger),
                                addr.host_str(),
                                addr.port_str()
                                where init_size=16384,max_size = 16384)
        let empty: Array[U8] iso = recover iso Array[U8]() end
        conn.set_notify(DirectForwardTCPConnectionNotify(conn_peer,consume empty,_logger))
        conn.unmute()

    be resolve() =>
        None
    