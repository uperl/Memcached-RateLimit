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

  $ffi->attach( DESTROY => ['rl']);

}

1;
