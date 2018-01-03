use "net"
use "collections"
use "logger"

primitive Socks5WaitInit
primitive Socks5WaitRequest
primitive Socks5WaitConnect

type Socks5ServerState is (Socks5WaitInit | Socks5WaitRequest | Socks5WaitConnect)

primitive Socks5
    fun version():U8 => 5
    fun meth_no_auth():U8 => 0
    fun meth_gssapi():U8 => 1
    fun meth_user_pass():U8 => 2
    fun cmd_connect():U8 => 1
    fun cmd_bind():U8 => 2
    fun cmd_udp_associate():U8 => 3
    fun atyp_ipv4():U8 => 1
    fun atyp_ipv6():U8 => 4
    fun atyp_domain():U8 => 3
    fun reply_ok():U8 => 0
    fun reply_general_error():U8 => 1
    fun reply_not_allowed():U8 => 2
    fun reply_net_unreachable():U8 => 3
    fun reply_host_unreachable():U8 => 4
    fun reply_conn_refused():U8 => 5
    fun reply_ttl_expired():U8 => 6
    fun reply_cmd_not_supported():U8 => 7
    fun reply_atyp_not_supported():U8 => 8

class SocksTCPConnectionNotify is TCPConnectionNotify
    let _auth:     AmbientAuth val
    let _chooser:  Chooser
    let _logger:   Logger[String]
    var _state:    Socks5ServerState
    var _tx_bytes: USize = 0
    var _rx_bytes: USize = 0

    new iso create(auth: AmbientAuth val, chooser: Chooser, logger: Logger[String]) =>
        _auth     = auth
        _chooser  = chooser
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
            _logger(Fine) and _logger.log(i.string()+":"+data(i)?.string())
        end
        match _state
        | Socks5WaitInit =>
            _logger(Info) and _logger.log("Received handshake")
            if data(0)? != Socks5.version() then error end
            if data.size() != (USize.from[U8](data(1)?) + 2) then error end
            data.find(Socks5.meth_no_auth(), 2)?
            _logger(Info) and _logger.log("Send initial response")
            conn.write([Socks5.version();Socks5.meth_no_auth()])
            _state = Socks5WaitRequest
        | Socks5WaitRequest =>
            _logger(Info) and _logger.log("Received address")
            if data(0)? != Socks5.version() then error end
            if data(1)? != Socks5.cmd_connect() then
                data(1)? = Socks5.reply_cmd_not_supported()
                conn.write(consume data)
                error
            end
            var atyp_len: USize = 0
            var port: U16 = U16.from[U8](data(data.size()-2)?)
            port = (port * 256) + U16.from[U8](data(data.size()-1)?)
            var addr: InetAddrPort iso
            match data(3)?
            | Socks5.atyp_ipv4()   => 
                atyp_len = 4
                let ip  = (data(4)?,data(5)?,data(6)?,data(7)?)
                addr = InetAddrPort(ip,port)
            | Socks5.atyp_domain() => 
                let astr_len = USize.from[U8](data(4)?)
                atyp_len = astr_len + 1
                var dest : String iso = recover iso String end
                for i in Range(0,atyp_len-1) do
                    dest.push(data(5+i)?)
                end
                addr  = InetAddrPort.create_from_string(consume dest,port)
            else
                data(1)? = Socks5.reply_atyp_not_supported()
                conn.write(consume data)
                error
            end
            if data.size() != (atyp_len + 6) then
                error
            end
            // The dialer should call set_notify on actor conn.
            // This means, no more communication should happen with this notifier
            Dialer(_auth,_chooser,conn,consume addr,consume data,_logger)
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
    let _auth: AmbientAuth val
    let _chooser: Chooser
    let _logger: Logger[String]

    new iso create(auth: AmbientAuth val, chooser: Chooser, logger: Logger[String]) =>
        _auth     = auth
        _chooser  = chooser
        _logger   = logger

    fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ =>
        SocksTCPConnectionNotify(_auth, _chooser, _logger)

    fun ref listening(listen: TCPListener ref) =>
        _logger(Info) and _logger.log("Successfully bound to address")

    fun ref not_listening(listen: TCPListener ref) =>
        _logger(Info) and _logger.log("Cannot bind to listen address")

    fun ref closed(listen: TCPListener ref) =>
        _logger(Info) and _logger.log("Successfully closed TCP listeners")


class Socks5OutgoingTCPConnectionNotify is TCPConnectionNotify
    var _dialer:    Dialer tag
    let _logger:    Logger[String]

    new iso create(dialer: Dialer,
                   logger: Logger[String]) =>
        _dialer = dialer
        _logger = logger

    fun ref connect_failed(conn: TCPConnection ref) =>
        _logger(Info) and _logger.log("Connection failed")
        _dialer.outgoing_socks_connection_failed(conn)

    fun ref connected(conn: TCPConnection ref) =>
        conn.write([Socks5.version();1;Socks5.meth_no_auth()])

    fun ref received(
            conn: TCPConnection ref,
            data: Array[U8] iso,
            times: USize)
            : Bool =>
        if times == 1 then
            try
                if data.size() != 2 then error end
                if data(0)? != Socks5.version() then error end
                if data(1)? != Socks5.meth_no_auth() then error end
                _dialer.outgoing_socks_connection_succeeded(conn)
                return false
            end
        end
        _dialer.outgoing_socks_connection_failed(conn)
        conn.dispose()
        false

    fun ref closed(conn: TCPConnection ref) =>
        _dialer.outgoing_socks_connection_failed(conn)
