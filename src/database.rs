// This module captures all relevant information from all areas.
//
use std::rc::Rc;
use std::str::FromStr;
use std::option::Option;
use ini;
use country::country_hash;

pub struct Node {
    id: u8,
    name: String,
    probe: Option<String>,
    country_code: Option<usize>
}

pub struct Database {
    nodes: Vec<Option<Node>>
}

#[allow(dead_code)]
impl Database {
    pub fn new() -> Rc<Database> {
        let mut db = Database {
            nodes: vec!()   // Array of Nodes set to None
        };
        while db.nodes.len() < 256 {
            db.nodes.push(None)
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
                                country_code: None
                            };
                            for (k,v) in node_section.iter() { 
                                if k == "Probe" {
                                    new_node.probe = Some(v.to_string())
                                }
                                else if (k == "Country") && (v.len() == 2) {
                                    let country = v.to_string().to_lowercase().into_bytes();
                                    let code = country_hash(&[country[0],country[1]]);
                                    if let Some(ch) = code {
                                        new_node.country_code = Some(ch)
                                    }
                                }
                                else {
                                    println!("UNKNOWN NODESECTION  {}:{}", *k, *v);
                                }
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