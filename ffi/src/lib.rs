use anyhow::bail;
use anyhow::Result;
use memcache::Client;
use memcache::CommandError::KeyExists;
use memcache::MemcacheError::CommandError;
use memcache::Url;
use std::cell::Cell;
use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::CStr;
use std::ffi::CString;
use std::str;
use std::time::SystemTime;

struct Rl {
    url: Url,
    client: Option<Client>,
    error: CString,
}

impl Rl {
    fn new(url: &CStr) -> Result<Rl> {
        let url = Url::parse(url.to_str()?)?;
        Ok(Rl {
            url: url,
            client: None,
            error: CString::new("")?,
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
            match client.add(&key, 0, rate_seconds + 1) {
                Ok(()) => (),
                Err(e) => match e {
                    CommandError(e) if e == KeyExists => (),
                    e => bail!(e),
                },
            };

            let keys: Vec<String> = (0..rate_seconds)
                .map(|n| format!("{}{}", prefix, n))
                .collect();
            let keys: Vec<&str> = keys.iter().map(|s| &**s).collect();
            let tokens: HashMap<String, u32> = client.gets(&keys)?;
            let (value, cas_id) = match client.get(&key)? {
                Some((value, _, cas)) => (
                    match str::from_utf8(&value) {
                        Ok(value) => match value.parse::<u32>() {
                            Ok(value) => value,
                            Err(_) => 0,
                        },
                        Err(_) => 0,
                    },
                    cas,
                ),
                None => (0, None),
            };

            let mut sum = value + size;
            for (_, v) in tokens {
                sum += v;
            }

            if sum > rate_max {
                return Ok(true);
            }

            if let Some(cas_id) = cas_id {
                client.cas(&key, value + size, rate_seconds + 1, cas_id)?;
            }

            Ok(false)
        } else {
            // TODO
            // shouldn't get in here?
            // but should probably error?
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
pub extern "C" fn rl__rate_limit(
    index: u64,
    prefix: *const i8,
    size: u32,
    rate_max: u32,
    rate_seconds: u32,
) -> i32 {
    let prefix = unsafe { CStr::from_ptr(prefix) };

    STORE.with(|it| {
        let mut it = it.borrow_mut();

        return match it.get_mut(&index) {
            Some(rl) => match rl.rate_limit(prefix, size, rate_max, rate_seconds) {
                Ok(true) => 1,
                Ok(false) => 0,
                Err(e) => {
                    if let Ok(error) = CString::new(e.to_string()) {
                        rl.error = error;
                    }
                    rl.client = None;
                    -1
                }
            },
            None => -1,
        };
    })
}

const INVALID_OBJECT_INDEX_ERROR_MESSAGE: *const u8 = b"Invalid object index\0" as *const u8;

#[no_mangle]
pub extern "C" fn rl__error(index: u64) -> *const i8 {
    STORE.with(|it| {
        let it = it.borrow();

        let error = match it.get(&index) {
            Some(rl) => rl.error.as_ptr(),
            None => INVALID_OBJECT_INDEX_ERROR_MESSAGE as *const i8,
        };

        error
    })
}

#[no_mangle]
pub extern "C" fn rl_DESTROY(index: u64) {
    STORE.with(|it| {
        let mut it = it.borrow_mut();
        it.remove(&index);
    })
}
