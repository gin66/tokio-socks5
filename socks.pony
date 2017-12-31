use "net"
use "collections"
use "logger"

primitive Socks5WaitInit
primitive Socks5WaitRequest
primitive Socks5WaitConnect

type Socks5State is (Socks5WaitInit | Socks5WaitRequest | Socks5WaitConnect)

class SocksTCPConnectionNotify is TCPConnectionNotify
    let socks_v5_version : U8 = 5
    let socks_v5_meth_no_auth   : U8 = 0
    let socks_v5_meth_gssapi    : U8 = 1
    let socks_v5_meth_user_pass : U8 = 2
    let socks_v5_cmd_connect       : U8 = 1
    let socks_v5_cmd_bind          : U8 = 2
    let socks_v5_cmd_udp_associate : U8 = 3
    let socks_v5_atyp_ipv4   : U8 = 1
    let socks_v5_atyp_ipv6   : U8 = 4
    let socks_v5_atyp_domain : U8 = 3
    let socks_v5_reply_ok                 : U8 = 0
    let socks_v5_reply_general_error      : U8 = 1
    let socks_v5_reply_not_allowed        : U8 = 2
    let socks_v5_reply_net_unreachable    : U8 = 3
    let socks_v5_reply_host_unreachable   : U8 = 4
    let socks_v5_reply_conn_refused       : U8 = 5
    let socks_v5_reply_ttl_expired        : U8 = 6
    let socks_v5_reply_cmd_not_supported  : U8 = 7
    let socks_v5_reply_atyp_not_supported : U8 = 8

    let _logger:   Logger[String]
    let _resolver: Resolver
    var _state:    Socks5State
    var _tx_bytes: USize = 0
    var _rx_bytes: USize = 0

    new iso create(resolver: Resolver, logger: Logger[String]) =>
        _resolver = resolver
        _logger   = logger
        _state    = Socks5WaitInit

    fun ref received(
        conn: TCPConnection ref,
        data: Array[U8] iso,
        times: USize)
        : Bool
    =>
    try 
        _rx_bytes = _rx_bytes + data.size()
        for i in Range(0,data.size()) do
            _logger(Info) and _logger.log(i.string()+":"+data(i)?.string())
        end
        match _state
        | Socks5WaitInit =>
            _logger(Info) and _logger.log("Received handshake")
            if data(0)? != socks_v5_version then error end
            if data.size() != (USize.from[U8](data(1)?) + 2) then error end
            data.find(socks_v5_meth_no_auth, 2)?
            _logger(Info) and _logger.log("Send initial response")
            conn.write([socks_v5_version;socks_v5_meth_no_auth])
            _state = Socks5WaitRequest
        | Socks5WaitRequest =>
            _logger(Info) and _logger.log("Received address")
            if data(0)? != socks_v5_version then error end
            if data(1)? != socks_v5_cmd_connect then
                data(1)? = socks_v5_reply_cmd_not_supported
                conn.write(consume data)
                error
            end
            var atyp_len: USize = 0
            var port: U16 = U16.from[U8](data(data.size()-2)?)
            port = (port * 256) + U16.from[U8](data(data.size()-1)?)
            var addr: InetAddrPort iso
            match data(3)?
            | socks_v5_atyp_ipv4   => 
                atyp_len = 4
                let ip  = (data(4)?,data(5)?,data(6)?,data(7)?)
                addr = InetAddrPort(ip,port)
            | socks_v5_atyp_domain => 
                let astr_len = USize.from[U8](data(4)?)
                atyp_len = astr_len + 1
                var dest : String iso = recover iso String end
                for i in Range(0,atyp_len) do
                    dest.push(data(5+i)?)
                end
                addr  = InetAddrPort.create_from_string(consume dest,port)
            else
                data(1)? = socks_v5_reply_atyp_not_supported
                conn.write(consume data)
                error
            end
            if data.size() != (atyp_len + 6) then
                error
            end
            data(1)? = socks_v5_reply_ok
            // The resolver should call set_notify on actor conn.
            // This means, no more communication should happen with this notifier
            _resolver.connect_to(conn,consume addr,port,consume data)
            _state = Socks5WaitConnect
        | Socks5WaitConnect=>
            _logger(Info) and _logger.log("Received data, while waiting for connection")
            error
            //conn.write(String.from_array(consume data))
        end
    else
        conn.dispose()
    end
    false

    fun ref sent(
        conn: TCPConnection ref,
        data: (String val | Array[U8] val))
        : (String val | Array[U8 val] val)
    =>
    _tx_bytes = _tx_bytes + data.size()
    data

    fun ref throttled(conn: TCPConnection ref) =>
        None

    fun ref unthrottled(conn: TCPConnection ref) =>
        None

    fun ref accepted(conn: TCPConnection ref) =>
        None

    fun ref connect_failed(conn: TCPConnection ref) =>
        None

    fun ref closed(conn: TCPConnection ref) =>
        _logger(Info) and _logger.log("Connection closed tx/rx=" + _tx_bytes.string() + "/" + _rx_bytes.string())

class SocksTCPListenNotify is TCPListenNotify
    let _logger: Logger[String]
    let _resolver: Resolver

    new iso create(resolver: Resolver, logger: Logger[String]) =>
        _resolver = resolver
        _logger   = logger

    fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ =>
        SocksTCPConnectionNotify(_resolver, _logger)

    fun ref listening(listen: TCPListener ref) =>
        _logger(Info) and _logger.log("Successfully bound to address")

    fun ref not_listening(listen: TCPListener ref) =>
        _logger(Info) and _logger.log("Cannot bind to listen address")

    fun ref closed(listen: TCPListener ref) =>
        _logger(Info) and _logger.log("Successfully closed TCP listeners")
