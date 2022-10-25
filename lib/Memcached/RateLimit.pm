use warnings;
use 5.020;
use experimental qw( postderef signatures );

package Memcached::RateLimit {

  # ABSTRACT: Sliding window rate limiting with Memcached

  use FFI::Platypus 2.00;
  use Ref::Util qw( is_plain_hashref );
  use Carp qw( croak );

  my $ffi = FFI::Platypus->new( api => 2, lang => 'Rust' );
  $ffi->bundle;
  $ffi->mangler(sub ($name) { "rl_$name" });
  $ffi->type("object(@{[ __PACKAGE__ ]})" => 'rl');
  our %keep;

  sub _hash_to_url (%config)
  {
    my %q;
    my $scheme          = delete $config{scheme}            // 'memcache';
    my $host            = delete $config{host}              // '127.0.0.1';
    my $port            = delete $config{port}              // '11211';
    my $read_timeout    = delete $config{read_timeout};
    my $write_timeout   = delete $config{write_timeout};
    $q{connect_timeout} = delete $config{connect_timeout}   if defined $config{connect_timeout};
    $q{protocol}        = delete $config{protocol}          if defined $config{protocol};
    $q{tcp_nodelay}     = delete $config{tcp_nodelay}       if defined $config{tcp_nodelay};
    $q{timeout}         = delete $config{timeout}           if defined $config{timeout};
    $q{verify_mode}     = delete $config{verify_mode}       if defined $config{verify_mode};

    require URI::Escape;

    croak("Unknown options: @{[ sort keys %config ]}") if %config;
    # host may need to be escaped if it is a IPv6 address
    my $url = "$scheme://@{[ URI::Escape::uri_escape($host) ]}:$port";

    if(%q)
    {
      # In theory none of the query parameters should have characters that need to be
      # escaped, but since we have to pull in uri_escape for the hostname, we may as
      # well escape these too.
      $url .= "?" . join '&', map { join '=', $_, URI::Escape::uri_escape($q{$_}) } sort keys %q;
    }

    ($url, $read_timeout, $write_timeout);
  }

  $ffi->attach( new => ['string'] => 'u64' => sub ($xsub, $class, $url) {

    my $read_timeout;
    my $write_timeout;

    ($url, $read_timeout, $write_timeout) = _hash_to_url(%$url)
      if is_plain_hashref $url;

    my $index = $xsub->($url);
    my $self = bless \$index, $class;

    $self->set_read_timeout($read_timeout) if defined $read_timeout;
    $self->set_write_timeout($write_timeout) if defined $write_timeout;

    $self;
  });

  $ffi->attach( _rate_limit       => ['rl','string','u32','u32','u32'] => 'i32' );
  $ffi->attach( _error            => ['rl'] => 'string'                         );
  $ffi->attach( set_read_timeout  => ['rl', 'f64']                              );
  $ffi->attach( set_write_timeout => ['rl', 'f64']                              );

  $ffi->attach( DESTROY => ['rl'] => sub ($xsub, $self) {
    delete $keep{$$self};
  });

  sub error_handler ($self, $sub)
  {
    $keep{$$self} = $sub;
  }

  sub rate_limit ($self, $name, $size, $rate_max, $rate_seconds)
  {
    my $ret = _rate_limit($self, $name, $size, $rate_max, $rate_seconds);
    if($ret == -1)
    {
      $keep{$$self}->($self, $self->_error) if defined $keep{$$self};
      # fail open
      return 0;
    }
    else
    {
      return $ret;
    }
  }


}

1;

=head1 SYNOPSIS

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

=head1 DESCRIPTION

This module implements rate limiting logic.  It is intended for high
volume websites that require limits on the access or modification to
resources.  It is implemented using Rust and L<FFI::Platypus>, so you
will need the rust toolchain in order to install this module.

Why Rust?  Well none of the Perl Memcache clients I found supported
TLS, and the Rust L<memcache crate|https://crates.io/crates/memcache>
did.  Also Rust is fast and has a number of safety checks that give
me confidence that it won't crash our app.

The actual algorithm is based one used by Bugzilla, and by default
it will "fail open", meaning if for some reason the client cannot
connect to the Memcached server, it will B<allow> the request.

=head1 CONSTRUCTOR

=head2 new

 my $rl = Memcached::RateLimit->new($url);
 my $rl = Memcached::RateLimit->new(\%config);

Create a new instance of L<Memcached::RateLimit>.  The URL should be of the
form shown in the synopsis above.

The following schemes are supported:

=over 4

=item C<memcache>

=item C<memcache+tcp>

=item C<memcache+tls>

=item C<memcache+udp>

=item C<memcache+unix>

=back

You can append these query parameters
to the URL:

=over 4

=item C<connect_timeout>

B<Experimental>: Connect timeout in seconds.  May be specified as a
floating point, that is C<0.2> is 20 milliseconds.

=item C<protocol>

If set to C<ascii> this will use the ASCII protocol instead of binary.

=item C<tcp_nodelay>

Boolean C<true> or C<false>.

=item C<timeout>

IO timeout in seconds.

B<Experimental>: May be specified as a 
floating point, that is C<0.2> is 20 milliseconds.

=item C<verify_mode>

For TLS, this can be set to C<none> or C<peer>.

=back

[version 0.03]

You can provide a C<%Config> hash instead of a URL.  All of the
query parameters mentioned above can be provided in addition to
these:

=over 4

=item C<scheme>

The scheme (example: C<memcache> or C<memcache+tls>).

=item C<host>

The server hostname or IPv4/IPv6 address.

=item C<port>

The TCP or UDP port to connect to.

=item C<read_timeout>

The read timeout in seconds.  May be specified as a
floating point, that is C<0.2> is 20 milliseconds.

=item C<write_timeout>

The write timeout in seconds.  May be specified as a
floating point, that is C<0.2> is 20 milliseconds.

=back

=head1 METHODS

=head2 rate_limit

 my $limited = $rl->rate_limt($name, $size, $rate_max, $rate_seconds);

This method returns a boolean true, if a request of C<$size> exceeds the
rate limit of C<$rate_max> over the past C<$rate_seconds>.  If you only
want to rate limit the number of requests then you can set C<$size> to 1.

This method will return a boolean false, and increment the appropriate
counters if the requests fits within the rate limit.

This method will B<also> return boolean false, if it is unable to connect
to or otherwise experiences an error talking to the memcached server.
In this case it will also call the L<error handler|/error_handler>.

=head2 set_read_timeout

 $rl->set_read_timeout($secs);

Sets the IO Read timeout to C<$secs>, may be fractional.

=head2 set_write_timeout

 $rl->set_write_timeout($secs);

Sets the IO Write timeout to C<$secs>, may be fractional.

=head2 error_handler

 $rl->error_handler(sub ($rl, $message) {
   ...
 });

This method will set the error handler, to be called in the case of an
error with the memcached server.  It will pass in the instance of
L<Memcached::RateLimit> as C<$rl> and a diagnostic as C<$message>.
Since this module will fail open, it is probably useful to increment
error counters and provide diagnostics with this method to your monitoring
system.

=head1 SEE ALSO

=over 4

=item L<Cache::Memcached::Fast>

=item L<Redis::RateLimit>

=back

=cut
