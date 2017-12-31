use "net"
use "collections"
use "logger"

class DirectForwardTCPConnectionNotify is TCPConnectionNotify
    let _logger:    Logger[String]
    let _peer:      TCPConnection
    var _conn_data: Array[U8] iso
    var _tx_bytes: USize = 0
    var _rx_bytes: USize = 0

    new iso create(peer: TCPConnection, conn_data: Array[U8] iso,logger: Logger[String]) =>
        _peer      = peer
        _conn_data = consume conn_data
        _logger    = logger

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
        _peer.write(consume data)
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

    fun ref connected(conn: TCPConnection ref) =>
        let empty: Array[U8] iso = recover iso Array[U8]() end
        let data = _conn_data = consume empty
        _peer.write(consume data)

    fun ref throttled(conn: TCPConnection ref) =>
        _peer.mute()

    fun ref unthrottled(conn: TCPConnection ref) =>
        _peer.unmute()

    fun ref accepted(conn: TCPConnection ref) =>
        None

    fun ref connect_failed(conn: TCPConnection ref) =>
        _peer.dispose()

    fun ref closed(conn: TCPConnection ref) =>
        _logger(Info) and _logger.log("Connection closed tx/rx=" + _tx_bytes.string() + "/" + _rx_bytes.string())

class ForwardTCPConnectionNotify is TCPConnectionNotify
    let _logger:   Logger[String]
    let _resolver: Resolver
    var _tx_bytes: USize = 0
    var _rx_bytes: USize = 0

    new iso create(resolver: Resolver, logger: Logger[String]) =>
        _resolver = resolver
        _logger   = logger

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
        // This would be just echoing
        // conn.write(String.from_array(consume data))
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
