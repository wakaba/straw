use strict;
use warnings;
use utf8;
use Encode;
use Path::Tiny;
use JSON::PS;

my $root_path = path (__FILE__)->parent->parent;

my $cert_path = $root_path->child ('local/cleardb.pem')->absolute;
if ($ENV{CLEARDB_CERT_URL}) {
  (system "curl", "-o", $cert_path, $ENV{CLEARDB_CERT_URL}) == 0 or die $?;
} else {
  $cert_path->spew ($ENV{CLEARDB_CERT});
}

$ENV{CLEARDB_DATABASE_URL} =~ m{^mysql://([^#?/\@:]*):([^#?/\@]*)\@([^#?/:]+)/([^#?]+)\?}
    or die "Bad |CLEARDB_DATABASE_URL| ($ENV{CLEARDB_DATABASE_URL})";

my $dsn = "dbi:mysql:host=$3;dbname=$4;user=$1;password=$2;mysql_ssl=1;mysql_ssl_ca_file=$cert_path";

my $Config = {
  ikachan_prefix => $ENV{IKACHAN_PREFIX},
  ikachan_channel => $ENV{IKACHAN_CHANNEL},
  alt_dsns => {master => {straw => $dsn}},
  dsns => {straw => $dsn},
  api_key => $ENV{APP_API_KEY},
};

my $config_path = $root_path->child ('local/config.json');
$config_path->spew (perl2json_bytes $Config);
