use anyhow::Result;
use memcache::Client;
use memcache::Url;
use std::cell::Cell;
use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::CStr;
use std::time::SystemTime;

struct Rl {
    url: Url,
    client: Option<Client>,
}

impl Rl {
    fn new(url: &CStr) -> Result<Rl> {
        let url = Url::parse(url.to_str()?)?;
        Ok(Rl {
            url: url,
            client: None,
        })
    }

    fn rate_limit(
        &mut self,
        prefix: &CStr,
        size: u32,
        rate_max: u32,
        rate_seconds: u32,
    ) -> Result<bool> {
        let prefix = prefix.to_str()?;

        /* re-connect if necessary */
        if let None = self.client {
            self.client = Some(Client::connect(String::from(self.url.clone()))?)
        };

        if let Some(client) = &self.client {
            let now = SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)?
                .as_secs();

            let key = format!("{}{}", prefix, now);
            client.add(&key, 0, rate_seconds + 1)?;

            //let keys: Vec<&str> = (0..rate_seconds).map(|n| format!("{}{}", prefix, n).as_str() ).collect();
            //let tokens = client.gets::<u64>(&keys)?;

            Ok(true)
        } else {
            // shouldn't get in here?
            Ok(false)
        }
    }
}

thread_local!(
  static COUNTER: Cell<u64> = Cell::new(1);
  static STORE: RefCell<HashMap<u64, Rl>> = RefCell::new(HashMap::new())
);

#[no_mangle]
pub extern "C" fn rl_new(url: *const i8) -> u64 {
    let url = unsafe { CStr::from_ptr(url) };
    let rl = match Rl::new(url) {
        Ok(rl) => rl,
        Err(_) => return 0,
    };

    let index = COUNTER.with(|it| {
        let index = it.get();
        it.set(index + 1);
        index
    });

    STORE.with(|it| {
        let mut it = it.borrow_mut();
        it.insert(index, rl);
    });

    index
}

#[no_mangle]
pub extern "C" fn rl_rate_limit(
    index: u64,
    prefix: *const i8,
    size: u32,
    rate_max: u32,
    rate_seconds: u32,
) -> i32 {
    let prefix = unsafe { CStr::from_ptr(prefix) };

    STORE.with(|it| {
        let mut it = it.borrow_mut(); // does this need to be mut?

        return match it.get_mut(&index) {
            Some(rl) => match rl.rate_limit(prefix, size, rate_max, rate_seconds) {
                Ok(true) => 1,
                Ok(false) => 0,
                Err(_) => {
                    rl.client = None;
                    -1
                }
            },
            None => -2,
        };
    })
}

#[no_mangle]
pub extern "C" fn rl_DESTROY(index: u64) {
    STORE.with(|it| {
        let mut it = it.borrow_mut();
        it.remove(&index);
    })
}
