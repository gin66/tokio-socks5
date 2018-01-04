use "collections"
use "logger"

actor Network
    let _logger : Logger[String]
    let _nodes : HashMap[U8,(String,Node tag),HashIs[U8]] = HashMap[U8,(String,Node tag),HashIs[U8]]

    new create(logger: Logger[String]) =>
        _logger = logger

    be add_node(id: U8, node: Node tag,country: String) =>
        _nodes.update(id,(country,node))
    
    be add_socks_proxy(to_id: U8,ia: InetAddrPort iso) =>
        let addr = ia.string()
        try
            (let country,let node_actor) = _nodes(to_id)?
            node_actor.add_socks_proxy(consume ia)
        else
            _logger(Info) and _logger.log("Cannot find node " + to_id.string() + " for " + consume addr)
        end

    be display() =>
        for (country,node) in _nodes.values() do
            node.display()
        end

    be country_of_node(id: U8, country: String) =>
        try
            (let old_country,let node_actor) = _nodes(id)?
            _nodes.update(id,(country,node_actor))
        end

    be select_node_by_country(destination_country:String,forbidden_countries:String) =>
        _logger(Info) and _logger.log("Select node by country destination/forbidden: "
                                        + destination_country + "/" + forbidden_countries)
        let ids = Array[U8]
        let candidates = Array[U8]

        for (id,country_node) in _nodes.pairs() do
            (let country,let node) = country_node
            if not forbidden_countries.contains(country) then
                candidates.push(id)
            end
            if country == destination_country then
                ids.push(id)
            end
            _logger(Info) and _logger.log(country + "=> " + ids.size().string() + "/" + candidates.size().string())
        end
        let select = (if ids.size() == 0 then candidates else ids end)
        _logger(Info) and _logger.log("Number of nodes: " + select.size().string())
