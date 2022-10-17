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

  $ffi->attach( new => ['string'] => 'u64' => sub ($xsub, $class, $url) {
    my $index = $xsub->($url);
    bless \$index, $class;
  });

  $ffi->attach( rate_limit => ['rl','string','u32','u32','u32'] => 'i32' );
  $ffi->attach( DESTROY    => ['rl']);

}

1;

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 CONSTRUCTOR

=head2 new

=head1 METHODS

=head2 rate_limit

=head1 SEE ALSO

=over 4

=item L<Cache::Memcached::Fast>

=item L<Redis::RateLimit>

=back

=cut
