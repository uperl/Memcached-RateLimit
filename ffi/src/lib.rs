use std::cell::Cell;
use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::CStr;
use std::time::SystemTime;
use memcache::Url;
use memcache::Client;
use anyhow::Result;

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

  fn rate_limit(&mut self, prefix: &CStr, size: u32, rate_max: u32, rate_seconds: u32) -> Result<bool> {

    /* re-connect if necessary */
    if let None = self.client {
      self.client = Some(Client::connect(self.url.clone().into_string())?)
    };

    if let Some(client) = &self.client {
      let now = SystemTime::now().duration_since(SystemTime::UNIX_EPOCH)?.as_secs();
      client.add(prefix.to_str()?, 0, rate_seconds + 1)?;
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
    Err(_) => return 0
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
pub extern "C" fn rl_rate_limit(index: u64, prefix: *const i8, size: u32, rate_max: u32, rate_seconds: u32) -> bool {
  let prefix = unsafe { CStr::from_ptr(prefix) };

  STORE.with(|it| {
    let mut it = it.borrow_mut(); // does this need to be mut?

    return match it.get_mut(&index) {
      Some(rl)  => match rl.rate_limit(prefix, size, rate_max, rate_seconds) {
        Ok(b)  => b,
        Err(_) => {rl.client = None; false },
      },
      None      => false
    }
  })
}

#[no_mangle]
pub extern "C" fn rl_DESTROY(index: u64) {
  STORE.with(|it| {
    let mut it = it.borrow_mut();
    it.remove(&index);
  })
}
