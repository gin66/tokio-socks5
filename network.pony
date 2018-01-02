use "collections"
use "logger"

actor Network
    let _logger : Logger[String]
    let _nodes : HashMap[U8,Node tag,HashIs[U8]] = HashMap[U8,Node tag,HashIs[U8]]

    new create(logger: Logger[String]) =>
        _logger = logger

    be add_node(id: U8, node: Node tag) =>
        _nodes.update(id,node)
    
    be add_socks_proxy(to_id: U8,ia: InetAddrPort iso) =>
        let addr = ia.string()
        try
            let node_actor = _nodes(to_id)?
            node_actor.add_socks_proxy(consume ia)
        else
            _logger(Info) and _logger.log("Cannot find node " + to_id.string() + " for " + consume addr)
        end
