use Test2::V0 -no_srand => 1;
use experimental qw( signatures );
use Memcached::RateLimit;
use YAML ();

subtest 'basic create without use' => sub {

  my $rl = Memcached::RateLimit->new("memcache://127.0.0.1:12345?timeout=10&tcp_nodelay=true");
  isa_ok $rl, 'Memcached::RateLimit';

  note YAML::Dump($rl);

  # this should destroy
  undef $rl;

};

subtest 'unencrypted' => sub {

  my $rl = Memcached::RateLimit->new("memcache://127.0.0.1:11211");
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

  is(
    $rl->rate_limit("frooble-$$", 19, 20, 60),
    0,
    '$rl->rate_limit("frooble-$$", 19, 20, 60) = 0');

  is(
    $rl->rate_limit("frooble-$$", 1, 20, 60),
    1,
    '$rl->rate_limit("frooble-$$", 1, 20, 60) = 1');

  is \@error, [], 'no errors';

  # this should destroy
  undef $rl;

};

done_testing;
