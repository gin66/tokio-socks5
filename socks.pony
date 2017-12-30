use "net"
use "collections"
use "logger"

primitive Socks5WaitInit
primitive Socks5WaitRequest
primitive Socks5PassThrough

type Socks5State is (Socks5WaitInit | Socks5WaitRequest | Socks5PassThrough)

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

    let _logger: Logger[String]
    var _state:  Socks5State

    new iso create(logger: Logger[String]) =>
        _logger = logger
        _state  = Socks5WaitInit

    fun ref received(
        conn: TCPConnection ref,
        data: Array[U8] iso,
        times: USize)
        : Bool
    =>
    try 
        for i in Range(0,data.size()) do
            _logger(Info) and _logger.log(i.string()+":"+data(i)?.string())
        end
        match _state
        | Socks5WaitInit =>
            _logger(Info) and _logger.log("Received handshake")
            if data(0)? != socks_v5_version then error end
            if data.size() != (USize.from[U8](data(1)?) + 2) then error end
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
            var atyp_len: U8 = 0
            match data(3)?
            | socks_v5_atyp_ipv4   => atyp_len = 4
            | socks_v5_atyp_domain => atyp_len = data(4)? + 1
            else
                data(1)? = socks_v5_reply_atyp_not_supported
                conn.write(consume data)
                error
            end // only IPV4 address type
            if data.size() != (USize.from[U8](atyp_len) + 6) then
                error
            end
            data(1)? = socks_v5_reply_ok
            conn.write(consume data)  // Reply with OK
            _state = Socks5PassThrough
        | Socks5PassThrough=>
            _logger(Info) and _logger.log("Received data")
            conn.write(String.from_array(consume data))
        end
    else
        conn.dispose()
    end
    false

  fun ref throttled(conn: TCPConnection ref) =>
    None

  fun ref unthrottled(conn: TCPConnection ref) =>
    None

  fun ref accepted(conn: TCPConnection ref) =>
    None

  fun ref connect_failed(conn: TCPConnection ref) =>
    None

  fun ref closed(conn: TCPConnection ref) =>
    _logger(Info) and _logger.log("Connection closed")

class SocksTCPListenNotify is TCPListenNotify
  let _logger: Logger[String]

  new iso create(logger: Logger[String]) =>
    _logger = logger

  fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ =>
    SocksTCPConnectionNotify(_logger)

  fun ref listening(listen: TCPListener ref) =>
    _logger(Info) and _logger.log("Successfully bound to address")

  fun ref not_listening(listen: TCPListener ref) =>
    _logger(Info) and _logger.log("Cannot bind to listen address")

  fun ref closed(listen: TCPListener ref) =>
    _logger(Info) and _logger.log("Successfully closed TCP listeners")
