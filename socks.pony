use "net"
use "collections"
use "logger"

primitive Socks5WaitInit
primitive Socks5WaitRequest
primitive Socks5WaitConnect
primitive Socks5NeedInit
primitive Socks5NeedRequest
primitive Socks5PassThrough

type Socks5ClientState is (Socks5NeedInit | Socks5NeedRequest | Socks5PassThrough)
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
    let _logger:   Logger[String]
    let _auth: AmbientAuth val
    var _state:    Socks5ServerState
    var _tx_bytes: USize = 0
    var _rx_bytes: USize = 0

    new iso create(auth: AmbientAuth val, logger: Logger[String]) =>
        _auth     = auth
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
            Dialer(_auth,conn,consume addr,consume data,_logger)
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
    let _auth: AmbientAuth val

    new iso create(auth: AmbientAuth val, logger: Logger[String]) =>
        _auth     = auth
        _logger   = logger

    fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ =>
        SocksTCPConnectionNotify(_auth, _logger)

    fun ref listening(listen: TCPListener ref) =>
        _logger(Info) and _logger.log("Successfully bound to address")

    fun ref not_listening(listen: TCPListener ref) =>
        _logger(Info) and _logger.log("Cannot bind to listen address")

    fun ref closed(listen: TCPListener ref) =>
        _logger(Info) and _logger.log("Successfully closed TCP listeners")


class Socks5ForwardTCPConnectionNotify is TCPConnectionNotify
    let _logger:    Logger[String]
    let _peer:      TCPConnection
    var _state:     Socks5ClientState
    var _conn_data: Array[U8] iso
    var _tx_bytes:  USize = 0
    var _rx_bytes:  USize = 0

    new iso create(peer: TCPConnection, 
                   is_proxy: Bool,
                   conn_data: Array[U8] iso,
                   logger: Logger[String]) =>
        _peer      = peer
        _conn_data = consume conn_data
        _logger    = logger
        _state     = (if is_proxy then
                          Socks5NeedInit
                      else
                          Socks5PassThrough
                      end)

    fun ref connect_failed(conn: TCPConnection ref) =>
        _logger(Info) and _logger.log("Connection failed")
        if _conn_data.size() > 0 then
            let empty: Array[U8] iso = recover iso Array[U8]() end
            let data = _conn_data = consume empty
            try data(1)? = Socks5.reply_conn_refused() end
            _peer.write(consume data)
        end
        _peer.dispose()

    fun ref connected(conn: TCPConnection ref) =>
        match _state
        | Socks5NeedInit =>
            conn.write([Socks5.version();1;Socks5.meth_no_auth()])
            _state = Socks5NeedRequest
        | Socks5PassThrough =>
            if _conn_data.size() > 0 then
                let empty: Array[U8] iso = recover iso Array[U8]() end
                let data = _conn_data = consume empty
                try data(1)? = Socks5.reply_ok() end
                _peer.write(consume data)
            end
        end

    fun ref received(
            conn: TCPConnection ref,
            data: Array[U8] iso,
            times: USize)
            : Bool =>
        match _state
        | Socks5NeedRequest =>
            let empty: Array[U8] iso = recover iso Array[U8]() end
            let cdata = _conn_data = consume empty
            var target = _peer
            try
                if data.size() != 2 then error end
                if data(0)? != Socks5.version() then error end
                if data(1)? != Socks5.meth_no_auth() then error end
                target = conn
            else
                try cdata(1)? = Socks5.reply_general_error() end
            end
            target.write(consume cdata)
            _state = Socks5PassThrough
        | Socks5PassThrough =>
            if data.size() > 0 then
                _rx_bytes = _rx_bytes + data.size()
                _peer.write(consume data)
            else
                _peer.write(consume data)
                conn.dispose()
            end
        end
        false

    fun ref sent(
            conn: TCPConnection ref,
            data: (String val | Array[U8] val))
            : (String val | Array[U8 val] val) =>
        if data.size() == 0 then
            _logger(Info) and _logger.log("sent empty")
            conn.close()
        end
        _tx_bytes = _tx_bytes + data.size()
        data

    fun ref throttled(conn: TCPConnection ref) =>
        _peer.mute()

    fun ref unthrottled(conn: TCPConnection ref) =>
        _peer.unmute()

    fun ref accepted(conn: TCPConnection ref) =>
        None

    fun ref closed(conn: TCPConnection ref) =>
        _logger(Info) and _logger.log("Connection closed tx/rx=" + _tx_bytes.string() + "/" + _rx_bytes.string())
        let empty: Array[U8] iso = recover iso Array[U8]() end
        _peer.write(consume empty)
