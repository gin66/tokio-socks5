# uservpn-socks5

# This is a work in progress project. => DOES NOT WORK YET

It shall be: A multi-server and multi-client vpn to internet showing up as socks5-proxy on client side

The tokio-socks5 project has been used as a starter for the implementation.

In the meantime an experimental implementation has started using the language pony as an alternative to rust.  The resulting application has demonstrated a surprising high CPU load in near idle situations.  Investigation has revealed, that this is caused by pony's runtime overhead.  A quite successful improvement idea to reduce the CPU load has been rejected by SeanTAllen (creator of pony) due to his judgement about the (unconfirmed) performance impact onto highly concurrent and highly loaded servers. Thus it can be predicted, that future design decisions of pony will not improve this situation. Due to this, the use has been abandoned as being a deadend for an application to be used on a laptop.

[![Build Status](https://travis-ci.org/gin66/uservpn-socks5.svg?branch=mba)](https://travis-ci.org/gin66/uservpn-socks5)

## Motivation
There are already several vpn-solutions, which all do not fully meet my requirements. My set up is multiple servers and few clients to make use of this. The servers are located in different continents and as such the best server for accessing the internet depends on the URL.

Solutions as per my knowledge:
* openvpn: Only point-to-point and not always working well (blocked)
* tinc: Is distributed, but internet access depending on URL is not supported.
* vpncloud: Similar to tinc 
* kcptun: Only point to point
* shadowsocks: Only point-to-point
* shadowsocks-rust: Supports several servers, but same internet-host can use different servers

The first four make use of a tun- or tap-device. Thus root is needed on client and server, which is IMHO a drawback.

## Requirements

- [ ] R.. Low CPU usage in order for use on battery driven computers like laptops
- [ ] R.. Connected nodes form a uservpn
- [X] R.. Nodes are uniquely numbered (range 1-254)
- [X] R.. Nodes with socks5-proxy enabled are typically clients
- [ ] R.. Nodes can have roaming IP/ports
- [ ] R.. Nodes with fixed IPs are considered as servers
- [ ] R.. Nodes with NAT-IPs are considered as temporary servers
- [ ] R.. Working uservpn needs minimum one server
- [ ] R.. Messages are exchanged/routed via Nodes. Hopcount max 3
- [ ] R.. Every Node maintains list of all nodes
- [ ] R.. Every Node can have more than one IP/port for communication
- [ ] R.. Servers are assumed to have good internet connection
- [ ] R.. Nodes inform each other about other nodes' IP/port
- [ ] R.. Nodes with outdated info get updated information from up-to-date nodes
- [ ] R.. Clients decide internet access point per site
- [ ] R.. Clients use same server for selected site for whole session
          => Rationale: Some internet sites lock login with IP
- [ ] R.. Server/Client keeps tcp connections alive (e.g. empty data messages)
- [X] R.. Client uses socks protocol for its clients in order to avoid tcp-over-tcp problem
- [ ] R.. Client multiplexes all TCP connections onto one byte stream per server
- [ ] R.. Client uses one cache per server
- [ ] R.. Out of band messages supported
- [ ] R.. Node sink requests messages to be sent/resent
- [ ] R.. Node communication uses encryption - ALL message bytes
- [ ] R.. Encryption uses static shared key (no session authentication protocol)
- [ ] R.. Two stage encryption of a message: Header and payload separately
- [ ] R.. Encryption of header with watermarking
- [ ] R.. Shared key and configuration stored in configuration file
- [ ] R.. List of static servers (IP/port) as command line or configuration option
- [ ] R.. Node communication is pluggable for protocols
- [ ] R...Support node to node protocol: TCP
- [ ] R...Support node to node protocol: UDP
- [ ] R...Support node to node protocol: KCP ?
- [ ] R.. Messages allow flight time to be measured
- [ ] R.. Two Nodes aka Server-Client together implement socks5-proxy
- [ ] R.. Language should be rust (for performance reasons) - not python
- [ ] R.. Portion of traffic from client to server will be always sent via other nodes
- [ ] R.. Autoupdate of all nodes triggered by node informing about latest SW
- [ ] R.. SW distribution via github
- [ ] R.. If a server dies, all connections via that server are dropped
- [ ] R.. Both sides of a TCP communication send keep-alive packets e.g. 10 mins
- [ ] R.. UDP as part of socks protocol is not supported  
- [ ] R.. DNS never happens on a client
- [ ] R.. Best server to access internet is determined e.g. by Geo-IP or just test
- [X] R.. To evaluate a connection the first roundtrip time in ms is evaluated.
          This roundtrip is defined as the time difference between
          first reply data message to the last sent data message
          For http: completed HTTP-Request to start of HTTP-Reply.
          Drawback: The http server performance is included.
          Remedy:   Only use averaged data. 
          BTW: international roundtrip time is more than server processing

## Usage - OUTDATED

First, run the server

```
$ cargo run
   ...
Listening for socks5 proxy connections on 127.0.0.1:8080
```

Then in a separate window you can test out the proxy:

```
$ export https_proxy=socks5h://localhost:8080
$ curl -v https://www.google.com
```

If you have an older version of libcurl which doesn't support the `socks5h` scheme,
you can try:

```
$ curl -v --socks5-hostname localhost:8080 https://www.google.com
```

The server is hardcoded to use Google's public DNS resolver (IPv4 address 8.8.8.8).
If you can't use external DNS services, change the address in the source and
rebuild the server.

# License

This project is licensed under either of

 * Apache License, Version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
   http://www.apache.org/licenses/LICENSE-2.0)
 * MIT license ([LICENSE-MIT](LICENSE-MIT) or
   http://opensource.org/licenses/MIT)

at your option.

