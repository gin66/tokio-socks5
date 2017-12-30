use "net"
use "logger"

actor Resolver
    let _logger: Logger[String]

    new create(logger: Logger[String]) =>
        _logger = logger

    be connect_to(conn: TCPConnection tag,socks_reply: Array[U8] iso) =>
        _logger(Info) and _logger.log("Called connect_to")
        conn.set_notify(ForwardTCPConnectionNotify(this,_logger))
        conn.write(consume socks_reply)

    be resolve() =>
        None