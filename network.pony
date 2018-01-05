use "net"
use "logger"
use "promises"
use "collections"

type Resolve is (DirectConnection | Array[Node tag] val)

class NodeInfoMap
    let node:       Node tag
    var country:    String

    new trn create(country': String,node': Node tag) =>
        country = country'
        node    = node'

actor Network
    let _auth:    AmbientAuth val
    let _logger : Logger[String]
    let _nodes :  HashMap[U8,NodeInfoMap,HashIs[U8]] = HashMap[U8,NodeInfoMap,HashIs[U8]]
    var _scnt: USize = 0

    new create(auth: AmbientAuth val, logger: Logger[String]) =>
        _auth   = auth
        _logger = logger

    be add_node(node_id: U8, node: Node tag,country: String) =>
        _nodes.update(node_id,recover iso NodeInfoMap(country,node) end)

    be add_socks_proxy(to_id: U8,ia: InetAddrPort iso) =>
        let addr = ia.string()
        try
            let ni = _nodes(to_id)?
            ni.node.add_socks_proxy(consume ia)
        else
            _logger(Info) and _logger.log("Cannot find node " + to_id.string() + " for " + consume addr)
        end

    be display() =>
        for ni in _nodes.values() do
            ni.node.display()
        end

    be country_of_node(id: U8, country: String) =>
        try
            let ni = _nodes(id)?
            ni.country = country
        end

    fun tag select_node_by_countries(myID: U8,destination_countries:String,
                            forbidden_countries:String): Promise[Array[Node] val] =>
        let p = Promise[Array[Node] val]
        _select_node_by_countries(p,myID,destination_countries,forbidden_countries)
        p

    be _select_node_by_countries(p: Promise[Array[Node] val],
                myID: U8,destination_countries:String,forbidden_countries:String) =>
        """
        Difficult to come up with the best node to use as internet connection.
        The selection should depend on node availability, distance of node to destination,
        connection reliability/speed to the selected node,.... And even the node has been
        determined, still there are several options to choose from like direct connection,
        UCP/TCP channel, socks-channel with different roundtrip time.
        Finally, what happens if the selected node just has gone down !?
        """
        _logger(Info) and _logger.log("Select node by country destination/forbidden: "
                                        + destination_countries + "/" + forbidden_countries)
        let nodes = recover iso Array[Node] end
        let candidates = recover iso Array[Node] end

        for (id,ni) in _nodes.pairs() do
            if id != myID then
                if not forbidden_countries.contains(ni.country) then
                    candidates.push(ni.node)
                    if destination_countries.contains(ni.country) then
                        nodes.push(ni.node)
                    end
                end
                _logger(Info) and _logger.log(ni.country 
                            + "=> " + nodes.size().string() + "/" + candidates.size().string())
            end
        end
        let select = (if nodes.size() == 0 then consume candidates else consume nodes end)
        _scnt = _scnt+1
        let i = _scnt % select.size()
        _logger(Info) and _logger.log("Number of nodes: " + select.size().string())
        p(consume select)

    fun tag dns_resolve(ia: InetAddrPort val): Promise[Array[U32] val] =>
        let p = Promise[Array[U32] val]
        _dns(p,ia)
        p

    be _dns(p: Promise[Array[U32] val], ia: InetAddrPort val) =>
        let ips = recover val DNS(_auth,ia.host_str(),ia.port_str()) end
        let ip4 = recover iso Array[U32] end
        for addr in ips.values() do
            ip4.push( ((addr.addr and 0xff000000) >> 24)
                    + ((addr.addr and 0x00ff0000) >>  8)
                    + ((addr.addr and 0x0000ff00) <<  8)
                    + ((addr.addr and 0x000000ff) << 24)
                )
        end
        let ip4_val: Array[U32] val = consume ip4
        p(ip4_val)
