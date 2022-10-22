use warnings;
use 5.020;
use experimental qw( postderef signatures );

package Memcached::RateLimit {

  # ABSTRACT: Sliding window rate limiting with Memcached

  use FFI::Platypus 2.00;

  my $ffi = FFI::Platypus->new( api => 2, lang => 'Rust' );
  $ffi->bundle;
  $ffi->mangler(sub ($name) { "rl_$name" });
  $ffi->type("object(@{[ __PACKAGE__ ]})" => 'rl');
  our %keep;

  $ffi->attach( new => ['string'] => 'u64' => sub ($xsub, $class, $url) {
    my $index = $xsub->($url);
    bless \$index, $class;
  });

  $ffi->attach( _rate_limit => ['rl','string','u32','u32','u32'] => 'i32' );
  $ffi->attach( _error => ['rl'] => 'string' );

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

Create a new instance of L<Memcached::RateLimit>.  The URL should be of the
form shown in the L<synopsis/SYNOPSIS> above.

=head1 METHODS

=head2 rate_limit

 $rl->rate_limt($name, $size, $rate_max, $rate_seconds);

=head2 error_handler

 $rl->error_handler(sub ($rl, $message) {
   ...
 });

=head1 SEE ALSO

=over 4

=item L<Cache::Memcached::Fast>

=item L<Redis::RateLimit>

=back

=cut
