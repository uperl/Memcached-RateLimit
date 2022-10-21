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

=head1 DESCRIPTION

=head1 CONSTRUCTOR

=head2 new

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
