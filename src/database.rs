// This module captures all relevant information from all areas.
//
use std::rc::Rc;

pub struct Database {

}

#[allow(dead_code)]
impl Database {
    pub fn new() -> Rc<Database> {
        Rc::new(Database {

        })
    }
}