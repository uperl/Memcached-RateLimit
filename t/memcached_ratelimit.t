use Test2::V0 -no_srand => 1;
use Memcached::RateLimit;
use YAML ();

subtest 'basic create without use' => sub {

  my $rl = Memcached::RateLimit->new("memcache://127.0.0.1:12345?timeout=10&tcp_nodelay=true");
  isa_ok $rl, 'Memcached::RateLimit';

  note YAML::Dump($rl);

  # this should destroy
  undef $rl;

};

done_testing;


