use "net"
use "collections"
use "logger"

interface tag PeerConnection
    be write(data: (String val | Array[U8 val] val))
    be mute()
    be unmute()
    be dispose()

class DirectForwardTCPConnectionNotify is TCPConnectionNotify
    let _logger:    Logger[String]
    let _peer:      PeerConnection
    var _conn_data: Array[U8] iso       // only used in connected and connect_failed
    var _tx_bytes: USize = 0
    var _rx_bytes: USize = 0

    new iso create(peer: PeerConnection, conn_data: Array[U8] iso = recover iso Array[U8]() end,
                   logger: Logger[String]) =>
        _peer      = peer
        _conn_data = consume conn_data
        _logger    = logger

    fun ref connected(conn: TCPConnection ref) =>
        """
        This function is only called, if this is an outgoing connection !!!
        On connect the (socks) peer is informed about successful connection.
        """
        _logger(Info) and _logger.log("Outgoing connection established")
        let empty: Array[U8] iso = recover iso Array[U8]() end
        let data = _conn_data = consume empty
        try data(1)? = Socks5.reply_ok() end
        _peer.write(consume data)

    fun ref connect_failed(conn: TCPConnection ref) =>
        """
        This function is only called, if this is an outgoing connection !!!
        On connect failure the (socks) peer is closed
        """
        _logger(Info) and _logger.log("Connection failed")
        let empty: Array[U8] iso = recover iso Array[U8]() end
        let data = _conn_data = consume empty
        try data(1)? = Socks5.reply_conn_refused() end
        _peer.write(consume data)
        _peer.dispose()

    fun ref received(
            conn: TCPConnection ref,
            data: Array[U8] iso,
            times: USize)
            : Bool =>
        _logger(Info) and _logger.log("Received " + data.size().string() + " Bytes")
        _rx_bytes = _rx_bytes + data.size()
        _peer.write(consume data)
        false

    fun ref sent(
            conn: TCPConnection ref,
            data: (String val | Array[U8] val))
            : (String val | Array[U8 val] val) =>
        _tx_bytes = _tx_bytes + data.size()
        data

    fun ref throttled(conn: TCPConnection ref) =>
        _peer.mute()

    fun ref unthrottled(conn: TCPConnection ref) =>
        _peer.unmute()

    fun ref closed(conn: TCPConnection ref) =>
        _logger(Info) and _logger.log("Connection closed tx/rx=" + _tx_bytes.string() + "/" + _rx_bytes.string())
        _peer.dispose()

class ForwardTCPConnectionNotify is TCPConnectionNotify
    let _logger:   Logger[String]
    var _tx_bytes: USize = 0
    var _rx_bytes: USize = 0

    new iso create(logger: Logger[String]) =>
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
