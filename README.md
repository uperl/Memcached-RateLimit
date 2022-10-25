# Memcached::RateLimit ![static](https://github.com/uperl/Memcached-RateLimit/workflows/static/badge.svg) ![linux](https://github.com/uperl/Memcached-RateLimit/workflows/linux/badge.svg)

Sliding window rate limiting with Memcached

# SYNOPSIS

```perl
use Memcached::RateLimit;

my $rl = Memcached::RateLimit->new("memcache://localhost:11211");
$rl->error_handler(sub ($rl, $message) {
  warn "rate limit error: $message";
});

# allow 30 requests per minute
if($rl->rate_limit("resource", 1, 30, 60))
{
  # rate limit exceeded
}
```

# DESCRIPTION

This module implements rate limiting logic.  It is intended for high
volume websites that require limits on the access or modification to
resources.  It is implemented using Rust and [FFI::Platypus](https://metacpan.org/pod/FFI::Platypus), so you
will need the rust toolchain in order to install this module.

Why Rust?  Well none of the Perl Memcache clients I found supported
TLS, and the Rust [memcache crate](https://crates.io/crates/memcache)
did.  Also Rust is fast and has a number of safety checks that give
me confidence that it won't crash our app.

The actual algorithm is based one used by Bugzilla, and by default
it will "fail open", meaning if for some reason the client cannot
connect to the Memcached server, it will **allow** the request.

# CONSTRUCTOR

## new

```perl
my $rl = Memcached::RateLimit->new($url);
```

Create a new instance of [Memcached::RateLimit](https://metacpan.org/pod/Memcached::RateLimit).  The URL should be of the
form shown in the synopsis above.

The following schemes are supported:

- `memcache`
- `memcache+tcp`
- `memcache+tls`
- `memcache+udp`
- `memcache+unix`

You can append these query parameters
to the URL:

- `connect_timeout`

    **Experimental**: Connect timeout in seconds.  May be specified as a
    floating point, that is `0.2` is 20 milliseconds.

- `protocol`

    If set to `ascii` this will use the ASCII protocol instead of binary.

- `tcp_nodelay`

    Boolean `true` or `false`.

- `timeout`

    IO timeout in seconds.

    **Experimental**: May be specified as a 
    floating point, that is `0.2` is 20 milliseconds.

- `verify_mode`

    For TLS, this can be set to `none` or `peer`.

# METHODS

## rate\_limit

```perl
my $limited = $rl->rate_limt($name, $size, $rate_max, $rate_seconds);
```

This method returns a boolean true, if a request of `$size` exceeds the
rate limit of `$rate_max` over the past `$rate_seconds`.  If you only
want to rate limit the number of requests then you can set `$size` to 1.

This method will return a boolean false, and increment the appropriate
counters if the requests fits within the rate limit.

This method will **also** return boolean false, if it is unable to connect
to or otherwise experiences an error talking to the memcached server.
In this case it will also call the [error handler](#error_handler).

## set\_read\_timeout

```
$rl->set_read_timeout($secs);
```

Sets the IO Read timeout to `$secs`, may be fractional.

## set\_write\_timeout

```
$rl->set_write_timeout($secs);
```

Sets the IO Write timeout to `$secs`, may be fractional.

## error\_handler

```perl
$rl->error_handler(sub ($rl, $message) {
  ...
});
```

This method will set the error handler, to be called in the case of an
error with the memcached server.  It will pass in the instance of
[Memcached::RateLimit](https://metacpan.org/pod/Memcached::RateLimit) as `$rl` and a diagnostic as `$message`.
Since this module will fail open, it is probably useful to increment
error counters and provide diagnostics with this method to your monitoring
system.

# SEE ALSO

- [Cache::Memcached::Fast](https://metacpan.org/pod/Cache::Memcached::Fast)
- [Redis::RateLimit](https://metacpan.org/pod/Redis::RateLimit)

# AUTHOR

Graham Ollis <plicease@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2022 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
