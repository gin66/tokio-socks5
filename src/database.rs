// This module captures all relevant information from all areas.
//
use std::rc::Rc;
use std::str::FromStr;
use std::option::Option;
use std::net::{SocketAddr};
use ini;
use country::country_hash;

pub struct Node {
    id: u8,
    name: String,
    probe: Option<String>,
    country_code: Option<usize>,
    socks5_listen_port: Option<SocketAddr>
}

pub struct Database {
    nodes: Vec<Option<Node>>,
    proxy_to: Vec<Option<Vec<SocketAddr>>>
}

#[allow(dead_code)]
impl Database {
    pub fn new() -> Rc<Database> {
        let mut db = Database {
            nodes: vec!(),   // Array of Nodes set to None
            proxy_to: vec!()
        };
        for i in 0..255 {
            db.nodes.push(None);
            db.proxy_to.push(None)
        }
        Rc::new(db)
    }

    pub fn read_from_ini(&mut self, config: ini::Ini, node_id: &str) -> Result<(),(&str)> {
        // Print parsed config file for debugging
        for (sec, prop) in config.iter() {
            println!("Section: {:?}", *sec);
            for (k, v) in prop.iter() {
                println!("   {}:{}", *k, *v);
            }
        }

        match config.section(Some("Nodes")) { 
            Some(section) =>  {
                for (k,v) in section.iter() { 
                    println!("NODE  {}:{}", *k, *v);
                    let nodename: &str = &v.to_string();
                    let id = k.to_string();
                    let id = u8::from_str(&id).unwrap();
                    match config.section(Some(nodename)) {
                        Some(ref node_section) => {
                            let mut new_node = Node {
                                id,
                                name: nodename.to_string(),
                                probe: None,
                                country_code: None,
                                socks5_listen_port: None
                            };
                            for (k,v) in node_section.iter() {
                                match k.as_ref() {
                                    "Probe" => {
                                        new_node.probe = Some(v.to_string());
                                    },
                                    "Socks5Address" => {
                                        match v.to_string().parse::<SocketAddr>() {
                                            Err(e) => return Err("Socks5Address is wrong"),
                                            Ok(sa) => new_node.socks5_listen_port = Some(sa)
                                        }
                                    },
                                    "Country" if v.len() == 2 => {
                                        let country = v.to_string().to_lowercase().into_bytes();
                                        let code = country_hash(&[country[0],country[1]]);
                                        if let Some(ch) = code {
                                            new_node.country_code = Some(ch)
                                        }
                                    }
                                    _ if k.contains("SocksProxy->") => {
                                        let to_id = k[12..].to_string();
                                        let to_id = u8::from_str(&to_id).unwrap();
                                        let mut sa_list: Vec<SocketAddr> = vec!();
                                        let split = v.split(",");
                                        for add in split {
                                            match add.parse::<SocketAddr>() {
                                                Err(e) => return Err("SocksProxy Address is wrong"),
                                                Ok(sa) => {
                                                    sa_list.push(sa)
                                                }
                                            }    
                                        }
                                        if sa_list.len() > 0 {
                                            self.proxy_to[to_id as usize] = Some(sa_list)
                                        }
                                    },
                                    _ => {
                                        println!("UNKNOWN NODESECTION  {}:{}", *k, *v);
                                    }
                                };
                            }
                            self.nodes[id as usize] = Some(new_node)
                        },
                        None => return Err("Cannot find node section")
                    }
                };
            },
            None => return Err("No [Nodes] section config-file")
        };

        let nodename = match config.get_from(Some("Nodes"), node_id) {
            Some(name) => name,
            None => return Err("Node is not defined in config-file")
        };
        println!("This node is {} with name {}",node_id,nodename);

        let nodeconfig = match config.section(Some(nodename)) { 
            Some(section) => section,
            None => return Err("No section for node {} in config-file")
        };
        println!("{:?}",nodeconfig);

        Ok(())
    }
}