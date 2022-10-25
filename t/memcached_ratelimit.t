use Test2::V0 -no_srand => 1;
use Test2::Tools::Subtest qw( subtest_streamed );
use experimental qw( signatures );
use Time::HiRes qw( time );
use Memcached::RateLimit;
use YAML ();

subtest_streamed 'basic create without use' => sub {

  my $rl = Memcached::RateLimit->new("memcache://127.0.0.1:12345?timeout=10&tcp_nodelay=true");
  isa_ok $rl, 'Memcached::RateLimit';

  note YAML::Dump($rl);

  # this should destroy
  undef $rl;

};

sub time_it :prototype(&) {
  my $code = shift;
  my $start = time;
  $code->();
  note "clocking in at: @{[ time - $start ]}s";
}

my %name = (
  simple => 'MEMCACHED_RATELIMIT_TEST',
  tls    => 'MEMCACHED_RATELIMIT_TLS_TEST',
);

my %scheme = (
  simple => 'memcache+tcp',
  tls    => 'memcache+tls',
);

subtest_streamed 'live tests' => sub {

  foreach my $name (sort keys %name) {

    subtest_streamed $name => sub {

      skip_all "Set $name{$name} to run tests"
        unless defined $ENV{$name{$name}};

      my($host, $port) = split /:/, $ENV{$name{$name}};
      $host ||= '127.0.0.1';
      $port ||= 11211;

      # note: connect_timeout not yet recognized, but hopefully will be soon
      my $url = "$scheme{$name}://$host:$port?timeout=5.5&connect_timeout=5.5";
      $url .= "&verify_mode=none" if $name eq 'tls';
      note "using $url";

      my $rl = Memcached::RateLimit->new($url);
      isa_ok $rl, 'Memcached::RateLimit';

      note YAML::Dump($rl);

      my @error;

      $rl->error_handler(sub ($rl,$message) {
        push @error, $message;
        note "error:$message";
      });

      time_it {
        is(
          $rl->rate_limit("frooble-$$", 1, 20, 60),
          0,
          '$rl->rate_limit("frooble-$$", 1, 20, 60) = 0');
      };

      time_it {
        is(
          $rl->rate_limit("frooble-$$", 19, 20, 60),
          0,
          '$rl->rate_limit("frooble-$$", 19, 20, 60) = 0');
      };

      time_it {
        is(
          $rl->rate_limit("frooble-$$", 1, 20, 60),
          1,
          '$rl->rate_limit("frooble-$$", 1, 20, 60) = 1');
      };

      is \@error, [], 'no errors';

      # this should destroy
      undef $rl;

    };
  }
};

subtest_streamed 'hash config' => sub {

  is
    [Memcached::RateLimit::_hash_to_url()],
    ["memcache://127.0.0.1:11211", undef, undef],
    'default';

  is
    [Memcached::RateLimit::_hash_to_url(
       scheme          => 'memcache+tls',
       read_timeout    => 0.4,
       write_timeout   => 0.5,
       host            => '1.2.3.4',
       port            => 12345,
       connect_timeout => 0.2,
       protocol        =>'ascii',
       timeout         => 0.3,
       verify_mode     => 'none' )],
    ['memcache+tls://1.2.3.4:12345?connect_timeout=0.2&protocol=ascii&timeout=0.3&verify_mode=none',0.4,0.5],
    'the works';

  is
    [Memcached::RateLimit::_hash_to_url( host => '::1')],
    ['memcache://%3A%3A1:11211', undef, undef],
    'IPv6';

  is
    dies { Memcached::RateLimit::_hash_to_url( x => 'y', z => 1, ) },
    match qr/Unknown options: x z/,
    'error on invalid arg';
};

subtest_streamed 'counterfit object!' => sub {

  my $rl = bless \do { my $x = 42}, 'Memcached::RateLimit';
  isa_ok $rl, 'Memcached::RateLimit';

  note YAML::Dump($rl);

  my @error;

  $rl->error_handler(sub ($rl,$message) {
    push @error, $message;
    note "error:$message";
  });

  is(
    $rl->rate_limit("frooble-$$", 1, 20, 60),
    0,
    '$rl->rate_limit("frooble-$$", 1, 20, 60) = 0');

  is
    \@error,
    ["Invalid object index"],
    "expected error";

  undef $rl;
};

done_testing;
