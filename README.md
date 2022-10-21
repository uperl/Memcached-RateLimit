# Memcached::RateLimit ![static](https://github.com/uperl/Memcached-RateLimit/workflows/static/badge.svg) ![linux](https://github.com/uperl/Memcached-RateLimit/workflows/linux/badge.svg)

Sliding window rate limiting with Memcached

# SYNOPSIS

# DESCRIPTION

# CONSTRUCTOR

## new

# METHODS

## rate\_limit

```
$rl->rate_limt($name, $size, $rate_max, $rate_seconds);
```

## error\_handler

```perl
$rl->error_handler(sub ($rl, $message) {
  ...
});
```

# SEE ALSO

- [Cache::Memcached::Fast](https://metacpan.org/pod/Cache::Memcached::Fast)
- [Redis::RateLimit](https://metacpan.org/pod/Redis::RateLimit)

# AUTHOR

Graham Ollis <plicease@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2022 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
